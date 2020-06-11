-- Interface with Neovim job control and provide a simple job sequencing structure
local split = vim.split
local loop  = vim.loop
local a     = require('packer/async')
local log   = require('packer/log')

local function make_logging_callback(err_tbl, data_tbl, pipe)
  return function(err, data)
    if err then
      table.insert(err_tbl, vim.trim(err))
    end

    if data ~= nil then
      table.insert(data_tbl, vim.trim(data))
    else
      loop.read_stop(pipe)
      loop.close(pipe)
    end
  end
end

local spawn = a.wrap(function(cmd, options, callback)
  local handle = nil
  handle = loop.spawn(
    cmd,
    options,
    function(exit_code, signal)
      handle:close()
      local check = loop.new_check()
      loop.check_start(check, function()
        for _, pipe in pairs(options.stdio) do
          if not loop.is_closing(pipe) then
            return
          end
        end

        loop.check_stop(check)
        callback(exit_code, signal)
      end)
    end)

  if options.stdio then
    for i, pipe in pairs(options.stdio) do
      loop.read_start(pipe, options.stdio_callbacks[i])
    end
  end
end)

local run_job = function(task, capture_output, options)
  return a.sync(
    function()
      options = options or { hide = true }
      local stdout = nil
      local stderr = nil
      local result = { exit_code = -1, signal = -1 }
      local uv_err
      local output = { err = {}, data = {} }
      local callbacks = {}
      local output_valid = false
      if capture_output then
        if type(capture_output) == 'boolean' then
          stdout, uv_err = loop.new_pipe(false)
          if uv_err then
            log.error('Failed to open stdout pipe: ' .. uv_err)
            return result
          end

          stderr, uv_err = loop.new_pipe(false)
          if uv_err then
            log.error('Failed to open stderr pipe: ' .. uv_err)
            return result
          end

          callbacks.stdout = make_logging_callback(output.err, output.data, stdout)
          callbacks.stderr = make_logging_callback(output.err, output.data, stderr)
          output_valid = true
        elseif type(capture_output) == 'table' then
          if capture_output.stdout then
            stdout, uv_err = loop.new_pipe(false)
            if uv_err then
              log.error('Failed to open stdout pipe: ' .. uv_err)
              return result
            end

            callbacks.stdout = function(err, data)
              if data ~= nil then
                capture_output.stdout(err, data)
              else
                loop.read_stop(stdout)
                loop.close(stdout)
              end
            end
          end
          if capture_output.stderr then
            stderr, uv_err = loop.new_pipe(false)
            if uv_err then
              log.error('Failed to open stderr pipe: ' .. uv_err)
              return result
            end

            callbacks.stderr = function(err, data)
              if data ~= nil then
                capture_output.stderr(err, data)
              else
                loop.read_stop(stderr)
                loop.close(stderr)
              end
            end
          end
        end
      end

      if type(task) == 'string' then
        local split_pattern = '%s+'
        task = split(task, split_pattern)
      end

      local cmd = task[1]
      options.args = { unpack(task, 2) }
      options.stdio = { nil, stdout, stderr }
      options.stdio_callbacks = { nil, callbacks.stdout, callbacks.stderr }

      local exit_code, signal = a.wait(spawn(cmd, options))
      result = { exit_code = exit_code, signal = signal }

      if output_valid then
        result.output = output
      end

      return result
    end)
end

local jobs = {
  run = run_job,
  make_logging_callback = make_logging_callback
}

return jobs
