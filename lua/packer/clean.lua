local plugin_utils = require('packer.plugin_utils')
local a = require('packer.async')
local display = require('packer.display')
local log = require('packer.log')
local util = require('packer.util')

local await = a.wait
local async = a.sync

local config = nil

-- Find and remove any plugins not currently configured for use
local clean_plugins = function(_, plugins, results)
  return async(function()
    results = results or {}
    results.removals = results.removals or {}
    local opt_plugins, start_plugins = plugin_utils.list_installed_plugins()
    local dirty_plugins = {}
    local aliases = {}
    for _, plugin in pairs(plugins) do
      if plugin.as and not plugin.disable then aliases[plugin.as] = true end
    end

    for _, plugin_list in ipairs({opt_plugins, start_plugins}) do
      for plugin_path, _ in pairs(plugin_list) do
        local plugin_name = vim.fn.fnamemodify(plugin_path, ":t")
        local plugin_data = plugins[plugin_name]
        if (plugin_data == nil and not aliases[plugin_name]) or (plugin_data and plugin_data.disable) then
          dirty_plugins[plugin_name] = plugin_path
        end
      end
    end

    if next(dirty_plugins) then
      local lines = {}
      for _, path in pairs(dirty_plugins) do table.insert(lines, '  - ' .. path) end
      if await(display.ask_user('Removing the following directories. OK? (y/N)', lines)) then
        results.removals = dirty_plugins
        if util.is_windows then
          for _, x in ipairs(vim.tbl_values(dirty_plugins)) do
            os.execute('cmd /C rmdir /S /Q ' .. x)
          end
        else
          os.execute('rm -rf ' .. table.concat(vim.tbl_values(dirty_plugins), ' '))
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
