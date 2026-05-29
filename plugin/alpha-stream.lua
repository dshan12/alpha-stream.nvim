if vim.g.loaded_alpha_stream then
  return
end
vim.g.loaded_alpha_stream = true

vim.api.nvim_create_user_command("AlphaStreamRun", function(opts)
  local parts = vim.split(opts.args or "", "%s+")
  local ticker = parts[1] or "SPY"
  local fast = tonumber(parts[2]) or 50
  local slow = tonumber(parts[3]) or 200
  require("alpha-stream").start({ ticker = ticker, fast_ma = fast, slow_ma = slow })
end, { desc = "Start backtest: :AlphaStreamRun [ticker] [fast_ma] [slow_ma]", nargs = "*" })

vim.api.nvim_create_user_command("AlphaStreamStop", function()
  require("alpha-stream").stop()
end, { desc = "Stop alpha-stream backtest dashboard" })

vim.api.nvim_create_user_command("AlphaStreamLog", function()
  require("alpha-stream").log()
end, { desc = "Show backtest results log" })
