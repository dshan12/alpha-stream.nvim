local M = {}

local job = require("alpha-stream.job")

local buf = nil
local win = nil
local ns = vim.api.nvim_create_namespace("alpha-stream-sweep")

local stored_opts = nil
local stored_on_complete = nil
local is_running = false
local results = {}
local best_so_far = nil
local total_combos = 0
local completed_combos = 0
local current_ticker = "SPY"
local current_strategy = ""
local current_params_grid = {}

local W = 76

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

local function fmt_param_value(v)
  if type(v) == "number" and v == math.floor(v) then
    return tostring(math.floor(v))
  elseif type(v) == "number" then
    return string.format("%.2f", v)
  end
  return tostring(v)
end

local function format_params(params)
  if type(params) ~= "table" then return "" end
  local parts = {}
  for k, v in pairs(params) do
    table.insert(parts, k .. "=" .. fmt_param_value(v))
  end
  table.sort(parts)
  return table.concat(parts, "  ")
end

local function grid_to_str(grid)
  local parts = {}
  for _, k in ipairs(grid) do
    table.insert(parts, k)
  end
  return table.concat(parts, "  ")
end

local function is_better(a, b)
  if not b then return true end
  if not a then return false end
  local a_sharpe = a.sharpe
  local b_sharpe = b.sharpe
  if type(a_sharpe) ~= "number" then return false end
  if type(b_sharpe) ~= "number" then return true end
  return a_sharpe > b_sharpe
end

local function row(label, value)
  return string.format("  %-14s %s", label, value)
end

local function close_win()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  win = nil
  buf = nil
end

function M.close()
  close_win()
end

function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function draw()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)

  local sorted = {}
  for _, r in ipairs(results) do
    if not r.error then
      table.insert(sorted, r)
    end
  end
  table.sort(sorted, function(a, b)
    local a_sharpe = type(a.sharpe) == "number" and a.sharpe or -math.huge
    local b_sharpe = type(b.sharpe) == "number" and b.sharpe or -math.huge
    return a_sharpe > b_sharpe
  end)

  local show_n = math.min(10, #sorted)
  local best_str = "  (none yet)"
  if best_so_far then
    local ps = format_params(best_so_far.params)
    best_str = "  " .. ps .. "  ->  Sharpe " .. fmt_sharpe(best_so_far.sharpe)
      .. ", " .. fmt_pct(best_so_far.return_pct)
  end

  local lines = {
    row("Ticker:", current_ticker),
    row("Strategy:", current_strategy),
    row("Sweeping:", grid_to_str(current_params_grid)),
    row("Progress:", tostring(completed_combos) .. " / " .. tostring(total_combos) .. " combos"),
    "",
    row("Best so far:", best_str),
    "",
    "  Top results (sorted by Sharpe):",
  }

  if show_n == 0 then
    table.insert(lines, "    (waiting for first combo to finish...)")
  else
    for i = 1, show_n do
      local r = sorted[i]
      local ps = format_params(r.params) or ""
      if #ps > 28 then ps = ps:sub(1, 25) .. "..." end
      local line = string.format("  %2d. %-28s  %8s  Sharpe %6s  DD %7s  %d trades",
        i, ps, fmt_pct(r.return_pct), fmt_sharpe(r.sharpe), fmt_dd(r.max_dd), r.trades or 0)
      table.insert(lines, line)
    end
  end

  if #sorted > show_n then
    table.insert(lines, "    ... and " .. (#sorted - show_n) .. " more")
  end

  local failed = completed_combos - #sorted
  if failed > 0 then
    table.insert(lines, "    " .. failed .. " combos failed")
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

  for i = 1, show_n do
    if sorted[i] and best_so_far and sorted[i].params and best_so_far.params then
      local a_key = table.concat(vim.tbl_values(sorted[i].params), ",")
      local b_key = table.concat(vim.tbl_values(best_so_far.params), ",")
      if a_key == b_key then
        pcall(vim.api.nvim_buf_add_highlight, buf, ns, "DiagnosticOk", 9 + i - 1, 0, -1)
      end
    end
  end
end

local function show_help()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local help_lines = {
    "",
    "  alpha-stream: sweep Help",
    "",
    "  r           Rerun this sweep",
    "  ?           Toggle this help",
    "  q  /  <Esc> Close dashboard",
    "",
    "  :AlphaStreamSweep TICKER STRATEGY param1=v1,v2 param2=v1,v2",
    "",
    "  Example:",
    "    :AlphaStreamSweep SPY sma_cross fast=10,20,50 slow=100,200",
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
    title = " " .. title .. " ",
    title_pos = "center",
  })

  vim.wo[win].winhighlight = "Normal:Normal"

  vim.keymap.set("n", "q", function() close_win() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function() close_win() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "?", function() show_help() end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "r", function()
    if not is_running and stored_opts then
      M.run(stored_opts, stored_on_complete)
    end
  end, { buffer = buf, nowait = true, silent = true })
end

local function rerun()
  if not stored_opts then return end
  if is_running then return end
  results = {}
  best_so_far = nil
  completed_combos = 0
  total_combos = 0
  M.run(stored_opts, stored_on_complete)
end

function M.run(opts, on_complete)
  opts = opts or {}
  stored_opts = opts
  stored_on_complete = on_complete

  results = {}
  best_so_far = nil
  completed_combos = 0
  total_combos = 0

  current_ticker = type(opts.ticker) == "string" and opts.ticker or "SPY"
  current_strategy = type(opts.strategy) == "string" and opts.strategy or ""
  current_params_grid = type(opts.grid) == "table" and opts.grid or {}

  local title = "α-stream: " .. current_ticker .. " · " .. current_strategy .. " · sweep"
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

  local extra_args = { "--mode", "sweep", "--ticker", current_ticker }
  if current_strategy:match("%.py$") or current_strategy:match("[/\\]") then
    table.insert(extra_args, "--strategy-file")
  else
    table.insert(extra_args, "--strategy")
  end
  table.insert(extra_args, current_strategy)

  for _, spec in ipairs(current_params_grid) do
    table.insert(extra_args, "--param")
    table.insert(extra_args, spec)
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
      total_combos = type(data.total_combos) == "number" and data.total_combos or 0
      if type(data.params) == "table" and #current_params_grid == 0 then
        current_params_grid = data.params
      end
      draw()
    elseif data.status == "running" then
      completed_combos = type(data.combo_idx) == "number" and data.combo_idx or completed_combos
      if type(data.params) == "table" then
        local rec = {
          params = data.params,
          return_pct = data.return_pct,
          sharpe = data.sharpe,
          max_dd = data.max_dd,
          win_rate = data.win_rate,
          trades = data.trades,
        }
        if data.error then
          rec.error = data.error
        else
          table.insert(results, rec)
          if is_better(rec, best_so_far) then
            best_so_far = rec
          end
        end
        draw()
      end
    elseif data.status == "done" then
      is_running = false
      if type(data.results) == "table" then
        results = {}
        for _, r in ipairs(data.results) do
          if not r.error then
            table.insert(results, r)
          end
        end
        best_so_far = data.best
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
  if data.status == "starting" then
    total_combos = type(data.total_combos) == "number" and data.total_combos or 0
  elseif data.status == "running" then
    completed_combos = type(data.combo_idx) == "number" and data.combo_idx or completed_combos
  end
  draw()
end

function M.show_error(msg)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    setup_window("α-stream: sweep · error")
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local lines = { "", "  ERROR", "", "  " .. tostring(msg), "", "  q to close" }
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
  pcall(vim.api.nvim_win_set_config, win, { height = #lines })
  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, "DiagnosticError", 1, 2, -1)
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, "Comment", 5, 0, -1)
end

return M
