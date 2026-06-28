# ProofDrop — 2–3 min demo video script

**Easiest path (recommended):** start your screen recorder, then run
**`bash scripts/record_demo.sh`** — it auto-plays the whole demo with big captions
and pacing (deploy → claim → attacks rejected → revoke → auditor report), live on
testnet, in ~2 min. Read the voiceover below as it plays. No typing, no camera
needed. (`scripts/deploy_testnet.sh` is the same flow without the cinematic pacing.)

Target length: **2:40**. Keep terminal font large. Add a one-line caption per beat.

---

### 0:00–0:20 — Hook (show the payoff first)
> "ProofDrop is compliance-oriented private disbursement rails for Stellar. In the
> next two minutes you'll see a real testnet claim get paid after one ZK proof —
> then watch a double-claim, a stolen-proof redirect, and a revoked recipient all
> fail on-chain. The problem is simple: aid, payroll, and grants need
> accountability without exposing every recipient."

*On screen:* title card — **ProofDrop: compliance-ready private disbursement rails for Stellar.**

### 0:20–0:45 — The solution
> "ProofDrop fixes this with zero-knowledge. An eligible user proves, privately,
> three things at once: they're in the campaign's allow-list, they're NOT on the
> revocation list, and they haven't claimed before — without revealing which
> identity they are. A Soroban smart contract verifies that proof on-chain and
> releases the tokens."

*On screen:* the architecture diagram from the README (off-chain Circom proof →
on-chain BN254 verify → payout).

### 0:45–1:45 — Live demo (run `scripts/deploy_testnet.sh`)
Narrate each labelled beat as it prints:

1. **(~0:50) Valid private claim.**
   > "Recipient A submits a proof. The contract verifies it with Stellar's native
   > BN254 pairing check and pays out — A's balance goes up. Nothing on-chain
   > reveals which allow-list entry A used."
   *Caption: ✅ Private claim → paid out.* (Open the claim tx on stellar.expert.)

2. **(~1:10) Double-claim blocked.**
   > "A tries again with the same proof. Rejected — error 9, AlreadyClaimed. The
   > nullifier is spent. One claim per identity, enforced on-chain."
   *Caption: 🔒 Double-claim → #9 AlreadyClaimed.*

3. **(~1:25) Front-run blocked.**
   > "An attacker grabs A's proof from the mempool and points it at their own
   > address. Rejected — error 7, RecipientMismatch. The proof is cryptographically
   > bound to its recipient."
   *Caption: 🛡️ Front-run → #7 RecipientMismatch.*

4. **(~1:40) Compliance — revocation.**
   > "Now the issuer revokes recipient B by updating the deny root on-chain. B was
   > eligible a moment ago — but B's claim is now rejected, error 10,
   > DenyRootMismatch. Everyone else's privacy is untouched."
   *Caption: ⚖️ Admin revokes B → #10 DenyRootMismatch.*

### 1:45–2:00 — Compliance: the auditor report
> "And for compliance, the auditor doesn't need to de-anonymize anyone. This
> report, read straight from Stellar state, proves the total paid, the number of
> one-time claims, asset and campaign consistency, and the active deny list —
> privacy with accountability."

*Caption: 📊 Auditor report — totals reconciled, no identity revealed.*
*(Run `bash scripts/audit.sh <contract> 42`, or open the read-only dashboard
`web/index.html` (`make dashboard`) to show claims, totals, and reconciliation
visually with explorer links.)*

### 2:00–2:20 — Why ZK is load-bearing
> "The zero-knowledge proof isn't decoration — it's the whole product. Without it,
> the contract could not know the claimant is eligible, not revoked, and unique,
> all while keeping their identity private. That's the trade public blockchains
> usually can't make."

### 2:20–2:40 — Stellar fit + close
> "It runs on Soroban testnet today: Groth16 BN254 proofs verified on-chain, a
> SEP-41 token payout, and a one-command reproducible demo with explorer links in
> the repo. ProofDrop is the compliance-ready privacy layer the Stellar
> Disbursement Platform is missing — private eligibility, Sybil resistance,
> issuer revocation, and on-chain stablecoin payout, exactly where Stellar is
> taking real-world privacy."

*On screen:* final card with the contract ID + the DEPLOYMENT.md link.

---

### Shot checklist
- [ ] Terminal font ≥ 18pt, dark theme, clear.
- [ ] One caption per demo beat (claim / double-claim / front-run / revoke).
- [ ] Show at least one real tx open on stellar.expert (the payout).
- [ ] Keep under 3:00. If tight, trim the intro, never the 4 demo beats.
- [ ] Say the three error names out loud (#9, #7, #10) — they prove it's real.
