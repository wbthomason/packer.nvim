local fn = vim.fn
local fmt = string.format

local a = require('packer.async')
local config = require('packer.config')
local log = require('packer.log')
local util = require('packer.util')
local fsstate = require('packer.fsstate')

local Plugin = require('packer.plugin').Plugin
local display = require('packer.display')

local packer_plugins = require('packer.plugin').plugins

local Display = display.Display

local M = {}

















local function open_display()
   return display.display.open({
      diff = function(plugin, commit, callback)
         local plugin_type = require('packer.plugin_types')[plugin.type]
         return plugin_type.diff(plugin, commit, callback)
      end,
      revert_last = function(plugin)
         local plugin_type = require('packer.plugin_types')[plugin.type]
         plugin_type.revert_last(plugin)
      end,
   })
end

local function run_tasks(tasks, disp, kind)
   if #tasks == 0 then
      log.info('Nothing to do!')
      return
   end

   local function check()
      if disp then
         return disp:check()
      end
   end

   local limit = config.max_jobs and config.max_jobs or #tasks

   log.fmt_debug('Running tasks: %s', kind)
   if disp then
      disp:update_headline_message(string.format('%s %d / %d plugins', kind, #tasks, #tasks))
   end
   return a.join(limit, check, tasks)
end

local function helptags_stale(dir)
   local glob = fn.glob


   local txts = glob(util.join_paths(dir, '*.txt'), true, true)
   vim.list_extend(txts, glob(util.join_paths(dir, '*.[a-z][a-z]x'), true, true))

   if #txts == 0 then
      return false
   end

   local tags = glob(util.join_paths(dir, 'tags'), true, true)
   vim.list_extend(tags, glob(util.join_paths(dir, 'tags-[a-z][a-z]'), true, true))

   if #tags == 0 then
      return true
   end

   local txt_newest = math.max(unpack(vim.tbl_map(fn.getftime, txts)))
   local tag_oldest = math.min(unpack(vim.tbl_map(fn.getftime, tags)))
   return txt_newest > tag_oldest
end

local function update_helptags(results)
   local paths = {}
   for plugin_name, r in pairs(results) do
      if not r.err then
         paths[#paths + 1] = packer_plugins[plugin_name].install_path
      end
   end

   for _, dir in ipairs(paths) do
      local doc_dir = util.join_paths(dir, 'doc')
      if helptags_stale(doc_dir) then
         log.fmt_debug('Updating helptags for %s', doc_dir)
         vim.cmd('silent! helptags ' .. fn.fnameescape(doc_dir))
      end
   end
end

local post_update_hook = a.sync(function(plugin, disp)
   if plugin.run or plugin.start then
      a.main()
      local loader = require('packer.loader')
      loader.load_plugin(plugin)
   end

   if not plugin.run then
      return
   end

   disp:task_update(plugin.full_name, 'running post update hooks...')

   for _, run_task in ipairs(plugin.run) do
      if type(run_task) == "function" then
         local ok, err = pcall(run_task, plugin, disp)
         if not ok then
            return { 'Error running post update hook: ' .. vim.inspect(err) }
         end
      elseif type(run_task) == 'string' and run_task:sub(1, 1) == ':' then

         a.main()
         vim.cmd(run_task:sub(2))
      else
         local jobs = require('packer.jobs')
         local jr = jobs.run(run_task, { cwd = plugin.install_path })

         if jr.exit_code ~= 0 then
            return { string.format('Error running post update hook: %s', table.concat(jr.stderr, '\n')) }
         end
      end
   end
end, 2)

local install_task = a.sync(function(plugin, disp, installs)
   disp:task_start(plugin.full_name, 'installing...')

   local plugin_type = require('packer.plugin_types')[plugin.type]

   local err = plugin_type.installer(plugin, disp)

   if not err then
      err = post_update_hook(plugin, disp)
   end

   if not disp.items then
      disp.items = {}
   end

   if not err then
      disp:task_succeeded(plugin.full_name, 'installed')
      log.fmt_debug('Installed %s', plugin.full_name)
   else
      disp:task_failed(plugin.full_name, 'failed to install', err)
      log.fmt_debug('Failed to install %s: %s', plugin.full_name, vim.inspect(err))
   end

   installs[plugin.name] = { err = err }
   return plugin.name, err
end, 3)

local function get_install_tasks(
   plugins,
   missing_plugins,
   disp,
   installs)

   if #missing_plugins == 0 then
      return {}
   end

   local tasks = {}
   for _, v in ipairs(missing_plugins) do
      tasks[#tasks + 1] = a.curry(install_task, plugins[v], disp, installs)
   end

   return tasks
end

local function move_plugin(plugin, moves, fs_state)
   local from
   local to
   if not plugin.start then
      from = util.join_paths(config.start_dir, plugin.name)
      to = util.join_paths(config.opt_dir, plugin.name)
   else
      from = util.join_paths(config.opt_dir, plugin.name)
      to = util.join_paths(config.start_dir, plugin.name)
   end

   fs_state.start[to] = plugin.name
   fs_state.opt[from] = nil
   fs_state.dirty[from] = nil

   moves[plugin.name] = { from = from, to = to }



   local success, msg = os.rename(from, to)
   if not success then
      log.fmt_error('Failed to move %s to %s: %s', from, to, msg)
      moves[plugin.name] = { err = { msg } }
   else
      log.fmt_debug('Moved %s from %s to %s', plugin.name, from, to)
   end
end

local update_task = a.sync(function(plugin, disp, updates, opts)
   disp:task_start(plugin.full_name, 'updating...')

   if plugin.lock then
      disp:task_succeeded(plugin.full_name, 'locked')
      return
   end

   local plugin_type = require('packer.plugin_types')[plugin.type]
   local actual_update = false

   plugin.err = plugin_type.updater(plugin, disp, opts)
   if not plugin.err and plugin.type == 'git' then
      local revs = plugin.revs
      actual_update = revs[1] ~= revs[2]
      if actual_update then
         if not opts.preview_updates then
            log.fmt_debug('Updated %s', plugin.full_name)
            plugin.err = post_update_hook(plugin, disp)
         end
      end
   end

   if plugin.err then
      disp:task_failed(plugin.full_name, 'failed to update', plugin.err)
      log.fmt_debug('Failed to update %s: %s', plugin.full_name, table.concat(plugin.err, '\n'))
   elseif actual_update then
      local info = {}
      local ncommits = 0
      if plugin.messages and #plugin.messages > 0 then
         table.insert(info, 'Commits:')
         for _, m in ipairs(plugin.messages) do
            for _, line in ipairs(vim.split(m, '\n')) do
               table.insert(info, '    ' .. line)
               ncommits = ncommits + 1
            end
         end

         table.insert(info, '')
      end

      local msg = fmt('updated: %d new commits', ncommits)
      disp:task_succeeded(plugin.full_name, msg, info)
   else
      disp:task_done(plugin.full_name, 'already up to date')
   end

   updates[plugin.name] = { err = plugin.err }
   return plugin.name, plugin.err
end, 4)

local function get_update_tasks(
   plugins,
   update_plugins,
   disp,
   updates,
   opts)

   local tasks = {}
   for _, v in ipairs(update_plugins) do
      local plugin = plugins[v]
      if not plugin then
         log.fmt_error('Unknown plugin: %s', v)
      end
      if plugin and not plugin.lock then
         tasks[#tasks + 1] = a.curry(update_task, plugin, disp, updates, opts)
      end
   end

   if #tasks == 0 then
      log.info('Nothing to update!')
   end

   return tasks
end

local function fix_plugin_types(
   plugins,
   extra_plugins,
   moves,
   fs_state)

   log.debug('Fixing plugin types')

   for _, v in ipairs(extra_plugins) do
      local plugin = plugins[v]
      local wrong_install_dir = util.join_paths(plugin.start and config.opt_dir or config.start_dir, plugin.name)
      if vim.loop.fs_stat(wrong_install_dir) then
         move_plugin(plugin, moves, fs_state)
      end
   end
   log.debug('Done fixing plugin types')
end



local function filter_opts_from_plugins(...)
   local args = { ... }
   local opts = {}
   if not vim.tbl_isempty(args) then
      local first = select(1, ...)
      if type(first) == "table" then
         table.remove(args, 1)
         opts = first
      elseif first == '--preview' then
         table.remove(args, 1)
         opts = { preview_updates = true }
      end
   end
   if config.preview_updates then
      opts.preview_updates = true
   end
   return opts, #args > 0 and args or vim.tbl_keys(packer_plugins)
end


local do_clean = a.sync(function(plugins, fs_state, removals)
   fs_state = fs_state or fsstate.get_fs_state(plugins)

   log.debug('Starting clean')
   local plugins_to_remove = vim.tbl_extend('force', fs_state.extra, fs_state.dirty)

   log.debug('extra plugins', fs_state.extra)
   log.debug('dirty plugins', fs_state.dirty)

   if not next(plugins_to_remove) then
      log.info('Already clean!')
      return
   end

   a.main()

   local lines = {}
   for path, _ in pairs(plugins_to_remove) do
      table.insert(lines, '  - ' .. path)
   end

   if config.autoremove or display.display.ask_user('Removing the following directories. OK? (y/N)', lines) then
      if removals then
         for r, _ in pairs(plugins_to_remove) do
            removals[#removals + 1] = r
         end
      end
      local removed = vim.deepcopy(plugins_to_remove)
      for path, _ in pairs(plugins_to_remove) do
         local result = vim.fn.delete(path, 'rf')
         if result == -1 then
            log.fmt_warn('Could not remove %s', path)
         end
         plugins_to_remove[path] = nil
      end
      log.debug('Removed', removed)
   else
      log.warn('Cleaning cancelled!')
   end
end, 4)



M.install = a.sync(function()
   local fs_state = fsstate.get_fs_state(packer_plugins)
   local missing_plugins = vim.tbl_values(fs_state.missing)
   if #missing_plugins == 0 then
      log.info('All configured plugins are installed')
      return
   end

   a.main()

   log.debug('Gathering install tasks')

   local disp = open_display()
   local installs = {}

   local delta = util.measure(function()
      local install_tasks = get_install_tasks(packer_plugins, missing_plugins, disp, installs)
      run_tasks(install_tasks, disp, 'installing')

      a.main()
      update_helptags(installs)
   end)

   disp:finish(delta)
end)






M.update = a.void(function(...)
   local opts, update_plugins = filter_opts_from_plugins(...)
   local fs_state = fsstate.get_fs_state(packer_plugins)
   local _, installed_plugins = util.partition(vim.tbl_values(fs_state.missing), update_plugins)

   local updates = {}

   a.main()

   local disp = open_display()

   local delta = util.measure(function()
      local tasks = {}

      a.main()

      log.debug('Gathering update tasks')
      vim.list_extend(tasks, get_update_tasks(packer_plugins, installed_plugins, disp, updates, opts))

      run_tasks(tasks, disp, 'updating')

      a.main()
      update_helptags(updates)
   end)

   disp:finish(delta)
end)







M.sync = a.void(function(...)
   local plugins = packer_plugins
   local opts, update_plugins = filter_opts_from_plugins(...)
   local fs_state = fsstate.get_fs_state(packer_plugins)

   local extra_plugins = util.partition(vim.tbl_values(fs_state.extra), update_plugins)

   local results = {
      moves = {},
      removals = {},
      installs = {},
      updates = {},
   }

   fix_plugin_types(packer_plugins, extra_plugins, results.moves, fs_state)



   fs_state = fsstate.get_fs_state(packer_plugins)

   do_clean(packer_plugins, fs_state, results.removals)

   local missing_plugins, installed_plugins = util.partition(vim.tbl_values(fs_state.missing), update_plugins)

   a.main()

   local disp = open_display()

   local delta = util.measure(function()
      local tasks = {}

      log.debug('Gathering install tasks')
      vim.list_extend(tasks, get_install_tasks(plugins, missing_plugins, disp, results.installs))

      a.main()

      log.debug('Gathering update tasks')
      vim.list_extend(tasks, get_update_tasks(plugins, installed_plugins, disp, results.updates, opts))

      run_tasks(tasks, disp, 'syncing')

      a.main()
      update_helptags(vim.tbl_extend('error', results.installs, results.updates))
   end)

   disp:finish(delta)
end)

M.status = a.sync(function()
   require('packer.status').run()
end)



M.clean = a.void(function()
   do_clean(packer_plugins)
end)

M.lock = a.sync(function()
   require('packer.lockfile').lock()
end)

M.restore = a.sync(function()
   require('packer.lockfile').restore()
end)

return M