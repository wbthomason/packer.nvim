local util = require('packer/util')
local log  = require('packer/log')
local jobs = require('packer/jobs')
local a    = require('packer/async')

local vim = vim

local git = {}

local config = {}
git.set_config = function(cmd, subcommands, base_dir, default_pkg)
  config.git = cmd .. ' '
  config.cmds = subcommands
  config.base_dir = base_dir
  config.default_base_dir = util.join_paths(base_dir, default_pkg)
end

local function was_successful(result)
  return result.exit_code == 0
    and (not result.output or not result.output.err or #result.output.err == 0)
end

local handle_checkouts = function(plugin, dest, disp)
  local plugin_name = util.get_plugin_full_name(plugin)
  return a.sync(function()
    disp:task_update(plugin_name, 'fetching reference...')
    local output = { err = {}, data = {} }
    local logger = jobs.make_logging_callback(output.err, output.data)
    local callbacks = {
      stdout = logger,
      stderr = logger
    }

    local result = a.wait(jobs.run(config.git .. vim.fn.printf(config.cmds.fetch, dest), callbacks))
    if not was_successful(result) then
      log.error('Error fetching ' .. plugin_name)
      result.output = output
      return result
    end

    if plugin.branch then
      disp:task_update(plugin_name 'updating branch ' .. plugin.branch .. '...')
      result = a.wait(jobs.run(config.git .. vim.fn.printf(config.cmds.update_branch, dest), callbacks))
      if not was_successful(result) then
        log.error('Error updating branch for ' .. plugin_name)
        result.output = output
        return result
      end

      disp:task_update(plugin_name 'checking out branch ' .. plugin.branch .. '...')
      result = a.wait(jobs.run(config.git .. vim.fn.printf(config.cmds.checkout, dest, plugin.branch), callbacks))
      if not was_successful(result) then
        log.error('Error checking out branch for ' .. plugin_name)
        result.output = output
        return result
      end
    end

    if plugin.rev then
      disp:task_update(plugin_name, 'checking out ' .. plugin.rev .. '...')
      result = a.wait(jobs.run(config.git .. vim.fn.printf(config.cmds.checkout, dest, plugin.rev), callbacks))
    end

    result.output = output
    return result
  end)
end

git.make_installer = function(plugin)
  local plugin_name = util.get_plugin_full_name(plugin)
  local needs_checkout = plugin.rev ~= nil or plugin.branch ~= nil
  local base_dir
  if plugin.package then
    base_dir = util.join_paths(config.base_dir, plugin.package)
  else
    base_dir = config.default_base_dir
  end

  base_dir = util.join_paths(base_dir, plugin.opt and 'opt' or 'start')
  local install_to = util.join_paths(base_dir, plugin.short_name)
  local install_cmd = config.git .. vim.fn.printf(config.cmds.install, plugin.url, install_to)
  local rev_cmd = config.git .. vim.fn.printf(config.cmds.get_rev, install_to)
  local update_cmd = config.git .. vim.fn.printf(config.cmds.update, install_to)
  local commit_cmd = vim.split(config.git .. vim.fn.printf(config.cmds.get_msg, install_to), '%s+')
  for i, arg in ipairs(commit_cmd) do
    commit_cmd[i] = string.gsub(arg, 'FMT', config.cmds.diff_fmt)
  end

  local messages_cmd = vim.split(config.git .. vim.fn.printf(config.cmds.diff, install_to), '%s+')
  for i, arg in ipairs(messages_cmd) do
    messages_cmd[i] = string.gsub(arg, 'FMT', config.cmds.diff_fmt)
  end

  if plugin.branch then
    install_cmd = install_cmd .. ' --branch ' .. plugin.branch
  end

  plugin.installer = function(disp)
    return a.sync(function()
      disp:task_update(plugin_name, 'cloning...')
      local result = a.wait(jobs.run(install_cmd, true))
      plugin.output = result.output
      if was_successful(result) then
        if needs_checkout then
          result = a.wait(handle_checkouts(plugin, install_to, disp))
          plugin.output.data = vim.list_extend(plugin.output.data, result.output.data)
          plugin.output.err = vim.list_extend(plugin.output.err, result.output.err)
        end
      end
      if not was_successful(result) then
        return false
      end

      result = a.wait(jobs.run(rev_cmd, true))
      if not was_successful(result) then
        return false
      end

      plugin.revs = result.output.data
      result = a.wait(jobs.run(commit_cmd, true))

      if was_successful(result) then
        plugin.messages = result.output.data
        return true
      end

      return false
    end)
  end

  plugin.updater = function(disp)
    return a.sync(function()
      local update_info = {
        err = {},
        revs = {},
        output = {},
        messages = {}
      }

      local function exit_ok(result)
        if #update_info.err > 0 then
          return false
        end

        return result.exit_code == 0
      end

      local rev_onread = jobs.make_logging_callback(update_info.err, update_info.revs)
      local rev_callbacks = {
        stdout = rev_onread,
        stderr = rev_onread,
      }

      disp:task_update(plugin_name, 'checking current commit...')
      local result = a.wait(jobs.run(rev_cmd, rev_callbacks))
      if not exit_ok(result) then
        plugin.output = { err = update_info.err, data = update_info.output }
        plugin.output.err = vim.list_extend(plugin.output.err, update_info.revs)
        return { false, update_info }
      end

      local update_onread = jobs.make_logging_callback(update_info.err, update_info.output)
      local update_callbacks = {
        stdout = update_onread,
        stderr = update_onread,
      }

      disp:task_update(plugin_name, 'pulling updates...')
      result = a.wait(jobs.run(update_cmd, update_callbacks))
      if not exit_ok(result) then
        plugin.output = { err = update_info.err, data = update_info.output }
        return { false, update_info }
      end

      if needs_checkout then
        result = a.wait(handle_checkouts(plugin, install_to, disp))
        update_info.err = vim.list_extend(update_info.err, result.output.err)
        update_info.output = vim.list_extend(update_info.output, result.output.data)
        if not exit_ok(result) then
          plugin.output = { err = update_info.err, data = update_info.output }
          return { false, update_info }
        end
      end

      disp:task_update(plugin_name, 'checking updated commit...')
      result = a.wait(jobs.run(rev_cmd, rev_callbacks))
      if not exit_ok(result) then
        plugin.output = { err = update_info.err, data = update_info.output }
        plugin.output.err = vim.list_extend(plugin.output.err, update_info.revs)
        return { false, update_info }
      end

      local messages_onread = jobs.make_logging_callback(update_info.err, update_info.messages)
      local messages_callbacks = {
        stdout = messages_onread,
        stderr = messages_onread,
      }

      disp:task_update(plugin_name, 'getting commit messages...')
      result = a.wait(jobs.run(messages_cmd, messages_callbacks))
      plugin.output = { err = update_info.err, data = update_info.output }
      if exit_ok(result) then
        plugin.messages = update_info.messages
        plugin.revs = update_info.revs
        return { true, update_info }
      elseif update_info.messages[1] == "fatal: log for 'HEAD' only has 1 entries" then
        plugin.revs = update_info.revs
        plugin.messages = update_info.messages
        result = a.wait(jobs.run(commit_cmd, true))
        if was_successful(result) then
          plugin.messages = result.output.data
        end

        return { was_successful(result), update_info }
      else
        plugin.output.err = vim.list_extend(plugin.output.err, update_info.messages)
        return { false, update_info }
      end
    end)
  end
end

return git
