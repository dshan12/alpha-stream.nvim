local M = {}

local buf = nil
local win = nil
local ns = vim.api.nvim_create_namespace("alpha-stream")
local restart_cb = nil
local start_cb = nil
local stop_cb = nil
local current_ticker = "SPY"
local current_strategy_file = nil

local W = 58
local LW = 14

local PARAM_KEYS = { "fast", "slow", "n1", "n2", "fast_window", "slow_window",
                     "lookback", "entry_pct", "exit_pct",
                     "rsi_period", "oversold", "overbought" }

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

local function fmt_pct(n)
  if type(n) ~= "number" then return "0.00%" end
  local s = string.format("%.2f%%", n)
  if n > 0 then s = "+" .. s end
  return s
end

local function row(label, value)
  return string.format("  %-" .. tostring(LW) .. "s %s", label, value)
end

local function extract_params(data)
  if type(data) ~= "table" then return "" end
  local parts = {}
  for _, k in ipairs(PARAM_KEYS) do
    if type(data[k]) == "number" then
      local v = data[k]
      if v == math.floor(v) then
        table.insert(parts, k .. "=" .. tostring(math.floor(v)))
      else
        table.insert(parts, k .. "=" .. string.format("%.2f", v))
      end
    end
  end
  return table.concat(parts, "  ")
end

local function strategy_short_name(path)
  if type(path) ~= "string" or path == "" then return "default" end
  local name = path:match("([^/\\]+)$") or path
  name = name:gsub("%.py$", "")
  return name
end

function M.set_restart_callback(cb)
  restart_cb = cb
end

function M.set_start_callback(cb)
  start_cb = cb
end

function M.set_stop_callback(cb)
  stop_cb = cb
end

function M.set_ticker(t)
  current_ticker = type(t) == "string" and t or "SPY"
end

function M.set_strategy_file(path)
  if type(path) == "string" and path ~= "" then
    current_strategy_file = path
  end
end

function M.open()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    return
  end

  local ui_state = vim.api.nvim_list_uis()[1]
  if not ui_state then return end

  buf = vim.api.nvim_create_buf(false, true)
  local height = 20
  local row_pos = math.floor((ui_state.height - height) / 2)
  local col = math.floor((ui_state.width - W) / 2)

  local strat_disp = strategy_short_name(current_strategy_file)
  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = W,
    height = height,
    row = row_pos,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " α-stream: " .. current_ticker .. " · " .. strat_disp .. " ",
    title_pos = "center",
  })

  vim.wo[win].winhighlight = "Normal:Normal"

  vim.keymap.set("n", "q", function() M.close() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "s", function()
    if start_cb then pcall(start_cb) end
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "x", function()
    if stop_cb then pcall(stop_cb) end
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "?", function()
    M.show_help()
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "r", function()
    if restart_cb then pcall(restart_cb) end
  end, { buffer = buf, nowait = true, silent = true })
end

function M.update_dashboard(data)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  if type(data) ~= "table" then return end
  local pnl = type(data.pnl) == "number" and data.pnl or 0
  local is_done = data.status == "done"
  local is_starting = data.status == "starting"
  local pnl_color = pnl >= 0 and "DiagnosticOk" or "DiagnosticError"
  local dd_val = type(data.drawdown) == "number" and data.drawdown or 0
  local dd_color = dd_val <= 0 and "DiagnosticOk" or "DiagnosticError"
  local pos_color = data.position == "long" and "DiagnosticOk" or "Comment"

  local pnl_sign = pnl >= 0 and "+" or ""
  local pnl_str = pnl_sign .. "$" .. fmt(math.abs(pnl))
  local dd_str = fmt(dd_val) .. "%"
  local port_str = type(data.portfolio) == "number" and "$" .. fmt(data.portfolio) or "--"
  local price_str = type(data.price) == "number" and "$" .. fmt(data.price) or "--"
  local pos_str = data.position == "long" and "LONG" or "FLAT"
  local sharpe_str = type(data.sharpe) == "number" and string.format("%.2f", data.sharpe) or "--"
  local trades_str = type(data.trades) == "number" and tostring(data.trades) or "--"
  local return_str = type(data.return_pct) == "number" and fmt_pct(data.return_pct) or "--"
  local winrate_str = type(data.win_rate) == "number" and string.format("%.1f%%", data.win_rate) or "--"
  local progress = type(data.progress) == "number" and data.progress or 0
  local total = type(data.total) == "number" and data.total or 100

  local strat_class = type(data.strategy) == "string" and data.strategy or strategy_short_name(current_strategy_file)
  local params_str = extract_params(data)

  local title = " " .. current_ticker .. " · " .. strat_class .. " "
  if is_done then
    title = " " .. current_ticker .. " ✓ " .. pnl_str .. " "
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

  local footer
  if is_starting or (data.status == "running") then
    footer = "  [x]stop  [r]restart  [?]help  [q]close"
  elseif is_done then
    footer = "  [r]restart  [?]help  [q]close"
  else
    footer = "  [s]start  [?]help  [q]close"
  end

  local strat_line = strat_class
  if params_str ~= "" then
    strat_line = strat_line .. "  " .. params_str
  end

  local lines = {
    row("Ticker:", current_ticker),
    row("Strategy:", strat_line),
    row("Status:", status_msg),
    row("Period:", tostring(progress) .. " / " .. tostring(total) .. " bars"),
    "",
    row("PnL:", pnl_str),
    row("Portfolio:", port_str),
    row("Return:", return_str),
    row("Max DD:", dd_str),
    row("Sharpe:", sharpe_str),
    row("Win Rate:", winrate_str),
    "",
    row("Price:", price_str),
    row("Position:", pos_str),
    row("Trades:", trades_str),
    "",
    "  " .. bar .. "  " .. tostring(progress) .. "/" .. tostring(total),
    "",
    footer,
  }

  pcall(vim.api.nvim_win_set_config, win, { height = #lines })
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)

  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, pnl_color, 5, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, dd_color, 8, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, pos_color, 13, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, "Special", 16, 2, -1)
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

function M.show_help()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local help_lines = {
    "",
    "  alpha-stream.nvim Help",
    "",
    "  s           Start backtest",
    "  x           Stop running backtest",
    "  r           Restart with same params",
    "  ?           Toggle this help",
    "  q  /  <Esc> Close dashboard",
    "",
    "  :AlphaStreamRun [TICKER] [STRATEGY]",
    "  :AlphaStreamLog",
    "  :AlphaStreamEdit",
    "",
    "  Strategies:",
    "    sma_cross       MA crossover (50/200)",
    "    mean_reversion  Bollinger-style reversion",
    "    rsi_reversal    RSI oversold/overbought",
    "    /path/to/file.py    Any backtesting.py file",
    "",
    "  Press ? to close",
  }
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, help_lines)
  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
end

function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
  buf = nil
end

return M
