// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {PrivBatchHook} from "../src/PrivBatchHook.sol";
import {BatchExecutor} from "../src/BatchExecutor.sol";
import {CommitContract} from "../src/CommitContract.sol";

/// @notice Deploy all PrivBatch contracts
contract DeployAll is Script {
    // CREATE2 deployer (standard across all chains)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() public {
        // Read from environment
        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        address permit2Addr = vm.envAddress("PERMIT2");

        console.log("=== PrivBatch Coordinator - Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("PoolManager:", poolManager);
        console.log("PositionManager:", positionManager);
        console.log("Permit2:", permit2Addr);
        console.log("");

        // Mine hook address with correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(IPoolManager(poolManager), uint256(1));
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(PrivBatchHook).creationCode,
            constructorArgs
        );

        console.log("Mined hook address:", hookAddress);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy CommitContract
        CommitContract commitContract = new CommitContract(5, 100);
        console.log("CommitContract:", address(commitContract));

        // 2. Deploy PrivBatchHook via CREATE2
        PrivBatchHook hook = new PrivBatchHook{salt: salt}(IPoolManager(poolManager), 1);
        require(address(hook) == hookAddress, "Hook address mismatch!");
        console.log("PrivBatchHook:", address(hook));

        // 3. Deploy BatchExecutor
        BatchExecutor executor = new BatchExecutor(
            IPositionManager(positionManager),
            IPermit2(permit2Addr)
        );
        console.log("BatchExecutor:", address(executor));

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("Copy these into your .env file:");
        console.log(string.concat("COMMIT_ADDRESS=", vm.toString(address(commitContract))));
        console.log(string.concat("HOOK_ADDRESS=", vm.toString(address(hook))));
        console.log(string.concat("EXECUTOR_ADDRESS=", vm.toString(address(executor))));
    }
}
