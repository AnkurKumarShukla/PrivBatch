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
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {BaseTest} from "./utils/BaseTest.sol";

import {PrivBatchHook} from "../src/PrivBatchHook.sol";
import {LPIntent} from "../src/types/LPIntent.sol";
import {IntentVerifier} from "../src/libraries/IntentVerifier.sol";
import {BatchMerkle} from "../src/libraries/BatchMerkle.sol";

contract PrivBatchHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;
    PrivBatchHook hook;
    PoolId poolId;

    // Test signers
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

        // Deploy hook with correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x5555 << 144)
        );
        bytes memory constructorArgs = abi.encode(poolManager, uint256(1)); // minBatchSize = 1
        deployCodeTo("PrivBatchHook.sol:PrivBatchHook", constructorArgs, flags);
        hook = PrivBatchHook(flags);

        // Create pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
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
        bytes32 root = leaf; // single element tree
        bytes32[] memory proof = new bytes32[](0);
        return abi.encode(root, proof, intent, sig, uint256(1));
    }

    function _buildTwoBatchHookData(
        LPIntent memory intent1,
        bytes memory sig1,
        LPIntent memory intent2,
        bytes memory sig2
    ) internal pure returns (bytes memory hookData1, bytes memory hookData2, bytes32 root) {
        bytes32 leaf1 = BatchMerkle.computeLeaf(intent1);
        bytes32 leaf2 = BatchMerkle.computeLeaf(intent2);

        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = leaf1;
        leaves[1] = leaf2;
        root = BatchMerkle.computeRoot(leaves);

        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf2;
        bytes32[] memory proof2 = new bytes32[](1);
        proof2[0] = leaf1;

        hookData1 = abi.encode(root, proof1, intent1, sig1, uint256(2));
        hookData2 = abi.encode(root, proof2, intent2, sig2, uint256(2));
    }

    /// @dev Mint using EasyPosm (for success cases)
    function _mintWithHookData(uint128 liquidity, bytes memory hookData) internal returns (uint256 tokenId) {
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

    /// @dev Directly call modifyLiquidities for revert tests (avoids balanceOf consuming expectRevert)
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

    // --- Tests ---

    function testValidBatchWithProofAndSignature() public {
        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        uint256 tokenId = _mintWithHookData(10e18, hookData);
        assertTrue(tokenId > 0);
    }

    function testInvalidMerkleProofReverts() public {
        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory sig = _signIntent(intent, pk1);

        bytes32 fakeRoot = keccak256("fake_root");
        bytes32[] memory proof = new bytes32[](0);
        bytes memory hookData = abi.encode(fakeRoot, proof, intent, sig, uint256(1));

        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, hookData);
    }

    function testInvalidSignatureReverts() public {
        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory wrongSig = _signIntent(intent, pk2);
        bytes memory hookData = _buildSingleBatchHookData(intent, wrongSig);

        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, hookData);
    }

    function testPausedHookReverts() public {
        hook.pause();

        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, hookData);
    }

    function testDirectAddWithoutHookDataReverts() public {
        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, Constants.ZERO_BYTES);
    }

    function testMultipleIntentsInSameBatch() public {
        LPIntent memory intent1 = _makeIntent(user1, 10e18, 0);
        LPIntent memory intent2 = _makeIntent(user2, 20e18, 0);

        bytes memory sig1 = _signIntent(intent1, pk1);
        bytes memory sig2 = _signIntent(intent2, pk2);

        (bytes memory hookData1, bytes memory hookData2,) = _buildTwoBatchHookData(intent1, sig1, intent2, sig2);

        uint256 tokenId1 = _mintWithHookData(10e18, hookData1);
        uint256 tokenId2 = _mintWithHookData(20e18, hookData2);

        assertTrue(tokenId1 > 0);
        assertTrue(tokenId2 > 0);
    }

    function testEmergencyPauseUnpause() public {
        hook.pause();
        assertTrue(hook.paused());

        hook.unpause();
        assertFalse(hook.paused());

        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        uint256 tokenId = _mintWithHookData(10e18, hookData);
        assertTrue(tokenId > 0);
    }

    function testNonOwnerCannotPause() public {
        vm.prank(user1);
        vm.expectRevert(PrivBatchHook.NotOwner.selector);
        hook.pause();
    }

    function testNonceReplayReverts() public {
        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        _mintWithHookData(10e18, hookData);

        // Same nonce again should fail
        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, hookData);
    }

    function testBatchBelowMinSizeReverts() public {
        hook.setMinBatchSize(3);

        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, hookData);
    }

    function testSetMinBatchSize() public {
        hook.setMinBatchSize(5);
        assertEq(hook.minBatchSize(), 5);
    }

    function testSetMinBatchSizeNonOwnerReverts() public {
        vm.prank(user1);
        vm.expectRevert(PrivBatchHook.NotOwner.selector);
        hook.setMinBatchSize(5);
    }

    function testExpiredIntentReverts() public {
        LPIntent memory intent = _makeIntent(user1, 10e18, 0);
        intent.deadline = block.timestamp - 1;
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        vm.expectRevert();
        _modifyLiquiditiesMint(10e18, hookData);
    }

    function testRemoveLiquidityAllowedDirectly() public {
        LPIntent memory intent = _makeIntent(user1, 100e18, 0);
        bytes memory sig = _signIntent(intent, pk1);
        bytes memory hookData = _buildSingleBatchHookData(intent, sig);

        uint256 tokenId = _mintWithHookData(100e18, hookData);

        positionManager.decreaseLiquidity(
            tokenId, 1e18, 0, 0, address(this), block.timestamp, Constants.ZERO_BYTES
        );
    }
}
