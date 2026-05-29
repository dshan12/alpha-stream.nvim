def get_params():
    return {"lookback": 20, "entry_z": 0.98, "exit_z": 1.02}


def run_bar(bar):
    price = bar["price"]
    prices = bar["prices"]
    i = bar["i"]
    capital = bar["capital"]
    shares = bar["shares"]
    position = bar["position"]

    lookback = min(i, 20)
    if lookback < 5:
        return capital, shares, position

    mean = sum(prices[i - lookback : i]) / lookback
    entry_thresh = mean * 0.98
    exit_thresh = mean * 1.02

    if price < entry_thresh and position == 0:
        shares = int(capital / price)
        if shares > 0:
            capital -= shares * price
            position = 1
    elif price > exit_thresh and position == 1 and shares > 0:
        capital += shares * price
        shares = 0
        position = 0

    return capital, shares, position
