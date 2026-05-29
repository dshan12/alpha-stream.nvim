# AGENTS.md

## Project Status

Implemented Neovim plugin (alpha-stream.nvim) — live-streaming financial backtest dashboard.

## Tech Stack

- **Lua** — Neovim plugin frontend (floating UI via `nvim_open_win`, extmarks for color)
- **Python** — Backtest engine (yfinance or synthetic, JSON lines to stdout)
- **Required**: Neovim 0.10+, Python 3.10+

## Directory Structure

```
plugin/alpha-stream.lua       # Registers :AlphaStreamRun [ticker] and :AlphaStreamStop
lua/alpha-stream/init.lua     # Entry point, wires job → UI
lua/alpha-stream/ui.lua       # Floating window (ASCII header, sparkline, extmarks)
lua/alpha-stream/job.lua      # Spawns Python via vim.fn.jobstart() with on_stdout
python/engine.py              # 50/200 MA crossover, yfinance or synthetic fallback
python/requirements.txt       # yfinance (optional)
.venv/                        # Python venv (not committed)
BLOG.md                       # Architecture blog post for dev.to
demo.tape                     # VHS v0.11.0 demo recording script
```

## Critical Gotchas (learned the hard way)

### Job spawning — use `vim.fn.jobstart()`, NOT `vim.system()`

`vim.system()` in Neovim 0.10 does NOT support `stdout_read()` for streaming. The returned `SystemObj` only has `wait`, `kill`, `write`, `is_closing`. Use `vim.fn.jobstart()` with `on_stdout` callback and `stdout_buffered = false` instead.

`vim.uv.spawn()` also has issues — the event loop doesn't process uv handles properly when called from `-c` context in headless mode.

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

# Normal test
nvim -c 'set rtp^=/path/to/alpha-stream.nvim' +AlphaStreamRun

# VHS demo recording
vhs demo.tape
```

### .venv auto-detection

`job.lua` auto-detects `.venv/bin/python3` relative to the plugin root. Falls back to `python3` if not found.

## Architecture Notes

- Python prints JSON lines to stdout (`sys.stdout.flush()` after each)
- Lua spawns via `vim.fn.jobstart()` with `on_stdout` callback, parses with `vim.json.decode()`
- UI updates wrapped in `vim.schedule()` (Neovim is single-threaded)
- Commands: `:AlphaStreamRun [TICKER]`, `:AlphaStreamStop`
- Keymaps in floating window: `q`/`<Esc>` close, `r` restart
- `vim.api.nvim_list_uis()[1]` can return nil in headless mode — always guard
