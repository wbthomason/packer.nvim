local log  = require 'packer.log'
local util = require 'packer.util'


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
      if c is function() then
        c()
      else
        loadstring(c, plugin.name..'.config'..sfx)()
      end
    end
  end, function (x: string): string
    log.error(string.format('Error running config for %s: %s', plugin.name, x))
  end)
end

local function source_runtime(plugin: Plugin)
  for _, parts in ipairs {
    {'plugin', '**', '*.vim'},
    {'plugin', '**', '*.lua'},
    {'after', 'plugin', '**', '*.vim'},
    {'after', 'plugin', '**', '*.lua'},
  } do
    local path = util.join_paths(plugin.install_path, unpack(parts))
    local ok, files = pcall(vim.fn.glob, path, false, true)
    if not ok then
      if (files as string):find('E77') then  -- E77: Too many file names
        vim.cmd('silent exe "source ' .. path .. '"')
      else
        error(files)
      end
    else
      for _, file in ipairs(files) do
        log.debug('sourcing '..file)
        vim.cmd.source{file, mods = {silent=true}}
      end
    end
  end
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
    log.debug('Already loaded '..plugin.name)
    return
  end

  log.debug('Running loader for '..plugin.name)

  -- Tidy up any lazy-loading state
  for _, d in pairs(plugin.destructors) do
    d()
  end

  apply_config(plugin, true) -- spec.config_pre()

  if not plugin.start then
    -- never packadd a start plugin
    log.debug('Loading '..plugin.name)

    -- we don't use ':packadd!' as we need to load dependencies before
    -- actually sourcing plugin files
    vim.cmd.packadd(plugin.name)
  end

  -- Set the plugin as loaded before config is run in case something in the
  -- config tries to load this same plugin again
  plugin.loaded = true

  if plugin.requires then
    log.debug('Loading dependencies of '..plugin.name)
    local all_plugins = require'packer.plugin'.plugins
    local rplugins = vim.tbl_map(function(n: string): Plugin
      return all_plugins[n]
    end, plugin.requires)
    load_plugins(rplugins)
  end

  if not plugin.start then
    -- never packadd a start plugin
    log.debug('Loading '..plugin.name)
    vim.cmd.packadd(plugin.name)
    source_runtime(plugin)
  end

  apply_config(plugin, false) -- spec.config()
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
