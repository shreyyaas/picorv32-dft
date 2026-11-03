#!/usr/bin/env bash
# Clone PicoRV32 at the commit pinned in versions.env.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/versions.env"
DEST="$REPO_ROOT/third_party/picorv32"

[ -d "$DEST/.git" ] || git clone -q "$PICORV32_REPO" "$DEST"
git -C "$DEST" fetch -q origin
git -C "$DEST" -c advice.detachedHead=false checkout -q "$PICORV32_COMMIT"
echo "picorv32 at $(git -C "$DEST" rev-parse HEAD)"
