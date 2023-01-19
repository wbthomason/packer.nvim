-- Interface with Neovim job control and provide a simple job sequencing structure
local uv = vim.loop
local a = require 'packer.async'
local log = require 'packer.log'

local record M
  record JobResult
    exit_code: integer
    signal: integer | string
    stdout: {string}
    stderr: {string}
  end

  record Opts
    cwd: string
    timeout: integer
    env: {string}
    on_stderr: function(string)
    on_stdout: function(string)
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
      for _, pipe in pairs(options.stdio as {integer:uv.Pipe}) do
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

--- Main exposed function for the jobs module. Takes a task and options and returns an async
-- function that will run the task with the given opts via vim.loop.spawn
M.run = a.wrap(function(task: string|{string}, opts: M.Opts, callback: function(M.JobResult))
  local stdout_data: {string} = {}
  local stderr_data: {string} = {}

  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

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
    callback{
      exit_code = exit_code,
      signal = signal,
      stdout = stdout_data,
      stderr = stderr_data
    }
  end)

  for kind, pipe in pairs({ stdout = stdout, stderr = stderr } as {StdioType:vim.loop.Pipe}) do
    if pipe then
      pipe:read_start(function(err: string, data: string)
        if kind == 'stderr' and opts.on_stderr and data then
          opts.on_stderr(data)
        end
        if kind == 'stdout' and opts.on_stdout and data then
          opts.on_stdout(data)
        end
        if err then
          log.error(err)
        end
        if data ~= nil then
          local output = kind == 'stdout' and stdout_data or stderr_data
          table.insert(output, vim.trim(data))
        else
          pipe:read_stop()
          pipe:close()
        end
      end)
    end
  end

end, 3)

return M
