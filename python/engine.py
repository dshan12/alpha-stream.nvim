import json
import math
import random
import sys
import time

try:
    import yfinance as yf
    HAS_YFINANCE = True
except ImportError:
    HAS_YFINANCE = False

TICKER = sys.argv[sys.argv.index("--ticker") + 1] if "--ticker" in sys.argv else "SPY"
FAST_MA = 50
SLOW_MA = 200
INITIAL_CAPITAL = 10000.0


def fetch_prices(ticker=TICKER):
    if not HAS_YFINANCE:
        return generate_synthetic_prices()
    try:
        data = yf.download(ticker, period="1y", interval="1d", progress=False)
        if data.empty:
            return generate_synthetic_prices()
        close = data["Close"]
        if hasattr(close, "droplevel"):
            close = close.droplevel("Ticker", axis=1) if close.columns.nlevels > 1 else close
        prices = close.tolist()
        if len(prices) < 10:
            return generate_synthetic_prices()
        return prices
    except Exception:
        return generate_synthetic_prices()


def generate_synthetic_prices():
    prices = [150.0]
    for _ in range(300):
        change = random.gauss(0.0004, 0.012)
        prices.append(prices[-1] * (1 + change))
    return prices


def compute_ma(prices, window):
    if len(prices) < window:
        return None
    return sum(prices[-window:]) / window


def compute_sharpe(returns, window=20):
    recent = returns[-window:]
    n = len(recent)
    if n < 2:
        return None
    mean_ret = sum(recent) / n
    var = sum((r - mean_ret) ** 2 for r in recent) / (n - 1)
    std = math.sqrt(var) if var > 0 else 0.0001
    return (mean_ret / std) * math.sqrt(252)


def run_backtest():
    prices = fetch_prices()
    total_bars = len(prices)

    position = 0
    capital = INITIAL_CAPITAL
    shares = 0
    entry_price = 0.0
    peak = INITIAL_CAPITAL
    prev_portfolio = float(INITIAL_CAPITAL)
    returns = []
    signals = []
    num_buys = 0

    for i in range(1, total_bars + 1):
        price = prices[i - 1]

        fast = compute_ma(prices[:i], FAST_MA)
        slow = compute_ma(prices[:i], SLOW_MA)

        if fast is not None and slow is not None:
            if fast > slow and position == 0:
                shares = int(capital / price)
                if shares > 0:
                    entry_price = price
                    capital -= shares * price
                    position = 1
                    signals.append("BUY")
                    num_buys += 1
            elif fast < slow and position == 1 and shares > 0:
                capital += shares * price
                shares = 0
                position = 0
                entry_price = 0.0
                signals.append("SELL")

        portfolio_value = capital + shares * price
        daily_return = (portfolio_value - prev_portfolio) / prev_portfolio if prev_portfolio > 0 else 0.0
        returns.append(daily_return)
        prev_portfolio = portfolio_value

        pnl = portfolio_value - INITIAL_CAPITAL
        peak = max(peak, portfolio_value)
        drawdown = ((portfolio_value - peak) / peak * 100) if peak != 0 else 0.0

        sharpe = compute_sharpe(returns)

        status = "running" if i < total_bars else "done"
        data = {
            "progress": i,
            "total": total_bars,
            "pnl": round(pnl, 2),
            "drawdown": round(drawdown, 2),
            "portfolio": round(portfolio_value, 2),
            "price": round(price, 2),
            "fast_ma": round(fast, 2) if fast else None,
            "slow_ma": round(slow, 2) if slow else None,
            "position": "long" if position == 1 else "flat",
            "status": status,
            "sharpe": round(sharpe, 2) if sharpe is not None else None,
            "trades": num_buys,
        }
        print(json.dumps(data))
        sys.stdout.flush()
        time.sleep(0.03)

    final_pnl = round(capital + shares * prices[-1] - INITIAL_CAPITAL, 2)
    summary = {
        "progress": total_bars,
        "total": total_bars,
        "pnl": final_pnl,
        "drawdown": round(drawdown, 2),
        "portfolio": round(capital + shares * prices[-1], 2),
        "price": round(prices[-1], 2),
        "fast_ma": None,
        "slow_ma": None,
        "position": "flat",
        "status": "done",
        "sharpe": round(sharpe, 2) if sharpe is not None else None,
        "trades": num_buys,
    }
    print(json.dumps(summary))
    sys.stdout.flush()


if __name__ == "__main__":
    run_backtest()
