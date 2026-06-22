# Live testnet deployment

ProofDrop is deployed and **running on Stellar testnet**. A real private claim is
verified on-chain (BN254 Groth16) and paid out; both attack paths are rejected;
the **admin revocation** (compliance control) is demonstrated; and an
**auditor report reconciles the campaign** from on-chain state.

| Item | Value |
|------|-------|
| Network | Stellar **Testnet** |
| ProofDrop contract | [`CDOHFSYP2V2UXQYLS6GFYXSOQMYB6FOUNQYTH7GXXPGF2KFRSE7E22FI`](https://stellar.expert/explorer/testnet/contract/CDOHFSYP2V2UXQYLS6GFYXSOQMYB6FOUNQYTH7GXXPGF2KFRSE7E22FI) |
| Disbursed asset | native XLM SAC `CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC` |
| Admin / funder | `GCAYIAWGRUPZDWDL7ALJAJ4J5FCUFQQU5TI74V7PSXZYJKM7B2O2UZMW` |
| Recipient A (claims) | `GCHZQT3ZL2LZXNXI3PPHRCPIZT7LFLLOKZVSX7BKNOMXUMAKGXSIXYTA` |
| Recipient B (revoked) | `GBJHWESY6SAUFQ7JE5Z3SBNUXQ22OXHCFBFRZNBX2WBKR6X3PM3MBNKV` |

## Transactions (stellar.expert)

| Step | Tx |
|------|----|
| **Private claim (proof-gated payout to A)** | [`7f698d0d…`](https://stellar.expert/explorer/testnet/tx/7f698d0d1bf15e78b7ba3603684184db51dcb7efcf1e878786ec61b26c266bc3) |
| **Admin revokes B** (`set_deny_root`) | [`1e8cd5c2…`](https://stellar.expert/explorer/testnet/tx/1e8cd5c2e502c9544609c4d0475191e984b0e0298407366129328a8418ba9315) |

Recipient A's balance moved `100001000000 → 100002000000` (+0.1 XLM), released
only after on-chain BN254 proof verification. The claim emits a `claim` event
`(campaign_id, nullifier, recipient, amount)`; revocation emits `deny_set`.

## Live policy enforcement (all rejected on-chain)

- **Double-claim** (A again) → `#9 AlreadyClaimed` (nullifier spent).
- **Front-run** (A's proof redirected) → `#7 RecipientMismatch` (proof bound to recipient).
- **Revoked claim** (B after admin updates the deny root) → `#10 DenyRootMismatch`.

## Auditor reconciliation (compliance, no de-anonymization)

`bash scripts/audit.sh <contract> 42` reads on-chain state and prints:

```
 ProofDrop — Auditor Report (Stellar testnet)
 Campaign        : 42
 Asset (SEP-41)  : CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC
 Allowlist root  : 028d09bc…
 Active deny root: 0cf6bf88…
 Successful claims : 1
 Total disbursed   : 1000000
 Conclusion: every payout is one-claim-per-nullifier, bound to this campaign
 and asset, and reconciles to the contract total — with no recipient identity
 revealed on-chain.
```

An auditor verifies totals, claim count, asset/campaign consistency, and the
active policy roots — **without learning who any recipient is.** (Recipient-level
selective disclosure via a viewing key is a documented future step.)

## Reproduce it

```bash
make circuit                 # one-time: compile circuit + Groth16 setup
bash scripts/deploy_testnet.sh   # deploy -> claim -> attacks rejected -> revoke -> audit
```
