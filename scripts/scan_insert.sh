#!/usr/bin/env bash
# Step 3: insert scan chains into the step-2 baseline, once per chain count,
# and report area overhead and chain lengths.
#
#   ./scripts/scan_insert.sh            # chain counts 1 2 4 8 16
#   CHAINS="1 8" ./scripts/scan_insert.sh
#
# Outputs in results/scan/:
#   chains_<N>/picorv32_scan.v   scan netlist        (git-ignored, regenerate)
#   chains_<N>/openroad.log      full OpenROAD log   (git-ignored)
#   chains_<N>/chains.json       every chain, in shift order (committed)
#   summary.md / summary.json    overhead and chain lengths  (committed)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/env.sh"
BASE="$REPO_ROOT/results/baseline"
OUT="$REPO_ROOT/results/scan"; mkdir -p "$OUT"

[ -f "$BASE/picorv32_syn.v" ] || { echo "No baseline netlist: run 'make baseline' first"; exit 1; }
command -v openroad >/dev/null || { echo "openroad not found: see README setup"; exit 1; }
echo "OpenROAD $(openroad -version 2>/dev/null | head -1)"

for N in ${CHAINS:-1 2 4 8 16}; do
  D="$OUT/chains_$N"; mkdir -p "$D"
  printf 'chains=%-3s ... ' "$N"
  if MAX_CHAINS=$N NETLIST="$BASE/picorv32_syn.v" OUT_DIR="$D" \
       openroad -exit -no_init -no_splash -log "$D/openroad.log" \
       "$REPO_ROOT/scripts/scan_insert.tcl" >/dev/null 2>&1; then
    echo "done"
  else
    echo "FAILED: last lines of $D/openroad.log:"; tail -15 "$D/openroad.log"; exit 1
  fi
done

python3 "$REPO_ROOT/scripts/scan_report.py" --lib "$LIB" --baseline "$BASE" --scan "$OUT"
