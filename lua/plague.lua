-- Utilities
local nvim = vim.api
local util = require('util')
local display = require('display')

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
    update = 'pull',
    install = 'clone'
  }
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
end

-- Add a plugin to the managed set
plague.use = function(plugin)
  local path = plugin[1]
  local name = util.slice(path, string.find(path, '/%S$'))
  if not plugin.installer then
    if vim.fn.isdirectory(path) then
      plugin.installer = 'local'
    elseif util.slice(path, 1, 6) == 'git://' or util.slice(path, 1, 4) == 'http' then
      plugin.installer = 'git'
    else
      plugin.installer = 'github'
    end
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
    
  local base_dir = config.start_dir
  if plugin.type == 'opt' then
    base_dir = config.opt_dir
  end

  local install_to = util.join_paths(base_dir, plugin.name)
  local install_from =
    jobs.start
  elseif plugin.installer ~= 'local' then
    -- This must be a custom installer
    jobs.start { task = plugin.installer, callbacks = { event = install_event, exit = install_exit } }
  end
end

plague.install = function(...)
  local install_plugins = args_or_all(...)
  local opt_plugins, start_plugins = list_installed_plugins()
  local missing_plugins = util.filter(plugin_missing, install_plugins)
  if #missing_plugins > 0 then
    local display_win = display.open()
    for _, v in ipairs(missing_plugins) do
      install_plugin(plugins[v], display_win)
    end
    return nil
  end
end

local function update(...)
  local update_plugins = args_or_all(...)
  local missing_plugins, installed_plugins = util.partition(plugin_missing_3f, update_plugins)
  return print("WIP")
end

local function sync(...)
  local sync_plugins = args_or_all(...)
  clean()
  return update(unpack(sync_plugins))
end

plague.config = config

return plague
