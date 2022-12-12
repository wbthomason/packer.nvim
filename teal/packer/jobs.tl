-- Interface with Neovim job control and provide a simple job sequencing structure
local uv = vim.loop
local a = require 'packer.async'
local log = require 'packer.log'

local record M
  record JobOutput
    record E
      stdout: {string}
      stderr: {string}
    end

    data: E
    err: E
  end

  record JobResult
    exit_code: integer
    signal: integer | string
    output: JobOutput

    ok: function(JobResult): boolean
  end

  record Opts
    cwd: string
    timeout: integer
    env: {string}
  end

  run: function(task: string|{string}, opts: M.Opts): M.JobResult
end

local function trace(cmd: string, options: uv.SpawnOpts)
  log.fmt_trace(
    "Running job: cmd = %s, args = %s, cwd = %s",
    cmd,
    vim.inspect(options.args),
    options.cwd
  )
end

--- Wrapper for vim.loop.spawn. Takes a command, options, and callback just like
--- vim.loop.spawn, but ensures that all output from the command has been
--- flushed before calling the callback.
local function spawn(cmd: string, options: uv.SpawnOpts, callback: function(integer, string))
  local handle = nil as uv.Process
  local timer = nil as uv.Timer
  trace(cmd, options)
  handle = uv.spawn(cmd, options, function(exit_code: integer, signal: string)
    handle:close()
    if timer then
      timer:stop()
      timer:close()
    end

    local check = uv.new_check()
    assert(check)
    check:start(function()
      for _, pipe in ipairs(options.stdio) do
        if not pipe:is_closing() then
          return
        end
      end
      check:stop()
      callback(exit_code, signal)
    end)
  end)

  local timeout = (options as table).timeout as integer

  if timeout then
    timer = uv.new_timer()
    timer:start(timeout, 0, function()
      timer:stop()
      timer:close()
      if handle and handle:is_active() then
        log.warn('Killing ' .. cmd .. ' due to timeout!')
        handle:kill('sigint')
        handle:close()
        for _, pipe in ipairs(options.stdio) do
          pipe:close()
        end
        callback(-9999, 'sigint')
      end
    end)
  end
end

local enum StdioType
  'stdout'
  'stderr'
end

local record StdioCallbacks
  stdout: function(string, string)
  stderr: function(string, string)
end

local function setup_pipe(kind: StdioType, callbacks: StdioCallbacks, output: M.JobOutput): string | uv.Pipe
  local handle, uv_err = uv.new_pipe(false)
  if uv_err then
    log.error(string.format('Failed to open %s pipe: %s', kind, uv_err))
    return uv_err
  end

  callbacks[kind] = function(err: string, data: string)
    if err then
      table.insert(output.err[kind], vim.trim(err))
    end
    if data ~= nil then
      local trimmed = vim.trim(data)
      table.insert(output.data[kind], trimmed)
    end
  end

  return handle
end

local function job_ok(self: M.JobResult): boolean
  return self.exit_code == 0
end

--- Main exposed function for the jobs module. Takes a task and options and returns an async
-- function that will run the task with the given opts via vim.loop.spawn
M.run = a.wrap(function(task: string|{string}, opts: M.Opts, callback: function(M.JobResult))
  local job_result: M.JobResult = {
    exit_code = -1,
    signal = -1,
    ok = job_ok
  }

  local output = {
    err  = { stdout = {}, stderr = {} },
    data = { stdout = {}, stderr = {} }
  }
  local callbacks = {}

  local stdout = setup_pipe('stdout', callbacks, output)

  if stdout is string then
    callback(job_result)
    return
  end

  stdout = stdout as uv.Pipe

  local stderr = setup_pipe('stderr', callbacks, output)

  if stderr is string then
    callback(job_result)
    return
  end

  stderr = stderr as uv.Pipe

  if task is string then
    local shell = os.getenv 'SHELL' or vim.o.shell
    local minus_c = shell:find 'cmd.exe$' and '/c' or '-c'
    task = { shell, minus_c, task }
  end

  task = task as {string}

  spawn(task[1], {
    args    = { unpack(task, 2) },
    stdio   = { nil, stdout, stderr },
    cwd     = opts.cwd,
    timeout = opts.timeout and 1000 * opts.timeout or nil,
    env     = opts.env,
    hide    = true
  }, function(exit_code: integer, signal: string)
    job_result.exit_code = exit_code
    job_result.signal = signal
    job_result.output = output
    callback(job_result)
  end)

  for kind, pipe in pairs({ stdout = stdout, stderr = stderr } as {StdioType:vim.loop.Pipe}) do
    if pipe and callbacks[kind] then
      pipe:read_start(function(err: string, data: string)
        if data then
          callbacks[kind](err, data)
        else
          pipe:read_stop()
          pipe:close()
        end
      end)
    end
  end

end, 3)

return M
