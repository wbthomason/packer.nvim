
local uv = vim.loop
local a = require('packer.async')
local log = require('packer.log')

local M = {JobOutput = {E = {}, }, JobResult = {}, Opts = {}, }



























local function trace(cmd, options)
   log.fmt_trace(
   "Running job: cmd = %s, args = %s, cwd = %s",
   cmd,
   vim.inspect(options.args),
   options.cwd)

end




local function spawn(cmd, options, callback)
   local handle = nil
   local timer = nil
   trace(cmd, options)
   handle = uv.spawn(cmd, options, function(exit_code, signal)
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

   local timeout = (options).timeout

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











local function setup_pipe(kind, callbacks, output)
   local handle, uv_err = uv.new_pipe(false)
   if uv_err then
      log.error(string.format('Failed to open %s pipe: %s', kind, uv_err))
      return uv_err
   end

   callbacks[kind] = function(err, data)
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

local function job_ok(self)
   return self.exit_code == 0
end



M.run = a.wrap(function(task, opts, callback)
   local job_result = {
      exit_code = -1,
      signal = -1,
      ok = job_ok,
   }

   local output = {
      err = { stdout = {}, stderr = {} },
      data = { stdout = {}, stderr = {} },
   }
   local callbacks = {}

   local stdout = setup_pipe('stdout', callbacks, output)

   if type(stdout) == "string" then
      callback(job_result)
      return
   end

   stdout = stdout

   local stderr = setup_pipe('stderr', callbacks, output)

   if type(stderr) == "string" then
      callback(job_result)
      return
   end

   stderr = stderr

   if type(task) == "string" then
      local shell = os.getenv('SHELL') or vim.o.shell
      local minus_c = shell:find('cmd.exe$') and '/c' or '-c'
      task = { shell, minus_c, task }
   end

   task = task

   spawn(task[1], {
      args = { unpack(task, 2) },
      stdio = { nil, stdout, stderr },
      cwd = opts.cwd,
      timeout = opts.timeout and 1000 * opts.timeout or nil,
      env = opts.env,
      hide = true,
   }, function(exit_code, signal)
      job_result.exit_code = exit_code
      job_result.signal = signal
      job_result.output = output
      callback(job_result)
   end)

   for kind, pipe in pairs({ stdout = stdout, stderr = stderr }) do
      if pipe and callbacks[kind] then
         pipe:read_start(function(err, data)
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