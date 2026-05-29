if vim.g.loaded_alpha_stream then
  return
end
vim.g.loaded_alpha_stream = true

vim.api.nvim_create_user_command("AlphaStreamRun", function(opts)
  local parts = vim.split(opts.args or "", "%s+")
  local ticker = parts[1] or "SPY"
  local strategy = "ma_crossover"
  local fast = 50
  local slow = 200

  if parts[2] then
    if parts[2]:match("^%d+$") then
      fast = tonumber(parts[2])
    else
      strategy = parts[2]
      if parts[3] and parts[3]:match("^%d+$") then fast = tonumber(parts[3]) end
      if parts[4] and parts[4]:match("^%d+$") then slow = tonumber(parts[4]) end
    end
  end

  require("alpha-stream").start({
    ticker = ticker,
    strategy = strategy,
    fast_ma = fast,
    slow_ma = slow,
  })
end, { desc = "Start backtest: :AlphaStreamRun [ticker] [strategy] [fast_ma] [slow_ma]", nargs = "*" })

vim.api.nvim_create_user_command("AlphaStreamStop", function()
  require("alpha-stream").stop()
end, { desc = "Stop alpha-stream backtest dashboard" })

vim.api.nvim_create_user_command("AlphaStreamLog", function()
  require("alpha-stream").log()
end, { desc = "Show backtest results log" })

vim.api.nvim_create_user_command("AlphaStreamEdit", function()
  local src = debug.getinfo(require("alpha-stream").start, "S").source:match("@?(.*)")
  local root = vim.fn.fnamemodify(src, ":p:h:h:h")
  vim.cmd("edit " .. root .. "/python/engine.py")
end, { desc = "Open strategy file for editing" })
