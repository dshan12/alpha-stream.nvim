def get_params():
    return {"fast_window": 50, "slow_window": 200}


def run_bar(bar):
    price = bar["price"]
    prices = bar["prices"]
    i = bar["i"]
    capital = bar["capital"]
    shares = bar["shares"]
    position = bar["position"]
    fast_ma = bar["fast_window"]
    slow_ma = bar["slow_window"]

    fast = compute_ma(prices[:i], fast_ma)
    slow = compute_ma(prices[:i], slow_ma)

    if fast is not None and slow is not None:
        if fast > slow and position == 0:
            shares = int(capital / price)
            if shares > 0:
                capital -= shares * price
                position = 1
        elif fast < slow and position == 1 and shares > 0:
            capital += shares * price
            shares = 0
            position = 0

    return capital, shares, position


def compute_ma(prices, window):
    if window <= 0 or len(prices) < window:
        return None
    return sum(prices[-window:]) / window
