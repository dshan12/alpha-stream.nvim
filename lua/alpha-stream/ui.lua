local M = {}

local buf = nil
local win = nil
local ns = vim.api.nvim_create_namespace("alpha-stream")
local restart_cb = nil

local W = 54
local CW = W - 2

local function fmt(n)
  if type(n) ~= "number" then return "0.00" end
  local neg = n < 0
  local s = string.format("%.2f", neg and -n or n)
  local int, dec = s:match("^(%d+).(%d+)$")
  if not int then return (neg and "-" or "") .. s end
  local parts = {}
  while #int > 3 do
    table.insert(parts, 1, int:sub(-3))
    int = int:sub(1, -4)
  end
  table.insert(parts, 1, int)
  return (neg and "-" or "") .. table.concat(parts, ",") .. "." .. dec
end

function M.set_restart_callback(cb)
  restart_cb = cb
end

function M.open()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    return
  end

  local ui_state = vim.api.nvim_list_uis()[1]
  if not ui_state then return end

  buf = vim.api.nvim_create_buf(false, true)
  local height = 16
  local row = math.floor((ui_state.height - height) / 2)
  local col = math.floor((ui_state.width - W) / 2)

  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = W,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " α-stream ",
    title_pos = "center",
  })

  vim.wo[win].winhighlight = "Normal:Normal"

  vim.keymap.set("n", "q", function() M.close() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "r", function()
    if restart_cb then pcall(restart_cb) end
  end, { buffer = buf, nowait = true, silent = true })
end

function M.update_dashboard(data)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local pnl = data.pnl or 0
  local is_done = data.status == "done"

  if is_done then
    pcall(vim.api.nvim_win_set_config, win, { title = " α-stream ✓ COMPLETE " })
  else
    pcall(vim.api.nvim_win_set_config, win, { title = " α-stream " })
  end

  local pnl_color = pnl >= 0 and "DiagnosticOk" or "DiagnosticError"
  local dd_color = (data.drawdown or 0) <= 0 and "DiagnosticOk" or "DiagnosticError"
  local pos_color = data.position == "long" and "DiagnosticOk" or "Comment"

  local pnl_sign = pnl >= 0 and "+" or ""
  local pnl_str = pnl_sign .. "$" .. fmt(math.abs(pnl))
  local dd_str = fmt(data.drawdown) .. "%"
  local port_str = type(data.portfolio) == "number" and "$" .. fmt(data.portfolio) or "--"
  local price_str = type(data.price) == "number" and "$" .. fmt(data.price) or "--"
  local fast_str = type(data.fast_ma) == "number" and "$" .. fmt(data.fast_ma) or "--"
  local slow_str = type(data.slow_ma) == "number" and "$" .. fmt(data.slow_ma) or "--"
  local pos_str = data.position == "long" and "LONG" or "FLAT"

  local bar_len = 18
  local filled = math.floor((data.progress or 0) / (data.total or 100) * bar_len)
  local bar = string.rep("█", filled) .. string.rep("░", bar_len - filled)

  local function L(label, val, w)
    return string.format("  %s %" .. tostring(w or 14) .. "s", label, val)
  end

  local lines = {
    L("PnL:", pnl_str, CW - 5),
    L("Drawdown:", dd_str, CW - 11),
    L("Portfolio:", port_str, CW - 11),
    "",
    L("Price:", price_str, CW - 7),
    L("Fast MA:", fast_str, CW - 9),
    L("Slow MA:", slow_str, CW - 9),
    L("Position:", pos_str, CW - 10),
    "",
    "  " .. bar .. string.format("  %d/%d", data.progress or 0, data.total or 0),
  }

  if is_done then
    table.insert(lines, "")
    table.insert(lines, "  Backtest Complete")
    table.insert(lines, "  Final: " .. pnl_str .. string.rep(" ", CW - 14 - #pnl_str))
    table.insert(lines, "  Press q close · r restart")
  else
    table.insert(lines, "")
    table.insert(lines, "  Press q close · r restart")
  end

  pcall(vim.api.nvim_win_set_config, win, { height = #lines })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_buf_add_highlight(buf, ns, pnl_color, 0, 6, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, dd_color, 1, 6, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticOk", 2, 6, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, pos_color, 7, 6, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "Special", 9, 2, -1)
end

function M.show_error(msg)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    M.open()
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local lines = { "", "  ERROR", "", "  " .. msg, "", "  Press q to close" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  pcall(vim.api.nvim_win_set_config, win, { height = #lines })
  vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticError", 1, 2, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 5, 0, -1)
end

function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
  buf = nil
end

return M
