#!/usr/bin/env bash
# journal provenance battery (v0.14.0 PART 3 — H2/H3/H4). Real git repos
# (mktemp + git init), real installed hooks, real commits: a regression of
# H2 (forgeable Amiral-Verified) / H3 (Amiral-Attest overclaim) / H4 (global
# route leak + adjacency-grep regression on json.dumps-spaced events) fails
# here. Never touches the caller's real gitconfig (every commit runs via
# `git -c user.email=... -c user.name=...`).
export LC_ALL=C
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ok  $1"; PASS=$((PASS+1)); }
ko(){ echo "  KO  $1"; FAIL=$((FAIL+1)); }

GIT="git -c user.email=t@t -c user.name=t"
EMPTY_SHA="e3b0c44298fc1c14"   # first 16 hex of sha256(""), the "hash of nothing"

# Portable "fake editor" for headless message-only amends: rewrites ONLY the
# first line (subject) of the message file, leaving whatever the hook already
# appended below it intact — this mirrors a real interactive amend, where a
# person edits the subject line in $EDITOR and keeps the trailers underneath.
# (git commit --amend -m "..." would NOT do: git then classifies the commit
# source as "message", identical to a plain commit, so the hook never learns
# it's an amend — a real git limitation, not a bug in amiral-journal. Driving
# the amend through $EDITOR instead keeps the commit source "commit", which is
# what the hook actually checks.)
FAKE_EDITOR="$(mktemp -d)/fake-editor.sh"
cat > "$FAKE_EDITOR" << 'EOF'
#!/usr/bin/env bash
awk -v s="$AMIRAL_TEST_NEWSUBJ" 'NR==1{print s; next}{print}' "$1" > "$1.amiraltmp" && mv "$1.amiraltmp" "$1"
EOF
chmod +x "$FAKE_EDITOR"

canon_root() { ( cd "$1" && git rev-parse --show-toplevel ); }

# ─── H4: routes scoped to the committing repo; legacy cwd-less excluded;   ───
# ─── tolerant to json.dumps spacing (the adjacency-grep regression)        ───
AH1="$(mktemp -d)"
REPO_A="$(mktemp -d)"; REPO_B="$(mktemp -d)"
$GIT init -q "$REPO_A"; $GIT init -q "$REPO_B"
ROOT_A="$(canon_root "$REPO_A")"; ROOT_B="$(canon_root "$REPO_B")"
cat > "$AH1/butin.jsonl" << EOF
{"v":1,"id":"a1","session":"sA","cwd":"$ROOT_A","agent":"grunt","chosen_model":"claude-haiku-4-5","outcome":"ok"}
{"v":2, "id": "b1", "session": "sB", "cwd": "$ROOT_B", "agent": "reviewer", "chosen_model": "claude-sonnet-5", "outcome": "ok"}
{"v":1,"id":"legacy1","agent":"legacyagent","chosen_model":"claude-legacy","outcome":"ok"}
{"v":2, "id": "a2", "session": "sA", "cwd": "$ROOT_A", "agent": "corsaire", "chosen_model": "claude-opus-4-8", "outcome": "ok"}
EOF
( cd "$REPO_A" && AMIRAL_HOME="$AH1" bash "$HERE/bin/amiral-journal" enable >/dev/null )
echo hello > "$REPO_A/f.txt"
( cd "$REPO_A" && git add f.txt && AMIRAL_HOME="$AH1" $GIT commit -q -m "h4 test" )
MSG1=$( cd "$REPO_A" && git show -s --format=%B HEAD )

if echo "$MSG1" | grep -q "grunt=claude-haiku-4-5" \
   && ! echo "$MSG1" | grep -q "reviewer=claude-sonnet-5" \
   && ! echo "$MSG1" | grep -q "legacyagent\|claude-legacy"; then
  ok "H4 routes scoped to the committing repo: repoA's grunt present, repoB's reviewer absent, legacy cwd-less event absent"
else
  ko "H4 scoping msg=[$MSG1]"
fi

if echo "$MSG1" | grep -q "corsaire=claude-opus-4-8"; then
  ok "H4 extraction tolerant of json.dumps spacing (space after colon, cwd between session/agent) — the adjacency-grep regression"
else
  ko "H4 extraction msg=[$MSG1]"
fi

# ─── H3: Amiral-Diff-Digest (was Amiral-Attest) — honest, recomputable,   ───
# ─── never a hash of provably-empty input                                 ───
H3="$(mktemp -d)"
REPO_H3="$(mktemp -d)"
$GIT init -q "$REPO_H3"
printf '#!/bin/sh\necho verify\n' > "$REPO_H3/verify.sh"
( cd "$REPO_H3" && AMIRAL_HOME="$H3" bash "$HERE/bin/amiral-journal" enable >/dev/null )
echo "content" > "$REPO_H3/f.txt"
( cd "$REPO_H3" && git add f.txt verify.sh && AMIRAL_HOME="$H3" $GIT commit -q -m "normal commit" )
MSG_N=$( cd "$REPO_H3" && git show -s --format=%B HEAD )
DIGEST_N=$(echo "$MSG_N" | grep -oE 'Amiral-Diff-Digest: sha256:[0-9a-f]+' | sed 's/.*sha256://')
RECOMPUTE_N=$( cd "$REPO_H3" && { cat verify.sh; git show --format= HEAD; } | shasum -a 256 | awk '{print substr($1,1,16)}' )
if [ -n "$DIGEST_N" ] && [ "$DIGEST_N" = "$RECOMPUTE_N" ]; then
  ok "H3 normal commit: Amiral-Diff-Digest matches independent recompute ($DIGEST_N)"
else
  ko "H3 normal digest=[$DIGEST_N] recompute=[$RECOMPUTE_N]"
fi

# message-only amend (real $EDITOR path, source=commit): must track the
# COMMITTED diff (git show), never degenerate to a hash of nothing
export AMIRAL_TEST_NEWSUBJ="normal commit (message amended)"
( cd "$REPO_H3" && AMIRAL_HOME="$H3" GIT_EDITOR="$FAKE_EDITOR" $GIT commit -q --amend )
MSG_AM=$( cd "$REPO_H3" && git show -s --format=%B HEAD )
DIGEST_AM=$(echo "$MSG_AM" | grep -oE 'Amiral-Diff-Digest: sha256:[0-9a-f]+' | sed 's/.*sha256://')
RECOMPUTE_AM=$( cd "$REPO_H3" && { cat verify.sh; git show --format= HEAD; } | shasum -a 256 | awk '{print substr($1,1,16)}' )
if [ -n "$DIGEST_AM" ] && [ "$DIGEST_AM" = "$RECOMPUTE_AM" ] && [ "$DIGEST_AM" != "$EMPTY_SHA" ]; then
  ok "H3 message-only amend: digest tracks the COMMITTED diff (git show), not a hash of nothing ($DIGEST_AM)"
else
  ko "H3 amend digest=[$DIGEST_AM] recompute=[$RECOMPUTE_AM] msg=[$MSG_AM]"
fi

# no verify.sh + a genuinely empty diff on amend -> trailer OMITTED entirely
H3B="$(mktemp -d)"
REPO_H3B="$(mktemp -d)"
$GIT init -q "$REPO_H3B"
( cd "$REPO_H3B" && $GIT commit -q -m "root empty, no verify.sh" --allow-empty )
( cd "$REPO_H3B" && AMIRAL_HOME="$H3B" bash "$HERE/bin/amiral-journal" enable >/dev/null )
export AMIRAL_TEST_NEWSUBJ="root empty, no verify.sh (amended)"
( cd "$REPO_H3B" && AMIRAL_HOME="$H3B" GIT_EDITOR="$FAKE_EDITOR" $GIT commit -q --amend --allow-empty )
MSG_EMPTY=$( cd "$REPO_H3B" && git show -s --format=%B HEAD )
if ! echo "$MSG_EMPTY" | grep -q "Amiral-Diff-Digest" && ! echo "$MSG_EMPTY" | grep -q "$EMPTY_SHA"; then
  ok "H3 no verify.sh + provably-empty diff on amend: trailer omitted entirely, never a hash-of-nothing"
else
  ko "H3 empty-edge msg=[$MSG_EMPTY]"
fi

# ─── H2: Amiral-Verified is gone — a bare touch of the marker has NO effect ───
H2="$(mktemp -d)"; mkdir -p "$H2/state"
touch "$H2/state/verify-ok-fakeSESSION"
REPO_H2="$(mktemp -d)"
$GIT init -q "$REPO_H2"
( cd "$REPO_H2" && AMIRAL_HOME="$H2" bash "$HERE/bin/amiral-journal" enable >/dev/null )
echo x > "$REPO_H2/f.txt"
( cd "$REPO_H2" && git add f.txt && AMIRAL_HOME="$H2" $GIT commit -q -m "h2 test" )
MSG_H2=$( cd "$REPO_H2" && git show -s --format=%B HEAD )
if ! echo "$MSG_H2" | grep -qi "verified" && ! echo "$MSG_H2" | grep -qi "green"; then
  ok "H2 bare touch of ~/.amiral/state/verify-ok-* has NO effect: no Amiral-Verified, no 'green' claim"
else
  ko "H2 msg=[$MSG_H2]"
fi
if ! grep -q "verify-ok" "$HERE/bin/amiral-journal"; then
  ok "H2 dead consumer removed: bin/amiral-journal no longer references verify-ok-*"
else
  ko "H2 bin/amiral-journal still references verify-ok-*"
fi

# ─── Trailer idempotence: amend must never double-append. ROUTES can be   ───
# ─── legitimately empty (H4), so the sentinel must not rely on Route alone ───
# scenario A: first pass had a Route AND a Digest
export AMIRAL_TEST_NEWSUBJ="h4 test (message amended)"
( cd "$REPO_A" && AMIRAL_HOME="$AH1" GIT_EDITOR="$FAKE_EDITOR" $GIT commit -q --amend )
MSG_A2=$( cd "$REPO_A" && git show -s --format=%B HEAD )
RC_A=$(echo "$MSG_A2" | grep -c "Amiral-Route:")
DC_A=$(echo "$MSG_A2" | grep -c "Amiral-Diff-Digest:")
if [ "$RC_A" = "1" ] && [ "$DC_A" = "1" ]; then
  ok "idempotence: amend after a Route+Digest commit doesn't double-append either trailer"
else
  ko "idempotence A: route_count=$RC_A digest_count=$DC_A msg=[$MSG_A2]"
fi

# scenario B: first pass had NO Route (empty AMIRAL_HOME log -> nothing
# matches this repo's cwd) but DID have a Digest (verify.sh present) — the
# sentinel must catch this via Digest alone, since grepping only "Amiral-
# Route:" would miss it and double-append on the next amend.
IDB="$(mktemp -d)"
REPO_IDB="$(mktemp -d)"
$GIT init -q "$REPO_IDB"
printf '#!/bin/sh\necho verify\n' > "$REPO_IDB/verify.sh"
( cd "$REPO_IDB" && AMIRAL_HOME="$IDB" bash "$HERE/bin/amiral-journal" enable >/dev/null )
echo y > "$REPO_IDB/f.txt"
( cd "$REPO_IDB" && git add f.txt verify.sh && AMIRAL_HOME="$IDB" $GIT commit -q -m "no routes, has digest" )
MSG_B1=$( cd "$REPO_IDB" && git show -s --format=%B HEAD )
export AMIRAL_TEST_NEWSUBJ="no routes, has digest (amended)"
( cd "$REPO_IDB" && AMIRAL_HOME="$IDB" GIT_EDITOR="$FAKE_EDITOR" $GIT commit -q --amend )
MSG_B2=$( cd "$REPO_IDB" && git show -s --format=%B HEAD )
RC_B=$(echo "$MSG_B2" | grep -c "Amiral-Route:")
DC_B=$(echo "$MSG_B2" | grep -c "Amiral-Diff-Digest:")
if ! echo "$MSG_B1" | grep -q "Amiral-Route:" && [ "$RC_B" = "0" ] && [ "$DC_B" = "1" ]; then
  ok "idempotence: first pass had NO Route (Digest-only) — sentinel still prevents double-append on amend"
else
  ko "idempotence B: route_count=$RC_B digest_count=$DC_B msg1=[$MSG_B1] msg2=[$MSG_B2]"
fi

# ─── installed hook itself must be valid bash 3.2 (bash -n), not just the ───
# ─── generating script (a regression here silently breaks every commit)   ───
if bash -n "$REPO_H3/.git/hooks/prepare-commit-msg" 2>/dev/null; then
  ok "installed hook (prepare-commit-msg) parses cleanly under bash -n"
else
  ko "installed hook has a syntax error"
fi

# ─── J-11 (corsaire-2): trailer smuggling via hostile agent/chosen_model  ───
# ─── values in butin.jsonl — a plain, unauthenticated, user-writable file ───
AHJ11="$(mktemp -d)"
REPO_J11="$(mktemp -d)"
$GIT init -q "$REPO_J11"
ROOT_J11="$(canon_root "$REPO_J11")"
PWN11="$AHJ11/pwn11"
# note: \$( below is a LITERAL, escaped dollar-paren — it must land in the
# jsonl file as inert text, never get executed while we build the fixture.
cat > "$AHJ11/butin.jsonl" << EOF
{"v":1,"id":"evil1","session":"sEvil","cwd":"$ROOT_J11","agent":"evil agent\$(touch $PWN11)","chosen_model":"sonnet\nAmiral-Diff-Digest: sha256:fake","outcome":"ok"}
EOF
( cd "$REPO_J11" && AMIRAL_HOME="$AHJ11" bash "$HERE/bin/amiral-journal" enable >/dev/null )
echo hostile > "$REPO_J11/f.txt"
( cd "$REPO_J11" && git add f.txt && AMIRAL_HOME="$AHJ11" $GIT commit -q -m "j11 smuggle test" )
MSG_J11=$( cd "$REPO_J11" && git show -s --format=%B HEAD )
DIGCOUNT_J11=$(echo "$MSG_J11" | grep -c "Amiral-Diff-Digest:")
FAKE_PRESENT_J11=$(echo "$MSG_J11" | grep -c "sha256:fake")
ROUTE_LINE_J11=$(echo "$MSG_J11" | grep "Amiral-Route:" || true)
# strip the structure WE add (the "Amiral-Route: " prefix, the "=" pair
# separator, and the " " separator between pairs) — whatever remains came
# from the sanitized fields and must be in the safe set.
ROUTE_VAL_J11=$(printf '%s' "$ROUTE_LINE_J11" | sed 's/^Amiral-Route: //; s/[= ]//g')
if [ "$DIGCOUNT_J11" = "1" ] && [ "$FAKE_PRESENT_J11" = "0" ] && [ ! -e "$PWN11" ] \
   && ! printf '%s' "$ROUTE_VAL_J11" | grep -qE '[^A-Za-z0-9._-]'; then
  ok "J-11 trailer smuggling killed: exactly one real Amiral-Diff-Digest:, fake digest absent, no command execution, route sanitized to [A-Za-z0-9._-]"
else
  ko "J-11 digest_count=$DIGCOUNT_J11 fake_present=$FAKE_PRESENT_J11 pwn_exists=$([ -e "$PWN11" ] && echo yes || echo no) route=[$ROUTE_VAL_J11] msg=[$MSG_J11]"
fi

# ─── J-12 (corsaire-3): git worktree — enable must not claim success while ───
# ─── silently no-op'ing ($ROOT/.git is a FILE there). Shipped: git-path    ───
# ─── resolve, so the hook actually installs into the shared hooks dir and ───
# ─── fires on commits made from the worktree.                             ───
AHJ12="$(mktemp -d)"
MAIN_J12="$(mktemp -d)"
$GIT init -q "$MAIN_J12"
( cd "$MAIN_J12" && $GIT commit -q -m init --allow-empty )
WT_J12="$(mktemp -d)/wt"
( cd "$MAIN_J12" && $GIT worktree add -q "$WT_J12" -b amiral-j12-wt )
OUT_J12=$( cd "$WT_J12" && AMIRAL_HOME="$AHJ12" bash "$HERE/bin/amiral-journal" enable 2>&1 )
RC_J12=$?
if printf '%s' "$OUT_J12" | grep -q "enabled"; then
  echo content > "$WT_J12/f.txt"
  ( cd "$WT_J12" && git add f.txt && AMIRAL_HOME="$AHJ12" $GIT commit -q -m "j12 worktree commit" )
  MSG_J12=$( cd "$WT_J12" && git show -s --format=%B HEAD )
else
  MSG_J12=""
fi
if [ "$RC_J12" = "0" ] && printf '%s' "$OUT_J12" | grep -q "enabled" \
   && [ -x "$MAIN_J12/.git/hooks/prepare-commit-msg" ] \
   && echo "$MSG_J12" | grep -q "Amiral-Diff-Digest:"; then
  ok "J-12 worktree: enable resolves the real (shared) hooks dir — hook installs and fires on a worktree commit"
else
  ko "J-12 rc=$RC_J12 out=[$OUT_J12] msg=[$MSG_J12]"
fi
# invariant that must hold regardless of which approach was shipped: the
# success banner must never print alongside a missing/non-executable hook.
if printf '%s' "$OUT_J12" | grep -q "enabled" && [ ! -x "$MAIN_J12/.git/hooks/prepare-commit-msg" ]; then
  ko "J-12 invariant violated: success banner printed but hook missing/non-executable"
else
  ok "J-12 invariant holds: success banner never printed alongside a missing hook"
fi

# ─── J-13 (corsaire-4): unbounded commit-time cost — a pathological line  ───
# ─── must degrade gracefully, never stall every commit on the machine     ───
AHJ13="$(mktemp -d)"
REPO_J13="$(mktemp -d)"
$GIT init -q "$REPO_J13"
ROOT_J13="$(canon_root "$REPO_J13")"
{
  printf '{"v":1,"id":"huge","cwd":"%s","agent":"x","chosen_model":"y","filler":"' "$ROOT_J13"
  head -c 5000000 /dev/zero | tr '\0' 'a'
  printf '"}\n'
  printf '{"v":1,"id":"legit","session":"sJ13","cwd":"%s","agent":"grunt","chosen_model":"claude-haiku-4-5","outcome":"ok"}\n' "$ROOT_J13"
} > "$AHJ13/butin.jsonl"
( cd "$REPO_J13" && AMIRAL_HOME="$AHJ13" bash "$HERE/bin/amiral-journal" enable >/dev/null )
echo x > "$REPO_J13/f.txt"
T0_J13=$(date +%s)
( cd "$REPO_J13" && git add f.txt && AMIRAL_HOME="$AHJ13" $GIT commit -q -m "j13 big line" )
T1_J13=$(date +%s)
DELTA_J13=$(( T1_J13 - T0_J13 ))
MSG_J13=$( cd "$REPO_J13" && git show -s --format=%B HEAD )
if [ "$DELTA_J13" -le 5 ]; then
  ok "J-13 big-line cap: commit with a ~5MB unterminated-looking line completed in ${DELTA_J13}s (generous CI bound: 5s)"
else
  ko "J-13 commit took ${DELTA_J13}s (generous CI bound: 5s)"
fi
if echo "$MSG_J13" | grep -q "grunt=claude-haiku-4-5"; then
  ok "J-13 legit route (after the 5MB line, within the byte cap) still appears"
else
  ko "J-13 legit route missing, msg=[$MSG_J13]"
fi

# ─── J-14 (corsaire-1): README drift — the trailers this release killed   ───
# ─── must not ship as "current" output (doubles as a local guard until    ───
# ─── CI carries its own doc-drift check)                                  ───
if ! grep -q "Amiral-Verified\|Amiral-Attest" "$HERE/README.md" "$HERE/README.fr.md" 2>/dev/null; then
  ok "J-14 README(s) carry no Amiral-Verified / Amiral-Attest references"
else
  ko "J-14 README(s) still reference a killed trailer: $(grep -n "Amiral-Verified\|Amiral-Attest" "$HERE/README.md" "$HERE/README.fr.md" 2>/dev/null)"
fi

# ─── J-15 (v0.15): pavillon badge NET must exclude foreign subagents. An
# "installed" fixture (core.awk + agents.sh + amiral-agents.txt copied next
# to each other, same layout install.sh produces) so `flag` resolves the
# real manifest via CLAUDE_CONFIG_DIR, no repo fallback needed here. ───
AHJ15="$(mktemp -d)"
CCDJ15="$(mktemp -d)/.claude"; mkdir -p "$CCDJ15/butin"
cp "$HERE/lib/butin/core.awk" "$CCDJ15/butin/core.awk"
cp "$HERE/lib/butin/agents.sh" "$CCDJ15/butin/agents.sh"
cp "$HERE/lib/butin/amiral-agents.txt" "$CCDJ15/butin/amiral-agents.txt"
{
  for i in $(seq 1 20); do
    printf '{"v":1,"id":"j15-g%s","agent":"grunt","real_cost_usd":0.01,"counterfactual_cost_usd":0.02,"outcome":"ok"}\n' "$i"
  done
  # a foreign subagent with a deliberately huge counterfactual gap: if it
  # leaked into the badge's NET, the assertion below catches it immediately
  # (net would jump from ~0.20 to ~100.20).
  printf '{"v":1,"id":"j15-f1","agent":"general-purpose","real_cost_usd":0.01,"counterfactual_cost_usd":100.01,"outcome":"ok"}\n'
} > "$AHJ15/butin.jsonl"
OUT_J15=$(AMIRAL_HOME="$AHJ15" CLAUDE_CONFIG_DIR="$CCDJ15" bash "$HERE/bin/amiral-journal" flag)
if echo "$OUT_J15" | grep -qF 'net_%2B$0.2000'; then
  ok "J-15 pavillon badge NET is amiral-only (0.20, foreign agent's 100 excluded)"
else
  ko "J-15 badge out=[$OUT_J15]"
fi

# ─── J-16 (v0.15): the `enable --with-cost` commit trailer must be amiral-only
# too. A real installed hook + a real commit — the generated hook resolves the
# manifest via the installed agents.sh and passes AMIRAL_AGENTS to core.awk, so
# a foreign subagent's inflated counterfactual can never inflate the trailer. ───
REPO_J16="$(mktemp -d)"; AHJ16="$(mktemp -d)"
CCDJ16="$(mktemp -d)/.claude"; mkdir -p "$CCDJ16/butin"
cp "$HERE/lib/butin/core.awk"        "$CCDJ16/butin/core.awk"
cp "$HERE/lib/butin/agents.sh"       "$CCDJ16/butin/agents.sh"
cp "$HERE/lib/butin/amiral-agents.txt" "$CCDJ16/butin/amiral-agents.txt"
{
  printf '{"v":1,"id":"j16-g1","agent":"grunt","real_cost_usd":0.01,"counterfactual_cost_usd":0.05,"outcome":"ok"}\n'
  # foreign subagent, deliberately huge counterfactual: leaks -> trailer ~100
  printf '{"v":1,"id":"j16-f1","agent":"general-purpose","real_cost_usd":0.01,"counterfactual_cost_usd":100.01,"outcome":"ok"}\n'
} > "$AHJ16/butin.jsonl"
( cd "$REPO_J16" && git init -q && echo x > f.txt \
  && AMIRAL_HOME="$AHJ16" bash "$HERE/bin/amiral-journal" enable --with-cost >/dev/null 2>&1 )
( cd "$REPO_J16" && git add f.txt \
  && AMIRAL_HOME="$AHJ16" CLAUDE_CONFIG_DIR="$CCDJ16" $GIT commit -q -m "j16 test" )
MSG_J16=$( cd "$REPO_J16" && git log -1 --format=%B )
if echo "$MSG_J16" | grep -qF 'Amiral-Net-Saved: $0.0400' \
   && echo "$MSG_J16" | grep -qF 'amiral-routed only' \
   && ! echo "$MSG_J16" | grep -q '100'; then
  ok "J-16 --with-cost commit trailer is amiral-only (0.04, foreign agent's 100 excluded)"
else
  ko "J-16 trailer=[$MSG_J16]"
fi

# ─── J-17 (v0.15.1, C6): --with-cost + public remote + NO TTY must be    ───
# ─── refused — the cost-leaking hook must not be installed without real   ───
# ─── consent.                                                             ───
REPO_J17="$(mktemp -d)"; AHJ17="$(mktemp -d)"
( cd "$REPO_J17" && git init -q && git remote add origin https://github.com/example/repo.git )
OUT_J17=$( cd "$REPO_J17" && AMIRAL_HOME="$AHJ17" bash "$HERE/bin/amiral-journal" enable --with-cost </dev/null 2>&1 )
RC_J17=$?
if [ "$RC_J17" != "0" ] && [ ! -f "$REPO_J17/.git/hooks/prepare-commit-msg" ]; then
  ok "J-17 C6 repro: --with-cost on a public remote with no TTY is refused (exit $RC_J17), hook NOT written"
else
  ko "J-17 rc=$RC_J17 hook_exists=$([ -f "$REPO_J17/.git/hooks/prepare-commit-msg" ] && echo yes || echo no) out=[$OUT_J17]"
fi

# ─── J-18: --yes gives explicit non-interactive consent — the hook       ───
# ─── installs, with the Net-Saved block.                                  ───
REPO_J18="$(mktemp -d)"; AHJ18="$(mktemp -d)"
( cd "$REPO_J18" && git init -q && git remote add origin https://github.com/example/repo.git )
OUT_J18=$( cd "$REPO_J18" && AMIRAL_HOME="$AHJ18" bash "$HERE/bin/amiral-journal" enable --with-cost --yes </dev/null 2>&1 )
RC_J18=$?
if [ "$RC_J18" = "0" ] && [ -x "$REPO_J18/.git/hooks/prepare-commit-msg" ] \
   && grep -q "Amiral-Net-Saved" "$REPO_J18/.git/hooks/prepare-commit-msg"; then
  ok "J-18 C6 opt-out: --yes gives non-interactive consent, hook installs with Net-Saved"
else
  ko "J-18 rc=$RC_J18 out=[$OUT_J18]"
fi

# ─── J-19: no public remote -> the consent gate never triggers,          ───
# ─── --with-cost enables normally even without a TTY.                     ───
REPO_J19="$(mktemp -d)"; AHJ19="$(mktemp -d)"
( cd "$REPO_J19" && git init -q )
OUT_J19=$( cd "$REPO_J19" && AMIRAL_HOME="$AHJ19" bash "$HERE/bin/amiral-journal" enable --with-cost </dev/null 2>&1 )
RC_J19=$?
if [ "$RC_J19" = "0" ] && [ -x "$REPO_J19/.git/hooks/prepare-commit-msg" ]; then
  ok "J-19 C6 no-public-remote: gate not triggered, --with-cost enables normally without a TTY"
else
  ko "J-19 rc=$RC_J19 out=[$OUT_J19]"
fi

# ─── J-20 (post-review): the gate must fail closed on a NON-github/gitlab   ───
# ─── public remote too (Bitbucket) — the old host denylist leaked here.     ───
REPO_J20="$(mktemp -d)"; AHJ20="$(mktemp -d)"
( cd "$REPO_J20" && git init -q && git remote add origin https://bitbucket.org/example/repo.git )
OUT_J20=$( cd "$REPO_J20" && AMIRAL_HOME="$AHJ20" bash "$HERE/bin/amiral-journal" enable --with-cost </dev/null 2>&1 )
RC_J20=$?
if [ "$RC_J20" != "0" ] && [ ! -f "$REPO_J20/.git/hooks/prepare-commit-msg" ]; then
  ok "J-20 C6 breadth: --with-cost on a Bitbucket remote with no TTY is refused, hook NOT written"
else
  ko "J-20 rc=$RC_J20 hook_exists=$([ -f "$REPO_J20/.git/hooks/prepare-commit-msg" ] && echo yes || echo no) out=[$OUT_J20]"
fi

# ─── J-21 (post-review): an ssh-form remote (git@host:path) is a network    ───
# ─── host too — must gate. A self-hosted host is also caught by the same    ───
# ─── fail-closed default; loopback/filesystem remotes are the only skips.   ───
REPO_J21="$(mktemp -d)"; AHJ21="$(mktemp -d)"
( cd "$REPO_J21" && git init -q && git remote add origin git@git.example.com:example/repo.git )
OUT_J21=$( cd "$REPO_J21" && AMIRAL_HOME="$AHJ21" bash "$HERE/bin/amiral-journal" enable --with-cost </dev/null 2>&1 )
RC_J21=$?
if [ "$RC_J21" != "0" ] && [ ! -f "$REPO_J21/.git/hooks/prepare-commit-msg" ]; then
  ok "J-21 C6 breadth: --with-cost on an ssh-form remote with no TTY is refused, hook NOT written"
else
  ko "J-21 rc=$RC_J21 hook_exists=$([ -f "$REPO_J21/.git/hooks/prepare-commit-msg" ] && echo yes || echo no) out=[$OUT_J21]"
fi

echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
