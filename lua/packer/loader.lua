local log = require('packer.log')
local util = require('packer.util')
local Plugin = require('packer.plugin').Plugin

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
         local c0
         if type(c) == "function" then
            c0 = c
         else
            c0 = loadstring(c, plugin.name .. '.config' .. sfx)
         end
         local delta = util.measure(c0)
         log.fmt_debug('config%s for %s took %fms', sfx, plugin.name, delta * 1000)
      end
   end, function(x)
      log.fmt_error('Error running config for %s: %s', plugin.name, x)
   end)
end

local FileType = vim.loop.FileType

local function ls(path, fn)
   local handle = vim.loop.fs_scandir(path)
   while handle do
      local name, t = vim.loop.fs_scandir_next(handle)
      if not name then
         break
      end
      if fn(util.join_paths(path, name), name, t) == false then
         break
      end
   end
end

local function walk(path, fn)
   ls(path, function(child, name, ftype)
      if ftype == "directory" then
         walk(child, fn)
      end
      fn(child, name, ftype)
   end)
end

local function source_after(install_path)
   walk(util.join_paths(install_path, 'after', 'plugin'), function(path, _, t)
      local ext = path:sub(-4)
      if t == "file" and (ext == ".lua" or ext == ".vim") then
         log.fmt_debug('sourcing %s', path)
         vim.cmd.source({ path, mods = { silent = true } })
      end
   end)
end

local M = {}



local function load_plugins(plugins)
   for _, plugin in ipairs(plugins) do
      M.load_plugin(plugin)
   end
end

function M.load_plugin(plugin)
   if plugin.loaded then
      log.fmt_debug('Already loaded %s', plugin.name)
      return
   end

   if not vim.loop.fs_stat(plugin.install_path) then
      log.fmt_error('%s is not installed', plugin.name)
      return
   end

   log.fmt_debug('Running loader for %s', plugin.name)

   apply_config(plugin, true)



   plugin.loaded = true

   if plugin.requires then
      log.fmt_debug('Loading dependencies of %s', plugin.name)
      local all_plugins = require('packer.plugin').plugins
      local rplugins = vim.tbl_map(function(n)
         return all_plugins[n]
      end, plugin.requires)
      load_plugins(rplugins)
   end

   log.fmt_debug('Loading %s', plugin.name)
   if vim.v.vim_did_enter == 0 then
      if not plugin.start then
         vim.cmd.packadd({ plugin.name, bang = true })
      end

      require('packer.plugin_config').add(function()
         apply_config(plugin, false)
      end)
   else
      if not plugin.start then
         vim.cmd.packadd(plugin.name)
         source_after(plugin.install_path)
      end

      apply_config(plugin, false)
   end
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