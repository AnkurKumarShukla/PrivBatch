"""Tests for EIP-712 signing utilities."""

from eth_account import Account

from src.types import LPIntent, PoolKey
from src.signer import sign_intent, verify_intent_signature


CHAIN_ID = 31337
VERIFYING_CONTRACT = "0x0000000000000000000000000000000000001234"


def _make_test_intent(user_address: str) -> LPIntent:
    return LPIntent(
        user=user_address,
        pool=PoolKey(
            currency0="0x0000000000000000000000000000000000001111",
            currency1="0x0000000000000000000000000000000000002222",
            fee=3000,
            tick_spacing=60,
            hooks="0x0000000000000000000000000000000000000000",
        ),
        tick_lower=-887220,
        tick_upper=887220,
        amount=100 * 10**18,
        nonce=0,
        deadline=99999999999,
    )


def test_sign_and_verify_roundtrip():
    """Sign an intent and verify the signature recovers the correct address."""
    acct = Account.create()
    intent = _make_test_intent(acct.address)

    sig = sign_intent(intent, acct.key.hex(), CHAIN_ID, VERIFYING_CONTRACT)
    assert len(sig) == 65

    recovered = verify_intent_signature(intent, sig, CHAIN_ID, VERIFYING_CONTRACT)
    assert recovered.lower() == acct.address.lower()


def test_different_keys_different_signatures():
    """Two different keys produce different signatures."""
    acct1 = Account.create()
    acct2 = Account.create()

    intent1 = _make_test_intent(acct1.address)
    intent2 = _make_test_intent(acct2.address)

    sig1 = sign_intent(intent1, acct1.key.hex(), CHAIN_ID, VERIFYING_CONTRACT)
    sig2 = sign_intent(intent2, acct2.key.hex(), CHAIN_ID, VERIFYING_CONTRACT)

    assert sig1 != sig2


def test_wrong_signer_detected():
    """Verifying with wrong expected user detects mismatch."""
    acct = Account.create()
    other = Account.create()

    intent = _make_test_intent(acct.address)
    sig = sign_intent(intent, acct.key.hex(), CHAIN_ID, VERIFYING_CONTRACT)

    recovered = verify_intent_signature(intent, sig, CHAIN_ID, VERIFYING_CONTRACT)
    assert recovered.lower() != other.address.lower()


def test_tampered_intent_fails():
    """Modifying intent after signing recovers wrong address."""
    acct = Account.create()
    intent = _make_test_intent(acct.address)

    sig = sign_intent(intent, acct.key.hex(), CHAIN_ID, VERIFYING_CONTRACT)

    # Tamper
    intent.amount = 999 * 10**18

    recovered = verify_intent_signature(intent, sig, CHAIN_ID, VERIFYING_CONTRACT)
    assert recovered.lower() != acct.address.lower()


def test_deterministic_signatures():
    """Same key + same intent = same signature."""
    key = "0x" + "ab" * 32
    acct = Account.from_key(key)
    intent = _make_test_intent(acct.address)

    sig1 = sign_intent(intent, key, CHAIN_ID, VERIFYING_CONTRACT)
    sig2 = sign_intent(intent, key, CHAIN_ID, VERIFYING_CONTRACT)

    assert sig1 == sig2
