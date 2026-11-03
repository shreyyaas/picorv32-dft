# picorv32-dft

Scan insertion, ATPG and Logic BIST on the [PicoRV32](https://github.com/YosysHQ/picorv32)
RISC-V core, using only open-source tools and the SkyWater SKY130 HD standard cells.
Every number in this repo is produced by a script and can be regenerated.

## Flow

| Step | What happens | Tool | Status |
|---|---|---|---|
| 1. Setup | Install tools, PDK, pinned PicoRV32 | OSS CAD Suite, ciel, Fault, Quaigh, OpenROAD | done |
| 2. Baseline | Synthesise PicoRV32 to SKY130 cells; count cells, flops, area | Yosys | next |
| 3. Scan insertion | Swap flops for scan flops, stitch 1 vs N chains; area overhead | OpenROAD `dft` / Fault `chain` | |
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

## Repo layout

```
versions.env        pinned versions of everything (edit here only)
env.sh              puts the pinned tools on PATH, defines $LIB, $LEF, $CELL_V ...
scripts/
  setup.sh          one-time install, safe to re-run
  fetch_picorv32.sh clone PicoRV32 at the pinned commit
  check_env.sh      report tools/PDK -> results/env.txt
  smoke_synth.sh    toolchain smoke test
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
