#!/usr/bin/env bash
# butin critical-path battery v2 — uses REAL transcript fixtures (message.model
# + message.usage) and a real SubagentStop payload (agent_type +
# agent_transcript_path), so a regression of C1/C2/H8/H10/C3/C7 FAILS here.
export LC_ALL=C
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ok  $1"; PASS=$((PASS+1)); }
ko(){ echo "  KO  $1"; FAIL=$((FAIL+1)); }

AMIRAL_HOME="$(mktemp -d)"; export AMIRAL_HOME
CFG="$(mktemp -d)"; cp "$HERE/lib/butin/pricing.tsv" "$CFG/"; export CLAUDE_CONFIG_DIR="$CFG"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$AMIRAL_HOME/butin-config.json"
PL=$(sed "s|TRANSCRIPT_PATH|$HERE/tests/fixtures/subagent-transcript.jsonl|" "$HERE/tests/fixtures/subagent-payload.json")

# C1 — real agent name, not "worker"
echo "$PL" | bash "$HERE/adapters/claude-code/butin-collect.sh"
L=$(grep -v superseded_marker "$AMIRAL_HOME/butin.jsonl" | tail -1)
echo "$L" | grep -q '"agent":"grunt"' && ok "C1 agent=grunt (not worker)" || ko "C1: $(echo "$L"|grep -oE '\"agent\":\"[^\"]*\"')"
# C2 — worker's model, not the brain's
echo "$L" | grep -q '"chosen_model":"claude-sonnet-5"' && ok "C2 model=sonnet-5 (worker, not brain)" || ko "C2"
# H10 — sum of ALL turns (8000, not the last 3000)
echo "$L" | grep -q '"in":8000' && ok "H10 in=8000 (all turns summed)" || ko "H10 in=$(echo "$L"|grep -oE '\"in\":[0-9]+')"
echo "$L" | grep -q '"cache_read":12000' && ok "H10 cache_read=12000" || ko "H10 cr"

# C3 — scientific notation parsed
printf '{"v":1,"id":"s","agent":"grunt","real_cost_usd":1.5e-2,"counterfactual_cost_usd":5e-2,"outcome":"ok"}\n' > "$AMIRAL_HOME/c3.jsonl"
NET=$(awk -f "$HERE/lib/butin/core.awk" "$AMIRAL_HOME/c3.jsonl" | awk -F'\t' '/^NET/{print $2}')
awk "BEGIN{exit !($NET>0.03 && $NET<0.04)}" && ok "C3 exponent (1.5e-2=0.015, net=$NET)" || ko "C3 net=$NET"

# C7 — merged line (missing newline) counted BAD, never silent
printf '%s' '{"v":1,"id":"a","agent":"grunt","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}' > "$AMIRAL_HOME/c7.jsonl"
printf '%s\n' '{"v":1,"id":"b","agent":"grunt","real_cost_usd":5.00,"counterfactual_cost_usd":9.00,"outcome":"ok"}' >> "$AMIRAL_HOME/c7.jsonl"
awk -f "$HERE/lib/butin/core.awk" "$AMIRAL_HOME/c7.jsonl" | grep -q BAD_LINES && ok "C7 merged line = BAD (no silent swallow)" || ko "C7"

# H8 — failed cheap route is a LOSS, never a fabricated profit
cat > "$AMIRAL_HOME/h8.jsonl" << 'EOF'
{"v":1,"id":"e1","agent":"grunt","chosen_model":"claude-haiku-4-5","real_cost_usd":0.01,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.04,"outcome":"superseded"}
{"v":1,"id":"sup","supersedes":"e1","outcome":"superseded_marker"}
{"v":1,"id":"e2","agent":"grunt","chosen_model":"claude-sonnet-4-6","real_cost_usd":0.05,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.05,"outcome":"escalated","escalation_extra_usd":0.01}
EOF
NET=$(awk -f "$HERE/lib/butin/core.awk" "$AMIRAL_HOME/h8.jsonl" | awk -F'\t' '/^NET/{print $2}')
awk "BEGIN{exit !($NET<0 && $NET>-0.02)}" && ok "H8 failed route = loss ($NET, not profit)" || ko "H8 net=$NET"

# C4 — corrupt state file (non-numeric epoch) must not crash/lose the event
printf 'grunt\tm\t0.01\tNOTANUMBER\t0.001\t0.01\tid\n' > "$AMIRAL_HOME/state/last-S2"
mkdir -p "$AMIRAL_HOME/state"
echo "{\"session_id\":\"S2\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$HERE/tests/fixtures/subagent-transcript.jsonl\"}" | bash "$HERE/adapters/claude-code/butin-collect.sh" 2>/dev/null
[ -f "$AMIRAL_HOME/butin.jsonl" ] && ok "C4 corrupt state didn't crash the collector" || ko "C4 event lost"

# brain premium still a penalty (regression guard, N3)
printf '{"v":1,"id":"b","agent":"brain","chosen_model":"claude-haiku-4-5","real_cost_usd":0.01,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.05,"outcome":"ok"}\n' > "$AMIRAL_HOME/bp.jsonl"
N=$(awk -f "$HERE/lib/butin/core.awk" "$AMIRAL_HOME/bp.jsonl" | awk -F'\t' '/^NET/{print $2}')
awk "BEGIN{exit !($N==0 || $N==0.0)}" && ok "N3 cheap brain earns no credit (net=$N)" || ko "N3 net=$N"


# ─── v0.12 cold-measurement battery ───
T=$(mktemp -d); mkdir -p "$T/s/subagents"
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"
echo '{"agentType":"corsaire","spawnDepth":1}' > "$T/s/subagents/agent-x.meta.json"
cat > "$T/s/subagents/agent-x.jsonl" << 'TX'
{"message":{"id":"m1","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}
{"message":{"id":"m1","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":500,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}
{"message":{"id":"m2","model":"claude-sonnet-5","usage":{"input_tokens":50,"output_tokens":250,"cache_read_input_tokens":2000,"cache_creation_input_tokens":0}}}
TX
A2="$(mktemp -d)"; printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$A2/butin-config.json"
echo "{\"session_id\":\"S\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$T/s/subagents/agent-x.jsonl\"}" \
  | AMIRAL_HOME="$A2" bash "$HERE/adapters/claude-code/butin-receipt.sh"
AMIRAL_HOME="$A2" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
E=$(cat "$A2/butin.jsonl" 2>/dev/null)
echo "$E" | grep -q '"out": 750' && ok "V12 dedup by message.id (out=750, not 800 naive)" || ko "V12 dedup: $(echo "$E"|grep -o '\"out\": [0-9]*')"
echo "$E" | grep -q '"agent": "corsaire"' && ok "V12 identity from .meta.json sidecar (not the hint)" || ko "V12 identity"
echo "{\"session_id\":\"S\",\"agent_type\":\"reviewer\",\"agent_transcript_path\":\"$T/s/subagents/agent-NOTYET.jsonl\"}" \
  | AMIRAL_HOME="$A2" bash "$HERE/adapters/claude-code/butin-receipt.sh"
AMIRAL_HOME="$A2" python3 "$HERE/lib/butin/measure.py" 2>/dev/null | grep -q "pending 1" && ok "V12 missing transcript stays PENDING (never invented)" || ko "V12 pending"
AMIRAL_HOME="$A2" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
N=$(grep -c '"real_cost_usd"' "$A2/butin.jsonl")
[ "$N" = "1" ] && ok "V12 idempotent (re-run doesn't double-count)" || ko "V12 idempotent: $N events"


# ─── v0.12.2 brain dedup: Stop fires per turn, same session = one event ───
Tb=$(mktemp -d); Ab=$(mktemp -d)
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Ab/butin-config.json"
printf '{"message":{"id":"bb","model":"claude-fable-5","usage":{"input_tokens":33,"output_tokens":1000,"cache_read_input_tokens":5000,"cache_creation_input_tokens":0}}}\n' > "$Tb/main.jsonl"
for i in 1 2 3; do
  echo "{\"session_id\":\"SS\",\"transcript_path\":\"$Tb/main.jsonl\"}" | AMIRAL_HOME="$Ab" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
done
AMIRAL_HOME="$Ab" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
BC=$(grep -c '"agent": "brain"' "$Ab/butin.jsonl" 2>/dev/null || echo 0)
[ "$BC" = "1" ] && ok "V12.2 brain deduped per session (3 Stop receipts -> 1 event)" || ko "V12.2 brain: $BC events"


# ─── v0.13.0 config subcommand: live re-baseline / re-mode, validated ───
AC="$(mktemp -d)"; cp "$HERE/lib/butin/pricing.tsv" "$AC/"

# T-C1 roundtrip: baseline+mode set together, --show reflects both, JSON parses
AH1="$(mktemp -d)"
AMIRAL_HOME="$AH1" CLAUDE_CONFIG_DIR="$AC" bash "$HERE/bin/amiral-butin" config --baseline claude-opus-4-8 --mode plan >/dev/null
SHOW1=$(AMIRAL_HOME="$AH1" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin" config --show)
if echo "$SHOW1" | grep -q "claude-opus-4-8" && echo "$SHOW1" | grep -q "plan" && echo "$SHOW1" | grep -q "manual (config)" \
   && python3 -c "import json; json.load(open('$AH1/butin-config.json'))" 2>/dev/null; then
  ok "T-C1 roundtrip: --show reflects baseline+mode+source, JSON parses"
else
  ko "T-C1 show=[$SHOW1]"
fi

# T-C2 rejection: unknown baseline writes nothing, no tmp residue
AH2="$(mktemp -d)"
printf '{ "baseline_model": "claude-sonnet-4-6", "baseline_source": "test", "mode": "api" }\n' > "$AH2/butin-config.json"
cp "$AH2/butin-config.json" "$AH2/butin-config.json.snapshot"
AMIRAL_HOME="$AH2" CLAUDE_CONFIG_DIR="$AC" bash "$HERE/bin/amiral-butin" config --baseline not-a-model >/dev/null 2>&1
RC2=$?
if [ "$RC2" != "0" ] && cmp -s "$AH2/butin-config.json" "$AH2/butin-config.json.snapshot" && [ -z "$(ls "$AH2"/butin-config.json.tmp.* 2>/dev/null)" ]; then
  ok "T-C2 unknown baseline rejected: rc!=0, config byte-identical, no tmp residue"
else
  ko "T-C2 rc=$RC2"
fi

# T-C3 future-only: re-baseline mid-session never re-prices stored history
AH3="$(mktemp -d)"
printf '{ "baseline_model": "claude-sonnet-4-6", "baseline_source": "test", "mode": "api" }\n' > "$AH3/butin-config.json"
PL3=$(sed "s|TRANSCRIPT_PATH|$HERE/tests/fixtures/subagent-transcript.jsonl|" "$HERE/tests/fixtures/subagent-payload.json")
echo "$PL3" | AMIRAL_HOME="$AH3" CLAUDE_CONFIG_DIR="$AC" bash "$HERE/adapters/claude-code/butin-collect.sh"
LA=$(grep -v superseded_marker "$AH3/butin.jsonl" | tail -1)
IDA=$(echo "$LA" | grep -oE '"id"[ ]*:[ ]*"[^"]*"' | head -1)
CFA=$(echo "$LA" | grep -oE '"counterfactual_cost_usd"[ ]*:[ ]*[0-9.eE+-]+' | sed 's/.*://')
AMIRAL_HOME="$AH3" CLAUDE_CONFIG_DIR="$AC" bash "$HERE/bin/amiral-butin" config --baseline claude-opus-4-8 >/dev/null
echo "$PL3" | AMIRAL_HOME="$AH3" CLAUDE_CONFIG_DIR="$AC" bash "$HERE/adapters/claude-code/butin-collect.sh"
LA2=$(grep -v superseded_marker "$AH3/butin.jsonl" | grep -F "$IDA")
LB=$(grep -v superseded_marker "$AH3/butin.jsonl" | tail -1)
CFB=$(echo "$LB" | grep -oE '"counterfactual_cost_usd"[ ]*:[ ]*[0-9.eE+-]+' | sed 's/.*://')
if [ "$LA2" = "$LA" ] && echo "$LA" | grep -q '"baseline_model":"claude-sonnet-4-6"' \
   && echo "$LB" | grep -q '"baseline_model":"claude-opus-4-8"' \
   && [ -n "$CFA" ] && [ -n "$CFB" ] && [ "$CFA" != "$CFB" ]; then
  ok "T-C3 future-only: A's stored line unchanged (sonnet-4-6, cf=$CFA), B carries opus-4-8 (cf=$CFB)"
else
  ko "T-C3 A=[$LA] A_after=[$LA2] B=[$LB]"
fi

# T-C4 mode flip is live: next report call reflects it, no restart needed
AH4="$(mktemp -d)"
printf '{"v":1,"id":"c4","agent":"grunt","chosen_model":"claude-haiku-4-5","real_cost_usd":0.01,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.05,"outcome":"ok"}\n' > "$AH4/butin.jsonl"
AMIRAL_HOME="$AH4" CLAUDE_CONFIG_DIR="$AC" bash "$HERE/bin/amiral-butin" config --mode plan >/dev/null
OUT4=$(AMIRAL_HOME="$AH4" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
echo "$OUT4" | grep -q "premium tokens avoided" && ok "T-C4 mode flip live: report hero shows premium tokens avoided" || ko "T-C4: $(echo "$OUT4" | grep -i "period\|premium\|net saved")"

# T-C5 --detail regression: no unbound-variable crash, new honesty bullet present
AH5="$(mktemp -d)"
printf '{"v":1,"id":"c5","agent":"grunt","chosen_model":"claude-haiku-4-5","real_cost_usd":0.01,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.05,"outcome":"ok"}\n' > "$AH5/butin.jsonl"
ERR5="$(mktemp)"
OUT5=$(AMIRAL_HOME="$AH5" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin" --detail 2>"$ERR5")
RC5=$?
if [ "$RC5" = "0" ] && echo "$OUT5" | grep -q "Honesty:" && echo "$OUT5" | grep -q "FUTURE events only" && ! grep -qi "unbound variable" "$ERR5"; then
  ok "T-C5 --detail: rc0, Honesty + FUTURE events only present, no unbound-variable crash"
else
  ko "T-C5 rc=$RC5 stderr=$(cat "$ERR5")"
fi
rm -f "$ERR5"

# T-C6 escalation marker carries a ts (v0.13): a ts-less marker is invisible
# to date-sliced passes (statusline today-cache) — an escalation day would
# render as a fabricated positive. Drive the REAL collector escalation path:
# fabricated session state = a cheap grunt attempt seconds ago, then the
# pricier fixture (sonnet-5) in the same session -> escalated + marker.
AH6="$(mktemp -d)"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$AH6/butin-config.json"
mkdir -p "$AH6/state"
printf 'grunt\tclaude-haiku-4-5\t0.001\t%s\t0.000004\t0.005\te1id\n' "$(date +%s)" > "$AH6/state/last-S6"
PL6=$(sed "s|TRANSCRIPT_PATH|$HERE/tests/fixtures/subagent-transcript.jsonl|;s|\"session_id\"[ ]*:[ ]*\"[^\"]*\"|\"session_id\":\"S6\"|" "$HERE/tests/fixtures/subagent-payload.json")
echo "$PL6" | AMIRAL_HOME="$AH6" CLAUDE_CONFIG_DIR="$AC" bash "$HERE/adapters/claude-code/butin-collect.sh"
MARK6=$(grep 'superseded_marker' "$AH6/butin.jsonl" | tail -1)
if [ -n "$MARK6" ] && echo "$MARK6" | grep -qE '"ts"[ ]*:[ ]*"[0-9]{4}-' \
   && grep -q '"outcome":"escalated"' "$AH6/butin.jsonl"; then
  ok "T-C6 collector stamps ts on the supersede marker (date-sliced passes see it)"
else
  ko "T-C6 marker=[$MARK6]"
fi

# T-C7 report survives a present-but-drained receipts.jsonl (grep -c under
# pipefail prints "0" AND exits 1 -> the old `|| echo 0` appended a second
# "0" line and crashed the coverage arithmetic; routine state once cache.sh
# measures receipts continuously).
AH7="$(mktemp -d)"
printf '{"v":1,"id":"c7r","agent":"grunt","chosen_model":"claude-haiku-4-5","real_cost_usd":0.01,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.05,"outcome":"ok"}\n' > "$AH7/butin.jsonl"
: > "$AH7/receipts.jsonl"
ERR7="$(mktemp)"
OUT7=$(AMIRAL_HOME="$AH7" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin" 2>"$ERR7"); RC7=$?
if [ "$RC7" = "0" ] && echo "$OUT7" | grep -q "Coverage: 1/1" && ! grep -q "syntax error\|unbound variable" "$ERR7"; then
  ok "T-C7 empty receipts.jsonl: report rc0, coverage intact (no pipefail double-zero crash)"
else
  ko "T-C7 rc=$RC7 stderr=$(cat "$ERR7") cov=[$(echo "$OUT7" | grep Coverage)]"
fi
rm -f "$ERR7"


# ─── v0.13.1 receipt TTL: absent transcript ages out, never invented ───
# Claude Code gc's ~/.claude/projects/<proj>/<session>/subagents/agent-*.jsonl
# after some days. A receipt pointing at a transcript that is GONE (not just
# unparseable) must not stay "pending" forever — past BUTIN_RECEIPT_TTL_HOURS
# (default 48) it becomes unmeasurable with an honest reason, once, and is
# drained from receipts.jsonl.
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"

# TTL-1 expired: transcript absent, receipt older than default TTL (48h)
AT1="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT1/butin-config.json"
TS49=$(date -u -v-49H +%FT%TZ 2>/dev/null || date -u -d '49 hours ago' +%FT%TZ)
printf '{"v":2,"id":"ttlX","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/agent-gone.jsonl","cwd":"/x","measured":false}\n' "$TS49" > "$AT1/receipts.jsonl"
OUT1=$(AMIRAL_HOME="$AT1" python3 "$HERE/lib/butin/measure.py")
if grep -q "transcript no longer on disk" "$AT1/butin.jsonl" 2>/dev/null \
   && grep -q '"receipt": "ttlX"' "$AT1/butin.jsonl" 2>/dev/null \
   && ! grep -q "ttlX" "$AT1/receipts.jsonl" 2>/dev/null \
   && echo "$OUT1" | grep -q "unmeasurable 1" \
   && echo "$OUT1" | grep -q "pending 0"; then
  ok "TTL-1 receipt older than TTL (49h>48h), transcript absent -> unmeasurable, drained"
else
  ko "TTL-1 out=[$OUT1] events=[$(cat "$AT1/butin.jsonl" 2>/dev/null)] receipts=[$(cat "$AT1/receipts.jsonl" 2>/dev/null)]"
fi

# TTL-2 young: same shape but ts=now -> stays pending, no unmeasurable event
AT2="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT2/butin-config.json"
TSNOW=$(date -u +%FT%TZ)
printf '{"v":2,"id":"ttlY","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/agent-gone.jsonl","cwd":"/x","measured":false}\n' "$TSNOW" > "$AT2/receipts.jsonl"
OUT2=$(AMIRAL_HOME="$AT2" python3 "$HERE/lib/butin/measure.py")
if grep -q "ttlY" "$AT2/receipts.jsonl" 2>/dev/null \
   && grep -q '"measured":false' "$AT2/receipts.jsonl" 2>/dev/null \
   && ! grep -q "transcript no longer on disk" "$AT2/butin.jsonl" 2>/dev/null \
   && echo "$OUT2" | grep -q "pending 1"; then
  ok "TTL-2 fresh receipt (transcript absent, age<TTL) stays pending, no unmeasurable event"
else
  ko "TTL-2 out=[$OUT2] events=[$(cat "$AT2/butin.jsonl" 2>/dev/null)] receipts=[$(cat "$AT2/receipts.jsonl" 2>/dev/null)]"
fi

# TTL-3 idempotence: re-run measure.py on AT1 -> exactly ONE event for ttlX
AMIRAL_HOME="$AT1" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
NTTL=$(grep -c "transcript no longer on disk" "$AT1/butin.jsonl" 2>/dev/null)
[ "$NTTL" = "1" ] && ok "TTL-3 idempotent: re-run doesn't duplicate the unmeasurable event" || ko "TTL-3 count=$NTTL"

# TTL-4 knob: young-side receipt + BUTIN_RECEIPT_TTL_HOURS=0 -> expires immediately
AT4="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT4/butin-config.json"
printf '{"v":2,"id":"ttlZ","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/agent-gone.jsonl","cwd":"/x","measured":false}\n' "$TSNOW" > "$AT4/receipts.jsonl"
OUT4T=$(AMIRAL_HOME="$AT4" BUTIN_RECEIPT_TTL_HOURS=0 python3 "$HERE/lib/butin/measure.py")
if grep -q "transcript no longer on disk" "$AT4/butin.jsonl" 2>/dev/null \
   && grep -q '"receipt": "ttlZ"' "$AT4/butin.jsonl" 2>/dev/null \
   && ! grep -q "ttlZ" "$AT4/receipts.jsonl" 2>/dev/null \
   && echo "$OUT4T" | grep -q "unmeasurable 1"; then
  ok "TTL-4 BUTIN_RECEIPT_TTL_HOURS=0 expires a fresh receipt immediately (knob works)"
else
  ko "TTL-4 out=[$OUT4T] events=[$(cat "$AT4/butin.jsonl" 2>/dev/null)]"
fi

# TTL-5 preserved: transcript EXISTS but is unparseable garbage -> stays pending
# regardless of age (the absent-vs-unparseable distinction must not blur)
AT5="$(mktemp -d)"; mkdir -p "$AT5/tx"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT5/butin-config.json"
GARBAGE="$AT5/tx/agent-garbage.jsonl"
printf 'not json at all\n{also not json}\n' > "$GARBAGE"
TS200=$(date -u -v-200H +%FT%TZ 2>/dev/null || date -u -d '200 hours ago' +%FT%TZ)
printf '{"v":2,"id":"ttlW","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"%s","cwd":"/x","measured":false}\n' "$TS200" "$GARBAGE" > "$AT5/receipts.jsonl"
OUT5T=$(AMIRAL_HOME="$AT5" python3 "$HERE/lib/butin/measure.py")
if grep -q "ttlW" "$AT5/receipts.jsonl" 2>/dev/null \
   && ! grep -q "transcript no longer on disk" "$AT5/butin.jsonl" 2>/dev/null \
   && echo "$OUT5T" | grep -q "pending 1"; then
  ok "TTL-5 existing-but-unparseable transcript stays pending regardless of age (200h old)"
else
  ko "TTL-5 out=[$OUT5T] events=[$(cat "$AT5/butin.jsonl" 2>/dev/null)] receipts=[$(cat "$AT5/receipts.jsonl" 2>/dev/null)]"
fi

# TTL-6 (review fix): an id-less receipt past the TTL must not crash the run —
# a KeyError on r["id"] would wedge EVERY receipt in the batch forever (and
# cache.sh swallows the rc, so the deadlock would be invisible). The id-less
# line stays pending (no event may be written for something un-dedupable);
# the healthy receipt in the same batch is still processed.
AT6="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT6/butin-config.json"
TS49B=$(date -u -v-49H +%FT%TZ 2>/dev/null || date -u -d '49 hours ago' +%FT%TZ)
printf '{"v":2,"ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/no-id.jsonl","cwd":"/x","measured":false}\n' "$TS49B" > "$AT6/receipts.jsonl"
printf '{"v":2,"id":"ttlG","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/good.jsonl","cwd":"/x","measured":false}\n' "$TS49B" >> "$AT6/receipts.jsonl"
OUT6T=$(AMIRAL_HOME="$AT6" python3 "$HERE/lib/butin/measure.py" 2>&1); RC6T=$?
if [ "$RC6T" = "0" ] && grep -q '"receipt": "ttlG"' "$AT6/butin.jsonl" 2>/dev/null \
   && grep -q "no-id" "$AT6/receipts.jsonl" 2>/dev/null \
   && ! grep -q "Traceback" <<< "$OUT6T" \
   && echo "$OUT6T" | grep -q "unmeasurable 1"; then
  ok "TTL-6 id-less receipt past TTL: rc0, no crash, healthy receipt still expires, id-less kept"
else
  ko "TTL-6 rc=$RC6T out=[$OUT6T] receipts=[$(cat "$AT6/receipts.jsonl" 2>/dev/null)]"
fi

# TTL-7 (review fix): BUTIN_RECEIPT_TTL_HOURS=nan must fall back to the
# documented 48h default (NaN comparisons are all False in Python — unguarded,
# "nan" silently meant "never expire"). A 49h-old absent-transcript receipt
# under TTL=nan must therefore expire exactly as under the default.
AT7="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT7/butin-config.json"
printf '{"v":2,"id":"ttlN","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/nan.jsonl","cwd":"/x","measured":false}\n' "$TS49B" > "$AT7/receipts.jsonl"
OUT7T=$(AMIRAL_HOME="$AT7" BUTIN_RECEIPT_TTL_HOURS=nan python3 "$HERE/lib/butin/measure.py")
if grep -q '"receipt": "ttlN"' "$AT7/butin.jsonl" 2>/dev/null \
   && echo "$OUT7T" | grep -q "unmeasurable 1"; then
  ok "TTL-7 TTL=nan falls back to the 48h default (49h-old receipt expires, not never)"
else
  ko "TTL-7 out=[$OUT7T] events=[$(cat "$AT7/butin.jsonl" 2>/dev/null)]"
fi


echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
