vim.api.nvim_create_user_command("AlphaStreamRun", function()
  require("alpha-stream").start()
end, { desc = "Start alpha-stream backtest dashboard" })
