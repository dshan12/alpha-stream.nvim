import argparse
import importlib
import json
import math
import os
import sys
import time

try:
    import yfinance as yf
    HAS_YFINANCE = True
except ImportError:
    HAS_YFINANCE = False

INITIAL_CAPITAL = 10000.0


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ticker", default="SPY")
    parser.add_argument("--strategy", default="ma_crossover")
    parser.add_argument("--fast", type=int, default=50)
    parser.add_argument("--slow", type=int, default=200)
    return parser.parse_args()


ARGS = parse_args()
TICKER = ARGS.ticker
STRATEGY_NAME = ARGS.strategy
FAST_MA = ARGS.fast
SLOW_MA = ARGS.slow


def load_strategy(name):
    if name.endswith(".py"):
        name = name[:-3]
    if "/" in name or "\\" in name:
        path = os.path.abspath(name)
        dirname = os.path.dirname(path)
        modname = os.path.splitext(os.path.basename(path))[0]
        sys.path.insert(0, dirname)
        mod = importlib.import_module(modname)
        sys.path.pop(0)
    else:
        mod = importlib.import_module(f"strategies.{name}")
    return mod


def fetch_prices(ticker=TICKER):
    data = yf.download(ticker, period="1y", interval="1d", progress=False)
    if data is None or data.empty:
        raise ValueError(f"No price data for {ticker}")
    close = data.get("Close")
    if close is None:
        raise ValueError(f"No Close column for {ticker}")
    if hasattr(close, "iloc") and close.ndim > 1:
        close = close.iloc[:, 0]
    prices = close.dropna().tolist()
    if len(prices) < 10:
        raise ValueError(f"Too few bars for {ticker} ({len(prices)})")
    return prices


def clean_number(value):
    if value is None or (isinstance(value, float) and (math.isnan(value) or math.isinf(value))):
        return None
    return value


def compute_sharpe(returns, window=20):
    recent = returns[-window:]
    n = len(recent)
    if n < 2:
        return None
    mean_ret = sum(recent) / n
    var = sum((r - mean_ret) ** 2 for r in recent) / (n - 1)
    if var <= 0:
        std = 0.0001
    else:
        std = math.sqrt(var)
    val = (mean_ret / std) * math.sqrt(252)
    return clean_number(val)


def run_backtest():
    if not HAS_YFINANCE:
        err = {"status": "error", "error_msg": "yfinance not installed — run: pip install yfinance"}
        print(json.dumps(err))
        sys.stdout.flush()
        sys.exit(1)

    try:
        strategy = load_strategy(STRATEGY_NAME)
    except Exception as e:
        err = {"status": "error", "error_msg": f"Failed to load strategy '{STRATEGY_NAME}': {e}"}
        print(json.dumps(err))
        sys.stdout.flush()
        sys.exit(1)

    if not hasattr(strategy, "run_bar"):
        err = {"status": "error", "error_msg": f"Strategy '{STRATEGY_NAME}' has no run_bar() function"}
        print(json.dumps(err))
        sys.stdout.flush()
        sys.exit(1)

    try:
        prices = fetch_prices()
    except Exception as e:
        err = {"status": "error", "error_msg": str(e)}
        print(json.dumps(err))
        sys.stdout.flush()
        sys.exit(1)

    total_bars = len(prices)
    position = 0
    capital = INITIAL_CAPITAL
    shares = 0
    peak = INITIAL_CAPITAL
    max_drawdown = 0.0
    prev_portfolio = float(INITIAL_CAPITAL)
    returns = []
    num_buys = 0

    strategy_params = {}
    if hasattr(strategy, "get_params"):
        strategy_params = strategy.get_params()

    for i in range(1, total_bars + 1):
        price = prices[i - 1]

        if math.isnan(price) or math.isinf(price):
            continue

        bar = {
            "price": price,
            "prices": prices,
            "i": i,
            "capital": capital,
            "shares": shares,
            "position": position,
            "fast_window": FAST_MA,
            "slow_window": SLOW_MA,
        }

        try:
            new_capital, new_shares, new_position = strategy.run_bar(bar)
        except Exception as e:
            err = {"status": "error", "error_msg": f"Strategy error at bar {i}: {e}"}
            print(json.dumps(err))
            sys.stdout.flush()
            sys.exit(1)

        if new_position == 1 and position == 0:
            num_buys += 1

        capital, shares, position = new_capital, new_shares, new_position

        portfolio_value = capital + shares * price
        daily_return = (portfolio_value - prev_portfolio) / prev_portfolio if prev_portfolio > 0 else 0.0
        returns.append(daily_return)
        prev_portfolio = portfolio_value

        pnl = portfolio_value - INITIAL_CAPITAL
        peak = max(peak, portfolio_value)
        drawdown = ((portfolio_value - peak) / peak * 100) if peak != 0 else 0.0
        max_drawdown = min(max_drawdown, drawdown)

        sharpe = compute_sharpe(returns)

        data = {
            "progress": i,
            "total": total_bars,
            "pnl": clean_number(round(pnl, 2)),
            "drawdown": clean_number(round(max_drawdown, 2)),
            "portfolio": clean_number(round(portfolio_value, 2)),
            "price": clean_number(round(price, 2)),
            "fast_ma": None,
            "slow_ma": None,
            "fast_window": FAST_MA,
            "slow_window": SLOW_MA,
            "strategy": STRATEGY_NAME,
            "position": "long" if position == 1 else "flat",
            "status": "running" if i < total_bars else "done",
            "sharpe": clean_number(round(sharpe, 2)) if sharpe is not None else None,
            "trades": num_buys,
        }

        for k, v in strategy_params.items():
            if isinstance(v, (int, float)):
                data[k] = clean_number(v)

        print(json.dumps(data))
        sys.stdout.flush()
        time.sleep(0.03)


if __name__ == "__main__":
    run_backtest()
