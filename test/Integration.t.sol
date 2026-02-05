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
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {BaseTest} from "./utils/BaseTest.sol";

import {PrivBatchHook} from "../src/PrivBatchHook.sol";
import {BatchExecutor} from "../src/BatchExecutor.sol";
import {CommitContract} from "../src/CommitContract.sol";
import {LPIntent} from "../src/types/LPIntent.sol";
import {IntentVerifier} from "../src/libraries/IntentVerifier.sol";
import {BatchMerkle} from "../src/libraries/BatchMerkle.sol";

contract IntegrationTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;
    PrivBatchHook hook;
    BatchExecutor executor;
    CommitContract commitContract;
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

        // Deploy commit contract (5 block delay, 100 block expiry)
        commitContract = new CommitContract(5, 100);

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

        // Fund executor
        MockERC20(Currency.unwrap(currency0)).transfer(address(executor), 1_000_000 ether);
        MockERC20(Currency.unwrap(currency1)).transfer(address(executor), 1_000_000 ether);
        executor.approveTokens(Currency.unwrap(currency0), type(uint256).max);
        executor.approveTokens(Currency.unwrap(currency1), type(uint256).max);

        // Approvals for test contract (direct minting)
        MockERC20(Currency.unwrap(currency0)).approve(address(permit2), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(currency0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(currency1), address(positionManager), type(uint160).max, type(uint48).max);
    }

    // --- Helpers ---

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

    function _buildSingleBatchHookData(LPIntent memory intent, bytes memory sig)
        internal
        pure
        returns (bytes memory)
    {
        bytes32 leaf = BatchMerkle.computeLeaf(intent);
        bytes32[] memory proof = new bytes32[](0);
        return abi.encode(leaf, proof, intent, sig, uint256(1));
    }

    function _mintDirect(uint128 liquidity, bytes memory hookData) internal returns (uint256 tokenId) {
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        (tokenId,) = positionManager.mint(
            poolKey, tickLower, tickUpper, liquidity, amount0 + 1, amount1 + 1, address(this), block.timestamp, hookData
        );
    }

    function _modifyLiquiditiesMint(uint128 liquidity, bytes memory hookData) internal {
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP), uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, amount0 + 1, amount1 + 1, address(this), hookData);
        params[1] = abi.encode(currency0, currency1);
        params[2] = abi.encode(currency0, address(this));
        params[3] = abi.encode(currency1, address(this));

        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    function _computeProofs3(LPIntent[] memory intents)
        internal
        pure
        returns (bytes32[][] memory proofs)
    {
        bytes32[] memory leaves = new bytes32[](3);
        for (uint256 i = 0; i < 3; i++) {
            leaves[i] = BatchMerkle.computeLeaf(intents[i]);
        }

        bytes32 pair01;
        if (leaves[0] <= leaves[1]) {
            pair01 = keccak256(abi.encodePacked(leaves[0], leaves[1]));
        } else {
            pair01 = keccak256(abi.encodePacked(leaves[1], leaves[0]));
        }

        proofs = new bytes32[][](3);
        proofs[0] = new bytes32[](2);
        proofs[0][0] = leaves[1];
        proofs[0][1] = leaves[2];

        proofs[1] = new bytes32[](2);
        proofs[1][0] = leaves[0];
        proofs[1][1] = leaves[2];

        proofs[2] = new bytes32[](1);
        proofs[2][0] = pair01;
    }

    // ===== SCENARIO 1: Happy Path =====
    function testHappyPath_CommitRevealBatchExecute() public {
        // Step 1: Users commit their intents (hidden)
        LPIntent memory intent1 = _makeIntent(user1, 10e18, 0);
        LPIntent memory intent2 = _makeIntent(user2, 20e18, 0);
        LPIntent memory intent3 = _makeIntent(user3, 30e18, 0);

        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");

        bytes memory encodedIntent1 = abi.encode(intent1);
        bytes memory encodedIntent2 = abi.encode(intent2);
        bytes memory encodedIntent3 = abi.encode(intent3);

        vm.prank(user1);
        commitContract.commit(keccak256(abi.encodePacked(encodedIntent1, salt1)));
        vm.prank(user2);
        commitContract.commit(keccak256(abi.encodePacked(encodedIntent2, salt2)));
        vm.prank(user3);
        commitContract.commit(keccak256(abi.encodePacked(encodedIntent3, salt3)));

        // Step 2: Wait for reveal window
        vm.roll(block.number + 6);

        // Step 3: Users reveal
        vm.prank(user1);
        commitContract.reveal(encodedIntent1, salt1);
        vm.prank(user2);
        commitContract.reveal(encodedIntent2, salt2);
        vm.prank(user3);
        commitContract.reveal(encodedIntent3, salt3);

        // Step 4: Agent batches and executes
        LPIntent[] memory intents = new LPIntent[](3);
        intents[0] = intent1;
        intents[1] = intent2;
        intents[2] = intent3;

        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _signIntent(intent1, pk1);
        sigs[1] = _signIntent(intent2, pk2);
        sigs[2] = _signIntent(intent3, pk3);

        bytes32[][] memory proofs = _computeProofs3(intents);

        executor.executeBatch(intents, sigs, proofs);

        // Verify all reveals happened
        assertTrue(commitContract.isRevealed(user1));
        assertTrue(commitContract.isRevealed(user2));
        assertTrue(commitContract.isRevealed(user3));
    }

    // ===== SCENARIO 2: MEV Resistance =====
    function testMEVResistance_CommitHidesIntent() public {
        LPIntent memory intent = _makeIntent(user1, 100e18, 0);
        bytes32 salt = keccak256("secret");
        bytes memory encodedIntent = abi.encode(intent);
        bytes32 commitHash = keccak256(abi.encodePacked(encodedIntent, salt));

        // Commit only reveals the hash - MEV bot can see the hash but not the intent
        vm.prank(user1);
        commitContract.commit(commitHash);

        // Cannot reveal too early
        vm.roll(block.number + 2);
        vm.prank(user1);
        vm.expectRevert(CommitContract.RevealTooEarly.selector);
        commitContract.reveal(encodedIntent, salt);

        // After window, reveal succeeds
        vm.roll(block.number + 4);
        vm.prank(user1);
        commitContract.reveal(encodedIntent, salt);
    }

    // ===== SCENARIO 3: Invalid Batch =====
    function testInvalidBatch_TamperedIntent() public {
        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory sig = _signIntent(intent, pk1);

        // Tamper after signing
        intent.amount = 999e18;

        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        // Should fail because signature doesn't match tampered intent
        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, hookData);
    }

    // ===== SCENARIO 4: Replay Attack =====
    function testReplayAttack_SameBatchTwice() public {
        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        _mintDirect(10e18, hookData);

        // Replay same intent (same nonce) fails
        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, hookData);
    }

    // ===== SCENARIO 5: Emergency Pause =====
    function testEmergencyPause_BlocksAndResumes() public {
        // Pause
        hook.pause();

        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        // Execution blocked
        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, hookData);

        // Unpause
        hook.unpause();

        // Now succeeds
        _mintDirect(10e18, hookData);
    }

    // ===== SCENARIO 6: Gas Benchmarks =====
    function testGasBenchmark_SoloVsBatched() public {
        // Solo: 3 individual adds
        uint256 gasStart = gasleft();
        for (uint256 i = 0; i < 3; i++) {
            LPIntent memory intent = _makeIntent(vm.addr(uint256(keccak256(abi.encode("solo", i))) % type(uint248).max + 1), 10e18, i);
            bytes memory sig;
            {
                bytes32 digest = IntentVerifier.getDigest(hook.DOMAIN_SEPARATOR(), intent);
                uint256 soloPk = uint256(keccak256(abi.encode("solo", i))) % type(uint248).max + 1;
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(soloPk, digest);
                sig = abi.encodePacked(r, s, v);
            }
            bytes memory hookData = _buildSingleBatchHookData(intent, sig);
            _mintDirect(10e18, hookData);
        }
        uint256 gasSolo = gasStart - gasleft();

        // Batched: 3 intents via executor
        LPIntent[] memory intents = new LPIntent[](3);
        intents[0] = _makeIntent(user1, 10e18, 1); // nonce 1 to avoid collision
        intents[1] = _makeIntent(user2, 10e18, 1);
        intents[2] = _makeIntent(user3, 10e18, 1);

        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _signIntent(intents[0], pk1);
        sigs[1] = _signIntent(intents[1], pk2);
        sigs[2] = _signIntent(intents[2], pk3);

        bytes32[][] memory proofs = _computeProofs3(intents);

        gasStart = gasleft();
        executor.executeBatch(intents, sigs, proofs);
        uint256 gasBatch = gasStart - gasleft();

        emit log_named_uint("Gas: 3 solo adds", gasSolo);
        emit log_named_uint("Gas: 1 batched (3 intents)", gasBatch);
        emit log_named_uint("Gas savings", gasSolo > gasBatch ? gasSolo - gasBatch : 0);
    }

    // ===== SCENARIO 7: Remove liquidity (direct) =====
    function testRemoveLiquidity_Direct() public {
        // Add via batch
        LPIntent memory intent = _makeIntent(user1, 100e18, 0);
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        uint256 tokenId = _mintDirect(100e18, hookData);

        // Remove directly (no batching required)
        positionManager.decreaseLiquidity(
            tokenId, 50e18, 0, 0, address(this), block.timestamp, Constants.ZERO_BYTES
        );
    }
}
