# AGENTS.md

## Project Status

This is a **Neovim plugin** (alpha-stream.nvim) that has not been implemented yet. The only file is `info.txt` (a 7-phase build plan). There is no source code, no config, and no tests yet.

## Planned Tech Stack

- **Lua** — Neovim plugin frontend (floating UI, async bridge)
- **Python** — Backend financial data engine (streaming JSON over stdout)
- **Required versions**: Neovim 0.10+, Python 3.10+

## Planned Directory Structure

```
plugin/alpha-stream.lua       # Registers :AlphaStreamRun command
lua/alpha-stream/init.lua     # Main entry point (require('alpha-stream'))
lua/alpha-stream/ui.lua       # Floating window logic
lua/alpha-stream/job.lua      # Async Python spawner
python/engine.py              # Backend engine (streams JSON to stdout)
python/requirements.txt
```

## Key Architecture Notes

- Python backend prints JSON lines to stdout, flushed per line.
- Lua side spawns Python via `vim.system()` (0.10+) or `vim.uv.spawn()`, captures stdout, parses with `vim.json.decode()`.
- UI updates must be wrapped in `vim.schedule()` since Neovim UI is single-threaded.
- User command: `:AlphaStreamRun` → calls `require('alpha-stream').start()`.

## Conventions

- Follow the standard Neovim plugin layout (`plugin/`, `lua/<plugin-name>/`).
- Reference: `info.txt` for the full phased build plan.
