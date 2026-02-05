"""Range optimization using oracle prices and volatility."""

import math


# Uniswap v4 tick spacing constants
TICK_SPACING_MAP = {500: 10, 3000: 60, 10000: 200}


def price_to_tick(price: float) -> int:
    """Convert a price to the nearest Uniswap tick."""
    if price <= 0:
        raise ValueError("Price must be positive")
    return int(math.floor(math.log(price) / math.log(1.0001)))


def tick_to_price(tick: int) -> float:
    """Convert a tick to a price."""
    return 1.0001**tick


def round_tick(tick: int, tick_spacing: int) -> int:
    """Round a tick to the nearest valid tick (multiple of tick_spacing)."""
    return (tick // tick_spacing) * tick_spacing


def calculate_historical_volatility(prices: list[float]) -> float:
    """Calculate annualized historical volatility from a price series.

    Uses log returns and annualizes assuming hourly data (8760 hours/year).
    """
    if len(prices) < 2:
        return 0.0

    log_returns = []
    for i in range(1, len(prices)):
        if prices[i] > 0 and prices[i - 1] > 0:
            log_returns.append(math.log(prices[i] / prices[i - 1]))

    if not log_returns:
        return 0.0

    n = len(log_returns)
    mean = sum(log_returns) / n
    variance = sum((r - mean) ** 2 for r in log_returns) / (n - 1) if n > 1 else 0.0

    # Annualize (hourly data)
    hourly_vol = math.sqrt(variance)
    annual_vol = hourly_vol * math.sqrt(8760)
    return annual_vol


def compute_optimal_range(
    current_price: float,
    volatility: float,
    k_multiplier: float = 2.0,
    tick_spacing: int = 60,
) -> tuple[int, int]:
    """Compute optimal tick range based on current price and volatility.

    The range is centered around the current price, extended by k * volatility
    on each side.

    Args:
        current_price: Current pool price
        volatility: Annualized volatility (as decimal, e.g. 0.082 for 8.2%)
        k_multiplier: How many standard deviations to cover
        tick_spacing: Pool tick spacing

    Returns:
        (tick_lower, tick_upper) rounded to tick_spacing
    """
    if volatility <= 0:
        volatility = 0.01  # minimum 1%

    center_tick = price_to_tick(current_price)

    # Convert annual vol to tick range
    # price_lower = price * exp(-k * vol), price_upper = price * exp(k * vol)
    price_lower = current_price * math.exp(-k_multiplier * volatility)
    price_upper = current_price * math.exp(k_multiplier * volatility)

    tick_lower = round_tick(price_to_tick(price_lower), tick_spacing)
    tick_upper = round_tick(price_to_tick(price_upper), tick_spacing) + tick_spacing

    # Ensure valid range
    if tick_lower >= tick_upper:
        tick_upper = tick_lower + tick_spacing

    return tick_lower, tick_upper
