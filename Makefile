.PHONY: demo circuit prove test wasm dashboard audit clean

# One command for judges: build circuit, generate a proof, run on-chain tests.
demo: circuit prove test

circuit:
	bash scripts/build_circuit.sh

prove:
	node cli/proofdrop.js demo

test:
	cd contracts/proofdrop && cargo test

wasm:
	cd contracts/proofdrop && cargo build --release --target wasm32v1-none
	@ls -la contracts/proofdrop/target/wasm32v1-none/release/proofdrop.wasm

# Compliance views over the LIVE testnet contract:
dashboard:
	bash scripts/gen_dashboard.sh
	@echo "→ open web/index.html in a browser"

audit:
	bash scripts/audit.sh $$(cat build/testnet_contract.txt 2>/dev/null) 42

clean:
	rm -rf build node_modules contracts/proofdrop/target
