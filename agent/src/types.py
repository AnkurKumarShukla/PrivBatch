"""EIP-712 typed data structures for LP intents."""

from dataclasses import dataclass
from pydantic import BaseModel


@dataclass
class PoolKey:
    """Uniswap v4 pool key."""

    currency0: str  # address
    currency1: str  # address
    fee: int
    tick_spacing: int
    hooks: str  # address


@dataclass
class LPIntent:
    """LP intent matching the Solidity struct."""

    user: str  # address
    pool: PoolKey
    tick_lower: int
    tick_upper: int
    amount: int
    nonce: int
    deadline: int


class LPIntentRequest(BaseModel):
    """API request model for submitting an intent."""

    user: str
    pool_currency0: str
    pool_currency1: str
    pool_fee: int
    pool_tick_spacing: int
    pool_hooks: str
    tick_lower: int
    tick_upper: int
    amount: int
    nonce: int
    deadline: int
    signature: str  # hex-encoded

    def to_lp_intent(self) -> LPIntent:
        return LPIntent(
            user=self.user,
            pool=PoolKey(
                currency0=self.pool_currency0,
                currency1=self.pool_currency1,
                fee=self.pool_fee,
                tick_spacing=self.pool_tick_spacing,
                hooks=self.pool_hooks,
            ),
            tick_lower=self.tick_lower,
            tick_upper=self.tick_upper,
            amount=self.amount,
            nonce=self.nonce,
            deadline=self.deadline,
        )


class BatchStatus(BaseModel):
    """Current batch status."""

    pending_intents: int
    last_batch_root: str | None = None
    last_batch_tx: str | None = None
    batches_executed: int = 0


# EIP-712 type definitions
EIP712_DOMAIN = {
    "name": "PrivBatch",
    "version": "1",
}

POOL_KEY_TYPE = [
    {"name": "currency0", "type": "address"},
    {"name": "currency1", "type": "address"},
    {"name": "fee", "type": "uint24"},
    {"name": "tickSpacing", "type": "int24"},
    {"name": "hooks", "type": "address"},
]

LP_INTENT_TYPE = [
    {"name": "user", "type": "address"},
    {"name": "pool", "type": "PoolKey"},
    {"name": "tickLower", "type": "int24"},
    {"name": "tickUpper", "type": "int24"},
    {"name": "amount", "type": "uint256"},
    {"name": "nonce", "type": "uint256"},
    {"name": "deadline", "type": "uint256"},
]

EIP712_TYPES = {
    "EIP712Domain": [
        {"name": "name", "type": "string"},
        {"name": "version", "type": "string"},
        {"name": "chainId", "type": "uint256"},
        {"name": "verifyingContract", "type": "address"},
    ],
    "PoolKey": POOL_KEY_TYPE,
    "LPIntent": LP_INTENT_TYPE,
}
