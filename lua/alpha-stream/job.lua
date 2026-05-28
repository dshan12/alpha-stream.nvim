local M = {}

local job = nil
local stdout_buf = ""

function M.spawn(script_path, on_line, on_exit)
  stdout_buf = ""

  local plugin_root = vim.fn.fnamemodify(script_path, ":h:h")
  local venv_python = plugin_root .. "/.venv/bin/python3"
  local python_cmd = vim.fn.executable(venv_python) == 1 and venv_python or "python3"
  local cmd = { python_cmd, script_path }

  job = vim.system(cmd, {
    stdout = true,
    stderr = true,
  }, function(exit_code)
    job = nil
    if on_exit then
      vim.schedule(function()
        on_exit(exit_code)
      end)
    end
  end)

  if not job then
    vim.schedule(function()
      vim.notify("alpha-stream: failed to spawn python process", vim.log.levels.ERROR)
    end)
    return
  end

  local function read_stdout()
    if not job then
      return
    end
    local data = job:stdout_read(4096)
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
  local timer = uv.new_timer()
  timer:start(10, 50, function()
    vim.schedule(function()
      if job then
        read_stdout()
      else
        timer:stop()
        timer:close()
      end
    end)
  end)
end

function M.stop()
  if job then
    job:kill("sigterm")
    job = nil
  end
end

return M
