// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @title LPIntent
/// @notice EIP-712 typed data structure for LP intents
struct LPIntent {
    address user; // LP's address
    PoolKey pool; // Target pool
    int24 tickLower; // Desired range lower
    int24 tickUpper; // Desired range upper
    uint256 amount; // Liquidity amount
    uint256 nonce; // Replay protection
    uint256 deadline; // Expiry timestamp
}
