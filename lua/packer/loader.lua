local log = require('packer.log')
local util = require('packer.util')

local vimenter_configs = {}
local vimenter_autocmd_id

local function create_vimenter_autocmd()
   return vim.api.nvim_create_autocmd('VimEnter', {
      once = true,
      callback = function()
         for _, cfg in ipairs(vimenter_configs) do
            cfg()
         end
         vimenter_configs = {}
      end,
   })
end

local function add_vimenter_config(cfg)
   if not vimenter_autocmd_id then
      vimenter_autocmd_id = create_vimenter_autocmd()
   end

   vimenter_configs[#vimenter_configs + 1] = cfg
end

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
      log.error(string.format('Error running config for %s: %s', plugin.name, x))
   end)
end

local function source_after(install_path)
   for _, kind in ipairs({ '*.vim', '*.lua' }) do
      local path = util.join_paths(install_path, 'after', 'plugin', '**', kind)
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

   if not plugin.start and vim.v.vim_did_enter == 0 then




      vim.o.runtimepath = plugin.install_path .. ',' .. vim.o.runtimepath
   end

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

      add_vimenter_config(function()
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