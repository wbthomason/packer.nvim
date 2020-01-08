-- Utilities
local nvim = vim.api
local util = require('util')
local display = require('display')
local jobs = require('jobs')

local function echo_special(msg, hl)
  nvim.nvim_command('echohl ' .. hl)
  nvim.nvim_command('echom [plague] ' .. msg)
  nvim.nvim_command('echohl None')
end

local log = {
  info = function(msg) echo_special(msg, 'None') end,
  error = function(msg) echo_special(msg, 'ErrorMsg') end,
  warning = function(msg) echo_special(msg, 'WarningMsg') end,
}

local function ensure_dirs(config)
  if not vim.fn.isdirectory(config.opt_dir) then
    vim.fn.mkdir(config.opt_dir, 'p')
  end

  if not vim.fn.isdirectory(config.start_dir) then
    vim.fn.mkdir(config.start_dir, 'p')
  end
end

-- Config
local plague = {}
local config_defaults = {
  dependencies = true,
  package_root = util.is_windows and '~\\AppData\\Local\\nvim-data\\site\\pack' or '~/.local/share/nvim/site/pack',
  plugin_package = 'plague',
  max_jobs = nil,
  auto_clean = false,
  git_cmd = 'git',
  git_commands = {
    update = '-C %s pull --quiet --ff-only',
    install = 'clone --quiet %s %s --no-single-branch',
    fetch = '-C %s fetch --depth 999999',
    checkout = '-C %s checkout %s --',
    update_branch = '-C %s merge --quiet --ff-only @{u}',
    diff = '-C %s log --color=never --pretty=format:FMT_STRING --no-show-signature HEAD...HEAD@{1}',
    diff_fmt = '%h <<<<%D>>>> %s (%cr)'
  },
  depth = 1,
  display_cmd = '45vsplit'
}

local config = {}
local config_mt = {
  __index = config_defaults
}

setmetatable(config, config_mt)

local plugins = nil

-- Initialize any customizations and the plugin table
plague.begin = function(user_config)
  vim.tbl_extend('force', config, user_config)
  plugins = {}
  config.pack_dir = util.join_paths(config.package_root, config.plugin_package)
  config.opt_dir = util.join_paths(config.pack_dir, 'opt')
  config.start_dir = util.join_paths(config.pack_dir, 'start')
  ensure_dirs(config)
  jobs.set_max_jobs(config.max_jobs)
  display.set_cmd(config.display_cmd)
end

local function ignore_output() end

local function make_git_installer(plugin)
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
        stdout = ignore_output,
        stderr = ignore_output,
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
        stdout = ignore_output,
        stderr = ignore_output,
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
            stdout = ignore_output,
            stderr = ignore_output,
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

local function setup_installer(plugin)
  if vim.fn.isdirectory(plugin.path) then
    plugin.installer = 'local'
    plugin.url = plugin.path
  elseif util.slice(plugin.path, 1, 6) == 'git://' or
    util.slice(plugin.path, 1, 4) == 'http' or
    string.match(plugin.path '@') then
    plugin.url = plugin.path
    make_git_installer(plugin)
  else
    plugin.url = 'https://github.com/' .. plugin.path
    make_git_installer(plugin)
  end
end

-- Add a plugin to the managed set
plague.use = function(plugin)
  local path = plugin[1]
  local name = util.slice(path, string.find(path, '/%S$'))
  if not plugin.installer then
    setup_installer(plugin)
  end

  plugin.path = path
  plugins[name] = plugin
end

local function list_installed_plugins()
  local opt_plugins = vim.fn.globpath(config.opt_dir, '*', true, true)
  local start_plugins = vim.fn.globpath(config.start_dir, '*', true, true)
  return opt_plugins, start_plugins
end

-- Find and remove any plugins not currently configured for use
plague.clean = function(plugin)
  local opt_plugins, start_plugins = list_installed_plugins()
  local function find_unused(plugin_list)
    return util.filter(
      function(plugin_path)
        local plugin_name = vim.fn.fnamemodify(plugin_path, ":t")
        local plugin_type = vim.fn.fnamemodify(plugin_path, ":h:t")
        local plugin_data = plugins[plugin_name]
        return (plugin_data == nil) or (plugin_data.type ~= plugin_type)
      end,
      plugin_list)
  end

  local dirty_plugins = {}
  if plugin then
    table.insert(dirty_plugins, plugin)
  else
    vim.list_extend(dirty_plugins, find_unused(opt_plugins), find_unused(start_plugins))
  end

  if #dirty_plugins > 0 then
    log.info(table.concat(dirty_plugins, ', '))
    if vim.fn.input('Removing the above directories. OK? [y/N]') == 'y' then
      return os.execute('rm -rf ' .. table.concat(dirty_plugins, ' '))
    end
  else
    log.info("Already clean!")
  end
end

local function plugin_missing(plugin_name, start_plugins, opt_plugins)
  local plugin = plugins[plugin_name]
  if plugin.type == 'start' then
    return vim.tbl_contains(start_plugins, util.join_paths(config.start_dir, plugin_name))
  else
    return vim.tbl_contains(opt_plugins, util.join_paths(config.opt_dir, plugin_name))
  end
end

local function args_or_all(...)
  return util.nonempty_or({...}, vim.tbl_keys(plugins))
end

local function install_plugin(plugin, display_win)
  if plugin.installer == 'git' or plugin.installer == 'github' then

    local callbacks = {
      stdout = ignore_output,
      stderr = ignore_output,
      exit = function(_, exit_code)
        display_win:task_done(plugin.name, exit_code)
      end
    }

    local base_dir = config.start_dir
    if plugin.type == 'opt' then
      base_dir = config.opt_dir
    end

    local install_to = util.join_paths(base_dir, plugin.name)
    local install_from = plugin.installer == 'github' and ('https://github.com/' .. plugin.path) or plugin.path
    local install_task = vim.fn.printf(
      '%s %s %s %s',
      config.git_cmd,
      config.git_commands.install,
      install_from,
      install_to)
    display_win:task_start(plugin.name)
    jobs.start { task = install_task, callbacks = callbacks }
  elseif plugin.installer ~= 'local' then
    -- This must be a custom installer, and we don't do anything for local plugins in this stage
    jobs.start { task = plugin.installer.task, callbacks = plugin.installer.callbacks }
  end
end

local function install_helper(missing_plugins)
  local display_win = nil
  if #missing_plugins > 0 then
    log.info('Installing ' .. #missing_plugins .. ' plugins')
    display_win = display.open()
    for _, v in ipairs(missing_plugins) do
      install_plugin(plugins[v], display_win)
    end
  end

  return display_win
end

plague.install = function(...)
  local install_plugins = args_or_all(...)
  local missing_plugins = util.filter(plugin_missing, install_plugins)
  install_helper(missing_plugins)
end

local function update_plugin(plugin, display_win)
  if plugin.installer == 'git' or plugin.installer == 'github' then
    local function ignore_output()
    -- For now, we just ignore stdout and stderr...
    end

    local callbacks = {
      stdout = ignore_output,
      stderr = ignore_output,
      exit = function(_, exit_code)
        display_win:task_done(plugin.name, exit_code)
      end
    }

    local base_dir = config.start_dir
    if plugin.type == 'opt' then
      base_dir = config.opt_dir
    end

    local install_dir = util.join_paths(base_dir, plugin.name)
    local install_task = config.git_cmd .. ' ' .. config.git_commands.update
    display_win:task_start(plugin.name)
    jobs.start { task = install_task, working_dir = install_dir, callbacks = callbacks }
  elseif plugin.installer ~= 'local' then
    -- This must be a custom installer, and we don't do anything for local plugins in this stage
    jobs.start { task = plugin.installer.update_task, callbacks = plugin.installer.update_callbacks }
  end
end

local function update_helper(installed_plugins, display_win)
  if display_win == nil then
    display_win = display.open()
  end

  for _, v in ipairs(installed_plugins) do
    update_plugin(plugins[v], display_win)
  end
end

plague.update = function(...)
  local update_plugins = args_or_all(...)
  local missing_plugins, installed_plugins = util.partition(plugin_missing, update_plugins)
  local display_win = install_helper(missing_plugins)
  update_helper(installed_plugins, display_win)
end

plague.sync = function(...)
  local sync_plugins = args_or_all(...)
  plague.clean()
  return plague.update(unpack(sync_plugins))
end

plague.config = config

return plague
