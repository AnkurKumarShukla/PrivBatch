// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CommitContract} from "../src/CommitContract.sol";

contract CommitContractTest is Test {
    CommitContract commitContract;

    uint256 constant MIN_REVEAL_DELAY = 5;
    uint256 constant COMMIT_EXPIRY = 100;

    address user1 = address(0x1);
    address user2 = address(0x2);

    bytes intentData = abi.encodePacked("addLiquidity", uint256(1000));
    bytes32 salt = keccak256("secret_salt");

    function setUp() public {
        commitContract = new CommitContract(MIN_REVEAL_DELAY, COMMIT_EXPIRY);
    }

    function _computeHash(bytes memory data, bytes32 _salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(data, _salt));
    }

    function testCommitStoresHashCorrectly() public {
        bytes32 commitHash = _computeHash(intentData, salt);

        vm.prank(user1);
        commitContract.commit(commitHash);

        (bytes32 storedHash, uint256 blockNum, bool revealed) = commitContract.commits(user1);
        assertEq(storedHash, commitHash);
        assertEq(blockNum, block.number);
        assertFalse(revealed);
    }

    function testRevealSucceedsWhenValid() public {
        bytes32 commitHash = _computeHash(intentData, salt);

        vm.prank(user1);
        commitContract.commit(commitHash);

        // Advance past min reveal delay
        vm.roll(block.number + MIN_REVEAL_DELAY + 1);

        vm.prank(user1);
        commitContract.reveal(intentData, salt);

        assertTrue(commitContract.isRevealed(user1));
    }

    function testRevealFailsIfHashMismatch() public {
        bytes32 commitHash = _computeHash(intentData, salt);

        vm.prank(user1);
        commitContract.commit(commitHash);

        vm.roll(block.number + MIN_REVEAL_DELAY + 1);

        bytes memory wrongData = abi.encodePacked("wrongData");

        vm.prank(user1);
        vm.expectRevert(CommitContract.HashMismatch.selector);
        commitContract.reveal(wrongData, salt);
    }

    function testRevealFailsIfTooEarly() public {
        bytes32 commitHash = _computeHash(intentData, salt);

        vm.prank(user1);
        commitContract.commit(commitHash);

        // Only advance by 2 blocks (less than MIN_REVEAL_DELAY)
        vm.roll(block.number + 2);

        vm.prank(user1);
        vm.expectRevert(CommitContract.RevealTooEarly.selector);
        commitContract.reveal(intentData, salt);
    }

    function testRevealFailsIfCommitExpired() public {
        bytes32 commitHash = _computeHash(intentData, salt);

        vm.prank(user1);
        commitContract.commit(commitHash);

        // Advance past expiry
        vm.roll(block.number + COMMIT_EXPIRY + 1);

        vm.prank(user1);
        vm.expectRevert(CommitContract.CommitExpired.selector);
        commitContract.reveal(intentData, salt);
    }

    function testCannotDoubleReveal() public {
        bytes32 commitHash = _computeHash(intentData, salt);

        vm.prank(user1);
        commitContract.commit(commitHash);

        vm.roll(block.number + MIN_REVEAL_DELAY + 1);

        vm.prank(user1);
        commitContract.reveal(intentData, salt);

        vm.prank(user1);
        vm.expectRevert(CommitContract.AlreadyRevealed.selector);
        commitContract.reveal(intentData, salt);
    }

    function testMultipleUsersCanCommitIndependently() public {
        bytes32 salt2 = keccak256("other_salt");
        bytes memory intentData2 = abi.encodePacked("removeLiquidity", uint256(500));

        bytes32 hash1 = _computeHash(intentData, salt);
        bytes32 hash2 = _computeHash(intentData2, salt2);

        vm.prank(user1);
        commitContract.commit(hash1);

        vm.prank(user2);
        commitContract.commit(hash2);

        vm.roll(block.number + MIN_REVEAL_DELAY + 1);

        vm.prank(user1);
        commitContract.reveal(intentData, salt);

        vm.prank(user2);
        commitContract.reveal(intentData2, salt2);

        assertTrue(commitContract.isRevealed(user1));
        assertTrue(commitContract.isRevealed(user2));
    }

    function testHasValidCommit() public {
        assertFalse(commitContract.hasValidCommit(user1));

        bytes32 commitHash = _computeHash(intentData, salt);
        vm.prank(user1);
        commitContract.commit(commitHash);

        assertTrue(commitContract.hasValidCommit(user1));

        // After reveal, no longer valid
        vm.roll(block.number + MIN_REVEAL_DELAY + 1);
        vm.prank(user1);
        commitContract.reveal(intentData, salt);

        assertFalse(commitContract.hasValidCommit(user1));
    }

    function testCommitEmitsEvent() public {
        bytes32 commitHash = _computeHash(intentData, salt);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit CommitContract.IntentCommitted(user1, commitHash);
        commitContract.commit(commitHash);
    }

    function testRevealEmitsEvent() public {
        bytes32 commitHash = _computeHash(intentData, salt);

        vm.prank(user1);
        commitContract.commit(commitHash);

        vm.roll(block.number + MIN_REVEAL_DELAY + 1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit CommitContract.IntentRevealed(user1, intentData);
        commitContract.reveal(intentData, salt);
    }

    function testRevealFailsWithNoCommit() public {
        vm.prank(user1);
        vm.expectRevert(CommitContract.NoCommitFound.selector);
        commitContract.reveal(intentData, salt);
    }

    function testOverwriteCommit() public {
        bytes32 hash1 = _computeHash(intentData, salt);
        bytes32 salt2 = keccak256("new_salt");
        bytes memory newData = abi.encodePacked("newIntent");
        bytes32 hash2 = _computeHash(newData, salt2);

        vm.prank(user1);
        commitContract.commit(hash1);

        // Overwrite with new commit
        vm.prank(user1);
        commitContract.commit(hash2);

        vm.roll(block.number + MIN_REVEAL_DELAY + 1);

        // Old data should fail
        vm.prank(user1);
        vm.expectRevert(CommitContract.HashMismatch.selector);
        commitContract.reveal(intentData, salt);

        // New data should succeed
        vm.prank(user1);
        commitContract.reveal(newData, salt2);

        assertTrue(commitContract.isRevealed(user1));
    }
}
