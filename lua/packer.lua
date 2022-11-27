local config = require('packer.config')

local Config = config.Config

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
   local plugins = require('packer.plugin').plugins
   local completion_list = vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
   end, vim.tbl_keys(plugins))
   table.sort(completion_list)
   return completion_list
end

local function load_plugin_configs(plugins)
   local Handlers = require('packer.handlers')

   local cond_plugins = {}
   local uncond_plugins = {}

   for name, plugin in pairs(plugins) do
      local has_cond = false
      for _, cond in ipairs(Handlers.types) do
         if (plugin)[cond] then
            has_cond = true
            cond_plugins[cond] = cond_plugins[cond] or {}
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

   for _, cond in ipairs(Handlers.types) do
      if cond_plugins[cond] then
         Handlers[cond](cond_plugins[cond], loader)
      end
   end
end

local function make_commands()
   local actions = setmetatable({}, {
      __index = function(_, k)
         return function(...)
            return (require('packer.actions'))[k](...)
         end
      end,
   })

   for _, cmd in ipairs({
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
   assert(type(spec) == 'table')
   assert(type(spec[1]) == 'table')

   config(spec.config)

   for _, dir in ipairs({ config.opt_dir, config.start_dir }) do
      if vim.fn.isdirectory(dir) == 0 then
         vim.fn.mkdir(dir, 'p')
      end
   end

   make_commands()

   local plugin = require('packer.plugin')

   plugin.process_spec(spec[1])

   load_plugin_configs(plugin.plugins)
end

return M