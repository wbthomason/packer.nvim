local log = require('packer.log')
local config = require('packer.config')

local Config = config.Config

local M = {}

local function apply_config(plugin, pre)
   local c
   if pre then
      c = plugin.config_pre
   else
      c = plugin.config
   end

   if c then
      if type(c) == "function" then
         log.debug('Running fun config for ' .. plugin.name)
         c()
      else
         log.debug('Running str config for ' .. plugin.name)
         local sfx = pre and '_pre()' or '()'
         loadstring(c, plugin.name .. '.config' .. sfx)()
      end
   end
end

local function loader(plugins)
   for _, plugin in ipairs(plugins) do
      if plugin.loaded then
         log.debug('Already loaded ' .. plugin.name)
      else
         log.debug('Running loader for ' .. plugin.name)


         for _, d in pairs(plugin.destructors) do
            d()
         end



         plugin.loaded = true

         apply_config(plugin, true)

         if not plugin.start then
            if plugin.requires then
               log.debug('Loading dependencies of ' .. plugin.name)
               local all_plugins = require('packer.plugin').plugins
               local rplugins = vim.tbl_map(function(n)
                  return all_plugins[n]
               end, plugin.requires)
               loader(rplugins)
            end


            log.debug('Loading ' .. plugin.name)
            vim.cmd.packadd(plugin.name)
         end

         apply_config(plugin, false)
      end
   end
end

local function load_plugin_configs(plugins)
   local Handlers = require('packer.handlers')

   for _, plugin in pairs(plugins) do
      if not plugin.lazy then
         loader({ plugin })
      end
   end

   for _, cond in ipairs(Handlers.types) do
      Handlers[cond](plugins, loader)
   end
end










function M.startup(spec)
   log.debug('STARTING')

   assert(type(spec) == 'table')
   assert(type(spec[1]) == 'table')

   log.debug('PROCESSING CONFIG')
   config(spec.config)

   for _, dir in ipairs({ config.opt_dir, config.start_dir }) do
      if vim.fn.isdirectory(dir) == 0 then
         vim.fn.mkdir(dir, 'p')
      end
   end

   local plugin = require('packer.plugin')

   log.debug('PROCESSING PLUGIN SPEC')
   plugin.process_spec(spec[1])

   log.debug('LOADING PLUGINS')
   load_plugin_configs(plugin.plugins)
end

return M