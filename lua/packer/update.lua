local util = require('packer/util')
local install = require('packer/install')
local plugin_utils = require('packer/plugin_utils')
local result = require('packer/result')
local display = require('packer/display')
local a = require('packer/async')
local log = require('packer/log')

local async = a.sync
local await = a.wait

local config = nil

local function get_plugin_status(plugins, plugin_name, start_plugins, opt_plugins)
  local status = {}
  local plugin = plugins[plugin_name]
  status.wrong_type = (plugin.opt
    and vim.tbl_contains(
      start_plugins,
      util.join_paths(config.start_dir, plugin_name))
    )
    or vim.tbl_contains(
      opt_plugins,
      util.join_paths(config.opt_dir, plugin_name)
    )
  return status
end

local function cfg(_config)
  config = _config
end

local function fix_plugin_type(plugin, results)
  local plugin_name = util.get_plugin_full_name(plugin)
  local from
  local to
  if plugin.opt then
    from = util.join_paths(config.start_dir, plugin.name)
    to   = util.join_paths(config.opt_dir, plugin.name)
  else
    from = util.join_paths(config.opt_dir, plugin.name)
    to   = util.join_paths(config.start_dir, plugin.name)
  end

  -- NOTE: If we stored all plugins somewhere off-package-path and used symlinks to put them in the
  -- right directories, this could be lighter-weight
  local success, msg = os.rename(from, to)
  if not success then
    log.error('Failed to move ' .. from .. ' to ' .. to .. ': ' .. msg)
  end

  results.moves[plugin_name] = { from = from, to = to, result = result.ok(success) }
end

local function fix_plugin_types(plugins, plugin_names, results)
  results = results or {}
  results.moves = results.moves or {}
  -- NOTE: This function can only be run on plugins already installed
  for _, v in ipairs(plugin_names) do
    local plugin = plugins[v]
    -- TODO: This will have to change when separate packages are implemented
    local install_dir = util.join_paths(plugin.opt and config.start_dir or config.opt_dir, plugin.name)
    if vim.fn.isdirectory(install_dir) == 1 then
      fix_plugin_type(plugin, results)
    end
  end
end

local function update_plugin(plugin, display_win, results)
  local plugin_name = util.get_plugin_full_name(plugin)
  -- TODO: This will have to change when separate packages are implemented
  local install_path = util.join_paths(config.pack_dir, plugin.opt and 'opt' or 'start', plugin.name)
  plugin.install_path = install_path
  return async(function()
    display_win:task_start(plugin_name, 'updating...')
    local r, info = unpack(await(plugin.updater(display_win)))
    if r.ok then
      local actual_update = info.revs[1] ~= info.revs[2]
      local msg = actual_update
        and ('updated: ' .. info.revs[1] .. '...' .. info.revs[2])
        or 'already up to date'
      if actual_update then
        if plugin.run then
          plugin.run(plugin, install_path)
        end
      end

      display_win:task_succeeded(plugin_name, msg)
    else
      display_win:task_failed(plugin_name, 'failed to update')
    end

    results.updates[plugin_name] = r
    results.plugins[plugin_name] = plugin
  end)
end

local function do_update(_, plugins, update_plugins, display_win, results)
  results                                  = results or {}
  results.updates                          = results.updates or {}
  results.plugins                          = results.plugins or {}
  local tasks = {}
  for _, v in ipairs(update_plugins) do
    local plugin = plugins[v]
    if not plugin.frozen then
      if display_win == nil then
        display_win = display.open(config.display.open_fn or config.display.open_cmd)
      end

      table.insert(tasks, update_plugin(plugin, display_win, results))
    end
  end

  if #tasks == 0 then
    log.info('Nothing to update!')
  end

  return tasks, display_win
end

local update = setmetatable({ cfg = cfg }, { __call = do_update })

update.get_plugin_status = get_plugin_status
update.fix_plugin_types = fix_plugin_types

return update
