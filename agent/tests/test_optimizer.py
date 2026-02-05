"""Tests for range optimizer."""

import math

from src.optimizer import (
    price_to_tick,
    tick_to_price,
    round_tick,
    calculate_historical_volatility,
    compute_optimal_range,
)


def test_price_to_tick_and_back():
    """Price -> tick -> price roundtrip is approximately correct."""
    price = 2450.0
    tick = price_to_tick(price)
    recovered = tick_to_price(tick)
    assert abs(recovered - price) / price < 0.001  # within 0.1%


def test_round_tick():
    """Ticks are rounded to nearest multiple of spacing."""
    assert round_tick(100, 60) == 60
    assert round_tick(119, 60) == 60
    assert round_tick(120, 60) == 120
    assert round_tick(-100, 60) == -120
    assert round_tick(0, 60) == 0


def test_historical_volatility_constant_price():
    """Constant prices have zero volatility."""
    prices = [100.0] * 24
    vol = calculate_historical_volatility(prices)
    assert vol == 0.0


def test_historical_volatility_known_series():
    """Volatility of a known series is reasonable."""
    # Generate a price series with ~8% annual volatility
    # Hourly returns with ~0.085% hourly vol
    import random

    random.seed(42)
    prices = [2450.0]
    hourly_vol = 0.08 / math.sqrt(8760)
    for _ in range(200):
        ret = random.gauss(0, hourly_vol)
        prices.append(prices[-1] * math.exp(ret))

    vol = calculate_historical_volatility(prices)
    # Should be roughly 8% (within reasonable bounds given randomness)
    assert 0.03 < vol < 0.20


def test_compute_optimal_range_basic():
    """Given price=2450, vol=8.2%, verify range output."""
    tick_lower, tick_upper = compute_optimal_range(
        current_price=2450.0,
        volatility=0.082,
        k_multiplier=2.0,
        tick_spacing=60,
    )

    # Verify range is centered around current price
    center_tick = price_to_tick(2450.0)
    assert tick_lower < center_tick < tick_upper

    # Verify ticks are multiples of spacing
    assert tick_lower % 60 == 0
    assert tick_upper % 60 == 0

    # Verify range is reasonable (not too wide, not too narrow)
    price_lower = tick_to_price(tick_lower)
    price_upper = tick_to_price(tick_upper)
    assert price_lower < 2450.0 < price_upper
    assert price_lower > 2000.0  # not unreasonably wide
    assert price_upper < 3000.0


def test_compute_optimal_range_high_volatility():
    """Higher volatility produces wider range."""
    low_vol = compute_optimal_range(2450.0, 0.05, 2.0, 60)
    high_vol = compute_optimal_range(2450.0, 0.20, 2.0, 60)

    low_width = low_vol[1] - low_vol[0]
    high_width = high_vol[1] - high_vol[0]
    assert high_width > low_width


def test_compute_optimal_range_higher_k():
    """Higher k multiplier produces wider range."""
    narrow = compute_optimal_range(2450.0, 0.08, 1.0, 60)
    wide = compute_optimal_range(2450.0, 0.08, 3.0, 60)

    narrow_width = narrow[1] - narrow[0]
    wide_width = wide[1] - wide[0]
    assert wide_width > narrow_width


def test_compute_optimal_range_zero_vol_uses_minimum():
    """Zero volatility uses minimum 1% volatility."""
    tick_lower, tick_upper = compute_optimal_range(100.0, 0.0, 2.0, 60)
    assert tick_lower < tick_upper
