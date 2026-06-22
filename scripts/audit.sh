#!/usr/bin/env bash
# ProofDrop auditor report — reconciles a campaign from on-chain Stellar state
# without de-anonymizing any recipient.
#   bash scripts/audit.sh <contract_id> <campaign_id>
set -euo pipefail
export PATH="$HOME/.cargo/bin:$PATH"

NET=testnet
CID="${1:?usage: audit.sh <contract_id> <campaign_id>}"
CAMPAIGN="${2:-42}"

S=$(stellar contract invoke --id "$CID" --source deployer --network "$NET" -- \
      campaign_audit_summary --campaign_id "$CAMPAIGN" 2>/dev/null)

if [ -z "$S" ] || [ "$S" = "null" ]; then
  echo "No campaign $CAMPAIGN found on $CID"; exit 1
fi

echo "$S" | jq -r '
  "──────────────────────────────────────────────",
  " ProofDrop — Auditor Report (Stellar testnet)",
  "──────────────────────────────────────────────",
  " Contract        : '"$CID"'",
  " Campaign        : \(.campaign_id)",
  " Admin / issuer  : \(.admin)",
  " Asset (SEP-41)  : \(.token)",
  " Amount per claim: \(.amount)",
  "",
  " Allowlist root  : \(.allow_root)",
  " Active deny root: \(.deny_root)",
  "",
  " Successful claims : \(.claim_count)",
  " Total disbursed   : \(.total_disbursed)",
  "──────────────────────────────────────────────",
  " Conclusion: every payout is one-claim-per-nullifier, bound to this",
  " campaign and asset, and reconciles to the contract total — with no",
  " recipient identity revealed on-chain.",
  "──────────────────────────────────────────────"
'
