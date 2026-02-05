"""Intent collection API (FastAPI)."""

import time
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from .types import LPIntentRequest, BatchStatus, LPIntent
from .signer import verify_intent_signature


class IntentCollector:
    """Collects and validates LP intents."""

    def __init__(self, chain_id: int, verifying_contract: str):
        self.chain_id = chain_id
        self.verifying_contract = verifying_contract
        self.pending_intents: list[tuple[LPIntent, bytes]] = []  # (intent, signature)
        self.batches_executed = 0
        self.last_batch_root: str | None = None
        self.last_batch_tx: str | None = None
        self.batch_history: list[dict] = []

    def submit_intent(self, request: LPIntentRequest) -> dict:
        """Validate and store a signed intent."""
        intent = request.to_lp_intent()
        signature = bytes.fromhex(request.signature.removeprefix("0x"))

        # Validate deadline
        if intent.deadline < int(time.time()):
            raise HTTPException(status_code=400, detail="Intent deadline has passed")

        # Verify signature
        try:
            recovered = verify_intent_signature(
                intent, signature, self.chain_id, self.verifying_contract
            )
            if recovered.lower() != intent.user.lower():
                raise HTTPException(
                    status_code=400,
                    detail=f"Signature mismatch: recovered {recovered}, expected {intent.user}",
                )
        except Exception as e:
            if isinstance(e, HTTPException):
                raise
            raise HTTPException(status_code=400, detail=f"Invalid signature: {e}")

        # Check for duplicate nonce
        for existing_intent, _ in self.pending_intents:
            if (
                existing_intent.user.lower() == intent.user.lower()
                and existing_intent.nonce == intent.nonce
            ):
                raise HTTPException(status_code=400, detail="Duplicate nonce")

        self.pending_intents.append((intent, signature))
        return {"status": "accepted", "pending_count": len(self.pending_intents)}

    def get_pending(self) -> list[dict]:
        """Return pending intents."""
        result = []
        for intent, sig in self.pending_intents:
            result.append(
                {
                    "user": intent.user,
                    "tick_lower": intent.tick_lower,
                    "tick_upper": intent.tick_upper,
                    "amount": str(intent.amount),
                    "nonce": intent.nonce,
                    "deadline": intent.deadline,
                }
            )
        return result

    def get_status(self) -> BatchStatus:
        """Return current batch status."""
        return BatchStatus(
            pending_intents=len(self.pending_intents),
            last_batch_root=self.last_batch_root,
            last_batch_tx=self.last_batch_tx,
            batches_executed=self.batches_executed,
        )

    def drain_pending(self) -> list[tuple[LPIntent, bytes]]:
        """Remove and return all pending intents for batching."""
        intents = list(self.pending_intents)
        self.pending_intents.clear()
        return intents

    def record_batch(self, root: str, tx_hash: str, intent_count: int = 0):
        """Record a completed batch."""
        self.last_batch_root = root
        self.last_batch_tx = tx_hash
        self.batches_executed += 1
        self.batch_history.append(
            {
                "root": root,
                "tx_hash": tx_hash,
                "intent_count": intent_count,
                "timestamp": int(time.time()),
            }
        )


def create_app(collector: IntentCollector, config=None, adaptive=None) -> FastAPI:
    """Create the FastAPI application."""
    app = FastAPI(title="PrivBatch Agent", version="0.1.0")

    # CORS for Next.js frontend
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.post("/intents")
    def submit_intent(request: LPIntentRequest):
        return collector.submit_intent(request)

    @app.get("/intents/pending")
    def get_pending():
        return collector.get_pending()

    @app.get("/batch/status")
    def get_status():
        return collector.get_status()

    @app.get("/config")
    def get_config():
        if config is None:
            return {"error": "Config not available"}
        return {
            "chain_id": config.chain_id,
            "hook_address": config.hook_address,
            "executor_address": config.executor_address,
            "commit_address": config.commit_address,
            "pool_manager": config.pool_manager_address,
            "position_manager": config.position_manager_address,
            "token_a": config.token_a_address,
            "token_b": config.token_b_address,
            "pool_key": {
                "currency0": min(config.token_a_address, config.token_b_address)
                if config.token_a_address and config.token_b_address
                else "",
                "currency1": max(config.token_a_address, config.token_b_address)
                if config.token_a_address and config.token_b_address
                else "",
                "fee": 3000,
                "tickSpacing": 60,
                "hooks": config.hook_address,
            },
        }

    @app.get("/optimizer/suggest")
    def suggest_range(
        price: float = Query(default=1.0, description="Current price"),
        volatility: float = Query(default=0.05, description="Annualized volatility"),
    ):
        from .optimizer import compute_optimal_range

        k = adaptive.k_multiplier if adaptive else 2.0
        tick_lower, tick_upper = compute_optimal_range(price, volatility, k, 60)
        return {
            "tick_lower": tick_lower,
            "tick_upper": tick_upper,
            "k_multiplier": k,
            "price": price,
            "volatility": volatility,
        }

    @app.get("/adaptive/stats")
    def get_adaptive_stats():
        if adaptive is None:
            return {"k_multiplier": 2.0, "total_batches": 0, "recent_avg_il": 0.0, "total_gas": 0}
        return adaptive.get_stats()

    @app.get("/batch/history")
    def get_batch_history():
        return collector.batch_history

    return app
