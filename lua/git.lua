local util = require('util')
local log  = require('log')

local git = {}

local config = {}
git.set_config = function(cmd, subcommands, base_dir, default_pkg)
  config.git = cmd .. ' '
  config.cmds = subcommands
  config.base_dir = base_dir
  config.default_base_dir = util.join_paths(base_dir, default_pkg)
end

local function branch_aware_install(plugin, cmd, dest, needs_checkout)
  return function(display_win, job_ctx)
    local plugin_name = util.get_plugin_full_name(plugin)
    local job = job_ctx:new_job({ task = cmd })
    if needs_checkout then
      job = job * job_ctx:new_job({ task = config.git .. vim.fn.printf(config.cmds.fetch, dest) })

      if plugin.branch then
        job = job *
          job_ctx:new_job({ task = config.git .. vim.fn.printf(config.cmds.update_branch, dest) }) *
          job_ctx:new_job({ task = config.git .. vim.fn.printf(config.cmds.checkout, dest, plugin.branch) })
      end

      if plugin.rev then
        job = job * job_ctx:new_job({ task = config.git .. vim.fn.printf(config.cmds.checkout, dest, plugin.rev) })
      end
    end

    job.finally = function(success)
      if success then
        log.info('Installing ' .. plugin_name .. ' succeeded!')
        display_win:task_succeeded(plugin_name, 'Installing')
      else
        log.error('Installing ' .. plugin_name .. ' failed!')
        display_win:task_failed(plugin_name, 'Installing')
      end
    end

    return job
  end
end

git.make_installer = function(plugin)
  local needs_checkout = plugin.rev ~= nil or plugin.branch ~= nil
  local base_dir = nil
  if plugin.package then
    base_dir = util.join_paths(config.base_dir, plugin.package)
  else
    base_dir = config.default_base_dir
  end

  base_dir = util.join_paths(base_dir, plugin.type)
  local install_to = util.join_paths(base_dir, plugin.name)
  local git_prefix = config.git .. ' '
  local install_cmd = git_prefix .. vim.fn.printf(config.cmds.install, plugin.url, install_to)
  if plugin.branch then
    install_cmd = install_cmd .. ' --branch ' .. plugin.branch
  end

  plugin.installer = branch_aware_install(plugin, install_cmd, install_to, needs_checkout)
  local update_cmd = git_prefix .. vim.fn.printf(config.cmds.update, install_to)
  plugin.updater = branch_aware_install(plugin, update_cmd, install_to, needs_checkout)
end

return git
