import argparse
import importlib.util
import inspect
import itertools
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
    parser.add_argument("--mode", default="single", choices=["single", "sweep", "compare"])
    parser.add_argument("--ticker", default="SPY")
    parser.add_argument("--strategy-file", default=None,
                        help="Path to a .py file defining a backtesting.Strategy subclass")
    parser.add_argument("--strategy", default=None,
                        help="Built-in strategy name (e.g. sma_cross, mean_reversion) or path to .py file")
    parser.add_argument("--cash", type=float, default=10000.0)
    parser.add_argument("--commission", type=float, default=0.0)
    parser.add_argument("--param", action="append", default=[],
                        help="For --mode sweep: NAME=v1,v2,v3 (repeatable)")
    parser.add_argument("--strategies", action="append", default=[],
                        help="For --mode compare: strategy name or path (repeatable)")
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


def resolve_strategy_file(name, plugin_root):
    if not name:
        return os.path.join(plugin_root, "python", "strategies", "sma_cross.py")
    if name.endswith(".py") or "/" in name or "\\" in name:
        path = os.path.abspath(os.path.expanduser(name))
        if not os.path.isfile(path):
            raise FileNotFoundError(f"Strategy file not found: {path}")
        return path
    candidate = os.path.join(plugin_root, "python", "strategies", name + ".py")
    if not os.path.isfile(candidate):
        raise FileNotFoundError(f"Built-in strategy not found: {name}")
    return candidate


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


def parse_param_value(s):
    s = s.strip()
    try:
        if "." in s or "e" in s.lower():
            return float(s)
        return int(s)
    except ValueError:
        if s.lower() == "true":
            return True
        if s.lower() == "false":
            return False
        return s.strip("'\"")


def parse_sweep_params(raw):
    grid = {}
    for spec in raw:
        if "=" not in spec:
            raise ValueError(f"--param must be NAME=v1,v2,v3 (got: {spec})")
        key, vals = spec.split("=", 1)
        key = key.strip()
        values = [parse_param_value(v) for v in vals.split(",") if v.strip() != ""]
        if not values:
            raise ValueError(f"--param {key} has no values")
        grid[key] = values
    return grid


def summarize_stats(stats, equity, trades, args):
    final_eq = clean(stats.get("Equity Final [$]"))
    return {
        "return_pct": clean(round(float(stats.get("Return [%]", 0.0) or 0.0), 2)),
        "buy_hold_pct": clean(round(float(stats.get("Buy & Hold Return [%]", 0.0) or 0.0), 2)),
        "sharpe": clean(round(float(stats.get("Sharpe Ratio") or 0.0), 2)) if stats.get("Sharpe Ratio") is not None else None,
        "max_dd": clean(round(float(stats.get("Max. Drawdown [%]", 0.0) or 0.0), 2)),
        "win_rate": clean(round(float(stats.get("Win Rate [%]", 0.0) or 0.0), 2)),
        "trades": int(stats.get("# Trades", 0) or 0),
        "equity_final": clean(round(float(final_eq) if final_eq is not None else float(args.cash), 2)),
        "exposure": clean(round(float(stats.get("Exposure Time [%]", 0.0) or 0.0), 2)),
    }


def run_single(args, data, strategy_class, strategy_path):
    param_attrs = detect_param_attrs(strategy_class)
    bt = Backtest(data, strategy_class, cash=args.cash, commission=args.commission, finalize_trades=True)
    stats = bt.run()
    equity = stats["_equity_curve"]
    trades = stats.get("_trades", pd.DataFrame())
    total_bars = len(equity)
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
            summary = summarize_stats(stats, equity, trades, args)
            event.update(summary)

        emit(event)
        time.sleep(STREAM_DELAY)


def run_sweep(args, data, strategy_class, strategy_path, plugin_root):
    param_attrs = detect_param_attrs(strategy_class)
    grid = parse_sweep_params(args.param)

    invalid = [k for k in grid if k not in param_attrs]
    if invalid:
        raise ValueError(
            f"Unknown parameter(s): {', '.join(invalid)}. "
            f"Strategy {strategy_class.__name__} has: {', '.join(sorted(param_attrs.keys())) or '(none)'}"
        )

    keys = list(grid.keys())
    value_lists = [grid[k] for k in keys]
    combos = list(itertools.product(*value_lists))
    total = len(combos)

    emit({
        "status": "starting",
        "mode": "sweep",
        "ticker": args.ticker,
        "strategy": strategy_class.__name__,
        "strategy_file": strategy_path,
        "params": [f"{k}={','.join(str(v) for v in grid[k])}" for k in keys],
        "total_combos": total,
    })
    time.sleep(STREAM_DELAY)

    bt = Backtest(data, strategy_class, cash=args.cash, commission=args.commission, finalize_trades=True)
    results = []
    for idx, combo in enumerate(combos):
        param_dict = dict(zip(keys, combo))
        try:
            stats = bt.run(**param_dict)
        except Exception as e:
            emit({
                "status": "running",
                "combo_idx": idx + 1,
                "total_combos": total,
                "params": {k: clean(v) for k, v in param_dict.items()},
                "ticker": args.ticker,
                "strategy": strategy_class.__name__,
                "error": f"{type(e).__name__}: {e}",
            })
            results.append({
                "params": {k: clean(v) for k, v in param_dict.items()},
                "error": str(e),
            })
            time.sleep(STREAM_DELAY)
            continue

        summary = summarize_stats(stats, stats["_equity_curve"], stats.get("_trades", pd.DataFrame()), args)
        record = {
            "params": {k: clean(v) for k, v in param_dict.items()},
            **summary,
        }
        results.append(record)

        emit({
            "status": "running",
            "combo_idx": idx + 1,
            "total_combos": total,
            "ticker": args.ticker,
            "strategy": strategy_class.__name__,
            "params": record["params"],
            "return_pct": record["return_pct"],
            "sharpe": record["sharpe"],
            "max_dd": record["max_dd"],
            "win_rate": record["win_rate"],
            "trades": record["trades"],
            "equity_final": record["equity_final"],
        })
        time.sleep(STREAM_DELAY)

    successful = [r for r in results if "error" not in r]
    sort_key = lambda r: (r.get("sharpe") is None, -(r.get("sharpe") or 0.0))
    successful.sort(key=sort_key)
    best = successful[0] if successful else None

    emit({
        "status": "done",
        "mode": "sweep",
        "ticker": args.ticker,
        "strategy": strategy_class.__name__,
        "strategy_file": strategy_path,
        "total_combos": total,
        "completed": len(successful),
        "failed": total - len(successful),
        "results": results,
        "best": best,
    })


def run_compare(args, data, plugin_root):
    if not args.strategies:
        raise ValueError("--strategies is required for --mode compare")

    strategy_specs = []
    for name in args.strategies:
        path = resolve_strategy_file(name, plugin_root)
        cls = load_strategy_class(path)
        strategy_specs.append((name, path, cls))

    emit({
        "status": "starting",
        "mode": "compare",
        "ticker": args.ticker,
        "strategies": [s[0] for s in strategy_specs],
    })
    time.sleep(STREAM_DELAY)

    results = []
    for idx, (name, path, cls) in enumerate(strategy_specs):
        try:
            bt = Backtest(data, cls, cash=args.cash, commission=args.commission, finalize_trades=True)
            stats = bt.run()
            summary = summarize_stats(stats, stats["_equity_curve"], stats.get("_trades", pd.DataFrame()), args)
        except Exception as e:
            emit({
                "status": "running",
                "strategy_idx": idx + 1,
                "total_strategies": len(strategy_specs),
                "strategy": name,
                "ticker": args.ticker,
                "error": f"{type(e).__name__}: {e}",
            })
            results.append({
                "strategy": name,
                "strategy_class": cls.__name__,
                "strategy_file": path,
                "error": str(e),
            })
            time.sleep(STREAM_DELAY)
            continue

        record = {
            "strategy": name,
            "strategy_class": cls.__name__,
            "strategy_file": path,
            **summary,
        }
        results.append(record)
        emit({
            "status": "running",
            "strategy_idx": idx + 1,
            "total_strategies": len(strategy_specs),
            "strategy": name,
            "strategy_class": cls.__name__,
            "ticker": args.ticker,
            "return_pct": record["return_pct"],
            "sharpe": record["sharpe"],
            "max_dd": record["max_dd"],
            "win_rate": record["win_rate"],
            "trades": record["trades"],
            "equity_final": record["equity_final"],
        })
        time.sleep(STREAM_DELAY)

    emit({
        "status": "done",
        "mode": "compare",
        "ticker": args.ticker,
        "results": results,
    })


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
        data = fetch_data(args.ticker)
    except Exception as e:
        emit({"status": "error", "error_msg": str(e), "ticker": args.ticker, "mode": args.mode})
        sys.exit(1)

    try:
        if args.mode == "single":
            strategy_path = resolve_strategy_file(args.strategy_file or args.strategy, plugin_root)
            strategy_class = load_strategy_class(strategy_path)
            run_single(args, data, strategy_class, strategy_path)
        elif args.mode == "sweep":
            strategy_path = resolve_strategy_file(args.strategy_file or args.strategy, plugin_root)
            strategy_class = load_strategy_class(strategy_path)
            run_sweep(args, data, strategy_class, strategy_path, plugin_root)
        elif args.mode == "compare":
            run_compare(args, data, plugin_root)
    except FileNotFoundError as e:
        emit({"status": "error", "error_msg": str(e), "ticker": args.ticker, "mode": args.mode})
        sys.exit(1)
    except Exception as e:
        emit({"status": "error", "error_msg": f"{type(e).__name__}: {e}", "ticker": args.ticker, "mode": args.mode})
        sys.exit(1)


if __name__ == "__main__":
    run_backtest()
