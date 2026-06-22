#!/usr/bin/env bash
# Generate the read-only dashboard data from the LIVE testnet contract.
#   bash scripts/gen_dashboard.sh [contract_id] [campaign_id]
# Writes web/data.js (loaded by web/index.html — no server/CORS needed).
set -euo pipefail
export PATH="$HOME/.cargo/bin:$PATH"

NET=testnet
CID="${1:-$(cat build/testnet_contract.txt 2>/dev/null || echo CDOHFSYP2V2UXQYLS6GFYXSOQMYB6FOUNQYTH7GXXPGF2KFRSE7E22FI)}"
CAMPAIGN="${2:-42}"
mkdir -p web

SUMMARY=$(stellar contract invoke --id "$CID" --source deployer --network "$NET" -- \
            campaign_audit_summary --campaign_id "$CAMPAIGN" 2>/dev/null)
if [ -z "$SUMMARY" ] || [ "$SUMMARY" = "null" ]; then
  echo "No campaign $CAMPAIGN on $CID"; exit 1
fi
TOKEN=$(echo "$SUMMARY" | jq -r .token)
BAL=$(stellar contract invoke --id "$TOKEN" --source deployer --network "$NET" -- \
        balance --id "$CID" 2>/dev/null | tr -d '"' || echo "0")

DATA=$(jq -n --arg cid "$CID" --arg net "$NET" --arg bal "${BAL:-0}" \
  --arg campaign "$CAMPAIGN" --argjson s "$SUMMARY" '{
    contract:$cid, network:$net, campaignId:$campaign, remainingBalance:$bal,
    summary:$s,
    facts:{ constraints:15886, system:"Groth16 / BN254", curve:"BN254 (Protocol 25 X-Ray)", tests:"7 / 7 passing" }
  }')
echo "window.DASHBOARD_DATA = $DATA;" > web/data.js
echo "wrote web/data.js (open web/index.html)"
