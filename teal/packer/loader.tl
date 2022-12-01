local log  = require 'packer.log'
local util = require 'packer.util'

local function apply_config(plugin: Plugin, pre: boolean)
  local c: function()|string
  if pre then
    c = plugin.config_pre
  else
    c = plugin.config
  end

  if c then
    if c is function() then
      log.debug('Running fun config for '..plugin.name)
      c()
    else
      log.debug('Running str config for '..plugin.name)
      local sfx = pre and '_pre()' or '()'
      loadstring(c, plugin.name..'.config'..sfx)()
    end
  end
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
  else
    log.debug('Running loader for '..plugin.name)

    -- Tidy up any lazy-loading state
    for _, d in pairs(plugin.destructors) do
      d()
    end

    -- Set the plugin as loaded before config is run in case something in the
    -- config tries to load this same plugin again
    plugin.loaded = true

    apply_config(plugin, true) -- spec.config_pre()

    if not plugin.start then
      if plugin.requires then
        log.debug('Loading dependencies of '..plugin.name)
        local all_plugins = require'packer.plugin'.plugins
        local rplugins = vim.tbl_map(function(n: string): Plugin
          return all_plugins[n]
        end, plugin.requires)
        load_plugins(rplugins)
      end

      -- never packadd a start plugin
      log.debug('Loading '..plugin.name)
      vim.cmd.packadd(plugin.name)
      source_runtime(plugin)
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
