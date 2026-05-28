local M = {}

local buf = nil
local win = nil
local ns = vim.api.nvim_create_namespace("alpha-stream")

function M.open()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    return
  end

  buf = vim.api.nvim_create_buf(false, true)
  local width = 54
  local height = 14
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

  vim.wo[win].winhighlight = "Normal:Normal"
end

function M.update_dashboard(data)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local pnl_str = string.format("$%s", string.format("%.2f", data.pnl))
  local dd_str = string.format("%.2f%%", data.drawdown)
  local price_str = data.price and string.format("$%.2f", data.price) or "N/A"
  local fast_str = data.fast_ma and string.format("$%.2f", data.fast_ma) or "---"
  local slow_str = data.slow_ma and string.format("$%.2f", data.slow_ma) or "---"
  local pos_str = data.position == "long" and "LONG" or "FLAT"
  local port_str = data.portfolio and string.format("$%s", string.format("%.2f", data.portfolio)) or "N/A"
  local progress = data.progress or 0
  local total = data.total or 100
  local bar_len = 20
  local filled = math.floor(progress / total * bar_len)
  local bar = string.rep("=", filled) .. string.rep("-", bar_len - filled)
  local progress_str = string.format("[%s] %d/%d", bar, progress, total)

  local lines = {
    "",
    "  PnL:        " .. pnl_str,
    "  Drawdown:   " .. dd_str,
    "  Portfolio:  " .. port_str,
    "",
    "  Price:      " .. price_str,
    "  Fast MA:    " .. fast_str,
    "  Slow MA:    " .. slow_str,
    "  Position:   " .. pos_str,
    "",
    "  " .. progress_str,
    "",
    "  " .. (data.sparkline or ""),
  }

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local pnl = data.pnl or 0
  local pnl_color = pnl >= 0 and "DiagnosticOk" or "DiagnosticError"
  local dd_color = data.drawdown <= 0 and "DiagnosticOk" or "DiagnosticError"
  local pos_color = data.position == "long" and "DiagnosticOk" or "Comment"

  vim.api.nvim_buf_add_highlight(buf, ns, pnl_color, 1, 2, 14)
  vim.api.nvim_buf_add_highlight(buf, ns, dd_color, 2, 2, 14)
  vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 3, 2, 14)
  vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 5, 2, 14)
  vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 6, 2, 14)
  vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 7, 2, 14)
  vim.api.nvim_buf_add_highlight(buf, ns, pos_color, 8, 2, 14)
  vim.api.nvim_buf_add_highlight(buf, ns, "Special", 11, 2, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "Title", 12, 2, -1)
end

function M.show_error(msg)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    M.open()
  end
  local lines = {
    "",
    "  ERROR",
    "",
    "  " .. msg,
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticError", 1, 2, -1)
end

function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
  buf = nil
end

return M
