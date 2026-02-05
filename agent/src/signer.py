"""EIP-712 signing utilities for LP intents."""

from eth_account import Account
from eth_account.messages import encode_typed_data

from .types import LPIntent, EIP712_DOMAIN


def build_eip712_message(intent: LPIntent, chain_id: int, verifying_contract: str) -> dict:
    """Build the full EIP-712 typed data message for signing."""
    domain = {
        **EIP712_DOMAIN,
        "chainId": chain_id,
        "verifyingContract": verifying_contract,
    }

    message = {
        "user": intent.user,
        "pool": {
            "currency0": intent.pool.currency0,
            "currency1": intent.pool.currency1,
            "fee": intent.pool.fee,
            "tickSpacing": intent.pool.tick_spacing,
            "hooks": intent.pool.hooks,
        },
        "tickLower": intent.tick_lower,
        "tickUpper": intent.tick_upper,
        "amount": intent.amount,
        "nonce": intent.nonce,
        "deadline": intent.deadline,
    }

    types = {
        "PoolKey": [
            {"name": "currency0", "type": "address"},
            {"name": "currency1", "type": "address"},
            {"name": "fee", "type": "uint24"},
            {"name": "tickSpacing", "type": "int24"},
            {"name": "hooks", "type": "address"},
        ],
        "LPIntent": [
            {"name": "user", "type": "address"},
            {"name": "pool", "type": "PoolKey"},
            {"name": "tickLower", "type": "int24"},
            {"name": "tickUpper", "type": "int24"},
            {"name": "amount", "type": "uint256"},
            {"name": "nonce", "type": "uint256"},
            {"name": "deadline", "type": "uint256"},
        ],
    }

    return {
        "domain": domain,
        "types": types,
        "primaryType": "LPIntent",
        "message": message,
    }


def sign_intent(
    intent: LPIntent,
    private_key: str,
    chain_id: int,
    verifying_contract: str,
) -> bytes:
    """Sign an LP intent with EIP-712."""
    full_message = build_eip712_message(intent, chain_id, verifying_contract)

    signable = encode_typed_data(
        full_message=full_message,
    )

    signed = Account.sign_message(signable, private_key=private_key)
    # Return r + s + v packed (65 bytes, matching Solidity's abi.encodePacked(r, s, v))
    return (
        signed.r.to_bytes(32, "big")
        + signed.s.to_bytes(32, "big")
        + signed.v.to_bytes(1, "big")
    )


def verify_intent_signature(
    intent: LPIntent,
    signature: bytes,
    chain_id: int,
    verifying_contract: str,
) -> str:
    """Verify an EIP-712 signature and return the recovered address."""
    full_message = build_eip712_message(intent, chain_id, verifying_contract)

    signable = encode_typed_data(
        full_message=full_message,
    )

    recovered = Account.recover_message(signable, signature=signature)
    return recovered
