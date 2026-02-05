// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {BaseTest} from "./utils/BaseTest.sol";

import {PrivBatchHook} from "../src/PrivBatchHook.sol";
import {BatchExecutor} from "../src/BatchExecutor.sol";
import {LPIntent} from "../src/types/LPIntent.sol";
import {IntentVerifier} from "../src/libraries/IntentVerifier.sol";
import {BatchMerkle} from "../src/libraries/BatchMerkle.sol";

contract BatchExecutorTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;
    PrivBatchHook hook;
    BatchExecutor executor;
    PoolId poolId;

    uint256 pk1 = 0xA11CE;
    uint256 pk2 = 0xB0B;
    uint256 pk3 = 0xCAFE;
    address user1;
    address user2;
    address user3;

    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        user1 = vm.addr(pk1);
        user2 = vm.addr(pk2);
        user3 = vm.addr(pk3);

        // Deploy hook
        address flags = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x5555 << 144)
        );
        bytes memory constructorArgs = abi.encode(poolManager, uint256(1));
        deployCodeTo("PrivBatchHook.sol:PrivBatchHook", constructorArgs, flags);
        hook = PrivBatchHook(flags);

        // Deploy executor
        executor = new BatchExecutor(positionManager, IPermit2(address(permit2)));

        // Create pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        // Transfer tokens to executor and set up its Permit2 approvals
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));

        // Fund the executor with tokens
        token0.transfer(address(executor), 1_000_000 ether);
        token1.transfer(address(executor), 1_000_000 ether);

        // Have executor approve Permit2 and PositionManager
        executor.approveTokens(Currency.unwrap(currency0), type(uint256).max);
        executor.approveTokens(Currency.unwrap(currency1), type(uint256).max);

        // Also keep approvals for test contract (for solo comparison)
        token0.approve(address(permit2), type(uint256).max);
        token1.approve(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(currency0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(currency1), address(positionManager), type(uint160).max, type(uint48).max);
    }

    function _makeIntent(address user, uint256 amount, uint256 nonce) internal view returns (LPIntent memory) {
        return LPIntent({
            user: user,
            pool: poolKey,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount: amount,
            nonce: nonce,
            deadline: block.timestamp + 1 hours
        });
    }

    function _signIntent(LPIntent memory intent, uint256 pk) internal view returns (bytes memory) {
        bytes32 digest = IntentVerifier.getDigest(hook.DOMAIN_SEPARATOR(), intent);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _computeProofs(LPIntent[] memory intents)
        internal
        pure
        returns (bytes32[][] memory proofs, bytes32 root)
    {
        uint256 n = intents.length;
        bytes32[] memory leaves = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            leaves[i] = BatchMerkle.computeLeaf(intents[i]);
        }
        root = BatchMerkle.computeRoot(leaves);

        proofs = new bytes32[][](n);

        if (n == 1) {
            proofs[0] = new bytes32[](0);
        } else if (n == 2) {
            proofs[0] = new bytes32[](1);
            proofs[0][0] = leaves[1];
            proofs[1] = new bytes32[](1);
            proofs[1][0] = leaves[0];
        } else if (n == 3) {
            // Tree: hash(hash(l0,l1), l2)
            bytes32 pair01;
            if (leaves[0] <= leaves[1]) {
                pair01 = keccak256(abi.encodePacked(leaves[0], leaves[1]));
            } else {
                pair01 = keccak256(abi.encodePacked(leaves[1], leaves[0]));
            }

            proofs[0] = new bytes32[](2);
            proofs[0][0] = leaves[1];
            proofs[0][1] = leaves[2];

            proofs[1] = new bytes32[](2);
            proofs[1][0] = leaves[0];
            proofs[1][1] = leaves[2];

            proofs[2] = new bytes32[](1);
            proofs[2][0] = pair01;
        }
    }

    function testExecuteBatchOfThreeIntents() public {
        LPIntent[] memory intents = new LPIntent[](3);
        intents[0] = _makeIntent(user1, 10e18, 0);
        intents[1] = _makeIntent(user2, 20e18, 0);
        intents[2] = _makeIntent(user3, 30e18, 0);

        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _signIntent(intents[0], pk1);
        sigs[1] = _signIntent(intents[1], pk2);
        sigs[2] = _signIntent(intents[2], pk3);

        (bytes32[][] memory proofs,) = _computeProofs(intents);

        // Convert to calldata-compatible arrays
        LPIntent[] memory callIntents = intents;
        bytes[] memory callSigs = sigs;
        bytes32[][] memory callProofs = proofs;

        executor.executeBatch(callIntents, callSigs, callProofs);
    }

    function testEmptyBatchReverts() public {
        LPIntent[] memory intents = new LPIntent[](0);
        bytes[] memory sigs = new bytes[](0);
        bytes32[][] memory proofs = new bytes32[][](0);

        vm.expectRevert(BatchExecutor.EmptyBatch.selector);
        executor.executeBatch(intents, sigs, proofs);
    }

    function testArrayLengthMismatchReverts() public {
        LPIntent[] memory intents = new LPIntent[](2);
        intents[0] = _makeIntent(user1, 10e18, 0);
        intents[1] = _makeIntent(user2, 20e18, 0);

        bytes[] memory sigs = new bytes[](1); // mismatched
        sigs[0] = _signIntent(intents[0], pk1);

        bytes32[][] memory proofs = new bytes32[][](2);

        vm.expectRevert(BatchExecutor.ArrayLengthMismatch.selector);
        executor.executeBatch(intents, sigs, proofs);
    }

    function testGasBatchVsSolo() public {
        // Measure gas for batch of 3
        LPIntent[] memory intents = new LPIntent[](3);
        intents[0] = _makeIntent(user1, 10e18, 0);
        intents[1] = _makeIntent(user2, 20e18, 1);
        intents[2] = _makeIntent(user3, 30e18, 0);

        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _signIntent(intents[0], pk1);
        sigs[1] = _signIntent(intents[1], pk2);
        sigs[2] = _signIntent(intents[2], pk3);

        (bytes32[][] memory proofs,) = _computeProofs(intents);

        uint256 gasBefore = gasleft();
        executor.executeBatch(intents, sigs, proofs);
        uint256 gasUsedBatch = gasBefore - gasleft();

        // Log gas for batch
        emit log_named_uint("Gas used for batch of 3", gasUsedBatch);
    }
}
