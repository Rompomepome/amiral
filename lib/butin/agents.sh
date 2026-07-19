#!/usr/bin/env bash
# amiral butin — resolves the amiral-attributed agent set into a
# comma-separated csv for core.awk's -v AMIRAL_AGENTS="...". Shared by
# every call site (bin/amiral-butin, lib/butin/cache.sh, bin/amiral-journal)
# so the manifest can never drift between them — one file, sourced, not
# copy-pasted per caller.
#
# The manifest itself (lib/butin/amiral-agents.txt) is the basenames of
# agents/*.md — the agents amiral actually ships and routes. Anything else
# (a Claude Code built-in like general-purpose/Explore, or a user's own
# custom agent) is NOT amiral's doing and belongs in the "other" bucket
# core.awk computes when AMIRAL_AGENTS is set (see core.awk's v0.15 note).
#
# usage:
#   . agents.sh
#   AMIRAL_AGENTS="$(amiral_agents_csv "$REPO_FALLBACK_PATH")"
#   awk -v AMIRAL_AGENTS="$AMIRAL_AGENTS" -f "$CORE" ...
#
# Lookup order (same installed-then-repo idiom as MEASURE in bin/amiral-butin):
#   1. installed copy: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/butin/amiral-agents.txt
#   2. $REPO_FALLBACK_PATH (caller's own lib/butin/amiral-agents.txt, dev checkout)
# If neither exists, returns an empty string — core.awk then falls back to
# its legacy behavior (every worker is amiral; see is_amiral() there).
# Pure bash, no jq/python3 dependency.
amiral_agents_csv() {
  local repo_fallback="${1:-}"
  local f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/butin/amiral-agents.txt"
  [ -f "$f" ] || f="$repo_fallback"
  [ -f "$f" ] || { printf ''; return 0; }
  grep -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null \
    | sed 's/[^A-Za-z0-9._-]//g' \
    | grep -v '^$' \
    | paste -sd',' -
}
