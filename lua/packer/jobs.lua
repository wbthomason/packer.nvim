
local uv = vim.loop
local a = require('packer.async')
local log = require('packer.log')

local M = {JobResult = {}, Opts = {}, }


















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
         for _, pipe in pairs(options.stdio) do
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








M.run = a.wrap(function(task, opts, callback)
   local stdout_data = {}
   local stderr_data = {}

   local stdout = uv.new_pipe(false)
   local stderr = uv.new_pipe(false)

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
      callback({
         exit_code = exit_code,
         signal = signal,
         stdout = stdout_data,
         stderr = stderr_data,
      })
   end)

   for kind, pipe in pairs({ stdout = stdout, stderr = stderr }) do
      if pipe then
         pipe:read_start(function(err, data)
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