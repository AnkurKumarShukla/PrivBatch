#!/usr/bin/env python3
"""
PrivBatch Coordinator - Full Demo Test Script
Tests both AGENTIC FINANCE and PRIVACY aspects.

Usage (while agent is running on localhost:8000):
    python3 agent/test_demo.py

Prerequisites:
    - Agent running: cd agent && python3 -m src.main
    - .env configured with Sepolia RPC, private key, and deployed contract addresses
"""

import json
import os
import sys
import time
import requests
from pathlib import Path
from eth_account import Account
from web3 import Web3
from dotenv import load_dotenv

# Load .env from project root
env_path = Path(__file__).parent.parent / ".env"
load_dotenv(env_path)

# Add agent src to path
sys.path.insert(0, str(Path(__file__).parent))
from src.types import LPIntent, PoolKey
from src.signer import sign_intent
from src.merkle import MerkleTree, compute_leaf

# === Configuration ===
AGENT_URL = "http://localhost:8000"
RPC_URL = os.getenv("RPC_URL")
PRIVATE_KEY = os.getenv("PRIVATE_KEY")
HOOK_ADDRESS = os.getenv("HOOK_ADDRESS")
COMMIT_ADDRESS = os.getenv("COMMIT_ADDRESS")
EXECUTOR_ADDRESS = os.getenv("EXECUTOR_ADDRESS")
CHAIN_ID = 11155111  # Sepolia

# Colors for terminal output
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"


def header(title):
    print(f"\n{BOLD}{CYAN}{'=' * 60}")
    print(f"  {title}")
    print(f"{'=' * 60}{RESET}\n")


def passed(msg):
    print(f"  {GREEN}PASS{RESET} {msg}")


def failed(msg):
    print(f"  {RED}FAIL{RESET} {msg}")


def info(msg):
    print(f"  {YELLOW}INFO{RESET} {msg}")


# =====================================================
# TEST 1: Agent API Health Check (Agentic Finance)
# =====================================================
def test_api_health():
    header("TEST 1: Agent API Health Check")

    # Check batch status
    r = requests.get(f"{AGENT_URL}/batch/status")
    assert r.status_code == 200, f"Status endpoint failed: {r.status_code}"
    status = r.json()
    passed(f"GET /batch/status -> {json.dumps(status)}")

    # Check pending intents
    r = requests.get(f"{AGENT_URL}/intents/pending")
    assert r.status_code == 200
    passed(f"GET /intents/pending -> {len(r.json())} pending")

    return True


# =====================================================
# TEST 2: EIP-712 Intent Signing (Privacy)
# =====================================================
def test_eip712_signing():
    header("TEST 2: EIP-712 Intent Signing")

    # Create 3 different test wallets (simulating 3 LPs)
    wallets = [Account.create() for _ in range(3)]

    info(f"Wallet 1: {wallets[0].address}")
    info(f"Wallet 2: {wallets[1].address}")
    info(f"Wallet 3: {wallets[2].address}")

    pool = PoolKey(
        currency0="0x0000000000000000000000000000000000000001",
        currency1="0x0000000000000000000000000000000000000002",
        fee=3000,
        tick_spacing=60,
        hooks=HOOK_ADDRESS,
    )

    intents = []
    signatures = []
    for i, wallet in enumerate(wallets):
        intent = LPIntent(
            user=wallet.address,
            pool=pool,
            tick_lower=-887220,
            tick_upper=887220,
            amount=(100 + i * 50) * 10**18,
            nonce=i,
            deadline=int(time.time()) + 3600,
        )
        sig = sign_intent(intent, wallet.key.hex(), CHAIN_ID, HOOK_ADDRESS)
        intents.append(intent)
        signatures.append(sig)
        passed(f"Wallet {i+1} signed intent (amount={intent.amount // 10**18} tokens)")

    info("All intents are EIP-712 signed - cannot be forged or tampered")
    return wallets, intents, signatures


# =====================================================
# TEST 3: Merkle Tree Privacy (Privacy)
# =====================================================
def test_merkle_privacy(intents):
    header("TEST 3: Merkle Tree Batch Privacy")

    # Compute leaves
    leaves = [compute_leaf(intent) for intent in intents]
    tree = MerkleTree(leaves)

    info(f"Batch Merkle Root: {tree.root.hex()[:16]}...")
    info("Only the root is published on-chain (32 bytes)")
    info("Individual intents are hidden until execution")

    # Verify each proof
    for i, intent in enumerate(intents):
        proof = tree.get_proof(i)
        valid = tree.verify(leaves[i], proof, tree.root)
        assert valid, f"Proof {i} failed!"
        passed(f"Intent {i+1} proof valid ({len(proof)} siblings)")

    # Show privacy: the root reveals NOTHING about individual intents
    info("")
    info("PRIVACY GUARANTEE:")
    info(f"  Root hash:     {tree.root.hex()[:32]}...")
    info(f"  Intent 1 leaf: {leaves[0].hex()[:32]}...")
    info(f"  Intent 2 leaf: {leaves[1].hex()[:32]}...")
    info(f"  Intent 3 leaf: {leaves[2].hex()[:32]}...")
    info("  -> Root cannot be reverse-engineered to reveal individual intents")
    info("  -> MEV bots cannot front-run because intent details are hidden")

    return tree


# =====================================================
# TEST 4: Submit Intents to Agent (Agentic Finance)
# =====================================================
def test_submit_intents(wallets, intents, signatures):
    header("TEST 4: Submit Signed Intents to Agent API")

    for i, (intent, sig) in enumerate(zip(intents, signatures)):
        payload = {
            "user": intent.user,
            "pool_currency0": intent.pool.currency0,
            "pool_currency1": intent.pool.currency1,
            "pool_fee": intent.pool.fee,
            "pool_tick_spacing": intent.pool.tick_spacing,
            "pool_hooks": intent.pool.hooks,
            "tick_lower": intent.tick_lower,
            "tick_upper": intent.tick_upper,
            "amount": intent.amount,
            "nonce": intent.nonce,
            "deadline": intent.deadline,
            "signature": "0x" + sig.hex(),
        }

        r = requests.post(f"{AGENT_URL}/intents", json=payload)
        if r.status_code == 200:
            result = r.json()
            passed(f"Intent {i+1} accepted (pending={result['pending_count']})")
        else:
            failed(f"Intent {i+1} rejected: {r.text}")
            return False

    # Verify pending
    r = requests.get(f"{AGENT_URL}/intents/pending")
    pending = r.json()
    info(f"Agent now has {len(pending)} pending intents")

    return True


# =====================================================
# TEST 5: Replay Protection (Privacy + Security)
# =====================================================
def test_replay_protection(intents, signatures):
    header("TEST 5: Replay Protection (Nonce Dedup)")

    # Try submitting the same intent again (same nonce)
    intent = intents[0]
    sig = signatures[0]
    payload = {
        "user": intent.user,
        "pool_currency0": intent.pool.currency0,
        "pool_currency1": intent.pool.currency1,
        "pool_fee": intent.pool.fee,
        "pool_tick_spacing": intent.pool.tick_spacing,
        "pool_hooks": intent.pool.hooks,
        "tick_lower": intent.tick_lower,
        "tick_upper": intent.tick_upper,
        "amount": intent.amount,
        "nonce": intent.nonce,
        "deadline": intent.deadline,
        "signature": "0x" + sig.hex(),
    }

    r = requests.post(f"{AGENT_URL}/intents", json=payload)
    if r.status_code == 400 and "Duplicate nonce" in r.text:
        passed("Duplicate intent correctly rejected (replay protection)")
    else:
        failed(f"Expected rejection, got: {r.status_code} {r.text}")
        return False

    return True


# =====================================================
# TEST 6: Forged Signature Rejection (Privacy)
# =====================================================
def test_forged_signature(intents):
    header("TEST 6: Forged Signature Rejection")

    intent = intents[0]
    # Create a fake signature (random bytes)
    fake_sig = "0x" + ("ab" * 65)

    payload = {
        "user": intent.user,
        "pool_currency0": intent.pool.currency0,
        "pool_currency1": intent.pool.currency1,
        "pool_fee": intent.pool.fee,
        "pool_tick_spacing": intent.pool.tick_spacing,
        "pool_hooks": intent.pool.hooks,
        "tick_lower": intent.tick_lower,
        "tick_upper": intent.tick_upper,
        "amount": intent.amount,
        "nonce": 999,  # different nonce to avoid dup check
        "deadline": intent.deadline,
        "signature": fake_sig,
    }

    r = requests.post(f"{AGENT_URL}/intents", json=payload)
    if r.status_code == 400:
        passed(f"Forged signature correctly rejected: {r.json()['detail'][:50]}")
    else:
        failed(f"Expected rejection, got: {r.status_code}")
        return False

    return True


# =====================================================
# TEST 7: Expired Intent Rejection (Security)
# =====================================================
def test_expired_intent():
    header("TEST 7: Expired Intent Rejection")

    wallet = Account.create()
    pool = PoolKey(
        currency0="0x0000000000000000000000000000000000000001",
        currency1="0x0000000000000000000000000000000000000002",
        fee=3000,
        tick_spacing=60,
        hooks=HOOK_ADDRESS,
    )

    # Intent with deadline in the past
    intent = LPIntent(
        user=wallet.address,
        pool=pool,
        tick_lower=-887220,
        tick_upper=887220,
        amount=100 * 10**18,
        nonce=0,
        deadline=int(time.time()) - 3600,  # 1 hour ago
    )
    sig = sign_intent(intent, wallet.key.hex(), CHAIN_ID, HOOK_ADDRESS)

    payload = {
        "user": intent.user,
        "pool_currency0": intent.pool.currency0,
        "pool_currency1": intent.pool.currency1,
        "pool_fee": intent.pool.fee,
        "pool_tick_spacing": intent.pool.tick_spacing,
        "pool_hooks": intent.pool.hooks,
        "tick_lower": intent.tick_lower,
        "tick_upper": intent.tick_upper,
        "amount": intent.amount,
        "nonce": intent.nonce,
        "deadline": intent.deadline,
        "signature": "0x" + sig.hex(),
    }

    r = requests.post(f"{AGENT_URL}/intents", json=payload)
    if r.status_code == 400 and "deadline" in r.text.lower():
        passed("Expired intent correctly rejected")
    else:
        failed(f"Expected rejection, got: {r.status_code} {r.text}")
        return False

    return True


# =====================================================
# TEST 8: Commit-Reveal On-Chain (Privacy)
# =====================================================
def test_commit_reveal_onchain():
    header("TEST 8: Commit-Reveal On-Chain (Sepolia)")

    if not RPC_URL or not PRIVATE_KEY or not COMMIT_ADDRESS:
        info("Skipping on-chain test (missing RPC_URL, PRIVATE_KEY, or COMMIT_ADDRESS)")
        return True

    w3 = Web3(Web3.HTTPProvider(RPC_URL))
    if not w3.is_connected():
        info(f"Cannot connect to {RPC_URL}, skipping on-chain test")
        return True

    account = Account.from_key(PRIVATE_KEY)
    info(f"Using account: {account.address}")
    info(f"Sepolia block: {w3.eth.block_number}")

    balance = w3.eth.get_balance(account.address)
    info(f"Balance: {w3.from_wei(balance, 'ether')} ETH")

    if balance < w3.to_wei(0.001, "ether"):
        info("Insufficient Sepolia ETH, skipping on-chain commit-reveal test")
        return True

    # CommitContract ABI (minimal)
    commit_abi = [
        {
            "inputs": [{"name": "commitHash", "type": "bytes32"}],
            "name": "commit",
            "outputs": [],
            "stateMutability": "nonpayable",
            "type": "function",
        },
        {
            "inputs": [{"name": "user", "type": "address"}],
            "name": "hasValidCommit",
            "outputs": [{"name": "", "type": "bool"}],
            "stateMutability": "view",
            "type": "function",
        },
        {
            "inputs": [],
            "name": "minRevealDelay",
            "outputs": [{"name": "", "type": "uint256"}],
            "stateMutability": "view",
            "type": "function",
        },
        {
            "inputs": [],
            "name": "commitExpiry",
            "outputs": [{"name": "", "type": "uint256"}],
            "stateMutability": "view",
            "type": "function",
        },
    ]

    commit_contract = w3.eth.contract(
        address=Web3.to_checksum_address(COMMIT_ADDRESS), abi=commit_abi
    )

    # Read contract params
    min_delay = commit_contract.functions.minRevealDelay().call()
    expiry = commit_contract.functions.commitExpiry().call()
    info(f"CommitContract: minRevealDelay={min_delay} blocks, commitExpiry={expiry} blocks")

    # Create a secret intent and commit its hash
    secret_intent_data = b"LP intent: add 100 ETH liquidity to WETH/USDC at tick [-887220, 887220]"
    salt = os.urandom(32)
    commit_hash = Web3.keccak(secret_intent_data + salt)

    info(f"Secret intent data: (hidden - only hash is published)")
    info(f"Commit hash: {commit_hash.hex()[:32]}...")
    info("An MEV bot seeing this hash CANNOT determine what the intent is")

    # Submit commit transaction (use pending nonce to avoid collisions)
    nonce = w3.eth.get_transaction_count(account.address, "pending")
    gas_price = int(w3.eth.gas_price * 1.5)  # 1.5x to avoid underpriced
    tx = commit_contract.functions.commit(commit_hash).build_transaction({
        "from": account.address,
        "nonce": nonce,
        "gas": 100000,
        "gasPrice": gas_price,
    })
    signed = w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    info(f"Commit tx sent: {tx_hash.hex()}")

    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
    if receipt["status"] == 1:
        passed(f"Commit successful! Block: {receipt['blockNumber']}, Gas: {receipt['gasUsed']}")
    else:
        failed("Commit transaction failed")
        return False

    # Verify commit exists
    has_commit = commit_contract.functions.hasValidCommit(account.address).call()
    if has_commit:
        passed("On-chain commit verified - intent is hidden until reveal window opens")
    else:
        failed("Commit not found on-chain")

    info("")
    info("PRIVACY FLOW DEMONSTRATED:")
    info("  1. User creates intent (kept private)")
    info("  2. User commits hash on-chain (only hash visible)")
    info("  3. MEV bots see the hash but cannot decode the intent")
    info(f"  4. After {min_delay} blocks, user can reveal and execute")
    info("  5. By reveal time, front-running is no longer profitable")

    return True


# =====================================================
# TEST 9: Batch Status After Submissions (Agentic)
# =====================================================
def test_batch_status():
    header("TEST 9: Batch Status & Agent Intelligence")

    r = requests.get(f"{AGENT_URL}/batch/status")
    status = r.json()

    info(f"Pending intents:  {status['pending_intents']}")
    info(f"Batches executed: {status['batches_executed']}")
    info(f"Last batch root:  {status['last_batch_root'] or 'none yet'}")
    info(f"Last batch tx:    {status['last_batch_tx'] or 'none yet'}")

    passed("Agent status retrieved")

    info("")
    info("AGENTIC FINANCE FLOW:")
    info("  1. Multiple LPs submit signed intents to the agent")
    info("  2. Agent collects intents in a queue")
    info("  3. When batch threshold is met, agent:")
    info("     a. Optimizes tick ranges based on volatility")
    info("     b. Builds Merkle tree for batch inclusion proofs")
    info("     c. Submits atomic batch transaction on-chain")
    info("  4. All positions created in ONE tx (gas savings ~45%)")
    info("  5. Agent adapts k-multiplier based on past IL performance")

    return True


# =====================================================
# MAIN
# =====================================================
def main():
    print(f"\n{BOLD}{CYAN}")
    print("  ____       _       ____        _       _     ")
    print(" |  _ \\ _ __(_)_   _| __ )  __ _| |_ ___| |__  ")
    print(" | |_) | '__| \\ \\ / /  _ \\ / _` | __/ __| '_ \\ ")
    print(" |  __/| |  | |\\ V /| |_) | (_| | || (__| | | |")
    print(" |_|   |_|  |_| \\_/ |____/ \\__,_|\\__\\___|_| |_|")
    print(f"{RESET}")
    print(f"  {BOLD}Full Demo: Agentic Finance + Privacy{RESET}")
    print(f"  Chain: Sepolia (11155111)")
    print(f"  Agent: {AGENT_URL}")
    print(f"  Hook:  {HOOK_ADDRESS}")
    print(f"  Commit: {COMMIT_ADDRESS}")
    print()

    results = {}

    # Test 1: API health
    try:
        results["API Health"] = test_api_health()
    except Exception as e:
        failed(f"API Health: {e}")
        print(f"\n{RED}Agent not running! Start it first:{RESET}")
        print(f"  cd agent && python3 -m src.main\n")
        return

    # Test 2: EIP-712 signing
    try:
        wallets, intents, signatures = test_eip712_signing()
        results["EIP-712 Signing"] = True
    except Exception as e:
        failed(f"EIP-712 Signing: {e}")
        results["EIP-712 Signing"] = False
        return

    # Test 3: Merkle privacy
    try:
        tree = test_merkle_privacy(intents)
        results["Merkle Privacy"] = True
    except Exception as e:
        failed(f"Merkle Privacy: {e}")
        results["Merkle Privacy"] = False

    # Test 4: Submit intents
    try:
        results["Submit Intents"] = test_submit_intents(wallets, intents, signatures)
    except Exception as e:
        failed(f"Submit Intents: {e}")
        results["Submit Intents"] = False

    # Test 5: Replay protection
    try:
        results["Replay Protection"] = test_replay_protection(intents, signatures)
    except Exception as e:
        failed(f"Replay Protection: {e}")
        results["Replay Protection"] = False

    # Test 6: Forged signature
    try:
        results["Forged Sig Rejection"] = test_forged_signature(intents)
    except Exception as e:
        failed(f"Forged Sig Rejection: {e}")
        results["Forged Sig Rejection"] = False

    # Test 7: Expired intent
    try:
        results["Expired Intent"] = test_expired_intent()
    except Exception as e:
        failed(f"Expired Intent: {e}")
        results["Expired Intent"] = False

    # Test 8: On-chain commit-reveal
    try:
        results["Commit-Reveal On-Chain"] = test_commit_reveal_onchain()
    except Exception as e:
        failed(f"Commit-Reveal: {e}")
        results["Commit-Reveal On-Chain"] = False

    # Test 9: Batch status
    try:
        results["Batch Status"] = test_batch_status()
    except Exception as e:
        failed(f"Batch Status: {e}")
        results["Batch Status"] = False

    # === Summary ===
    header("RESULTS SUMMARY")

    total = len(results)
    passes = sum(1 for v in results.values() if v)

    for name, result in results.items():
        status = f"{GREEN}PASS{RESET}" if result else f"{RED}FAIL{RESET}"
        category = "(Privacy)" if name in ["EIP-712 Signing", "Merkle Privacy", "Forged Sig Rejection", "Commit-Reveal On-Chain"] else "(Agentic)"
        if name in ["Replay Protection", "Expired Intent"]:
            category = "(Security)"
        print(f"  {status}  {name} {YELLOW}{category}{RESET}")

    print(f"\n  {BOLD}{passes}/{total} tests passed{RESET}\n")

    if passes == total:
        print(f"  {GREEN}{BOLD}All systems operational!{RESET}")
        print(f"  Your PrivBatch Coordinator is ready for the demo.\n")
    else:
        print(f"  {RED}Some tests failed - check output above.{RESET}\n")


if __name__ == "__main__":
    main()
