local log = require('packer.log')
local util = require('packer.util')


local function apply_config(plugin, pre)
   xpcall(function()
      local c, sfx
      if pre then
         c, sfx = plugin.config_pre, '_pre'
      else
         c, sfx = plugin.config, ''
      end

      if c then
         log.fmt_debug('Running config%s for %s', sfx, plugin.name)
         if type(c) == "function" then
            c()
         else
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