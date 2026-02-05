// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title CommitContract
/// @notice Commit-reveal scheme for anti-front-running of LP intents
contract CommitContract {
    struct Commit {
        bytes32 hash;
        uint256 blockNumber;
        bool revealed;
    }

    /// @notice Minimum blocks before a commit can be revealed
    uint256 public immutable minRevealDelay;

    /// @notice Maximum blocks after which a commit expires
    uint256 public immutable commitExpiry;

    /// @notice Mapping of user address to their latest commit
    mapping(address => Commit) public commits;

    event IntentCommitted(address indexed user, bytes32 commitHash);
    event IntentRevealed(address indexed user, bytes data);

    error CommitAlreadyExists();
    error NoCommitFound();
    error RevealTooEarly();
    error CommitExpired();
    error HashMismatch();
    error AlreadyRevealed();

    constructor(uint256 _minRevealDelay, uint256 _commitExpiry) {
        minRevealDelay = _minRevealDelay;
        commitExpiry = _commitExpiry;
    }

    /// @notice Submit a hash commitment of intent data
    /// @param commitHash keccak256(abi.encodePacked(intentData, salt))
    function commit(bytes32 commitHash) external {
        commits[msg.sender] = Commit({hash: commitHash, blockNumber: block.number, revealed: false});

        emit IntentCommitted(msg.sender, commitHash);
    }

    /// @notice Reveal the committed intent after the delay window
    /// @param intentData The original intent data
    /// @param salt The salt used during commitment
    function reveal(bytes calldata intentData, bytes32 salt) external {
        Commit storage userCommit = commits[msg.sender];

        if (userCommit.hash == bytes32(0)) revert NoCommitFound();
        if (userCommit.revealed) revert AlreadyRevealed();
        if (block.number < userCommit.blockNumber + minRevealDelay) revert RevealTooEarly();
        if (block.number > userCommit.blockNumber + commitExpiry) revert CommitExpired();

        bytes32 expectedHash = keccak256(abi.encodePacked(intentData, salt));
        if (expectedHash != userCommit.hash) revert HashMismatch();

        userCommit.revealed = true;

        emit IntentRevealed(msg.sender, intentData);
    }

    /// @notice Check if a user's commit has been revealed
    function isRevealed(address user) external view returns (bool) {
        return commits[user].revealed;
    }

    /// @notice Check if a user has a valid (non-expired, non-revealed) commit
    function hasValidCommit(address user) external view returns (bool) {
        Commit storage c = commits[user];
        if (c.hash == bytes32(0)) return false;
        if (c.revealed) return false;
        if (block.number > c.blockNumber + commitExpiry) return false;
        return true;
    }
}
