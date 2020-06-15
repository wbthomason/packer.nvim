local util   = require('packer/util')
local log    = require('packer/log')
local jobs   = require('packer/jobs')
local a      = require('packer/async')
local result = require('packer/result')
local await = a.wait
local async = a.sync

local vim = vim

local git = {}

local config = {}
git.set_config = function(cmd, subcommands, base_dir, default_pkg)
  config.git = cmd .. ' '
  config.cmds = subcommands
  config.base_dir = base_dir
  config.default_base_dir = util.join_paths(base_dir, default_pkg)
end

local handle_checkouts = function(plugin, dest, disp)
  local plugin_name = util.get_plugin_full_name(plugin)
  return async(function()
    disp:task_update(plugin_name, 'fetching reference...')
    local output = jobs.output_table()
    local callbacks = {
      stdout = jobs.logging_callback(output.err.stdout, output.data.stdout),
      stderr = jobs.logging_callback(output.err.stderr, output.data.stderr)
    }

    local opts = { capture_output = callbacks }

    local r = await(jobs.run(config.git .. vim.fn.printf(config.cmds.fetch, dest), opts))
      :map_err(function(err) return { msg = 'Error fetching ' .. plugin_name, data = err } end)

    if plugin.branch then
      disp:task_update(plugin_name 'updating branch ' .. plugin.branch .. '...')
      r = r:and_then(
        await,
        jobs.run(config.git .. vim.fn.printf(config.cmds.update_branch, dest), opts)
      )
        :map_err(function(err)
          return {
            msg = 'Error updating branch ' .. plugin.branch .. ' for ' .. plugin_name,
            data = err
          }
        end)

      disp:task_update(plugin_name 'checking out branch ' .. plugin.branch .. '...')
      r = r:and_then(
        await,
        jobs.run(config.git .. vim.fn.printf(config.cmds.checkout, dest, plugin.branch), opts)
      )
        :map_err(function(err)
          return {
            msg = 'Error checking out branch ' .. plugin.branch .. ' for ' .. plugin_name,
            data = err
          }
        end)
    end

    if plugin.rev then
      disp:task_update(plugin_name, 'checking out ' .. plugin.rev .. '...')
      r = r:and_then(
        await,
        jobs.run(config.git .. vim.fn.printf(config.cmds.checkout, dest, plugin.rev), opts)
      )
        :map_err(function(err)
          return {
            msg = 'Error checking out revision ' .. plugin.rev .. ' for ' .. plugin_name,
            data = err
          }
        end)
    end

    return r:map_ok(function(ok) return { status = ok, output = output } end)
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

  local installer_opts = { capture_output = true }
  plugin.installer = function(disp)
    return async(function()
      disp:task_update(plugin_name, 'cloning...')
      local r = await(jobs.run(install_cmd, installer_opts))
      r:map_ok(function(ok) plugin.output = ok.output end)
      if needs_checkout then
        r = r:and_then(await, handle_checkouts(plugin, install_to, disp))
        r:map_ok(function(ok)
          plugin.output.data = jobs.extend_output(plugin.output.data, ok.output.data)
        end)
          :map_err(function(err)
            plugin.output.data = jobs.extend_output(plugin.output.data, err.output.data)
            plugin.output.err = jobs.extend_output(plugin.output.err, err.output.err)
          end)
      end

      r = r:and_then(await, jobs.run(rev_cmd, installer_opts))
        :map_ok(function(ok) plugin.revs = ok.output.data.stderr end)
      r = r:and_then(await, jobs.run(commit_cmd, { capture_output = true }))
        :map_ok(function(ok) plugin.messages = ok.output.data.stderr end)

      return r
    end)
  end

  plugin.updater = function(disp)
    return async(function()
      local update_info = {
        err = {},
        revs = {},
        output = {},
        messages = {}
      }

      local function exit_ok(r)
        if #update_info.err > 0 or r.exit_code ~= 0 then
          return result.err(r)
        end

        return result.ok(r)
      end

      local rev_onread = jobs.logging_callback(update_info.err, update_info.revs)
      local rev_callbacks = {
        stdout = rev_onread,
        stderr = rev_onread,
      }

      disp:task_update(plugin_name, 'checking current commit...')
      local r = await(
        jobs.run(rev_cmd, { success_test = exit_ok, capture_output = rev_callbacks })
      )
        :map_err(function(err)
          plugin.output = {
            err = vim.list_extend(update_info.err, update_info.revs),
            data = {}
          }

          return err
        end)

      local update_onread = jobs.logging_callback(update_info.err, update_info.output)
      local update_callbacks = {
        stdout = update_onread,
        stderr = update_onread,
      }

      disp:task_update(plugin_name, 'pulling updates...')
      r = r:and_then(
        await,
        jobs.run(update_cmd, { success_test = exit_ok, capture_output = update_callbacks})
      )
        :map_err(function(err)
          plugin.output = {
            err = vim.list_extend(update_info.err, update_info.output),
            data = {}
          }

          return err
        end)

      if needs_checkout then
        r = r:and_then(await, handle_checkouts(plugin, install_to, disp))
        local function merge_output(res)
          update_info.err = vim.list_extend(
            update_info.err,
            res.output.err.stderr,
            res.output.err.stdout
          )
          update_info.output = vim.list_extend(
            update_info.output,
            res.output.data.stdout,
            res.output.data.stderr
          )
        end

        r:map_ok(merge_output)
        r:map_err(function(err)
          merge_output(err)
          plugin.output = {
            err = vim.list.extend(update_info.err, update_info.output),
            data = {}
          }
        end)
      end

      disp:task_update(plugin_name, 'checking updated commit...')
      r = r:and_then(
        await,
        jobs.run(rev_cmd, { success_test = exit_ok, capture_output = rev_callbacks })
      )
        :map_err(function(_)
          plugin.output = {
            err = vim.list_extend(update_info.err, update_info.revs),
            data = {}
          }
        end)

      if r.ok then
        if update_info.revs[1] ~= update_info.revs[2] then
          local messages_onread = jobs.logging_callback(update_info.err, update_info.messages)
          local messages_callbacks = {
            stdout = messages_onread,
            stderr = messages_onread,
          }

          disp:task_update(plugin_name, 'getting commit messages...')
          r = r:and_then(
            await,
            jobs.run(messages_cmd, { success_test = exit_ok, capture_output = messages_callbacks })
          )

          plugin.output = { err = update_info.err, data = update_info.output }
          if r.ok then
            plugin.messages = update_info.messages
            plugin.revs = update_info.revs
          end
        else
          plugin.revs = update_info.revs
          plugin.messages = update_info.messages
          r = r:and_then(
            await,
            jobs.run(commit_cmd, { capture_output = true })
          )
            :map_ok(function(ok)
              plugin.messages = ok.output.data
            end)
        end
      else
        plugin.output.err = vim.list_extend(plugin.output.err, update_info.messages)
      end

      return { r, update_info }
    end)
  end
end

return git
