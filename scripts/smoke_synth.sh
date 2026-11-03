#!/usr/bin/env bash
# Smoke test: can Yosys read PicoRV32 and map it to SKY130 HD cells?
# This only proves the toolchain works. The real baseline (step 2)
# adds a dont_use list, fixed parameters and a reviewed script.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/env.sh"
OUT="$REPO_ROOT/results/smoke"; mkdir -p "$OUT"

yosys -q -l "$OUT/yosys.log" -p "
  read_verilog $REPO_ROOT/third_party/picorv32/picorv32.v
  synth -top picorv32 -flatten
  dfflibmap -liberty $LIB
  abc -liberty $LIB
  opt_clean
  tee -o $OUT/stat.txt stat -liberty $LIB
" >/dev/null 2>"$OUT/warnings.txt"
# Expected warnings: dfflibmap skips the scan/enable flops (their D pin is
# a mux expression). We want plain flops here; scan replacement is step 3.
echo "yosys : $(yosys -V)   ($(wc -l < "$OUT/warnings.txt") warnings in results/smoke/warnings.txt)"

echo "cells : $(grep -m1 -E 'Number of cells' "$OUT/stat.txt" | grep -oE '[0-9]+$' || awk '/cells$/{print $1; exit}' "$OUT/stat.txt")"
# stat format differs by Yosys version: old "name count", new "count area name"
FLOPS=$(grep -E 'sky130_fd_sc_hd__[a-z]*df' "$OUT/stat.txt" | awk '
  { n = ($1 ~ /^[0-9]+$/) ? $1 : $NF
    for (i=1;i<=NF;i++) if ($i ~ /sky130/) { sub(/.*__/,"",$i); c=$i }
    t += n; s = s " " c "=" n }
  END { print t " (" substr(s,2) ")" }')
echo "flops : $FLOPS"
echo "area  : $(grep -m1 -oE 'Chip area[^:]*: *[0-9.]+' "$OUT/stat.txt" | grep -oE '[0-9.]+$') um^2"
echo "full report: results/smoke/stat.txt"
