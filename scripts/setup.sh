#!/usr/bin/env bash
# One-time tool installation for Ubuntu 22.04/24.04 (native or WSL2).
# Safe to re-run: every step skips work that is already done.
#
#   ./scripts/setup.sh                       # everything except OpenROAD
#   OPENROAD_DEB=/path/openroad.deb ./scripts/setup.sh   # also install OpenROAD
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/versions.env"
EDA_HOME="${EDA_HOME:-$HOME/eda}"
export PDK_ROOT="${PDK_ROOT:-$HOME/.ciel}"
mkdir -p "$EDA_HOME"
step() { printf '\n=== %s ===\n' "$*"; }

if [[ "$REPO_ROOT" == /mnt/* ]]; then
  echo "WARNING: repo is on the Windows drive ($REPO_ROOT)."
  echo "         Builds are much slower there. Clone it under ~ instead."
fi

step "1/6 apt prerequisites"
sudo apt-get update -qq
sudo apt-get install -y -qq git curl ca-certificates build-essential \
     python3 python3-venv python3-pip cargo

step "2/6 OSS CAD Suite (Yosys, Icarus, Verilator, GTKWave)"
if [ -x "$EDA_HOME/oss-cad-suite/bin/yosys" ]; then
  echo "already installed: $("$EDA_HOME/oss-cad-suite/bin/yosys" -V)"
else
  API=https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases
  [ -n "$OSS_CAD_TAG" ] && API="$API/tags/$OSS_CAD_TAG" || API="$API/latest"
  read -r TAG URL < <(curl -fsSL "$API" | python3 -c '
import json, sys
r = json.load(sys.stdin)
a = [x for x in r["assets"] if "linux-x64" in x["name"] and x["name"].endswith(".tgz")]
print(r["tag_name"], a[0]["browser_download_url"])')
  echo "downloading OSS CAD Suite $TAG"
  curl -fL --progress-bar "$URL" | tar -xz -C "$EDA_HOME"
  echo ">>> Pin it: set OSS_CAD_TAG=$TAG in versions.env"
fi

step "3/6 Python venv: ciel $CIEL_VERSION, fault-dft $FAULT_VERSION"
# Use the system python explicitly (OSS CAD Suite ships its own python)
[ -d "$REPO_ROOT/.venv" ] || /usr/bin/python3 -m venv "$REPO_ROOT/.venv"
"$REPO_ROOT/.venv/bin/pip" install -q --upgrade pip
"$REPO_ROOT/.venv/bin/pip" install -q "ciel==$CIEL_VERSION" "fault-dft==$FAULT_VERSION"

step "4/6 SKY130 PDK via ciel (PDK_ROOT=$PDK_ROOT)"
CIEL="$REPO_ROOT/.venv/bin/ciel"
HASH="$SKY130_PDK_HASH"
if [ -z "$HASH" ]; then
  # ls-remote lists builds newest first; take the first commit hash shown
  HASH="$("$CIEL" ls-remote --pdk-family sky130 | grep -oE '[0-9a-f]{40}' | head -1)"
  echo ">>> Pin it: set SKY130_PDK_HASH=$HASH in versions.env"
fi
"$CIEL" enable --pdk-family sky130 "$HASH"

step "5/6 Quaigh $QUAIGH_VERSION (open-source ATPG used by Fault)"
if command -v "$HOME/.cargo/bin/quaigh" >/dev/null; then
  echo "already installed: $("$HOME/.cargo/bin/quaigh" --version)"
else
  cargo install --locked "quaigh@$QUAIGH_VERSION" || {
    echo "cargo install failed. Your apt Rust may be too old; install rustup:"
    echo "  curl https://sh.rustup.rs -sSf | sh    then re-run this script"; }
fi

step "6/6 OpenROAD (scan insertion)"
if command -v openroad >/dev/null; then
  echo "already installed: $(openroad -version 2>/dev/null | head -1)"
elif [ -n "${OPENROAD_DEB:-}" ]; then
  sudo apt-get install -y "$OPENROAD_DEB"
else
  . /etc/os-release
  cat <<EOF
OpenROAD is not installed. Prebuilt packages are not on apt or GitHub:
  1. Open https://vaultlink.precisioninno.com/ in your Windows browser
  2. Download the .deb for Ubuntu $VERSION_ID
  3. Re-run:  OPENROAD_DEB=/mnt/c/Users/<you>/Downloads/<file>.deb ./scripts/setup.sh
EOF
fi

step "PicoRV32 source"
"$REPO_ROOT/scripts/fetch_picorv32.sh"

echo; echo "Done. Next:  source env.sh && ./scripts/check_env.sh"
