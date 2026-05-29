local M = {}

local active_job = nil
local stdout_buf = ""
local timer = nil

function M.spawn(script_path, on_line, on_exit, extra_args)
  stdout_buf = ""

  local plugin_root = vim.fn.fnamemodify(script_path, ":p:h:h")
  local venv_python = plugin_root .. "/.venv/bin/python3"
  local python_cmd = vim.fn.executable(venv_python) == 1 and venv_python or "python3"
  local cmd = { python_cmd, script_path }
  if extra_args then
    for _, arg in ipairs(extra_args) do
      table.insert(cmd, arg)
    end
  end

  active_job = vim.system(cmd, {
    stdout = true,
    stderr = true,
  }, function(result)
    active_job = nil
    if on_exit then
      vim.schedule(function()
        on_exit(result)
      end)
    end
  end)

  if not active_job then
    vim.schedule(function()
      vim.notify("alpha-stream: failed to spawn python process", vim.log.levels.ERROR)
    end)
    return
  end

  local function read_stdout()
    if not active_job then
      return
    end
    local data = active_job:stdout_read(4096)
    if data and #data > 0 then
      stdout_buf = stdout_buf .. data
      local lines = {}
      for segment in stdout_buf:gmatch("([^\n]+)") do
        table.insert(lines, segment)
      end
      stdout_buf = lines[#lines] or ""
      for i = 1, #lines - 1 do
        local line = lines[i]
        if line and #line > 0 then
          vim.schedule(function()
            local ok, parsed = pcall(vim.json.decode, line)
            if ok and parsed then
              on_line(parsed)
            end
          end)
        end
      end
    end
  end

  local uv = vim.uv or vim.loop
  timer = uv.new_timer()
  timer:start(10, 50, function()
    vim.schedule(function()
      if active_job then
        read_stdout()
      else
        if timer then
          timer:stop()
          timer:close()
          timer = nil
        end
      end
    end)
  end)
end

function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  if active_job then
    active_job:kill("sigterm")
    active_job = nil
  end
end

return M
