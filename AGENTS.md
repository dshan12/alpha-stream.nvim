# AGENTS.md

## Project Status

Implemented Neovim plugin (alpha-stream.nvim): live-streaming financial backtest dashboard.

## Tech Stack

- **Lua**: Neovim plugin frontend (floating UI via `nvim_open_win`, extmarks for color)
- **Python**: Backtest engine (uses [backtesting.py](https://github.com/kernc/backtesting.py), JSON lines to stdout)
- **Required**: Neovim 0.10+, Python 3.10+, yfinance, backtesting

## Directory Structure

```
plugin/alpha-stream.lua       # Registers :AlphaStreamRun / :AlphaStreamSweep / :AlphaStreamCompare [ticker] [strategy]
lua/alpha-stream/init.lua     # Entry point, wires job → UI for single mode
lua/alpha-stream/ui.lua       # Floating window (dashboard, keymaps, extmarks) for single mode
lua/alpha-stream/sweep.lua    # Floating window for parameter sweep mode
lua/alpha-stream/compare.lua  # Floating window for strategy comparison mode
lua/alpha-stream/job.lua      # Spawns Python via vim.fn.jobstart() with on_stdout
python/engine.py              # Loads .py strategy, runs backtesting.Backtest, streams equity curve
python/strategies/sma_cross.py       # Built-in: MA crossover
python/strategies/mean_reversion.py  # Built-in: mean reversion
python/strategies/rsi_reversal.py    # Built-in: RSI oversold/overbought
python/requirements.txt       # yfinance, pandas, backtesting
.venv/                        # Python venv (not committed)
BLOG.md                       # Architecture blog post for dev.to
demo.tape                     # VHS v0.11.0 demo recording script
```

## Critical Gotchas (learned the hard way)

### Job spawning: use `vim.fn.jobstart()`, NOT `vim.system()`

`vim.system()` in Neovim 0.10 does NOT support `stdout_read()` for streaming. The returned `SystemObj` only has `wait`, `kill`, `write`, `is_closing`. Use `vim.fn.jobstart()` with `on_stdout` callback and `stdout_buffered = false` instead.

`vim.uv.spawn()` also has issues: the event loop doesn't process uv handles properly when called from `-c` context in headless mode.

### `pcall(module.fn, module, ...)` shifts args

`pcall(job.spawn, job, ...)` passes the `job` table as the first positional arg to `M.spawn()`. Always use a closure: `pcall(function() job.spawn(...) end)`.

### `--cmd` rtp is overridden by lazy.nvim

`--cmd 'set rtp^=path'` runs before plugins load, but lazy.nvim rebuilds rtp during init, wiping your change. Use `-c 'set rtp^=path'` instead.

### Testing

```bash
# Headless test (must use -c, not --cmd)
nvim --headless -c 'set rtp^=/path/to/alpha-stream.nvim' \
  -c 'runtime plugin/alpha-stream.lua' \
  -c 'lua require("alpha-stream").start()'

# Normal test (no -c for rtp; use --cmd or runtime plugin/...)
nvim -c 'set rtp^=.' -c 'runtime plugin/alpha-stream.lua' -c 'AlphaStreamRun'
nvim -c 'set rtp^=.' -c 'runtime plugin/alpha-stream.lua' -c 'AlphaStreamRun AAPL mean_reversion'
nvim -c 'set rtp^=.' -c 'runtime plugin/alpha-stream.lua' -c 'AlphaStreamRun TSLA ./python/strategies/sma_cross.py'

# VHS demo recording
vhs demo.tape
```

### .venv auto-detection

`job.lua` auto-detects `.venv/bin/python3` relative to the plugin root. Falls back to `python3` if not found.

### Auto-restart autocmd uses `fnamemodify(file, ":p")` to normalize paths

Comparing `current_strategy_file` (which may be a relative path like `python/strategies/sma_cross.py`) to `vim.api.nvim_buf_get_name(0)` (which is the absolute path Neovim tracks) requires normalization or they never match. Use `vim.fn.fnamemodify(path, ":p")` on both sides before `==` comparison.

## Architecture

### Python engine (`python/engine.py`)

- Loads user's `.py` via `importlib.util.spec_from_file_location`, finds the `backtesting.Strategy` subclass with `inspect.getmembers`, runs `Backtest(data, cls).run()`, then streams the `_equity_curve` row by row as JSON (one event per bar with 30ms delay for live effect).
- Each per-bar event has: `progress`, `total`, `pnl`, `drawdown`, `portfolio`, `price`, `position`, `trades`, `strategy` (class name), plus any int/float/str/bool class attributes from the strategy.
- Final event has `status: "done"` and adds `sharpe`, `return_pct`, `win_rate`, `equity_final`.
- Three modes: `single` (default), `sweep` (loops `itertools.product` of a param grid, streams per-combo + best), `compare` (runs N strategies sequentially on shared data, streams per-strategy). All three share `summarize_stats()` and `clean()` (NaN/Inf → None).

### Lua side

- Spawns Python via `vim.fn.jobstart()` with `on_stdout` callback, parses with `vim.json.decode()`.
- UI updates wrapped in `vim.schedule()` (Neovim is single-threaded).
- The three UI modules (`ui.lua`/`sweep.lua`/`compare.lua`) own their own buf+win+namespace. Each registers with `vim.api.nvim_create_namespace("alpha-stream-{name}")`, never share namespaces across modules.
- Sweep/compare modules are self-contained: they each call `job.spawn()` directly with their own `--mode`. They do not go through `init.lua`.

### Commands and keymaps

- Commands: `:AlphaStreamRun [TICKER] [STRATEGY-FILE]`, `:AlphaStreamSweep TICKER STRATEGY param=v1,v2 [...]`, `:AlphaStreamCompare TICKER STRAT1 STRAT2 [...]`, `:AlphaStreamStop`, `:AlphaStreamLog`, `:AlphaStreamEdit`.
- Keymaps in floating windows: `s` start, `x` stop, `r` restart, `?` help, `q`/`<Esc>` close.
- `M.run_current_buffer()` is exposed for users to wire up a keybind that uses the current buffer's file path as the strategy file.
- `BufWritePost` autocmd (group `AlphaStreamAutoRestart`) auto-restarts the running backtest when the user saves the current strategy file. Uses 300ms debounce via `vim.defer_fn`. Only fires if a backtest is running and the saved file path matches `current_strategy_file` (path-normalized via `fnamemodify`).

## Strategy file format

Any `.py` file with a `backtesting.Strategy` subclass works. Engine auto-detects the class:

```python
from backtesting import Strategy
import pandas as pd

class MyStrategy(Strategy):
    fast = 50
    slow = 200

    def init(self):
        close = pd.Series(self.data.Close)
        self.ma_fast = self.I(lambda: close.rolling(self.fast).mean())

    def next(self):
        if self.ma_fast[-1] > self.data.Close[-1] and not self.position:
            self.buy()
```

Class attributes that are `int`/`float`/`str`/`bool` are auto-detected and shown next to the strategy name in the dashboard. Use absolute or relative path: `:AlphaStreamRun SPY ./python/strategies/my_strat.py` or `:AlphaStreamRun SPY sma_cross` (built-in name resolved against `python/strategies/`).
