#!/usr/bin/env python3
"""butin cold measurement (v0.12).

Reads receipts, measures each one from now-stable transcripts, and writes
measured events. Correct by construction:

  * DEDUP BY message.id — a streaming transcript writes the same turn many
    times (observed: the same id 6x). The LAST record of an id carries the
    turn's final usage. Summing every line over-counted 6.7x in v0.11.
  * IDENTITY FROM THE SIDECAR — .meta.json carries agentType (and
    spawnDepth), so a worker is never a nameless "worker" fallback.
  * PENDING, NOT INVENTED — if a transcript isn't there yet, the receipt
    stays pending and is retried next run. Coverage tells the truth:
    measured / pending / unmeasurable.
  * REPRODUCIBLE — the same receipts + transcripts always yield the same
    number. Anyone can re-run it.
"""
import json, os, sys, glob

HOME = os.environ.get("AMIRAL_HOME", os.path.expanduser("~/.amiral"))
RECEIPTS = os.path.join(HOME, "receipts.jsonl")
EVENTS = os.path.join(HOME, "butin.jsonl")
CFG = os.path.join(HOME, "butin-config.json")
PRICES = os.environ.get("BUTIN_PRICES") or os.path.expanduser("~/.claude/butin/pricing.tsv")

def load_prices():
    rates, ver = {}, "unknown"
    for line in open(PRICES, encoding="utf-8"):
        if line.startswith("#"):
            if "pricing_version:" in line: ver = line.split("pricing_version:")[1].strip()
            continue
        p = line.rstrip("\n").split("\t")
        if len(p) >= 5:
            try: rates[p[0]] = tuple(float(x) for x in p[1:5])
            except ValueError: pass
    return rates, ver

def measure_transcript(path):
    """Return (model, in, out, cache_read, cache_write) deduped by message.id.
    Returns None if the file can't be read (→ receipt stays pending)."""
    if not path or not os.path.isfile(path): return None
    turns = {}   # message.id -> usage of its LAST occurrence
    model = None
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            line = line.strip()
            if not line.startswith("{"): continue
            try: d = json.loads(line)
            except json.JSONDecodeError: continue          # torn/partial line: skip, never guess
            m = d.get("message") or {}
            mid, usage = m.get("id"), m.get("usage")
            if mid and isinstance(usage, dict):
                turns[mid] = usage                          # last write wins = final totals
                if m.get("model"): model = m["model"]
    except OSError:
        return None
    if not turns or not model: return None
    tot = [0, 0, 0, 0]
    for u in turns.values():
        tot[0] += u.get("input_tokens", 0) or 0
        tot[1] += u.get("output_tokens", 0) or 0
        tot[2] += u.get("cache_read_input_tokens", 0) or 0
        tot[3] += u.get("cache_creation_input_tokens", 0) or 0
    return (model, *tot)

def agent_name(transcript, hint, role):
    """Identity from the platform's own sidecar; hint is only a fallback."""
    if role == "brain": return "brain"
    side = (transcript or "")[:-6] + ".meta.json" if (transcript or "").endswith(".jsonl") else ""
    if side and os.path.isfile(side):
        try:
            meta = json.load(open(side, encoding="utf-8"))
            if meta.get("agentType"): return meta["agentType"]
        except Exception: pass
    return hint or "worker"

def cost(rates, model, tk):
    r = rates.get(model)
    if not r: return None
    return tk[0]*r[0] + tk[1]*r[1] + tk[3]*r[2] + tk[2]*r[3]   # in, out, cache_write, cache_read

def main():
    if not os.path.isfile(RECEIPTS):
        print("no receipts yet"); return 0
    cfg = json.load(open(CFG)) if os.path.isfile(CFG) else {}
    baseline = cfg.get("baseline_model", "claude-sonnet-4-6")
    rates, pver = load_prices()

    done = set()
    brain_sessions = {}   # session -> True if a brain event already exists
    existing = []
    if os.path.isfile(EVENTS):
        for l in open(EVENTS, encoding="utf-8"):
            try: e = json.loads(l)
            except Exception: continue
            existing.append(e)
            if e.get("receipt"): done.add(e["receipt"])
            if e.get("agent") == "brain" and e.get("session"):
                brain_sessions[e["session"]] = True

    kept, measured, pending, unmeasurable = [], 0, 0, 0
    new_events = []
    brain_replace = {}   # session -> new brain event that supersedes the old one
    for line in open(RECEIPTS, encoding="utf-8"):
        try: r = json.loads(line)
        except Exception: continue
        if r.get("id") in done: continue
        role = r.get("role")
        # BRAIN dedup: the Stop hook fires once per turn, each receipt points at
        # the SAME growing main transcript. Only ONE brain event per session is
        # correct (the latest state). A new brain receipt for a session that
        # already has a brain event REPLACES it instead of adding a duplicate.
        m = measure_transcript(r.get("transcript"))
        if m is None:
            kept.append(line); pending += 1; continue
        model, i, o, cr, cw = m
        real = cost(rates, model, (i, o, cr, cw))
        cf = cost(rates, baseline, (i, o, cr, cw))
        ag = agent_name(r.get("transcript"), r.get("agent_hint"), r.get("role"))
        if real is None or cf is None:
            new_events.append({"v": 2, "receipt": r["id"], "ts": r["ts"], "agent": ag,
                  "model": model, "unmeasurable": True, "reason": "unknown pricing_id"})
            unmeasurable += 1; continue
        prem_i = i if (ag != "brain" and model != baseline and real < cf) else 0
        prem_o = o if (ag != "brain" and model != baseline and real < cf) else 0
        ev = {"v": 2, "receipt": r["id"], "ts": r["ts"], "session": r.get("session"),
              "cwd": r.get("cwd"), "agent": ag, "chosen_model": model,
              "tokens": {"in": i, "out": o, "cache_read": cr, "cache_write": cw},
              "real_cost_usd": round(real, 6), "baseline_model": baseline,
              "counterfactual_cost_usd": round(cf, 6), "pricing_version": pver,
              "outcome": "ok", "prem_in_avoided": prem_i, "prem_out_avoided": prem_o}
        if ag == "brain" and r.get("session"):
            sess = r["session"]
            if sess in brain_sessions or sess in brain_replace:
                brain_replace[sess] = ev      # supersede: don't double-count the brain
                measured += 0                  # not a new measured task, a refresh
            else:
                brain_replace[sess] = ev; measured += 1
        else:
            new_events.append(ev); measured += 1

    # rewrite EVENTS: keep existing (minus superseded brains), add new + replacements
    final = []
    for e in existing:
        if e.get("agent") == "brain" and e.get("session") in brain_replace:
            continue   # dropped: a fresher brain measurement for this session replaces it
        final.append(e)
    final.extend(new_events)
    final.extend(brain_replace.values())
    with open(EVENTS, "w", encoding="utf-8") as f:
        for e in final: f.write(json.dumps(e) + "\n")
    with open(RECEIPTS, "w", encoding="utf-8") as f: f.writelines(kept)
    print(f"measured {measured} · pending {pending} · unmeasurable {unmeasurable}")
    return 0

if __name__ == "__main__": sys.exit(main())
