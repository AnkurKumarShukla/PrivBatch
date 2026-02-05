"""Adaptive learning from on-chain events."""

from dataclasses import dataclass, field


@dataclass
class BatchResult:
    """Result of a completed batch."""

    batch_root: str
    intent_count: int
    gas_used: int
    tick_lower: int
    tick_upper: int
    # Impermanent loss metrics (simplified)
    price_at_entry: float = 0.0
    price_at_check: float = 0.0


@dataclass
class AdaptiveParams:
    """Adaptive optimizer parameters."""

    k_multiplier: float = 2.0
    min_k: float = 1.0
    max_k: float = 5.0
    learning_rate: float = 0.1
    history: list[BatchResult] = field(default_factory=list)

    def record_batch(self, result: BatchResult):
        """Record a batch result for learning."""
        self.history.append(result)

    def calculate_il_score(self, result: BatchResult) -> float:
        """Calculate a simplified impermanent loss score.

        Returns a value between 0 (no IL) and 1 (maximum IL).
        Positive values indicate the range was too narrow.
        """
        if result.price_at_entry <= 0 or result.price_at_check <= 0:
            return 0.0

        price_ratio = result.price_at_check / result.price_at_entry

        # Check if price moved outside the range
        from .optimizer import tick_to_price

        lower_price = tick_to_price(result.tick_lower)
        upper_price = tick_to_price(result.tick_upper)

        current_price = result.price_at_check
        if current_price < lower_price or current_price > upper_price:
            return 1.0  # Price moved outside range - maximum IL indicator

        # IL approximation: 2*sqrt(price_ratio) / (1 + price_ratio) - 1
        il = 2 * (price_ratio**0.5) / (1 + price_ratio) - 1
        return abs(il)

    def update_k(self):
        """Adjust k_multiplier based on recent batch results.

        If recent batches show high IL (price going outside range),
        increase k to widen ranges. If IL is low, decrease k to
        concentrate liquidity.
        """
        if len(self.history) < 2:
            return

        # Use last N batches
        recent = self.history[-10:]
        il_scores = [self.calculate_il_score(r) for r in recent]
        avg_il = sum(il_scores) / len(il_scores) if il_scores else 0.0

        # Target: keep IL score around 0.3 (moderate)
        target_il = 0.3
        error = avg_il - target_il

        # If IL too high, increase k (wider ranges)
        # If IL too low, decrease k (narrower ranges for more fees)
        adjustment = self.learning_rate * error
        self.k_multiplier = max(self.min_k, min(self.max_k, self.k_multiplier + adjustment))

    def get_stats(self) -> dict:
        """Return current adaptive stats."""
        recent = self.history[-10:]
        il_scores = [self.calculate_il_score(r) for r in recent] if recent else []

        return {
            "k_multiplier": round(self.k_multiplier, 4),
            "total_batches": len(self.history),
            "recent_avg_il": round(sum(il_scores) / len(il_scores), 6) if il_scores else 0.0,
            "total_gas": sum(r.gas_used for r in self.history),
        }
