"""Configuration for the PrivBatch agent."""

import os
from dataclasses import dataclass, field


@dataclass
class Config:
    """Agent configuration."""

    # RPC
    rpc_url: str = field(default_factory=lambda: os.getenv("RPC_URL", "http://127.0.0.1:8545"))

    # Contract addresses
    hook_address: str = field(default_factory=lambda: os.getenv("HOOK_ADDRESS", ""))
    executor_address: str = field(default_factory=lambda: os.getenv("EXECUTOR_ADDRESS", ""))
    commit_address: str = field(default_factory=lambda: os.getenv("COMMIT_ADDRESS", ""))
    pool_manager_address: str = field(default_factory=lambda: os.getenv("POOL_MANAGER", ""))
    position_manager_address: str = field(default_factory=lambda: os.getenv("POSITION_MANAGER", ""))
    token_a_address: str = field(default_factory=lambda: os.getenv("TOKEN_A", ""))
    token_b_address: str = field(default_factory=lambda: os.getenv("TOKEN_B", ""))

    # Agent private key (for signing transactions)
    agent_private_key: str = field(default_factory=lambda: os.getenv("PRIVATE_KEY", ""))

    # Batching parameters
    min_batch_size: int = 2
    max_batch_wait_seconds: int = 60
    batch_check_interval: int = 5

    # Optimizer parameters
    volatility_window: int = 24  # hours of price history
    k_multiplier: float = 2.0  # range width = k * volatility

    # API
    api_host: str = "0.0.0.0"
    api_port: int = 8000

    # Chain (11155111 = Sepolia, 31337 = Anvil)
    chain_id: int = field(default_factory=lambda: int(os.getenv("CHAIN_ID", "11155111")))
