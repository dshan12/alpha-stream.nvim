# alpha-stream.nvim
### Run backtests without leaving Neovim.

![Neovim 0.10+](https://img.shields.io/badge/neovim-0.10%2B-green?style=flat-square&logo=neovim)
![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-blue?style=flat-square&logo=python)
![License: MIT](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)

![demo](https://github.com/dshan12/alpha-stream.nvim/blob/master/demo.gif)

Every time I wanted to test a trading idea, I had to leave my editor, run a Python script, wait for it to finish, switch back to Neovim, look at the numbers, make a change, and repeat. That got old fast.

So I built a dashboard that runs inside Neovim. Type `:AlphaStreamRun SPY`, and a floating window pops up with PnL, drawdown, Sharpe, and position updating in real time, like a Bloomberg terminal in your editor.

Under the hood it's just a Python process and a Lua callback. Nothing fancy. Change the strategy file, press `r`, and the engine restarts in place. The window stays open, the numbers keep streaming.

---

### Commands

| What | How |
|------|-----|
| Run default | `:AlphaStreamRun` |
| Pick a ticker | `:AlphaStreamRun AAPL` |
| Pick a strategy | `:AlphaStreamRun SPY mean_reversion` |
| Custom MAs | `:AlphaStreamRun AAPL ma_crossover 20 100` |
| Results log | `:AlphaStreamLog` |
| Open strategy | `:AlphaStreamEdit` |

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

```vim
" vim-plug
Plug 'dshan12/alpha-stream.nvim'
```

```bash
# One-time setup
cd alpha-stream.nvim
python3 -m venv .venv
.venv/bin/pip install yfinance
```

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
4. **Compare results**: `:AlphaStreamLog` (opens quickfix with all runs)
5. **Write your own**: create `./strategies/my_strat.py`, then `:AlphaStreamRun SPY ./strategies/my_strat.py 50 200`
6. **Iterate**: edit the `.py` file, press `r` in the dashboard, no Neovim restart needed

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
# ./strategies/momentum.py
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

**Return** `(capital, shares, position)`. The engine handles trade counting and portfolio math.

Use it with an absolute path:

```vim
:AlphaStreamRun SPY ./strategies/momentum.py
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

## What I learned building this

I built this to figure out how Neovim's async process API works, specifically how to stream data from a child process without blocking the UI. The trick was `vim.fn.jobstart()` with `stdout_buffered=false` and routing every update through `vim.schedule()`. Miss that and the editor freezes.

The Python side was straightforward. The Lua side had a few sharp edges:
- `vim.json.decode` returns `vim.NIL` (userdata) for JSON null (truthiness checks won't catch it)
- Window doesn't exist in headless mode (guard every `nvim_list_uis()` call)
- `vim.system()` looks like the right tool but its `SystemObj` has no streaming API (`jobstart` with `on_stdout` is the way to go)

These are all documented in `AGENTS.md` so I don't trip over them again.

---

## License

MIT
