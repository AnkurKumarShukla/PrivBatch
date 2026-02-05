// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BatchMerkle} from "../src/libraries/BatchMerkle.sol";
import {LPIntent} from "../src/types/LPIntent.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @notice Harness contract to test BatchMerkle library
contract BatchMerkleHarness {
    function computeLeaf(LPIntent memory intent) external pure returns (bytes32) {
        return BatchMerkle.computeLeaf(intent);
    }

    function verifyBatchInclusion(bytes32 root, bytes32 leaf, bytes32[] memory proof) external pure returns (bool) {
        return BatchMerkle.verifyBatchInclusion(root, leaf, proof);
    }

    function requireBatchInclusion(bytes32 root, bytes32 leaf, bytes32[] memory proof) external pure {
        BatchMerkle.requireBatchInclusion(root, leaf, proof);
    }

    function computeRoot(bytes32[] memory leaves) external pure returns (bytes32) {
        return BatchMerkle.computeRoot(leaves);
    }
}

contract BatchMerkleTest is Test {
    BatchMerkleHarness harness;
    PoolKey testPool;

    function setUp() public {
        harness = new BatchMerkleHarness();
        testPool = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function _makeIntent(address user, uint256 amount, uint256 nonce) internal view returns (LPIntent memory) {
        return LPIntent({
            user: user,
            pool: testPool,
            tickLower: -887220,
            tickUpper: 887220,
            amount: amount,
            nonce: nonce,
            deadline: block.timestamp + 1 hours
        });
    }

    function _sortedHash(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        if (a <= b) {
            return keccak256(abi.encodePacked(a, b));
        } else {
            return keccak256(abi.encodePacked(b, a));
        }
    }

    function testSingleElementTree() public view {
        LPIntent memory intent = _makeIntent(address(0x1), 100e18, 0);
        bytes32 leaf = harness.computeLeaf(intent);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = leaf;
        bytes32 root = harness.computeRoot(leaves);

        // Single element tree: root == leaf
        assertEq(root, leaf);

        // Verify with empty proof
        bytes32[] memory proof = new bytes32[](0);
        assertTrue(harness.verifyBatchInclusion(root, leaf, proof));
    }

    function testTwoElementTree() public view {
        LPIntent memory intent1 = _makeIntent(address(0x1), 100e18, 0);
        LPIntent memory intent2 = _makeIntent(address(0x2), 200e18, 0);

        bytes32 leaf1 = harness.computeLeaf(intent1);
        bytes32 leaf2 = harness.computeLeaf(intent2);

        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = leaf1;
        leaves[1] = leaf2;
        bytes32 root = harness.computeRoot(leaves);

        // Verify leaf1 with leaf2 as proof
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf2;
        assertTrue(harness.verifyBatchInclusion(root, leaf1, proof1));

        // Verify leaf2 with leaf1 as proof
        bytes32[] memory proof2 = new bytes32[](1);
        proof2[0] = leaf1;
        assertTrue(harness.verifyBatchInclusion(root, leaf2, proof2));
    }

    function testThreeElementTree() public {
        LPIntent memory intent1 = _makeIntent(address(0x1), 100e18, 0);
        LPIntent memory intent2 = _makeIntent(address(0x2), 200e18, 0);
        LPIntent memory intent3 = _makeIntent(address(0x3), 300e18, 0);

        bytes32 leaf1 = harness.computeLeaf(intent1);
        bytes32 leaf2 = harness.computeLeaf(intent2);
        bytes32 leaf3 = harness.computeLeaf(intent3);

        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = leaf1;
        leaves[1] = leaf2;
        leaves[2] = leaf3;
        bytes32 root = harness.computeRoot(leaves);

        // Root should be: hash(hash(leaf1, leaf2), leaf3) with sorting
        bytes32 pair12 = _sortedHash(leaf1, leaf2);
        bytes32 expectedRoot = _sortedHash(pair12, leaf3);
        assertEq(root, expectedRoot);
    }

    function testInvalidProofReverts() public {
        LPIntent memory intent1 = _makeIntent(address(0x1), 100e18, 0);
        LPIntent memory intent2 = _makeIntent(address(0x2), 200e18, 0);

        bytes32 leaf1 = harness.computeLeaf(intent1);
        bytes32 leaf2 = harness.computeLeaf(intent2);

        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = leaf1;
        leaves[1] = leaf2;
        bytes32 root = harness.computeRoot(leaves);

        // Wrong proof
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = keccak256("garbage");

        assertFalse(harness.verifyBatchInclusion(root, leaf1, badProof));

        vm.expectRevert(BatchMerkle.InvalidMerkleProof.selector);
        harness.requireBatchInclusion(root, leaf1, badProof);
    }

    function testLeafNotInTreeFails() public view {
        LPIntent memory intent1 = _makeIntent(address(0x1), 100e18, 0);
        LPIntent memory intent2 = _makeIntent(address(0x2), 200e18, 0);
        LPIntent memory intentNotInTree = _makeIntent(address(0x99), 999e18, 0);

        bytes32 leaf1 = harness.computeLeaf(intent1);
        bytes32 leaf2 = harness.computeLeaf(intent2);
        bytes32 fakeLeaf = harness.computeLeaf(intentNotInTree);

        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = leaf1;
        leaves[1] = leaf2;
        bytes32 root = harness.computeRoot(leaves);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;
        assertFalse(harness.verifyBatchInclusion(root, fakeLeaf, proof));
    }

    function testComputeLeafDeterministic() public view {
        LPIntent memory intent = _makeIntent(address(0x1), 100e18, 0);
        assertEq(harness.computeLeaf(intent), harness.computeLeaf(intent));
    }

    function testFourElementTree() public view {
        bytes32[] memory leaves = new bytes32[](4);
        for (uint256 i = 0; i < 4; i++) {
            LPIntent memory intent = _makeIntent(address(uint160(i + 1)), (i + 1) * 100e18, 0);
            leaves[i] = harness.computeLeaf(intent);
        }

        bytes32 root = harness.computeRoot(leaves);

        // Manually compute: hash(hash(l0,l1), hash(l2,l3))
        bytes32 pair01 = _sortedHash(leaves[0], leaves[1]);
        bytes32 pair23 = _sortedHash(leaves[2], leaves[3]);
        bytes32 expectedRoot = _sortedHash(pair01, pair23);
        assertEq(root, expectedRoot);

        // Verify leaf[0] with proof [leaf1, hash(leaf2,leaf3)]
        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = leaves[1];
        proof0[1] = pair23;
        assertTrue(harness.verifyBatchInclusion(root, leaves[0], proof0));
    }
}
