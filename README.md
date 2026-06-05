# alpha-stream.nvim
### Run backtests without leaving Neovim.

![Neovim 0.10+](https://img.shields.io/badge/neovim-0.10%2B-green?style=flat-square&logo=neovim)
![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-blue?style=flat-square&logo=python)
![License: MIT](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)

<!--![demo](https://github.com/dshan12/alpha-stream.nvim/blob/master/demo.gif)-->

Every time I wanted to test a trading idea, I had to leave my editor, run a Python script, wait for it to finish, switch back to Neovim, look at the numbers, make a change, and repeat. That got old fast.

So I built a dashboard that runs inside Neovim. Type `:AlphaStreamRun SPY`, and a floating window pops up with PnL, drawdown, Sharpe, and position updating in real time, like a Bloomberg terminal in your editor.

Under the hood it uses [backtesting.py](https://github.com/kernc/backtesting.py) for the actual backtest. You write a strategy the way the library docs show it, drop the file in `python/strategies/`, and Neovim loads it.

---

### Commands

| What | How |
|------|-----|
| Run default | `:AlphaStreamRun` |
| Pick a ticker | `:AlphaStreamRun AAPL` |
| Pick a strategy | `:AlphaStreamRun SPY mean_reversion` |
| Use your own file | `:AlphaStreamRun TSLA ~/code/my_strat.py` |
| Sweep parameters | `:AlphaStreamSweep SPY sma_cross fast=10,20 slow=100,200` |
| Compare strategies | `:AlphaStreamCompare AAPL sma_cross mean_reversion rsi_reversal` |
| Results log | `:AlphaStreamLog` |
| Open strategies | `:AlphaStreamEdit` |

Tab completion works: tickers on the first arg, strategy names on the second.

---

### Install

```lua
-- lazy.nvim
{
  "dshan12/alpha-stream.nvim",
  config = function()
    require("alpha-stream")
  end,
}
```

```lua
-- packer.nvim
use {
  "dshan12/alpha-stream.nvim",
  config = function()
    require("alpha-stream")
  end,
}
```

```vim
" vim-plug
Plug 'dshan12/alpha-stream.nvim'
```

```bash
# One-time setup
cd alpha-stream.nvim
python3 -m venv .venv
.venv/bin/pip install -r python/requirements.txt
```

### Optional keybinds

The plugin doesn't set any global keymaps by default, but you can wire up your own:

```lua
-- Run a backtest on the .py file in your current buffer
vim.keymap.set("n", "<leader>ar", function()
  require("alpha-stream").run_current_buffer()
end, { desc = "alpha-stream: run backtest on current file" })
```

Now editing `momentum.py` and pressing `<leader>ar` runs the backtest on that file with the last-used ticker. No path typing needed.

### In the dashboard

| Key | Action |
|-----|--------|
| `s` | Start backtest |
| `x` | Stop running backtest |
| `r` | Restart with the same parameters |
| `?` | Toggle help overlay |
| `q` / `<Esc>` | Close the dashboard |

---

## Workflow: Rapid Strategy Iteration

1. **Run a baseline**: `:AlphaStreamRun SPY sma_cross`
2. **Try a different strategy**: `:AlphaStreamRun SPY mean_reversion`
3. **Tweak a strategy**: open `python/strategies/sma_cross.py`, change `fast` or `slow`, save
4. **It restarts itself**: saving the .py file auto-reloads the backtest (300ms debounce)
5. **Compare runs**: `:AlphaStreamLog` (opens quickfix with all results)
6. **Write your own**: create `python/strategies/momentum.py`, then `:AlphaStreamRun SPY momentum`

> Save the .py file and the dashboard restarts. No `:r` to press, no Neovim quit. Just edit, save, watch the numbers.

Each run is saved to `~/.local/share/nvim/alpha-stream/results.jsonl` with timestamp, ticker, strategy, and final metrics.

---

## Sweep & Compare

Hand-tuning `fast=50` to `fast=20` and rerunning gets old. The engine has two extra modes that do the grid for you.

### Parameter sweep

`:AlphaStreamSweep` runs every combination in a parameter grid, sorts by Sharpe, and shows the top results in a floating table.

```vim
:AlphaStreamSweep SPY sma_cross fast=10,20,50,100 slow=100,200,300
```

That's 12 backtests, all in one go. The dashboard shows progress, the best combo so far, and a live top-10 table. Press `r` to rerun, `q` to close.

### Strategy comparison

`:AlphaStreamCompare` runs multiple strategies on the same ticker and lays them out side by side.

```vim
:AlphaStreamCompare AAPL sma_cross mean_reversion rsi_reversal
```

The compare view is a table: one row per strategy, columns for Return, Sharpe, Max DD, Win%, Trades, and Final $. The best by Return is highlighted.

Both commands accept the same `TICKER` and strategy names as `:AlphaStreamRun`. Sweep takes one or more `name=v1,v2,v3` params. Compare takes two or more strategy names.

---

## Strategies

### Built-in

| Name | Description |
|------|-------------|
| `sma_cross` | Buy when fast MA crosses above slow MA, sell on the reverse |
| `mean_reversion` | Buy when price dips below 20-bar mean, sell on the bounce |
| `rsi_reversal` | Buy when RSI < 30, sell when RSI > 70 |

### Custom strategies

Any `.py` file with a `backtesting.Strategy` subclass works. The engine imports your file, finds the class, and runs the standard `Backtest(...)` flow.

```python
# python/strategies/momentum.py
from backtesting import Strategy
from backtesting.lib import crossover
import pandas as pd


class Momentum(Strategy):
    lookback = 20

    def init(self):
        close = pd.Series(self.data.Close)
        self.sma = self.I(lambda: close.rolling(self.lookback).mean())

    def next(self):
        if self.data.Close[-1] > self.sma[-1] and not self.position:
            self.buy(size=0.95)
        elif self.data.Close[-1] < self.sma[-1] and self.position:
            self.position.close()
```

Reference: [backtesting.py docs](https://kernc.github.io/backtesting.py/doc/backtesting/index.html)

Tweak the class attrs (`lookback = 20`) in your file, then press `r` to restart. Class attributes that are `int`/`float`/`str`/`bool` are auto-detected and shown next to the strategy name in the dashboard.

### Pointing at any file

The strategy arg accepts a path too. Got a file somewhere outside the plugin? Pass the full path:

```vim
:AlphaStreamRun TSLA ~/code/quant/donchian_breakout.py
:AlphaStreamRun /home/me/experiments/volume_spike.py
```

The engine imports whatever you give it, finds the first class that subclasses `backtesting.Strategy`, and runs it. Everything else is standard backtesting.py: `self.buy()`, `self.position.close()`, `self.I()` for indicators. If you've read the [backtesting.py docs](https://kernc.github.io/backtesting.py/doc/backtesting/index.html) you already know how to write a strategy.

### Quick example: build and test a strategy in 60 seconds

Say you want to test a simple "buy on big up days" rule. Make a file:

```python
# /tmp/big_up_day.py
from backtesting import Strategy


class BigUpDay(Strategy):
    threshold = 0.02

    def init(self):
        pass

    def next(self):
        ret = self.data.Close[-1] / self.data.Close[-2] - 1
        if ret > self.threshold and not self.position:
            self.buy(size=0.5)
```

Run it:

```vim
:AlphaStreamRun SPY /tmp/big_up_day.py
```

The dashboard picks up `threshold=0.02` and shows it next to the strategy name. Want to try `0.03`? Edit the file, press `r` in the dashboard. No Neovim restart, no Python re-import dance. The plugin kills the old engine, spawns a new one, and the dashboard updates.

That's the whole loop. Make it short, make it test in 5 seconds, iterate on what works.

---

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│  Python engine (python/engine.py)                       │
│  • yfinance downloads OHLCV data                        │
│  • Loads your .py file, finds Strategy subclass         │
│  • Runs backtesting.Backtest(data, YourStrategy).run()  │
│  • Three modes: single, sweep, compare                  │
│  • Streams events as JSON lines to stdout               │
└──────────────────────────────────┬──────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────┐
│  Lua job handler (lua/alpha-stream/job.lua)             │
│  • vim.fn.jobstart() spawns Python                     │
│  • on_stdout fires per chunk, decodes each JSON line    │
│  • vim.schedule() → UI update (thread-safe)             │
└──────────────────────────────────┬──────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────┐
│  Floating windows (lua/alpha-stream/{ui,sweep,compare}) │
│  • nvim_open_win() with relative='editor'              │
│  • nvim_buf_add_highlight() for highlights              │
│  • Live progress, dynamic keymap hints in footer        │
└─────────────────────────────────────────────────────────┘
```

---

## Requirements

| Tool      | Version | Notes                          |
|-----------|---------|--------------------------------|
| Neovim    | ≥ 0.10  | `vim.fn.jobstart()` requirement|
| Python    | ≥ 3.10  |                                |
| yfinance  | any     | `pip install yfinance`         |
| backtesting | ≥ 0.6 | `pip install backtesting`    |

---

## What I learned building this

I built this to figure out how Neovim's async process API works, specifically how to stream data from a child process without blocking the UI. The trick was `vim.fn.jobstart()` with `stdout_buffered=false` and routing every update through `vim.schedule()`. Miss that and the editor freezes.

The Python side stays out of the way. The whole point is that `backtesting.py` already does the heavy lifting, which is loading data, running bars, computing stats. The engine just imports your strategy, runs it, and replays the equity curve as JSON.

The Lua side has a few sharp edges:
- `vim.json.decode` returns `vim.NIL` (userdata) for JSON null (truthiness checks won't catch it)
- Window doesn't exist in headless mode (guard every `nvim_list_uis()` call)
- `vim.system()` looks like the right tool but its `SystemObj` has no streaming API (`jobstart` with `on_stdout` is the way to go)


---

## License

MIT
