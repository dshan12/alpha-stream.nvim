local ui = require("alpha-stream.ui")
local job = require("alpha-stream.job")

local M = {}
local running = false
local current_ticker = "SPY"
local current_strategy = "ma_crossover"
local current_fast = 50
local current_slow = 200

local function get_plugin_root()
  local src = debug.getinfo(1, "S").source:match("@?(.*/)")
  if src then
    return vim.fn.fnamemodify(src, ":p:h:h:h")
  end
  return vim.fn.stdpath("data") .. "/alpha-stream/"
end

local function save_result(data)
  local dir = vim.fn.stdpath("data") .. "/alpha-stream"
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/results.jsonl"
  local entry = {
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    ticker = current_ticker,
    strategy = current_strategy,
    fast_ma = current_fast,
    slow_ma = current_slow,
    pnl = type(data.pnl) == "number" and data.pnl or 0,
    drawdown = type(data.drawdown) == "number" and data.drawdown or 0,
    sharpe = type(data.sharpe) == "number" and data.sharpe or nil,
    trades = type(data.trades) == "number" and data.trades or 0,
  }
  local line = vim.json.encode(entry) .. "\n"
  local fd = vim.fn.writefile({ line }, path, "a")
  if fd == 0 then
    vim.notify("alpha-stream: results saved to " .. path, vim.log.levels.INFO)
  end
end

ui.set_restart_callback(function()
  M.restart()
end)

function M.start(opts)
  opts = opts or {}
  current_ticker = type(opts.ticker) == "string" and opts.ticker or "SPY"
  current_strategy = type(opts.strategy) == "string" and opts.strategy or "ma_crossover"
  current_fast = type(opts.fast_ma) == "number" and opts.fast_ma or 50
  current_slow = type(opts.slow_ma) == "number" and opts.slow_ma or 200

  if running then
    vim.notify("alpha-stream: already running", vim.log.levels.WARN)
    return
  end

  running = true
  ui.set_ticker(current_ticker)
  ui.set_strategy(current_fast, current_slow, current_strategy)
  ui.open()
  ui.update_dashboard({
    progress = 0,
    pnl = 0,
    drawdown = 0,
    portfolio = 10000,
    price = 0,
    fast_ma = nil,
    slow_ma = nil,
    fast_window = current_fast,
    slow_window = current_slow,
    position = "flat",
    status = "starting",
  })

  local root = get_plugin_root()
  local script = root .. "/python/engine.py"
  local extra_args = { "--ticker", current_ticker, "--strategy", current_strategy, "--fast", tostring(current_fast), "--slow", tostring(current_slow) }

  local ok, err = pcall(function()
    job.spawn(script, function(data)
      if data.status == "error" then
        running = false
        ui.show_error(tostring(data.error_msg or "unknown error"))
        vim.notify("alpha-stream: " .. tostring(data.error_msg or "unknown error"), vim.log.levels.ERROR)
      else
        ui.update_dashboard(data)
        if data.status == "done" then
          save_result(data)
        end
      end
    end, function(result)
      running = false
      local code = result and result.code or -1
      if code ~= 0 then
        ui.show_error("Process exited with code " .. code)
        vim.notify("alpha-stream: process exited with code " .. code, vim.log.levels.ERROR)
      end
    end, extra_args)
  end)

  if not ok then
    running = false
    ui.show_error(tostring(err))
    vim.notify("alpha-stream: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.stop()
  job.stop()
  running = false
  ui.close()
end

function M.restart()
  M.stop()
  vim.defer_fn(function()
    M.start({ ticker = current_ticker, strategy = current_strategy, fast_ma = current_fast, slow_ma = current_slow })
  end, 150)
end

function M.log()
  local path = vim.fn.stdpath("data") .. "/alpha-stream/results.jsonl"
  local ok, fd = pcall(vim.fn.readfile, path)
  if not ok or #fd == 0 then
    vim.notify("alpha-stream: no results yet", vim.log.levels.INFO)
    return
  end
  local qf = {}
  for _, line in ipairs(fd) do
    local ok, entry = pcall(vim.json.decode, line)
    if ok and entry then
      local log_fast = type(entry.fast_ma) == "number" and tostring(entry.fast_ma) or "?"
      local log_slow = type(entry.slow_ma) == "number" and tostring(entry.slow_ma) or "?"
      local log_pnl = type(entry.pnl) == "number" and string.format("%+.2f", entry.pnl) or "?"
      local log_dd = type(entry.drawdown) == "number" and string.format("%.2f", entry.drawdown) or "?"
      local log_sharpe = type(entry.sharpe) == "number" and string.format("%.2f", entry.sharpe) or "?"
      local log_trades = type(entry.trades) == "number" and tostring(entry.trades) or "?"
      table.insert(qf, {
        filename = path,
        text = string.format("[%s] %s MA(%s,%s) PnL=%s DD=%s Sharpe=%s Trades=%s",
          entry.ticker, entry.timestamp, log_fast, log_slow,
          log_pnl, log_dd, log_sharpe, log_trades),
      })
    end
  end
  vim.fn.setqflist(qf)
  vim.cmd("copen")
  vim.notify("alpha-stream: showing " .. #qf .. " backtest results", vim.log.levels.INFO)
end

return M
