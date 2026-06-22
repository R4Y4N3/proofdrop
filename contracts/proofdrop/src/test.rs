#![cfg(test)]
extern crate std;

use soroban_sdk::{testutils::Address as _, token, Address, BytesN, Env, Vec};

use crate::fixtures;
use crate::{ProofBytes, ProofDrop, ProofDropClient, VkBytes};

fn decode_hex(s: &str) -> std::vec::Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

fn hexn<const N: usize>(env: &Env, s: &str) -> BytesN<N> {
    let v = decode_hex(s);
    assert_eq!(v.len(), N, "hex length mismatch for BytesN<{}>", N);
    let mut a = [0u8; N];
    a.copy_from_slice(&v);
    BytesN::from_array(env, &a)
}

fn load_vk(env: &Env) -> VkBytes {
    let mut ic = Vec::new(env);
    for h in fixtures::VK_IC {
        ic.push_back(hexn::<64>(env, h));
    }
    VkBytes {
        alpha: hexn::<64>(env, fixtures::VK_ALPHA),
        beta: hexn::<128>(env, fixtures::VK_BETA),
        gamma: hexn::<128>(env, fixtures::VK_GAMMA),
        delta: hexn::<128>(env, fixtures::VK_DELTA),
        ic,
    }
}

fn load_proof(env: &Env) -> ProofBytes {
    ProofBytes {
        a: hexn::<64>(env, fixtures::PROOF_A),
        b: hexn::<128>(env, fixtures::PROOF_B),
        c: hexn::<64>(env, fixtures::PROOF_C),
    }
}

fn load_signals(env: &Env) -> Vec<BytesN<32>> {
    let mut s = Vec::new(env);
    for h in fixtures::PUB_SIGNALS {
        s.push_back(hexn::<32>(env, h));
    }
    s
}

struct Fixture {
    env: Env,
    client_id: Address,
    token: Address,
    recipient: Address,
}

fn setup() -> Fixture {
    let env = Env::default();
    env.mock_all_auths();

    let sac_admin = Address::generate(&env);
    let funder = Address::generate(&env);
    let admin = Address::generate(&env);

    let sac = env.register_stellar_asset_contract_v2(sac_admin);
    let token_addr = sac.address();
    token::StellarAssetClient::new(&env, &token_addr).mint(&funder, &1_000_000_000i128);

    let client_id = env.register(ProofDrop, ());
    let client = ProofDropClient::new(&env, &client_id);

    let allow_root = hexn::<32>(&env, fixtures::PUB_SIGNALS[fixtures::IDX_ALLOW_ROOT]);
    let deny_root = hexn::<32>(&env, fixtures::PUB_SIGNALS[fixtures::IDX_DENY_ROOT]);
    client.create_campaign(
        &funder,
        &admin,
        &fixtures::CAMPAIGN_ID,
        &allow_root,
        &deny_root,
        &token_addr,
        &fixtures::AMOUNT,
        &(fixtures::AMOUNT * 10),
        &load_vk(&env),
    );

    let recipient = Address::from_str(&env, fixtures::RECIPIENT_STRKEY);
    Fixture { env, client_id, token: token_addr, recipient }
}

#[test]
fn valid_claim_pays_out() {
    let f = setup();
    let client = ProofDropClient::new(&f.env, &f.client_id);
    let token_client = token::TokenClient::new(&f.env, &f.token);

    assert_eq!(token_client.balance(&f.recipient), 0);
    client.claim(&fixtures::CAMPAIGN_ID, &load_proof(&f.env), &load_signals(&f.env), &f.recipient);
    assert_eq!(token_client.balance(&f.recipient), fixtures::AMOUNT);
    f.env.cost_estimate().budget().print();
}

#[test]
fn double_claim_is_rejected() {
    let f = setup();
    let client = ProofDropClient::new(&f.env, &f.client_id);
    client.claim(&fixtures::CAMPAIGN_ID, &load_proof(&f.env), &load_signals(&f.env), &f.recipient);
    let res = client.try_claim(&fixtures::CAMPAIGN_ID, &load_proof(&f.env), &load_signals(&f.env), &f.recipient);
    assert!(res.is_err(), "second claim with same nullifier must fail");
}

#[test]
fn tampered_signal_is_rejected() {
    let f = setup();
    let client = ProofDropClient::new(&f.env, &f.client_id);
    let mut signals = load_signals(&f.env);
    let bad = hexn::<32>(&f.env, fixtures::PUB_SIGNALS[fixtures::IDX_NULLIFIER]);
    signals.set(fixtures::IDX_RECIPIENT as u32, bad);
    let res = client.try_claim(&fixtures::CAMPAIGN_ID, &load_proof(&f.env), &signals, &f.recipient);
    assert!(res.is_err(), "tampered public signals must fail verification");
}

#[test]
fn wrong_recipient_is_rejected() {
    let f = setup();
    let client = ProofDropClient::new(&f.env, &f.client_id);
    let attacker = Address::generate(&f.env);
    let res = client.try_claim(&fixtures::CAMPAIGN_ID, &load_proof(&f.env), &load_signals(&f.env), &attacker);
    assert!(res.is_err(), "claim redirected to a different recipient must fail");
}

#[test]
fn malleated_nullifier_replay_is_rejected() {
    let f = setup();
    let client = ProofDropClient::new(&f.env, &f.client_id);

    // Legit claim succeeds and spends the canonical nullifier.
    client.claim(&fixtures::CAMPAIGN_ID, &load_proof(&f.env), &load_signals(&f.env), &f.recipient);

    // Replay with nullifier + r: same field element (proof still verifies), but
    // different raw bytes. Must be rejected as non-canonical — no double payout.
    let mut signals = load_signals(&f.env);
    signals.set(
        fixtures::IDX_NULLIFIER as u32,
        hexn::<32>(&f.env, fixtures::MALLEATED_NULLIFIER),
    );
    let res = client.try_claim(&fixtures::CAMPAIGN_ID, &load_proof(&f.env), &signals, &f.recipient);
    assert!(res.is_err(), "malleated non-canonical nullifier must be rejected");
}

#[test]
fn audit_summary_reconciles() {
    let f = setup();
    let client = ProofDropClient::new(&f.env, &f.client_id);
    client.claim(&fixtures::CAMPAIGN_ID, &load_proof(&f.env), &load_signals(&f.env), &f.recipient);

    let s = client.campaign_audit_summary(&fixtures::CAMPAIGN_ID).unwrap();
    assert_eq!(s.claim_count, 1, "auditor should see exactly one claim");
    assert_eq!(s.total_disbursed, fixtures::AMOUNT, "totals must reconcile");
}

#[test]
fn revocation_blocks_claim() {
    let f = setup();
    let client = ProofDropClient::new(&f.env, &f.client_id);

    // Admin updates the deny root (e.g. revokes / refreshes the sanction list).
    let new_deny = hexn::<32>(&f.env, fixtures::PUB_SIGNALS[fixtures::IDX_NULLIFIER]); // any different value
    client.set_deny_root(&fixtures::CAMPAIGN_ID, &new_deny);

    // The existing proof was built against the OLD deny root -> rejected.
    let res = client.try_claim(&fixtures::CAMPAIGN_ID, &load_proof(&f.env), &load_signals(&f.env), &f.recipient);
    assert!(res.is_err(), "claim must fail after deny root changes (revocation)");
}
