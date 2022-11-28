local config = require('packer.config')

local Config = config.Config

local M = {}

local function apply_config(plugin)
   if plugin.config then
      local c = plugin.config
      if type(c) == "function" then
         c()
      else
         loadstring(c, plugin.name .. '.config()')()
      end
   end
end

local function loader(plugins)
   for _, plugin in ipairs(plugins) do
      if not plugin.loaded then


         plugin.loaded = true
         if plugin.opt then

            vim.cmd.packadd(plugin.name)
         end
         apply_config(plugin)
      end
   end
end

local function load_plugin_configs(plugins)
   local Handlers = require('packer.handlers')

   for _, plugin in pairs(plugins) do
      if not plugin.opt then
         loader({ plugin })
      end
   end

   for _, cond in ipairs(Handlers.types) do
      Handlers[cond](plugins, loader)
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

   local plugin = require('packer.plugin')

   plugin.process_spec(spec[1])

   load_plugin_configs(plugin.plugins)
end

return M