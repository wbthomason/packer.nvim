-- Interface with Neovim job control and provide a simple job sequencing structure
local split  = vim.split
local loop   = vim.loop
local a      = require('packer/async')
local log    = require('packer/log')
local result = require('packer/result')

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

local function make_output_table()
  return {
    err = {
      stdout = {},
      stderr = {}
    },
    data = {
      stdout = {},
      stderr = {}
    }
  }
end

local function extend_output(to, from)
  to.stdout = vim.list_extend(to.stdout, from.stdout)
  to.stderr = vim.list_extend(to.stderr, from.stderr)
  return to
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

local function was_successful(r)
  if
    r.exit_code == 0
    and (not r.output or not r.output.err or #r.output.err == 0)
  then
    return result.ok(r)
  else
    return result.err(r)
  end
end

local run_job = function(task, opts)
  return a.sync(
    function()
      local options = opts.options or { hide = true }
      local stdout = nil
      local stderr = nil
      local job_result = { exit_code = -1, signal = -1 }
      local success_test = opts.success_test or was_successful
      local uv_err
      local output = make_output_table()
      local callbacks = {}
      local output_valid = false
      if opts.capture_output then
        if type(opts.capture_output) == 'boolean' then
          stdout, uv_err = loop.new_pipe(false)
          if uv_err then
            log.error('Failed to open stdout pipe: ' .. uv_err)
            return result.err()
          end

          stderr, uv_err = loop.new_pipe(false)
          if uv_err then
            log.error('Failed to open stderr pipe: ' .. uv_err)
            return job_result
          end

          callbacks.stdout = make_logging_callback(output.err, output.data, stdout)
          callbacks.stderr = make_logging_callback(output.err, output.data, stderr)
          output_valid = true
        elseif type(opts.capture_output) == 'table' then
          if opts.capture_output.stdout then
            stdout, uv_err = loop.new_pipe(false)
            if uv_err then
              log.error('Failed to open stdout pipe: ' .. uv_err)
              return job_result
            end

            callbacks.stdout = function(err, data)
              if data ~= nil then
                opts.capture_output.stdout(err, data)
              else
                loop.read_stop(stdout)
                loop.close(stdout)
              end
            end
          end
          if opts.capture_output.stderr then
            stderr, uv_err = loop.new_pipe(false)
            if uv_err then
              log.error('Failed to open stderr pipe: ' .. uv_err)
              return job_result
            end

            callbacks.stderr = function(err, data)
              if data ~= nil then
                opts.capture_output.stderr(err, data)
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
      job_result = { exit_code = exit_code, signal = signal }

      if output_valid then
        job_result.output = output
      end

      return success_test(job_result)
    end)
end

local jobs = {
  run = run_job,
  logging_callback = make_logging_callback,
  output_table = make_output_table,
  extend_output = extend_output
}

return jobs
