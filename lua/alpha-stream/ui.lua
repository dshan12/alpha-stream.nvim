local M = {}

local buf = nil
local win = nil
local ns = vim.api.nvim_create_namespace("alpha-stream")
local restart_cb = nil

local W = 60
local CW = W - 2

local function format_num(n)
  if n == nil then return "0.00" end
  local neg = n < 0
  local str = string.format("%.2f", neg and -n or n)
  local int_part, dec_part = str:match("^(%d+).(%d+)$")
  if not int_part then
    return (neg and "-" or "") .. str
  end
  local parts = {}
  while #int_part > 3 do
    table.insert(parts, 1, int_part:sub(-3))
    int_part = int_part:sub(1, -4)
  end
  table.insert(parts, 1, int_part)
  return (neg and "-" or "") .. table.concat(parts, ",") .. "." .. dec_part
end

function M.set_restart_callback(cb)
  restart_cb = cb
end

function M.open()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    return
  end

  buf = vim.api.nvim_create_buf(false, true)
  local height = 18
  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - W) / 2)

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

  vim.keymap.set("n", "q", function() M.close() end, { buffer = buf, nowait = true, silent = true, desc = "Close alpha-stream" })
  vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = buf, nowait = true, silent = true, desc = "Close alpha-stream" })
  vim.keymap.set("n", "r", function()
    if restart_cb then
      pcall(restart_cb)
    end
  end, { buffer = buf, nowait = true, silent = true, desc = "Restart backtest" })
end

function M.update_dashboard(data)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local pnl = data.pnl or 0
  local is_done = data.status == "done"

  if is_done then
    pcall(vim.api.nvim_win_set_config, win, { title = " α-stream ✓ COMPLETE " })
    vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:DiagnosticOk"
  else
    pcall(vim.api.nvim_win_set_config, win, { title = " α-stream " })
    vim.wo[win].winhighlight = "Normal:Normal"
  end

  local function make_line(label, val)
    return string.format("  %-12s %" .. tostring(CW - 15) .. "s", label, val)
  end

  local pnl_sign = pnl >= 0 and "+" or ""
  local pnl_str = pnl_sign .. "$" .. format_num(math.abs(pnl))
  local port_str = data.portfolio and "$" .. format_num(data.portfolio) or "N/A"
  local dd_str = format_num(data.drawdown) .. "%"
  local price_str = data.price and "$" .. format_num(data.price) or "N/A"
  local fast_str = data.fast_ma and "$" .. format_num(data.fast_ma) or "---"
  local slow_str = data.slow_ma and "$" .. format_num(data.slow_ma) or "---"
  local pos_str = data.position == "long" and "LONG" or "FLAT"

  local progress = data.progress or 0
  local total = data.total or 100
  local bar_len = 20
  local filled = math.floor(progress / total * bar_len)
  local bar = string.rep("█", filled) .. string.rep("░", bar_len - filled)
  local progress_str = string.format("[%s] %d/%d", bar, progress, total)

  local hdr1 = "  ╔" .. string.rep("═", W - 6) .. "╗"
  local hdr2 = "  ║  α-stream — Real-time Backtest" .. string.rep(" ", W - 6 - 30 - 4) .. "║"
  local hdr3 = "  ╚" .. string.rep("═", W - 6) .. "╝"

  local lines = {
    hdr1,
    hdr2,
    hdr3,
    "",
    make_line("PnL:", pnl_str),
    make_line("Drawdown:", dd_str),
    make_line("Portfolio:", port_str),
    "",
    make_line("Price:", price_str),
    make_line("Fast MA:", fast_str),
    make_line("Slow MA:", slow_str),
    make_line("Position:", pos_str),
    "",
    "  " .. progress_str,
  }

  if is_done then
    local bw = CW - 4
    local banner_inner = "    Backtest Complete!  "
    local banner_val = "Final: " .. pnl_str
    local pad = bw - #banner_inner - #banner_val
    table.insert(lines, "  │" .. banner_inner .. banner_val .. string.rep(" ", pad) .. "│")
    table.insert(lines, "  ├" .. string.rep("─", bw) .. "┤")
    local hint_str = "  Press  q  close  ·  r  restart  "
    table.insert(lines, "  │" .. hint_str .. string.rep(" ", bw - #hint_str) .. "│")
    table.insert(lines, "  └" .. string.rep("─", bw) .. "┘")
  else
    table.insert(lines, "  " .. (data.sparkline or ""))
    table.insert(lines, "")
    local hint_str = "  Press  q  close  ·  r  restart"
    table.insert(lines, hint_str .. string.rep(" ", CW - #hint_str))
  end

  pcall(vim.api.nvim_win_set_config, win, { height = #lines })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local hl_lines = {}

  if is_done then
    hl_lines.header = { { 0, "Special", 0, -1 }, { 1, "Title", 0, -1 }, { 2, "Special", 0, -1 } }
    hl_lines.labels = { { 4, "Comment", 2, 15 }, { 5, "Comment", 2, 15 }, { 6, "Comment", 2, 15 }, { 8, "Comment", 2, 15 }, { 9, "Comment", 2, 15 }, { 10, "Comment", 2, 15 }, { 11, "Comment", 2, 15 } }
    hl_lines.pnl = { { 4, pnl >= 0 and "DiagnosticOk" or "DiagnosticError", 15, -1 } }
    hl_lines.dd = { { 5, (data.drawdown or 0) <= 0 and "DiagnosticOk" or "DiagnosticError", 15, -1 } }
    hl_lines.pos = { { 11, data.position == "long" and "DiagnosticOk" or "Comment", 15, -1 } }
    hl_lines.progress = { { 13, "Special", 2, -1 } }
    hl_lines.banner = { { 14, "DiagnosticOk", 0, -1 }, { 15, "Comment", 0, -1 }, { 16, "Comment", 0, -1 }, { 17, "Special", 0, -1 } }
  else
    hl_lines.header = { { 0, "Special", 0, -1 }, { 1, "Title", 0, -1 }, { 2, "Special", 0, -1 } }
    hl_lines.labels = { { 4, "Comment", 2, 15 }, { 5, "Comment", 2, 15 }, { 6, "Comment", 2, 15 }, { 8, "Comment", 2, 15 }, { 9, "Comment", 2, 15 }, { 10, "Comment", 2, 15 }, { 11, "Comment", 2, 15 } }
    hl_lines.pnl = { { 4, pnl >= 0 and "DiagnosticOk" or "DiagnosticError", 15, -1 } }
    hl_lines.dd = { { 5, (data.drawdown or 0) <= 0 and "DiagnosticOk" or "DiagnosticError", 15, -1 } }
    hl_lines.pos = { { 11, data.position == "long" and "DiagnosticOk" or "Comment", 15, -1 } }
    hl_lines.progress = { { 13, "Special", 2, -1 } }
    hl_lines.sparkline = { { 14, "Special", 2, -1 } }
    hl_lines.hint = { { 16, "Comment", 0, -1 } }
  end

  for _, group in pairs(hl_lines) do
    for _, hl in ipairs(group) do
      vim.api.nvim_buf_add_highlight(buf, ns, hl[2], hl[1], hl[3], hl[4])
    end
  end
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
    "",
    "  Press q to close",
  }
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
