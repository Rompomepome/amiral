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

echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
