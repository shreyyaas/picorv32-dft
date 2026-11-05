#!/usr/bin/env bash
# Step 2: baseline synthesis of PicoRV32 to SKY130 HD cells, with NO DFT.
# Every later step (scan, ATPG, BIST) is measured against this netlist.
#
# Outputs in results/baseline/:
#   baseline.ys          the exact Yosys script that was run (committed)
#   picorv32_syn.v       the gate-level netlist           (git-ignored, regenerate)
#   yosys.log            full Yosys log                   (git-ignored)
#   stat.json            cell counts from `stat -json`    (committed)
#   summary.md/.json     cells, flops, area, flop breakdown (committed)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/env.sh"
OUT="$REPO_ROOT/results/baseline"; mkdir -p "$OUT"
RTL="$REPO_ROOT/third_party/picorv32/picorv32.v"
[ -f "$RTL" ] || "$REPO_ROOT/scripts/fetch_picorv32.sh"

# Cells synthesis must never pick:
#   *sdf*            scan flops: a baseline by definition has no scan cells
#   *lpflow* *probe* power-domain and probe cells (same list as OpenROAD-flow-scripts)
DONT_USE="-dont_use *sdf* -dont_use *lpflow* -dont_use *probe*"

# Written to a file so the exact script is saved next to the results.
cat > "$OUT/baseline.ys" <<EOF
# --- read: library first, so Yosys knows each cell's pin directions
read_liberty -lib $LIB
read_verilog $RTL
hierarchy -check -top picorv32        # default parameters (see summary.md)

# --- generic synthesis, flattened to one module
synth -top picorv32 -flatten

# --- technology mapping to SKY130 HD
dfflibmap -liberty $LIB $DONT_USE     # flip-flops
abc -liberty $LIB $DONT_USE           # combinational logic

# --- netlist clean-up for the DFT tools that read it next
setundef -zero                        # no 'x' constants left in the netlist
splitnets                             # multi-bit wires -> single bits
opt_clean -purge
hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO
opt_clean -purge                      # constants -> one tie cell per bit
insbuf -buf sky130_fd_sc_hd__buf_4 A X
opt_clean -purge                      # ports sharing a net -> buffer between them
check -assert                         # stop if anything is undriven or shorted

# --- reports and netlist
tee -q -o $OUT/stat.json stat -json -liberty $LIB
tee -q -o $OUT/stat.txt  stat -liberty $LIB
write_verilog -noattr -nohex -nodec $OUT/picorv32_syn.v
EOF

echo "synthesising with $(yosys -V)"
yosys -q -l "$OUT/yosys.log" -s "$OUT/baseline.ys" >/dev/null

python3 "$REPO_ROOT/scripts/baseline_report.py" \
  --lib "$LIB" --netlist "$OUT/picorv32_syn.v" --stat "$OUT/stat.json" \
  --rtl "$RTL" --out "$OUT"
