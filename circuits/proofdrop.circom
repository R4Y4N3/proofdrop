pragma circom 2.1.6;

// ProofDrop — private, Sybil-resistant, *compliance-aware* disbursement claim.
//
// A holder of a secret identity proves, in zero knowledge:
//   1. ALLOW: their identity commitment is a leaf in the campaign's eligibility
//      Merkle tree (approved by the issuer) — without revealing which leaf.
//   2. DENY:  their identity commitment is NOT in the campaign's revocation /
//      sanction Sparse Merkle Tree (an Association-Set-Provider style deny
//      list the issuer/ASP controls) — a non-membership proof.
//   3. A per-campaign nullifier, so the contract enforces one-claim-per-identity.
//   4. The recipient address (field-reduced hash) and amount are bound in, so a
//      valid proof can't be stolen and redirected (anti-front-running).
//
// This is the "compliant privacy" pattern: private recipients, public policy
// controls (allow + deny roots), verified on-chain in a Soroban contract via
// BN254 host functions.
//
// Public signal order produced by snarkjs (output first, then public inputs in
// declaration order) — FROZEN, must match the contract:
//   [ nullifierHash, allowRoot, denyRoot, campaignId, recipientHash, amount ]

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/smt/smtverifier.circom";

// One level of a binary Merkle tree using Poseidon(2).
template MerkleLevel() {
    signal input cur;
    signal input sibling;
    signal input pathIndex;
    signal output out;

    pathIndex * (1 - pathIndex) === 0;

    signal left;
    signal right;
    left  <== cur + pathIndex * (sibling - cur);
    right <== sibling + pathIndex * (cur - sibling);

    component h = Poseidon(2);
    h.inputs[0] <== left;
    h.inputs[1] <== right;
    out <== h.out;
}

template MerkleRoot(depth) {
    signal input leaf;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    signal output root;

    component levels[depth];
    signal cur[depth + 1];
    cur[0] <== leaf;
    for (var i = 0; i < depth; i++) {
        levels[i] = MerkleLevel();
        levels[i].cur <== cur[i];
        levels[i].sibling <== pathElements[i];
        levels[i].pathIndex <== pathIndices[i];
        cur[i + 1] <== levels[i].out;
    }
    root <== cur[depth];
}

template ProofDrop(depth, denyLevels) {
    // ---- private inputs ----
    signal input identityNullifier;
    signal input identityTrapdoor;
    signal input pathElements[depth];     // allowlist authentication path
    signal input pathIndices[depth];
    // denylist non-membership (Sparse Merkle Tree exclusion proof)
    signal input denySiblings[denyLevels];
    signal input denyOldKey;
    signal input denyOldValue;
    signal input denyIsOld0;

    // ---- public inputs ----
    signal input allowRoot;
    signal input denyRoot;
    signal input campaignId;
    signal input recipientHash;
    signal input amount;

    // ---- public output ----
    signal output nullifierHash;

    // 1. identity commitment = Poseidon(nullifier, trapdoor)
    component idc = Poseidon(2);
    idc.inputs[0] <== identityNullifier;
    idc.inputs[1] <== identityTrapdoor;

    // 2. ALLOW: membership in the eligibility tree
    component mr = MerkleRoot(depth);
    mr.leaf <== idc.out;
    for (var i = 0; i < depth; i++) {
        mr.pathElements[i] <== pathElements[i];
        mr.pathIndices[i] <== pathIndices[i];
    }
    mr.root === allowRoot;

    // 3. DENY: non-membership in the revocation tree (SMT exclusion, fnc = 1)
    component smt = SMTVerifier(denyLevels);
    smt.enabled <== 1;
    smt.fnc <== 1;                 // 1 = verify EXCLUSION (non-membership)
    smt.root <== denyRoot;
    for (var i = 0; i < denyLevels; i++) {
        smt.siblings[i] <== denySiblings[i];
    }
    smt.oldKey <== denyOldKey;
    smt.oldValue <== denyOldValue;
    smt.isOld0 <== denyIsOld0;
    smt.key <== idc.out;          // the identity commitment is the deny key
    smt.value <== 0;

    // 4. nullifier = Poseidon(identityNullifier, campaignId)
    component nf = Poseidon(2);
    nf.inputs[0] <== identityNullifier;
    nf.inputs[1] <== campaignId;
    nullifierHash <== nf.out;

    // 5. bind recipientHash and amount into the proof
    signal recipientBind;
    recipientBind <== recipientHash * recipientHash;
    signal amountBind;
    amountBind <== amount * amount;
}

// denyLevels = 8 keeps total constraints < 2^14 so the FFT domain (and proving
// memory) matches the original; ample for a demo revocation list.
component main { public [allowRoot, denyRoot, campaignId, recipientHash, amount] } = ProofDrop(16, 8);
