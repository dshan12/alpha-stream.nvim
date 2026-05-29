if vim.g.loaded_alpha_stream then
  return
end
vim.g.loaded_alpha_stream = true

vim.api.nvim_create_user_command("AlphaStreamRun", function(opts)
  local args = opts.args or ""
  local ticker = #args > 0 and args or "SPY"
  require("alpha-stream").start({ ticker = ticker })
end, { desc = "Start alpha-stream backtest dashboard", nargs = "?" })

vim.api.nvim_create_user_command("AlphaStreamStop", function()
  require("alpha-stream").stop()
end, { desc = "Stop alpha-stream backtest dashboard" })
