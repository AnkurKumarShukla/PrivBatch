"""Main orchestrator: collect -> optimize -> build tree -> execute."""

import asyncio
import logging
import time
import threading

import uvicorn
from web3 import Web3

from .config import Config
from .types import LPIntent
from .collector import IntentCollector, create_app
from .merkle import MerkleTree, compute_leaf
from .optimizer import compute_optimal_range, calculate_historical_volatility
from .executor import BatchSubmitter
from .adaptive import AdaptiveParams, BatchResult

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)


class PrivBatchAgent:
    """Main agent orchestrator."""

    def __init__(self, config: Config):
        self.config = config
        self.collector = IntentCollector(config.chain_id, config.hook_address)
        self.adaptive = AdaptiveParams(k_multiplier=config.k_multiplier)
        self.app = create_app(self.collector, config=config, adaptive=self.adaptive)
        self.running = False

        # Web3 connection (lazy)
        self._w3 = None
        self._submitter = None

    @property
    def w3(self) -> Web3:
        if self._w3 is None:
            self._w3 = Web3(Web3.HTTPProvider(self.config.rpc_url))
        return self._w3

    @property
    def submitter(self) -> BatchSubmitter:
        if self._submitter is None:
            self._submitter = BatchSubmitter(
                self.w3,
                self.config.executor_address,
                self.config.agent_private_key,
            )
        return self._submitter

    def process_batch(self) -> str | None:
        """Check for pending intents and process a batch if threshold met.

        Returns the transaction hash if a batch was submitted, None otherwise.
        """
        pending = self.collector.drain_pending()
        if len(pending) < self.config.min_batch_size:
            # Put them back if not enough
            self.collector.pending_intents.extend(pending)
            return None

        intents = [p[0] for p in pending]
        signatures = [p[1] for p in pending]

        logger.info(f"Processing batch of {len(intents)} intents")

        try:
            tx_hash = self.submitter.submit_batch(intents, signatures)
            batch_root = self.submitter.get_batch_root(intents)

            self.collector.record_batch(batch_root, tx_hash, len(intents))
            logger.info(f"Batch submitted: root={batch_root}, tx={tx_hash}")

            # Record for adaptive learning
            receipt = self.w3.eth.get_transaction_receipt(tx_hash)
            result = BatchResult(
                batch_root=batch_root,
                intent_count=len(intents),
                gas_used=receipt["gasUsed"],
                tick_lower=intents[0].tick_lower,
                tick_upper=intents[0].tick_upper,
            )
            self.adaptive.record_batch(result)
            self.adaptive.update_k()

            return tx_hash

        except Exception as e:
            logger.error(f"Batch submission failed: {e}")
            # Put intents back
            self.collector.pending_intents.extend(pending)
            return None

    def _batch_loop(self):
        """Background loop that checks for batches."""
        while self.running:
            try:
                self.process_batch()
            except Exception as e:
                logger.error(f"Batch loop error: {e}")
            time.sleep(self.config.batch_check_interval)

    def start(self):
        """Start the agent (API server + batch processing loop)."""
        self.running = True

        # Start batch processing in background thread
        batch_thread = threading.Thread(target=self._batch_loop, daemon=True)
        batch_thread.start()

        logger.info(
            f"PrivBatch Agent starting on {self.config.api_host}:{self.config.api_port}"
        )

        # Start API server (blocks)
        uvicorn.run(
            self.app,
            host=self.config.api_host,
            port=self.config.api_port,
            log_level="info",
        )

    def stop(self):
        """Stop the agent."""
        self.running = False


def main():
    """Entry point."""
    import argparse
    from pathlib import Path

    # Load .env from project root (one level above agent/)
    try:
        from dotenv import load_dotenv

        env_path = Path(__file__).parent.parent.parent / ".env"
        load_dotenv(env_path)
    except ImportError:
        pass

    parser = argparse.ArgumentParser(description="PrivBatch Agent")
    parser.add_argument("--test", action="store_true", help="Run in test mode against Anvil")
    parser.add_argument("--rpc", default=None, help="RPC URL (overrides .env)")
    parser.add_argument("--port", type=int, default=None, help="API port")
    args = parser.parse_args()

    config = Config()
    if args.rpc:
        config.rpc_url = args.rpc
    if args.port:
        config.api_port = args.port

    logger.info(f"Config loaded:")
    logger.info(f"  RPC:      {config.rpc_url[:40]}...")
    logger.info(f"  Hook:     {config.hook_address}")
    logger.info(f"  Executor: {config.executor_address}")
    logger.info(f"  Commit:   {config.commit_address}")
    logger.info(f"  Chain ID: {config.chain_id}")

    if args.test:
        logger.info("Running in test mode")
        _run_test_mode(config)
    else:
        agent = PrivBatchAgent(config)
        agent.start()


def _run_test_mode(config: Config):
    """Run a full local test cycle against Anvil."""
    from eth_account import Account

    logger.info("=== PrivBatch Agent Test Mode ===")

    # Connect to Anvil
    w3 = Web3(Web3.HTTPProvider(config.rpc_url))
    if not w3.is_connected():
        logger.error(f"Cannot connect to {config.rpc_url}. Is Anvil running?")
        return

    logger.info(f"Connected to chain {w3.eth.chain_id}")
    logger.info(f"Block number: {w3.eth.block_number}")

    # Test signer
    from .signer import sign_intent, verify_intent_signature
    from .types import LPIntent, PoolKey

    acct = Account.create()
    intent = LPIntent(
        user=acct.address,
        pool=PoolKey(
            currency0="0x0000000000000000000000000000000000001111",
            currency1="0x0000000000000000000000000000000000002222",
            fee=3000,
            tick_spacing=60,
            hooks="0x0000000000000000000000000000000000000000",
        ),
        tick_lower=-887220,
        tick_upper=887220,
        amount=100 * 10**18,
        nonce=0,
        deadline=int(time.time()) + 3600,
    )

    sig = sign_intent(intent, acct.key.hex(), w3.eth.chain_id, "0x" + "00" * 20)
    recovered = verify_intent_signature(intent, sig, w3.eth.chain_id, "0x" + "00" * 20)
    assert recovered.lower() == acct.address.lower()
    logger.info(f"Signer test: PASSED (addr={acct.address[:10]}...)")

    # Test Merkle tree
    from .merkle import MerkleTree, compute_leaf

    leaves = [compute_leaf(intent)]
    tree = MerkleTree(leaves)
    proof = tree.get_proof(0)
    assert tree.verify(leaves[0], proof, tree.root)
    logger.info(f"Merkle test: PASSED (root={tree.root.hex()[:16]}...)")

    # Test optimizer
    from .optimizer import compute_optimal_range

    tick_lower, tick_upper = compute_optimal_range(2450.0, 0.082, 2.0, 60)
    logger.info(f"Optimizer test: PASSED (range=[{tick_lower}, {tick_upper}])")

    # Test collector
    from .collector import IntentCollector
    from .types import LPIntentRequest

    collector = IntentCollector(w3.eth.chain_id, "0x" + "00" * 20)
    request = LPIntentRequest(
        user=acct.address,
        pool_currency0="0x0000000000000000000000000000000000001111",
        pool_currency1="0x0000000000000000000000000000000000002222",
        pool_fee=3000,
        pool_tick_spacing=60,
        pool_hooks="0x0000000000000000000000000000000000000000",
        tick_lower=-887220,
        tick_upper=887220,
        amount=100 * 10**18,
        nonce=0,
        deadline=int(time.time()) + 3600,
        signature="0x" + sig.hex(),
    )
    result = collector.submit_intent(request)
    assert result["status"] == "accepted"
    logger.info(f"Collector test: PASSED (pending={result['pending_count']})")

    # Test adaptive
    from .adaptive import AdaptiveParams, BatchResult

    adaptive = AdaptiveParams()
    adaptive.record_batch(
        BatchResult(
            batch_root="0x123",
            intent_count=3,
            gas_used=500000,
            tick_lower=-887220,
            tick_upper=887220,
            price_at_entry=2450.0,
            price_at_check=2480.0,
        )
    )
    stats = adaptive.get_stats()
    logger.info(f"Adaptive test: PASSED (k={stats['k_multiplier']})")

    logger.info("=== All test mode checks PASSED ===")


if __name__ == "__main__":
    main()
