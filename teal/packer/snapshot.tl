local a = require 'packer.async'
local util = require 'packer.util'
local log = require 'packer.log'
local plugin_utils = require 'packer.plugin_utils'
local async = a.sync
local fmt = string.format
local uv = vim.loop

local config = require'packer.config'

local record M
  record SResult
    err: boolean
    message: string
    record Completed
      commit: string
    end
    completed: {string:Completed}
    failed: {string:string}
  end
  record Completion
    snapshot: function(string, string, integer): {string}
    create  : function(string, string, integer): {string}
    rollback: function(string, string, integer): {string}
  end
  completion: Completion

  rollback : function(snapshot_path: string, plugins: {string:Plugin}): SResult
  create   : function(snapshot_path: string, plugins: {string:Plugin}): SResult
end

M.completion = {}

--- Completion for listing snapshots in `config.snapshot_path`
--- Intended to provide completion for PackerSnapshotDelete command
M.completion.snapshot = function(lead: string, _: string, _: integer): {string}
  local completion_list = {}
  if config.snapshot_path == nil then
    return completion_list
  end

  local dir = uv.fs_opendir(config.snapshot_path)

  if dir ~= nil then
    local res = uv.fs_readdir(dir)
    while res ~= nil do
      for _, entry in ipairs(res) do
        if entry.type == 'file' and vim.startswith(entry.name, lead) then
          completion_list[#completion_list + 1] = entry.name
        end
      end

      res = uv.fs_readdir(dir)
    end
  end

  dir:closedir()
  return completion_list
end

-- Completion user plugins
-- Intended to provide completion for PackerUpdate/Sync/Install command
local function plugin_complete(lead: string, _: string, _: integer): {string}
  local completion_list = vim.tbl_filter(function(name: string): boolean
    return vim.startswith(name, lead)
  end, vim.tbl_keys(_G.packer_plugins))
  table.sort(completion_list)
  return completion_list
end

--- Completion for listing single plugins before taking snapshot
--- Intended to provide completion for PackerSnapshot command
M.completion.create = function(lead:string, cmdline:string, pos:integer): {string}
  local cmd_args = (vim.split(cmdline, '%s+'))

  if #cmd_args > 1 then
    return plugin_complete(lead, cmdline, pos)
  end

  return {}
end

--- Completion for listing snapshots in `config.snapshot_path` and single plugins after
--- the first argument is provided
--- Intended to provide completion for PackerSnapshotRollback command
M.completion.rollback = function(lead:string, cmdline:string, pos:integer): {string}
  local cmd_args = vim.split(cmdline, ' ')

  if #cmd_args > 2 then
    return plugin_complete(lead)
  else
    return M.completion.snapshot(lead, cmdline, pos)
  end
end

---Creates a with with `completed` and `failed` keys, each containing a map with plugin name as key and commit hash/error as value
local generate_snapshot = async(function(plugins:{string:Plugin}): M.SResult
  local completed = {}
  local failed = {}
  local opt, start = plugin_utils.list_installed_plugins()
  local installed = vim.tbl_extend('error', start, opt)

  plugins = vim.tbl_filter(function(plugin: Plugin): boolean
    if installed[plugin.install_path] and plugin.type == 'git' then
      return true
    end
    return false
  end, plugins)

  for _, plugin in pairs(plugins) do
    local plugin_type = require'packer.plugin_types'[plugin.type]
    local rev, err = plugin_type.get_rev(plugin)

    if err then
      failed[plugin.name] =
        fmt("Snapshotting %s failed because of error '%s'", plugin.name, err)
    else
      completed[plugin.name] = { commit = rev } as M.SResult.Completed
    end
  end

  return { failed = failed, completed = completed }
end, 1)

---Serializes a table of git-plugins with `name` as table key and another
---table with `commit`; the serialized tables will be written in the path `snapshot_path`
---provided, if there is already a snapshot it will be overwritten
---Snapshotting work only with git plugins,
---other will be ignored.
M.create = async(function(snapshot_path: string, plugins: {string:Plugin}): M.SResult
  assert(type(snapshot_path) == 'string', fmt("filename needs to be a string but '%s' provided", type(snapshot_path)))
  assert(type(plugins) == 'table', fmt("plugins needs to be an array but '%s' provided", type(plugins)))
  local commits = generate_snapshot(plugins)

  a.main()

  local snapshot_content = vim.json.encode(commits.completed)

  local status, res = pcall(function(): boolean
    return vim.fn.writefile({ snapshot_content }, snapshot_path) == 0
  end)

  if status and res then
    return {
      message = fmt("Snapshot '%s' complete", snapshot_path),
      completed = commits.completed,
      failed = commits.failed,
    }
  else
    return {
      err = true,
      message = fmt("Error on creation of snapshot '%s': '%s'", snapshot_path, res)
    }
  end
end, 2)

---Rollbacks `plugins` to the hash specified in `snapshot_path` if exists.
---It automatically runs `git fetch --depth 999999 --progress` to retrieve the history
M.rollback = async(function(_snapshot_path: string, _plugins: {string:Plugin}): M.SResult
  return { message = 'Not implemented' }
  -- assert(type(snapshot_path) == 'string', 'snapshot_path: expected string but got ' .. type(snapshot_path))
  -- assert(type(plugins) == 'table', 'plugins: expected table but got ' .. type(snapshot_path))
  -- log.debug('Rolling back to ' .. snapshot_path)

  -- local content = table.concat(vim.fn.readfile(snapshot_path), '\n')

  -- local plugins_snapshot = vim.json.decode(content) as {string:Plugin}
  -- if not plugins_snapshot then -- not valid snapshot file
  --   local r: M.SResult = { message = fmt("Couldn't load '%s' file", snapshot_path) }
  --   return result.err(r)
  -- end

  -- local completed: {string:M.SResult.Completed} = {}
  -- local failed = {}

  -- for _, plugin in pairs(plugins) do
  --   if plugins_snapshot[plugin.name] then
  --     local commit = plugins_snapshot[plugin.name].commit
  --     if commit then
  --       local fetch_cmd = {config.git.cmd, 'fetch', '--depth', '999999', '--progress'}
  --       local r = require('packer.jobs').run(fetch_cmd, {
  --         capture_output = true,
  --         cwd = plugin.install_path,
  --         env = git.job_env
  --       })

  --       if r.ok then
  --         r = git.revert_to(plugin, commit)
  --       end

  --       if r.ok then
  --         completed[plugin.name] = r.ok
  --       else
  --         failed[plugin.name] = failed[plugin.name] or {}
  --         table.insert(failed[plugin.name], r.err)
  --       end
  --     end
  --   end
  -- end

  -- return ok {
  --   completed = completed,
  --   failed    = failed
  -- }
end, 2)

---Deletes the snapshot provided
function M.delete(snapshot_name: string)
  assert(type(snapshot_name) == 'string', fmt('Expected string, got %s', type(snapshot_name)))
  local snapshot_path = uv.fs_realpath(snapshot_name)
    or uv.fs_realpath(util.join_paths(config.snapshot_path, snapshot_name))

  if snapshot_path == nil then
    log.warn(fmt("Snapshot '%s' is wrong or doesn't exist", snapshot_name))
    return
  end

  log.debug('Deleting ' .. snapshot_path)
  if uv.fs_unlink(snapshot_path) then
    log.info('Deleted ' .. snapshot_path)
  else
    log.warn("Couldn't delete " .. snapshot_path)
  end
end

return M
