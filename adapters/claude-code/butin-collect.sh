#!/usr/bin/env bash
# butin collector — Claude Code adapter. Wired (opt-in) on SubagentStop
# (workers) and Stop with --brain (main session). Reads the hook JSON on
# stdin, extracts real token usage from the transcript, prices it, and
# appends ONE atomic JSONL line to ~/.amiral/butin.jsonl.
# HONESTY RULES: if tokens can't be extracted, we write an "unmeasured"
# event (coverage is reported, numbers are never invented). Costs are
# computed category-by-category (input/output/cache_read/cache_write) —
# never collapsed. Data locale is ALWAYS C (dot decimals).
export LC_ALL=C
set -uo pipefail

AMIRAL_HOME="${AMIRAL_HOME:-$HOME/.amiral}"
LOG="$AMIRAL_HOME/butin.jsonl"
ERRLOG="$AMIRAL_HOME/butin-errors.log"
CONFIG="$AMIRAL_HOME/butin-config.json"
PRICES="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/butin/pricing.tsv"
[ -f "$PRICES" ] || PRICES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/butin/pricing.tsv"
mkdir -p "$AMIRAL_HOME"

err() { echo "$(date -u +%FT%TZ) $*" >> "$ERRLOG" 2>/dev/null; }

ROLE="worker"; [ "${1:-}" = "--brain" ] && ROLE="brain"

INPUT="$(cat 2>/dev/null || true)"
TRANSCRIPT=$(echo "$INPUT" | grep -oE '"transcript_path"[ ]*:[ ]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
SESSION=$(echo "$INPUT" | grep -oE '"session_id"[ ]*:[ ]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
AGENT=$(echo "$INPUT" | grep -oE '"subagent_type"[ ]*:[ ]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$AGENT" ] && AGENT="$ROLE"
[ "$ROLE" = "brain" ] && AGENT="brain"
TS="$(date -u +%FT%TZ)"
ID=$(printf '%s' "$SESSION-$AGENT-$(date +%s%N)" | shasum 2>/dev/null | awk '{print substr($1,1,12)}')

# --- extract last usage block from the transcript (defensive) ---
IN=""; OUT=""; CR=""; CW=""; MODEL=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  ULINE=$(grep '"input_tokens"' "$TRANSCRIPT" 2>/dev/null | tail -1)
  IN=$(echo "$ULINE"  | grep -oE '"input_tokens"[ ]*:[ ]*[0-9]+'                | grep -oE '[0-9]+$' | tail -1)
  OUT=$(echo "$ULINE" | grep -oE '"output_tokens"[ ]*:[ ]*[0-9]+'               | grep -oE '[0-9]+$' | tail -1)
  CR=$(echo "$ULINE"  | grep -oE '"cache_read_input_tokens"[ ]*:[ ]*[0-9]+'     | grep -oE '[0-9]+$' | tail -1)
  CW=$(echo "$ULINE"  | grep -oE '"cache_creation_input_tokens"[ ]*:[ ]*[0-9]+' | grep -oE '[0-9]+$' | tail -1)
  MODEL=$(grep -oE '"model"[ ]*:[ ]*"[^"]*"' "$TRANSCRIPT" 2>/dev/null | tail -1 | sed 's/.*"\([^"]*\)"$/\1/')
fi
CR=${CR:-0}; CW=${CW:-0}

# --- unmeasured path: never invent ---
if [ -z "$IN" ] || [ -z "$OUT" ] || [ -z "$MODEL" ]; then
  LINE="{\"v\":1,\"id\":\"$ID\",\"ts\":\"$TS\",\"agent\":\"$AGENT\",\"model\":\"${MODEL:-unknown}\",\"unmeasured\":true}"
  printf '%s\n' "$LINE" >> "$LOG"
  err "unmeasured event ($AGENT): transcript=$TRANSCRIPT in=$IN out=$OUT model=$MODEL"
  exit 0
fi

# --- baseline + rates ---
BASE=$(grep -oE '"baseline_model"[ ]*:[ ]*"[^"]*"' "$CONFIG" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$BASE" ] && BASE="claude-sonnet-4-6"
rates() { awk -F'\t' -v m="$1" '$1==m{print $2,$3,$4,$5}' "$PRICES"; }
PVER=$(grep -oE 'pricing_version: [0-9-]+' "$PRICES" | head -1 | awk '{print $2}'); PVER=${PVER:-unknown}
CHOSEN_R=$(rates "$MODEL"); BASE_R=$(rates "$BASE")
if [ -z "$CHOSEN_R" ] || [ -z "$BASE_R" ]; then
  LINE="{\"v\":1,\"id\":\"$ID\",\"ts\":\"$TS\",\"agent\":\"$AGENT\",\"model\":\"${MODEL:-unknown}\",\"unmeasured\":true}"
  printf '%s\n' "$LINE" >> "$LOG"; err "unknown pricing_id: chosen=$MODEL base=$BASE"; exit 0
fi

# --- category-by-category costs (rule A2) ---
read -r RI RO RCW RCR <<< "$CHOSEN_R"
read -r BI BO BCW BCR <<< "$BASE_R"
COSTS=$(awk -v i="$IN" -v o="$OUT" -v cr="$CR" -v cw="$CW" \
            -v ri="$RI" -v ro="$RO" -v rcr="$RCR" -v rcw="$RCW" \
            -v bi="$BI" -v bo="$BO" -v bcr="$BCR" -v bcw="$BCW" 'BEGIN{
  real = i*ri + o*ro + cr*rcr + cw*rcw
  cf   = i*bi + o*bo + cr*bcr + cw*bcw
  printf "%.6f %.6f", real, cf }')
REAL=$(echo "$COSTS" | awk '{print $1}'); CF=$(echo "$COSTS" | awk '{print $2}')

# premium tokens avoided: only when a cheaper model served baseline-work
PIA=0; POA=0
CHEAPER=$(awk -v a="$RO" -v b="$BO" 'BEGIN{print (a<b)?1:0}')
[ "$MODEL" != "$BASE" ] && [ "$CHEAPER" = "1" ] && { PIA=$IN; POA=$OUT; }

# verified: consume a fresh marker written by the verify gate (best effort)
VERIF="null"
MARK="$AMIRAL_HOME/state/verify-ok-$SESSION"
if [ -f "$MARK" ]; then
  MT=$(stat -c %Y "$MARK" 2>/dev/null || stat -f %m "$MARK" 2>/dev/null || echo "")
  case "$MT" in (*[!0-9]*|"") MT=0;; esac
  AGE=$(( $(date +%s) - MT ))
  [ "$MT" != "0" ] && [ "$AGE" -lt 300 ] && VERIF="true"
fi

# escalation heuristic (conservative, counts AGAINST amiral): if the
# previous event in THIS session ran on a cheaper model (out-rate), was
# grunt or the same agent, and finished < 15 min ago, this event is the
# escalation and the wasted cheap attempt is charged as extra cost.
OUTCOME="ok"; ESCX=0
STATE="$AMIRAL_HOME/state/last-$SESSION"
mkdir -p "$AMIRAL_HOME/state"
if [ -f "$STATE" ] && [ "$ROLE" != "brain" ]; then
  IFS=$'\t' read -r PAG PMODEL PREAL PEPOCH PRATE < "$STATE" || true
  NOW=$(date +%s); GAP=$(( NOW - ${PEPOCH:-0} ))
  PRICIER=$(awk -v a="${PRATE:-0}" -v b="$RO" 'BEGIN{print (b>a)?1:0}')
  if [ "$GAP" -lt 900 ] && [ "$PRICIER" = "1" ] && { [ "$PAG" = "grunt" ] || [ "$PAG" = "$AGENT" ]; }; then
    OUTCOME="escalated"; ESCX="$PREAL"
  fi
fi
[ "$ROLE" != "brain" ] && printf '%s\t%s\t%s\t%s\t%s\n' "$AGENT" "$MODEL" "$REAL" "$(date +%s)" "$RO" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

PVER=$(grep -oE "pricing_version: [0-9-]+" "$PRICES" 2>/dev/null | awk '{print $2}')
LINE="{\"v\":1,\"id\":\"$ID\",\"ts\":\"$TS\",\"pricing_version\":\"${PVER:-unknown}\",\"agent\":\"$AGENT\",\"chosen_model\":\"$MODEL\",\"tokens\":{\"in\":$IN,\"out\":$OUT,\"cache_read\":$CR,\"cache_write\":$CW},\"real_cost_usd\":$REAL,\"baseline_model\":\"$BASE\",\"counterfactual_cost_usd\":$CF,\"outcome\":\"$OUTCOME\",\"escalation_extra_usd\":$ESCX,\"pricing_version\":\"$PVER\",\"verified\":$VERIF,\"prem_in_avoided\":$PIA,\"prem_out_avoided\":$POA}"

# atomic append: single write, guaranteed < PIPE_BUF (line is ~400 chars)
[ ${#LINE} -lt 4000 ] && printf '%s\n' "$LINE" >> "$LOG" || err "line too long, dropped ($AGENT)"
exit 0
