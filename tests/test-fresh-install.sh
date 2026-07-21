#!/usr/bin/env bash
# fresh-install / new-user battery. The whole butin layer was only ever
# validated on a machine already carrying six weeks of state (see
# amiral-butin backfill) — this walks the from-scratch path a brand new
# user actually hits, hermetically (temp HOME + temp CLAUDE_CONFIG_DIR,
# never the caller's real ~/.claude), and fails loudly on any step that
# errors, prompts, or needs a manual edit docs/butin.md doesn't mention.
#
# Documented steps this battery exercises (docs/butin.md):
#   1. ./install.sh — the butin layer lands under $CLAUDE_DIR/butin.
#   2. Wiring the collector: the exact SubagentStop/Stop settings.json
#      snippet from docs/butin.md ("Wiring the butin (one-time, opt-in)"),
#      and that its `~/.claude/butin/butin-receipt.sh` command resolves.
#   3. `amiral-butin init` — "first-run setup: detects your baseline model
#      from history ... writes butin-config.json" — with NO history, this
#      must be non-interactive (conservative default, no prompt/no hang).
#   4. "Then work normally and run amiral-butin" — the receipt -> cold
#      measure path (SubagentStop hook writes a receipt; amiral-butin's
#      cold pass measures it from the transcript), no live Claude session
#      required.
#   5. `amiral-butin`'s own report: Net + Coverage lines, real numbers,
#      exit 0.
export LC_ALL=C
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ok  $1"; PASS=$((PASS+1)); }
ko(){ echo "  KO  $1"; FAIL=$((FAIL+1)); }

TMP_HOME="$(mktemp -d)"
CLAUDE_DIR="$TMP_HOME/.claude"
export HOME="$TMP_HOME"
export CLAUDE_CONFIG_DIR="$CLAUDE_DIR"

# ─── step 1: ./install.sh into a hermetic HOME ───
INSTALL_OUT="$(bash "$HERE/install.sh" 2>&1)"; INSTALL_RC=$?
if [ "$INSTALL_RC" = "0" ]; then
  ok "install.sh exits 0 on a brand-new HOME"
else
  ko "install.sh exited $INSTALL_RC — out=[$INSTALL_OUT]"
fi
for f in core.awk measure.py butin-receipt.sh agents.sh amiral-agents.txt pricing.tsv; do
  if [ -f "$CLAUDE_DIR/butin/$f" ]; then
    ok "installed: \$CLAUDE_DIR/butin/$f"
  else
    ko "MISSING after install: \$CLAUDE_DIR/butin/$f"
  fi
done

# ─── step 2: wire the collector exactly as docs/butin.md documents ───
SETTINGS="$CLAUDE_DIR/settings.json"
cat > "$SETTINGS" << 'EOF'
{ "hooks": {
    "SubagentStop": [{ "hooks": [{ "type": "command",
      "command": "bash ~/.claude/butin/butin-receipt.sh" }] }],
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "bash ~/.claude/butin/butin-receipt.sh --brain" }] }]
} }
EOF
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if 'SubagentStop' in d['hooks'] and 'Stop' in d['hooks'] else 1)" "$SETTINGS" 2>/dev/null; then
  ok "settings.json parses and carries the documented SubagentStop + Stop hooks"
else
  ko "settings.json does not parse or is missing the documented hooks"
fi
# the documented command is literally `bash ~/.claude/butin/butin-receipt.sh`
# — resolve `~` against THIS test's HOME (== CLAUDE_CONFIG_DIR's parent here)
# and assert the path it names is a real, executable file.
RESOLVED="$HOME/.claude/butin/butin-receipt.sh"
if [ -f "$RESOLVED" ]; then
  ok "documented collector command path resolves to a real file ($RESOLVED)"
else
  ko "documented collector command path does NOT resolve: $RESOLVED"
fi

# ─── step 3: amiral-butin init on a clean HOME — no history means the ───
# ─── conservative default, so init must NOT prompt (background + poll   ───
# ─── timeout: catches a real hang instead of letting the suite wedge;   ───
# ─── stdin is /dev/null, never fake menu input — a real prompt must     ───
# ─── surface as a FAILURE here, not be silently satisfied).             ───
INIT_HOME="$(mktemp -d)"
INIT_OUT="$(mktemp)"
( AMIRAL_HOME="$INIT_HOME" bash "$CLAUDE_DIR/amiral-butin" init < /dev/null > "$INIT_OUT" 2>&1 ) &
INIT_PID=$!
INIT_DONE=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  kill -0 "$INIT_PID" 2>/dev/null || { INIT_DONE=1; break; }
  sleep 0.5
done
if [ "$INIT_DONE" = "1" ]; then
  wait "$INIT_PID"; INIT_RC=$?
  if [ "$INIT_RC" = "0" ] && [ -f "$INIT_HOME/butin-config.json" ] \
     && grep -q '"baseline_model": "claude-sonnet-4-6"' "$INIT_HOME/butin-config.json" \
     && grep -q '"baseline_source": "default (conservative)"' "$INIT_HOME/butin-config.json"; then
    ok "amiral-butin init: clean HOME, no history -> non-interactive conservative default (sonnet), butin-config.json written, no prompt"
  else
    ko "amiral-butin init rc=$INIT_RC config=[$(cat "$INIT_HOME/butin-config.json" 2>/dev/null)] out=[$(cat "$INIT_OUT")]"
  fi
else
  kill -9 "$INIT_PID" 2>/dev/null; wait "$INIT_PID" 2>/dev/null || true
  ko "REAL NEW-USER DEFECT: amiral-butin init blocked (did not return within ~7.5s) on a clean HOME with no history — it should never need tty input in this case. out so far=[$(cat "$INIT_OUT" 2>/dev/null)]"
fi
rm -f "$INIT_OUT"

# ─── step 4: one measured task, no live Claude session — drive the real ───
# ─── receipt -> cold-measure path a new user hits, exactly per docs.     ───
FIXT="$(mktemp -d)"; mkdir -p "$FIXT/S/subagents"
AT="$FIXT/S/subagents/agent-fresh1.jsonl"
cat > "$AT" << 'TX'
{"message":{"id":"f1","model":"claude-haiku-4-5","usage":{"input_tokens":120,"output_tokens":80,"cache_read_input_tokens":500,"cache_creation_input_tokens":0}}}
TX
echo '{"agentType":"grunt","spawnDepth":1}' > "$FIXT/S/subagents/agent-fresh1.meta.json"
# backdate the transcript's mtime well past the 60s stable-gate amiral-butin
# applies before it will cold-measure anything — a just-written transcript
# mirrors an in-flight task, not a completed one.
touch -t 202601010000 "$AT"

RECEIPT_PAYLOAD='{"session_id":"FRESH1","agent_type":"grunt","agent_transcript_path":"'"$AT"'","cwd":"'"$FIXT"'"}'
echo "$RECEIPT_PAYLOAD" | AMIRAL_HOME="$INIT_HOME" bash "$CLAUDE_DIR/butin/butin-receipt.sh"
if grep -q "$AT" "$INIT_HOME/receipts.jsonl" 2>/dev/null; then
  ok "butin-receipt.sh (installed copy) mints a receipt for the fixture transcript"
else
  ko "no receipt written for the fixture transcript — receipts.jsonl=[$(cat "$INIT_HOME/receipts.jsonl" 2>/dev/null)]"
fi

REPORT_OUT="$(AMIRAL_HOME="$INIT_HOME" NO_COLOR=1 bash "$CLAUDE_DIR/amiral-butin" 2>&1)"; REPORT_RC=$?
if grep -q '"real_cost_usd"' "$INIT_HOME/butin.jsonl" 2>/dev/null && grep -q '"agent": "grunt"' "$INIT_HOME/butin.jsonl" 2>/dev/null; then
  ok "amiral-butin's cold pass measured the receipt -> butin.jsonl gains a real measured event (agent=grunt)"
else
  ko "no measured event landed in butin.jsonl — events=[$(cat "$INIT_HOME/butin.jsonl" 2>/dev/null)]"
fi

# ─── step 5: the report itself — Net + Coverage, real numbers, exit 0 ───
if [ "$REPORT_RC" = "0" ]; then
  ok "amiral-butin report runs clean (exit 0)"
else
  ko "amiral-butin report exited $REPORT_RC — out=[$REPORT_OUT]"
fi
if echo "$REPORT_OUT" | grep -qE 'Net saved +[+-][0-9]+\.[0-9]+ \$'; then
  ok "report shows a Net saved line with a real dollar figure"
else
  ko "no Net saved line with a real number — out=[$REPORT_OUT]"
fi
if echo "$REPORT_OUT" | grep -qE 'Coverage: 1/1 measured'; then
  ok "report shows Coverage: 1/1 measured (the fixture task, and only it)"
else
  ko "Coverage line missing/wrong — out=[$(echo "$REPORT_OUT" | grep -i coverage)]"
fi

echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
