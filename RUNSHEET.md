# 🎬 ProofDrop — recording run-sheet (~2.5 min, one take)

Open this on your phone or a second screen. Start recording, then follow the
**[DO]** actions and read the **SAY** lines naturally. The demo script pauses on
each caption, so you have time to talk over it.

**Before you start:** terminal fullscreen, big font (`Ctrl+Shift++`). Optionally do
one practice run first and keep that contract's stellar.expert page open in a tab.

---

**[DO] Start recording — `Ctrl+Alt+Shift+R` (orange dot appears).**

### ① Intro (~15s) — before running anything
> "Hi — this is **ProofDrop**, compliance-ready private disbursement rails on
> Stellar. Organizations like NGOs or employers can pay approved people in
> stablecoins **without exposing who's on their list**, while still blocking fraud
> and sanctioned users. Everything you'll see is **live on Stellar testnet**."

### ② Run the demo
**[DO] Type and run:**
```bash
bash scripts/record_demo.sh
```
Narrate each caption as it appears:

- **Deploy / setup:** "It's deploying a fresh contract and two eligible recipients."
- **Generate proofs:** "Each recipient makes a **zero-knowledge proof** off-chain — proving they're on the allowlist, **not** on the denylist, and haven't claimed before, without revealing their identity."
- **Fund campaign:** "The issuer funds a private campaign."
- **Claim (balance rises):** "Recipient A submits their proof. Soroban **verifies it on-chain with BN254** and pays out — watch the balance go up."
- **Attacks (#9, #7):** "Replaying the same proof is **rejected** — the nullifier is spent. Redirecting it to an attacker is **rejected** — the proof is bound to the recipient."
- **Revoke (#10):** "Now compliance: the issuer **revokes** recipient B on-chain. B was eligible a second ago — now B's claim is **rejected**."
- **Auditor report:** "An auditor reconciles totals and policy roots from chain — without learning which member each claim maps to."

### ③ Show it's real on stellar.expert (~20s)
**[DO]** The script prints an **`Explorer:`** URL at the end. Copy it → open browser → paste.
> "And here it is on the public block explorer — the live contract, the claim
> transaction that paid out, and the revocation event. This is real, on Stellar
> testnet."

**[DO]** Scroll the contract's **History / Events** so the transactions are visible.

### ④ Close (~10s)
> "So that's ProofDrop — private eligibility, Sybil-resistance, issuer revocation,
> and auditor-ready reporting, all verified on-chain on Stellar. Thanks for
> watching."

**[DO] Stop recording — `Ctrl+Alt+Shift+R`. File saved to `~/Videos/Screencasts/`.**

---

### Tips
- **Don't rush** — the script's pauses are for you to talk; the next caption waits.
- If you fumble a line, just pause and repeat it — you can trim later in CapCut.
- Keep it **2–3 minutes** total (hard cap 3:00).
