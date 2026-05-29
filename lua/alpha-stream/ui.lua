local M = {}

local buf = nil
local win = nil
local ns = vim.api.nvim_create_namespace("alpha-stream")
local restart_cb = nil
local current_ticker = "SPY"

local W = 54
local CW = W - 2
local LW = 11

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

local function row(label, value)
  return string.format("  %-" .. tostring(LW) .. "s %s", label, value)
end

function M.set_restart_callback(cb)
  restart_cb = cb
end

function M.set_ticker(t)
  current_ticker = t or "SPY"
end

function M.open()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    return
  end

  local ui_state = vim.api.nvim_list_uis()[1]
  if not ui_state then return end

  buf = vim.api.nvim_create_buf(false, true)
  local height = 18
  local row_pos = math.floor((ui_state.height - height) / 2)
  local col = math.floor((ui_state.width - W) / 2)

  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = W,
    height = height,
    row = row_pos,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " α-stream: " .. current_ticker .. " ",
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
  local is_starting = data.status == "starting"
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
  local sharpe_str = type(data.sharpe) == "number" and string.format("%.2f", data.sharpe) or "--"
  local trades_str = type(data.trades) == "number" and tostring(data.trades) or "--"
  local progress = data.progress or 0
  local total = data.total or 100

  local title = " α-stream: " .. current_ticker .. " "
  if is_done then
    title = " α-stream: " .. current_ticker .. " ✓ COMPLETE "
  end
  pcall(vim.api.nvim_win_set_config, win, { title = title })

  local status_msg
  if is_starting then
    status_msg = "Initializing backtest..."
  elseif is_done then
    status_msg = "Complete!  Final: " .. pnl_str
  else
    status_msg = "Live backtest running..."
  end

  local bar_len = 22
  local filled = math.floor(progress / total * bar_len)
  local bar = string.rep("█", filled) .. string.rep("░", bar_len - filled)

  local lines = {
    row("Ticker:", current_ticker),
    row("Status:", status_msg),
    row("Period:", tostring(progress) .. " / " .. tostring(total) .. " bars"),
    "",
    row("PnL:", pnl_str),
    row("Portfolio:", port_str),
    row("Max DD:", dd_str),
    row("Sharpe (20d):", sharpe_str),
    "",
    row("Price:", price_str),
    row("Fast MA (50):", fast_str),
    row("Slow MA (200):", slow_str),
    row("Position:", pos_str),
    row("Trades:", trades_str),
    "",
    "  " .. bar .. "  " .. tostring(progress) .. "/" .. tostring(total),
    "",
    ":AlphaStreamRun AAPL  q close  r restart",
  }

  pcall(vim.api.nvim_win_set_config, win, { height = #lines })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_buf_add_highlight(buf, ns, pnl_color, 4, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, dd_color, 6, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, pos_color, 12, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "Special", 15, 2, -1)
end

function M.show_error(msg)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    M.open()
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local lines = { "", "  ERROR", "", "  " .. msg, "", "  q to close" }
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
