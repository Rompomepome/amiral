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
# v0.16 UPDATE (source fix, see butin-receipt.sh header): a worker receipt
# whose NAMED transcript does not exist on disk at hook time is now SKIPPED
# at mint time (never appended to receipts.jsonl) rather than minted and
# left pending forever/until TTL — the v0.14 finding is that such a firing
# is a phantom (SubagentStop only fires for agents whose named transcript is
# never written), and a real worker transcript is always covered by the
# discovery scan instead. So this used to assert "pending 1"; it now
# asserts the opposite: no receipt at all, pending 0.
echo "{\"session_id\":\"S\",\"agent_type\":\"reviewer\",\"agent_transcript_path\":\"$T/s/subagents/agent-NOTYET.jsonl\"}" \
  | AMIRAL_HOME="$A2" bash "$HERE/adapters/claude-code/butin-receipt.sh"
if ! grep -q "agent-NOTYET" "$A2/receipts.jsonl" 2>/dev/null; then
  ok "V12 missing transcript at mint time is SKIPPED, not invented-then-pending (v0.16 source fix)"
else
  ko "V12 missing-transcript receipt=[$(cat "$A2/receipts.jsonl" 2>/dev/null)]"
fi
AMIRAL_HOME="$A2" python3 "$HERE/lib/butin/measure.py" 2>/dev/null | grep -q "pending 0" && ok "V12 no phantom pending from the skipped receipt" || ko "V12 pending should be 0"
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

# TTL-1 expired: transcript absent, receipt older than default TTL (48h).
# No "observed" field on this receipt (pre-v0.16.0 shape / never-observed) ->
# v0.16.0 PHANTOM/LOSS SPLIT classifies this as phantom (new wording, not the
# legacy exact string — that string is only ever read back from ALREADY
# emitted pre-v0.16.0 events, never written by measure.py again).
AT1="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT1/butin-config.json"
TS49=$(date -u -v-49H +%FT%TZ 2>/dev/null || date -u -d '49 hours ago' +%FT%TZ)
printf '{"v":2,"id":"ttlX","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/agent-gone.jsonl","cwd":"/x","measured":false}\n' "$TS49" > "$AT1/receipts.jsonl"
OUT1=$(AMIRAL_HOME="$AT1" python3 "$HERE/lib/butin/measure.py")
if grep -q "transcript never written (phantom" "$AT1/butin.jsonl" 2>/dev/null \
   && grep -q '"receipt": "ttlX"' "$AT1/butin.jsonl" 2>/dev/null \
   && ! grep -q "ttlX" "$AT1/receipts.jsonl" 2>/dev/null \
   && echo "$OUT1" | grep -q "unmeasurable 1" \
   && echo "$OUT1" | grep -q "pending 0"; then
  ok "TTL-1 receipt older than TTL (49h>48h), transcript absent (no observed field) -> phantom, drained"
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
NTTL=$(grep -c "transcript never written (phantom" "$AT1/butin.jsonl" 2>/dev/null)
[ "$NTTL" = "1" ] && ok "TTL-3 idempotent: re-run doesn't duplicate the unmeasurable event" || ko "TTL-3 count=$NTTL"

# TTL-4 knob: young-side receipt + BUTIN_RECEIPT_TTL_HOURS=0 -> expires immediately
AT4="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT4/butin-config.json"
printf '{"v":2,"id":"ttlZ","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/agent-gone.jsonl","cwd":"/x","measured":false}\n' "$TSNOW" > "$AT4/receipts.jsonl"
OUT4T=$(AMIRAL_HOME="$AT4" BUTIN_RECEIPT_TTL_HOURS=0 python3 "$HERE/lib/butin/measure.py")
if grep -q "transcript never written (phantom" "$AT4/butin.jsonl" 2>/dev/null \
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

# ─── v0.16.0 PHANTOM/LOSS SPLIT: the receipt's own "observed" field (set at
# mint time by butin-receipt.sh) decides whether an absent-transcript
# expiry is noise (never written) or a real loss (existed, then removed).
# ───

# TTL-8: "observed":true + transcript absent past TTL -> LOSS. reason
# contains "removed"; core.awk must count it UNMEASURED (stays IN the
# coverage denominator), NOT phantom.
AT8="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT8/butin-config.json"
printf '{"v":2,"id":"ttlLoss","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/agent-was-here.jsonl","cwd":"/x","measured":false,"observed":true}\n' "$TS49B" > "$AT8/receipts.jsonl"
OUT8T=$(AMIRAL_HOME="$AT8" python3 "$HERE/lib/butin/measure.py")
if grep -q '"reason": "transcript removed after it was recorded (existed at mint, measurement lost)"' "$AT8/butin.jsonl" 2>/dev/null \
   && grep -q '"receipt": "ttlLoss"' "$AT8/butin.jsonl" 2>/dev/null \
   && echo "$OUT8T" | grep -q "unmeasurable 1"; then
  ok "TTL-8 observed:true + absent past TTL -> LOSS reason (contains 'removed')"
else
  ko "TTL-8 out=[$OUT8T] events=[$(cat "$AT8/butin.jsonl" 2>/dev/null)]"
fi
AT8_REPORT=$(awk -f "$HERE/lib/butin/core.awk" "$AT8/butin.jsonl")
AT8_PHANTOM=$(echo "$AT8_REPORT" | awk -F'\t' '/^PHANTOM/{print $2}')
AT8_UNMEAS=$(echo "$AT8_REPORT" | awk -F'\t' '/^UNMEASURED/{print $2}')
if [ "${AT8_PHANTOM:-x}" = "0" ] && [ "${AT8_UNMEAS:-x}" = "1" ]; then
  ok "TTL-8b core.awk: a LOSS event counts UNMEASURED (denominator), never PHANTOM"
else
  ko "TTL-8b phantom=$AT8_PHANTOM unmeas=$AT8_UNMEAS report=[$AT8_REPORT]"
fi

# TTL-9: "observed":false + transcript absent past TTL -> PHANTOM. reason
# contains "phantom"; core.awk must count it PHANTOM (excluded).
AT9="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$AT9/butin-config.json"
printf '{"v":2,"id":"ttlPh","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/agent-never-was.jsonl","cwd":"/x","measured":false,"observed":false}\n' "$TS49B" > "$AT9/receipts.jsonl"
OUT9T=$(AMIRAL_HOME="$AT9" python3 "$HERE/lib/butin/measure.py")
if grep -q '"reason": "transcript never written (phantom' "$AT9/butin.jsonl" 2>/dev/null \
   && grep -q '"receipt": "ttlPh"' "$AT9/butin.jsonl" 2>/dev/null \
   && echo "$OUT9T" | grep -q "unmeasurable 1"; then
  ok "TTL-9 observed:false + absent past TTL -> phantom reason (contains 'phantom')"
else
  ko "TTL-9 out=[$OUT9T] events=[$(cat "$AT9/butin.jsonl" 2>/dev/null)]"
fi
AT9_REPORT=$(awk -f "$HERE/lib/butin/core.awk" "$AT9/butin.jsonl")
AT9_PHANTOM=$(echo "$AT9_REPORT" | awk -F'\t' '/^PHANTOM/{print $2}')
AT9_UNMEAS=$(echo "$AT9_REPORT" | awk -F'\t' '/^UNMEASURED/{print $2}')
if [ "${AT9_PHANTOM:-x}" = "1" ] && [ "${AT9_UNMEAS:-x}" = "0" ]; then
  ok "TTL-9b core.awk: a phantom event counts PHANTOM (excluded), never UNMEASURED"
else
  ko "TTL-9b phantom=$AT9_PHANTOM unmeas=$AT9_UNMEAS report=[$AT9_REPORT]"
fi

# TTL-10: LEGACY exact reason string (pre-v0.16.0, no "observed" field ever
# existed for these) still counts PHANTOM in core.awk — the ~48 already-
# emitted events must not shift into UNMEASURED under the new rule.
AT10="$(mktemp -d)"
printf '{"v":2,"receipt":"legacy1","unmeasurable":true,"reason":"transcript absent (never written or removed)"}\n' > "$AT10/legacy.jsonl"
AT10_REPORT=$(awk -f "$HERE/lib/butin/core.awk" "$AT10/legacy.jsonl")
AT10_PHANTOM=$(echo "$AT10_REPORT" | awk -F'\t' '/^PHANTOM/{print $2}')
AT10_UNMEAS=$(echo "$AT10_REPORT" | awk -F'\t' '/^UNMEASURED/{print $2}')
if [ "${AT10_PHANTOM:-x}" = "1" ] && [ "${AT10_UNMEAS:-x}" = "0" ]; then
  ok "TTL-10 legacy exact reason string still counts PHANTOM (pre-v0.16.0 events can't be split)"
else
  ko "TTL-10 phantom=$AT10_PHANTOM unmeas=$AT10_UNMEAS report=[$AT10_REPORT]"
fi


# ─── v0.14.0 mixed-model cold measurement (AUDIT-FABLE C2, brain path) ───
# A `/model` switch mid-session (opus -> fable) used to let ONE `model`
# variable, overwritten by every usage-bearing line, price ALL deduped turns
# at the LAST model's rate — a real-money lie. Turns are now grouped BY
# MODEL and ONE EVENT PER MODEL is written, each priced at its own rate over
# exactly its own tokens.
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"

# MM-1: two-model BRAIN transcript (opus -> fable mid-session). m1 carries a
# duplicate-id line (same shape as the V12 dedup fixture) to prove dedup
# still last-write-wins per id even when grouping by model. After a --brain
# receipt + measure.py: exactly TWO brain events for the session, one per
# model, each with its own summed tokens and its own real cost (non-equal,
# both present) — no event names a model that didn't price its tokens.
Tm1=$(mktemp -d); Am1=$(mktemp -d)
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Am1/butin-config.json"
cat > "$Tm1/main.jsonl" << 'TXM1'
{"message":{"id":"m1","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}
{"message":{"id":"m1","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":500,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}
{"message":{"id":"m2","model":"claude-opus-4-8","usage":{"input_tokens":50,"output_tokens":250,"cache_read_input_tokens":2000,"cache_creation_input_tokens":0}}}
{"message":{"id":"m3","model":"claude-fable-5","usage":{"input_tokens":30,"output_tokens":400,"cache_read_input_tokens":500,"cache_creation_input_tokens":100}}}
TXM1
echo "{\"session_id\":\"MB1\",\"transcript_path\":\"$Tm1/main.jsonl\"}" \
  | AMIRAL_HOME="$Am1" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
AMIRAL_HOME="$Am1" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
BEV=$(grep '"agent": "brain"' "$Am1/butin.jsonl" 2>/dev/null)
BN=$(echo "$BEV" | grep -c '.'); [ -z "$BEV" ] && BN=0
OPUS_EV=$(echo "$BEV" | grep '"chosen_model": "claude-opus-4-8"')
FABLE_EV=$(echo "$BEV" | grep '"chosen_model": "claude-fable-5"')
UNMEAS1=$(grep -c '"unmeasurable": true' "$Am1/butin.jsonl" 2>/dev/null); UNMEAS1=${UNMEAS1:-0}
REAL_OPUS=$(echo "$OPUS_EV" | grep -oE '"real_cost_usd": [0-9.eE+-]+')
REAL_FABLE=$(echo "$FABLE_EV" | grep -oE '"real_cost_usd": [0-9.eE+-]+')
if [ "$BN" = "2" ] && [ -n "$OPUS_EV" ] && [ -n "$FABLE_EV" ] \
   && echo "$OPUS_EV" | grep -q '"in": 150' && echo "$OPUS_EV" | grep -q '"out": 750' \
   && echo "$OPUS_EV" | grep -q '"cache_read": 3000' && echo "$OPUS_EV" | grep -q '"cache_write": 200' \
   && echo "$FABLE_EV" | grep -q '"in": 30' && echo "$FABLE_EV" | grep -q '"out": 400' \
   && echo "$FABLE_EV" | grep -q '"cache_read": 500' && echo "$FABLE_EV" | grep -q '"cache_write": 100' \
   && [ -n "$REAL_OPUS" ] && [ -n "$REAL_FABLE" ] && [ "$REAL_OPUS" != "$REAL_FABLE" ] \
   && [ "$UNMEAS1" = "0" ]; then
  ok "MM-1 brain two-model: dedup last-write-wins per id, 2 events (own tokens, real costs differ)"
else
  ko "MM-1 events=[$BEV]"
fi

# MM-2: worker two-model transcript. Same receipt (agent identity from the
# sidecar, not the hint) -> two events sharing one receipt id, receipts.jsonl
# drained, re-run idempotent (event count stable).
Tm2=$(mktemp -d); mkdir -p "$Tm2/s/subagents"
echo '{"agentType":"corsaire","spawnDepth":1}' > "$Tm2/s/subagents/agent-y.meta.json"
cat > "$Tm2/s/subagents/agent-y.jsonl" << 'TXM2'
{"message":{"id":"w1","model":"claude-opus-4-8","usage":{"input_tokens":40,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
{"message":{"id":"w2","model":"claude-fable-5","usage":{"input_tokens":15,"output_tokens":60,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TXM2
Am2="$(mktemp -d)"; printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Am2/butin-config.json"
echo "{\"session_id\":\"SW\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$Tm2/s/subagents/agent-y.jsonl\"}" \
  | AMIRAL_HOME="$Am2" bash "$HERE/adapters/claude-code/butin-receipt.sh"
AMIRAL_HOME="$Am2" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
EVCOUNT=$(grep -c '"real_cost_usd"' "$Am2/butin.jsonl" 2>/dev/null); EVCOUNT=${EVCOUNT:-0}
AGCOUNT=$(grep -c '"agent": "corsaire"' "$Am2/butin.jsonl" 2>/dev/null); AGCOUNT=${AGCOUNT:-0}
RIDS=$(grep -oE '"receipt": "[^"]*"' "$Am2/butin.jsonl" 2>/dev/null | sort -u | wc -l | tr -d ' ')
if [ -s "$Am2/receipts.jsonl" ]; then RCPT_DRAINED=no; else RCPT_DRAINED=yes; fi
AMIRAL_HOME="$Am2" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
EVCOUNT2=$(grep -c '"real_cost_usd"' "$Am2/butin.jsonl" 2>/dev/null); EVCOUNT2=${EVCOUNT2:-0}
if [ "$EVCOUNT" = "2" ] && [ "$AGCOUNT" = "2" ] && [ "$RIDS" = "1" ] \
   && [ "$RCPT_DRAINED" = "yes" ] && [ "$EVCOUNT2" = "2" ]; then
  ok "MM-2 worker two-model: 2 events, agent identical (corsaire), shared receipt id, drained, idempotent"
else
  ko "MM-2 ev=$EVCOUNT ag=$AGCOUNT rids=$RIDS drained=$RCPT_DRAINED ev2=$EVCOUNT2"
fi

# MM-3: mixed with one UNKNOWN model (not in pricing.tsv) -> ALL-OR-NOTHING:
# exactly ONE unmeasurable event for the whole receipt, reason unknown
# pricing_id, no partial measured event for the slice that WAS priceable,
# unknown model named.
Tm3=$(mktemp -d); mkdir -p "$Tm3/s/subagents"
echo '{"agentType":"reviewer","spawnDepth":1}' > "$Tm3/s/subagents/agent-z.meta.json"
cat > "$Tm3/s/subagents/agent-z.jsonl" << 'TXM3'
{"message":{"id":"u1","model":"claude-opus-4-8","usage":{"input_tokens":40,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
{"message":{"id":"u2","model":"claude-unicorn-9","usage":{"input_tokens":15,"output_tokens":60,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TXM3
Am3="$(mktemp -d)"; printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Am3/butin-config.json"
echo "{\"session_id\":\"SU\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$Tm3/s/subagents/agent-z.jsonl\"}" \
  | AMIRAL_HOME="$Am3" bash "$HERE/adapters/claude-code/butin-receipt.sh"
AMIRAL_HOME="$Am3" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
EVCOUNT3=$(grep -c '.' "$Am3/butin.jsonl" 2>/dev/null); EVCOUNT3=${EVCOUNT3:-0}
REALCOUNT3=$(grep -c '"real_cost_usd"' "$Am3/butin.jsonl" 2>/dev/null); REALCOUNT3=${REALCOUNT3:-0}
UNM3=$(grep '"unmeasurable": true' "$Am3/butin.jsonl" 2>/dev/null)
if [ "$EVCOUNT3" = "1" ] && [ "$REALCOUNT3" = "0" ] \
   && echo "$UNM3" | grep -q '"reason": "unknown pricing_id"' \
   && echo "$UNM3" | grep -q 'claude-unicorn-9'; then
  ok "MM-3 mixed with one unknown model: single unmeasurable event, reason+model named, no partial measured"
else
  ko "MM-3 events=[$(cat "$Am3/butin.jsonl" 2>/dev/null)]"
fi

# MM-4 regression: single-model transcript still produces exactly one event,
# byte-level same fields as the V12 expectations — already asserted by the
# unmodified V12/V12.2/TTL-* blocks above (this section adds no new fixture
# for it on purpose: the whole point is that the single-model path is
# untouched by the mixed-model grouping).

# MM-5: brain dedup with mixed models. Two --brain receipts for the SAME
# growing session transcript (first single-model, then a second model
# appended before the second receipt) -> final log has exactly the LATEST
# set (2 brain events), never 4 (no stale per-model leftovers accumulate).
Tm5=$(mktemp -d); Am5=$(mktemp -d)
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Am5/butin-config.json"
printf '{"message":{"id":"m1","model":"claude-opus-4-8","usage":{"input_tokens":20,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$Tm5/main.jsonl"
echo "{\"session_id\":\"MB5\",\"transcript_path\":\"$Tm5/main.jsonl\"}" \
  | AMIRAL_HOME="$Am5" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
AMIRAL_HOME="$Am5" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
FIRSTCOUNT=$(grep -c '"agent": "brain"' "$Am5/butin.jsonl" 2>/dev/null); FIRSTCOUNT=${FIRSTCOUNT:-0}
printf '{"message":{"id":"m2","model":"claude-fable-5","usage":{"input_tokens":5,"output_tokens":40,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' >> "$Tm5/main.jsonl"
echo "{\"session_id\":\"MB5\",\"transcript_path\":\"$Tm5/main.jsonl\"}" \
  | AMIRAL_HOME="$Am5" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
AMIRAL_HOME="$Am5" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
FINALCOUNT=$(grep -c '"agent": "brain"' "$Am5/butin.jsonl" 2>/dev/null); FINALCOUNT=${FINALCOUNT:-0}
MODELS5=$(grep '"agent": "brain"' "$Am5/butin.jsonl" 2>/dev/null | grep -oE '"chosen_model": "[^"]*"' | sort -u)
if [ "$FIRSTCOUNT" = "1" ] && [ "$FINALCOUNT" = "2" ] \
   && echo "$MODELS5" | grep -q 'claude-opus-4-8' && echo "$MODELS5" | grep -q 'claude-fable-5'; then
  ok "MM-5 brain dedup mixed models: growing 2-receipt session -> latest set (2 events, not 4)"
else
  ko "MM-5 first=$FIRSTCOUNT final=$FINALCOUNT models=[$MODELS5]"
fi


# ─── v0.14.0 diagnostic gate (AUDIT-FABLE M8): report's "same tier" line
# used to print TWICE from near-zero data (once from CHEAP-empty + net~=0,
# which is absence of data, not evidence; once from core.awk's DEGENERATE
# flag). Now: ONE diagnostic, ONLY from DEGENERATE, gated on >=3 measured
# WORKER events AND pending < 25% of total. Silence otherwise.
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"
mkdir -p "$AC/butin"; cp "$HERE/lib/butin/pricing.tsv" "$AC/butin/"

# T-D1 lying scenario killed: ONE measured BRAIN event (no worker events at
# all) + 2 pending receipts. core.awk's DEGENERATE still fires (measured>0,
# no worker ever set diversity, brain premium 0) but 0 measured WORKERS is
# near-zero data, not proof of tier identity — the report must stay silent,
# and the retired "same tier" wording must never resurface.
AD1="$(mktemp -d)"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$AD1/butin-config.json"
printf '{"v":1,"id":"br1","agent":"brain","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}\n' > "$AD1/butin.jsonl"
TSNOWD=$(date -u +%FT%TZ)
printf '{"v":2,"id":"pd1","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/d1.jsonl","cwd":"/x","measured":false}\n' "$TSNOWD" > "$AD1/receipts.jsonl"
printf '{"v":2,"id":"pd2","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/d2.jsonl","cwd":"/x","measured":false}\n' "$TSNOWD" >> "$AD1/receipts.jsonl"
OUTD1=$(AMIRAL_HOME="$AD1" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
ND1A=$(echo "$OUTD1" | grep -ci "same tier")
ND1B=$(echo "$OUTD1" | grep -ci "tiers identical")
if [ "$ND1A" = "0" ] && [ "$ND1B" = "0" ]; then
  ok "T-D1 lying scenario killed: 1 measured brain event + 2 pending -> no same-tier/tiers-identical text"
else
  ko "T-D1 same_tier=$ND1A tiers_identical=$ND1B out=[$OUTD1]"
fi

# T-D2 single print: genuinely degenerate WITH enough evidence — 3 measured
# WORKER events, all chosen_model == baseline_model, no pending -> the
# diagnostic appears EXACTLY ONCE.
AD2="$(mktemp -d)"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$AD2/butin-config.json"
cat > "$AD2/butin.jsonl" << 'EOF'
{"v":1,"id":"deg1","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"deg2","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"deg3","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
EOF
OUTD2=$(AMIRAL_HOME="$AD2" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
ND2=$(echo "$OUTD2" | grep -c "tiers identical")
[ "$ND2" = "1" ] && ok "T-D2 genuinely degenerate, >=3 measured workers, no pending -> diagnostic prints exactly once" || ko "T-D2 count=$ND2 out=[$OUTD2]"

# T-D3 evidence gate (worker count): only 2 degenerate worker events, no
# pending -> below the >=3 measured-worker threshold, must stay silent.
AD3="$(mktemp -d)"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$AD3/butin-config.json"
cat > "$AD3/butin.jsonl" << 'EOF'
{"v":1,"id":"deg1","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"deg2","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
EOF
OUTD3=$(AMIRAL_HOME="$AD3" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
ND3=$(echo "$OUTD3" | grep -c "tiers identical")
[ "$ND3" = "0" ] && ok "T-D3 evidence gate (worker count): only 2 measured workers -> silent" || ko "T-D3 count=$ND3 out=[$OUTD3]"

# T-D4 evidence gate (coverage): 3 degenerate worker events + 1 pending
# receipt = 4 total, pending is exactly 25% (1*4 == 4, not < 4) -> materially
# incomplete coverage, must stay silent (honest move at the boundary).
AD4="$(mktemp -d)"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$AD4/butin-config.json"
cat > "$AD4/butin.jsonl" << 'EOF'
{"v":1,"id":"deg1","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"deg2","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"deg3","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
EOF
TSNOWD4=$(date -u +%FT%TZ)
printf '{"v":2,"id":"pd4","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/d4.jsonl","cwd":"/x","measured":false}\n' "$TSNOWD4" > "$AD4/receipts.jsonl"
OUTD4=$(AMIRAL_HOME="$AD4" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
ND4=$(echo "$OUTD4" | grep -c "tiers identical")
[ "$ND4" = "0" ] && ok "T-D4 evidence gate (coverage): 3 measured + 1 pending (25%) -> silent" || ko "T-D4 count=$ND4 out=[$OUTD4]"

# T-D5 regression: a genuinely healthy log (chosen_model != baseline_model)
# never shows the diagnostic — real savings logs must never see it.
AD5="$(mktemp -d)"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$AD5/butin-config.json"
cat > "$AD5/butin.jsonl" << 'EOF'
{"v":1,"id":"h1","agent":"grunt","chosen_model":"claude-haiku-4-5","baseline_model":"claude-opus-4-8","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"h2","agent":"grunt","chosen_model":"claude-haiku-4-5","baseline_model":"claude-opus-4-8","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"h3","agent":"grunt","chosen_model":"claude-haiku-4-5","baseline_model":"claude-opus-4-8","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}
EOF
OUTD5=$(AMIRAL_HOME="$AD5" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
ND5=$(echo "$OUTD5" | grep -c "tiers identical")
[ "$ND5" = "0" ] && ok "T-D5 regression: healthy diversity log (chosen != baseline) never shows the diagnostic" || ko "T-D5 count=$ND5 out=[$OUTD5]"


# ─── v0.14.0 receipt-by-discovery: SubagentStop is dead for Task-tool
# agents on Claude Code 2.1.214 (verified 2026-07-18: a synchronous agent
# completed, wrote its transcript+sidecar instantly, receipts.jsonl never
# moved — 9 real transcripts that session, 0 receipts). The Stop hook DOES
# fire reliably every turn with the main transcript_path, so worker
# receipts are now minted by DISCOVERY off that path instead: scan
# .../<session>/subagents/ for agent-*.jsonl files that exist but have no
# receipt yet.
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"
Tdisc1=$(mktemp -d); Adisc1=$(mktemp -d)
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Adisc1/butin-config.json"
mkdir -p "$Tdisc1/S/subagents"
printf '{"message":{"id":"main1","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$Tdisc1/S.jsonl"
echo '{"agentType":"grunt","spawnDepth":1}' > "$Tdisc1/S/subagents/agent-d1.meta.json"
cat > "$Tdisc1/S/subagents/agent-d1.jsonl" << 'TXDISC1'
{"message":{"id":"d1a","model":"claude-sonnet-5","usage":{"input_tokens":40,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TXDISC1
echo '{"agentType":"reviewer","spawnDepth":1}' > "$Tdisc1/S/subagents/agent-d2.meta.json"
cat > "$Tdisc1/S/subagents/agent-d2.jsonl" << 'TXDISC2'
{"message":{"id":"d2a","model":"claude-sonnet-5","usage":{"input_tokens":15,"output_tokens":60,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TXDISC2
touch -t 202601010000 "$Tdisc1/S.jsonl" "$Tdisc1/S/subagents/agent-d1.jsonl" "$Tdisc1/S/subagents/agent-d2.jsonl"

# D-1: a Stop payload for session S discovers BOTH worker transcripts (real,
# existing files, different agentTypes) and records the brain receipt too.
echo "{\"session_id\":\"S\",\"transcript_path\":\"$Tdisc1/S.jsonl\"}" \
  | AMIRAL_HOME="$Adisc1" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
if grep -qF "$Tdisc1/S/subagents/agent-d1.jsonl" "$Adisc1/receipts.jsonl" 2>/dev/null \
   && grep -qF "$Tdisc1/S/subagents/agent-d2.jsonl" "$Adisc1/receipts.jsonl" 2>/dev/null \
   && grep -q '"role":"brain"' "$Adisc1/receipts.jsonl" 2>/dev/null; then
  ok "D-1 discovery: receipts.jsonl carries BOTH real worker paths + the brain receipt"
else
  ko "D-1 receipts=[$(cat "$Adisc1/receipts.jsonl" 2>/dev/null)]"
fi
# D-1c (v0.16.0): every receipt minted here points at a file confirmed
# present on disk (the discovery scan's own `[ -f "$AT" ]` guard, and the
# brain branch's main transcript that the Stop hook just wrote) -> ALL
# lines in this batch must carry "observed":true.
D1_LINES=$(grep -c '.' "$Adisc1/receipts.jsonl" 2>/dev/null); D1_LINES=${D1_LINES:-0}
D1_OBSERVED_TRUE=$(grep -c '"observed":true' "$Adisc1/receipts.jsonl" 2>/dev/null); D1_OBSERVED_TRUE=${D1_OBSERVED_TRUE:-0}
if [ "$D1_LINES" -gt 0 ] && [ "$D1_LINES" = "$D1_OBSERVED_TRUE" ]; then
  ok "D-1c discovery + brain receipts all carry \"observed\":true (transcript confirmed present at mint)"
else
  ko "D-1c lines=$D1_LINES observed_true=$D1_OBSERVED_TRUE receipts=[$(cat "$Adisc1/receipts.jsonl" 2>/dev/null)]"
fi
AMIRAL_HOME="$Adisc1" BUTIN_STABLE_SECS=0 python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
EVDISC1=$(cat "$Adisc1/butin.jsonl" 2>/dev/null)
if echo "$EVDISC1" | grep -q '"agent": "grunt"' && echo "$EVDISC1" | grep -q '"agent": "reviewer"' \
   && echo "$EVDISC1" | grep -qF "\"transcript\": \"$Tdisc1/S/subagents/agent-d1.jsonl\"" \
   && echo "$EVDISC1" | grep -qF "\"transcript\": \"$Tdisc1/S/subagents/agent-d2.jsonl\""; then
  ok "D-1 measure: worker events carry sidecar identity (grunt/reviewer) + the real transcript path"
else
  ko "D-1 events=[$EVDISC1]"
fi

# D-2: dedup across draining — receipts are drained once measured; a
# second --brain call for the SAME session must not re-mint worker
# receipts for transcripts already on the event side.
echo "{\"session_id\":\"S\",\"transcript_path\":\"$Tdisc1/S.jsonl\"}" \
  | AMIRAL_HOME="$Adisc1" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
RC_D1=$(grep -cF "$Tdisc1/S/subagents/agent-d1.jsonl" "$Adisc1/receipts.jsonl" 2>/dev/null); RC_D1=${RC_D1:-0}
RC_D2=$(grep -cF "$Tdisc1/S/subagents/agent-d2.jsonl" "$Adisc1/receipts.jsonl" 2>/dev/null); RC_D2=${RC_D2:-0}
if [ "$RC_D1" = "0" ] && [ "$RC_D2" = "0" ]; then
  ok "D-2 dedup across draining: re-run mints no new receipts for already-measured transcripts"
else
  ko "D-2 rc_d1=$RC_D1 rc_d2=$RC_D2 receipts=[$(cat "$Adisc1/receipts.jsonl" 2>/dev/null)]"
fi
EVN_BEFORE=$(grep -c '"real_cost_usd"' "$Adisc1/butin.jsonl" 2>/dev/null); EVN_BEFORE=${EVN_BEFORE:-0}
AMIRAL_HOME="$Adisc1" BUTIN_STABLE_SECS=0 python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
EVN_AFTER=$(grep -c '"real_cost_usd"' "$Adisc1/butin.jsonl" 2>/dev/null); EVN_AFTER=${EVN_AFTER:-0}
[ "$EVN_BEFORE" = "$EVN_AFTER" ] && ok "D-2 event count stable across an extra measure.py run ($EVN_AFTER)" || ko "D-2 before=$EVN_BEFORE after=$EVN_AFTER"

# D-3: stable-gate — a THIRD worker transcript, mtime=NOW (never
# back-dated), is discovered but must stay PENDING under a stable window
# that hasn't elapsed yet (never measured warm mid-flush).
echo '{"agentType":"grunt","spawnDepth":1}' > "$Tdisc1/S/subagents/agent-d3.meta.json"
cat > "$Tdisc1/S/subagents/agent-d3.jsonl" << 'TXDISC3'
{"message":{"id":"d3a","model":"claude-sonnet-5","usage":{"input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TXDISC3
echo "{\"session_id\":\"S\",\"transcript_path\":\"$Tdisc1/S.jsonl\"}" \
  | AMIRAL_HOME="$Adisc1" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
D3_RECEIPTED=no
grep -qF "$Tdisc1/S/subagents/agent-d3.jsonl" "$Adisc1/receipts.jsonl" 2>/dev/null && D3_RECEIPTED=yes
OUTD3=$(AMIRAL_HOME="$Adisc1" BUTIN_STABLE_SECS=3600 python3 "$HERE/lib/butin/measure.py" 2>&1)
D3_STILL_PENDING=no
grep -qF "$Tdisc1/S/subagents/agent-d3.jsonl" "$Adisc1/receipts.jsonl" 2>/dev/null && D3_STILL_PENDING=yes
D3_MEASURED=no
grep -qF "\"transcript\": \"$Tdisc1/S/subagents/agent-d3.jsonl\"" "$Adisc1/butin.jsonl" 2>/dev/null && D3_MEASURED=yes
if [ "$D3_RECEIPTED" = "yes" ] && [ "$D3_STILL_PENDING" = "yes" ] && [ "$D3_MEASURED" = "no" ] \
   && echo "$OUTD3" | grep -q "pending 1"; then
  ok "D-3 stable-gate: fresh (mtime=now) worker transcript discovered but kept PENDING, never measured warm"
else
  ko "D-3 receipted=$D3_RECEIPTED still_pending=$D3_STILL_PENDING measured=$D3_MEASURED out=[$OUTD3]"
fi

# D-4: phantom fast-expiry — the default TTL is now 6h (was 48h): a
# receipt whose transcript was NEVER written ("observed":false — the
# real-world SubagentStop-noise case) must expire well inside a day, not
# linger for two.
Adisc4="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Adisc4/butin-config.json"
TS7H=$(date -u -v-7H +%FT%TZ 2>/dev/null || date -u -d '7 hours ago' +%FT%TZ)
printf '{"v":2,"id":"phantom1","ts":"%s","role":"worker","session":"s","agent_hint":"","transcript":"/nonexistent/agent-phantom.jsonl","cwd":"/x","measured":false,"observed":false}\n' "$TS7H" > "$Adisc4/receipts.jsonl"
OUTD4=$(AMIRAL_HOME="$Adisc4" python3 "$HERE/lib/butin/measure.py")
if grep -q '"receipt": "phantom1"' "$Adisc4/butin.jsonl" 2>/dev/null \
   && grep -q '"reason": "transcript never written (phantom' "$Adisc4/butin.jsonl" 2>/dev/null \
   && ! grep -q "phantom1" "$Adisc4/receipts.jsonl" 2>/dev/null \
   && echo "$OUTD4" | grep -q "unmeasurable 1"; then
  ok "D-4 phantom fast-expiry: 7h-old absent-transcript receipt expires under the new 6h default, drained"
else
  ko "D-4 out=[$OUTD4] events=[$(cat "$Adisc4/butin.jsonl" 2>/dev/null)] receipts=[$(cat "$Adisc4/receipts.jsonl" 2>/dev/null)]"
fi

# D-5: ts = mtime — recompute the expected ts independently (same
# stat/date fallback chain the hook uses) and compare against the stored
# event ts for D-1's agent-d1 transcript (back-dated, never touched again
# since, so its mtime is still authoritative here).
# GNU-first + validate, then BSD — same order as butin-receipt.sh. A
# BSD-first chain here is exactly what made D-5 red on ubuntu: on GNU,
# `stat -f %m` prints filesystem garbage to stdout and exits non-zero, so the
# `||` appended the epoch to it, and `date` then failed both ways -> empty
# expect. Never chain on exit status alone when the failing branch writes stdout.
EPOCH_D1="$(stat -c %Y "$Tdisc1/S/subagents/agent-d1.jsonl" 2>/dev/null)"
case "$EPOCH_D1" in ''|*[!0-9]*) EPOCH_D1="$(stat -f %m "$Tdisc1/S/subagents/agent-d1.jsonl" 2>/dev/null)" ;; esac
case "$EPOCH_D1" in ''|*[!0-9]*) EPOCH_D1="" ;; esac
EXPECT_TS_D1="$(date -u -d "@$EPOCH_D1" +%FT%TZ 2>/dev/null)"
case "$EXPECT_TS_D1" in [0-9][0-9][0-9][0-9]-*) ;; *) EXPECT_TS_D1="$(date -u -r "$EPOCH_D1" +%FT%TZ 2>/dev/null)" ;; esac
case "$EXPECT_TS_D1" in [0-9][0-9][0-9][0-9]-*) ;; *) EXPECT_TS_D1="" ;; esac
ACTUAL_TS_D1=$(grep -F "\"transcript\": \"$Tdisc1/S/subagents/agent-d1.jsonl\"" "$Adisc1/butin.jsonl" 2>/dev/null | grep -oE '"ts": "[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$EXPECT_TS_D1" ] && [ "$ACTUAL_TS_D1" = "$EXPECT_TS_D1" ]; then
  ok "D-5 discovery ts = transcript mtime ($EXPECT_TS_D1), not discovery time"
else
  ko "D-5 expect=$EXPECT_TS_D1 actual=$ACTUAL_TS_D1"
fi

# D-5b: regression guard for the epoch-resolution shape. A non-numeric epoch
# (the multi-line garbage a BSD-first `stat` chain produces on GNU) must NEVER
# be accepted — it must degrade to the default. Mirrors butin-receipt.sh's
# GNU-first + validate logic and asserts both directions: a real file yields a
# digits-only epoch, and injected garbage is rejected rather than propagated.
_resolve_epoch_d5b() {   # GNU-first, validate, BSD, validate — the correct shape
  local f="$1" e
  e="$(stat -c %Y "$f" 2>/dev/null)"
  case "$e" in ''|*[!0-9]*) e="$(stat -f %m "$f" 2>/dev/null)" ;; esac
  case "$e" in ''|*[!0-9]*) e="" ;; esac
  printf '%s' "$e"
}
_RF_D5B="$(mktemp)"
GOOD_D5B="$(_resolve_epoch_d5b "$_RF_D5B")"
GOOD_NUM=0; case "$GOOD_D5B" in ''|*[!0-9]*) GOOD_NUM=0 ;; *) GOOD_NUM=1 ;; esac
# the exact garbage BSD-first-on-GNU would produce: fs-info lines + epoch.
BAD_D5B="$(printf '  File: "/x"\n  ID: 0\n1699999999')"
BAD_OUT=nonempty; case "$BAD_D5B" in ''|*[!0-9]*) BAD_OUT="" ;; *) BAD_OUT="$BAD_D5B" ;; esac
rm -f "$_RF_D5B"
if [ "$GOOD_NUM" = "1" ] && [ -z "$BAD_OUT" ]; then
  ok "D-5b epoch validation: numeric epoch accepted ($GOOD_D5B), non-numeric/multi-line rejected"
else
  ko "D-5b good=[$GOOD_D5B] num=$GOOD_NUM bad_accepted=[$BAD_OUT]"
fi



# ─── v0.14.1 final-review fixes: F1 double-bill dedup (both directions,
# hook-side + measure.py belt-and-braces), F2 one-pass discovery scan, F3
# hostile transcript paths + never-destroy-unparseable-receipts, F4 future
# mtime doesn't mean pending forever. (F5/F6 are comment/label/grep-pattern
# fixes in bin/amiral-butin and bin/amiral-journal — covered by the existing
# T-C7/T-D* batteries and manual bash -n, not new fixtures here.)
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"

# R-1: double-bill killed, both the hook-side guard AND measure.py's
# belt-and-braces. A worker transcript first receipted+measured via
# DISCOVERY (the --brain scan), then the SAME transcript arrives again via
# a PLAIN (non-brain) worker hook firing — the exact scenario a revived
# SubagentStop would produce. R-1a: the hook itself must mint no second
# receipt. R-1b: even if a duplicate receipt line reaches receipts.jsonl
# some OTHER way (forced by hand here), measure.py must still write no
# second event — just count it.
Tr1=$(mktemp -d); mkdir -p "$Tr1/S1/subagents"
Ar1="$(mktemp -d)"; printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Ar1/butin-config.json"
printf '{"message":{"id":"r1m","model":"claude-sonnet-5","usage":{"input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$Tr1/S1.jsonl"
echo '{"agentType":"grunt","spawnDepth":1}' > "$Tr1/S1/subagents/agent-r1.meta.json"
printf '{"message":{"id":"r1a","model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$Tr1/S1/subagents/agent-r1.jsonl"
echo "{\"session_id\":\"R1\",\"transcript_path\":\"$Tr1/S1.jsonl\"}" \
  | AMIRAL_HOME="$Ar1" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
AMIRAL_HOME="$Ar1" BUTIN_STABLE_SECS=0 python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
echo "{\"session_id\":\"R1\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$Tr1/S1/subagents/agent-r1.jsonl\"}" \
  | AMIRAL_HOME="$Ar1" bash "$HERE/adapters/claude-code/butin-receipt.sh"
R1_NEWRECEIPT=no
grep -qF "$Tr1/S1/subagents/agent-r1.jsonl" "$Ar1/receipts.jsonl" 2>/dev/null && R1_NEWRECEIPT=yes
if [ "$R1_NEWRECEIPT" = "no" ]; then
  ok "R-1a hook-side two-way dedup: plain worker hook skips a transcript discovery already measured"
else
  ko "R-1a receipts=[$(cat "$Ar1/receipts.jsonl" 2>/dev/null)]"
fi
printf '{"v":2,"id":"r1dup","ts":"%s","role":"worker","session":"R1","agent_hint":"","transcript":"%s","cwd":"/x","measured":false}\n' \
  "$(date -u +%FT%TZ)" "$Tr1/S1/subagents/agent-r1.jsonl" >> "$Ar1/receipts.jsonl"
OUTR1=$(AMIRAL_HOME="$Ar1" BUTIN_STABLE_SECS=0 python3 "$HERE/lib/butin/measure.py")
R1_TCOUNT=$(grep -cF "$Tr1/S1/subagents/agent-r1.jsonl" "$Ar1/butin.jsonl" 2>/dev/null)
if [ "$R1_TCOUNT" = "1" ] && echo "$OUTR1" | grep -qE "dup_receipts 1" \
   && ! grep -q "r1dup" "$Ar1/receipts.jsonl" 2>/dev/null; then
  ok "R-1b measure.py belt-and-braces: forced dup receipt -> no 2nd event, dup_receipts counts it, drained"
else
  ko "R-1b tcount=$R1_TCOUNT out=[$OUTR1] receipts=[$(cat "$Ar1/receipts.jsonl" 2>/dev/null)]"
fi

# R-2: brain exemption — 2 brain receipts, same session, same main
# transcript, still SUPERSEDE (1 final event set) instead of being caught
# by the new transcript-dedup (which must apply to role=worker only).
Tr2=$(mktemp -d); Ar2=$(mktemp -d)
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Ar2/butin-config.json"
printf '{"message":{"id":"r2a","model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$Tr2/main.jsonl"
echo "{\"session_id\":\"R2\",\"transcript_path\":\"$Tr2/main.jsonl\"}" \
  | AMIRAL_HOME="$Ar2" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
AMIRAL_HOME="$Ar2" BUTIN_STABLE_SECS=0 python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
echo "{\"session_id\":\"R2\",\"transcript_path\":\"$Tr2/main.jsonl\"}" \
  | AMIRAL_HOME="$Ar2" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
OUTR2=$(AMIRAL_HOME="$Ar2" BUTIN_STABLE_SECS=0 python3 "$HERE/lib/butin/measure.py")
BC_R2=$(grep -c '"agent": "brain"' "$Ar2/butin.jsonl" 2>/dev/null); BC_R2=${BC_R2:-0}
if [ "$BC_R2" = "1" ] && echo "$OUTR2" | grep -qE "dup_receipts 0"; then
  ok "R-2 brain exempt from transcript-dedup: 2 same-transcript Stop receipts still supersede (1 event), not dup-skipped"
else
  ko "R-2 bc=$BC_R2 out=[$OUTR2]"
fi

# R-3: hostile filename (embedded double-quote) in subagents/ must never
# reach receipts.jsonl — every line that DOES land there still parses as
# JSON (python3, line by line), and no receipt is minted for the hostile
# name itself.
Tr3=$(mktemp -d); Ar3=$(mktemp -d); mkdir -p "$Tr3/S3/subagents"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Ar3/butin-config.json"
printf '{"message":{"id":"r3m","model":"claude-sonnet-5","usage":{"input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$Tr3/S3.jsonl"
HOSTILE_FILE="$Tr3/S3/subagents/agent-x\"quote.jsonl"
printf '{"message":{"id":"hx","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$HOSTILE_FILE"
echo "{\"session_id\":\"R3\",\"transcript_path\":\"$Tr3/S3.jsonl\"}" \
  | AMIRAL_HOME="$Ar3" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
ALL_JSON_OK=yes
while IFS= read -r RLINE; do
  [ -z "$RLINE" ] && continue
  python3 -c "import json,sys; json.loads(sys.argv[1])" "$RLINE" >/dev/null 2>&1 || ALL_JSON_OK=no
done < "$Ar3/receipts.jsonl"
HOSTILE_RECEIPTED=no
grep -qF 'agent-x"quote.jsonl' "$Ar3/receipts.jsonl" 2>/dev/null && HOSTILE_RECEIPTED=yes
if [ "$ALL_JSON_OK" = "yes" ] && [ "$HOSTILE_RECEIPTED" = "no" ]; then
  ok "R-3 hostile filename (embedded quote) skipped: receipts.jsonl stays valid JSON, no receipt minted for it"
else
  ko "R-3 all_json_ok=$ALL_JSON_OK hostile_receipted=$HOSTILE_RECEIPTED receipts=[$(cat "$Ar3/receipts.jsonl" 2>/dev/null)]"
fi

# R-4: an unparseable receipts.jsonl line is preserved verbatim (never
# destroyed) by measure.py, and the run itself still exits 0.
Ar4="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Ar4/butin-config.json"
GARBAGE_LINE='not a json line at all { broken'
printf '%s\n' "$GARBAGE_LINE" > "$Ar4/receipts.jsonl"
OUTR4=$(AMIRAL_HOME="$Ar4" python3 "$HERE/lib/butin/measure.py"); RCR4=$?
if [ "$RCR4" = "0" ] && grep -qF "$GARBAGE_LINE" "$Ar4/receipts.jsonl" 2>/dev/null; then
  ok "R-4 unparseable receipt line preserved verbatim after measure.py (rc0, never destroyed)"
else
  ko "R-4 rc=$RCR4 receipts=[$(cat "$Ar4/receipts.jsonl" 2>/dev/null)]"
fi

# R-5: a future mtime must not mean pending forever. R-5a: a discovered
# worker transcript touched 1h into the future is still MEASURED under a
# STABLE=60 gate (a future mtime is not "mid-flush"). R-5b: a receipt
# carrying a future ts, absent transcript, has its age clamped to 0 —
# stays pending, never crashes (a normal 7h-old absent receipt still
# expiring is already proven by D-4 above; unaffected by this change).
Tr5=$(mktemp -d); Ar5=$(mktemp -d); mkdir -p "$Tr5/S5/subagents"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Ar5/butin-config.json"
printf '{"message":{"id":"r5m","model":"claude-sonnet-5","usage":{"input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$Tr5/S5.jsonl"
echo '{"agentType":"grunt","spawnDepth":1}' > "$Tr5/S5/subagents/agent-r5.meta.json"
printf '{"message":{"id":"r5a","model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$Tr5/S5/subagents/agent-r5.jsonl"
FUTURE_TOUCH=$(date -v+1H +%Y%m%d%H%M 2>/dev/null || date -d '+1 hour' +%Y%m%d%H%M)
touch -t "$FUTURE_TOUCH" "$Tr5/S5/subagents/agent-r5.jsonl"
echo "{\"session_id\":\"R5\",\"transcript_path\":\"$Tr5/S5.jsonl\"}" \
  | AMIRAL_HOME="$Ar5" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
OUTR5A=$(AMIRAL_HOME="$Ar5" BUTIN_STABLE_SECS=60 python3 "$HERE/lib/butin/measure.py")
R5A_MEASURED=no
grep -qF "$Tr5/S5/subagents/agent-r5.jsonl" "$Ar5/butin.jsonl" 2>/dev/null && R5A_MEASURED=yes
# note: the main brain transcript (S5.jsonl, mtime=now) is itself correctly
# held PENDING by the same STABLE=60 gate — that's unrelated, expected
# behavior. This assertion is specifically about the FUTURE-mtime worker
# transcript, which must be measured, not stuck pending forever.
if [ "$R5A_MEASURED" = "yes" ] && echo "$OUTR5A" | grep -qE "measured 1"; then
  ok "R-5a future-mtime transcript measured despite STABLE gate (not pending forever)"
else
  ko "R-5a measured=$R5A_MEASURED out=[$OUTR5A]"
fi
Ar5b="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Ar5b/butin-config.json"
TSFUT=$(date -u -v+1H +%FT%TZ 2>/dev/null || date -u -d '+1 hour' +%FT%TZ)
printf '{"v":2,"id":"r5fut","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/agent-future.jsonl","cwd":"/x","measured":false}\n' "$TSFUT" > "$Ar5b/receipts.jsonl"
OUTR5B=$(AMIRAL_HOME="$Ar5b" python3 "$HERE/lib/butin/measure.py" 2>&1); RCR5B=$?
if [ "$RCR5B" = "0" ] && grep -q "r5fut" "$Ar5b/receipts.jsonl" 2>/dev/null \
   && ! grep -q "Traceback" <<< "$OUTR5B" \
   && echo "$OUTR5B" | grep -q "pending 1"; then
  ok "R-5b future-ts absent-transcript receipt: age clamped to 0, stays pending, no crash"
else
  ko "R-5b rc=$RCR5B out=[$OUTR5B] receipts=[$(cat "$Ar5b/receipts.jsonl" 2>/dev/null)]"
fi

# R-6: diagnostic gate, other side of T-D4's boundary — 4 degenerate
# worker events + 1 pending receipt = 5 total, pending is 20% (< 25%) ->
# enough evidence + enough coverage, the diagnostic MUST print.
AR6="$(mktemp -d)"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$AR6/butin-config.json"
cat > "$AR6/butin.jsonl" << 'EOF'
{"v":1,"id":"r6d1","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"r6d2","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"r6d3","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"r6d4","agent":"grunt","chosen_model":"claude-opus-4-8","baseline_model":"claude-opus-4-8","real_cost_usd":0.05,"counterfactual_cost_usd":0.05,"outcome":"ok"}
EOF
TSNOWR6=$(date -u +%FT%TZ)
printf '{"v":2,"id":"pr6","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/nonexistent/r6.jsonl","cwd":"/x","measured":false}\n' "$TSNOWR6" > "$AR6/receipts.jsonl"
OUTR6=$(AMIRAL_HOME="$AR6" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
NR6=$(echo "$OUTR6" | grep -c "tiers identical")
[ "$NR6" = "1" ] && ok "R-6 gate other side: 4 degenerate workers + 1 pending (4/5) -> diagnostic prints" || ko "R-6 count=$NR6 out=[$OUTR6]"

# R-7: perf smoke — the F2 one-pass restructure. 300 tiny subagent
# transcripts, all pre-drained into butin.jsonl (already "known"), sit in
# subagents/ when a --brain hook fires: the old per-file 2-greps-of-the-
# full-files design degraded with N (200 files measured at 3.2s in the
# audit); the one-pass KNOWN-list design must stay comfortably under a
# generous CI bound regardless.
Tr7=$(mktemp -d); Ar7=$(mktemp -d); mkdir -p "$Tr7/S7/subagents"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Ar7/butin-config.json"
printf '{"message":{"id":"r7m","model":"claude-sonnet-5","usage":{"input_tokens":5,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$Tr7/S7.jsonl"
: > "$Ar7/butin.jsonl"
for i in $(seq 1 300); do
  F="$Tr7/S7/subagents/agent-p$i.jsonl"
  printf '{"message":{"id":"p%d","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$i" > "$F"
  printf '{"v":2,"receipt":"pre%d","ts":"2026-01-01T00:00:00Z","agent":"grunt","transcript":"%s","chosen_model":"claude-sonnet-5","real_cost_usd":0.001,"baseline_model":"claude-opus-4-8","counterfactual_cost_usd":0.002,"outcome":"ok"}\n' "$i" "$F" >> "$Ar7/butin.jsonl"
done
: > "$Ar7/receipts.jsonl"
T0=$(date +%s)
echo "{\"session_id\":\"R7\",\"transcript_path\":\"$Tr7/S7.jsonl\"}" \
  | AMIRAL_HOME="$Ar7" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
T1=$(date +%s)
DUR=$((T1 - T0))
NEWRECEIPTS=$(grep -c "agent-p" "$Ar7/receipts.jsonl" 2>/dev/null); NEWRECEIPTS=${NEWRECEIPTS:-0}
if [ "$DUR" -lt 3 ] && [ "$NEWRECEIPTS" = "0" ]; then
  ok "R-7 perf smoke: 300 pre-drained subagent transcripts, --brain hook completes in ${DUR}s (<3s), no re-receipting"
else
  ko "R-7 dur=${DUR}s new_receipts=$NEWRECEIPTS"
fi


# ─── v0.15 dated model-id normalization (measure.py resolve_rate) ───
# The platform reports ids like claude-sonnet-5-20251001 (verified on real
# transcripts) while pricing.tsv holds the undated claude-sonnet-5. A
# pricing MISS retries ONCE with a trailing -YYYYMMDD stripped; if the
# stripped id isn't priced either, it stays unmeasurable — never a guess.
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"

# PN-1: dated id that RESOLVES — chosen_model stays the dated id (what was
# actually billed), billed_pricing_id carries the stripped id,
# pricing_normalized:true, and the cost equals what the undated id's own
# rate would produce over the same tokens.
Tpn1=$(mktemp -d); mkdir -p "$Tpn1/s/subagents"
echo '{"agentType":"grunt","spawnDepth":1}' > "$Tpn1/s/subagents/agent-pn1.meta.json"
cat > "$Tpn1/s/subagents/agent-pn1.jsonl" << 'TXPN1'
{"message":{"id":"pn1a","model":"claude-sonnet-5-20251001","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TXPN1
Apn1="$(mktemp -d)"; printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Apn1/butin-config.json"
echo "{\"session_id\":\"PN1\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$Tpn1/s/subagents/agent-pn1.jsonl\"}" \
  | AMIRAL_HOME="$Apn1" bash "$HERE/adapters/claude-code/butin-receipt.sh"
AMIRAL_HOME="$Apn1" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
EVPN1=$(cat "$Apn1/butin.jsonl" 2>/dev/null)
REAL_PN1=$(echo "$EVPN1" | grep -oE '"real_cost_usd": [0-9.eE+-]+' | sed 's/.*: //')
# v0.17.0: pricing.tsv now carries TWO rows for claude-sonnet-5 (an undated
# base row + a dated 2026-09-01 cutover) — this fixture's receipt is
# minted with ts="now" (via butin-collect.sh/butin-receipt.sh), so the
# expected rate must be picked the SAME way measure.py picks it: the
# dated row if today >= its effective_from, else the undated base row.
# Robust across time (not just "for now"), unlike a naive single-row match.
TODAY_PN1=$(date -u +%F)
EXP_PN1=$(awk -F'\t' -v today="$TODAY_PN1" '
  $1=="claude-sonnet-5" {
    if (NF>=6 && $6<=today) { dated=1; di=$2; do_=$3 }
    else if (NF==5)         { basei=$2; baseo=$3 }
  }
  END {
    if (dated) printf "%.6f", 100*di+50*do_
    else       printf "%.6f", 100*basei+50*baseo
  }' "$HERE/lib/butin/pricing.tsv")
if [ "$(grep -c '"real_cost_usd"' <<< "$EVPN1")" = "1" ] \
   && echo "$EVPN1" | grep -q '"chosen_model": "claude-sonnet-5-20251001"' \
   && echo "$EVPN1" | grep -q '"billed_pricing_id": "claude-sonnet-5"' \
   && echo "$EVPN1" | grep -q '"pricing_normalized": true' \
   && [ -n "$REAL_PN1" ] && [ -n "$EXP_PN1" ] \
   && awk -v a="$REAL_PN1" -v b="$EXP_PN1" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<0.0000015)}'; then
  ok "PN-1 dated id resolves: chosen_model=dated, billed_pricing_id stripped, pricing_normalized true, cost=undated rate"
else
  ko "PN-1 real=$REAL_PN1 exp=$EXP_PN1 events=[$EVPN1]"
fi

# PN-2: dated id that does NOT resolve — stripped claude-bogus-9 is absent
# from pricing.tsv too -> ONE unmeasurable event, reason "unknown
# pricing_id" (never a guessed price).
Tpn2=$(mktemp -d); mkdir -p "$Tpn2/s/subagents"
echo '{"agentType":"grunt","spawnDepth":1}' > "$Tpn2/s/subagents/agent-pn2.meta.json"
cat > "$Tpn2/s/subagents/agent-pn2.jsonl" << 'TXPN2'
{"message":{"id":"pn2a","model":"claude-bogus-9-20251001","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TXPN2
Apn2="$(mktemp -d)"; printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Apn2/butin-config.json"
echo "{\"session_id\":\"PN2\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$Tpn2/s/subagents/agent-pn2.jsonl\"}" \
  | AMIRAL_HOME="$Apn2" bash "$HERE/adapters/claude-code/butin-receipt.sh"
AMIRAL_HOME="$Apn2" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
EVPN2=$(cat "$Apn2/butin.jsonl" 2>/dev/null)
EVCOUNT_PN2=$(grep -c '.' <<< "$EVPN2")
if [ "$EVCOUNT_PN2" = "1" ] && echo "$EVPN2" | grep -q '"unmeasurable": true' \
   && echo "$EVPN2" | grep -q '"reason": "unknown pricing_id"' \
   && ! echo "$EVPN2" | grep -q '"real_cost_usd"'; then
  ok "PN-2 dated id does not resolve (stripped claude-bogus-9 absent): single unmeasurable event, no guessed price"
else
  ko "PN-2 events=[$EVPN2]"
fi

# PN-3: undated unknown id — no 8-digit suffix, so no normalization is even
# attempted; stays unmeasurable, no crash.
Tpn3=$(mktemp -d); mkdir -p "$Tpn3/s/subagents"
echo '{"agentType":"grunt","spawnDepth":1}' > "$Tpn3/s/subagents/agent-pn3.meta.json"
cat > "$Tpn3/s/subagents/agent-pn3.jsonl" << 'TXPN3'
{"message":{"id":"pn3a","model":"claude-bogus","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TXPN3
Apn3="$(mktemp -d)"; printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$Apn3/butin-config.json"
echo "{\"session_id\":\"PN3\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$Tpn3/s/subagents/agent-pn3.jsonl\"}" \
  | AMIRAL_HOME="$Apn3" bash "$HERE/adapters/claude-code/butin-receipt.sh"
OUTPN3=$(AMIRAL_HOME="$Apn3" python3 "$HERE/lib/butin/measure.py" 2>&1); RCPN3=$?
EVPN3=$(cat "$Apn3/butin.jsonl" 2>/dev/null)
if [ "$RCPN3" = "0" ] && ! grep -qi traceback <<< "$OUTPN3" \
   && echo "$EVPN3" | grep -q '"unmeasurable": true' \
   && echo "$EVPN3" | grep -q '"reason": "unknown pricing_id"' \
   && ! echo "$EVPN3" | grep -q '"billed_pricing_id"'; then
  ok "PN-3 undated unknown id: unmeasurable, no crash, no normalization attempted"
else
  ko "PN-3 rc=$RCPN3 out=[$OUTPN3] events=[$EVPN3]"
fi


# ─── v0.17.0 date-aware pricing (measure.py resolve_rate()/cost() pick the
# rate by the EVENT'S OWN ts, never by the date the measurement is RUN).
# pricing.tsv rows may carry an OPTIONAL 6th column, effective_from — the
# same receipts + transcripts must always reprice to the same dollar
# (REPRODUCIBLE), so history is never repriced by "now".
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"

# Shared fixture for DA-1/DA-2: one turn, model claude-sonnet-5,
# in=1000 out=500 cache_read=200 cache_write=100.
#   intro rate    (undated base row):  in=0.000002 out=0.00001   cw=0.0000025  cr=0.0000002
#     1000*0.000002 + 500*0.00001 + 100*0.0000025 + 200*0.0000002
#   =    0.002      +   0.005     +   0.00025      +   0.00004    = 0.00729
#   standard rate (effective_from 2026-09-01): in=0.000003 out=0.000015 cw=0.00000375 cr=0.0000003
#     1000*0.000003 + 500*0.000015 + 100*0.00000375 + 200*0.0000003
#   =    0.003      +   0.0075     +   0.000375      +   0.00006    = 0.010935
DA_TX_LINE='{"message":{"id":"m1","model":"claude-sonnet-5","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":200,"cache_creation_input_tokens":100}}}'

# DA-1: event dated 2026-08-15 (before the 2026-09-01 cutover) -> intro rate.
ADA1="$(mktemp -d)"; TDA1="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$ADA1/butin-config.json"
printf '%s\n' "$DA_TX_LINE" > "$TDA1/agent-da1.jsonl"
printf '{"v":2,"id":"da1","ts":"2026-08-15T12:00:00Z","role":"worker","session":"s","agent_hint":"grunt","transcript":"%s","cwd":"/x","measured":false}\n' "$TDA1/agent-da1.jsonl" > "$ADA1/receipts.jsonl"
AMIRAL_HOME="$ADA1" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
REAL_DA1=$(grep -oE '"real_cost_usd": [0-9.eE+-]+' "$ADA1/butin.jsonl" 2>/dev/null | sed 's/.*: //')
if [ "$REAL_DA1" = "0.00729" ]; then
  ok "DA-1 receipt dated 2026-08-15 (pre-cutover) measures at the intro rate (real_cost_usd=0.00729)"
else
  ko "DA-1 real=$REAL_DA1 events=[$(cat "$ADA1/butin.jsonl" 2>/dev/null)]"
fi

# DA-2: IDENTICAL tokens, event dated 2026-09-15 (on/after the cutover) ->
# standard rate, a DIFFERENT real_cost_usd than DA-1's.
ADA2="$(mktemp -d)"; TDA2="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$ADA2/butin-config.json"
printf '%s\n' "$DA_TX_LINE" > "$TDA2/agent-da2.jsonl"
printf '{"v":2,"id":"da2","ts":"2026-09-15T12:00:00Z","role":"worker","session":"s","agent_hint":"grunt","transcript":"%s","cwd":"/x","measured":false}\n' "$TDA2/agent-da2.jsonl" > "$ADA2/receipts.jsonl"
AMIRAL_HOME="$ADA2" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
REAL_DA2=$(grep -oE '"real_cost_usd": [0-9.eE+-]+' "$ADA2/butin.jsonl" 2>/dev/null | sed 's/.*: //')
if [ "$REAL_DA2" = "0.010935" ] && [ "$REAL_DA2" != "$REAL_DA1" ]; then
  ok "DA-2 identical tokens dated 2026-09-15 (post-cutover) measures at the standard rate (real_cost_usd=0.010935, != DA-1)"
else
  ko "DA-2 real=$REAL_DA2 (DA-1=$REAL_DA1) events=[$(cat "$ADA2/butin.jsonl" 2>/dev/null)]"
fi

# DA-3: a malformed effective_from row is SKIPPED ENTIRELY at load time —
# the model still prices from its undated base row. Own temp pricing.tsv
# (real table untouched): a valid base row for a synthetic pricing_id
# (in=0.000001 out=0.000005 cw=0.00000125 cr=0.0000001) plus a
# garbage-dated second row ("2026-9-1", not zero-padded YYYY-MM-DD) at a
# conspicuously different, far pricier rate — if the parser ever let the
# bad row through, the cost below would be wildly off, not 0.003645.
#   1000*0.000001 + 500*0.000005 + 100*0.00000125 + 200*0.0000001
# =    0.001      +   0.0025     +   0.000125      +   0.00002    = 0.003645
TPDA3="$(mktemp -d)/pricing.tsv"; cp "$HERE/lib/butin/pricing.tsv" "$TPDA3"
printf 'claude-testbad-1\t0.000001\t0.000005\t0.00000125\t0.0000001\n' >> "$TPDA3"
printf 'claude-testbad-1\t0.0009\t0.0009\t0.0009\t0.0009\t2026-9-1\n' >> "$TPDA3"
ADA3="$(mktemp -d)"; TDA3="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$ADA3/butin-config.json"
printf '{"message":{"id":"m1","model":"claude-testbad-1","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":200,"cache_creation_input_tokens":100}}}\n' > "$TDA3/agent-da3.jsonl"
printf '{"v":2,"id":"da3","ts":"2026-09-15T12:00:00Z","role":"worker","session":"s","agent_hint":"grunt","transcript":"%s","cwd":"/x","measured":false}\n' "$TDA3/agent-da3.jsonl" > "$ADA3/receipts.jsonl"
AMIRAL_HOME="$ADA3" BUTIN_PRICES="$TPDA3" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
REAL_DA3=$(grep -oE '"real_cost_usd": [0-9.eE+-]+' "$ADA3/butin.jsonl" 2>/dev/null | sed 's/.*: //')
if [ "$REAL_DA3" = "0.003645" ]; then
  ok "DA-3 malformed effective_from (2026-9-1) row skipped entirely: model still prices from its base row (0.003645)"
else
  ko "DA-3 real=$REAL_DA3 events=[$(cat "$ADA3/butin.jsonl" 2>/dev/null)]"
fi

# DA-4: a model with ONLY a future-dated row (no base row) and an event
# BEFORE that date -> unmeasurable "unknown pricing_id", never a guessed
# rate. Own temp pricing.tsv, one row, effective_from far in the future.
TPDA4="$(mktemp -d)/pricing.tsv"; cp "$HERE/lib/butin/pricing.tsv" "$TPDA4"
printf 'claude-futureonly-1\t0.00002\t0.0001\t0.000025\t0.000002\t2027-01-01\n' >> "$TPDA4"
ADA4="$(mktemp -d)"; TDA4="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$ADA4/butin-config.json"
printf '{"message":{"id":"m1","model":"claude-futureonly-1","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$TDA4/agent-da4.jsonl"
printf '{"v":2,"id":"da4","ts":"2026-08-01T12:00:00Z","role":"worker","session":"s","agent_hint":"grunt","transcript":"%s","cwd":"/x","measured":false}\n' "$TDA4/agent-da4.jsonl" > "$ADA4/receipts.jsonl"
AMIRAL_HOME="$ADA4" BUTIN_PRICES="$TPDA4" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
EVDA4=$(cat "$ADA4/butin.jsonl" 2>/dev/null)
if echo "$EVDA4" | grep -q '"unmeasurable": true' && echo "$EVDA4" | grep -q '"reason": "unknown pricing_id"' \
   && echo "$EVDA4" | grep -q 'claude-futureonly-1' && ! echo "$EVDA4" | grep -q '"real_cost_usd"'; then
  ok "DA-4 model with only a future-dated row + event before it: unmeasurable unknown pricing_id, never a guessed rate"
else
  ko "DA-4 events=[$EVDA4]"
fi

# DA-5: the HOT collector path (adapters/claude-code/butin-collect.sh) is
# ALSO date-aware now — same regression class as DA-1..DA-4, just a second
# consumer of a multi-row pricing.tsv. Own CLAUDE_CONFIG_DIR/butin/
# pricing.tsv (butin-collect.sh has no BUTIN_PRICES override, only the
# CLAUDE_CONFIG_DIR/butin/... resolution — a "butin" subdir is required or
# it silently falls back to the repo table), hermetic, no real files
# touched. A synthetic 2-row model with one row far in the PAST
# (2020-01-01) and one far in the FUTURE (2099-01-01) makes the assertion
# stable regardless of the real date this suite runs on: "today" always
# falls between them, so the far-past row is always the correct pick — and
# its rate is deliberately far cheaper than the future row's, so picking
# the wrong one would be obvious (0.9-ish vs 0.002).
#   in=1000 out=500 cache_read=0 cache_write=0, far-past rate in=0.000001
#   out=0.000002 (cache columns unused since cr=cw=0 tokens):
#     1000*0.000001 + 500*0.000002 = 0.001 + 0.001 = 0.002 -> "%.6f" = 0.002000
CFGDA5="$(mktemp -d)"; mkdir -p "$CFGDA5/butin"
printf '# pricing_version: test-DA5\n' > "$CFGDA5/butin/pricing.tsv"
printf 'claude-datest-1\t0.000001\t0.000002\t0.0000005\t0.00000005\t2020-01-01\n' >> "$CFGDA5/butin/pricing.tsv"
printf 'claude-datest-1\t0.0009\t0.0009\t0.0009\t0.0009\t2099-01-01\n' >> "$CFGDA5/butin/pricing.tsv"
printf 'claude-baseline-x\t0.00002\t0.00004\t0\t0\n' >> "$CFGDA5/butin/pricing.tsv"
ADA5="$(mktemp -d)"; TDA5="$(mktemp -d)"
printf '{"baseline_model":"claude-baseline-x","mode":"api"}\n' > "$ADA5/butin-config.json"
cat > "$TDA5/agent-collect.jsonl" << 'TXDA5'
{"type":"user","message":{"role":"user","content":"do the task"}}
{"type":"assistant","message":{"model":"claude-datest-1","role":"assistant","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TXDA5
PLDA5="{\"session_id\":\"DA5\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$TDA5/agent-collect.jsonl\"}"
echo "$PLDA5" | AMIRAL_HOME="$ADA5" CLAUDE_CONFIG_DIR="$CFGDA5" bash "$HERE/adapters/claude-code/butin-collect.sh"
LDA5=$(cat "$ADA5/butin.jsonl" 2>/dev/null)
REAL_DA5=$(echo "$LDA5" | grep -oE '"real_cost_usd":[0-9.eE+-]+' | sed 's/.*://')
if [ "$REAL_DA5" = "0.002000" ]; then
  ok "DA-5 hot collector path picks the eligible row for TODAY on a 2-row model (real_cost_usd=0.002000, not the far-future rate)"
else
  ko "DA-5 real=$REAL_DA5 events=[$LDA5]"
fi

# DA-6: bin/amiral-butin config --show with a 2-row baseline (real
# claude-sonnet-5) prints exactly ONE row's rates — not two printf blocks
# concatenated with no separator. The expected row is derived the SAME way
# the implementation picks it (greatest effective_from <= today, else the
# undated base), so this assertion is correct on any day the suite runs,
# not just today.
ACDA6="$(mktemp -d)"; cp "$HERE/lib/butin/pricing.tsv" "$ACDA6/"   # no "butin/" subdir -> falls back to the repo table, same pattern as $AC elsewhere in this file
ADA6="$(mktemp -d)"
AMIRAL_HOME="$ADA6" CLAUDE_CONFIG_DIR="$ACDA6" bash "$HERE/bin/amiral-butin" config --baseline claude-sonnet-5 --mode api >/dev/null
SHOWDA6=$(AMIRAL_HOME="$ADA6" CLAUDE_CONFIG_DIR="$ACDA6" NO_COLOR=1 bash "$HERE/bin/amiral-butin" config --show)
TODAY_DA6=$(date -u +%F)
EXP_DA6=$(awk -F'\t' -v today="$TODAY_DA6" '
  $1=="claude-sonnet-5" {
    if (NF < 6) { eff = "" } else { eff = $6; if (eff !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) next }
    if (eff == "" || eff <= today) { if (!found || eff > best) { best=eff; bi=$2; bo=$3; bcw=$4; bcr=$5; found=1 } }
  }
  END { if (found) printf "in=%s out=%s cache_write=%s cache_read=%s ($/tok)", bi, bo, bcw, bcr }
' "$HERE/lib/butin/pricing.tsv")
RATE_MATCHES_DA6=$(echo "$SHOWDA6" | grep -oE 'in=[0-9.eE+-]+ out=[0-9.eE+-]+ cache_write=[0-9.eE+-]+ cache_read=[0-9.eE+-]+ \(\$/tok\)')
RATE_COUNT_DA6=$(printf '%s\n' "$RATE_MATCHES_DA6" | grep -c '.')
if [ "$RATE_COUNT_DA6" = "1" ] && [ "$RATE_MATCHES_DA6" = "$EXP_DA6" ]; then
  ok "DA-6 config --show with a 2-row baseline (claude-sonnet-5) prints exactly one row's rates ($RATE_MATCHES_DA6)"
else
  ko "DA-6 count=$RATE_COUNT_DA6 matches=[$RATE_MATCHES_DA6] exp=[$EXP_DA6] show=[$SHOWDA6]"
fi


# ─── v0.15 amiral-butin backfill: mint worker receipts for PAST sessions'
# real subagent transcripts (live discovery only ever scans the CURRENT
# session — every session that already ended stays invisible to it
# forever). Same rules as live discovery: hostile-path guard, stable-gate,
# dedup against both receipts.jsonl and butin.jsonl. Mints ONLY, never
# measures.
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"

# BF-1: --dry-run computes everything but writes NOTHING (no receipts.jsonl,
# no butin.jsonl) yet reports a correct would-mint count.
BFP1="$(mktemp -d)"
mkdir -p "$BFP1/projects/-tmp-bf1proj/sessA/subagents"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' \
  > "$BFP1/projects/-tmp-bf1proj/sessA/subagents/agent-a1.jsonl"
touch -t 202601010000 "$BFP1/projects/-tmp-bf1proj/sessA/subagents/agent-a1.jsonl"
BFH1="$(mktemp -d)"
OUT_BF1=$(AMIRAL_HOME="$BFH1" CLAUDE_CONFIG_DIR="$BFP1" python3 "$HERE/lib/butin/backfill.py" --all --dry-run)
if [ ! -f "$BFH1/receipts.jsonl" ] && [ ! -f "$BFH1/butin.jsonl" ] \
   && echo "$OUT_BF1" | grep -qi "dry-run" \
   && echo "$OUT_BF1" | grep -qE "would mint: 1"; then
  ok "BF-1 --dry-run writes nothing (no receipts.jsonl/butin.jsonl) yet reports correct would-mint count"
else
  ko "BF-1 out=[$OUT_BF1] receipts=$( [ -f "$BFH1/receipts.jsonl" ] && echo present || echo absent )"
fi

# BF-2: real run mints a receipt for the planted transcript; second run is
# idempotent (0 new). Then measure.py prices it with sidecar identity.
BFP2="$(mktemp -d)"
mkdir -p "$BFP2/projects/-tmp-bf2proj/sessB/subagents"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' \
  > "$BFP2/projects/-tmp-bf2proj/sessB/subagents/agent-b1.jsonl"
echo '{"agentType":"grunt","spawnDepth":1}' > "$BFP2/projects/-tmp-bf2proj/sessB/subagents/agent-b1.meta.json"
touch -t 202601010000 "$BFP2/projects/-tmp-bf2proj/sessB/subagents/agent-b1.jsonl"
BFH2="$(mktemp -d)"
OUT_BF2A=$(AMIRAL_HOME="$BFH2" CLAUDE_CONFIG_DIR="$BFP2" python3 "$HERE/lib/butin/backfill.py" --all)
RCPT_B1=$(grep -c "agent-b1.jsonl" "$BFH2/receipts.jsonl" 2>/dev/null); RCPT_B1=${RCPT_B1:-0}
OUT_BF2B=$(AMIRAL_HOME="$BFH2" CLAUDE_CONFIG_DIR="$BFP2" python3 "$HERE/lib/butin/backfill.py" --all)
LINES_AFTER=$(wc -l < "$BFH2/receipts.jsonl" | tr -d ' ')
if [ "$RCPT_B1" = "1" ] && echo "$OUT_BF2A" | grep -qE "minted: 1" \
   && echo "$OUT_BF2B" | grep -qE "minted: 0" && [ "$LINES_AFTER" = "1" ]; then
  ok "BF-2a real run mints receipt for planted transcript; second run idempotent (0 new)"
else
  ko "BF-2a rcpt_b1=$RCPT_B1 lines_after=$LINES_AFTER out1=[$OUT_BF2A] out2=[$OUT_BF2B]"
fi
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$BFH2/butin-config.json"
AMIRAL_HOME="$BFH2" python3 "$HERE/lib/butin/measure.py" >/dev/null 2>&1
if grep -q '"agent": "grunt"' "$BFH2/butin.jsonl" 2>/dev/null && grep -q '"real_cost_usd"' "$BFH2/butin.jsonl" 2>/dev/null; then
  ok "BF-2b measure.py prices the backfilled receipt with sidecar identity (grunt)"
else
  ko "BF-2b events=[$(cat "$BFH2/butin.jsonl" 2>/dev/null)]"
fi

# BF-3: dedup — a transcript already present in butin.jsonl (measured) AND
# one already present in receipts.jsonl are both skipped, never re-minted.
BFP3="$(mktemp -d)"
mkdir -p "$BFP3/projects/-tmp-bf3proj/sessC/subagents"
T_MEASURED="$BFP3/projects/-tmp-bf3proj/sessC/subagents/agent-measured.jsonl"
T_RECEIPTED="$BFP3/projects/-tmp-bf3proj/sessC/subagents/agent-receipted.jsonl"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$T_MEASURED"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$T_RECEIPTED"
touch -t 202601010000 "$T_MEASURED" "$T_RECEIPTED"
BFH3="$(mktemp -d)"
printf '{"v":2,"receipt":"pre","ts":"2026-01-01T00:00:00Z","agent":"grunt","transcript":"%s","chosen_model":"claude-sonnet-5","real_cost_usd":0.001,"baseline_model":"claude-opus-4-8","counterfactual_cost_usd":0.002,"outcome":"ok"}\n' \
  "$T_MEASURED" > "$BFH3/butin.jsonl"
printf '{"v":2,"id":"already","ts":"2026-01-01T00:00:00Z","role":"worker","session":"sessC","agent_hint":"","transcript":"%s","cwd":"","measured":false}\n' \
  "$T_RECEIPTED" > "$BFH3/receipts.jsonl"
OUT_BF3=$(AMIRAL_HOME="$BFH3" CLAUDE_CONFIG_DIR="$BFP3" python3 "$HERE/lib/butin/backfill.py" --all)
NEW_MEASURED=$(grep -c "agent-measured.jsonl" "$BFH3/receipts.jsonl" 2>/dev/null); NEW_MEASURED=${NEW_MEASURED:-0}
COUNT_RECEIPTED=$(grep -c "agent-receipted.jsonl" "$BFH3/receipts.jsonl" 2>/dev/null); COUNT_RECEIPTED=${COUNT_RECEIPTED:-0}
if [ "$NEW_MEASURED" = "0" ] && [ "$COUNT_RECEIPTED" = "1" ] && echo "$OUT_BF3" | grep -qE "already_known=2"; then
  ok "BF-3 dedup: already-measured + already-receipted transcripts both skipped, not re-minted"
else
  ko "BF-3 out=[$OUT_BF3] receipts=[$(cat "$BFH3/receipts.jsonl" 2>/dev/null)]"
fi

# BF-4: hostile filename (embedded double-quote) is skipped, never minted.
BFP4="$(mktemp -d)"
mkdir -p "$BFP4/projects/-tmp-bf4proj/sessD/subagents"
HOSTILE_BF="$BFP4/projects/-tmp-bf4proj/sessD/subagents/agent-x\"quote.jsonl"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$HOSTILE_BF"
touch -t 202601010000 "$HOSTILE_BF"
BFH4="$(mktemp -d)"
OUT_BF4=$(AMIRAL_HOME="$BFH4" CLAUDE_CONFIG_DIR="$BFP4" python3 "$HERE/lib/butin/backfill.py" --all)
HOSTILE_MINTED=no
grep -qF 'agent-x"quote.jsonl' "$BFH4/receipts.jsonl" 2>/dev/null && HOSTILE_MINTED=yes
if [ "$HOSTILE_MINTED" = "no" ] && echo "$OUT_BF4" | grep -qE "hostile=1"; then
  ok "BF-4 hostile filename (embedded quote) skipped, never minted"
else
  ko "BF-4 out=[$OUT_BF4] receipts=[$(cat "$BFH4/receipts.jsonl" 2>/dev/null)]"
fi

# BF-5: stable-gate — a fresh transcript (mtime=now) is held out under the
# default 60s gate, never minted warm.
BFP5="$(mktemp -d)"
mkdir -p "$BFP5/projects/-tmp-bf5proj/sessE/subagents"
T_FRESH="$BFP5/projects/-tmp-bf5proj/sessE/subagents/agent-fresh.jsonl"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$T_FRESH"
BFH5="$(mktemp -d)"
OUT_BF5=$(AMIRAL_HOME="$BFH5" CLAUDE_CONFIG_DIR="$BFP5" python3 "$HERE/lib/butin/backfill.py" --all)
FRESH_MINTED=no
grep -qF "agent-fresh.jsonl" "$BFH5/receipts.jsonl" 2>/dev/null && FRESH_MINTED=yes
if [ "$FRESH_MINTED" = "no" ] && echo "$OUT_BF5" | grep -qE "streaming=1"; then
  ok "BF-5 stable-gate: fresh transcript (mtime=now) held out under the default 60s gate"
else
  ko "BF-5 out=[$OUT_BF5] receipts=[$(cat "$BFH5/receipts.jsonl" 2>/dev/null)]"
fi

# BF-6: default scope (cwd-mangled project only) vs --all (every project).
# The mangle must match backfill.py's own os.getcwd() — computed via
# python3 too, so a symlinked tmp dir (e.g. macOS /var -> /private/var)
# can't desync the test from the real behavior.
BF6ROOT="$(mktemp -d)"
BF6REPO="$(mktemp -d)"
REALCWD=$(cd "$BF6REPO" && python3 -c 'import os; print(os.getcwd())')
MANGLED=$(printf '%s' "$REALCWD" | tr '/.' '-')
mkdir -p "$BF6ROOT/projects/$MANGLED/sessF/subagents"
mkdir -p "$BF6ROOT/projects/-some-other-project/sessG/subagents"
T_OWN="$BF6ROOT/projects/$MANGLED/sessF/subagents/agent-own.jsonl"
T_OTHER="$BF6ROOT/projects/-some-other-project/sessG/subagents/agent-other.jsonl"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$T_OWN"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$T_OTHER"
touch -t 202601010000 "$T_OWN" "$T_OTHER"
BFH6="$(mktemp -d)"
OUT_BF6D=$(cd "$BF6REPO" && AMIRAL_HOME="$BFH6" CLAUDE_CONFIG_DIR="$BF6ROOT" python3 "$HERE/lib/butin/backfill.py")
OWN_MINTED=no; OTHER_MINTED=no
grep -qF "agent-own.jsonl" "$BFH6/receipts.jsonl" 2>/dev/null && OWN_MINTED=yes
grep -qF "agent-other.jsonl" "$BFH6/receipts.jsonl" 2>/dev/null && OTHER_MINTED=yes
if [ "$OWN_MINTED" = "yes" ] && [ "$OTHER_MINTED" = "no" ]; then
  ok "BF-6a default scope: mints only the cwd-mangled project's transcripts"
else
  ko "BF-6a own=$OWN_MINTED other=$OTHER_MINTED out=[$OUT_BF6D] receipts=[$(cat "$BFH6/receipts.jsonl" 2>/dev/null)]"
fi
BFH6B="$(mktemp -d)"
OUT_BF6A=$(cd "$BF6REPO" && AMIRAL_HOME="$BFH6B" CLAUDE_CONFIG_DIR="$BF6ROOT" python3 "$HERE/lib/butin/backfill.py" --all)
OWN_MINTED_B=no; OTHER_MINTED_B=no
grep -qF "agent-own.jsonl" "$BFH6B/receipts.jsonl" 2>/dev/null && OWN_MINTED_B=yes
grep -qF "agent-other.jsonl" "$BFH6B/receipts.jsonl" 2>/dev/null && OTHER_MINTED_B=yes
if [ "$OWN_MINTED_B" = "yes" ] && [ "$OTHER_MINTED_B" = "yes" ]; then
  ok "BF-6b --all: mints across both projects"
else
  ko "BF-6b own=$OWN_MINTED_B other=$OTHER_MINTED_B out=[$OUT_BF6A] receipts=[$(cat "$BFH6B/receipts.jsonl" 2>/dev/null)]"
fi

# BF-7 (review fix): BUTIN_STABLE_SECS=abc must not crash the run — falls
# back to the documented 60s default (guarded exactly like measure.py
# guards BUTIN_RECEIPT_TTL_HOURS).
BFP7="$(mktemp -d)"
mkdir -p "$BFP7/projects/-tmp-bf7proj/sessH/subagents"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' \
  > "$BFP7/projects/-tmp-bf7proj/sessH/subagents/agent-h1.jsonl"
touch -t 202601010000 "$BFP7/projects/-tmp-bf7proj/sessH/subagents/agent-h1.jsonl"
BFH7="$(mktemp -d)"
OUT_BF7=$(AMIRAL_HOME="$BFH7" CLAUDE_CONFIG_DIR="$BFP7" BUTIN_STABLE_SECS=abc python3 "$HERE/lib/butin/backfill.py" --all --dry-run 2>&1); RC_BF7=$?
if [ "$RC_BF7" = "0" ] && ! grep -qi traceback <<< "$OUT_BF7" && echo "$OUT_BF7" | grep -qE "would mint: 1"; then
  ok "BF-7 BUTIN_STABLE_SECS=abc: no crash, falls back to the 60s default (dry-run still would-mint 1)"
else
  ko "BF-7 rc=$RC_BF7 out=[$OUT_BF7]"
fi

# BF-8 (review fix — FIX 1): lock coordination with measure.py. A FRESH
# ${AMIRAL_HOME}/.measure.lock (mtime=now, not stale) must block a real
# (non-dry) backfill entirely: mints NOTHING, exits 0 (busy back-off),
# foreign lock left in place. Removing the lock lets a subsequent real run
# mint as expected — proving the lock is advisory/cooperative, not a
# permanent wedge.
BFP8="$(mktemp -d)"
mkdir -p "$BFP8/projects/-tmp-bf8proj/sessI/subagents"
T_BF8="$BFP8/projects/-tmp-bf8proj/sessI/subagents/agent-i1.jsonl"
printf '{"message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$T_BF8"
touch -t 202601010000 "$T_BF8"
BFH8="$(mktemp -d)"
mkdir -p "$BFH8/.measure.lock"   # fresh lock, mtime=now (not stale)
OUT_BF8A=$(AMIRAL_HOME="$BFH8" CLAUDE_CONFIG_DIR="$BFP8" python3 "$HERE/lib/butin/backfill.py" --all); RC_BF8A=$?
RCPT_BEFORE=$(grep -c "agent-i1.jsonl" "$BFH8/receipts.jsonl" 2>/dev/null); RCPT_BEFORE=${RCPT_BEFORE:-0}
LOCK_STILL_THERE=no; [ -d "$BFH8/.measure.lock" ] && LOCK_STILL_THERE=yes
if [ "$RC_BF8A" = "0" ] && [ "$RCPT_BEFORE" = "0" ] && echo "$OUT_BF8A" | grep -qi "busy" \
   && [ "$LOCK_STILL_THERE" = "yes" ]; then
  ok "BF-8a fresh lock present: real backfill mints nothing, exits 0 (busy back-off), lock untouched"
else
  ko "BF-8a rc=$RC_BF8A rcpt_before=$RCPT_BEFORE lock=$LOCK_STILL_THERE out=[$OUT_BF8A]"
fi
rm -rf "$BFH8/.measure.lock"
OUT_BF8B=$(AMIRAL_HOME="$BFH8" CLAUDE_CONFIG_DIR="$BFP8" python3 "$HERE/lib/butin/backfill.py" --all); RC_BF8B=$?
RCPT_AFTER=$(grep -c "agent-i1.jsonl" "$BFH8/receipts.jsonl" 2>/dev/null); RCPT_AFTER=${RCPT_AFTER:-0}
if [ "$RC_BF8B" = "0" ] && [ "$RCPT_AFTER" = "1" ] && echo "$OUT_BF8B" | grep -qE "minted: 1"; then
  ok "BF-8b after removing the lock, a real run mints as expected (0 -> 1 receipt)"
else
  ko "BF-8b rc=$RC_BF8B rcpt_after=$RCPT_AFTER out=[$OUT_BF8B]"
fi


# ─── v0.15 attribution split: NET must never credit amiral for subagent
# activity it did not route (Claude Code built-ins, other tooling, a
# user's own custom agent). AMIRAL_AGENTS partitions core.awk's output;
# unset/empty must stay byte-identical to the pre-v0.15 mixed accounting
# (legacy safety — every existing caller above never passes it). ───
cat > "$AMIRAL_HOME/attrib.jsonl" << 'EOF'
{"v":1,"id":"at1","agent":"grunt","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"at2","agent":"implementer","real_cost_usd":0.02,"counterfactual_cost_usd":0.10,"outcome":"ok"}
{"v":1,"id":"at3","agent":"general-purpose","real_cost_usd":0.03,"counterfactual_cost_usd":0.09,"outcome":"ok"}
{"v":1,"id":"at4","agent":"Explore","chosen_model":"claude-haiku-4-5","real_cost_usd":0.01,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.02,"outcome":"escalated","escalation_extra_usd":0.005}
{"v":1,"id":"at5","agent":"fullstack-dev","real_cost_usd":0.02,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"at6","agent":"brain","real_cost_usd":0.05,"counterfactual_cost_usd":0.01,"outcome":"ok"}
EOF
ATTRIB_REPORT=$(awk -v AMIRAL_AGENTS="grunt,implementer,reviewer,corsaire,advisor" -f "$HERE/lib/butin/core.awk" "$AMIRAL_HOME/attrib.jsonl")
A_NET=$(echo "$ATTRIB_REPORT" | awk -F'\t' '/^NET/{print $2}')
A_ONET=$(echo "$ATTRIB_REPORT" | awk -F'\t' '/^OTHER_NET/{print $2}')
A_OTASKS=$(echo "$ATTRIB_REPORT" | awk -F'\t' '/^OTHER_TASKS/{print $2}')
A_AGENTS_BLOCK=$(echo "$ATTRIB_REPORT" | awk '/^AGENTS_START/{p=1;next} /^AGENTS_END/{p=0;next} p')
A_OTHER_BLOCK=$(echo "$ATTRIB_REPORT" | awk '/^OTHER_START/{p=1;next} /^OTHER_END/{p=0;next} p')
if awk "BEGIN{exit !($A_NET>0.079 && $A_NET<0.081)}"; then
  ok "V15 NET excludes foreign+custom agents (amiral-only: (0.15-0.03)-0-0.04=0.08, net=$A_NET)"
else
  ko "V15 NET wrong: $A_NET (want ~0.08)"
fi
if awk "BEGIN{exit !($A_ONET>0.0949 && $A_ONET<0.0951)}"; then
  ok "V15 OTHER_NET includes foreign+custom exactly ((0.16-0.06)-0.005=0.095, other_net=$A_ONET)"
else
  ko "V15 OTHER_NET wrong: $A_ONET (want ~0.095)"
fi
[ "${A_OTASKS:-0}" = "3" ] && ok "V15 OTHER_TASKS counts the 3 non-amiral worker events" || ko "V15 OTHER_TASKS=$A_OTASKS (want 3)"
if echo "$A_AGENTS_BLOCK" | grep -q '^grunt' && echo "$A_AGENTS_BLOCK" | grep -q '^implementer' \
   && ! echo "$A_AGENTS_BLOCK" | grep -qE '^(general-purpose|Explore|fullstack-dev)'; then
  ok "V15 AGENTS_START holds only amiral agents (grunt, implementer)"
else
  ko "V15 AGENTS_START wrong: [$A_AGENTS_BLOCK]"
fi
if echo "$A_OTHER_BLOCK" | grep -q '^general-purpose' && echo "$A_OTHER_BLOCK" | grep -q '^Explore' \
   && echo "$A_OTHER_BLOCK" | grep -q '^fullstack-dev' && ! echo "$A_OTHER_BLOCK" | grep -qE '^(grunt|implementer)'; then
  ok "V15 OTHER_START holds the foreign built-ins + the unknown custom agent, never amiral's own"
else
  ko "V15 OTHER_START wrong: [$A_OTHER_BLOCK]"
fi
# brain premium (0.05-0.01=0.04) still deducted from the amiral NET only —
# already asserted above (0.08 bakes it in); confirm the BRAIN row itself too.
A_BRAIN=$(echo "$ATTRIB_REPORT" | awk -F'\t' '/^BRAIN/{print $3}')
awk "BEGIN{exit !($A_BRAIN>0.0399 && $A_BRAIN<0.0401)}" && ok "V15 brain premium still charged (0.04, neither bucket)" || ko "V15 brain premium=$A_BRAIN"

# legacy safety: no AMIRAL_AGENTS at all -> byte-identical to the OLD mixed
# NET (every worker, foreign included, all counted as amiral — the exact
# pre-v0.15 behavior every existing caller above still gets).
LEGACY_REPORT=$(awk -f "$HERE/lib/butin/core.awk" "$AMIRAL_HOME/attrib.jsonl")
L_NET=$(echo "$LEGACY_REPORT" | awk -F'\t' '/^NET/{print $2}')
# all non-brain real=0.09, cf=0.31, gross=0.22, esc=0.005, brain=0.04 -> net=0.175
if awk "BEGIN{exit !($L_NET>0.1749 && $L_NET<0.1751)}"; then
  ok "V15 legacy (no AMIRAL_AGENTS) reproduces the OLD mixed NET (0.175, no split)"
else
  ko "V15 legacy NET wrong: $L_NET (want ~0.175)"
fi
L_OTASKS=$(echo "$LEGACY_REPORT" | awk -F'\t' '/^OTHER_TASKS/{print $2}')
[ "${L_OTASKS:-x}" = "0" ] && ok "V15 legacy OTHER_TASKS=0 (split is a no-op when unset)" || ko "V15 legacy OTHER_TASKS=$L_OTASKS"

# ─── v0.16 phantom receipts: "transcript absent" is the tool's own noise,
# not lost work (v0.14 finding) — excluded from the coverage denominator,
# counted on its own PHANTOM line. "unknown pricing_id" (a genuine gap on
# real work) is untouched: stays in UNMEASURED and the denominator. ───

# PH-1: core.awk directly — 2 measured amiral events, 1 phantom-reason
# unmeasurable, 1 unknown-pricing-id unmeasurable.
APH1="$(mktemp -d)"
cat > "$APH1/phantom.jsonl" << 'EOF'
{"v":1,"id":"ph1","agent":"grunt","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}
{"v":1,"id":"ph2","agent":"grunt","real_cost_usd":0.02,"counterfactual_cost_usd":0.06,"outcome":"ok"}
{"v":1,"id":"ph3","unmeasurable":true,"reason":"transcript absent (never written or removed)"}
{"v":1,"id":"ph4","unmeasurable":true,"reason":"unknown pricing_id","model":"<synthetic>"}
EOF
PHREPORT=$(awk -f "$HERE/lib/butin/core.awk" "$APH1/phantom.jsonl")
PH_PHANTOM=$(echo "$PHREPORT" | awk -F'\t' '/^PHANTOM/{print $2}')
PH_UNMEAS=$(echo "$PHREPORT" | awk -F'\t' '/^UNMEASURED/{print $2}')
PH_MEAS=$(echo "$PHREPORT" | awk -F'\t' '/^MEASURED/{print $2}')
if [ "${PH_PHANTOM:-x}" = "1" ] && [ "${PH_UNMEAS:-x}" = "1" ] && [ "${PH_MEAS:-x}" = "2" ]; then
  ok "PH-1 core.awk: PHANTOM=1 (the transcript-absent event), UNMEASURED=1 (the pricing_id event, NOT the phantom), MEASURED=2"
else
  ko "PH-1 phantom=$PH_PHANTOM unmeas=$PH_UNMEAS meas=$PH_MEAS report=[$PHREPORT]"
fi

# PH-2: same fixture through the amiral-butin report — Coverage denominator
# (measured+unmeasured+pending) excludes the phantom (denominator=3, not 4),
# the unknown-pricing gap is still surfaced (unmeasured models line), and a
# dedicated phantom line appears, dim and clearly labelled.
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$APH1/butin-config.json"
mv "$APH1/phantom.jsonl" "$APH1/butin.jsonl"
OUTPH2=$(AMIRAL_HOME="$APH1" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
if echo "$OUTPH2" | grep -q "Coverage: 2/3 measured" \
   && echo "$OUTPH2" | grep -q "1 phantom receipt(s) excluded from coverage" \
   && echo "$OUTPH2" | grep -q "unmeasured models:.*<synthetic>"; then
  ok "PH-2 amiral-butin report: Coverage 2/3 (phantom excluded from denominator), phantom line shown, pricing gap still surfaced"
else
  ko "PH-2 out=[$(echo "$OUTPH2" | grep -i "coverage\|phantom\|unmeasured models")]"
fi

# PH-3: --detail carries the phantom/loss explanation bullet (v0.16.0 split).
OUTPH3=$(AMIRAL_HOME="$APH1" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin" --detail)
echo "$OUTPH3" | grep -q "Phantom vs loss" && ok "PH-3 --detail: phantom/loss honesty bullet present" || ko "PH-3 --detail missing phantom bullet"

# PH-4: butin-receipt.sh source fix — a worker receipt whose named transcript
# does NOT exist on disk at hook time is skipped (not minted); one whose
# transcript DOES exist is minted normally. Real temp file for the exists
# case, a bogus path for the absent case, same AMIRAL_HOME (isolates the
# dedup guard from the existence guard: two DIFFERENT transcript paths).
APH4="$(mktemp -d)"
TPH4="$(mktemp -d)"
EXIST_FILE="$TPH4/agent-real.jsonl"
printf '{"message":{"id":"x1","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$EXIST_FILE"
ABSENT_FILE="$TPH4/agent-absent.jsonl"   # deliberately never created
echo "{\"session_id\":\"PH4\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$EXIST_FILE\"}" \
  | AMIRAL_HOME="$APH4" bash "$HERE/adapters/claude-code/butin-receipt.sh"
echo "{\"session_id\":\"PH4\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$ABSENT_FILE\"}" \
  | AMIRAL_HOME="$APH4" bash "$HERE/adapters/claude-code/butin-receipt.sh"
PH4_LINES=$(grep -c '.' "$APH4/receipts.jsonl" 2>/dev/null); PH4_LINES=${PH4_LINES:-0}
if grep -qF "$EXIST_FILE" "$APH4/receipts.jsonl" 2>/dev/null \
   && ! grep -qF "$ABSENT_FILE" "$APH4/receipts.jsonl" 2>/dev/null \
   && [ "$PH4_LINES" = "1" ]; then
  ok "PH-4 butin-receipt.sh: existing-transcript worker receipt minted, absent-transcript worker receipt skipped (source fix)"
else
  ko "PH-4 receipts=[$(cat "$APH4/receipts.jsonl" 2>/dev/null)]"
fi
# PH-4b (v0.16.0): the ONE line that was minted (the existing-transcript
# case; the absent case never got a line to check) must carry
# "observed":true — the plain branch only reaches the printf when the file
# exists.
if grep -qF "$EXIST_FILE" "$APH4/receipts.jsonl" 2>/dev/null && grep -q '"observed":true' "$APH4/receipts.jsonl" 2>/dev/null; then
  ok "PH-4b plain-branch mint for an existing transcript carries \"observed\":true"
else
  ko "PH-4b receipts=[$(cat "$APH4/receipts.jsonl" 2>/dev/null)]"
fi

# manifest == agents/ (mirrors the CI guard; catches drift locally too)
MANIFEST_DIFF=$(diff <(sort "$HERE/lib/butin/amiral-agents.txt") <(ls "$HERE"/agents/*.md | xargs -n1 basename | sed 's/\.md$//' | sort))
[ -z "$MANIFEST_DIFF" ] && ok "V15 lib/butin/amiral-agents.txt matches agents/*.md exactly" || ko "V15 manifest drift: $MANIFEST_DIFF"

# ─── v0.16.0 (audit M7): core.awk must be correct-by-construction under any
# locale, not merely by the LC_ALL=C caller convention — that convention
# already failed on this repo's own doc author, and ports/BUTIN.md invites
# third parties to invoke core.awk directly. LC_ALL=C is exported at the top
# of THIS test file (line 5) for every other test's sake, so this one block
# runs in a subshell with its own LC_ALL to actually exercise the guard. ───
AM7="$(mktemp -d)"
printf '{"v":1,"id":"m7","agent":"grunt","real_cost_usd":1.5,"counterfactual_cost_usd":2.75,"outcome":"ok"}\n' > "$AM7/m7.jsonl"
# NOT `grep -q`: under `set -o pipefail`, grep -q's early exit on first match
# SIGPIPEs the still-writing `locale -a` (288 lines), and pipefail then
# reports the PIPELINE as failed (rightmost non-zero exit, which is locale
# -a's 141 from the SIGPIPE) even though grep DID find the match. Let grep
# run to completion (output binned to /dev/null) instead.
if locale -a 2>/dev/null | grep -i '^fr_FR' >/dev/null; then
  M7LOC=fr_FR.UTF-8
elif locale -a 2>/dev/null | grep -i '^de_DE' >/dev/null; then
  M7LOC=de_DE.UTF-8
else
  M7LOC=""
fi
if [ -n "$M7LOC" ]; then
  M7OUT=$(LC_ALL="$M7LOC" awk -f "$HERE/lib/butin/core.awk" "$AM7/m7.jsonl")
  M7NET=$(echo "$M7OUT" | awk -F'\t' '/^NET/{print $2}')
  if echo "$M7NET" | grep -q '\.' && ! echo "$M7NET" | grep -q ','; then
    ok "M7 comma-locale regression ($M7LOC): NET=$M7NET uses a period, never a comma"
  else
    ko "M7 comma-locale regression: NET=[$M7NET] under $M7LOC (want period, no comma)"
  fi
else
  # No comma-decimal locale installed on this machine (some CI images) —
  # never silently pass on nothing: fall back to a structural check that the
  # locale guard is actually present in the source, and say so explicitly.
  echo "  (M7: no fr_FR/de_DE locale available — falling back to a structural source check)"
  if grep -q 'gsub(/,/' "$HERE/lib/butin/core.awk"; then
    ok "M7 structural fallback: core.awk contains the comma->period locale guard (gsub(/,/...)"
  else
    ko "M7 structural fallback: locale guard (gsub(/,/...) not found in core.awk"
  fi
fi


# ─── v0.18.1 receipt-corruption fix: background_tasks[]'s duplicated
# "agent_type" used to leak through g()'s old whole-payload grep as a
# literal embedded newline in agent_hint, tearing one receipt into two
# physical lines. g() is now a top-level-only JSON scan; both
# transcript-claiming sites ignore a torn line instead of silently letting
# it block re-discovery forever; measure.py counts a torn line as `corrupt`,
# never `pending`; the report surfaces it. ───

# REPLAY: the real captured background-subagent SubagentStop payload
# (structure verbatim — only the three transcript/cwd placeholders are
# templated to test-local files) must mint exactly ONE clean receipt line.
ARP="$(mktemp -d)"
TRP="$(mktemp -d)"
MAIN_RP="$TRP/main.jsonl"; AGENT_RP="$TRP/agent-bg.jsonl"
printf '{"type":"user","message":{"role":"user","content":"ping"}}\n' > "$MAIN_RP"
printf '{"type":"assistant","message":{"model":"claude-sonnet-5","role":"assistant","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$AGENT_RP"
PLRP=$(sed "s|__MAIN_TRANSCRIPT__|$MAIN_RP|;s|__AGENT_TRANSCRIPT__|$AGENT_RP|;s|__CWD__|$TRP|" "$HERE/tests/fixtures/subagent-bg-payload.json")
echo "$PLRP" | AMIRAL_HOME="$ARP" bash "$HERE/adapters/claude-code/butin-receipt.sh"
RP_LINES=$(grep -c '.' "$ARP/receipts.jsonl" 2>/dev/null); RP_LINES=${RP_LINES:-0}
RP_LAST=$(tail -1 "$ARP/receipts.jsonl" 2>/dev/null)
if [ "$RP_LINES" = "1" ] \
   && python3 -c "import json,sys; json.loads(sys.argv[1])" "$RP_LAST" >/dev/null 2>&1 \
   && echo "$RP_LAST" | grep -q '"agent_hint":"general-purpose"'; then
  ok "REPLAY background-subagent payload: ONE clean receipt line, agent_hint=general-purpose (no torn newline)"
else
  ko "REPLAY lines=$RP_LINES receipts=[$(cat "$ARP/receipts.jsonl" 2>/dev/null)]"
fi

# TORN-LINE UNCLAIM: seed receipts.jsonl with the exact two-physical-line
# corrupt shape this bug used to write (a literal newline inside
# agent_hint), pointing at a real worker transcript with known usage. Run
# the brain Stop branch (discovery) over that transcript's session — the
# torn line must no longer block re-discovery: a fresh clean receipt is
# minted, and measure.py then measures it, WHILE the corrupt line stays
# byte-identically present (never destroyed) and is reported via `corrupt`.
ATL="$(mktemp -d)"
TTL="$(mktemp -d)"; mkdir -p "$TTL/STL/subagents"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$ATL/butin-config.json"
MAIN_TL="$TTL/STL.jsonl"
printf '{"type":"user","message":{"role":"user","content":"go"}}\n' > "$MAIN_TL"
AGENT_TL="$TTL/STL/subagents/agent-torn.jsonl"
echo '{"agentType":"grunt","spawnDepth":1}' > "$TTL/STL/subagents/agent-torn.meta.json"
printf '{"message":{"id":"tlm1","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$AGENT_TL"
TORN_HINT=$'general-purpose\ngeneral-purpose'
printf '{"v":2,"id":"torn1","ts":"%s","role":"worker","session":"STL","agent_hint":"%s","transcript":"%s","cwd":"%s","measured":false,"observed":true}\n' \
  "$(date -u +%FT%TZ)" "$TORN_HINT" "$AGENT_TL" "$TTL" > "$ATL/receipts.jsonl"
TL_CORRUPT_BEFORE="$(cat "$ATL/receipts.jsonl")"
echo "{\"session_id\":\"STL\",\"transcript_path\":\"$MAIN_TL\"}" \
  | AMIRAL_HOME="$ATL" bash "$HERE/adapters/claude-code/butin-receipt.sh" --brain
TL_DISCOVERED=no
grep -qF -- "$AGENT_TL" "$ATL/receipts.jsonl" 2>/dev/null && grep -q '"id":"torn1"' "$ATL/receipts.jsonl" 2>/dev/null && TL_DISCOVERED=yes
if [ "$TL_DISCOVERED" = "yes" ]; then
  ok "TORN-LINE UNCLAIM: discovery mints a fresh receipt for the torn line's transcript (torn line no longer blocks it)"
else
  ko "TORN-LINE UNCLAIM: receipts=[$(cat "$ATL/receipts.jsonl" 2>/dev/null)]"
fi
# The corrupt line's OWN second physical half also textually contains
# AGENT_TL (it carries the "transcript" kv) — a plain grep for the path
# would therefore "find" it forever, corrupt line or not. Capture the
# freshly-discovered CLEAN line's own id instead (the only line matching
# BOTH the AGENT_TL path and the ^{.*}$ anchor) so the post-measure.py
# drain check below is unambiguous.
DISC_ID=$(grep -E '^\{.*\}$' "$ATL/receipts.jsonl" 2>/dev/null | grep -F -- "$AGENT_TL" \
  | grep -oE '"id":"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
export BUTIN_PRICES="$HERE/lib/butin/pricing.tsv"
OUTTL=$(AMIRAL_HOME="$ATL" BUTIN_STABLE_SECS=0 python3 "$HERE/lib/butin/measure.py")
TL_MEASURED=no
grep -F -- "$AGENT_TL" "$ATL/butin.jsonl" 2>/dev/null | grep -q real_cost_usd && TL_MEASURED=yes
TL_AFTER="$(cat "$ATL/receipts.jsonl" 2>/dev/null)"
# The corrupt fixture's two physical lines are never reordered or rewritten
# — only appended-after content can ever separate them from later entries
# (here, the brain receipt for the main transcript, which stays pending:
# a plain "user" message carries no usage) — so TL_CORRUPT_BEFORE must
# still be an exact PREFIX of TL_AFTER, byte for byte.
TL_PREFIX_OK=no
case "$TL_AFTER" in "$TL_CORRUPT_BEFORE"*) TL_PREFIX_OK=yes ;; esac
TL_DRAINED=no
[ -n "$DISC_ID" ] && { grep -qF -- "\"$DISC_ID\"" "$ATL/receipts.jsonl" 2>/dev/null || TL_DRAINED=yes; }
if [ "$TL_MEASURED" = "yes" ] && [ "$TL_PREFIX_OK" = "yes" ] && [ "$TL_DRAINED" = "yes" ] && echo "$OUTTL" | grep -qE "corrupt [1-9]"; then
  ok "TORN-LINE UNCLAIM: re-discovered transcript measured (real_cost_usd) & drained, torn line byte-identical & counted as corrupt"
else
  ko "TORN-LINE UNCLAIM measure: measured=$TL_MEASURED prefix_ok=$TL_PREFIX_OK drained=$TL_DRAINED out=[$OUTTL] receipts_after=[$TL_AFTER] receipts_before=[$TL_CORRUPT_BEFORE]"
fi

# PLAIN-BRANCH dedup still works on CLEAN lines (no regression on F1 from
# the new anchor filter around the transcript-claim grep).
APD="$(mktemp -d)"
TPD="$(mktemp -d)"
PD_T="$TPD/agent-pd.jsonl"
printf '{"message":{"id":"pdm","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$PD_T"
echo "{\"session_id\":\"PD\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$PD_T\"}" \
  | AMIRAL_HOME="$APD" bash "$HERE/adapters/claude-code/butin-receipt.sh"
PD_FIRST=$(grep -c '.' "$APD/receipts.jsonl" 2>/dev/null); PD_FIRST=${PD_FIRST:-0}
echo "{\"session_id\":\"PD\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$PD_T\"}" \
  | AMIRAL_HOME="$APD" bash "$HERE/adapters/claude-code/butin-receipt.sh"
PD_SECOND=$(grep -c '.' "$APD/receipts.jsonl" 2>/dev/null); PD_SECOND=${PD_SECOND:-0}
if [ "$PD_FIRST" = "1" ] && [ "$PD_SECOND" = "1" ]; then
  ok "PLAIN-DEDUP: a clean receipt line still dedups a repeat worker hook firing (F1 unaffected by the torn-line anchor filter)"
else
  ko "PLAIN-DEDUP first=$PD_FIRST second=$PD_SECOND receipts=[$(cat "$APD/receipts.jsonl" 2>/dev/null)]"
fi

# REPORT WARNING: bin/amiral-butin surfaces a corrupt receipts.jsonl line;
# a clean ledger prints no such warning.
ARW="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$ARW/butin-config.json"
printf '{"v":1,"id":"rw1","agent":"grunt","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}\n' > "$ARW/butin.jsonl"
RW_HINT=$'general-purpose\ngeneral-purpose'
printf '{"v":2,"id":"rwc","ts":"%s","role":"worker","session":"s","agent_hint":"%s","transcript":"/x/agent-rw.jsonl","cwd":"/x","measured":false,"observed":true}\n' \
  "$(date -u +%FT%TZ)" "$RW_HINT" > "$ARW/receipts.jsonl"
OUTRW=$(AMIRAL_HOME="$ARW" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
echo "$OUTRW" | grep -q "corrupt receipt line" && ok "REPORT-WARN: corrupt receipts.jsonl line triggers the warning" || ko "REPORT-WARN missing warning: out=[$OUTRW]"
# v0.18.1: the torn line's SECOND physical half contains the literal text
# "measured":false — the report's PEND count anchors on valid ^{.*}$ lines,
# so a ledger whose only receipt is torn must show ZERO pending, not 1.
if echo "$OUTRW" | grep -q "awaiting measurement"; then
  ko "REPORT-WARN: torn line's second half inflated pending: out=[$OUTRW]"
else
  ok "REPORT-WARN: torn line's second half does not inflate pending (PEND anchors on valid lines)"
fi

ARW2="$(mktemp -d)"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$ARW2/butin-config.json"
printf '{"v":1,"id":"rw2","agent":"grunt","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}\n' > "$ARW2/butin.jsonl"
printf '{"v":2,"id":"rwok","ts":"%s","role":"worker","session":"s","agent_hint":"grunt","transcript":"/x/agent-ok.jsonl","cwd":"/x","measured":false,"observed":true}\n' "$(date -u +%FT%TZ)" > "$ARW2/receipts.jsonl"
OUTRW2=$(AMIRAL_HOME="$ARW2" CLAUDE_CONFIG_DIR="$AC" NO_COLOR=1 bash "$HERE/bin/amiral-butin")
if echo "$OUTRW2" | grep -q "corrupt receipt line"; then
  ko "REPORT-WARN: false positive on a clean ledger: out=[$OUTRW2]"
else
  ok "REPORT-WARN: clean ledger prints no corrupt-line warning"
fi

# EXTRACTOR tricky payload shapes: a last_assistant_message that contains
# the LITERAL JSON-escaped text \"agent_type\":\"forged\" must not leak into
# agent_hint (the real top-level agent_type must win), and a value ending in
# an escaped backslash immediately before the closing quote (\\") must not
# desync the scanner (proven here by the field extracting cleanly at all,
# AND by the real field still winning over the forged one).
TFORGE="$(mktemp -d)"
FORGE_T="$TFORGE/agent-forge.jsonl"
printf '{"message":{"id":"fm","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$FORGE_T"
PAYLOAD_FORGE='{"session_id":"FORGE","agent_type":"real-type","agent_transcript_path":"'"$FORGE_T"'","cwd":"/x","last_assistant_message":"before \"agent_type\":\"forged\" after, ends in a backslash\\"}'
AFORGE="$(mktemp -d)"
echo "$PAYLOAD_FORGE" | AMIRAL_HOME="$AFORGE" bash "$HERE/adapters/claude-code/butin-receipt.sh"
FORGE_LAST=$(tail -1 "$AFORGE/receipts.jsonl" 2>/dev/null)
if python3 -c "
import json,sys
d = json.loads(sys.argv[1])
sys.exit(0 if d.get('agent_hint') == 'real-type' else 1)
" "$FORGE_LAST" >/dev/null 2>&1; then
  ok 'EXTRACTOR: a forged \"agent_type\":\"forged\" inside last_assistant_message never leaks into agent_hint (real-type wins, scanner not desynced by \\")'
else
  ko "EXTRACTOR forged-payload leak: receipts=[$FORGE_LAST]"
fi


echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
