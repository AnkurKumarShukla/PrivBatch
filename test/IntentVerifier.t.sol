// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IntentVerifier} from "../src/libraries/IntentVerifier.sol";
import {LPIntent} from "../src/types/LPIntent.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @notice Wrapper contract to expose IntentVerifier library functions
contract IntentVerifierHarness {
    using IntentVerifier for *;

    mapping(address => mapping(uint256 => bool)) public nonces;

    bytes32 public immutable DOMAIN_SEPARATOR;

    constructor() {
        DOMAIN_SEPARATOR = IntentVerifier.domainSeparator("PrivBatch", "1", address(this));
    }

    function hashIntent(LPIntent memory intent) external pure returns (bytes32) {
        return IntentVerifier.hashIntent(intent);
    }

    function getDigest(LPIntent memory intent) external view returns (bytes32) {
        return IntentVerifier.getDigest(DOMAIN_SEPARATOR, intent);
    }

    function verifySignature(LPIntent memory intent, bytes memory signature) external {
        IntentVerifier.verifySignature(DOMAIN_SEPARATOR, intent, signature, nonces);
    }

    function isNonceUsed(address user, uint256 nonce) external view returns (bool) {
        return nonces[user][nonce];
    }
}

contract IntentVerifierTest is Test {
    IntentVerifierHarness harness;

    uint256 signerPk = 0xA11CE;
    address signer;

    PoolKey testPool;
    LPIntent testIntent;

    function setUp() public {
        harness = new IntentVerifierHarness();
        signer = vm.addr(signerPk);

        testPool = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        testIntent = LPIntent({
            user: signer,
            pool: testPool,
            tickLower: -887220,
            tickUpper: 887220,
            amount: 100e18,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
    }

    function _signIntent(LPIntent memory intent, uint256 pk) internal view returns (bytes memory) {
        bytes32 digest = harness.getDigest(intent);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testHashIntentDeterministic() public view {
        bytes32 hash1 = harness.hashIntent(testIntent);
        bytes32 hash2 = harness.hashIntent(testIntent);
        assertEq(hash1, hash2);
    }

    function testHashIntentDifferentIntents() public view {
        LPIntent memory other = testIntent;
        other.amount = 200e18;
        assertNotEq(harness.hashIntent(testIntent), harness.hashIntent(other));
    }

    function testSignAndVerifyRoundtrip() public {
        bytes memory sig = _signIntent(testIntent, signerPk);
        harness.verifySignature(testIntent, sig);
        assertTrue(harness.isNonceUsed(signer, 0));
    }

    function testInvalidSignatureReverts() public {
        uint256 wrongPk = 0xDEAD;
        bytes memory sig = _signIntent(testIntent, wrongPk);

        vm.expectRevert(IntentVerifier.InvalidSignature.selector);
        harness.verifySignature(testIntent, sig);
    }

    function testExpiredDeadlineReverts() public {
        testIntent.deadline = block.timestamp - 1;
        bytes memory sig = _signIntent(testIntent, signerPk);

        vm.expectRevert(IntentVerifier.IntentExpired.selector);
        harness.verifySignature(testIntent, sig);
    }

    function testNonceReplayReverts() public {
        bytes memory sig = _signIntent(testIntent, signerPk);
        harness.verifySignature(testIntent, sig);

        vm.expectRevert(IntentVerifier.NonceAlreadyUsed.selector);
        harness.verifySignature(testIntent, sig);
    }

    function testDifferentNoncesWork() public {
        bytes memory sig1 = _signIntent(testIntent, signerPk);
        harness.verifySignature(testIntent, sig1);

        testIntent.nonce = 1;
        bytes memory sig2 = _signIntent(testIntent, signerPk);
        harness.verifySignature(testIntent, sig2);

        assertTrue(harness.isNonceUsed(signer, 0));
        assertTrue(harness.isNonceUsed(signer, 1));
    }

    function testTamperedIntentFailsVerification() public {
        bytes memory sig = _signIntent(testIntent, signerPk);

        // Tamper with the intent after signing
        testIntent.amount = 999e18;

        vm.expectRevert(IntentVerifier.InvalidSignature.selector);
        harness.verifySignature(testIntent, sig);
    }
}
