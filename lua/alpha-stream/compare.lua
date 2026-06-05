local M = {}

local job = require("alpha-stream.job")

local buf = nil
local win = nil
local ns = vim.api.nvim_create_namespace("alpha-stream-compare")
local stored_opts = nil
local stored_on_complete = nil
local is_running = false
local rows = {}
local total_strategies = 0
local completed_strategies = 0
local current_ticker = "SPY"
local current_strategies = {}

local W = 80

local function fmt(n)
  if type(n) ~= "number" then return "0" end
  local s = string.format("%.2f", n)
  local int, dec = s:match("^(%d+).(%d+)$")
  if not int then return s end
  local parts = {}
  while #int > 3 do
    table.insert(parts, 1, int:sub(-3))
    int = int:sub(1, -4)
  end
  table.insert(parts, 1, int)
  return table.concat(parts, ",") .. "." .. dec
end

local function fmt_pct(n)
  if type(n) ~= "number" then return "--" end
  local s = string.format("%.2f%%", n)
  if n > 0 then s = "+" .. s end
  return s
end

local function fmt_sharpe(n)
  if type(n) ~= "number" then return "--" end
  return string.format("%.2f", n)
end

local function fmt_dd(n)
  if type(n) ~= "number" then return "--" end
  return string.format("%.2f%%", n)
end

local function fmt_winrate(n)
  if type(n) ~= "number" then return "--" end
  return string.format("%.1f%%", n)
end

local function fmt_trades(n)
  if type(n) ~= "number" then return "--" end
  return tostring(math.floor(n))
end

local function fmt_money(n)
  if type(n) ~= "number" then return "--" end
  return "$" .. fmt(n)
end

local function find_row(name)
  for i, r in ipairs(rows) do
    if r.name == name then return i end
  end
  return nil
end

local function best_by_return()
  local best_idx = nil
  local best_val = nil
  for i, r in ipairs(rows) do
    if not r.error and type(r.return_pct) == "number" then
      if not best_val or r.return_pct > best_val then
        best_val = r.return_pct
        best_idx = i
      end
    end
  end
  if not best_idx and #rows > 0 then
    for i, r in ipairs(rows) do
      if not r.error and type(r.sharpe) == "number" then
        if not best_val or r.sharpe > best_val then
          best_val = r.sharpe
          best_idx = i
        end
      end
    end
  end
  return best_idx
end

local function draw()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)

  local strat_list = table.concat(current_strategies, ", ")

  local lines = {
    "  Ticker:    " .. current_ticker,
    "  Compare:   " .. strat_list,
    "  Progress:  " .. tostring(completed_strategies) .. " / " .. tostring(total_strategies) .. " strategies",
    "",
    string.format("  %-18s %10s %9s %9s %8s %7s %12s",
      "Strategy", "Return", "Sharpe", "Max DD", "Win%", "Trades", "Final $"),
    string.rep("─", 76),
  }

  for i, r in ipairs(rows) do
    local line
    if r.error then
      line = string.format("  %-18s  ERROR: %s",
        r.name:sub(1, 18), tostring(r.error):sub(1, 50))
    else
      line = string.format("  %-18s %10s %9s %9s %8s %7s %12s",
        r.name:sub(1, 18),
        fmt_pct(r.return_pct),
        fmt_sharpe(r.sharpe),
        fmt_dd(r.max_dd),
        fmt_winrate(r.win_rate),
        fmt_trades(r.trades),
        fmt_money(r.equity_final))
    end
    table.insert(lines, line)
  end

  if #rows == 0 then
    table.insert(lines, "  (waiting for first strategy to finish...)")
  end

  table.insert(lines, "")

  local best_idx = best_by_return()
  if best_idx then
    local b = rows[best_idx]
    table.insert(lines, "  Best: " .. b.name .. " (Return)")
  end

  table.insert(lines, "")

  local footer
  if is_running then
    footer = "  [?]help  [q]close"
  else
    footer = "  [r]rerun  [?]help  [q]close"
  end
  table.insert(lines, footer)

  pcall(vim.api.nvim_win_set_config, win, { height = #lines })
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)

  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  if best_idx then
    local data_row_line = 6 + best_idx - 1
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, "DiagnosticOk", data_row_line, 0, -1)
  end
end

local function show_help()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local help_lines = {
    "",
    "  alpha-stream: compare Help",
    "",
    "  r           Rerun this comparison",
    "  ?           Toggle this help",
    "  q  /  <Esc> Close dashboard",
    "",
    "  :AlphaStreamCompare TICKER STRAT1 STRAT2 [STRAT3 ...]",
    "",
    "  Example:",
    "    :AlphaStreamCompare AAPL sma_cross mean_reversion rsi_reversal",
    "",
    "  Press ? to close",
  }
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, help_lines)
  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
end

local function setup_window(title)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_set_current_win, win)
    return
  end

  local ui_state = vim.api.nvim_list_uis()[1]
  if not ui_state then return end

  buf = vim.api.nvim_create_buf(false, true)
  local height = 14
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
    title = " " .. title .. " ",
    title_pos = "center",
  })

  vim.wo[win].winhighlight = "Normal:Normal"

  vim.keymap.set("n", "q", function() M.close() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "?", function() show_help() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "r", function()
    if stored_opts and not is_running then
      M.run(stored_opts, stored_on_complete)
    end
  end, { buffer = buf, nowait = true, silent = true })
end

function M.run(opts, on_complete)
  opts = opts or {}
  stored_opts = opts
  stored_on_complete = on_complete

  rows = {}
  completed_strategies = 0
  total_strategies = 0
  current_ticker = type(opts.ticker) == "string" and opts.ticker or "SPY"
  current_strategies = type(opts.strategies) == "table" and opts.strategies or {}

  for _, s in ipairs(current_strategies) do
    table.insert(rows, { name = s })
  end

  local title = "α-stream: " .. current_ticker .. " · compare"
  setup_window(title)

  is_running = true
  draw()

  local src = debug.getinfo(1, "S").source:match("@?(.*/)")
  if not src then
    M.show_error("Could not locate plugin root")
    return
  end
  local root = vim.fn.fnamemodify(src, ":p:h:h:h")
  local script = root .. "/python/engine.py"

  local extra_args = { "--mode", "compare", "--ticker", current_ticker }
  for _, s in ipairs(current_strategies) do
    table.insert(extra_args, "--strategies")
    table.insert(extra_args, s)
  end

  if opts.cash then
    table.insert(extra_args, "--cash")
    table.insert(extra_args, tostring(opts.cash))
  end
  if opts.commission then
    table.insert(extra_args, "--commission")
    table.insert(extra_args, tostring(opts.commission))
  end

  local started = job.spawn(script, function(data)
    if data.status == "starting" then
      total_strategies = type(data.strategies) == "table" and #data.strategies or total_strategies
      if type(data.strategies) == "table" then
        rows = {}
        for _, s in ipairs(data.strategies) do
          table.insert(rows, { name = s })
        end
      end
      draw()
    elseif data.status == "running" then
      completed_strategies = type(data.strategy_idx) == "number" and data.strategy_idx or completed_strategies
      local name = type(data.strategy) == "string" and data.strategy or nil
      if name then
        local idx = find_row(name)
        if not idx then
          table.insert(rows, { name = name })
          idx = #rows
        end
        if data.error then
          rows[idx].error = data.error
        else
          rows[idx].return_pct = data.return_pct
          rows[idx].sharpe = data.sharpe
          rows[idx].max_dd = data.max_dd
          rows[idx].win_rate = data.win_rate
          rows[idx].trades = data.trades
          rows[idx].equity_final = data.equity_final
        end
        draw()
      end
    elseif data.status == "done" then
      is_running = false
      if type(data.results) == "table" then
        for _, r in ipairs(data.results) do
          local name = r.strategy
          if name then
            local idx = find_row(name)
            if not idx then
              table.insert(rows, { name = name })
              idx = #rows
            end
            if r.error then
              rows[idx].error = r.error
            else
              rows[idx].return_pct = r.return_pct
              rows[idx].sharpe = r.sharpe
              rows[idx].max_dd = r.max_dd
              rows[idx].win_rate = r.win_rate
              rows[idx].trades = r.trades
              rows[idx].equity_final = r.equity_final
            end
          end
        end
      end
      draw()
      if on_complete then pcall(on_complete, data) end
    elseif data.status == "error" then
      is_running = false
      M.show_error(tostring(data.error_msg or "unknown error"))
    end
  end, function(result)
    is_running = false
    local code = result and result.code or -1
    if code ~= 0 then
      M.show_error("Process exited with code " .. code)
    end
  end, extra_args)

  if not started then
    is_running = false
    M.show_error("Failed to spawn Python process")
  end
end

function M.update(data)
  if type(data) ~= "table" then return end
  if data.status == "starting" and type(data.strategies) == "table" then
    total_strategies = #data.strategies
  elseif data.status == "running" then
    completed_strategies = type(data.strategy_idx) == "number" and data.strategy_idx or completed_strategies
  end
  draw()
end

function M.show_error(msg)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    setup_window("α-stream: compare · error")
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local lines = { "", "  ERROR", "", "  " .. tostring(msg), "", "  q to close" }
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
  pcall(vim.api.nvim_win_set_config, win, { height = #lines })
  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, "DiagnosticError", 1, 2, -1)
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, "Comment", 5, 0, -1)
end

function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  win = nil
  buf = nil
end

function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

return M
