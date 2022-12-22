local fmt = string.format

local a = require('packer.async')
local config = require('packer.config')
local log = require('packer.log')
local P = require('packer.plugin')
local plugin_types = require('packer.plugin_types')
local display = require('packer.display')

local Display = display.Display

local M = {}





local function run_tasks(tasks, disp, kind)
   if #tasks == 0 then
      log.info('Nothing to do!')
      return
   end

   local function interrupt_check()
      if disp then
         return disp:check()
      end
   end

   local limit = config.max_jobs and config.max_jobs or #tasks

   if kind then
      log.fmt_debug('Running tasks: %s', kind)
   end
   if disp then
      disp:update_headline_message(string.format('%s %d / %d plugins', kind, #tasks, #tasks))
   end
   return a.join(limit, interrupt_check, tasks)
end

local function update(path, info)
   local dir = vim.fs.dirname(path)
   if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
   end

   local urls = vim.tbl_keys(info)
   table.sort(urls)

   local f = assert(io.open(path, "w"))
   f:write("return {\n")
   for _, url in ipairs(urls) do
      local obj = { commit = info[url] }
      f:write(fmt("  [%q] = %s,", url, vim.inspect(obj, { newline = ' ', indent = '' })))
      f:write('\n')
   end
   f:write("}")
   f:close()
end

M.lock = a.sync(function()
   local lock_tasks = {}
   for _, plugin in pairs(P.plugins) do
      lock_tasks[#lock_tasks + 1] = a.sync(function()
         local plugin_type = plugin_types[plugin.type]
         if plugin_type.get_rev then
            return plugin.url, (plugin_type.get_rev(plugin))
         end
      end)
   end

   local info = run_tasks(lock_tasks)
   local info1 = {}
   for _, i in ipairs(info) do
      if i[1] then
         info1[i[1]] = i[2]
      end
   end

   a.main()
   local lockfile = config.lockfile.path
   update(lockfile, info1)
   log.fmt_info('Lockfile created at %s', config.lockfile.path)
end)

local restore_plugin = a.sync(function(plugin, disp, commit)
   disp:task_start(plugin.full_name, fmt('restoring to %s', commit))

   if plugin.type == 'local' then
      disp:task_done(plugin.full_name, 'local plugin')
      return
   end

   if not commit then
      disp:task_failed(plugin.full_name, 'could not find plugin in lockfile')
      return
   end

   local plugin_type = require('packer.plugin_types')[plugin.type]

   local rev = plugin_type.get_rev(plugin)
   if commit == rev then
      disp:task_done(plugin.full_name, fmt('already at commit %s', commit))
      return
   end

   plugin.err = plugin_type.revert_to(plugin, commit)
   if plugin.err then
      disp:task_failed(plugin.full_name, fmt('failed to restore to commit %s', commit))
      return
   end

   disp:task_succeeded(plugin.full_name, fmt('restored to commit %s', commit))
end, 3)





M.restore = a.sync(function()
   local disp = display.display.open({})
   disp:update_headline_message('Restoring from lockfile')

   local lockfile = config.lockfile.path
   local lockinfo = loadfile(lockfile)()

   local restore_tasks = {}
   for _, plugin in pairs(P.plugins) do
      local info = lockinfo[plugin.url] or {}
      restore_tasks[#restore_tasks + 1] = a.curry(restore_plugin, plugin, disp, info.commit)
   end

   run_tasks(restore_tasks, disp, 'restoring')
end)

return M