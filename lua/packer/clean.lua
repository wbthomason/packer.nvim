local plugin_utils = require('packer/plugin_utils')
local a            = require('packer/async')
local display      = require('packer/display')
local log          = require('packer/log')

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
    for _, plugin_list in ipairs({opt_plugins, start_plugins}) do
      for plugin_path, _ in pairs(plugin_list) do
        local plugin_name = vim.fn.fnamemodify(plugin_path, ":t")
        local plugin_data = plugins[plugin_name]
        if (plugin_data == nil) or (plugin_data.disable) then
          dirty_plugins[plugin_name] = plugin_path
        end
      end
    end

    if next(dirty_plugins) then
      local lines = {}
      for _, path in pairs(dirty_plugins) do
        table.insert(lines, '  - ' .. path)
      end

      if await(display.ask_user('Removing the following directories. OK? (y/N)', lines)) then
        results.removals = dirty_plugins
        return os.execute('rm -rf ' .. table.concat(vim.tbl_values(dirty_plugins), ' '))
      else
        log.warning('Cleaning cancelled!')
      end
    else
      log.info("Already clean!")
    end
  end)
end

local function cfg(_config)
  config = _config
end

local clean = setmetatable({ cfg = cfg }, { __call = clean_plugins })
return clean
