import argparse
import importlib.util
import inspect
import json
import math
import os
import sys
import time
import warnings

warnings.filterwarnings("ignore")

try:
    import pandas as pd
    import yfinance as yf
    from backtesting import Backtest, Strategy
    HAS_DEPS = True
except ImportError as e:
    HAS_DEPS = False
    _IMPORT_ERROR = str(e)

INITIAL_CAPITAL = 10000.0
STREAM_DELAY = 0.03


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ticker", default="SPY")
    parser.add_argument("--strategy-file", default=None,
                        help="Path to a .py file defining a backtesting.Strategy subclass")
    parser.add_argument("--strategy", default=None,
                        help="Built-in strategy name (e.g. sma_cross, mean_reversion) or path to .py file")
    parser.add_argument("--cash", type=float, default=10000.0)
    parser.add_argument("--commission", type=float, default=0.0)
    return parser.parse_args()


def emit(obj):
    obj.pop("_internal", None)
    print(json.dumps(obj))
    sys.stdout.flush()


def clean(value):
    if value is None:
        return None
    if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
        return None
    if hasattr(value, "item"):
        try:
            value = value.item()
            if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
                return None
        except (ValueError, AttributeError):
            pass
    return value


def resolve_strategy_file(args, plugin_root):
    if args.strategy_file:
        path = os.path.abspath(os.path.expanduser(args.strategy_file))
        if not os.path.isfile(path):
            raise FileNotFoundError(f"Strategy file not found: {path}")
        return path

    if args.strategy:
        s = args.strategy
        if s.endswith(".py") or "/" in s or "\\" in s:
            path = os.path.abspath(os.path.expanduser(s))
            if not os.path.isfile(path):
                raise FileNotFoundError(f"Strategy file not found: {path}")
            return path
        candidate = os.path.join(plugin_root, "python", "strategies", s + ".py")
        if not os.path.isfile(candidate):
            raise FileNotFoundError(f"Built-in strategy not found: {s}")
        return candidate

    return os.path.join(plugin_root, "python", "strategies", "sma_cross.py")


def load_strategy_class(path):
    spec = importlib.util.spec_from_file_location("user_strategy", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load Python file: {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    strategy_class = None
    for _, obj in inspect.getmembers(mod, inspect.isclass):
        if obj is Strategy:
            continue
        if not issubclass(obj, Strategy):
            continue
        if obj.__module__ != "user_strategy":
            continue
        if strategy_class is not None:
            raise ValueError(
                f"Multiple Strategy subclasses in {path}: {strategy_class.__name__} and {obj.__name__}"
            )
        strategy_class = obj

    if strategy_class is None:
        raise ValueError(
            f"No backtesting.Strategy subclass found in {path}. "
            "Define `class MyStrategy(Strategy):` and try again."
        )
    return strategy_class


def fetch_data(ticker):
    data = yf.download(ticker, period="1y", interval="1d", progress=False)
    if data is None or data.empty:
        raise ValueError(f"No price data for {ticker}")
    if isinstance(data.columns, pd.MultiIndex):
        data.columns = data.columns.get_level_values(0)
    data = data.dropna()
    if len(data) < 30:
        raise ValueError(f"Too few bars for {ticker} ({len(data)})")
    return data


def detect_param_attrs(strategy_class):
    skip = {"__init__", "init", "next", "I", "buy", "sell", "position",
            "data", "orders", "closed_trades", "equity", "trades"}
    params = {}
    for name, value in inspect.getmembers(strategy_class):
        if name.startswith("_") or name in skip:
            continue
        if callable(value):
            continue
        if isinstance(value, (int, float, str, bool)):
            params[name] = value
    return params


def is_position_open(trades_df, bar_idx):
    if trades_df is None or trades_df.empty:
        return False
    for _, trade in trades_df.iterrows():
        if int(trade["EntryBar"]) <= bar_idx and bar_idx < int(trade["ExitBar"]):
            return True
    return False


def run_backtest():
    if not HAS_DEPS:
        emit({
            "status": "error",
            "error_msg": f"Missing dependencies: {_IMPORT_ERROR}. Run: pip install yfinance backtesting",
            "ticker": "",
        })
        sys.exit(1)

    args = parse_args()
    plugin_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    try:
        strategy_path = resolve_strategy_file(args, plugin_root)
    except FileNotFoundError as e:
        emit({"status": "error", "error_msg": str(e), "ticker": args.ticker})
        sys.exit(1)

    try:
        strategy_class = load_strategy_class(strategy_path)
    except Exception as e:
        emit({"status": "error", "error_msg": f"Failed to load strategy: {e}", "ticker": args.ticker})
        sys.exit(1)

    try:
        data = fetch_data(args.ticker)
    except Exception as e:
        emit({"status": "error", "error_msg": str(e), "ticker": args.ticker})
        sys.exit(1)

    try:
        bt = Backtest(data, strategy_class, cash=args.cash, commission=args.commission, finalize_trades=True)
        stats = bt.run()
    except Exception as e:
        emit({"status": "error", "error_msg": f"Backtest failed: {e}", "ticker": args.ticker})
        sys.exit(1)

    equity = stats["_equity_curve"]
    trades = stats.get("_trades", pd.DataFrame())
    total_bars = len(equity)
    param_attrs = detect_param_attrs(strategy_class)
    close = data["Close"].reset_index(drop=True)

    starting = {
        "status": "starting",
        "progress": 0,
        "total": total_bars,
        "pnl": 0.0,
        "drawdown": 0.0,
        "portfolio": float(args.cash),
        "price": float(close.iloc[0]) if total_bars else 0.0,
        "position": "flat",
        "trades": 0,
        "ticker": args.ticker,
        "strategy": strategy_class.__name__,
        "strategy_file": strategy_path,
    }
    for k, v in param_attrs.items():
        starting[k] = clean(v)
    emit(starting)
    time.sleep(STREAM_DELAY)

    trade_count = 0
    max_dd = 0.0
    peak = float(args.cash)

    for i in range(total_bars):
        eq_row = equity.iloc[i]
        equity_val = clean(eq_row["Equity"])
        if equity_val is None:
            continue
        equity_val = float(equity_val)
        price_val = clean(close.iloc[i]) or 0.0
        pnl = equity_val - float(args.cash)
        dd = clean(eq_row.get("DrawdownPct", 0.0)) or 0.0
        dd_pct = float(dd) * 100.0
        if dd_pct < max_dd:
            max_dd = dd_pct
        peak = max(peak, equity_val)
        trade_count = int((trades["EntryBar"] <= i).sum()) if trades is not None and not trades.empty else 0
        position = "long" if is_position_open(trades, i) else "flat"

        event = {
            "status": "running" if i < total_bars - 1 else "done",
            "progress": i + 1,
            "total": total_bars,
            "pnl": clean(round(pnl, 2)),
            "drawdown": clean(round(max_dd, 2)),
            "portfolio": clean(round(equity_val, 2)),
            "price": clean(round(price_val, 2)),
            "position": position,
            "trades": trade_count,
            "ticker": args.ticker,
            "strategy": strategy_class.__name__,
            "strategy_file": strategy_path,
        }
        for k, v in param_attrs.items():
            event[k] = clean(v)

        if event["status"] == "done":
            sharpe = clean(stats.get("Sharpe Ratio"))
            if sharpe is not None:
                event["sharpe"] = clean(round(float(sharpe), 2))
            else:
                event["sharpe"] = None
            event["return_pct"] = clean(round(float(stats.get("Return [%]", 0.0) or 0.0), 2))
            event["buy_hold_pct"] = clean(round(float(stats.get("Buy & Hold Return [%]", 0.0) or 0.0), 2))
            event["equity_final"] = clean(round(float(stats.get("Equity Final [$]", equity_val)), 2))
            event["trades"] = int(stats.get("# Trades", trade_count) or trade_count)
            event["win_rate"] = clean(round(float(stats.get("Win Rate [%]", 0.0) or 0.0), 2))
            event["drawdown"] = clean(round(float(stats.get("Max. Drawdown [%]", max_dd) or max_dd), 2))

        emit(event)
        time.sleep(STREAM_DELAY)


if __name__ == "__main__":
    run_backtest()
