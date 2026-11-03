# shellcheck shell=bash
# Source this in every new shell:   source env.sh
# It puts the pinned tools on PATH and defines the PDK paths the scripts use.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT
source "$REPO_ROOT/versions.env"

# Tools live in ~/eda so they stay on the Linux filesystem (fast in WSL2)
export EDA_HOME="${EDA_HOME:-$HOME/eda}"
export PDK_ROOT="${PDK_ROOT:-$HOME/.ciel}"

# OSS CAD Suite first, then the project venv (so its python/fault win)
[ -d "$EDA_HOME/oss-cad-suite/bin" ] && export PATH="$EDA_HOME/oss-cad-suite/bin:$PATH"
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"
[ -d "$REPO_ROOT/.venv/bin" ] && export PATH="$REPO_ROOT/.venv/bin:$PATH"

# Tell Fault exactly which Yosys / Icarus to use (otherwise it may fall
# back to the slower WebAssembly yowasp-yosys it ships with)
FAULT_YOSYS="$(command -v yosys)"       && export FAULT_YOSYS
FAULT_IVERILOG="$(command -v iverilog)" && export FAULT_IVERILOG

# SKY130 HD library files (open_pdks layout created by ciel)
export SC_DIR="$PDK_ROOT/sky130A/libs.ref/$STD_CELL_LIB"
export LIB="$SC_DIR/lib/${STD_CELL_LIB}__${LIB_CORNER}.lib"
export LEF="$SC_DIR/lef/${STD_CELL_LIB}.lef"
export TECH_LEF="$SC_DIR/techlef/${STD_CELL_LIB}__nom.tlef"
export CELL_V="$SC_DIR/verilog/${STD_CELL_LIB}.v"
export PRIM_V="$SC_DIR/verilog/primitives.v"
