local a = require 'packer.async'
local log = require 'packer.log'
local plugin_utils = require 'packer.plugin_utils'
local result = require 'packer.result'
local async = a.sync
local await = a.wait
local fmt = string.format

local config = nil
local data = {}

local function cfg(_config)
  config = _config
end

local lockfile = {
  cfg = cfg,
  is_updating = false,
}

local opt_args = {
  '--path=',
}

local function dofile_wrap(file)
  return dofile(file)
end

local function collect_commits(plugins)
  local completed = {}
  local failed = {}
  local opt, start = plugin_utils.list_installed_plugins()
  local installed = vim.tbl_extend('error', start, opt)

  plugins = vim.tbl_filter(function(plugin)
    if installed[plugin.install_path] then -- this plugin is installed
      return plugin
    end
  end, plugins)

  return async(function()
    for _, plugin in pairs(plugins) do
      local name = plugin.short_name
      if plugin.type == plugin_utils.local_plugin_type then
        -- If a local plugin exists in the current lockfile data then use that to keep conistant.
        -- Note: Since local plugins are ignored by the lockfile it will not try and change the local repo.
        if data[name] then
          completed[name] = data[name]
        end
      else
        local rev = await(plugin.get_rev())
        local date = await(plugin.get_date())
        if rev.err then
          failed[name] = fmt("Getting rev for '%s' failed because of error '%s'", name, vim.inspect(rev.err))
        elseif date.err then
          failed[name] = fmt("Getting date for '%s' failed because of error '%s'", name, vim.inspect(date.err))
        else
          completed[name] = { commit = rev.ok, date = date.ok }
        end
      end
    end

    return result.ok { failed = failed, completed = completed }
  end)
end

lockfile.completion = function(lead, _, _)
  if vim.startswith(lead, '-') then
    return vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
    end, opt_args)
  end
end

lockfile.load = function()
  local file = config.lockfile.path
  if vim.loop.fs_stat(file) == nil then
    log.warn(fmt("Lockfile: '%s' not found. Run `PackerLockfile` to generate", file))
    return
  end

  local ok, res = pcall(dofile_wrap, file)
  if not ok then
    log.error(fmt("Failed loading '%s' lockfile: '%s'", file, res))
  else
    data = res
  end
end

lockfile.get = function(name)
  return data[name] or {}
end

lockfile.update = function(plugins, path)
  local lines = {}
  return async(function()
    local commits = await(collect_commits(plugins))

    for name, commit in pairs(commits.ok.completed) do
      lines[#lines + 1] = fmt([[  ["%s"] = { commit = "%s", date = %s },]], name, commit.commit, commit.date)
    end

    -- Lines are sorted so that the diff will only contain changes not random re-ordering
    table.sort(lines)
    table.insert(lines, '}')
    table.insert(lines, 1, 'return {')
    table.insert(lines, 1, '-- Automatically generated by packer.nvim')

    await(a.main)
    local status, res = pcall(function()
      return vim.fn.writefile(lines, path) == 0
    end)

    if status and res then
      return result.ok {
        message = fmt('Lockfile written to %s', path),
        failed = commits.ok.failed,
      }
    else
      return result.err { message = fmt("Error on creating lockfile '%s': '%s'", path, res) }
    end
  end)
end

return lockfile
