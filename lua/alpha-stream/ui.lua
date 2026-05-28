local M = {}

local buf = nil
local win = nil

function M.open()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    return
  end

  buf = vim.api.nvim_create_buf(false, true)
  local width = 50
  local height = 12
  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Alpha Stream ",
    title_pos = "center",
  })
end

function M.update_dashboard(data)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = {
    "  Progress:   " .. tostring(data.progress) .. " / 100",
    "  PnL:        $" .. string.format("%.2f", data.pnl),
    "  Drawdown:   " .. string.format("%.2f", data.drawdown) .. "%",
    "  Status:     " .. data.status,
  }

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
  buf = nil
end

return M
