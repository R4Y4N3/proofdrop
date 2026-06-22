// Encode snarkjs (BN254/bn128) verification key, proof, and public signals into
// the byte layout expected by Soroban's env.crypto().bn254() host functions.
//
// Soroban BN254 uses the Ethereum/EVM convention (verified against
// soroban-env-host src/crypto/bn254.rs):
//   - Fp  : 32-byte BIG-ENDIAN
//   - Fp2 : c1 || c0  (imaginary component first), each 32-byte big-endian
//   - G1  : X || Y                       (64 bytes)
//   - G2  : X.c1 || X.c0 || Y.c1 || Y.c0 (128 bytes)
//   - Fr  : 32-byte big-endian, auto-reduced mod r by Bn254Fr::from_bytes
//
// snarkjs JSON gives coordinates as decimal strings, with G2 components in
// [c0, c1] order — so we swap to [c1, c0] here.

import { createHash } from "node:crypto";
import { Address, xdr } from "@stellar/stellar-sdk";

// BN254 scalar field modulus (Fr)
export const FR =
  21888242871839275222246405745257275088548364400416034343698204186575808495617n;

function be32(x) {
  // x: bigint or decimal string -> 32-byte big-endian Buffer
  let v = typeof x === "bigint" ? x : BigInt(x);
  v = ((v % FR) + FR) % FR; // keep in range for Fr; for Fp values are already < p < 2^256
  const hex = v.toString(16).padStart(64, "0");
  return Buffer.from(hex, "hex");
}

// For Fp coordinates (curve base field, < p) we must NOT reduce mod r.
function fpBe32(decStr) {
  const v = BigInt(decStr);
  const hex = v.toString(16).padStart(64, "0");
  return Buffer.from(hex, "hex");
}

export function g1ToHex(p) {
  // p = [x, y, z] decimal strings (affine, z == "1")
  return Buffer.concat([fpBe32(p[0]), fpBe32(p[1])]).toString("hex");
}

export function g2ToHex(p) {
  // p = [[x_c0, x_c1], [y_c0, y_c1], [z...]] decimal strings
  const xc0 = p[0][0], xc1 = p[0][1];
  const yc0 = p[1][0], yc1 = p[1][1];
  return Buffer.concat([
    fpBe32(xc1), fpBe32(xc0), // X: c1 || c0
    fpBe32(yc1), fpBe32(yc0), // Y: c1 || c0
  ]).toString("hex");
}

export function frToHex(decStr) {
  return be32(BigInt(decStr)).toString("hex");
}

// Recipient binding: must match the Soroban contract, which computes
//   Fr::from_bytes( sha256( recipient.to_xdr(env) ) )
// soroban_sdk's Address::to_xdr serializes the address as an ScVal
// (ScVal::Address(ScAddress)), not a bare ScAddress — so we serialize the
// matching ScVal here.
export function addressToXdr(strkey) {
  const scVal = xdr.ScVal.scvAddress(Address.fromString(strkey).toScAddress());
  return scVal.toXDR("raw"); // Buffer
}

export function addressToFrDecimal(strkey) {
  const bytes = addressToXdr(strkey);
  const h = createHash("sha256").update(bytes).digest(); // 32 bytes
  const v = BigInt("0x" + h.toString("hex")) % FR;
  return v.toString(10);
}

// Build the full fixtures object (hex strings) for the Soroban contract test.
export function encodeForSoroban(vk, proof, publicSignals) {
  return {
    vk: {
      alpha: g1ToHex(vk.vk_alpha_1),
      beta: g2ToHex(vk.vk_beta_2),
      gamma: g2ToHex(vk.vk_gamma_2),
      delta: g2ToHex(vk.vk_delta_2),
      ic: vk.IC.map(g1ToHex),
    },
    proof: {
      a: g1ToHex(proof.pi_a),
      b: g2ToHex(proof.pi_b),
      c: g1ToHex(proof.pi_c),
    },
    publicSignals: publicSignals.map(frToHex),
  };
}
