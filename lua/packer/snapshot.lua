local a = require 'packer.async'
local util = require 'packer.util'
local log = require 'packer.log'
local plugin_utils = require 'packer.plugin_utils'
local plugin_complete = require('packer').plugin_complete
local result = require 'packer.result'
local async = a.sync
local await = a.wait
local fmt = string.format

local config = {}

local snapshot = {
  completion = {},
}

snapshot.cfg = function(_config)
  config = _config
end

--- Completion for listing snapshots in `config.snapshot_path`
--- Intended to provide completion for PackerSnapshotDelete command
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
        if entry.type == 'file' and vim.startswith(entry.name, lead) then
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
snapshot.completion.create = function(lead, cmdline, pos)
  local cmd_args = (vim.fn.split(cmdline, ' '))

  if #cmd_args > 1 then
    return plugin_complete(lead, cmdline, pos)
  end

  return {}
end

--- Completion for listing snapshots in `config.snapshot_path` and single plugins after
--- the first argument is provided
--- Intended to provide completion for PackerSnapshotRollback command
snapshot.completion.rollback = function(lead, cmdline, pos)
  local cmd_args = vim.split(cmdline, ' ')

  if #cmd_args > 2 then
    return plugin_complete(lead)
  else
    return snapshot.completion.snapshot(lead, cmdline, pos)
  end
end

--- Creates a with with `completed` and `failed` keys, each containing a map with plugin name as key and commit hash/error as value
--- @param plugins list
--- @return { ok: { failed : table<string, string>, completed : table<string, string>}}
local function generate_snapshot(plugins)
  local completed = {}
  local failed = {}
  local opt, start = plugin_utils.list_installed_plugins()
  local installed = vim.tbl_extend('error', start, opt)

  plugins = vim.tbl_filter(function(plugin)
    if installed[plugin.install_path] and plugin.type == plugin_utils.git_plugin_type then -- this plugin is installed
      return plugin
    end
  end, plugins)
  return async(function()
    for _, plugin in pairs(plugins) do
      local rev = await(plugin.get_rev())

      if rev.err then
        failed[plugin.short_name] =
          fmt("Snapshotting %s failed because of error '%s'", plugin.short_name, vim.inspect(rev.err))
      else
        completed[plugin.short_name] = { commit = rev.ok }
      end
    end

    return result.ok { failed = failed, completed = completed }
  end)
end

---Serializes a table of git-plugins with `short_name` as table key and another
---table with `commit`; the serialized tables will be written in the path `snapshot_path`
---provided, if there is already a snapshot it will be overwritten
---Snapshotting work only with `plugin_utils.git_plugin_type` type of plugins,
---other will be ignored.
---@param snapshot_path string realpath for snapshot file
---@param plugins table<string, any>[]
snapshot.create = function(snapshot_path, plugins)
  assert(type(snapshot_path) == 'string', fmt("filename needs to be a string but '%s' provided", type(snapshot_path)))
  assert(type(plugins) == 'table', fmt("plugins needs to be an array but '%s' provided", type(plugins)))
  return async(function()
    local commits = await(generate_snapshot(plugins))

    await(a.main)
    local snapshot_content = vim.fn.json_encode(commits.ok.completed)

    local status, res = pcall(function()
      return vim.fn.writefile({ snapshot_content }, snapshot_path) == 0
    end)

    if status and res then
      return result.ok {
        message = fmt("Snapshot '%s' complete", snapshot_path),
        completed = commits.ok.completed,
        failed = commits.ok.failed,
      }
    else
      return result.err { message = fmt("Error on creation of snapshot '%s': '%s'", snapshot_path, res) }
    end
  end)
end

local function fetch(plugin)
  local git = require 'packer.plugin_types.git'
  local opts = { capture_output = true, cwd = plugin.install_path, options = { env = git.job_env } }

  return async(function()
    return await(require('packer.jobs').run('git ' .. config.git.subcommands.fetch, opts))
  end)
end

---Rollbacks `plugins` to the hash specified in `snapshot_path` if exists.
---It automatically runs `git fetch --depth 999999 --progress` to retrieve the history
---@param snapshot_path string @ realpath to the snapshot file
---@param plugins list @ of `plugin_utils.git_plugin_type` type of plugins
---@return {ok: {completed: table<string, string>, failed: table<string, string[]>}}
snapshot.rollback = function(snapshot_path, plugins)
  assert(type(snapshot_path) == 'string', 'snapshot_path: expected string but got ' .. type(snapshot_path))
  assert(type(plugins) == 'table', 'plugins: expected table but got ' .. type(snapshot_path))
  log.debug('Rolling back to ' .. snapshot_path)
  local content = vim.fn.readfile(snapshot_path)
  ---@type string
  local plugins_snapshot = vim.fn.json_decode(content)
  if plugins_snapshot == nil then -- not valid snapshot file
    return result.err(fmt("Couldn't load '%s' file", snapshot_path))
  end

  local completed = {}
  local failed = {}

  return async(function()
    for _, plugin in pairs(plugins) do
      local function err_handler(err)
        failed[plugin.short_name] = failed[plugin.short_name] or {}
        failed[plugin.short_name][#failed[plugin.short_name] + 1] = err
      end

      if plugins_snapshot[plugin.short_name] then
        local commit = plugins_snapshot[plugin.short_name].commit
        if commit ~= nil then
          await(fetch(plugin))
            :map_err(err_handler)
            :and_then(await, plugin.revert_to(commit))
            :map_ok(function(ok)
              completed[plugin.short_name] = ok
            end)
            :map_err(err_handler)
        end
      end
    end

    return result.ok { completed = completed, failed = failed }
  end)
end

---Deletes the snapshot provided
---@param snapshot_name string absolute path or just a snapshot name
snapshot.delete = function(snapshot_name)
  assert(type(snapshot_name) == 'string', fmt('Expected string, got %s', type(snapshot_name)))
  ---@type string
  local snapshot_path = vim.loop.fs_realpath(snapshot_name)
    or vim.loop.fs_realpath(util.join_paths(config.snapshot_path, snapshot_name))

  if snapshot_path == nil then
    local warn = fmt("Snapshot '%s' is wrong or doesn't exist", snapshot_name)
    log.warn(warn)
    return
  end

  log.debug('Deleting ' .. snapshot_path)
  if vim.loop.fs_unlink(snapshot_path) then
    local info = 'Deleted ' .. snapshot_path
    log.info(info)
  else
    local warn = "Couldn't delete " .. snapshot_path
    log.warn(warn)
  end
end

return snapshot
