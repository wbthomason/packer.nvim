local log = require('packer.log')
local util = require('packer.util')


local function apply_config(plugin, pre)
   xpcall(function()
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
   end, function(x)
      log.error(string.format('Error running config for %s: %s', plugin.name, x))
   end)
end

local function source_runtime(plugin)
   for _, parts in ipairs({
         { 'plugin', '**', '*.vim' },
         { 'plugin', '**', '*.lua' },
         { 'after', 'plugin', '**', '*.vim' },
         { 'after', 'plugin', '**', '*.lua' },
      }) do
      local path = util.join_paths(plugin.install_path, unpack(parts))
      local ok, files = pcall(vim.fn.glob, path, false, true)
      if not ok then
         if (files):find('E77') then
            vim.cmd('silent exe "source ' .. path .. '"')
         else
            error(files)
         end
      else
         for _, file in ipairs(files) do
            log.debug('sourcing ' .. file)
            vim.cmd.source({ file, mods = { silent = true } })
         end
      end
   end
end

local M = {}



local function load_plugins(plugins)
   for _, plugin in ipairs(plugins) do
      M.load_plugin(plugin)
   end
end

function M.load_plugin(plugin)
   if plugin.loaded then
      log.debug('Already loaded ' .. plugin.name)
      return
   end

   log.debug('Running loader for ' .. plugin.name)


   for _, d in pairs(plugin.destructors) do
      d()
   end

   apply_config(plugin, true)

   if not plugin.start then

      log.debug('Loading ' .. plugin.name)



      vim.cmd.packadd(plugin.name)
   end



   plugin.loaded = true

   if plugin.requires then
      log.debug('Loading dependencies of ' .. plugin.name)
      local all_plugins = require('packer.plugin').plugins
      local rplugins = vim.tbl_map(function(n)
         return all_plugins[n]
      end, plugin.requires)
      load_plugins(rplugins)
   end

   if not plugin.start then

      log.debug('Loading ' .. plugin.name)
      vim.cmd.packadd(plugin.name)
      source_runtime(plugin)
   end

   apply_config(plugin, false)
end

function M.setup(plugins)
   local Handlers = require('packer.handlers')

   for _, plugin in pairs(plugins) do
      if not plugin.lazy then
         load_plugins({ plugin })
      end
   end

   for _, cond in ipairs(Handlers.types) do
      Handlers[cond](plugins, load_plugins)
   end
end

return M