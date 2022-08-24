local a = require 'packer.async'
local log = require 'packer.log'
local util = require 'packer.util'
local display = require 'packer.display'
local plugin_utils = require 'packer.plugin_utils'

local fmt = string.format
local async = a.sync
local await = a.wait

local config = nil

local function install_plugin(plugin, display_win, results)
  local plugin_name = util.get_plugin_full_name(plugin)
  return async(function()
    display_win:task_start(plugin_name, 'installing...')
    -- TODO: If the user provided a custom function as an installer, we would like to use pcall
    -- here. Need to figure out how that integrates with async code
    local r = await(plugin.installer(display_win))
    r = r:and_then(await, plugin_utils.post_update_hook(plugin, display_win))
    if r.ok then
      display_win:task_succeeded(plugin_name, 'installed')
      log.debug('Installed ' .. plugin_name)
    else
      display_win:task_failed(plugin_name, 'failed to install')
      log.debug(fmt('Failed to install %s: %s', plugin_name, vim.inspect(r.err)))
    end

    results.installs[plugin_name] = r
    results.plugins[plugin_name] = plugin
  end)
end

local function do_install(_, plugins, missing_plugins, results)
  results = results or {}
  results.installs = results.installs or {}
  results.plugins = results.plugins or {}
  local display_win = nil
  local tasks = {}
  if #missing_plugins > 0 then
    display_win = display.open(config.display.open_fn or config.display.open_cmd)
    for _, v in ipairs(missing_plugins) do
      if not plugins[v].disable then
        table.insert(tasks, install_plugin(plugins[v], display_win, results))
      end
    end
  end

  return tasks, display_win
end

local function cfg(_config)
  config = _config
end

local install = setmetatable({ cfg = cfg }, { __call = do_install })

return install
