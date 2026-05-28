local ui = require("alpha-stream.ui")
local job = require("alpha-stream.job")

local M = {}
local running = false

local engine_path = debug.getinfo(1, "S").source:match("@?(.*/)")
  or vim.fn.stdpath("data") .. "/alpha-stream/"

function M.start()
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

  local script = vim.fn.fnamemodify(engine_path .. "../../python/engine.py", ":p")

  job.spawn(script, function(data)
    ui.update_dashboard(data)
  end, function(result)
    running = false
    local code = result and result.code or -1
    if code ~= 0 then
      ui.show_error("Process exited with code " .. code)
      vim.notify("alpha-stream: process exited with code " .. code, vim.log.levels.ERROR)
    end
  end)
end

function M.stop()
  job.stop()
  running = false
  ui.close()
end

return M
