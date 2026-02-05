"""Tests for Merkle tree builder and proof generation."""

from web3 import Web3

from src.types import LPIntent, PoolKey
from src.merkle import MerkleTree, compute_leaf, _hash_pair


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


def test_compute_leaf_deterministic():
    """Same intent produces same leaf hash."""
    intent = _make_intent(1, 100 * 10**18)
    leaf1 = compute_leaf(intent)
    leaf2 = compute_leaf(intent)
    assert leaf1 == leaf2


def test_different_intents_different_leaves():
    """Different intents produce different leaves."""
    intent1 = _make_intent(1, 100 * 10**18)
    intent2 = _make_intent(2, 200 * 10**18)
    assert compute_leaf(intent1) != compute_leaf(intent2)


def test_single_element_tree():
    """Single element tree: root == leaf."""
    intent = _make_intent(1, 100 * 10**18)
    leaf = compute_leaf(intent)

    tree = MerkleTree([leaf])
    assert tree.root == leaf

    proof = tree.get_proof(0)
    assert proof == []
    assert tree.verify(leaf, proof, tree.root)


def test_two_element_tree():
    """Two element tree with proofs."""
    i1 = _make_intent(1, 100 * 10**18)
    i2 = _make_intent(2, 200 * 10**18)

    leaf1 = compute_leaf(i1)
    leaf2 = compute_leaf(i2)

    tree = MerkleTree([leaf1, leaf2])
    expected_root = _hash_pair(leaf1, leaf2)
    assert tree.root == expected_root

    # Verify leaf1
    proof1 = tree.get_proof(0)
    assert len(proof1) == 1
    assert proof1[0] == leaf2
    assert tree.verify(leaf1, proof1, tree.root)

    # Verify leaf2
    proof2 = tree.get_proof(1)
    assert len(proof2) == 1
    assert proof2[0] == leaf1
    assert tree.verify(leaf2, proof2, tree.root)


def test_three_element_tree():
    """Three element tree: verify all proofs."""
    intents = [_make_intent(i, (i + 1) * 100 * 10**18) for i in range(1, 4)]
    leaves = [compute_leaf(intent) for intent in intents]

    tree = MerkleTree(leaves)

    for i in range(3):
        proof = tree.get_proof(i)
        assert tree.verify(leaves[i], proof, tree.root), f"Proof failed for leaf {i}"


def test_four_element_tree():
    """Four element tree: verify all proofs."""
    intents = [_make_intent(i, (i + 1) * 100 * 10**18) for i in range(1, 5)]
    leaves = [compute_leaf(intent) for intent in intents]

    tree = MerkleTree(leaves)

    # Manually compute expected root
    pair01 = _hash_pair(leaves[0], leaves[1])
    pair23 = _hash_pair(leaves[2], leaves[3])
    expected_root = _hash_pair(pair01, pair23)
    assert tree.root == expected_root

    for i in range(4):
        proof = tree.get_proof(i)
        assert tree.verify(leaves[i], proof, tree.root), f"Proof failed for leaf {i}"


def test_invalid_proof_fails():
    """Invalid proof doesn't verify."""
    intents = [_make_intent(i, (i + 1) * 100 * 10**18) for i in range(1, 3)]
    leaves = [compute_leaf(intent) for intent in intents]

    tree = MerkleTree(leaves)

    fake_sibling = Web3.keccak(b"garbage")
    assert not tree.verify(leaves[0], [fake_sibling], tree.root)


def test_leaf_not_in_tree():
    """Leaf not in tree fails verification."""
    intents = [_make_intent(i, (i + 1) * 100 * 10**18) for i in range(1, 3)]
    leaves = [compute_leaf(intent) for intent in intents]

    tree = MerkleTree(leaves)

    fake_intent = _make_intent(99, 999 * 10**18)
    fake_leaf = compute_leaf(fake_intent)

    proof = tree.get_proof(0)  # proof for leaf[0]
    assert not tree.verify(fake_leaf, proof, tree.root)
