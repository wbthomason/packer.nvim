local log    = require 'packer.log'
local config = require 'packer.config'

local Config = config.Config

local M = {}

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

local function loader(plugins: {Plugin})
  for _, plugin in ipairs(plugins) do
    if plugin.loaded then
      log.debug('Already loaded '..plugin.name)
    else
      for _, d in pairs(plugin.destructors) do
        d()
      end

      -- Set the plugin as loaded before config is run in case something in the
      -- config tries to load this same plugin again
      plugin.loaded = true
      apply_config(plugin, true)
      if plugin.opt then
        -- never packadd a start plugin
        vim.cmd.packadd(plugin.name)
      end
      apply_config(plugin, false)
    end
  end
end

local function load_plugin_configs(plugins: {string:Plugin})
  local Handlers = require('packer.handlers')

  for _, plugin in pairs(plugins) do
    if not plugin.opt then
      loader({plugin})
    end
  end

  for _, cond in ipairs(Handlers.types) do
    Handlers[cond](plugins, loader)
  end
end

local record StartupSpec
  {UserSpec}

  config: Config
end

-- Convenience function for simple setup
-- spec can be a table with a table of plugin specifications as its first
-- element, config overrides as another element.
function M.startup(spec: StartupSpec)
  log.debug('STARTING')

  assert(type(spec) == 'table')
  assert(type(spec[1]) == 'table')

  log.debug('PROCESSING CONFIG')
  config(spec.config)

  for _, dir in ipairs{config.opt_dir, config.start_dir} do
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
    end
  end

  local plugin = require 'packer.plugin'

  log.debug('PROCESSING PLUGIN SPEC')
  plugin.process_spec(spec[1])

  log.debug('LOADING PLUGINS')
  load_plugin_configs(plugin.plugins)
end

return M
