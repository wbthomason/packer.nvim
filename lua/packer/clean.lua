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
  return plugin.disable or (plugin.opt and typ == 2) or (not plugin.opt and typ == 1)
end

-- Find and remove any plugins not currently configured for use
local clean_plugins = function(_, plugins, results)
  return async(function()
    results = results or {}
    results.removals = results.removals or {}

    local function map_install_folder(install_paths)
      local install_folders = {}

      for install_path, _ in pairs(install_paths) do
        local split_path = vim.split(install_path, '/', true)
        install_folders[split_path[#split_path]] = true
      end

      return install_folders
    end

    local function map_names_to_paths(plugin_names)
      local paths = {}

      for _, plugin_name in ipairs(plugin_names) do
        paths[#paths+1] = plugins[plugin_name].install_path
      end

      return paths
    end

    local opt_plugins, start_plugins = plugin_utils.list_installed_plugins()
    local dirty_plugins = plugin_utils.find_missing_plugins(plugins, opt_plugins, start_plugins)

    opt_plugins = map_install_folder(opt_plugins)
    start_plugins = map_install_folder(start_plugins)

    for _, plugin_config in pairs(plugins) do
      local plugin_name = plugin_config.short_name
      local plugin_source = (opt_plugins[plugin_name] and PLUGIN_OPTIONAL_LIST) or
        (start_plugins[plugin_name] and PLUGIN_START_LIST)

      if is_dirty(plugin_config, plugin_source) then
        dirty_plugins[#dirty_plugins+1] = plugin_name
      end
    end

    if next(dirty_plugins) then
      local lines = {}

      for _, plugin_name in ipairs(dirty_plugins) do
        table.insert(lines, '  - ' .. plugins[plugin_name].install_path)
      end

      if await(display.ask_user('Removing the following directories. OK? (y/N)', lines)) then
        results.removals = dirty_plugins
        if util.is_windows then
          for _, plugin_name in ipairs(vim.tbl_keys(dirty_plugins)) do
            os.execute('cmd /C rmdir /S /Q ' .. plugins[plugin_name].install_path)
          end
        else
          os.execute('rm -rf ' .. table.concat(map_names_to_paths(dirty_plugins), ' '))
        end
      else
        log.warning('Cleaning cancelled!')
      end
    else
      log.info("Already clean!")
    end
  end)
end

local function cfg(_config) config = _config end

local clean = setmetatable({cfg = cfg}, {__call = clean_plugins})
return clean
