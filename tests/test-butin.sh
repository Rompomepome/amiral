#!/usr/bin/env bash
# butin critical-path battery. Self-contained, uses temp dirs.
export LC_ALL=C
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ok  $1"; PASS=$((PASS+1)); }
ko(){ echo "  KO  $1"; FAIL=$((FAIL+1)); }

export AMIRAL_HOME=$(mktemp -d)
mkdir -p "$AMIRAL_HOME"
cat > "$AMIRAL_HOME/butin-config.json" << 'CFG'
{ "baseline_model": "claude-sonnet-4-6", "baseline_source": "test", "mode": "api" }
CFG

# T1 — collector extracts the golden fixture exactly
echo "{\"session_id\":\"S1\",\"transcript_path\":\"$HERE/tests/fixtures/transcript-sample.jsonl\",\"subagent_type\":\"grunt\"}" \
  | bash "$HERE/adapters/claude-code/butin-collect.sh"
LINE=$(tail -1 "$AMIRAL_HOME/butin.jsonl")
echo "$LINE" | grep -q '"in":4210' && echo "$LINE" | grep -q '"out":1830' \
  && echo "$LINE" | grep -q '"cache_read":12400' && echo "$LINE" | grep -q 'claude-haiku-4-5' \
  && ok "T1 golden fixture extraction (4210/1830/12400, haiku)" || ko "T1 extraction"

# T2 — category-by-category counterfactual (rule A2): cache priced as cache
# haiku real = 4210*8e-7 + 1830*4e-6 + 12400*8e-8 = 0.0116808
# sonnet cf  = 4210*3e-6 + 1830*1.5e-5 + 12400*3e-7 = 0.043800
R=$(echo "$LINE" | grep -oE '"real_cost_usd":[0-9.]+' | cut -d: -f2)
C=$(echo "$LINE" | grep -oE '"counterfactual_cost_usd":[0-9.]+' | cut -d: -f2)
awk -v r="$R" -v c="$C" 'BEGIN{ exit !( (r>0.0116 && r<0.0118) && (c>0.0437 && c<0.0439) ) }' \
  && ok "T2 cache-aware pricing (real=$R cf=$C)" || ko "T2 pricing (real=$R cf=$C)"

# T3 — unmeasured path: broken transcript => coverage event, never invented
echo '{"session_id":"S1","transcript_path":"/nonexistent","subagent_type":"grunt"}' \
  | bash "$HERE/adapters/claude-code/butin-collect.sh"
tail -1 "$AMIRAL_HOME/butin.jsonl" | grep -q '"unmeasured":true' && ok "T3 unmeasured, not invented" || ko "T3"

# T4 — dedup: duplicated id counted once
DUPLINE=$(grep '"in":4210' "$AMIRAL_HOME/butin.jsonl" | head -1)
printf '%s\n' "$DUPLINE" >> "$AMIRAL_HOME/butin.jsonl"
OUT=$(AMIRAL_HOME="$AMIRAL_HOME" "$HERE/bin/amiral-butin" --no-color)
echo "$OUT" | grep -q "1 duplicate" && ok "T4 dedup by id" || ko "T4 dedup"

# T5 — coverage line
echo "$OUT" | grep -qE "Coverage: 1/2 tasks measured" && ok "T5 coverage 1/2" || ko "T5 coverage ($(echo "$OUT" | grep Coverage))"

# T6 — brain premium is a penalty, never a credit
# brain on opus (pricier than sonnet baseline): premium
printf '%s\n' '{"v":1,"id":"b1","ts":"t","agent":"brain","chosen_model":"claude-opus-4-8","real_cost_usd":0.30,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.10,"outcome":"ok"}' >> "$AMIRAL_HOME/butin.jsonl"
OUT=$(AMIRAL_HOME="$AMIRAL_HOME" "$HERE/bin/amiral-butin" --no-color)
echo "$OUT" | grep -q "brain premium" && ok "T6a brain premium shown" || ko "T6a"
# brain cheaper than baseline: NO credit
printf '%s\n' '{"v":1,"id":"b2","ts":"t","agent":"brain","chosen_model":"claude-haiku-4-5","real_cost_usd":0.01,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.05,"outcome":"ok"}' >> "$AMIRAL_HOME/butin.jsonl"
NET1=$(echo "$OUT" | grep "Net saved" | grep -oE '[+-][0-9.]+')
OUT2=$(AMIRAL_HOME="$AMIRAL_HOME" "$HERE/bin/amiral-butin" --no-color)
NET2=$(echo "$OUT2" | grep "Net saved" | grep -oE '[+-][0-9.]+')
[ "$NET1" = "$NET2" ] && ok "T6b cheap brain gives no credit (net unchanged $NET1)" || ko "T6b ($NET1 vs $NET2)"

# T7 — verified marker consumed
mkdir -p "$AMIRAL_HOME/state"; touch "$AMIRAL_HOME/state/verify-ok-S2"
echo "{\"session_id\":\"S2\",\"transcript_path\":\"$HERE/tests/fixtures/transcript-sample.jsonl\",\"subagent_type\":\"implementer\"}" \
  | bash "$HERE/adapters/claude-code/butin-collect.sh"
tail -1 "$AMIRAL_HOME/butin.jsonl" | grep -q '"verified":true' && ok "T7 verified via gate marker" || ko "T7"

# T8 — data locale is C (dot decimals in the log, whatever the env)
! grep -E '"real_cost_usd":[0-9]+,[0-9]' "$AMIRAL_HOME/butin.jsonl" && ok "T8 dot decimals in data" || ko "T8 comma leaked into data!"


# ---- v0.10.1 additions ----
# T9 — escalation heuristic: grunt(haiku) then implementer(sonnet) < 15min => escalated + extra
export AMIRAL_HOME=$(mktemp -d); mkdir -p "$AMIRAL_HOME"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$AMIRAL_HOME/butin-config.json"
echo "{\"session_id\":\"E1\",\"transcript_path\":\"$HERE/tests/fixtures/transcript-sample.jsonl\",\"subagent_type\":\"grunt\"}" | bash "$HERE/adapters/claude-code/butin-collect.sh"
cat > /tmp/tr2.jsonl << 'J'
{"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
J
echo "{\"session_id\":\"E1\",\"transcript_path\":\"/tmp/tr2.jsonl\",\"subagent_type\":\"implementer\"}" | bash "$HERE/adapters/claude-code/butin-collect.sh"
tail -1 "$AMIRAL_HOME/butin.jsonl" | grep -q '"outcome":"escalated"' \
  && tail -1 "$AMIRAL_HOME/butin.jsonl" | grep -qE '"escalation_extra_usd":0\.01' \
  && ok "T9 escalation detected + wasted attempt charged" || ko "T9 escalation ($(tail -1 "$AMIRAL_HOME/butin.jsonl" | grep -oE '"outcome":"[a-z]*"'))"

# T10 — pricing_version stamped
tail -1 "$AMIRAL_HOME/butin.jsonl" | grep -q '"pricing_version":"20[0-9][0-9]-' && ok "T10 pricing_version stamped" || ko "T10"

# T11 — haircut reduces net
N0=$(AMIRAL_HOME="$AMIRAL_HOME" "$HERE/bin/amiral-butin" --no-color | grep "Net saved" | grep -oE '[+-][0-9.]+')
N1=$(AMIRAL_HOME="$AMIRAL_HOME" "$HERE/bin/amiral-butin" --no-color --haircut=15 | grep "Net saved" | grep -oE '[+-][0-9.]+')
awk -v a="$N0" -v b="$N1" 'BEGIN{ exit !(b < a) }' && ok "T11 haircut lowers net ($N0 -> $N1)" || ko "T11 ($N0 vs $N1)"

# T12 — unknown schema version skipped, not crashed
printf '%s\n' '{"v":9,"id":"z9","agent":"grunt","real_cost_usd":99}' >> "$AMIRAL_HOME/butin.jsonl"
O12=$(AMIRAL_HOME="$AMIRAL_HOME" "$HERE/bin/amiral-butin" --no-color)
echo "$O12" | grep -q "Net saved" && ok "T12 future schema skipped" || ko "T12"

# T13 — degenerate state message (all tiers equal)
export AMIRAL_HOME=$(mktemp -d); mkdir -p "$AMIRAL_HOME"
printf '{ "baseline_model": "claude-sonnet-4-6", "baseline_source": "test", "mode": "api" }\n' > "$AMIRAL_HOME/butin-config.json"
printf '%s\n' '{"v":1,"id":"d1","ts":"t","agent":"implementer","chosen_model":"claude-sonnet-4-6","real_cost_usd":0.05,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":0.05,"outcome":"ok"}' > "$AMIRAL_HOME/butin.jsonl"
O13=$(AMIRAL_HOME="$AMIRAL_HOME" "$HERE/bin/amiral-butin" --no-color)
echo "$O13" | grep -q "measures cost, not quality" && ok "T13 degenerate message" || ko "T13"

# T14 — init writes config (non-interactive fallback, atomic)
export AMIRAL_HOME=$(mktemp -d); mkdir -p "$AMIRAL_HOME"
printf 'n\n' | AMIRAL_HOME="$AMIRAL_HOME" CLAUDE_CONFIG_DIR=$(mktemp -d) "$HERE/bin/amiral-butin" init >/dev/null 2>&1
grep -q '"baseline_model"' "$AMIRAL_HOME/butin-config.json" && ok "T14 init writes config" || ko "T14"

# T15 — journal note survives (created on HEAD)
D2=$(mktemp -d); cd "$D2"; git init -q .
git config user.email t@t; git config user.name t
echo x > f; git add f; git commit -qm m
AMIRAL_HOME="$AMIRAL_HOME" bash "$HERE/bin/amiral-journal" note >/dev/null 2>&1
git notes --ref=amiral show HEAD 2>/dev/null | grep -q "Amiral-Attest" && ok "T15 git note attached" || ko "T15"
cd "$HERE"

echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
