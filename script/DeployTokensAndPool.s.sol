// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {BatchExecutor} from "../src/BatchExecutor.sol";

/// @notice Deploy test tokens, initialize pool, and fund the executor
contract DeployTokensAndPool is Script {
    // sqrtPriceX96 for price = 1.0 (token0/token1 = 1:1)
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() public {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address executorAddress = vm.envAddress("EXECUTOR_ADDRESS");

        console.log("=== Deploy Test Tokens & Initialize Pool ===");
        console.log("Chain ID:", block.chainid);
        console.log("PoolManager:", poolManager);
        console.log("Hook:", hookAddress);
        console.log("Executor:", executorAddress);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy two MockERC20 tokens
        MockERC20 tokenRaw0 = new MockERC20("TestTokenA", "TTA", 18);
        MockERC20 tokenRaw1 = new MockERC20("TestTokenB", "TTB", 18);

        console.log("TokenRaw0 (TTA):", address(tokenRaw0));
        console.log("TokenRaw1 (TTB):", address(tokenRaw1));

        // 2. Sort so currency0 < currency1
        MockERC20 token0;
        MockERC20 token1;
        if (address(tokenRaw0) < address(tokenRaw1)) {
            token0 = tokenRaw0;
            token1 = tokenRaw1;
        } else {
            token0 = tokenRaw1;
            token1 = tokenRaw0;
        }

        console.log("");
        console.log("Sorted currency0:", address(token0));
        console.log("Sorted currency1:", address(token1));

        // 3. Mint 10M of each to deployer
        uint256 mintAmount = 10_000_000 * 1e18;
        token0.mint(msg.sender, mintAmount);
        token1.mint(msg.sender, mintAmount);
        console.log("Minted 10M of each token to deployer");

        // 4. Initialize the pool
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: int24(60),
            hooks: IHooks(hookAddress)
        });

        IPoolManager(poolManager).initialize(poolKey, SQRT_PRICE_1_1);
        console.log("Pool initialized with sqrtPrice 1:1");

        // 5. Transfer 1M of each to the executor
        uint256 executorAmount = 1_000_000 * 1e18;
        token0.mint(executorAddress, executorAmount);
        token1.mint(executorAddress, executorAmount);
        console.log("Minted 1M of each token to executor");

        // 6. Approve tokens on executor (ERC20 -> Permit2 -> PositionManager)
        BatchExecutor executor = BatchExecutor(executorAddress);
        executor.approveTokens(address(token0), type(uint256).max);
        executor.approveTokens(address(token1), type(uint256).max);
        console.log("Token approvals set on executor");

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("Add these to your .env file:");
        console.log(string.concat("TOKEN_A=", vm.toString(address(token0))));
        console.log(string.concat("TOKEN_B=", vm.toString(address(token1))));
    }
}
