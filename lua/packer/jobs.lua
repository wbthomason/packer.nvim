-- Interface with Neovim job control and provide a simple job sequencing structure
local loop = vim.loop
local split = vim.split
local trim = vim.trim

local a = require('packer.async')
local await = a.wait

local log = require('packer.log')

local function output_callback(err, data, dest)
  if err then
    dest.err_count = dest.err_count + 1
    dest.err[dest.err_count] = trim(err)
  end

  if data then
    local trimmed = trim(data)
    dest.data_count = dest.data_count + 1
    dest.data[dest.data_count] = trimmed
    if dest.disp then dest.disp:task_update(dest.task_name, split(trimmed, '\n')[1]) end
  else
    loop.read_stop(dest.pipe)
    loop.close(dest.pipe)
  end
end

local function make_output_struct(data_tbl, err_tbl, pipe, task_name, disp)
  return {
    data = data_tbl,
    data_count = 0,
    err = err_tbl,
    err_count = 0,
    pipe = pipe,
    disp = disp,
    task_name = task_name
  }
end

--- Utility function to make a table for capturing output with "standard" structure
local function make_output_table() return {err = {}, data = {}} end

local function init_output(pipe, task_name, disp)
  local output_tables = make_output_table()
  return make_output_struct(output_tables.data, output_tables.err, pipe, task_name, disp)
end

local function check_for_closed_pipes(pipes, check, cb, exit_code, signal)
  for i = 1, #pipes do
    if not loop.is_closing(pipes[i]) then return end
    loop.check_stop(check)
    cb(exit_code, signal)
  end
end

local function job_cleanup(job, signal, exit_code)
  job.handle:close()
  if job.timer then
    job.timer:stop()
    job.timer:close()
  end

  local opts = job.options
  local pipes_closed_check = loop.new_check()
  local function check_fn()
    check_for_closed_pipes(opts.stdio, pipes_closed_check, job.cb, exit_code, signal)
  end

  loop.check_start(pipes_closed_check, check_fn)
end

local function timer_cleanup(job)
  job.timer:stop()
  job.timer:close()
  local handle = job.handle
  if loop.is_active(handle) then
    log.warn('Killing ' .. job.cmd .. ' due to timeout!')
    loop.process_kill(handle, 'sigint')
    handle:close()
    local pipes = job.opts.stdio
    for i = 1, #pipes do loop.close(pipes[i]) end
    job.cb(-9999, 'sigint')
  end
end

local function spawn_job(cmd, options, async_cb)
  local job = {handle = nil, timer = nil, opts = options, cb = async_cb, cmd = cmd}
  local function job_fn(exit_code, signal) job_cleanup(job, exit_code, signal) end
  job.handle = loop.spawn(cmd, options, job_fn)
  if options.stdio then
    local pipes = options.stdio
    local output_dests = options.output_dests
    for i = 1, #pipes do
      if pipes[i] then
        local function pipe_callback(err, data) output_callback(err, data, output_dests[i]) end
        loop.read_start(pipes[i], pipe_callback)
      end
    end
  end

  if options.timeout then
    job.timer = loop.new_timer()
    local function timer_fn() timer_cleanup(job) end
    job.timer:start(options.timeout, 0, timer_fn)
  end
end

local spawn = a.wrap(spawn_job)

--- Utility function to perform a common check for process success
local function was_successful(job_result)
  if job_result.exit_code == 0 then
    local output_dests = job_result.output
    for i = 1, 3 do if output_dests[i] and #output_dests[i].err > 0 then error(job_result) end end
    return job_result
  end

  error(job_result)
end

local DEFAULT_OPTIONS = {hide = true}
local TASK_SPLIT_PATTERN = '%s+'
local function run_job(task, opts, async_cb)
  local options = opts.options or DEFAULT_OPTIONS
  local stdout = nil
  local stderr = nil
  local output_dests = {false, false, false}
  local success_test = opts.success_test or was_successful
  local uv_err
  if opts.capture_output or opts.stdout then
    stdout, uv_err = loop.new_pipe(false)
    if uv_err then
      log.error('Failed to open stdout pipe for ' .. vim.inspect(task) .. ': ' .. uv_err)
      error(uv_err)
    end
  end

  if opts.capture_output or opts.stderr then
    stderr, uv_err = loop.new_pipe(false)
    if uv_err then
      log.error('Failed to open stderr pipe for ' .. vim.inspect(task) .. ': ' .. uv_err)
      error(uv_err)
    end
  end

  if opts.capture_output then
    output_dests[2] = init_output(stdout, opts.task_name, opts.disp)
    output_dests[3] = init_output(stderr, opts.task_name, opts.disp)
  end

  if opts.stdout then
    output_dests[2] = make_output_struct(opts.stdout.data, opts.stdout.err, stdout, opts.task_name,
                                         opts.disp)
  end

  if opts.stderr then
    output_dests[3] = make_output_struct(opts.stderr.data, opts.stderr.err, stderr, opts.task_name,
                                         opts.disp)
  end

  if type(task) == 'string' then task = split(task, TASK_SPLIT_PATTERN) end

  local cmd = task[1]
  if opts.timeout then options.timeout = 1000 * opts.timeout end
  options.args = {unpack(task, 2)}
  options.stdio = {nil, stdout, stderr}
  options.output_dests = output_dests

  local exit_code, signal = await(spawn(cmd, options))
  local job_result = {task = task, exit_code = exit_code, signal = signal, output = output_dests}
  async_cb(success_test(job_result))
end

local jobs = {run = a.wrap(run_job), init_output = init_output}
return jobs
