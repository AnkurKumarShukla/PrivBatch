"""Batch submission via web3 transactions."""

import json
from pathlib import Path
from eth_abi import encode
from web3 import Web3

from .types import LPIntent
from .merkle import MerkleTree, compute_leaf


# Load ABI from forge artifacts
def _load_abi(contract_name: str) -> list:
    """Load ABI from forge output."""
    out_dir = Path(__file__).parent.parent.parent / "out"
    artifact_path = out_dir / f"{contract_name}.sol" / f"{contract_name}.json"
    if artifact_path.exists():
        with open(artifact_path) as f:
            return json.load(f)["abi"]
    return []


class BatchSubmitter:
    """Submits batched intents to the BatchExecutor contract."""

    def __init__(self, w3: Web3, executor_address: str, private_key: str):
        self.w3 = w3
        self.private_key = private_key
        self.account = w3.eth.account.from_key(private_key)

        abi = _load_abi("BatchExecutor")
        self.executor = w3.eth.contract(address=executor_address, abi=abi)

    def build_batch_tx(
        self,
        intents: list[LPIntent],
        signatures: list[bytes],
    ) -> dict:
        """Build the executeBatch transaction."""
        # Compute Merkle tree
        leaves = [compute_leaf(intent) for intent in intents]
        tree = MerkleTree(leaves)
        proofs = [tree.get_proof(i) for i in range(len(intents))]

        # Convert intents to the tuple format expected by the contract
        intent_tuples = []
        for intent in intents:
            pool_tuple = (
                Web3.to_checksum_address(intent.pool.currency0),
                Web3.to_checksum_address(intent.pool.currency1),
                intent.pool.fee,
                intent.pool.tick_spacing,
                Web3.to_checksum_address(intent.pool.hooks),
            )
            intent_tuples.append((
                Web3.to_checksum_address(intent.user),
                pool_tuple,
                intent.tick_lower,
                intent.tick_upper,
                intent.amount,
                intent.nonce,
                intent.deadline,
            ))

        # Build transaction
        tx = self.executor.functions.executeBatch(
            intent_tuples,
            signatures,
            proofs,
        ).build_transaction({
            "from": self.account.address,
            "nonce": self.w3.eth.get_transaction_count(self.account.address),
            "gas": 3_000_000,
            "gasPrice": self.w3.eth.gas_price,
        })

        return tx

    def submit_batch(
        self,
        intents: list[LPIntent],
        signatures: list[bytes],
    ) -> str:
        """Build, sign, and submit a batch transaction. Returns tx hash."""
        tx = self.build_batch_tx(intents, signatures)
        signed_tx = self.w3.eth.account.sign_transaction(tx, self.private_key)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)

        if receipt["status"] != 1:
            raise RuntimeError(f"Batch transaction failed: {tx_hash.hex()}")

        return tx_hash.hex()

    def get_batch_root(self, intents: list[LPIntent]) -> str:
        """Compute the batch Merkle root."""
        leaves = [compute_leaf(intent) for intent in intents]
        tree = MerkleTree(leaves)
        return "0x" + tree.root.hex()
