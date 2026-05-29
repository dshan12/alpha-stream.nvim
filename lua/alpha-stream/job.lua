local M = {}

local job_id = nil

function M.spawn(script_path, on_line, on_exit, extra_args)
  local plugin_root = vim.fn.fnamemodify(script_path, ":p:h:h")
  local venv_python = plugin_root .. "/.venv/bin/python3"
  local python_cmd = vim.fn.executable(venv_python) == 1 and venv_python or "python3"

  local cmd = { python_cmd, script_path }
  if extra_args then
    for _, arg in ipairs(extra_args) do
      table.insert(cmd, arg)
    end
  end

  job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, lines, _)
      if not lines or #lines == 0 then return end
      for i = 1, #lines do
        local line = lines[i]
        if line and #line > 0 then
          local ok, parsed = pcall(vim.json.decode, line)
          if ok and parsed then
            vim.schedule(function()
              on_line(parsed)
            end)
          end
        end
      end
    end,
    on_exit = function(_, code, _)
      job_id = nil
      if on_exit then
        vim.schedule(function()
          on_exit({ code = code, signal = 0 })
        end)
      end
    end,
    stdout_buffered = false,
  })

  if job_id == 0 or job_id == -1 then
    vim.schedule(function()
      vim.notify("alpha-stream: failed to spawn python process", vim.log.levels.ERROR)
    end)
    job_id = nil
  end
end

function M.stop()
  if job_id then
    vim.fn.jobstop(job_id)
    job_id = nil
  end
end

return M
