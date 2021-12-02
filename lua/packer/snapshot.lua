local a = require 'packer.async'
local async = a.sync
local await = a.wait
local wait_all = a.wait_all
local fmt = string.format
local log = require 'packer.log'
local loop = vim.loop
local plugin_utils = require 'packer.plugin_utils'

local function cfg(_config)
  config = _config
end

---@class SnapshotResult
---@field ok table[]
---@field err table[]

---Serializes a table of git-plugins with `short_name` as table key and another
---table with `commit`; the serialized tables will be written in the path `snapshot_path`
---provided, if there is already a snapshot it will be overwritten
---Snapshotting work only with `plugin_utils.git_plugin_type` type of plugins,
---other will be ignored.
---@param snapshot_path string @ realpath for snapshot file
---@param plugins table[]
---@return SnapshotResult|string result @ `SnapshotResult` if snapshot has success,
--otherwise a string of the error message
local function snapshot(_, snapshot_path, plugins)
  assert(type(snapshot_path) == "string",
    fmt("filename needs to be a string but '%s' provided", type(snapshot_path)))
  assert(type(plugins) == "table",
    fmt("plugins needs to be an array but '%s' provided", type(plugins)))

  return async(function()
    local snapshot_plugins = {}
    ---@type SnapshotResult
    local completed = {}
    local not_completed = {}
    local result = {
      ok = completed,
      err = not_completed
    }
    local opt, start = plugin_utils.list_installed_plugins()
    local installed = {}

    for key, _ in pairs(opt) do installed[key] = key end
    for key, _ in pairs(start) do installed[key] = key end

    for _, plugin in pairs(plugins) do
      if installed[plugin.install_path] then -- this plugin is installed
        log.debug(fmt("Snapshotting '%s'", plugin.short_name))
        if plugin.type == plugin_utils.git_plugin_type then
          local rev = await(plugin.get_rev())

          if rev.err then

            local warn = fmt("Snapshotting %s failed because of error '%s'",
              plugin.short_name,
              rev.err
            )

            log.warn(warn)
            not_completed[#not_completed + 1] = {[plugin.short_name] = plugin, err = warn}
          else
            snapshot_plugins[plugin.short_name] = {commit = rev.ok}
            completed[#completed + 1] = plugin
          end
        end
      end
    end

    ---@type string
    local snapshot_content = "return " .. vim.inspect(snapshot_plugins)

    local fd = loop.fs_open(snapshot_path, "w", tonumber("600", 8))

    if fd == nil then
      local warn = fmt("Error on creation of snapshot '%s'",snapshot_path)
      log.warn(warn)
      return warn
    else
      local res = loop.fs_write(fd, snapshot_content)
      loop.fs_close(fd)
      if res ~= #snapshot_content then
        print(vim.inspect(snapshot_content))
        local warn = fmt(
          "Snapshot '%s' generation failed. Written '%d' bytes instead of '%d' ",
          snapshot_path,
          res,
          #snapshot_content
        )
        log.warn(warn)
        return warn
      end
    end

    return result
  end)
end

---Rollbacks `plugins` to the hash specified in `snapshot_path` if exists
---@param snapshot_path string @ realpath to the snapshot file
---@param plugins table[] @ list of `plugin_utils.git_plugin_type` type of plugins
---@return SnapshotResult|"stronzo" result @ `SnapshotResult` if rollback has success,
--otherwise a string of the error message
local function rollback(_, snapshot_path, plugins)
  return async(function()
    log.debug("Rolling back to " .. snapshot_path)
    local completed = {}
    local not_completed = {}
    local jobs = {}
    local snap_plugins = dofile(snapshot_path)

    if snap_plugins == nil then
      not_completed = vim.fn.map(plugins, function (_, plugin)
        return {
          [plugin.short_name] = plugin,
          error = fmt("Couldn't load '%s' file", snapshot_path)
        }
      end)
    else
      for _, plugin in pairs(plugins) do
        if snap_plugins[plugin.short_name] then
          local commit = snap_plugins[plugin.short_name].commit
          if commit ~= nil then
            jobs[#jobs + 1] = async(function ()
              local res = await(plugin.revert_to(commit))
              if res.err then
                log.error(res.err)
                not_completed[#not_completed] = {[plugin.short_name] = plugin, error = res.err}
              else
                completed[#completed + 1] = plugin
              end
            end)
          end
        end
      end

      wait_all(unpack(jobs))
    end

    return {ok = completed, err = not_completed}
  end)
end

--@class Snapshot @ Module that provides snapshotting feature
local M = {
  cfg = cfg,
  snapshot = snapshot,
  rollback = rollback
}

return M
