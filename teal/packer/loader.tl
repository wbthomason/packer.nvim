local log  = require 'packer.log'
local util = require 'packer.util'

local vimenter_configs: {function()} = {}
local vimenter_autocmd_id: integer

local function create_vimenter_autocmd(): integer
  return vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
      for _, cfg in ipairs(vimenter_configs) do
        cfg()
      end
      vimenter_configs = {}
    end
  })
end

local function add_vimenter_config(cfg: function())
  if not vimenter_autocmd_id then
    vimenter_autocmd_id = create_vimenter_autocmd()
  end

  vimenter_configs[#vimenter_configs+1] = cfg
end

local function apply_config(plugin: Plugin, pre: boolean)
  xpcall(function()
    local c, sfx: function()|string, string
    if pre then
      c, sfx = plugin.config_pre, '_pre'
    else
      c, sfx = plugin.config, ''
    end

    if c then
      log.fmt_debug('Running config%s for %s', sfx, plugin.name)
      local c0: function()
      if c is function() then
        c0 = c
      else
        c0 = loadstring(c, plugin.name..'.config'..sfx)
      end
      local delta = util.measure(c0)
      log.fmt_debug('config%s for %s took %fms', sfx, plugin.name, delta*1000)
    end
  end, function (x: string): string
    log.fmt_error('Error running config for %s: %s', plugin.name, x)
  end)
end

local FileType = vim.loop.FileType

local function ls(path: string, fn: function(string, string, FileType): boolean)
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

local function walk(path: string, fn: function(string, string, FileType))
  ls(path, function(child: string, name: string, ftype: FileType): boolean
    if ftype == "directory" then
      walk(child, fn)
    end
    fn(child, name, ftype)
  end)
end

local function source_after(install_path: string)
  walk(util.join_paths(install_path, 'after', 'plugin'), function(path: string, _: string, t: FileType)
    local ext = path:sub(-4)
    if t == "file" and (ext == ".lua" or ext == ".vim") then
      log.fmt_debug('sourcing %s', path)
      vim.cmd.source{path, mods = {silent=true}}
    end
  end)
end

local record M
  load_plugin : function(plugin: Plugin)
end

local function load_plugins(plugins: {Plugin})
  for _, plugin in ipairs(plugins) do
    M.load_plugin(plugin)
  end
end

function M.load_plugin(plugin: Plugin)
  if plugin.loaded then
    log.fmt_debug('Already loaded %s', plugin.name)
    return
  end

  if not vim.loop.fs_stat(plugin.install_path) then
    log.fmt_error('%s is not installed', plugin.name)
    return
  end

  log.fmt_debug('Running loader for %s', plugin.name)

  apply_config(plugin, true) -- spec.config_pre()

  -- Set the plugin as loaded before config is run in case something in the
  -- config tries to load this same plugin again
  plugin.loaded = true

  if plugin.requires then
    log.fmt_debug('Loading dependencies of %s', plugin.name)
    local all_plugins = require'packer.plugin'.plugins
    local rplugins = vim.tbl_map(function(n: string): Plugin
      return all_plugins[n]
    end, plugin.requires)
    load_plugins(rplugins)
  end

  log.fmt_debug('Loading %s', plugin.name)
  if vim.v.vim_did_enter == 0 then
    if not plugin.start then
      vim.cmd.packadd{plugin.name, bang = true}
    end

    add_vimenter_config(function()
      apply_config(plugin, false) -- spec.config()
    end)
  else
    if not plugin.start then
      vim.cmd.packadd(plugin.name)
      source_after(plugin.install_path)
    end

    apply_config(plugin, false) -- spec.config()
  end
end

function M.setup(plugins: {string:Plugin})
  local Handlers = require('packer.handlers')

  for _, plugin in pairs(plugins) do
    if not plugin.lazy then
      load_plugins({plugin})
    end
  end

  for _, cond in ipairs(Handlers.types) do
    Handlers[cond](plugins, load_plugins)
  end
end

return M
