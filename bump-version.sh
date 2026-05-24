#!/usr/bin/env bash
set -euo pipefail

NEW_VERSION="${1:-}"
if [ -z "$NEW_VERSION" ]; then
  echo "Usage: ./bump-version.sh <new-version>"
  echo "Example: ./bump-version.sh 1.1.0"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Update package.json
node -e "
  const fs = require('fs');
  const p = '$ROOT/package.json';
  const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
  pkg.version = '$NEW_VERSION';
  fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
"

# Update manifest.json
node -e "
  const fs = require('fs');
  const p = '$ROOT/manifest.json';
  const manifest = JSON.parse(fs.readFileSync(p, 'utf8'));
  manifest.version = '$NEW_VERSION';
  fs.writeFileSync(p, JSON.stringify(manifest, null, 2) + '\n');
"

echo "✓ Bumped to v$NEW_VERSION"
echo "  → package.json"
echo "  → manifest.json"
