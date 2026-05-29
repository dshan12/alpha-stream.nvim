# alpha-stream.nvim

> Watch your backtest stream live **inside Neovim**. No bloated GUI. No alt-tabbing.

![Neovim 0.10+](https://img.shields.io/badge/neovim-0.10%2B-green?style=flat-square&logo=neovim)
![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-blue?style=flat-square&logo=python)
![License: MIT](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)
![built with ❤️](https://img.shields.io/badge/built%20with-%E2%9D%A4%EF%B8%8F-red?style=flat-square)

![demo](https://raw.githubusercontent.com/dshan12/alpha-stream.nvim/main/demo.gif)

A live-streaming financial backtest dashboard that runs entirely inside Neovim. The Python engine streams JSON to stdout; Lua parses it asynchronously and paints a real-time floating window with colored extmarks — all without leaving your editor.

---

## Features

- **📈 Real-time streaming** — PnL, drawdown, portfolio value, and position update every tick
- **📊 MA Crossover Strategy** — configurable fast/slow windows, defaults to 50/200
- **🔁 Multiple tickers** — pass any symbol that yfinance supports
- **⚡ Edit & restart** — swap strategies or write your own, press `r` to reload
- **📋 Results log** — every run is saved; view with `:AlphaStreamLog`
- **🎨 Colored extmarks** — green profits, red losses, highlighted positions
- **🎯 Progress bar** — know exactly how far the backtest has come

---

## Install

```lua
-- lazy.nvim
{
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

---

## Quick Start

```vim
:AlphaStreamRun
```

A floating window opens, the Python engine fires up, and you watch your backtest stream live. Press `q` to close.

### Setup

The plugin auto-detects `.venv/bin/python3` in its root directory. Set it up:

```bash
cd alpha-stream.nvim
python3 -m venv .venv
.venv/bin/pip install yfinance
```

### Commands

| Command | Description |
|---------|-------------|
| `:AlphaStreamRun` | SPY, ma_crossover, MA(50,200) |
| `:AlphaStreamRun AAPL` | Apple, ma_crossover |
| `:AlphaStreamRun SPY mean_reversion` | SPY, mean reversion strategy |
| `:AlphaStreamRun AAPL ma_crossover 20 100` | Apple, MA crossover with custom windows |
| `:AlphaStreamLog` | Open quickfix list with all past results |
| `:AlphaStreamEdit` | Open strategy file for editing |
| `:AlphaStreamStop` | Stop the current backtest |

### In the dashboard

| Key | Action |
|-----|--------|
| `q` / `<Esc>` | Close the dashboard |
| `r` | Restart with the same parameters |

---

## Workflow: Rapid Strategy Iteration

1. **Run a baseline**: `:AlphaStreamRun SPY ma_crossover 50 200`
2. **Try a different strategy**: `:AlphaStreamRun SPY mean_reversion`
3. **Tweak parameters**: `:AlphaStreamRun SPY mean_reversion 20 100`
4. **Compare results**: `:AlphaStreamLog` — opens quickfix with all runs
5. **Write your own**: create `~/strategies/my_strat.py`, then `:AlphaStreamRun SPY ~/strategies/my_strat.py 50 200`
6. **Iterate**: edit the `.py` file, press `r` in the dashboard — no Neovim restart needed

Each run is saved to `~/.local/share/nvim/alpha-stream/results.jsonl` with timestamp, ticker, params, and final metrics.

---

## Strategies

### Built-in

| Name | Description | File |
|------|-------------|------|
| `ma_crossover` | Buy when fast MA crosses above slow MA, sell when it crosses below | `python/strategies/ma_crossover.py` |
| `mean_reversion` | Buy when price dips 2% below 20-bar mean, sell when it bounces 2% above | `python/strategies/mean_reversion.py` |

```vim
:AlphaStreamRun SPY ma_crossover 50 200    " MA crossover (default)
:AlphaStreamRun SPY mean_reversion         " Mean reversion
```

### Custom strategies

A strategy is a Python file with a `run_bar(bar)` function:

```python
# ~/my_strategies/momentum.py
def run_bar(bar):
    price = bar["price"]
    prices = bar["prices"]
    i = bar["i"]
    capital = bar["capital"]
    shares = bar["shares"]
    position = bar["position"]

    # Your logic here
    return capital, shares, position
```

The `bar` dict has everything you need:

| Key | Type | Description |
|-----|------|-------------|
| `price` | float | Current bar's close |
| `prices` | list | All price history |
| `i` | int | Current bar index (1-based) |
| `capital` | float | Cash available |
| `shares` | int | Shares held |
| `position` | int | 0 = flat, 1 = long |

**Return** `(capital, shares, position)` — the engine handles trade counting and portfolio math.

Use it with an absolute path:

```vim
:AlphaStreamRun SPY ~/my_strategies/momentum.py
```

Strategies can also export `get_params()` returning a dict of config values
to display in the dashboard. See the built-in strategies for examples.

---

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│  Python engine (python/engine.py)                       │
│  ┌────────────┐   ┌──────────────┐   ┌───────────────┐ │
│  │ DataFetcher │──▶│ Strategy     │──▶│ Portfolio     │ │
│  │ (yfinance)  │   │ (MA cross)   │   │ (PnL, DD,    │ │
│  │             │   │              │   │  equity)      │ │
│  └────────────┘   └──────────────┘   └───────┬───────┘ │
│                                              │          │
│                    prints JSON lines to stdout           │
└──────────────────────────────────┬──────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────┐
│  Lua job handler (lua/alpha-stream/job.lua)            │
│  • vim.fn.jobstart() spawns Python                     │
│  • on_stdout callback fires per-chunk                  │
│  • vim.json.decode() each JSON object                  │
│  • vim.schedule() → UI update (thread-safe)            │
└──────────────────────────────────┬──────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────┐
│  Floating window (lua/alpha-stream/ui.lua)             │
│  • nvim_open_win() with relative='editor'              │
│  • nvim_buf_add_highlight() for colored labels         │
│  • PnL, MA values, progress bar                        │
└─────────────────────────────────────────────────────────┘
```

---

## Requirements

| Tool      | Version | Notes                          |
|-----------|---------|--------------------------------|
| Neovim    | ≥ 0.10  | `vim.fn.jobstart()` requirement|
| Python    | ≥ 3.10  |                                |
| `yfinance`| any     | install via `.venv/bin/pip`    |

---

## College Application Portfolio

**alpha-stream.nvim** isn't just a plugin — it's a demonstration of genuine CS depth:

- **Systems Programming** — Spawning and managing a child process from within an editor extension, handling pipe I/O.
- **Async Architecture** — Designing a multi-process, callback-driven pipeline where a Python engine and a Lua UI communicate over a unidirectional stream without shared memory.
- **Real-Time Data Processing** — Buffering, parsing, and rendering a stream of structured data at interactive framerates.
- **Neovim Internals** — Using `vim.fn.jobstart()`, `vim.schedule()`, floating windows, extmarks — the full breadth of the Neovim 0.10+ API.
- **Resilience** — Clean error handling when Python crashes, graceful shutdown path, and a results log that persists across sessions.

Built for speed, demonstrated in a modal editor, documented like production software.

---

## License

MIT
