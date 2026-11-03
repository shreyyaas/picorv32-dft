# Each target runs one script. Run `source env.sh` once per shell first.
.PHONY: setup fetch check smoke clean

setup:            ## install tools, PDK and PicoRV32 (one time)
	./scripts/setup.sh

fetch:            ## clone PicoRV32 at the pinned commit
	./scripts/fetch_picorv32.sh

check:            ## record tool versions and PDK files in results/env.txt
	./scripts/check_env.sh

smoke: fetch      ## prove Yosys can map PicoRV32 to SKY130 cells
	./scripts/smoke_synth.sh

clean:            ## remove generated outputs (keeps tools and PDK)
	rm -rf results/smoke
