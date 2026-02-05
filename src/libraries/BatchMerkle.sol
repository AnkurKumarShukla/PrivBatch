// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {LPIntent} from "../types/LPIntent.sol";
import {IntentVerifier} from "./IntentVerifier.sol";

/// @title BatchMerkle
/// @notice Merkle proof verification for batch inclusion of LP intents
library BatchMerkle {
    error InvalidMerkleProof();

    /// @notice Compute a leaf from an LPIntent (uses the EIP-712 struct hash)
    function computeLeaf(LPIntent memory intent) internal pure returns (bytes32) {
        return IntentVerifier.hashIntent(intent);
    }

    /// @notice Verify that a leaf is included in the Merkle tree with the given root
    function verifyBatchInclusion(bytes32 root, bytes32 leaf, bytes32[] memory proof) internal pure returns (bool) {
        return MerkleProof.verify(proof, root, leaf);
    }

    /// @notice Verify batch inclusion, reverts on failure
    function requireBatchInclusion(bytes32 root, bytes32 leaf, bytes32[] memory proof) internal pure {
        if (!MerkleProof.verify(proof, root, leaf)) {
            revert InvalidMerkleProof();
        }
    }

    /// @notice Compute Merkle root from an array of leaves (for on-chain tree building)
    /// @dev Uses a simple bottom-up construction. Leaves must be sorted.
    function computeRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        require(leaves.length > 0, "BatchMerkle: empty leaves");
        if (leaves.length == 1) return leaves[0];

        uint256 n = leaves.length;
        // Work with a copy
        bytes32[] memory layer = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            layer[i] = leaves[i];
        }

        while (n > 1) {
            uint256 nextN = (n + 1) / 2;
            for (uint256 i = 0; i < nextN; i++) {
                uint256 left = i * 2;
                uint256 right = left + 1;
                if (right < n) {
                    // Sort pair before hashing (OpenZeppelin standard)
                    if (layer[left] <= layer[right]) {
                        layer[i] = keccak256(abi.encodePacked(layer[left], layer[right]));
                    } else {
                        layer[i] = keccak256(abi.encodePacked(layer[right], layer[left]));
                    }
                } else {
                    layer[i] = layer[left];
                }
            }
            n = nextN;
        }
        return layer[0];
    }
}
