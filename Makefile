# Each target runs one script. Run `source env.sh` once per shell first.
.PHONY: setup fetch check smoke baseline scan clean

setup:            ## install tools, PDK and PicoRV32 (one time)
	./scripts/setup.sh

fetch:            ## clone PicoRV32 at the pinned commit
	./scripts/fetch_picorv32.sh

check:            ## record tool versions and PDK files in results/env.txt
	./scripts/check_env.sh

smoke: fetch      ## prove Yosys can map PicoRV32 to SKY130 cells
	./scripts/smoke_synth.sh

baseline: fetch   ## step 2: synthesise PicoRV32 to SKY130 HD with no DFT
	./scripts/synth_baseline.sh

scan:             ## step 3: scan insertion with OpenROAD (1,2,4,8,16 chains)
	./scripts/scan_insert.sh

clean:            ## remove generated outputs (keeps tools and PDK)
	rm -rf results/smoke results/baseline results/scan
