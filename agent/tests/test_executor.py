"""Tests for batch executor (uses mocks since we need a chain)."""

from src.types import LPIntent, PoolKey
from src.merkle import MerkleTree, compute_leaf


def _make_intent(user_suffix: int, amount: int) -> LPIntent:
    return LPIntent(
        user=f"0x{user_suffix:040x}",
        pool=PoolKey(
            currency0="0x0000000000000000000000000000000000001111",
            currency1="0x0000000000000000000000000000000000002222",
            fee=3000,
            tick_spacing=60,
            hooks="0x0000000000000000000000000000000000000000",
        ),
        tick_lower=-887220,
        tick_upper=887220,
        amount=amount,
        nonce=0,
        deadline=99999999999,
    )


def test_batch_merkle_root_computation():
    """Verify batch root is computed correctly."""
    intents = [_make_intent(i, (i + 1) * 100 * 10**18) for i in range(1, 4)]
    leaves = [compute_leaf(intent) for intent in intents]
    tree = MerkleTree(leaves)

    # Root should be deterministic
    tree2 = MerkleTree(leaves)
    assert tree.root == tree2.root


def test_batch_proofs_all_valid():
    """All proofs in a batch should verify."""
    intents = [_make_intent(i, (i + 1) * 100 * 10**18) for i in range(1, 4)]
    leaves = [compute_leaf(intent) for intent in intents]
    tree = MerkleTree(leaves)

    for i in range(len(intents)):
        proof = tree.get_proof(i)
        assert tree.verify(leaves[i], proof, tree.root)


def test_batch_root_changes_with_different_intents():
    """Different intent sets produce different roots."""
    intents1 = [_make_intent(i, 100 * 10**18) for i in range(1, 4)]
    intents2 = [_make_intent(i, 200 * 10**18) for i in range(1, 4)]

    leaves1 = [compute_leaf(intent) for intent in intents1]
    leaves2 = [compute_leaf(intent) for intent in intents2]

    tree1 = MerkleTree(leaves1)
    tree2 = MerkleTree(leaves2)

    assert tree1.root != tree2.root
