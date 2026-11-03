#!/usr/bin/env bash
# Report which tools and PDK files are present, with versions.
# Writes results/env.txt so every result in the repo records the
# exact toolchain it came from. Exits 1 if a required item is missing.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/env.sh"
OUT="$REPO_ROOT/results/env.txt"; mkdir -p "$(dirname "$OUT")"
missing=0

row() { printf '%-10s %-8s %s\n' "$1" "$2" "$3"; }
tool() {  # name, required(1/0), version command...
  local name=$1 req=$2; shift 2
  if command -v "$1" >/dev/null 2>&1; then
    row "$name" OK "$("$@" 2>&1 | grep -v '^WARNING' | head -1)  [$(command -v "$1")]"
  elif [ "$req" = 1 ]; then row "$name" MISSING "(required)"; missing=1
  else row "$name" MISSING "(needed from step 3)"; fi
}
file() {
  if [ -f "$2" ]; then row "$1" OK "$2"
  else row "$1" MISSING "$2"; missing=1; fi
}

# Not piped into tee: a pipe would run this in a subshell and lose $missing
report() {
  echo "# picorv32-dft environment  $(date -u +%Y-%m-%dT%H:%MZ)"
  . /etc/os-release; echo "# OS: $PRETTY_NAME  $(uname -r)"
  grep -qi microsoft /proc/version && echo "# Running under WSL"
  echo
  tool yosys     1 yosys -V
  tool iverilog  1 iverilog -V
  tool verilator 1 verilator --version
  tool gtkwave   0 gtkwave --version
  tool fault     1 fault --version
  tool nl2bench  1 nl2bench --help
  tool quaigh    1 quaigh --version
  tool ciel      1 ciel --version
  tool openroad  0 openroad -version
  echo
  echo "# PDK  (PDK_ROOT=$PDK_ROOT)"
  file liberty  "$LIB"
  file cell-lef "$LEF"
  file tech-lef "$TECH_LEF"
  file cell-v   "$CELL_V"
  file prim-v   "$PRIM_V"
  [ -f "$LIB" ] && row scan-ffs INFO \
    "$(grep -oE 'cell *\( *"?sky130_fd_sc_hd__s[a-z]*df[a-z]*_[0-9]+' "$LIB" | sed 's/.*__//' | sort -u | tr '\n' ' ')"
  echo
  echo "# PicoRV32"
  P="$REPO_ROOT/third_party/picorv32"
  if [ -f "$P/picorv32.v" ]; then row picorv32 OK "$(git -C "$P" rev-parse HEAD)"
  else row picorv32 MISSING "run scripts/fetch_picorv32.sh"; missing=1; fi
}
report > "$OUT"; cat "$OUT"

echo; [ $missing = 0 ] && echo "All required items present." \
                       || echo "Some required items are missing (see above)."
exit $missing
