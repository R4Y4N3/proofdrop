#!/usr/bin/env bash
# End-to-end ProofDrop demo on Stellar testnet — the compliant-privacy story:
#   deploy -> fund campaign -> private claim (A) -> double-claim rejected ->
#   front-run rejected -> admin REVOKES B -> B's claim rejected on-chain.
#
# Requires: stellar-cli, jq, node, and a completed `make circuit`.
set -euo pipefail
export PATH="$HOME/.cargo/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NET=testnet
TOKEN=$(stellar contract id asset --asset native --network $NET)
CID_FILE=build/testnet_contract.txt
CAMPAIGN_ID=42
AMOUNT=1000000      # 0.1 XLM
BUDGET=10000000     # 1 XLM

bold() { printf "\n\033[1m%s\033[0m\n" "$1"; }
inv() { stellar contract invoke --id "$1" --source deployer --network $NET -- "${@:2}"; }
fails() { if "$@" >/dev/null 2>&1; then echo "UNEXPECTED SUCCESS"; else echo "REJECTED ✅"; fi; }

bold "1. Identities"
for k in deployer recipientA recipientB; do
  stellar keys generate $k --network $NET --fund 2>/dev/null || true
done
DEPLOYER=$(stellar keys address deployer)
RA=$(stellar keys address recipientA)
RB=$(stellar keys address recipientB)
echo "   admin/funder: $DEPLOYER"
echo "   recipient A : $RA"
echo "   recipient B : $RB"

bold "2. Build + deploy contract"
( cd contracts/proofdrop && stellar contract build >/dev/null 2>&1 )
WASM=contracts/proofdrop/target/wasm32v1-none/release/proofdrop.wasm
CID=$(stellar contract deploy --wasm "$WASM" --source deployer --network $NET 2>/dev/null | tail -1)
echo "$CID" > "$CID_FILE"
echo "   contract: $CID"

bold "3. Generate scenario proofs (A and B both eligible; B will be revoked)"
node cli/proofdrop.js scenario "$RA" "$RB" "$CAMPAIGN_ID" >/dev/null
jq -c .vk                    build/scenario.json > build/vk.json
jq -c .claimA.proof          build/scenario.json > build/proofA.json
jq -c .claimA.signals        build/scenario.json > build/signalsA.json
jq -c .claimB_preRevoke.proof   build/scenario.json > build/proofB.json
jq -c .claimB_preRevoke.signals build/scenario.json > build/signalsB.json
ALLOW=$(jq -r .allowRoot build/scenario.json)
DENY_EMPTY=$(jq -r .denyRootEmpty build/scenario.json)
DENY_AFTER=$(jq -r .denyRootAfterRevokeB build/scenario.json)

bold "4. Create + fund campaign (deny list empty)"
inv "$CID" create_campaign --funder "$DEPLOYER" --admin "$DEPLOYER" \
  --campaign_id "$CAMPAIGN_ID" --allow_root "$ALLOW" --deny_root "$DENY_EMPTY" \
  --token "$TOKEN" --amount "$AMOUNT" --budget "$BUDGET" --vk-file-path build/vk.json >/dev/null
echo "   campaign $CAMPAIGN_ID funded"

bold "5. Private claim by A"
echo -n "   A balance before: "; inv "$TOKEN" balance --id "$RA" 2>/dev/null || echo "(rpc hiccup)"
inv "$CID" claim --campaign_id "$CAMPAIGN_ID" --proof-file-path build/proofA.json \
  --signals-file-path build/signalsA.json --recipient "$RA" >/dev/null
echo -n "   A balance after:  "; inv "$TOKEN" balance --id "$RA" 2>/dev/null || echo "(rpc hiccup)"

bold "6. Attacks rejected"
echo -n "   double-claim (A again)       -> "
fails inv "$CID" claim --campaign_id "$CAMPAIGN_ID" --proof-file-path build/proofA.json --signals-file-path build/signalsA.json --recipient "$RA"
echo -n "   front-run (A proof -> admin) -> "
fails inv "$CID" claim --campaign_id "$CAMPAIGN_ID" --proof-file-path build/proofA.json --signals-file-path build/signalsA.json --recipient "$DEPLOYER"

bold "7. Compliance: admin REVOKES B, then B's claim is rejected on-chain"
inv "$CID" set_deny_root --campaign_id "$CAMPAIGN_ID" --new_deny_root "$DENY_AFTER" >/dev/null
echo "   admin updated deny root (B revoked)"
echo -n "   B claim after revocation     -> "
fails inv "$CID" claim --campaign_id "$CAMPAIGN_ID" --proof-file-path build/proofB.json --signals-file-path build/signalsB.json --recipient "$RB"

bold "8. Auditor reconciliation (no recipient de-anonymized)"
bash scripts/audit.sh "$CID" "$CAMPAIGN_ID" || true

bold "Done. Contract: $CID"
