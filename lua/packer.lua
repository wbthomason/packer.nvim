local M = {}

local function apply_config(plugin)
   if plugin.config and plugin.loaded then
      local c = plugin.config
      if type(c) == "function" then
         c()
      else
         loadstring(c, plugin.name .. '.config()')()
      end
   end
end

local function loader(lplugins)
   for _, plugin in ipairs(lplugins) do
      if not plugin.loaded then


         plugin.loaded = true
         vim.cmd.packadd(plugin.name)
         apply_config(plugin)
      end
   end
end



local function plugin_complete(lead, _)
   local completion_list = vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
   end, vim.tbl_keys(_G.packer_plugins))
   table.sort(completion_list)
   return completion_list
end

local function load_plugin_configs()
   local Handlers = require('packer.handlers')

   local cond_plugins = {
      cmd = {},
      keys = {},
      ft = {},
      event = {},
   }

   local uncond_plugins = {}

   local conds = { 'cmd', 'keys', 'ft', 'event' }

   for name, plugin in pairs(_G.packer_plugins) do
      local has_cond = false
      for _, cond in ipairs(conds) do
         if (plugin)[cond] then
            has_cond = true
            cond_plugins[cond][name] = plugin
            break
         end
      end
      if not has_cond then
         uncond_plugins[name] = plugin
      end
   end

   for _, plugin in pairs(uncond_plugins) do
      apply_config(plugin)
   end

   for _, cond in ipairs(conds) do
      if next(cond_plugins[cond]) then
         Handlers[cond](cond_plugins[cond], loader)
      end
   end
end

local function make_commands()
   local snapshot_cmpl = setmetatable({}, {
      __index = function(_, k)
         return function(...)
            return (require('packer.snapshot').completion)[k](...)
         end
      end,
   })

   local actions = setmetatable({}, {
      __index = function(_, k)
         return function(...)
            return (require('packer.actions'))[k](...)
         end
      end,
   })

   for _, cmd in ipairs({
         { 'PackerSnapshot', '+', actions.create, snapshot_cmpl.create },
         { 'PackerSnapshotRollback', '+', actions.rollback, snapshot_cmpl.rollback },
         { 'PackerSnapshotDelete', '+', actions.delete, snapshot_cmpl.snapshot },
         { 'PackerInstall', '*', actions.install, plugin_complete },
         { 'PackerUpdate', '*', actions.update, plugin_complete },
         { 'PackerSync', '*', actions.sync },
         { 'PackerClean', '*', actions.clean },
         { 'PackerStatus', '*', actions.status },
      }) do
      vim.api.nvim_create_user_command(cmd[1], function(args)
         cmd[3](unpack(args.fargs))
      end, { nargs = cmd[2], complete = cmd[4] })
   end
end










function M.startup(spec)
   local config = require('packer.config')
   local log = require('packer.log')

   assert(type(spec) == 'table')
   assert(type(spec[1]) == 'table')

   config(spec.config)

   for _, dir in ipairs({ config.opt_dir, config.start_dir }) do
      if vim.fn.isdirectory(dir) == 0 then
         vim.fn.mkdir(dir, 'p')
      end
   end

   make_commands()

   if vim.fn.mkdir(config.snapshot_path, 'p') ~= 1 then
      log.warn("Couldn't create " .. config.snapshot_path)
   end

   _G.packer_plugins = require('packer.plugin').process_spec({
      spec = spec[1],
      line = debug.getinfo(2, 'l').currentline,
   })

   load_plugin_configs()

   if config.snapshot then
      require('packer.actions').rollback(config.snapshot)
   end
end

return M