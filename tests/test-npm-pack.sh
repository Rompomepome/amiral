#!/usr/bin/env bash
# npm-pack security battery (v0.17.0). The non-negotiable shape: `npm i -g
# @rompomepome/amiral` installs two commands on PATH and does NOTHING else —
# no postinstall, no touching ~/.claude, no shell rc edits. This battery is
# the one guard against that constraint silently regressing:
#   1. the tarball ships exactly what install.sh needs (files: allowlist),
#      and none of the audit/test/docs cruft that shouldn't leave the repo.
#   2. package.json carries no postinstall/preinstall/install script — the
#      literal mechanism that would make `npm i` a silent config-rewrite.
#   3. an end-to-end `npm i -g <tgz>` into a hermetic temp prefix + temp
#      HOME: after install, the temp ~/.claude is untouched; only running
#      `amiral-install` afterwards (an explicit, knowing action) lands the
#      config — reusing test-fresh-install.sh's own assertions so the npm
#      route is held to the same bar as the git-clone route.
# Hermetic throughout: temp HOME, temp CLAUDE_CONFIG_DIR, temp npm prefix.
# Never touches the caller's real ~/.claude or global npm state.
export LC_ALL=C
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ok  $1"; PASS=$((PASS+1)); }
ko(){ echo "  KO  $1"; FAIL=$((FAIL+1)); }

if ! command -v npm >/dev/null 2>&1; then
  echo "  SKIP: npm not found in PATH — cannot exercise the npm-pack battery"
  echo ""; echo "  0 passed, 0 failed"
  exit 0
fi

WORK="$(mktemp -d)"
TARBALL=""
cleanup() {
  [ -n "$TARBALL" ] && rm -f "$TARBALL"
  rm -rf "$WORK"
}
trap cleanup EXIT

# ─── step 1: npm pack the real package, inspect its file list ───
PACK_JSON="$(cd "$HERE" && npm pack --json --pack-destination "$WORK" 2>/dev/null)"
TARBALL="$WORK/$(python3 -c "import json,sys; print(json.loads(sys.argv[1])[0]['filename'])" "$PACK_JSON" 2>/dev/null)"

if [ -f "$TARBALL" ]; then
  ok "npm pack produced a tarball ($TARBALL)"
else
  ko "npm pack did not produce a tarball — cannot continue this battery"
  echo ""; echo "  $PASS passed, $FAIL failed"
  exit 1
fi

FILELIST="$(tar tzf "$TARBALL")"

# every file install.sh copies (spot-check the critical ones), all under
# npm's package/ prefix inside the tarball.
MUST_CONTAIN="
install.sh
uninstall.sh
CLAUDE.md
agents/implementer.md
skills/plan-ship/SKILL.md
shell/amiral-profiles.sh
bin/amiral-butin
bin/amiral-journal
bin/amiral-doctor
lib/butin/core.awk
lib/butin/measure.py
lib/butin/agents.sh
lib/butin/amiral-agents.txt
lib/butin/pricing.tsv
adapters/claude-code/butin-receipt.sh
"
for f in $MUST_CONTAIN; do
  if echo "$FILELIST" | grep -q "^package/$f$"; then
    ok "tarball contains $f"
  else
    ko "tarball MISSING $f — install.sh would fail against this package"
  fi
done

# none of the audit/test/docs cruft.
# (README.fr.md IS in the tarball and that's expected, not a leak: npm ALWAYS
# ships files matching README* regardless of the files: allowlist — so it is
# deliberately absent from this MUST_NOT list.)
MUST_NOT_CONTAIN="tests/ AUDIT-FABLE DESIGN-NOTES IDEAS.md docs/ BENCHMARKS.md CHANGELOG.md examples/ .github/"
for f in $MUST_NOT_CONTAIN; do
  if echo "$FILELIST" | grep -q "^package/$f"; then
    ko "tarball CONTAINS excluded path matching '$f' — files: allowlist regressed"
  else
    ok "tarball does not contain '$f'"
  fi
done

# Build/editor artifacts must NEVER ship. npm's files: allowlist does NOT
# re-apply .gitignore/.npmignore filtering to files sitting inside a
# wholesale-listed directory (documented npm behavior), so a stray
# lib/butin/__pycache__/*.pyc (measure.py/backfill.py generate these), a
# *.amiral-bak.* backup, or a .DS_Store in a dirty local clone would leak
# into a hand-run `npm publish`. The publish workflow packs from a fresh
# checkout so CI is safe, but this gate catches a dirty-clone publish too —
# nested paths the anchored ^package/ loop above can't see.
if echo "$FILELIST" | grep -qE '__pycache__|\.pyc$|\.bak\.|\.DS_Store$'; then
  ko "tarball CONTAINS a build/editor artifact (.pyc/__pycache__/.bak/.DS_Store) — dirty-clone leak"
  echo "$FILELIST" | grep -E '__pycache__|\.pyc$|\.bak\.|\.DS_Store$' | sed 's/^/    /'
else
  ok "tarball carries no build/editor artifacts (no .pyc/__pycache__/.bak/.DS_Store)"
fi

# ─── step 2: the postinstall guard — the constraint that must never regress ───
PACKED_PKG_JSON="$(tar xzOf "$TARBALL" package/package.json)"
if echo "$PACKED_PKG_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
scripts = d.get('scripts', {})
bad = [k for k in ('postinstall', 'preinstall', 'install') if k in scripts]
sys.exit(1 if bad else 0)
"; then
  ok "packed package.json has NO postinstall/preinstall/install script"
else
  ko "packed package.json DOES carry a postinstall/preinstall/install script — this is the exact regression that must never happen"
fi

# ─── step 3: end-to-end npm i -g <tgz> into a hermetic prefix + temp HOME ───
NPM_PREFIX="$WORK/npm-prefix"
mkdir -p "$NPM_PREFIX"
TMP_HOME="$WORK/home"
mkdir -p "$TMP_HOME"

INSTALL_G_OUT="$(HOME="$TMP_HOME" npm_config_prefix="$NPM_PREFIX" npm install -g "$TARBALL" --no-audit --no-fund 2>&1)"
INSTALL_G_RC=$?

if [ "$INSTALL_G_RC" = "0" ]; then
  ok "npm i -g <tgz> into a hermetic prefix exits 0"
else
  ko "npm i -g <tgz> failed (rc=$INSTALL_G_RC) — out=[$INSTALL_G_OUT]"
fi

# (a) the temp HOME's ~/.claude must be untouched — proves no postinstall
# silently wrote config.
if [ ! -d "$TMP_HOME/.claude" ]; then
  ok "SECURITY: npm i -g left \$HOME/.claude untouched (no postinstall side effect)"
else
  ko "SECURITY REGRESSION: \$HOME/.claude exists after npm i -g — something wrote config on install"
fi

# (b) the amiral-install bin exists in the temp prefix's bin.
AMIRAL_INSTALL_BIN="$NPM_PREFIX/bin/amiral-install"
AMIRAL_UNINSTALL_BIN="$NPM_PREFIX/bin/amiral-uninstall"
if [ -x "$AMIRAL_INSTALL_BIN" ]; then
  ok "amiral-install lands on PATH in the npm prefix's bin/"
else
  ko "amiral-install NOT found (or not executable) at $AMIRAL_INSTALL_BIN"
fi
if [ -x "$AMIRAL_UNINSTALL_BIN" ]; then
  ok "amiral-uninstall lands on PATH in the npm prefix's bin/"
else
  ko "amiral-uninstall NOT found (or not executable) at $AMIRAL_UNINSTALL_BIN"
fi

# (c) running amiral-install (explicit action) lands config in ~/.claude,
# exactly like the git-clone route — reuse test-fresh-install's assertions.
CLAUDE_DIR="$TMP_HOME/.claude"
if [ -x "$AMIRAL_INSTALL_BIN" ]; then
  # `bash "$BIN"` is equivalent to direct exec here: BASH_SOURCE[0] is still the
  # bin's own (symlinked) path, so install.sh's REPO_DIR symlink-walk resolves
  # the real package dir identically to a PATH invocation — this DOES exercise
  # the npm symlink, it isn't bypassing it.
  RUN_OUT="$(HOME="$TMP_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_DIR" bash "$AMIRAL_INSTALL_BIN" 2>&1)"
  RUN_RC=$?
  if [ "$RUN_RC" = "0" ]; then
    ok "amiral-install (npm-installed bin) exits 0"
  else
    ko "amiral-install (npm-installed bin) exited $RUN_RC — out=[$RUN_OUT]"
  fi

  for f in agents/implementer.md agents/grunt.md agents/reviewer.md agents/corsaire.md \
           agents/advisor.md skills/plan-ship/SKILL.md amiral-profiles.sh amiral-profiles.ps1 \
           butin/core.awk butin/agents.sh butin/amiral-agents.txt butin/measure.py \
           butin/butin-receipt.sh butin/pricing.tsv amiral-journal amiral-doctor; do
    if [ -f "$CLAUDE_DIR/$f" ]; then
      ok "npm-installed amiral-install landed \$CLAUDE_DIR/$f"
    else
      ko "npm-installed amiral-install did NOT land \$CLAUDE_DIR/$f — REPO_DIR symlink resolution likely broken"
    fi
  done

  if grep -q '@amiral-policy.md' "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
    ok "npm-installed amiral-install wired the @amiral-policy.md import into CLAUDE.md"
  else
    ko "npm-installed amiral-install did NOT wire the @amiral-policy.md import"
  fi

  # confirm installed butin/ files match the repo's byte-for-byte (at
  # minimum) — the measure path itself is already covered end-to-end by
  # tests/test-fresh-install.sh against the git-clone route.
  if diff -q "$HERE/lib/butin/core.awk" "$CLAUDE_DIR/butin/core.awk" >/dev/null 2>&1; then
    ok "installed butin/core.awk matches the repo's copy byte-for-byte"
  else
    ko "installed butin/core.awk DIFFERS from the repo's copy"
  fi
else
  ko "cannot exercise amiral-install (bin missing) — skipping post-install file assertions"
fi

echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
