import json
import math
import sys
import time

try:
    import yfinance as yf
    HAS_YFINANCE = True
except ImportError:
    HAS_YFINANCE = False

TICKER = sys.argv[sys.argv.index("--ticker") + 1] if "--ticker" in sys.argv else "SPY"
FAST_MA = int(sys.argv[sys.argv.index("--fast") + 1]) if "--fast" in sys.argv else 50
SLOW_MA = int(sys.argv[sys.argv.index("--slow") + 1]) if "--slow" in sys.argv else 200
INITIAL_CAPITAL = 10000.0


def fetch_prices(ticker=TICKER):
    data = yf.download(ticker, period="1y", interval="1d", progress=False)
    if data.empty:
        raise ValueError(f"No price data for {ticker}")
    close = data["Close"]
    if hasattr(close, "iloc") and close.ndim > 1:
        close = close.iloc[:, 0]
    prices = list(close)
    if len(prices) < 10:
        raise ValueError(f"Too few bars for {ticker} ({len(prices)})")
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
    if not HAS_YFINANCE:
        err = {"status": "error", "error_msg": "yfinance not installed — run: pip install yfinance"}
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
                    capital -= shares * price
                    position = 1
                    signals.append("BUY")
                    num_buys += 1
            elif fast < slow and position == 1 and shares > 0:
                capital += shares * price
                shares = 0
                position = 0
                signals.append("SELL")

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
            "pnl": round(pnl, 2),
            "drawdown": round(max_drawdown, 2),
            "portfolio": round(portfolio_value, 2),
            "price": round(price, 2),
            "fast_ma": round(fast, 2) if fast else None,
            "slow_ma": round(slow, 2) if slow else None,
            "fast_window": FAST_MA,
            "slow_window": SLOW_MA,
            "position": "long" if position == 1 else "flat",
            "status": "running" if i < total_bars else "done",
            "sharpe": round(sharpe, 2) if sharpe is not None else None,
            "trades": num_buys,
        }
        print(json.dumps(data))
        sys.stdout.flush()
        time.sleep(0.03)


if __name__ == "__main__":
    run_backtest()
