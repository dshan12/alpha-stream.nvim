local M = {}

local buf = nil
local win = nil
local ns = vim.api.nvim_create_namespace("alpha-stream")
local restart_cb = nil
local pnl_ticks = {}
local dd_ticks = {}

local W = 86
local CW = W - 2

local function format_num(n)
  if type(n) ~= "number" then return "0.00" end
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

local function compute_sharpe(ticks)
  if #ticks < 3 then return 0 end
  local returns = {}
  for i = 2, #ticks do
    table.insert(returns, ticks[i] - ticks[i - 1])
  end
  local sum = 0
  for _, v in ipairs(returns) do sum = sum + v end
  local mean = sum / #returns
  local variance = 0
  for _, v in ipairs(returns) do
    variance = variance + (v - mean) ^ 2
  end
  variance = variance / (#returns - 1)
  local std = math.sqrt(variance)
  if std == 0 then return 0 end
  return math.floor(mean / std * 100) / 100
end

local function render_chart(values, chart_w, chart_h)
  local rows = {}
  for i = 1, chart_h do rows[i] = "" end
  if not values or #values < 2 then return rows end

  local n = math.min(#values, chart_w)
  local start = #values - n + 1

  local mn = values[start]
  local mx = values[start]
  for i = start, #values do
    if values[i] < mn then mn = values[i] end
    if values[i] > mx then mx = values[i] end
  end
  local rng = mx - mn
  if rng == 0 then rng = 1 end

  local partials = { "▁", "▂", "▃", "▄" }

  for i = start, #values do
    local raw = (values[i] - mn) / rng * (chart_h * 4)
    local row = math.floor(raw / 4)
    local sub = raw % 4

    for r = 0, chart_h - 1 do
      local idx = chart_h - r
      if r < row then
        rows[idx] = rows[idx] .. "█"
      elseif r == row then
        if sub >= 3 then
          rows[idx] = rows[idx] .. "█"
        else
          rows[idx] = rows[idx] .. partials[math.floor(sub) + 1]
        end
      else
        rows[idx] = rows[idx] .. " "
      end
    end
  end

  return rows
end

local partials = { "▁", "▂", "▃", "▄" }

local function render_sharpe_chart(ticks, chart_w, chart_h)
  local rows = {}
  for i = 1, chart_h do rows[i] = "" end
  if #ticks < 22 then return rows end

  local window = 20
  local sharpe_vals = {}
  for i = window + 1, #ticks do
    local s = 0
    for j = i - window + 1, i do
      s = s + ticks[j] - ticks[j - 1]
    end
    local mean = s / window
    local v = 0
    for j = i - window + 1, i do
      v = v + (ticks[j] - ticks[j - 1] - mean) ^ 2
    end
    v = v / (window - 1)
    local std = math.sqrt(v)
    table.insert(sharpe_vals, std > 0 and mean / std or 0)
  end

  if #sharpe_vals < 2 then return rows end

  local n = math.min(#sharpe_vals, chart_w)
  local start = #sharpe_vals - n + 1

  local mn = sharpe_vals[start]
  local mx = sharpe_vals[start]
  for i = start, #sharpe_vals do
    if sharpe_vals[i] < mn then mn = sharpe_vals[i] end
    if sharpe_vals[i] > mx then mx = sharpe_vals[i] end
  end
  local rng = mx - mn
  if rng == 0 then rng = 1 end

  for i = start, #sharpe_vals do
    local raw = (sharpe_vals[i] - mn) / rng * (chart_h * 4)
    local row = math.floor(raw / 4)
    local sub = raw % 4

    for r = 0, chart_h - 1 do
      local idx = chart_h - r
      if r < row then
        rows[idx] = rows[idx] .. "█"
      elseif r == row then
        if sub >= 3 then
          rows[idx] = rows[idx] .. "█"
        else
          rows[idx] = rows[idx] .. partials[math.floor(sub) + 1]
        end
      else
        rows[idx] = rows[idx] .. " "
      end
    end
  end

  return rows
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
  local height = 30
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

  if type(data.pnl) == "number" then
    table.insert(pnl_ticks, data.pnl)
  end
  if type(data.drawdown) == "number" then
    table.insert(dd_ticks, data.drawdown)
  end

  local sep = "  " .. string.rep("─", CW - 2) .. "  "

  local pnl_sign = pnl >= 0 and "+" or ""
  local pnl_str = pnl_sign .. "$" .. format_num(math.abs(pnl))
  local dd_str = format_num(data.drawdown) .. "%"
  local port_str = type(data.portfolio) == "number" and "$" .. format_num(data.portfolio) or "N/A"
  local price_str = type(data.price) == "number" and "$" .. format_num(data.price) or "N/A"
  local fast_str = type(data.fast_ma) == "number" and "$" .. format_num(data.fast_ma) or "---"
  local slow_str = type(data.slow_ma) == "number" and "$" .. format_num(data.slow_ma) or "---"
  local pos_str = data.position == "long" and "LONG" or "FLAT"
  local sharpe_str = format_num(compute_sharpe(pnl_ticks))

  local progress = data.progress or 0
  local total = data.total or 100
  local bar_len = 16
  local bar = string.rep("█", math.floor(progress / total * bar_len)) .. string.rep("░", bar_len - math.floor(progress / total * bar_len))
  local progress_str = string.format("[%s] %d/%d", bar, progress, total)

  local eq_h = 7
  local sub_h = 7
  local sub_w = math.floor((CW - 4) / 2)

  local eq_curve = render_chart(pnl_ticks, CW - 4, eq_h)
  local dd_curve = render_chart(dd_ticks, sub_w, sub_h)
  local sr_curve = render_sharpe_chart(pnl_ticks, sub_w, sub_h)

  local eq_color = pnl >= 0 and "DiagnosticOk" or "DiagnosticError"
  local dd_color = (data.drawdown or 0) <= 0 and "DiagnosticOk" or "DiagnosticError"
  local sr_color = compute_sharpe(pnl_ticks) >= 0 and "DiagnosticOk" or "DiagnosticError"

  local lines = {
    "  " .. progress_str,
    sep,
    string.format("  %-13s %s     %-13s %s", "PnL:", pnl_str, "Drawdown:", dd_str),
    string.format("  %-13s %s     %-13s %s", "Portfolio:", port_str, "Price:", price_str),
    string.format("  %-13s %s     %-13s %s", "Fast MA:", fast_str, "Slow MA:", slow_str),
    string.format("  %-13s %s     %-13s %s", "Position:", pos_str, "Sharpe:", sharpe_str),
    sep,
    "  " .. "Equity Curve",
  }

  for _, row in ipairs(eq_curve) do
    table.insert(lines, "   " .. row)
  end

  table.insert(lines, sep)

  local hdr_dd = "  Drawdown" .. string.rep(" ", sub_w - 8) .. "│   "
  local hdr_sr = "Rolling Sharpe"
  local hdr_pad = sub_w * 2 + 2 - #hdr_dd - #hdr_sr
  table.insert(lines, hdr_dd .. hdr_sr .. string.rep(" ", hdr_pad))

  for r = 1, sub_h do
    local dd_row = dd_curve[r] or ""
    local sr_row = sr_curve[r] or ""
    local dd_pad = sub_w - #dd_row
    local sr_pad = sub_w - #sr_row
    table.insert(lines, "  " .. dd_row .. string.rep(" ", dd_pad) .. " │  " .. sr_row .. string.rep(" ", sr_pad))
  end

  if is_done then
    table.insert(lines, sep)
    table.insert(lines, "  │  Backtest Complete!  Final: " .. pnl_str .. string.rep(" ", CW - 34 - #pnl_str) .. "│")
    table.insert(lines, "  └" .. string.rep("─", CW - 2) .. "┘  ")
  end

  local hint_line = #lines + 1
  table.insert(lines, "  Press  q  close  ·  r  restart" .. string.rep(" ", CW - 38))

  pcall(vim.api.nvim_win_set_config, win, { height = #lines })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local hl_lines = {
    { 0, "Special", 2, -1 },
    { 2, "Comment", 2, 15 }, { 2, "Comment", 40, 55 },
    { 3, "Comment", 2, 15 }, { 3, "Comment", 40, 55 },
    { 4, "Comment", 2, 15 }, { 4, "Comment", 40, 55 },
    { 5, "Comment", 2, 15 }, { 5, "Comment", 40, 55 },
    { 2, pnl >= 0 and "DiagnosticOk" or "DiagnosticError", 16, -1 },
    { 2, (data.drawdown or 0) <= 0 and "DiagnosticOk" or "DiagnosticError", 56, -1 },
    { 3, "DiagnosticOk", 16, -1 },
    { 5, data.position == "long" and "DiagnosticOk" or "Comment", 16, -1 },
    { 5, sr_color, 56, -1 },
  }

  local chart_start = 8
  for r = 1, eq_h do
    table.insert(hl_lines, { r - 1 + chart_start, eq_color, 2, -1 })
  end

  local sub_start = chart_start + eq_h + 2
  for r = 1, sub_h do
    table.insert(hl_lines, { r - 1 + sub_start, dd_color, 2, sub_w + 2 })
    table.insert(hl_lines, { r - 1 + sub_start, sr_color, sub_w + 7, -1 })
  end

  local hint_idx = #lines - 1
  table.insert(hl_lines, { hint_idx, "Comment", 0, -1 })

  for _, hl in ipairs(hl_lines) do
    if hl[1] ~= nil and hl[2] ~= nil then
      local ok, _ = pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl[2], hl[1], hl[3] or 0, hl[4] or -1)
    end
  end
end

function M.show_error(msg)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    M.open()
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
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
  pnl_ticks = {}
  dd_ticks = {}
end

return M
