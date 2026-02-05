// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {LPIntent} from "./types/LPIntent.sol";
import {BatchMerkle} from "./libraries/BatchMerkle.sol";

/// @title BatchExecutor
/// @notice Executes multiple LP intents atomically via PositionManager
contract BatchExecutor {
    IPositionManager public immutable positionManager;
    IPermit2 public immutable permit2;

    error EmptyBatch();
    error ArrayLengthMismatch();

    event BatchSubmitted(bytes32 indexed batchRoot, uint256 intentCount);

    constructor(IPositionManager _positionManager, IPermit2 _permit2) {
        positionManager = _positionManager;
        permit2 = _permit2;
    }

    /// @notice Execute a batch of LP intents atomically
    function executeBatch(
        LPIntent[] calldata intents,
        bytes[] calldata signatures,
        bytes32[][] calldata proofs
    ) external {
        uint256 n = intents.length;
        if (n == 0) revert EmptyBatch();
        if (signatures.length != n || proofs.length != n) revert ArrayLengthMismatch();

        // Compute Merkle root from all intents
        bytes32 batchRoot = _computeBatchRoot(intents);

        // Build and execute the modifyLiquidities call
        _executeModifyLiquidities(intents, signatures, proofs, batchRoot);

        emit BatchSubmitted(batchRoot, n);
    }

    function _computeBatchRoot(LPIntent[] calldata intents) internal pure returns (bytes32) {
        uint256 n = intents.length;
        bytes32[] memory leaves = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            leaves[i] = BatchMerkle.computeLeaf(intents[i]);
        }
        return BatchMerkle.computeRoot(leaves);
    }

    function _executeModifyLiquidities(
        LPIntent[] calldata intents,
        bytes[] calldata signatures,
        bytes32[][] calldata proofs,
        bytes32 batchRoot
    ) internal {
        uint256 n = intents.length;
        PoolKey memory pool = intents[0].pool;

        // Build actions bytes: N MINTs + SETTLE_PAIR + 2 SWEEPs
        bytes memory actions = _buildActions(n);
        bytes[] memory params = new bytes[](n + 3);

        // Encode each MINT_POSITION param
        for (uint256 i = 0; i < n; i++) {
            params[i] = _encodeMintParam(intents[i], signatures[i], proofs[i], batchRoot, n, pool);
        }

        // SETTLE_PAIR + SWEEPs
        params[n] = abi.encode(pool.currency0, pool.currency1);
        params[n + 1] = abi.encode(pool.currency0, msg.sender);
        params[n + 2] = abi.encode(pool.currency1, msg.sender);

        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    function _buildActions(uint256 n) internal pure returns (bytes memory) {
        bytes memory mintActions = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            mintActions[i] = bytes1(uint8(Actions.MINT_POSITION));
        }
        return abi.encodePacked(mintActions, uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP), uint8(Actions.SWEEP));
    }

    function _encodeMintParam(
        LPIntent calldata intent,
        bytes calldata sig,
        bytes32[] calldata proof,
        bytes32 batchRoot,
        uint256 batchSize,
        PoolKey memory pool
    ) internal view returns (bytes memory) {
        bytes memory hookData = abi.encode(batchRoot, proof, intent, sig, batchSize);
        return abi.encode(
            pool,
            intent.tickLower,
            intent.tickUpper,
            intent.amount,
            type(uint256).max,
            type(uint256).max,
            msg.sender,
            hookData
        );
    }

    /// @notice Approve tokens for PositionManager via Permit2
    function approveTokens(address token, uint256 amount) external {
        IERC20(token).approve(address(permit2), amount);
        permit2.approve(token, address(positionManager), uint160(amount), type(uint48).max);
    }
}
