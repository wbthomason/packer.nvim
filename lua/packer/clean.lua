local plugin_utils = require 'packer.plugin_utils'
local a = require 'packer.async'
local display = require 'packer.display'
local log = require 'packer.log'
local util = require 'packer.util'

local await = a.wait
local async = a.sync

local config

local PLUGIN_OPTIONAL_LIST = 1
local PLUGIN_START_LIST = 2

local function is_dirty(plugin, typ)
  return (plugin.opt and typ == PLUGIN_START_LIST) or (not plugin.opt and typ == PLUGIN_OPTIONAL_LIST)
end

-- Find and remove any plugins not currently configured for use
local clean_plugins = function(_, plugins, fs_state, results)
  return async(function()
    log.debug 'Starting clean'
    local dirty_plugins = {}
    results = results or {}
    results.removals = results.removals or {}
    local opt_plugins = vim.deepcopy(fs_state.opt)
    local start_plugins = vim.deepcopy(fs_state.start)
    local missing_plugins = fs_state.missing
    -- test for dirty / 'missing' plugins
    for _, plugin_config in pairs(plugins) do
      local path = plugin_config.install_path
      local plugin_source = nil
      if opt_plugins[path] then
        plugin_source = PLUGIN_OPTIONAL_LIST
        opt_plugins[path] = nil
      elseif start_plugins[path] then
        plugin_source = PLUGIN_START_LIST
        start_plugins[path] = nil
      end

      -- We don't want to report paths which don't exist for removal; that will confuse people
      local path_exists = false
      if missing_plugins[plugin_config.short_name] or plugin_config.disable then
        path_exists = vim.loop.fs_stat(path) ~= nil
      end

      local plugin_missing = path_exists and missing_plugins[plugin_config.short_name]
      local disabled_but_installed = path_exists and plugin_config.disable
      if plugin_missing or is_dirty(plugin_config, plugin_source) or disabled_but_installed then
        dirty_plugins[#dirty_plugins + 1] = path
      end
    end

    -- Any path which was not set to `nil` above will be set to dirty here
    local function mark_remaining_as_dirty(plugin_list)
      for path, _ in pairs(plugin_list) do
        dirty_plugins[#dirty_plugins + 1] = path
      end
    end

    mark_remaining_as_dirty(opt_plugins)
    mark_remaining_as_dirty(start_plugins)
    if next(dirty_plugins) then
      local lines = {}
      for _, path in ipairs(dirty_plugins) do
        table.insert(lines, '  - ' .. path)
      end
      await(a.main)
      if config.autoremove or await(display.ask_user('Removing the following directories. OK? (y/N)', lines)) then
        results.removals = dirty_plugins
        log.debug('Removed ' .. vim.inspect(dirty_plugins))
        for _, path in ipairs(dirty_plugins) do
          local result = vim.fn.delete(path, 'rf')
          if result == -1 then
            log.warn('Could not remove ' .. path)
          end
        end
      else
        log.warn 'Cleaning cancelled!'
      end
    else
      log.info 'Already clean!'
    end
  end)
end

local function cfg(_config)
  config = _config
end

local clean = setmetatable({ cfg = cfg }, { __call = clean_plugins })
return clean
