#!/usr/bin/env bash
# verify.sh — machine-verifiable "done" gate for a Next.js project.
# Drop at your repo root, adapt the commands, and reference it in your
# plans: "done = ./verify.sh exits 0". Works with npm, pnpm or bun.
set -euo pipefail

# Detect package manager
if [ -f pnpm-lock.yaml ]; then PM="pnpm"
elif [ -f bun.lockb ] || [ -f bun.lock ]; then PM="bun"
else PM="npm"; fi

echo "== verify.sh ($PM) =="

echo "-- typecheck --"
npx tsc --noEmit

echo "-- lint --"
$PM run lint

echo "-- build --"
$PM run build

# Uncomment if you have tests:
# echo "-- tests --"
# $PM test

echo "== ALL GREEN =="
