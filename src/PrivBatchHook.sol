// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {LPIntent} from "./types/LPIntent.sol";
import {IntentVerifier} from "./libraries/IntentVerifier.sol";
import {BatchMerkle} from "./libraries/BatchMerkle.sol";

/// @title PrivBatchHook
/// @notice Uniswap v4 hook enforcing batched LP operations with Merkle proofs and EIP-712 signatures
contract PrivBatchHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    // --- Events ---
    event BatchExecuted(bytes32 indexed batchRoot, uint256 intentCount);
    event IntentFulfilled(bytes32 indexed batchRoot, address indexed user);

    // --- Errors ---
    error HookDataRequired();
    error BatchAlreadyExecuted();
    error HookPaused();
    error NotOwner();
    error BatchTooSmall();

    // --- State ---
    mapping(bytes32 => bool) public executedBatches;
    mapping(bytes32 => uint256) public batchIntentCount;
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    uint256 public minBatchSize;
    address public owner;
    bool public paused;

    bytes32 public immutable DOMAIN_SEPARATOR;

    constructor(IPoolManager _poolManager, uint256 _minBatchSize) BaseHook(_poolManager) {
        owner = msg.sender;
        minBatchSize = _minBatchSize;
        DOMAIN_SEPARATOR = IntentVerifier.domainSeparator("PrivBatch", "1", address(this));
    }

    // --- Hook Permissions ---
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // --- Hook Implementations ---

    function _beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        if (paused) revert HookPaused();
        if (hookData.length == 0) revert HookDataRequired();

        // Decode hookData: (batchRoot, merkleProof, intent, signature, batchSize)
        (bytes32 batchRoot, bytes32[] memory merkleProof, LPIntent memory intent, bytes memory signature, uint256 batchSize) =
            abi.decode(hookData, (bytes32, bytes32[], LPIntent, bytes, uint256));

        // Check batch size meets minimum
        if (batchSize < minBatchSize) revert BatchTooSmall();

        // Verify Merkle proof
        bytes32 leaf = BatchMerkle.computeLeaf(intent);
        BatchMerkle.requireBatchInclusion(batchRoot, leaf, merkleProof);

        // Verify EIP-712 signature
        IntentVerifier.verifySignature(DOMAIN_SEPARATOR, intent, signature, usedNonces);

        // Track batch intent count (first intent in batch registers it)
        if (!executedBatches[batchRoot]) {
            batchIntentCount[batchRoot] = batchSize;
        }

        return BaseHook.beforeAddLiquidity.selector;
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (hookData.length > 0) {
            (bytes32 batchRoot,,LPIntent memory intent,,) =
                abi.decode(hookData, (bytes32, bytes32[], LPIntent, bytes, uint256));

            emit IntentFulfilled(batchRoot, intent.user);

            // Mark batch as executed after processing
            if (!executedBatches[batchRoot]) {
                executedBatches[batchRoot] = true;
                emit BatchExecuted(batchRoot, batchIntentCount[batchRoot]);
            }
        }

        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        if (paused) revert HookPaused();
        // Allow direct removals (no batching required for removals)
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    // --- Admin ---

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function setMinBatchSize(uint256 _minBatchSize) external onlyOwner {
        minBatchSize = _minBatchSize;
    }
}
