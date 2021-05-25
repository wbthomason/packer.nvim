local plugin_utils = require('packer.plugin_utils')
local a = require('packer.async')
local display = require('packer.display')
local log = require('packer.log')
local util = require('packer.util')

local await = a.wait
local async = a.sync

local config

local PLUGIN_OPTIONAL_LIST = 1
local PLUGIN_START_LIST = 2

local function is_dirty(plugin, typ)
  return (plugin.opt and typ == PLUGIN_START_LIST)
           or (not plugin.opt and typ == PLUGIN_OPTIONAL_LIST)
end

-- Find and remove any plugins not currently configured for use
local clean_plugins = function(_, plugins, results)
  return async(function()
    local dirty_plugins = {}
    results = results or {}
    results.removals = results.removals or {}
    await(a.main)
    local opt_plugins, start_plugins = plugin_utils.list_installed_plugins()
    local missing_plugins = plugin_utils.find_missing_plugins(plugins, opt_plugins, start_plugins)
    -- turn the list into a hashset-like structure
    for idx, plugin_name in ipairs(missing_plugins) do
      missing_plugins[plugin_name] = true
      missing_plugins[idx] = nil
    end

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
      local is_installed = vim.loop.fs_stat(path) ~= nil
      local plugin_missing = missing_plugins[plugin_config.short_name] and is_installed
      local disabled_but_installed = is_installed and plugin_config.disable
      if plugin_missing or is_dirty(plugin_config, plugin_source) or disabled_but_installed then
        table.insert(dirty_plugins, path)
      end
    end

    -- Any path which was not set to `nil` above will be set to dirty here
    local function mark_remaining_as_dirty(plugin_list)
      for path, _ in pairs(plugin_list) do table.insert(dirty_plugins, path) end
    end

    mark_remaining_as_dirty(opt_plugins)
    mark_remaining_as_dirty(start_plugins)
    if next(dirty_plugins) then
      local lines = {}
      for _, path in ipairs(dirty_plugins) do table.insert(lines, '  - ' .. path) end
      if await(display.ask_user('Removing the following directories. OK? (y/N)', lines)) then
        results.removals = dirty_plugins
        log.debug('Removed ' .. vim.inspect(dirty_plugins))
        if util.is_windows then
          for _, path in ipairs(dirty_plugins) do os.execute('cmd /C rmdir /S /Q ' .. path) end
        else
          os.execute('rm -rf ' .. table.concat(dirty_plugins, ' '))
        end
      else
        log.warn('Cleaning cancelled!')
      end
    else
      log.info("Already clean!")
    end
  end)
end

local function cfg(_config) config = _config end

local clean = setmetatable({cfg = cfg}, {__call = clean_plugins})
return clean
