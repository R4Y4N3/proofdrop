#!/usr/bin/env bash
# Cinematic, self-playing ProofDrop demo for SCREEN RECORDING.
# Just run this while recording your screen — it paces itself and shows big
# captions for each beat. Read the voiceover from VIDEO_SCRIPT.md as it plays.
#
#   bash scripts/record_demo.sh
#
# Requires: stellar-cli, jq, node, and a completed `make circuit`.
set -euo pipefail
export PATH="$HOME/.cargo/bin:$PATH"
export TERM=${TERM:-xterm-256color}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

NET=testnet
TOKEN=$(stellar contract id asset --asset native --network $NET)
CAMPAIGN_ID=42; AMOUNT=1000000; BUDGET=10000000

# ----- presentation helpers -----
C_RESET=$'\033[0m'; C_B=$'\033[1m'; C_CYAN=$'\033[1;36m'; C_GRN=$'\033[1;32m'
C_RED=$'\033[1;31m'; C_YEL=$'\033[1;33m'; C_DIM=$'\033[2m'
banner(){ printf "\n${C_CYAN}╔══════════════════════════════════════════════════════════╗${C_RESET}\n"; \
          printf   "${C_CYAN}║${C_RESET} ${C_B}%-56s${C_RESET} ${C_CYAN}║${C_RESET}\n" "$1"; \
          printf   "${C_CYAN}╚══════════════════════════════════════════════════════════╝${C_RESET}\n"; }
say(){ printf "${C_DIM}» %s${C_RESET}\n" "$1"; }
ok(){ printf "   ${C_GRN}✅ %s${C_RESET}\n" "$1"; }
no(){ printf "   ${C_RED}⛔ %s${C_RESET}\n" "$1"; }
pause(){ sleep "${1:-3}"; }
inv(){ stellar contract invoke --id "$1" --source deployer --network $NET -- "${@:2}"; }
submit(){ # retry a should-succeed call up to 5x on transient testnet errors (TxBadSeq)
  local n=0; while ! inv "$@" >/dev/null 2>/tmp/pd_err; do
    n=$((n+1)); if [ $n -ge 5 ]; then cat /tmp/pd_err; return 1; fi
    printf "${C_DIM}   (retrying… %s)${C_RESET}\n" "$n"; sleep 5; done; }
fails(){ # runs a claim, expects on-chain rejection; prints the contract error code
  local out; if out=$("$@" 2>&1); then echo "UNEXPECTED SUCCESS"; else
    echo "$out" | grep -oE 'Error\(Contract, #[0-9]+\)' | head -1; fi; }

clear 2>/dev/null || true
banner "ProofDrop — private compliant disbursements on Stellar"
say "Aid, payroll and grants need privacy for recipients AND compliance."
say "One ZK proof. Verified on-chain by Soroban. Let's watch it live on testnet."
pause 4

banner "1. Setup: issuer, two eligible recipients, fresh contract"
stellar keys generate deployer  --network $NET --fund >/dev/null 2>&1 || true
stellar keys generate recipientA --network $NET --fund >/dev/null 2>&1 || true
stellar keys generate recipientB --network $NET --fund >/dev/null 2>&1 || true
DEPLOYER=$(stellar keys address deployer); RA=$(stellar keys address recipientA); RB=$(stellar keys address recipientB)
say "issuer/admin : $DEPLOYER"
say "recipient A  : $RA"
say "recipient B  : $RB  (will be revoked)"
( cd contracts/proofdrop && stellar contract build >/dev/null 2>&1 )
WASM=contracts/proofdrop/target/wasm32v1-none/release/proofdrop.wasm
CID=$(stellar contract deploy --wasm "$WASM" --source deployer --network $NET 2>/dev/null | tail -1)
ok "contract deployed: $CID"
pause 3

banner "2. Generate ZK proofs (Circom / Groth16 / BN254)"
say "Each proof shows: allowlist membership ∧ NOT on denylist ∧ one-claim nullifier ∧ recipient/amount binding."
node cli/proofdrop.js scenario "$RA" "$RB" "$CAMPAIGN_ID" >/dev/null
jq -c .vk build/scenario.json > build/vk.json
jq -c .claimA.proof build/scenario.json > build/proofA.json
jq -c .claimA.signals build/scenario.json > build/signalsA.json
jq -c .claimB_preRevoke.proof build/scenario.json > build/proofB.json
jq -c .claimB_preRevoke.signals build/scenario.json > build/signalsB.json
ALLOW=$(jq -r .allowRoot build/scenario.json); DENY0=$(jq -r .denyRootEmpty build/scenario.json); DENY1=$(jq -r .denyRootAfterRevokeB build/scenario.json)
ok "proofs generated off-chain; identities never leave the client"
pause 3

banner "3. Issuer funds a private campaign (1 XLM budget)"
submit "$CID" create_campaign --funder "$DEPLOYER" --admin "$DEPLOYER" --campaign_id "$CAMPAIGN_ID" \
  --allow_root "$ALLOW" --deny_root "$DENY0" --token "$TOKEN" --amount "$AMOUNT" --budget "$BUDGET" \
  --vk-file-path build/vk.json
ok "campaign $CAMPAIGN_ID funded"
pause 3

banner "4. Recipient A claims privately — paid on-chain"
say "balance before:"; printf "   "; inv "$TOKEN" balance --id "$RA" 2>/dev/null
submit "$CID" claim --campaign_id "$CAMPAIGN_ID" --proof-file-path build/proofA.json \
  --signals-file-path build/signalsA.json --recipient "$RA"
say "balance after:"; printf "   "; inv "$TOKEN" balance --id "$RA" 2>/dev/null
ok "BN254 proof verified on-chain → 0.1 XLM disbursed"
pause 4

banner "5. Attacks rejected on-chain"
printf "   double-claim (replay A's proof) ........ "
no "$(fails inv "$CID" claim --campaign_id "$CAMPAIGN_ID" --proof-file-path build/proofA.json --signals-file-path build/signalsA.json --recipient "$RA")"
printf "   front-run (redirect A's proof) ......... "
no "$(fails inv "$CID" claim --campaign_id "$CAMPAIGN_ID" --proof-file-path build/proofA.json --signals-file-path build/signalsA.json --recipient "$DEPLOYER")"
pause 4

banner "6. Compliance: issuer REVOKES recipient B"
submit "$CID" set_deny_root --campaign_id "$CAMPAIGN_ID" --new_deny_root "$DENY1"
ok "admin updated the deny root (B is now sanctioned)"
printf "   B was eligible — now B's claim ......... "
no "$(fails inv "$CID" claim --campaign_id "$CAMPAIGN_ID" --proof-file-path build/proofB.json --signals-file-path build/signalsB.json --recipient "$RB")"
pause 4

banner "7. Auditor reconciliation from on-chain state"
echo "$CID" > build/testnet_contract.txt
bash scripts/audit.sh "$CID" "$CAMPAIGN_ID" || true
pause 4

banner "Private · Sybil-resistant · revocable · auditor-ready"
say "Live on Stellar testnet. Contract: $CID"
printf "${C_YEL}   Explorer: https://stellar.expert/explorer/testnet/contract/%s${C_RESET}\n\n" "$CID"
