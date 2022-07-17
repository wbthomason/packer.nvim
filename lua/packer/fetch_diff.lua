local util = require 'packer.util'
local display = require 'packer.display'
local a = require 'packer.async'
local log = require 'packer.log'
local update = require 'packer.update'
local plugin_utils = require 'packer.plugin_utils'

local fmt = string.format
local async = a.sync
local await = a.wait

local config = nil

local function cfg(_config)
  config = _config
end

local function fetch_diff_plugin(plugin, display_win, results)
  local plugin_name = util.get_plugin_full_name(plugin)
  -- TODO: This will have to change when separate packages are implemented
  local install_path = util.join_paths(config.pack_dir, plugin.opt and 'opt' or 'start', plugin.short_name)
  plugin.install_path = install_path
  return async(function()
    if plugin.lock or plugin.disable then
      return
    end
    display_win:task_start(plugin_name, 'fetching...')
    local r = await(plugin.fetcher(display_win))
    if r ~= nil and r.ok then
      if plugin.type == plugin_utils.git_plugin_type and r.diff then
        display_win:task_status('item_sym', plugin_name, 'changes to fetch')
      else
        display_win:task_status('item_sym', plugin_name, 'up to date')
      end

    else
      display_win:task_failed(plugin_name, 'failed to fetch')
      local errmsg = '<unknown error>'
      if r ~= nil and r.err ~= nil then
        errmsg = r.err
      end
      log.debug(fmt('Failed to fetch %s: %s', plugin_name, vim.inspect(errmsg)))
    end

    results.fetches[plugin_name] = r
    results.plugins[plugin_name] = plugin
  end)
end

local function do_fetch_diff(_, plugins, update_plugins, display_win, results)
  results = results or {}
  results.fetches = results.fetches or {}
  results.plugins = results.plugins or {}
  local tasks = {}
  for _, v in ipairs(update_plugins) do
    local plugin = plugins[v]
    if not plugin.frozen then
      if display_win == nil then
        display_win = display.open(config.display.open_fn or config.display.open_cmd)
      end

      table.insert(tasks, fetch_diff_plugin(plugin, display_win, results))
    end
  end

  if #tasks == 0 then
    log.info 'Nothing to update!'
  end

  return tasks, display_win
end

local fetch_diff = setmetatable({ cfg = cfg }, { __call = do_fetch_diff })

fetch_diff.get_plugin_status = update.get_plugin_status
fetch_diff.fix_plugin_types = update.fix_plugin_types

return fetch_diff
