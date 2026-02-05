"""Merkle tree builder and proof generation for intent batches."""

from eth_abi import encode
from web3 import Web3


def _hash_pair(a: bytes, b: bytes) -> bytes:
    """Hash two nodes, sorting them first (OpenZeppelin standard)."""
    if a <= b:
        return Web3.keccak(a + b)
    else:
        return Web3.keccak(b + a)


def _hash_pool_key(pool) -> bytes:
    """Hash a PoolKey struct matching Solidity's IntentVerifier.hashPoolKey."""
    pool_key_typehash = Web3.keccak(
        text="PoolKey(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)"
    )
    encoded = encode(
        ["bytes32", "address", "address", "uint24", "int24", "address"],
        [pool_key_typehash, pool.currency0, pool.currency1, pool.fee, pool.tick_spacing, pool.hooks],
    )
    return Web3.keccak(encoded)


def compute_leaf(intent) -> bytes:
    """Compute a Merkle leaf from an LPIntent, matching Solidity's IntentVerifier.hashIntent."""
    lp_intent_typehash = Web3.keccak(
        text="LPIntent(address user,PoolKey pool,int24 tickLower,int24 tickUpper,uint256 amount,uint256 nonce,uint256 deadline)PoolKey(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)"
    )

    pool_hash = _hash_pool_key(intent.pool)

    encoded = encode(
        ["bytes32", "address", "bytes32", "int24", "int24", "uint256", "uint256", "uint256"],
        [
            lp_intent_typehash,
            intent.user,
            pool_hash,
            intent.tick_lower,
            intent.tick_upper,
            intent.amount,
            intent.nonce,
            intent.deadline,
        ],
    )
    return Web3.keccak(encoded)


class MerkleTree:
    """Simple Merkle tree matching the Solidity BatchMerkle.computeRoot implementation."""

    def __init__(self, leaves: list[bytes]):
        if not leaves:
            raise ValueError("Cannot build tree with no leaves")
        self.leaves = list(leaves)
        self.layers: list[list[bytes]] = []
        self._build()

    def _build(self):
        """Build the tree bottom-up."""
        layer = list(self.leaves)
        self.layers.append(list(layer))

        while len(layer) > 1:
            next_layer = []
            n = len(layer)
            for i in range(0, n, 2):
                if i + 1 < n:
                    next_layer.append(_hash_pair(layer[i], layer[i + 1]))
                else:
                    next_layer.append(layer[i])
            layer = next_layer
            self.layers.append(list(layer))

    @property
    def root(self) -> bytes:
        return self.layers[-1][0]

    def get_proof(self, index: int) -> list[bytes]:
        """Get the Merkle proof for the leaf at the given index."""
        if index < 0 or index >= len(self.leaves):
            raise IndexError(f"Leaf index {index} out of range")

        proof = []
        idx = index

        for layer in self.layers[:-1]:
            n = len(layer)
            if idx % 2 == 0:
                # sibling is to the right
                if idx + 1 < n:
                    proof.append(layer[idx + 1])
            else:
                # sibling is to the left
                proof.append(layer[idx - 1])
            idx //= 2

        return proof

    def verify(self, leaf: bytes, proof: list[bytes], root: bytes) -> bool:
        """Verify a Merkle proof."""
        computed = leaf
        for sibling in proof:
            computed = _hash_pair(computed, sibling)
        return computed == root
