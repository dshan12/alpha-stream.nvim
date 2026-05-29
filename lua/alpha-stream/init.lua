local ui = require("alpha-stream.ui")
local job = require("alpha-stream.job")

local M = {}
local running = false
local current_ticker = "SPY"

local function get_plugin_root()
  local src = debug.getinfo(1, "S").source:match("@?(.*/)")
  if src then
    return vim.fn.fnamemodify(src, ":p:h:h:h")
  end
  return vim.fn.stdpath("data") .. "/alpha-stream/"
end

ui.set_restart_callback(function()
  M.restart()
end)

function M.start(opts)
  opts = opts or {}
  current_ticker = opts.ticker or "SPY"

  if running then
    vim.notify("alpha-stream: already running", vim.log.levels.WARN)
    return
  end

  running = true
  ui.open()
  ui.update_dashboard({
    progress = 0,
    pnl = 0,
    drawdown = 0,
    portfolio = 10000,
    price = 0,
    fast_ma = nil,
    slow_ma = nil,
    position = "flat",
    sparkline = "",
    status = "starting",
  })

  local root = get_plugin_root()
  local script = root .. "/python/engine.py"
  local extra_args = { "--ticker", current_ticker }

  local ok, err = pcall(function()
    job.spawn(script, function(data)
      ui.update_dashboard(data)
    end, function(result)
      running = false
      local code = result and result.code or -1
      if code ~= 0 then
        ui.show_error("Process exited with code " .. code)
        vim.notify("alpha-stream: process exited with code " .. code, vim.log.levels.ERROR)
      end
    end, extra_args)
  end)

  if not ok then
    running = false
    ui.show_error(tostring(err))
    vim.notify("alpha-stream: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.stop()
  job.stop()
  running = false
  ui.close()
end

function M.restart()
  M.stop()
  vim.defer_fn(function()
    M.start({ ticker = current_ticker })
  end, 150)
end

return M
