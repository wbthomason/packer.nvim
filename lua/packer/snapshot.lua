local a = require 'packer.async'
local util = require 'packer.util'
local log = require 'packer.log'
local plugin_utils = require 'packer.plugin_utils'
local plugin_complete = require('packer').plugin_complete
local async = a.sync
local await = a.wait
local wait_all = a.wait_all
local fmt = string.format
local loop = vim.loop

local config = {}

local snapshot = {
  completion = {}
}

snapshot.cfg = function(_config)
  config = _config
end

--- Completion for listing snapshots in `config.snapshot_path`
--- Intended to provide completion for PackerDelete command
snapshot.completion.snapshot = function(lead, cmdline, pos)
  local completion_list = {}
  if config.snapshot_path == nil then
    return completion_list
  end

  local dir = vim.loop.fs_opendir(config.snapshot_path)

  if dir ~= nil then
    local res = vim.loop.fs_readdir(dir)
    while res ~= nil do
      for _, entry in ipairs(res) do
        if entry.type == "file" and vim.startswith(entry.name, lead) then
          completion_list[#completion_list + 1] = entry.name
        end
      end

      res = vim.loop.fs_readdir(dir)
    end
  end

  vim.loop.fs_closedir(dir)
  return completion_list
end

--- Completion for listing single plugins before taking snapshot
--- Intended to provide completion for PackerSnapshot command
snapshot.completion.create = function (lead, cmdline, pos)
  local cmd_args = (vim.fn.split(cmdline, " "))

  if #cmd_args > 1 then
    return plugin_complete(lead, cmdline, pos)
  end

  return {}
end

--- Completion for listing snapshots in `config.snapshot_path` and single plugins after
--- the first argument is provided
--- Intended to provide completion for PackerRollback command
snapshot.completion.rollback = function (lead, cmdline, pos)
  local cmd_args = vim.split(cmdline, " ")

  if #cmd_args > 2 then
    return plugin_complete(lead)
  else
    return snapshot.completion.snapshot(lead, cmdline, pos)
  end
end

---Serializes a table of git-plugins with `short_name` as table key and another
---table with `commit`; the serialized tables will be written in the path `snapshot_path`
---provided, if there is already a snapshot it will be overwritten
---Snapshotting work only with `plugin_utils.git_plugin_type` type of plugins,
---other will be ignored.
---@param snapshot_path string realpath for snapshot file
---@param plugins table<string, any>[]
snapshot.create = function(snapshot_path, plugins)
  assert(type(snapshot_path) == "string",
    fmt("filename needs to be a string but '%s' provided", type(snapshot_path)))
  assert(type(plugins) == "table",
    fmt("plugins needs to be an array but '%s' provided", type(plugins)))

  return async(function()
    local snapshot_plugins = {}
    local installed = {}
    local opt, start = plugin_utils.list_installed_plugins()

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
          else
            snapshot_plugins[plugin.short_name] = {commit = rev.ok}
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
    else
      local res = loop.fs_write(fd, snapshot_content)
      loop.fs_close(fd)
      if res ~= #snapshot_content then
        local warn = fmt(
          "Snapshot '%s' generation failed. Written '%d' bytes instead of '%d' ",
          snapshot_path, res, #snapshot_content
        )
        log.warn(warn)
      end
    end

  end)
end

---Rollbacks `plugins` to the hash specified in `snapshot_path` if exists
---@param snapshot_path string realpath to the snapshot file
---@param plugins table<string, any>[] list of `plugin_utils.git_plugin_type` type of plugins
snapshot.rollback = function(snapshot_path, plugins)
  return async(function()
    log.debug("Rolling back to " .. snapshot_path)
    local snap_plugins = dofile(snapshot_path)

    if snap_plugins == nil then -- not valid snapshot file
      local err = fmt("Couldn't load '%s' file", snapshot_path)
      log.warn(err)
    else
      local jobs = {}
      for _, plugin in pairs(plugins) do
        if snap_plugins[plugin.short_name] then
          local commit = snap_plugins[plugin.short_name].commit
          if commit ~= nil then
            jobs[#jobs + 1] = async(function ()
              local res = await(plugin.revert_to(commit))
              if res.err then
                log.error(res.err)
              end
            end)
          end
        end
      end

      wait_all(unpack(jobs))
    end
  end)
end

---Deletes the snapshot provided
---@param snapshot_name string absolute path or just a snapshot name
snapshot.delete = function (snapshot_name)
  return async(function ()
    assert(type(snapshot_name) == "string", fmt("Expected string, got %s", type(snapshot_name)))
    ---@type string
    local snapshot_path = vim.loop.fs_realpath(snapshot_name) or
      vim.loop.fs_realpath(util.join_paths(config.snapshot_path, snapshot_name))

    if snapshot_path == nil then
      log.warn(fmt("Snapshot '%s' is wrong or doesn't exist", snapshot_name))
      return
    end

    log.debug("Deleting " .. snapshot_path)
    if vim.loop.fs_unlink(snapshot_path) then
      log.info("Deleted " .. snapshot_path)
    else
      log.warn("Couldn't delete " .. snapshot_path)
    end
  end)
end

return snapshot
