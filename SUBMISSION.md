# ProofDrop

> Submission writeup. The clean text from **Tagline** down is what goes on the
> DoraHacks form (fill the two links first). Skip the one block marked
> **"✋ Repo note"** — that's a checklist for you, not for the form.

## Tagline
**Compliance-ready private disbursement rails for Stellar** — pay approved recipients
in stablecoins without doxxing the eligibility set on-chain, with one-claim anti-abuse,
issuer revocation, and auditor-ready reporting.

## Links
- **Repo:** https://github.com/R4Y4N3/proofdrop
- **Demo video (2–3 min):** https://youtu.be/jkfChJQgCL0
- **Live contract (testnet):** [`CCHOFZBK…6AXFS`](https://stellar.expert/explorer/testnet/contract/CCHOFZBKZVBBCGSJFYPUV3Q4HPY3GOMBX2Q7H4CLP3IIBOX2W6U6AXFS)
- **Private claim tx:** [`0fa86207…`](https://stellar.expert/explorer/testnet/tx/0fa86207117ed0869e66af8738d4213b1c189376f2650b53e925b1a6526031e4)

## What (problem)
Organizations already send stablecoins to people on Stellar — humanitarian aid,
payroll, grants. On a public ledger this exposes **every recipient**, lets bots
**farm claims**, and gives issuers **no way to revoke** a sanctioned recipient.
Regulated organizations are forced to choose between privacy and compliance.

## Why (it matters)
Privacy without compliance can't be adopted by regulated institutions; compliance
without privacy doxxes vulnerable recipients (aid beneficiaries, employees). The
sweet spot SDF itself points to is **"compliant privacy"** — private recipients,
public policy controls. That's the unlock for real-world stablecoin disbursement at
institutional scale.

## Who (it's for)
NGOs distributing aid, employers running confidential payroll, and protocols running
grants/airdrops — i.e. the [Stellar Disbursement Platform](https://developers.stellar.org/docs/platforms/stellar-disbursement-platform)
audience, plus a privacy + compliance layer.

## How (it works)
An issuer publishes two roots on-chain: an **allow root** (eligibility set) and an
admin-controlled **deny root** (revocation / sanction list). An eligible person
claims a fixed stablecoin payout by submitting **one Groth16 proof** that, in zero
knowledge, simultaneously shows:

1. **Allowlist membership** — they're approved (Merkle membership), revealing no identity.
2. **Denylist non-membership** — they're not revoked (SMT exclusion proof).
3. **One-claim** — a per-campaign **nullifier** prevents double-claims.
4. **Recipient/amount binding** — the proof is tied to its recipient and amount, so it
   can't be stolen from the mempool and redirected.

The proof is generated **off-chain** (Circom / Groth16 / BN254) and **verified
on-chain** inside a Soroban smart contract using Stellar's native BN254 host
functions; the contract then pays a **SEP-41** token. An **auditor report** (and a
read-only web dashboard) reconciles totals, claim count, and policy roots from
on-chain state — **without revealing which eligibility-set member each claim maps
to** (recipient address and amount are public, as in any payment).

## Stellar / Soroban integration (essential, not bolted-on)
- **On-chain ZK verification** with Soroban's **BN254** host functions
  (`g1_mul`, `g1_add`, `pairing_check`) added in **Protocol 25 "X-Ray"** — this is the
  core of the product, not a side feature.
- **SEP-41 token payout** — the contract holds a funded budget and disburses on a
  successful proof (demoed with the native asset; works with any SEP-41 stablecoin).
- **Soroban contract** (`#![no_std]`, ~12 KB wasm): campaign registry, nullifier
  store, admin revocation (`set_deny_root`), auditor views, and `claim`/`deny_set`/
  `created` events for indexers.
- **Deployed and exercised on Stellar testnet** — a real private claim is verified
  and paid; double-claim, front-run, and revoked claims are all rejected on-chain
  (see tx links).

Why Stellar specifically: Stellar is built for **real-world money movement**, and
Protocol 25 added the on-chain **BN254** host functions used to verify these proofs
cheaply (Poseidon runs inside the Circom circuit). ProofDrop couldn't exist on
Stellar a protocol ago.

## Why ZK is load-bearing
Remove the proof and the product disappears: the contract could not know the claimant
is **eligible, not revoked, and unique** without learning **who they are**. The ZK
proof is the only thing that makes private-yet-compliant disbursement possible.

## Requirements checklist (Stellar Hacks: Real-World ZK)
- ✅ **Open-source repo + clear README** — full source, architecture, threat model, run steps. MIT licensed.
- ✅ **2–3 min demo video** — walkthrough of the live testnet flow (link above). Keep it within 2–3 min.
- ✅ **ZK + Stellar, load-bearing** — Groth16 proofs verified in a Soroban contract; ZK gates every claim.

---

### ✋ Repo note — do NOT paste below (pre-submit checklist for you)
- [ ] **Repo is PUBLIC** and the link is in the submission.
- [ ] **Demo video link is public** (unlisted YouTube/Loom is fine) and **2–3 min**.
- [ ] **Answer every required question** on the DoraHacks form (incl. "is your repo + video public?").
- [ ] Code is **original to this hackathon** (it is — see Credits in the README) and **not submitted to another hackathon**.
- [ ] **LICENSE** present (MIT, included).

## Tech stack
Circom 2 / circomlib (Poseidon, SMT) · Groth16 · BN254 · snarkjs · Soroban Rust SDK
26 · stellar-cli · Node CLI · static web dashboard.

## What's verified
7/7 contract tests (valid claim, double-claim, front-run, tampered-signal, revocation,
audit reconciliation, **non-canonical-signal replay** — a real bug we found in our own
security audit and fixed). Zero-warning build. Reproducible one-command demo
(`scripts/deploy_testnet.sh`).

## Honest limitations & roadmap
- Demo trusted setup is a single local ceremony (production needs an MPC ceremony).
- Eligibility issuance (who's on the allowlist) is the issuer's process — we prove
  membership privately, we don't establish personhood (issuer-gated eligibility).
- Amounts/recipients are visible at the SEP-41 transfer; the deny tree is demo-depth.
- **Roadmap:** recipient-level selective disclosure via an **auditor-attested
  enrollment registry** (viewing key) — designed and documented; deliberately kept
  out of the claim circuit to preserve proving reliability.

## Why it can win
It's a **live, on-thesis** Stellar app: real on-chain ZK verification, a real SEP-41
payout, and the **compliant-privacy** controls (allow + deny + auditor reconciliation)
that SDF calls the real-world adoption sweet spot — aligned with Stellar's real-world
ZK direction.
