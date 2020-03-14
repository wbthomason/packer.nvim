local util = require('packer/util')
local log  = require('packer/log')

local vim = vim

local git = {}

local config = {}
git.set_config = function(cmd, subcommands, base_dir, default_pkg)
  config.git = cmd .. ' '
  config.cmds = subcommands
  config.base_dir = base_dir
  config.default_base_dir = util.join_paths(base_dir, default_pkg)
end

local function handle_checkouts(job, job_ctx, plugin, dest)
  job = job * job_ctx:new_job({ task = config.git .. vim.fn.printf(config.cmds.fetch, dest) })

  if plugin.branch then
    job = job *
      job_ctx:new_job({ task = config.git .. vim.fn.printf(config.cmds.update_branch, dest) }) *
      job_ctx:new_job({ task = config.git .. vim.fn.printf(config.cmds.checkout, dest, plugin.branch) })
  end

  if plugin.rev then
    job = job * job_ctx:new_job({ task = config.git .. vim.fn.printf(config.cmds.checkout, dest, plugin.rev) })
  end

  return job
end

git.make_installer = function(plugin)
  local needs_checkout = plugin.rev ~= nil or plugin.branch ~= nil
  local base_dir = nil
  if plugin.package then
    base_dir = util.join_paths(config.base_dir, plugin.package)
  else
    base_dir = config.default_base_dir
  end

  base_dir = util.join_paths(base_dir, plugin.opt and 'opt' or 'start')
  local install_to = util.join_paths(base_dir, plugin.name)
  local install_cmd = config.git .. vim.fn.printf(config.cmds.install, plugin.url, install_to)
  if plugin.branch then
    install_cmd = install_cmd .. ' --branch ' .. plugin.branch
  end

  plugin.installer = function(display_win, job_ctx)
    local plugin_name = util.get_plugin_full_name(plugin)
    local job = job_ctx:new_job({ task = install_cmd })
    if needs_checkout then
      handle_checkouts(job, job_ctx, plugin, install_to)
    end

    job.finally = vim.schedule_wrap(function(success)
      if success then
        log.info('Installing ' .. plugin_name .. ' succeeded!')
        display_win:task_succeeded(plugin_name, 'Installed')
      else
        log.error('Installing ' .. plugin_name .. ' failed!')
        display_win:task_failed(plugin_name, 'Failed to install')
      end
    end)

    return job
  end

  local update_cmd = config.git .. vim.fn.printf(config.cmds.update, install_to)
  -- TODO: The updater should determine if the plugin was actually updated or not and fetch the
  -- relevant commit messages
  -- TODO: Handle status once there's anything meaningful in it
  plugin.updater = function(display_win, job_ctx, status)
    local plugin_name = util.get_plugin_full_name(plugin)
    local job = job_ctx:new_job({ task = update_cmd })
    if needs_checkout then
      handle_checkouts(job, job_ctx, plugin, install_to)
    end

    job.finally = vim.schedule_wrap(function(success)
      if success then
        log.info('Updating ' .. plugin_name .. ' succeeded!')
        display_win:task_succeeded(plugin_name, 'Updated')
      else
        log.error('Updating ' .. plugin_name .. ' failed!')
        display_win:task_failed(plugin_name, 'Failed to update')
      end
    end)

    return job
  end
end

return git
