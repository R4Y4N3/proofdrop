// ProofDrop CLI — compliance-aware private disbursements.
//
//   node cli/proofdrop.js demo [recipient] [campaignId]
//       Build an eligibility set (empty deny list), prove one claim, and write
//       Rust test fixtures + build/args.json. Used by the contract tests and
//       the basic testnet claim.
//
//   node cli/proofdrop.js scenario <recipientA> <recipientB> [campaignId]
//       Full compliance demo: members A and B are both eligible. Emits A's claim
//       proof and B's claim proof (both against an EMPTY deny root), plus the
//       deny root AFTER B is revoked — so the testnet script can show the live
//       contract reject B once the admin updates the deny root.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";
import { buildPoseidon, newMemEmptyTrie } from "circomlibjs";
import * as snarkjs from "snarkjs";
import { StrKey } from "@stellar/stellar-sdk";
import { encodeForSoroban, addressToFrDecimal, frToHex, FR } from "./soroban_encode.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const BUILD = resolve(ROOT, "build");
const KEYS = resolve(BUILD, "keys");
const WASM = resolve(BUILD, "proofdrop_js/proofdrop.wasm");
const ZKEY = resolve(KEYS, "proofdrop_final.zkey");

const DEPTH = 16;      // allowlist Merkle depth
const DENY_LEVELS = 8; // denylist SMT levels (matches circuits/proofdrop.circom)
const AMOUNT = 1_000_000n;

let poseidon, F, H2;

function randField() {
  return BigInt("0x" + randomBytes(31).toString("hex"));
}

function makeIdentity() {
  const identityNullifier = randField();
  const identityTrapdoor = randField();
  const commitment = H2(identityNullifier, identityTrapdoor);
  return { identityNullifier, identityTrapdoor, commitment };
}

// Zero-padded binary Merkle tree (Poseidon) over a small set of leaves.
function buildAllowTree(commitments) {
  const zeros = [0n];
  for (let i = 1; i <= DEPTH; i++) zeros.push(H2(zeros[i - 1], zeros[i - 1]));
  let level = commitments.slice();
  const levels = [level];
  for (let d = 0; d < DEPTH; d++) {
    const next = [];
    const n = Math.ceil(level.length / 2);
    for (let j = 0; j < n; j++) {
      const left = level[2 * j] ?? zeros[d];
      const right = level[2 * j + 1] ?? zeros[d];
      next.push(H2(left, right));
    }
    if (next.length === 0) next.push(H2(zeros[d], zeros[d]));
    level = next;
    levels.push(level);
  }
  return {
    root: levels[DEPTH][0],
    pathFor(idx) {
      const pathElements = [];
      const pathIndices = [];
      let i = idx;
      for (let d = 0; d < DEPTH; d++) {
        const sib = levels[d][i ^ 1] ?? zeros[d];
        pathElements.push(sib.toString());
        pathIndices.push(i & 1);
        i >>= 1;
      }
      return { pathElements, pathIndices };
    },
  };
}

// Sparse Merkle Tree deny list; returns root + a non-membership proof builder.
async function buildDenyTree(revokedCommitments) {
  const tree = await newMemEmptyTrie();
  const TF = tree.F;
  for (const c of revokedCommitments) {
    await tree.insert(TF.e(c), TF.e(1n));
  }
  return {
    root: TF.toObject(tree.root),
    async exclusion(key) {
      const res = await tree.find(TF.e(key));
      if (res.found) throw new Error("key is revoked: cannot build exclusion proof");
      const siblings = res.siblings.map((s) => TF.toObject(s).toString());
      if (siblings.length > DENY_LEVELS) throw new Error("deny tree too deep; retry");
      while (siblings.length < DENY_LEVELS) siblings.push("0");
      return {
        denySiblings: siblings,
        denyOldKey: res.isOld0 ? "0" : TF.toObject(res.notFoundKey).toString(),
        denyOldValue: res.isOld0 ? "0" : TF.toObject(res.notFoundValue).toString(),
        denyIsOld0: res.isOld0 ? 1 : 0,
      };
    },
  };
}

async function prove(member, allowTree, memberIdx, denyTree, recipient, campaignId) {
  const path = allowTree.pathFor(memberIdx);
  const excl = await denyTree.exclusion(member.commitment);
  const recipientHash = addressToFrDecimal(recipient);

  const input = {
    identityNullifier: member.identityNullifier.toString(),
    identityTrapdoor: member.identityTrapdoor.toString(),
    pathElements: path.pathElements,
    pathIndices: path.pathIndices,
    denySiblings: excl.denySiblings,
    denyOldKey: excl.denyOldKey,
    denyOldValue: excl.denyOldValue,
    denyIsOld0: excl.denyIsOld0,
    allowRoot: allowTree.root.toString(),
    denyRoot: denyTree.root.toString(),
    campaignId: campaignId.toString(),
    recipientHash,
    amount: AMOUNT.toString(),
  };
  writeFileSync(resolve(BUILD, "input.json"), JSON.stringify(input, null, 2));
  const WTNS = resolve(BUILD, "witness.wtns");
  console.log("    [1/3] witness calc…");
  const t0 = Date.now();
  await snarkjs.wtns.calculate(input, WASM, WTNS);
  console.log(`    [2/3] proving… (witness ${((Date.now() - t0) / 1000).toFixed(1)}s)`);
  const t1 = Date.now();
  const { proof, publicSignals } = await snarkjs.groth16.prove(ZKEY, WTNS);
  console.log(`    [3/3] proved (${((Date.now() - t1) / 1000).toFixed(1)}s)`);
  const vk = JSON.parse(readFileSync(resolve(KEYS, "verification_key.json")));
  if (!(await snarkjs.groth16.verify(vk, publicSignals, proof)))
    throw new Error("off-chain verification failed");
  return { proof, publicSignals, vk, recipient, recipientHash };
}

async function init() {
  poseidon = await buildPoseidon();
  F = poseidon.F;
  H2 = (a, b) => F.toObject(poseidon([a, b]));
}

function writeFixtures(enc, recipient, allowRootDec, denyRootDec, campaignId) {
  const icArr = enc.vk.ic.map((h) => `        "${h}",`).join("\n");
  const sigArr = enc.publicSignals.map((h) => `        "${h}",`).join("\n");
  // Non-canonical encoding of the nullifier (= nullifier + r): same field
  // element, different 32 bytes. Used by the malleation-replay security test.
  const malleated = (BigInt("0x" + enc.publicSignals[0]) + FR)
    .toString(16)
    .padStart(64, "0");
  const rs = `// AUTO-GENERATED by cli/proofdrop.js — do not edit by hand.
#![allow(dead_code)]

pub const VK_ALPHA: &str = "${enc.vk.alpha}";
pub const VK_BETA: &str = "${enc.vk.beta}";
pub const VK_GAMMA: &str = "${enc.vk.gamma}";
pub const VK_DELTA: &str = "${enc.vk.delta}";
pub const VK_IC: &[&str] = &[
${icArr}
];

pub const PROOF_A: &str = "${enc.proof.a}";
pub const PROOF_B: &str = "${enc.proof.b}";
pub const PROOF_C: &str = "${enc.proof.c}";

// Public signals (BE32 hex), frozen order:
// [nullifierHash, allowRoot, denyRoot, campaignId, recipientHash, amount]
pub const PUB_SIGNALS: &[&str] = &[
${sigArr}
];
pub const IDX_NULLIFIER: usize = 0;
pub const IDX_ALLOW_ROOT: usize = 1;
pub const IDX_DENY_ROOT: usize = 2;
pub const IDX_CAMPAIGN: usize = 3;
pub const IDX_RECIPIENT: usize = 4;
pub const IDX_AMOUNT: usize = 5;

pub const MALLEATED_NULLIFIER: &str = "${malleated}";

pub const RECIPIENT_STRKEY: &str = "${recipient}";
pub const ALLOW_ROOT_DEC: &str = "${allowRootDec}";
pub const DENY_ROOT_DEC: &str = "${denyRootDec}";
pub const CAMPAIGN_ID: u64 = ${campaignId};
pub const AMOUNT: i128 = ${AMOUNT.toString()};
`;
  writeFileSync(resolve(ROOT, "contracts/proofdrop/src/fixtures.rs"), rs);
}

function claimArgs(res, campaignId) {
  const enc = encodeForSoroban(res.vk, res.proof, res.publicSignals);
  return {
    campaignId: Number(campaignId),
    recipient: res.recipient,
    allowRoot: enc.publicSignals[1],
    denyRoot: enc.publicSignals[2],
    vk: enc.vk,
    proof: enc.proof,
    signals: enc.publicSignals,
  };
}

async function cmdDemo() {
  await init();
  const recipient = process.argv[3] ?? StrKey.encodeContract(randomBytes(32));
  const campaignId = BigInt(process.argv[4] ?? "42");

  const ids = Array.from({ length: 5 }, makeIdentity);
  const CLAIMANT = 2;
  const allowTree = buildAllowTree(ids.map((x) => x.commitment));
  // Non-empty deny list (exercises the exclusion path) — none of them is the claimant.
  const deny = await buildDenyTree([makeIdentity().commitment, makeIdentity().commitment]);

  const res = await prove(ids[CLAIMANT], allowTree, CLAIMANT, deny, recipient, campaignId);
  console.log("==> off-chain verification OK");
  console.log("    signals:", res.publicSignals);

  const enc = encodeForSoroban(res.vk, res.proof, res.publicSignals);
  writeFixtures(enc, recipient, allowTree.root.toString(), deny.root.toString(), Number(campaignId));
  writeFileSync(resolve(BUILD, "args.json"), JSON.stringify({ amount: AMOUNT.toString(), ...claimArgs(res, campaignId) }, null, 2));
  console.log("==> wrote fixtures + build/args.json (recipient", recipient + ")");
}

async function cmdScenario() {
  await init();
  const recipientA = process.argv[3];
  const recipientB = process.argv[4];
  const campaignId = BigInt(process.argv[5] ?? "42");
  if (!recipientA || !recipientB) throw new Error("usage: scenario <recipientA> <recipientB> [campaignId]");

  // Eligibility set: A and B (plus padding members).
  const A = makeIdentity();
  const B = makeIdentity();
  const others = [makeIdentity(), makeIdentity()];
  const members = [A, B, ...others];
  const allowTree = buildAllowTree(members.map((m) => m.commitment));

  const denyEmpty = await buildDenyTree([]);                 // root 0
  const denyAfter = await buildDenyTree([B.commitment]);     // B revoked

  const claimA = await prove(A, allowTree, 0, denyEmpty, recipientA, campaignId);
  const claimB = await prove(B, allowTree, 1, denyEmpty, recipientB, campaignId);

  const enc = encodeForSoroban(claimA.vk, claimA.proof, claimA.publicSignals);
  const scenario = {
    amount: AMOUNT.toString(),
    allowRoot: frToHex(allowTree.root.toString()),
    denyRootEmpty: frToHex(denyEmpty.root.toString()),
    denyRootAfterRevokeB: frToHex(denyAfter.root.toString()),
    vk: enc.vk,
    claimA: claimArgs(claimA, campaignId),
    claimB_preRevoke: claimArgs(claimB, campaignId),
  };
  writeFileSync(resolve(BUILD, "scenario.json"), JSON.stringify(scenario, null, 2));
  console.log("==> wrote build/scenario.json");
  console.log("    allowRoot   :", scenario.allowRoot);
  console.log("    denyRoot(∅) :", scenario.denyRootEmpty);
  console.log("    denyRoot(B✗):", scenario.denyRootAfterRevokeB);
}

const cmd = process.argv[2] ?? "demo";
// snarkjs/ffjavascript leave worker threads alive, so Node won't exit on its
// own — exit explicitly once outputs are written.
(cmd === "scenario" ? cmdScenario() : cmdDemo())
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
