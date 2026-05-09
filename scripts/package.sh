#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Cleaning previous .mcpb"
rm -f ./*.mcpb

echo "==> Backing up dev node_modules"
if [ -d node_modules ]; then
  rm -rf node_modules.dev
  mv node_modules node_modules.dev
fi

restore_dev_modules() {
  if [ -d node_modules.dev ]; then
    rm -rf node_modules
    mv node_modules.dev node_modules
  fi
}
trap restore_dev_modules EXIT

echo "==> Installing prod-only flat node_modules (hoisted linker)"
pnpm install --prod --shamefully-hoist --no-frozen-lockfile

echo "==> Packing .mcpb via @anthropic-ai/mcpb"
npx -y @anthropic-ai/mcpb pack

echo "==> .mcpb produced:"
ls -1 ./*.mcpb
