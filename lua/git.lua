local util = require('util')
local log  = require('log')

local git = {}

local config = {}
git.set_config = function(cmd, subcommands, start_dir, opt_dir)
  config.git = cmd
  config.cmds = subcommands
  config.start_dir = start_dir
  config.opt_dir = opt_dir
end

git.make_installer = function(plugin)
  local needs_checkout = plugin.rev ~= nil or plugin.branch ~= nil
  local base_dir = config.start_dir
  if plugin.type == 'opt' then
    base_dir = config.opt_dir
  end

  local install_to = util.join_paths(base_dir, plugin.name)
  local install_cmd = config.git_cmd .. ' ' .. vim.fn.printf(config.git_commands.install, plugin.url, install_to)
  if plugin.branch then
    install_cmd = install_cmd .. ' --branch ' .. plugin.branch
  end

  plugin.installer = function(display_win, job_ctx)
    local job = job_ctx:new_job({
      task = install_cmd,
      callbacks = {
        exit = function(_, exit_code)
          if needs_checkout then
            return exit_code == 0
          end

          if exit_code ~= 0 then
            log.error('Installing ' .. plugin.name .. ' failed!')
            display_win:task_failed(plugin.name, 'Installing')
            return false
          end

          display_win:task_succeeded(plugin.name, 'Installing')

          return true
        end
      }})

    if needs_checkout then
      local callbacks = {
        exit = function(_, exit_code) return exit_code == 0 end
      }

      job = job * job_ctx:new_job({
        task = config.git_cmd .. ' ' .. vim.fn.printf(config.git_commands.fetch, install_to),
        callbacks = callbacks
      })

      if plugin.branch then
        job = job *
          job_ctx:new_job({
            task = config.git_cmd .. ' ' .. vim.fn.printf(config.git_commands.update_branch, install_to),
            callbacks = callbacks
          }) *
          job_ctx:new_job({
            task = config.git_cmd .. ' ' .. vim.fn.printf(config.git_commands.checkout, install_to, plugin.branch),
            callbacks = callbacks
          })
      end

      if plugin.rev then
        job = job * job_ctx:new_job({
          task = config.git_cmd .. ' ' .. vim.fn.printf(config.git_commands.checkout, install_to, plugin.rev),
          callbacks = {
            exit = function(_, exit_code)
              local branch_rev = ''
              if plugin.branch then
                branch_rev = ':' .. plugin.branch
              end

              if plugin.rev then
                branch_rev = branch_rev .. '@' .. plugin.rev
              end

              if exit_code ~= 0 then
                log.error(vim.fn.printf('Installing %s%s failed!', plugin.name, branch_rev))
                display_win:task_failed(plugin.name, 'Installing')
                return false
              end

              display_win:task_succeeded(plugin.name .. branch_rev, 'Installing')
              return true
            end
          }
        })
      end
    end

    return job
  end

  plugin.updater = function(display_win, job_ctx)
  end
end

git.get_branch = function(plugin, type)
end

return git
