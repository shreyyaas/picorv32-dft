# picorv32-dft

Scan insertion, ATPG and Logic BIST on the [PicoRV32](https://github.com/YosysHQ/picorv32)
RISC-V core, using only open-source tools and the SkyWater SKY130 HD standard cells.
Every number in this repo is produced by a script and can be regenerated.

## Flow

| Step | What happens | Tool | Status |
|---|---|---|---|
| 1. Setup | Install tools, PDK, pinned PicoRV32 | OSS CAD Suite, ciel, Fault, Quaigh, OpenROAD | done |
| 2. Baseline | Synthesise PicoRV32 to SKY130 cells; count cells, flops, area | Yosys | done |
| 3. Scan insertion | Swap flops for scan flops, stitch 1 vs N chains; area overhead | OpenROAD `dft` / Fault `chain` | in progress |
| 4. ATPG | Stuck-at patterns on the scan-cut netlist; coverage, pattern count | Fault + Quaigh | |
| 5. Verify | Gate-level scan shift/capture sim; patterns catch injected faults | Icarus Verilog | |
| 6. Logic BIST | LFSR/MISR around the chains; coverage vs ATPG, golden signature | own RTL + Fault sim | |
| 7. Write-up | Results table and reproduction steps | | |

## Tools and what each one does here

| Tool | Role in this flow |
|---|---|
| **Yosys** | Synthesis: turns PicoRV32 RTL into a netlist of SKY130 cells |
| **Icarus Verilog** | Gate-level simulation of scan shift/capture and fault injection |
| **Verilator** | Fast RTL simulation (sanity checks of the core) |
| **ciel** | Downloads a pinned build of the SKY130 PDK (`.lib`, `.lef`, cell Verilog models) |
| **OpenROAD** (`dft` module) | `scan_replace` swaps flops for scan flops; `execute_dft_plan` stitches chains |
| **Fault** | Open DFT toolkit: `cut` (flops → pseudo-I/O), `atpg`, fault simulation, `chain` |
| **Quaigh** | Open-source ATPG engine Fault can call (`fault atpg -g Quaigh`) |

OpenROAD's DFT module only does scan insertion (no ATPG), and Fault's bundled
alternatives Atalanta and NTU PODEM are proprietary, so ATPG here uses
Quaigh and Fault's own pattern generators.

## Setup (Ubuntu 22.04/24.04 or WSL2)

Clone into the Linux filesystem (`~/...`), not `/mnt/c/...`: WSL2 is much slower on the Windows drive.

```bash
git clone https://github.com/shreyyaas/picorv32-dft ~/picorv32-dft
cd ~/picorv32-dft
./scripts/setup.sh          # OSS CAD Suite, venv (ciel, fault-dft), SKY130, Quaigh, PicoRV32
```

OpenROAD has no apt or GitHub-release package. Download the `.deb` for your
Ubuntu version from [OpenROAD VaultLink](https://vaultlink.precisioninno.com/), then:

```bash
OPENROAD_DEB=/mnt/c/Users/<you>/Downloads/<openroad>.deb ./scripts/setup.sh
```

The first run prints the OSS CAD Suite tag and SKY130 PDK hash it chose.
Paste both into `versions.env` and commit, so the toolchain is pinned.

Then, in every new shell:

```bash
source env.sh
make check     # writes results/env.txt (tool versions + PDK files)
make smoke     # Yosys maps PicoRV32 to SKY130 cells
```

## Step 2: Baseline synthesis

```bash
make baseline    # results/baseline/summary.md
```

The baseline is PicoRV32 with its default parameters, synthesised to SKY130 HD
at `tt_025C_1v80` with no DFT. Scan area overhead, coverage and test time are
all measured against it. Choices made in `scripts/synth_baseline.sh`:

- **Scan flops are excluded** (`dont_use *sdf*`), so the baseline cannot contain
  scan cells by accident.
- **Netlist clean-up for the DFT tools**: constant outputs get a tie cell each
  (`hilomap`), output ports that share a net get a buffer (`insbuf`), and
  `check -assert` stops the run if any net is undriven.
- **Area is cross-checked**: the report re-adds every cell's Liberty area and
  fails if the sum differs from Yosys's total.

## Step 3: Scan insertion

```bash
make scan        # results/scan/summary.md, one run per chain count
```

`scripts/scan_insert.tcl` runs OpenROAD's DFT module on the baseline netlist:
`scan_replace` swaps every flop for its SKY130 scan version, a rough
floorplan and global placement give each cell a position, and
`execute_dft_plan` stitches the chains neighbour to neighbour. It runs for
1, 2, 4, 8 and 16 chains.

`scripts/scan_report.py` then:

- recomputes area from the Liberty file and reports the overhead against the baseline;
- traces every chain through the netlist (scan-in port → SCD → Q → SCD …) and saves
  it in shift order to `chains_<N>/chains.json`, which steps 4–6 need;
- checks that every flop was replaced and stitched exactly once, and that the traced
  lengths match OpenROAD's own plan. The tracer was tested on OpenROAD's reference
  scan netlists from its DFT test suite.

## Repo layout

```
versions.env        pinned versions of everything (edit here only)
env.sh              puts the pinned tools on PATH, defines $LIB, $LEF, $CELL_V ...
scripts/
  setup.sh          one-time install, safe to re-run
  fetch_picorv32.sh clone PicoRV32 at the pinned commit
  check_env.sh      report tools/PDK -> results/env.txt
  smoke_synth.sh    toolchain smoke test
  synth_baseline.sh step 2: baseline synthesis (writes results/baseline/)
  baseline_report.py  cells, flops, area, flop breakdown -> summary.md/.json
  scan_insert.sh/.tcl step 3: OpenROAD scan insertion (writes results/scan/)
  scan_report.py      overhead, chains in shift order, consistency checks
results/            measured outputs, committed with env.txt
third_party/        PicoRV32 checkout (git-ignored)
```

## Notes from setup

- **The Yosys version changes the netlist.** With the same RTL and library, Yosys 0.33
  maps all 1597 flops to plain `dfxtp_1`; Yosys 0.70 maps 1280 of them to `edfxtp_1`
  (flop with a built-in enable mux). That changes the scan cells OpenROAD substitutes
  (`sdfxtp` vs `sedfxtp`) and the area overhead, so the Yosys version is pinned and recorded.
- SKY130 HD provides mux-D scan flops (`sdfxtp`, `sedfxtp`, and reset/set variants),
  which is what `scan_replace` needs.
