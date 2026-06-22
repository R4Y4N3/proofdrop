#!/usr/bin/env bash
# Compile the ProofDrop circuit, run a (demo) Groth16 trusted setup on BN254,
# and export the verification key. Produces everything needed to generate and
# verify proofs. NOT a production ceremony — the phase-2 contribution here is a
# single local contribution for reproducibility. Documented in the README.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$PATH"

BUILD="$ROOT/build"
KEYS="$BUILD/keys"
PTAU="$BUILD/pot16_final.ptau"
POWER=16            # supports up to 2^16 = 65536 constraints (allow Merkle + deny SMT)
mkdir -p "$BUILD" "$KEYS"

echo "==> [1/6] Installing JS deps (circomlib, snarkjs, circomlibjs, stellar-sdk)"
[ -d node_modules ] || npm install --silent

echo "==> [2/6] Compiling circuit (BN254)"
circom circuits/proofdrop.circom \
  --r1cs --wasm --sym \
  -l node_modules \
  -o "$BUILD"
echo "    constraints:"; snarkjs r1cs info "$BUILD/proofdrop.r1cs" | sed 's/^/      /'

if [ ! -f "$PTAU" ]; then
  echo "==> [3/6] Powers of Tau (phase 1, bn128, power $POWER) — local demo ceremony"
  snarkjs powersoftau new bn128 "$POWER" "$BUILD/pot_0000.ptau" -v
  snarkjs powersoftau contribute "$BUILD/pot_0000.ptau" "$BUILD/pot_0001.ptau" \
    --name="proofdrop-demo" -v -e="proofdrop entropy $(date +%s)"
  snarkjs powersoftau prepare phase2 "$BUILD/pot_0001.ptau" "$PTAU" -v
else
  echo "==> [3/6] Reusing existing $PTAU"
fi

echo "==> [4/6] Groth16 setup (phase 2)"
snarkjs groth16 setup "$BUILD/proofdrop.r1cs" "$PTAU" "$BUILD/proofdrop_0000.zkey"
snarkjs zkey contribute "$BUILD/proofdrop_0000.zkey" "$KEYS/proofdrop_final.zkey" \
  --name="proofdrop-demo-2" -v -e="proofdrop phase2 $(date +%s)"

echo "==> [5/6] Export verification key"
snarkjs zkey export verificationkey "$KEYS/proofdrop_final.zkey" "$KEYS/verification_key.json"

echo "==> [6/6] Done."
echo "    circuit wasm : $BUILD/proofdrop_js/proofdrop.wasm"
echo "    proving key  : $KEYS/proofdrop_final.zkey"
echo "    verify key   : $KEYS/verification_key.json"
echo
echo "Next: node cli/proofdrop.js demo   # build a tree, prove, and emit Soroban test fixtures"
