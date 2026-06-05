if vim.g.loaded_alpha_stream then
  return
end
vim.g.loaded_alpha_stream = true

local BUILTIN_STRATEGIES = { "sma_cross", "mean_reversion", "rsi_reversal" }
local TICKERS = { "SPY", "AAPL", "MSFT", "GOOGL", "AMZN", "TSLA", "NVDA", "META", "BRK.B", "JPM", "V", "JNJ", "WMT", "PG", "MA", "UNH", "HD", "DIS", "NFLX", "KO", "PEP", "BAC", "CRM", "INTC", "AMD", "QQQ", "IWM", "EEM", "GLD", "SLV" }

vim.api.nvim_create_user_command("AlphaStreamRun", function(opts)
  local parts = vim.split(opts.args or "", "%s+")
  local ticker = (parts[1] and parts[1] ~= "") and parts[1] or nil
  local strategy_file = (parts[2] and parts[2] ~= "") and parts[2] or nil

  local args = {}
  if ticker then args.ticker = ticker end
  if strategy_file then args.strategy_file = strategy_file end

  require("alpha-stream").start(args)
end, {
  desc = "Run backtest: :AlphaStreamRun [ticker] [strategy-file-or-name]",
  nargs = "*",
  complete = function(ArgLead, CmdLine, CursorPos)
    local args = vim.split(CmdLine, "%s+")
    local arg_idx = #args
    if CmdLine:match("%s$") then
      arg_idx = arg_idx + 1
    end
    local choices
    if arg_idx == 1 then
      choices = TICKERS
    elseif arg_idx == 2 then
      choices = BUILTIN_STRATEGIES
    else
      return {}
    end
    if ArgLead == "" then
      return choices
    end
    local result = {}
    for _, c in ipairs(choices) do
      if c:lower():find(ArgLead:lower(), 1, true) then
        table.insert(result, c)
      end
    end
    return result
  end,
})

vim.api.nvim_create_user_command("AlphaStreamStop", function()
  require("alpha-stream").stop()
end, { desc = "Stop alpha-stream backtest dashboard" })

vim.api.nvim_create_user_command("AlphaStreamSweep", function(opts)
  local parts = vim.split(opts.args or "", "%s+")
  local ticker = (parts[1] and parts[1] ~= "") and parts[1] or nil
  local strategy = (parts[2] and parts[2] ~= "") and parts[2] or nil

  local grid = {}
  for i = 3, #parts do
    local spec = parts[i]
    if spec and spec ~= "" then
      if not spec:find("=", 1, true) then
        vim.notify("alpha-stream: expected NAME=v1,v2,v3 (got: " .. spec .. ")", vim.log.levels.ERROR)
        return
      end
      table.insert(grid, spec)
    end
  end

  if not ticker or not strategy or #grid == 0 then
    vim.notify("alpha-stream: usage :AlphaStreamSweep TICKER STRATEGY param=v1,v2 [...]", vim.log.levels.ERROR)
    return
  end

  local sweep = require("alpha-stream.sweep")
  if sweep.is_open() then
    sweep.close()
  end
  sweep.run({ ticker = ticker, strategy = strategy, grid = grid })
end, {
  desc = "Sweep parameters: :AlphaStreamSweep TICKER STRATEGY param=v1,v2 [...]",
  nargs = "*",
  complete = function(ArgLead, CmdLine, CursorPos)
    local args = vim.split(CmdLine, "%s+")
    local arg_idx = #args
    if CmdLine:match("%s$") then
      arg_idx = arg_idx + 1
    end
    local choices
    if arg_idx == 1 then
      choices = TICKERS
    elseif arg_idx == 2 then
      choices = BUILTIN_STRATEGIES
    else
      return {}
    end
    if ArgLead == "" then
      return choices
    end
    local result = {}
    for _, c in ipairs(choices) do
      if c:lower():find(ArgLead:lower(), 1, true) then
        table.insert(result, c)
      end
    end
    return result
  end,
})

vim.api.nvim_create_user_command("AlphaStreamCompare", function(opts)
  local parts = vim.split(opts.args or "", "%s+")
  local ticker = (parts[1] and parts[1] ~= "") and parts[1] or nil

  local strategies = {}
  for i = 2, #parts do
    local s = parts[i]
    if s and s ~= "" then
      table.insert(strategies, s)
    end
  end

  if not ticker or #strategies < 2 then
    vim.notify("alpha-stream: usage :AlphaStreamCompare TICKER STRAT1 STRAT2 [STRAT3 ...]", vim.log.levels.ERROR)
    return
  end

  local compare = require("alpha-stream.compare")
  if compare.is_open() then
    compare.close()
  end
  compare.run({ ticker = ticker, strategies = strategies })
end, {
  desc = "Compare strategies: :AlphaStreamCompare TICKER STRAT1 STRAT2 [STRAT3 ...]",
  nargs = "*",
  complete = function(ArgLead, CmdLine, CursorPos)
    local args = vim.split(CmdLine, "%s+")
    local arg_idx = #args
    if CmdLine:match("%s$") then
      arg_idx = arg_idx + 1
    end
    if arg_idx == 1 then
      local choices = TICKERS
      if ArgLead == "" then return choices end
      local result = {}
      for _, c in ipairs(choices) do
        if c:lower():find(ArgLead:lower(), 1, true) then
          table.insert(result, c)
        end
      end
      return result
    elseif arg_idx >= 2 then
      local choices = BUILTIN_STRATEGIES
      if ArgLead == "" then return choices end
      local result = {}
      for _, c in ipairs(choices) do
        if c:lower():find(ArgLead:lower(), 1, true) then
          table.insert(result, c)
        end
      end
      return result
    end
    return {}
  end,
})

vim.api.nvim_create_user_command("AlphaStreamLog", function()
  require("alpha-stream").log()
end, { desc = "Show backtest results log" })

vim.api.nvim_create_user_command("AlphaStreamEdit", function()
  local ok, mod = pcall(require, "alpha-stream")
  if not ok or not mod or not mod.start then return end
  local info = debug.getinfo(mod.start, "S")
  if not info or not info.source then return end
  local src = info.source:match("@?(.*)")
  if not src then return end
  local root = vim.fn.fnamemodify(src, ":p:h:h:h")
  vim.cmd("edit " .. root .. "/python/strategies")
end, { desc = "Open strategies directory for editing" })
