# Live testnet deployment

ProofDrop is deployed and **running on Stellar testnet**. A real private claim is
verified on-chain (BN254 Groth16) and paid out; both attack paths are rejected;
the **admin revocation** (compliance control) is demonstrated; and an
**auditor report reconciles the campaign** from on-chain state.

| Item | Value |
|------|-------|
| Network | Stellar **Testnet** |
| ProofDrop contract | [`CCHOFZBKZVBBCGSJFYPUV3Q4HPY3GOMBX2Q7H4CLP3IIBOX2W6U6AXFS`](https://stellar.expert/explorer/testnet/contract/CCHOFZBKZVBBCGSJFYPUV3Q4HPY3GOMBX2Q7H4CLP3IIBOX2W6U6AXFS) |
| Disbursed asset | native XLM SAC `CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC` |
| Admin / funder | `GCAYIAWGRUPZDWDL7ALJAJ4J5FCUFQQU5TI74V7PSXZYJKM7B2O2UZMW` |
| Recipient A (claims) | `GCHZQT3ZL2LZXNXI3PPHRCPIZT7LFLLOKZVSX7BKNOMXUMAKGXSIXYTA` |
| Recipient B (revoked) | `GBJHWESY6SAUFQ7JE5Z3SBNUXQ22OXHCFBFRZNBX2WBKR6X3PM3MBNKV` |

## Transactions (verified via Soroban RPC; click to view)

| Step | Event | Transaction |
|------|-------|-------------|
| Create + fund campaign #42 | `created` | [`e059ee26…`](https://stellar.expert/explorer/testnet/tx/e059ee26a9d54409f3cd780af824b55cc78b53777f6e53158bc57a5b93882df4) |
| **Private claim (proof-gated payout to A)** | `claim` | [`0fa86207…`](https://stellar.expert/explorer/testnet/tx/0fa86207117ed0869e66af8738d4213b1c189376f2650b53e925b1a6526031e4) |
| **Admin revokes B** (`set_deny_root`) | `deny_set` | [`a3f05413…`](https://stellar.expert/explorer/testnet/tx/a3f05413d3b296fb0f35efeafa0ff47d946af608a5e4b0beda78b43d9b3a60ab) |

The claim released 0.1 XLM to recipient A only after on-chain BN254 proof
verification; the contract's remaining balance reflects the disbursement.

> Note: stellar.expert's **contract-level** Events/History tabs can lag on testnet.
> The individual transaction pages above render immediately, and Soroban RPC
> `getEvents` confirms all three contract events (`created`, `claim`, `deny_set`).

## Live policy enforcement (all rejected on-chain)

- **Double-claim** (A again) → `#9 AlreadyClaimed` (nullifier spent).
- **Front-run** (A's proof redirected) → `#7 RecipientMismatch` (proof bound to recipient).
- **Revoked claim** (B after admin updates the deny root) → `#10 DenyRootMismatch`.

## Auditor reconciliation (compliance, no eligibility de-anonymization)

`bash scripts/audit.sh <contract> 42` reads on-chain state and prints campaign
totals, claim count, asset/campaign consistency, and the active allow/deny roots —
**without revealing which eligibility-set member each claim maps to** (recipient
address + amount are public, as in any payment). Recipient-level selective
disclosure via a viewing key is a documented future step.

## Reproduce it

```bash
make circuit                     # one-time: compile circuit + Groth16 setup
bash scripts/deploy_testnet.sh   # deploy -> claim -> attacks rejected -> revoke -> audit
```
