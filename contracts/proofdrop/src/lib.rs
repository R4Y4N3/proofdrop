#![no_std]
//! ProofDrop — private, Sybil-resistant, compliance-aware disbursements on Stellar.
//!
//! A campaign issuer publishes:
//!   - an **allow root** (Merkle root of the eligibility set), and
//!   - a **deny root** (Sparse-Merkle root of a revocation / sanction list,
//!     an Association-Set-Provider–style control the issuer can update).
//!
//! Each eligible identity claims its fixed disbursement exactly once, to any
//! Stellar address, by submitting a Groth16 proof that it is in the allow set,
//! NOT in the deny set, and bound to a recipient/amount — without revealing
//! which member of the set it is. Proofs are generated off-chain (Circom, BN254)
//! and verified on-chain here via Soroban's BN254 host functions.
//!
//! This is the "compliant privacy" pattern: private recipients, public policy
//! controls. The admin can revoke an identity by updating the deny root; that
//! identity can no longer produce a valid claim.

use soroban_sdk::{
    contract, contracterror, contractevent, contractimpl, contracttype,
    crypto::bn254::{Bn254Fr, Bn254G1Affine, Bn254G2Affine},
    token, vec, xdr::ToXdr, Address, BytesN, Env, Vec,
};

/// Frozen public-signal layout (must match circuits/proofdrop.circom):
/// [ nullifierHash, allowRoot, denyRoot, campaignId, recipientHash, amount ]
const IDX_NULLIFIER: u32 = 0;
const IDX_ALLOW_ROOT: u32 = 1;
const IDX_DENY_ROOT: u32 = 2;
const IDX_CAMPAIGN: u32 = 3;
const IDX_RECIPIENT: u32 = 4;
const IDX_AMOUNT: u32 = 5;
const NUM_SIGNALS: u32 = 6;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum Error {
    CampaignExists = 1,
    CampaignNotFound = 2,
    InvalidProof = 3,
    BadPublicSignals = 4,
    AllowRootMismatch = 5,
    CampaignMismatch = 6,
    RecipientMismatch = 7,
    AmountMismatch = 8,
    AlreadyClaimed = 9,
    DenyRootMismatch = 10,
    InvalidCampaign = 11,
    NonCanonicalSignal = 12,
}

/// Verification key as raw BN254 byte points (Ethereum encoding).
#[derive(Clone)]
#[contracttype]
pub struct VkBytes {
    pub alpha: BytesN<64>,
    pub beta: BytesN<128>,
    pub gamma: BytesN<128>,
    pub delta: BytesN<128>,
    pub ic: Vec<BytesN<64>>,
}

/// Groth16 proof as raw BN254 byte points.
#[derive(Clone)]
#[contracttype]
pub struct ProofBytes {
    pub a: BytesN<64>,
    pub b: BytesN<128>,
    pub c: BytesN<64>,
}

#[derive(Clone)]
#[contracttype]
pub struct Campaign {
    pub admin: Address,
    pub allow_root: BytesN<32>,
    pub deny_root: BytesN<32>,
    pub token: Address,
    pub amount: i128,
    pub vk: VkBytes,
    // Auditor-readable running totals (maintained on every claim).
    pub claim_count: u32,
    pub total_disbursed: i128,
}

/// Compliance / auditor view of a campaign — everything an auditor needs to
/// reconcile a campaign from on-chain state, without de-anonymizing recipients.
#[derive(Clone)]
#[contracttype]
pub struct CampaignAuditSummary {
    pub campaign_id: u64,
    pub admin: Address,
    pub token: Address,
    pub amount: i128,
    pub allow_root: BytesN<32>,
    pub deny_root: BytesN<32>,
    pub claim_count: u32,
    pub total_disbursed: i128,
}

#[contracttype]
pub enum DataKey {
    Campaign(u64),
    Nullifier(u64, BytesN<32>),
}

// ---- Events (auditor / indexer friendly) ----

#[contractevent(topics = ["created"])]
#[derive(Clone)]
pub struct CampaignCreated {
    #[topic]
    pub campaign_id: u64,
    pub admin: Address,
    pub token: Address,
    pub allow_root: BytesN<32>,
}

#[contractevent(topics = ["claim"])]
#[derive(Clone)]
pub struct ClaimPaid {
    #[topic]
    pub campaign_id: u64,
    pub nullifier: BytesN<32>,
    pub recipient: Address,
    pub amount: i128,
}

#[contractevent(topics = ["deny_set"])]
#[derive(Clone)]
pub struct DenyRootSet {
    #[topic]
    pub campaign_id: u64,
    pub deny_root: BytesN<32>,
}

#[contract]
pub struct ProofDrop;

#[contractimpl]
impl ProofDrop {
    /// Create and fund a campaign. `funder` deposits `budget` of `token`;
    /// `admin` controls the deny/revocation root.
    pub fn create_campaign(
        env: Env,
        funder: Address,
        admin: Address,
        campaign_id: u64,
        allow_root: BytesN<32>,
        deny_root: BytesN<32>,
        token: Address,
        amount: i128,
        budget: i128,
        vk: VkBytes,
    ) -> Result<(), Error> {
        funder.require_auth();
        if amount <= 0 || budget < amount {
            return Err(Error::InvalidCampaign);
        }
        let key = DataKey::Campaign(campaign_id);
        if env.storage().persistent().has(&key) {
            return Err(Error::CampaignExists);
        }
        token::TokenClient::new(&env, &token).transfer(
            &funder,
            &env.current_contract_address(),
            &budget,
        );
        env.storage().persistent().set(
            &key,
            &Campaign {
                admin: admin.clone(),
                allow_root: allow_root.clone(),
                deny_root,
                token: token.clone(),
                amount,
                vk,
                claim_count: 0,
                total_disbursed: 0,
            },
        );
        CampaignCreated { campaign_id, admin, token, allow_root }.publish(&env);
        Ok(())
    }

    /// Admin-only: update the deny/revocation root (e.g. to revoke an identity
    /// or refresh the Association-Set-Provider sanction list).
    pub fn set_deny_root(env: Env, campaign_id: u64, new_deny_root: BytesN<32>) -> Result<(), Error> {
        let mut campaign: Campaign = env
            .storage()
            .persistent()
            .get(&DataKey::Campaign(campaign_id))
            .ok_or(Error::CampaignNotFound)?;
        campaign.admin.require_auth();
        campaign.deny_root = new_deny_root.clone();
        env.storage().persistent().set(&DataKey::Campaign(campaign_id), &campaign);
        DenyRootSet { campaign_id, deny_root: new_deny_root }.publish(&env);
        Ok(())
    }

    /// Claim a disbursement for `recipient` using a ZK proof of eligibility.
    /// Anyone may submit; funds always go to the recipient bound in the proof.
    pub fn claim(
        env: Env,
        campaign_id: u64,
        proof: ProofBytes,
        signals: Vec<BytesN<32>>,
        recipient: Address,
    ) -> Result<(), Error> {
        let mut campaign: Campaign = env
            .storage()
            .persistent()
            .get(&DataKey::Campaign(campaign_id))
            .ok_or(Error::CampaignNotFound)?;

        if signals.len() != NUM_SIGNALS {
            return Err(Error::BadPublicSignals);
        }

        // 0. Reject non-canonical field encodings. The verifier reduces signals
        //    mod r, but the nullifier is keyed by raw bytes — without this a
        //    claimant could resubmit a valid proof with nullifierHash + k*r
        //    (same field element, different bytes) to mint duplicate nullifier
        //    keys and claim multiple times.
        let mut i = 0;
        while i < signals.len() {
            let s = signals.get(i).unwrap();
            if Bn254Fr::from_bytes(s.clone()).to_bytes() != s {
                return Err(Error::NonCanonicalSignal);
            }
            i += 1;
        }

        // 1. Verify the Groth16 proof.
        if !verify_groth16(&env, &campaign.vk, &proof, &signals) {
            return Err(Error::InvalidProof);
        }

        // 2. Bind public signals to this campaign's policy.
        if !fr_eq(&signals.get(IDX_ALLOW_ROOT).unwrap(), &campaign.allow_root) {
            return Err(Error::AllowRootMismatch);
        }
        if !fr_eq(&signals.get(IDX_DENY_ROOT).unwrap(), &campaign.deny_root) {
            return Err(Error::DenyRootMismatch);
        }
        if !fr_eq(&signals.get(IDX_CAMPAIGN).unwrap(), &u64_to_be32(&env, campaign_id)) {
            return Err(Error::CampaignMismatch);
        }
        if !fr_eq(&signals.get(IDX_AMOUNT).unwrap(), &i128_to_be32(&env, campaign.amount)) {
            return Err(Error::AmountMismatch);
        }
        if !fr_eq(&signals.get(IDX_RECIPIENT).unwrap(), &address_to_be32(&env, &recipient)) {
            return Err(Error::RecipientMismatch);
        }

        // 3. One claim per identity per campaign.
        let nullifier = signals.get(IDX_NULLIFIER).unwrap();
        let nkey = DataKey::Nullifier(campaign_id, nullifier.clone());
        if env.storage().persistent().has(&nkey) {
            return Err(Error::AlreadyClaimed);
        }
        env.storage().persistent().set(&nkey, &true);

        // 4. Pay out.
        let amount = campaign.amount;
        token::TokenClient::new(&env, &campaign.token).transfer(
            &env.current_contract_address(),
            &recipient,
            &amount,
        );

        // 5. Maintain auditor-readable totals + emit a claim event.
        campaign.claim_count += 1;
        campaign.total_disbursed += amount;
        env.storage().persistent().set(&DataKey::Campaign(campaign_id), &campaign);
        ClaimPaid { campaign_id, nullifier, recipient, amount }.publish(&env);
        Ok(())
    }

    pub fn is_claimed(env: Env, campaign_id: u64, nullifier: BytesN<32>) -> bool {
        env.storage()
            .persistent()
            .has(&DataKey::Nullifier(campaign_id, nullifier))
    }

    pub fn get_campaign(env: Env, campaign_id: u64) -> Option<Campaign> {
        env.storage().persistent().get(&DataKey::Campaign(campaign_id))
    }

    /// Auditor view: reconcile a campaign from on-chain state (totals, claim
    /// count, policy roots) without revealing any recipient identity.
    pub fn campaign_audit_summary(env: Env, campaign_id: u64) -> Option<CampaignAuditSummary> {
        let c: Campaign = env.storage().persistent().get(&DataKey::Campaign(campaign_id))?;
        Some(CampaignAuditSummary {
            campaign_id,
            admin: c.admin,
            token: c.token,
            amount: c.amount,
            allow_root: c.allow_root,
            deny_root: c.deny_root,
            claim_count: c.claim_count,
            total_disbursed: c.total_disbursed,
        })
    }
}

/// BN254 Groth16 verification:
///   e(-A, B) * e(alpha, beta) * e(vk_x, gamma) * e(C, delta) == 1
fn verify_groth16(
    env: &Env,
    vk: &VkBytes,
    proof: &ProofBytes,
    signals: &Vec<BytesN<32>>,
) -> bool {
    if signals.len() + 1 != vk.ic.len() {
        return false;
    }
    let bn = env.crypto().bn254();

    let mut vk_x = Bn254G1Affine::from_bytes(vk.ic.get(0).unwrap());
    for i in 0..signals.len() {
        let ic = Bn254G1Affine::from_bytes(vk.ic.get(i + 1).unwrap());
        let s = Bn254Fr::from_bytes(signals.get(i).unwrap());
        let prod = bn.g1_mul(&ic, &s);
        vk_x = bn.g1_add(&vk_x, &prod);
    }

    let neg_a = -Bn254G1Affine::from_bytes(proof.a.clone());
    let alpha = Bn254G1Affine::from_bytes(vk.alpha.clone());
    let c = Bn254G1Affine::from_bytes(proof.c.clone());

    let b = Bn254G2Affine::from_bytes(proof.b.clone());
    let beta = Bn254G2Affine::from_bytes(vk.beta.clone());
    let gamma = Bn254G2Affine::from_bytes(vk.gamma.clone());
    let delta = Bn254G2Affine::from_bytes(vk.delta.clone());

    let vp1 = vec![env, neg_a, alpha, vk_x, c];
    let vp2 = vec![env, b, beta, gamma, delta];
    bn.pairing_check(vp1, vp2)
}

fn fr_eq(sig: &BytesN<32>, expected: &BytesN<32>) -> bool {
    Bn254Fr::from_bytes(sig.clone()).to_u256() == Bn254Fr::from_bytes(expected.clone()).to_u256()
}

fn u64_to_be32(env: &Env, x: u64) -> BytesN<32> {
    let mut b = [0u8; 32];
    b[24..32].copy_from_slice(&x.to_be_bytes());
    BytesN::from_array(env, &b)
}

fn i128_to_be32(env: &Env, x: i128) -> BytesN<32> {
    let mut b = [0u8; 32];
    b[16..32].copy_from_slice(&x.to_be_bytes());
    BytesN::from_array(env, &b)
}

/// Fr( sha256( recipient ScVal-XDR ) ), reproduced off-chain in soroban_encode.js.
fn address_to_be32(env: &Env, addr: &Address) -> BytesN<32> {
    env.crypto().sha256(&addr.clone().to_xdr(env)).to_bytes()
}

#[cfg(test)]
mod fixtures;
#[cfg(test)]
mod test;
