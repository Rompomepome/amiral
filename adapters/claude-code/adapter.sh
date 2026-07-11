#!/usr/bin/env bash
# butin adapter — Claude Code. Implements the BUTIN port for this harness.
# Declares its capabilities and knows the Claude-specific bits (log path,
# default model) so the CORE never has to.
set -uo pipefail

ADAPTER_HARNESS="claude-code"
ADAPTER_CAPS="task_event pricing_id history_scan plan_detect quota_snapshot statusline_surface"
ADAPTER_DEFAULT_BASELINE="claude-sonnet-4-6"   # conservative: never the priciest
ADAPTER_LOG_GLOB="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"

# history_scan: majority model over pre-amiral sessions (by token weight).
# Returns "model<TAB>session_count" or "" if insufficient history.
adapter_detect_baseline() {
  local dir="$ADAPTER_LOG_GLOB"
  [ -d "$dir" ] || { echo ""; return; }
  # count sessions per model from transcript jsonl; pick majority.
  # (kept defensive: missing dir/files never crash)
  local found
  found=$(grep -rhoE '"model":"[^"]+"' "$dir" 2>/dev/null \
          | sed 's/.*:"//;s/"//' | grep -v '^$' | sort | uniq -c | sort -rn | head -1)
  local sessions
  sessions=$(find "$dir" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
  if [ -z "$found" ] || [ "${sessions:-0}" -lt 20 ]; then echo ""; return; fi
  local model; model=$(echo "$found" | awk '{print $2}')
  echo "$model	$sessions"
}

# plan_detect: subscription if rate-limit windows are present in session json.
# Fallback: api. (Heuristic per SPEC §5; adapter-specific.)
adapter_detect_mode() {
  # if the statusline/session ever exposed rate_limit windows, we're on a plan
  if grep -rqE '"(five_?hour|week)_?(limit|window)"|rate_limit' \
      "$ADAPTER_LOG_GLOB" 2>/dev/null; then echo "plan"; else echo "api"; fi
}

adapter_default_baseline() { echo "$ADAPTER_DEFAULT_BASELINE"; }
adapter_capabilities()     { echo "$ADAPTER_CAPS"; }
adapter_harness()          { echo "$ADAPTER_HARNESS"; }
