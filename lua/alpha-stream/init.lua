local ui = require("alpha-stream.ui")
local job = require("alpha-stream.job")

local M = {}
local running = false
local current_ticker = "SPY"
local current_strategy_file = "sma_cross"

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
    strategy_file = current_strategy_file or "",
    strategy = type(data.strategy) == "string" and data.strategy or "",
    pnl = type(data.pnl) == "number" and data.pnl or 0,
    drawdown = type(data.drawdown) == "number" and data.drawdown or 0,
    sharpe = type(data.sharpe) == "number" and data.sharpe or nil,
    trades = type(data.trades) == "number" and data.trades or 0,
    return_pct = type(data.return_pct) == "number" and data.return_pct or nil,
    win_rate = type(data.win_rate) == "number" and data.win_rate or nil,
  }
  local line = vim.json.encode(entry) .. "\n"
  vim.fn.writefile({ line }, path, "a")
end

ui.set_restart_callback(function()
  M.restart()
end)

ui.set_start_callback(function()
  M.start({ ticker = current_ticker, strategy_file = current_strategy_file })
end)

ui.set_stop_callback(function()
  M.stop()
end)

function M.start(opts)
  opts = opts or {}
  current_ticker = type(opts.ticker) == "string" and opts.ticker or "SPY"
  if type(opts.strategy_file) == "string" and opts.strategy_file ~= "" then
    current_strategy_file = opts.strategy_file
  elseif type(opts.strategy) == "string" and opts.strategy ~= "" then
    current_strategy_file = opts.strategy
  end

  if running then
    vim.notify("alpha-stream: already running", vim.log.levels.WARN)
    return
  end

  running = true
  ui.set_ticker(current_ticker)
  ui.set_strategy_file(current_strategy_file)
  ui.open()
  ui.update_dashboard({
    progress = 0,
    pnl = 0,
    drawdown = 0,
    portfolio = 10000,
    price = 0,
    position = "flat",
    status = "starting",
  })

  local root = get_plugin_root()
  local script = root .. "/python/engine.py"
  local extra_args = { "--ticker", current_ticker }
  if current_strategy_file then
    if current_strategy_file:match("%.py$") or current_strategy_file:match("[/\\]") then
      table.insert(extra_args, "--strategy-file")
    else
      table.insert(extra_args, "--strategy")
    end
    table.insert(extra_args, current_strategy_file)
  end

  local ok, err = pcall(function()
    local started = job.spawn(script, function(data)
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
    if not started then
      running = false
    end
  end)

  if not ok then
    running = false
    ui.show_error(tostring(err))
    local tb = debug.traceback()
    io.stderr:write("ALPHA-STREAM PCALL ERROR: " .. tostring(err) .. "\n")
    io.stderr:write("TRACEBACK: " .. tostring(tb) .. "\n")
    io.stderr:flush()
    vim.notify("alpha-stream: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- debug: test raw spawn
--[[
io.stderr:write("DEBUG: testing raw job.spawn...\n")
local debug_started = job.spawn(
  script,
  function(d) io.stderr:write("DEBUG on_line\n") end,
  function(r) io.stderr:write("DEBUG on_exit\n") end,
  extra_args
)
io.stderr:write("DEBUG spawn result: " .. tostring(debug_started) .. "\n")
io.stderr:flush()
--]]

function M.stop()
  job.stop()
  running = false
  ui.close()
end

function M.restart()
  M.stop()
  vim.defer_fn(function()
    M.start({ ticker = current_ticker, strategy_file = current_strategy_file })
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
      local log_strat = type(entry.strategy) == "string" and entry.strategy or "?"
      local log_pnl = type(entry.pnl) == "number" and string.format("%+.2f", entry.pnl) or "?"
      local log_dd = type(entry.drawdown) == "number" and string.format("%.2f", entry.drawdown) or "?"
      local log_sharpe = type(entry.sharpe) == "number" and string.format("%.2f", entry.sharpe) or "?"
      local log_trades = type(entry.trades) == "number" and tostring(entry.trades) or "?"
      local log_return = type(entry.return_pct) == "number" and string.format("%.2f%%", entry.return_pct) or "?"
      table.insert(qf, {
        filename = path,
        text = string.format("[%s] %s %s PnL=%s Return=%s DD=%s Sharpe=%s Trades=%s",
          entry.ticker, entry.timestamp, log_strat,
          log_pnl, log_return, log_dd, log_sharpe, log_trades),
      })
    end
  end
  vim.fn.setqflist(qf)
  vim.cmd("copen")
  vim.notify("alpha-stream: showing " .. #qf .. " backtest results", vim.log.levels.INFO)
end

return M
