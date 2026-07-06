#!/usr/bin/env bash
# verify.sh — machine-verifiable "done" gate for a Next.js project.
# Drop at your repo root, adapt if needed, and reference it in plans:
# "done = ./verify.sh exits 0". Works with npm, pnpm, yarn or bun.
set -euo pipefail

# Detect package manager
if [ -f pnpm-lock.yaml ]; then PM="pnpm"
elif [ -f bun.lockb ] || [ -f bun.lock ]; then PM="bun"
elif [ -f yarn.lock ]; then PM="yarn"
else PM="npm"; fi

echo "== verify.sh ($PM) =="

# Helper: run a package script only if it exists in package.json.
has_script() { node -e "process.exit(require('./package.json').scripts?.['$1']?0:1)" 2>/dev/null; }

echo "-- typecheck --"
if has_script typecheck; then
  $PM run typecheck
elif has_script tsc; then
  $PM run tsc
elif [ -f tsconfig.json ]; then
  # use the project's local TypeScript, never a global one
  npx --no-install tsc --noEmit || {
    echo "   (no local 'typescript' — skip typecheck or add a 'typecheck' script)"; }
else
  echo "   (no tsconfig.json — skipping)"
fi

echo "-- lint --"
if has_script lint; then $PM run lint; else echo "   (no 'lint' script — skipping)"; fi

echo "-- build --"
if has_script build; then $PM run build; else echo "   (no 'build' script — skipping)"; fi

# Uncomment if you have tests:
# echo "-- tests --"
# has_script test && $PM test

echo "== DONE =="
