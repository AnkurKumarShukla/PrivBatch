// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LPIntent} from "../types/LPIntent.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title IntentVerifier
/// @notice EIP-712 signature verification for LP intents
library IntentVerifier {
    using ECDSA for bytes32;

    bytes32 public constant POOL_KEY_TYPEHASH = keccak256(
        "PoolKey(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)"
    );

    bytes32 public constant LP_INTENT_TYPEHASH = keccak256(
        "LPIntent(address user,PoolKey pool,int24 tickLower,int24 tickUpper,uint256 amount,uint256 nonce,uint256 deadline)PoolKey(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)"
    );

    error InvalidSignature();
    error IntentExpired();
    error NonceAlreadyUsed();

    /// @notice Compute the EIP-712 domain separator
    function domainSeparator(string memory name, string memory version, address verifyingContract)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                verifyingContract
            )
        );
    }

    /// @notice Hash a PoolKey struct
    function hashPoolKey(PoolKey memory pool) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                POOL_KEY_TYPEHASH,
                Currency.unwrap(pool.currency0),
                Currency.unwrap(pool.currency1),
                pool.fee,
                pool.tickSpacing,
                address(pool.hooks)
            )
        );
    }

    /// @notice Hash an LPIntent struct for EIP-712
    function hashIntent(LPIntent memory intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                LP_INTENT_TYPEHASH,
                intent.user,
                hashPoolKey(intent.pool),
                intent.tickLower,
                intent.tickUpper,
                intent.amount,
                intent.nonce,
                intent.deadline
            )
        );
    }

    /// @notice Build the EIP-712 digest for signing
    function getDigest(bytes32 _domainSeparator, LPIntent memory intent) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator, hashIntent(intent)));
    }

    /// @notice Verify an EIP-712 signature for an LPIntent
    /// @param _domainSeparator The domain separator for the verifying contract
    /// @param intent The LP intent
    /// @param signature The EIP-712 signature
    /// @param nonces Mapping of user nonces for replay protection
    function verifySignature(
        bytes32 _domainSeparator,
        LPIntent memory intent,
        bytes memory signature,
        mapping(address => mapping(uint256 => bool)) storage nonces
    ) internal {
        if (block.timestamp > intent.deadline) revert IntentExpired();
        if (nonces[intent.user][intent.nonce]) revert NonceAlreadyUsed();

        bytes32 digest = getDigest(_domainSeparator, intent);
        address signer = digest.recover(signature);

        if (signer != intent.user) revert InvalidSignature();

        nonces[intent.user][intent.nonce] = true;
    }
}
