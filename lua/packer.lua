local display = require('display')
local git     = require('git')
local jobs    = require('jobs')
local log     = require('log')
local util    = require('util')
local compile = require('compile')

local api     = vim.api

local function ensure_dirs(config)
  if not vim.fn.isdirectory(config.opt_dir) then
    vim.fn.mkdir(config.opt_dir, 'p')
  end

  if not vim.fn.isdirectory(config.start_dir) then
    vim.fn.mkdir(config.start_dir, 'p')
  end
end

-- Config
local packer = {}
local config_defaults = {
  dependencies   = true,
  package_root   = util.is_windows and '~\\AppData\\Local\\nvim-data\\site\\pack' or '~/.local/share/nvim/site/pack',
  plugin_package = 'packer',
  max_jobs       = nil,
  auto_clean     = false,
  compile_vim    = true,
  git_cmd        = 'git',
  git_commands = {
    update        = '-C %s pull --quiet --ff-only',
    install       = 'clone --quiet %s %s --no-single-branch',
    fetch         = '-C %s fetch --depth 999999',
    checkout      = '-C %s checkout %s --',
    update_branch = '-C %s merge --quiet --ff-only @{u}',
    diff          = '-C %s log --color=never --pretty=format:FMT_STRING --no-show-signature HEAD...HEAD@{1}',
    diff_fmt      = '%h <<<<%D>>>> %s (%cr)'
  },
  depth       = 1,
  display_cmd = '45vsplit'
}

local config    = {}
local config_mt = {
  __index = config_defaults
}

setmetatable(config, config_mt)

local plugins = nil

-- Initialize any customizations and the plugin table
packer.init = function(user_config)
  vim.tbl_extend('force', config, user_config)
  plugins = {}
  config.pack_dir = util.join_paths(config.package_root, config.plugin_package)
  config.opt_dir = util.join_paths(config.pack_dir, 'opt')
  config.start_dir = util.join_paths(config.pack_dir, 'start')
  ensure_dirs(config)
  git.set_config(config.git_cmd, config.git_commands, config.package_root, config.plugin_package)
end

local function setup_installer(plugin)
  if plugin.installer then
    plugin.installer_type = 'custom'
  elseif vim.fn.isdirectory(plugin.path) then
    plugin.installer_type = 'local'
    plugin.url = plugin.path
  elseif util.slice(plugin.path, 1, 6) == 'git://' or
    util.slice(plugin.path, 1, 4) == 'http' or
    string.match(plugin.path '@') then
    plugin.url = plugin.path
    plugin.installer_type = 'git'
    git.make_git_installer(plugin)
  else
    plugin.url = 'https://github.com/' .. plugin.path
    plugin.installer_type = 'git'
    git.make_git_installer(plugin)
  end
end

-- Add a plugin to the managed set
packer.use = function(plugin)
  local path = plugin[1]
  local name = util.slice(path, string.find(path, '/%S$'))
  setup_installer(plugin)
  plugin.path = path
  plugins[name] = plugin
  -- TODO: Process keys that may change plugin type or add other plugins
end

local function list_installed_plugins()
  local opt_plugins   = vim.fn.globpath(config.opt_dir, '*', true, true)
  local start_plugins = vim.fn.globpath(config.start_dir, '*', true, true)
  return opt_plugins, start_plugins
end

-- Find and remove any plugins not currently configured for use
packer.clean = function(...)
  local dirty_plugins = {}
  if ... then
    dirty_plugins = {...}
  else
    local opt_plugins, start_plugins = list_installed_plugins()
    local function find_unused(plugin_list)
      return util.filter(
        function(plugin_path)
          local plugin_name = vim.fn.fnamemodify(plugin_path, ":t")
          local plugin_data = plugins[plugin_name]
          return (plugin_data == nil) or (plugin_data.disable)
        end,
        plugin_list)
    end

    vim.list_extend(dirty_plugins, find_unused(opt_plugins))
    vim.list_extend(dirty_plugins, find_unused(start_plugins))
  end

  if #dirty_plugins > 0 then
    -- TODO: Use a prettier display, like vim-packager, for this
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

local function helptags_stale(dir)
  -- Adapted directly from minpac.vim
  local txts = vim.fn.glob(util.join_paths(dir, '*.txt'), true, true)
  txts = vim.list_extend(txts, vim.fn.glob(util.join_paths(dir, '*.[a-z][a-z]x'), true, true))
  local tags = vim.fn.glob(util.join_paths(dir, 'tags'), true, true)
  tags = vim.list_extend(tags, vim.fn.glob(util.join_paths(dir, 'tags-[a-z][a-z]'), true, true))
  local txt_newest = math.max(unpack(util.map(vim.fn.getftime, txts)))
  local tag_oldest = math.min(unpack(util.map(vim.fn.getftime, tags)))
  return txt_newest > tag_oldest
end

local function update_helptags(plugin_dir)
  local doc_dir = util.join_paths(plugin_dir, 'doc')
  if helptags_stale(doc_dir) then
    api.nvim_command('silent! helptags ' .. vim.fn.fnameescape(doc_dir))
  end
end

local function install_plugin(plugin, display_win, job_ctx)
  if plugin.installer == 'local' then
    -- TODO: Should local plugins be symlinked or copied or something?
    update_helptags(plugin.path)
  else
    local plugin_name = util.get_plugin_full_name(plugin)
    display_win:task_start(plugin_name, 'Installing')
    local installer_job = plugin.installer(display_win, job_ctx)
    -- TODO: This will have to change when multiple packages are added
    local install_path = util.join_paths(config.pack_dir, plugin.type, plugin.name)
    installer_job.after = function(result) if result then update_helptags(install_path) end end
    job_ctx:start(installer_job)
  end
end

local function install_helper(missing_plugins)
  local display_win = nil
  local job_ctx = nil
  if #missing_plugins > 0 then
    log.info('Installing ' .. #missing_plugins .. ' plugins')
    display_win = display.open(config.display_fn or config.display_cmd)
    job_ctx = jobs.new(config.max_jobs)
    for _, v in ipairs(missing_plugins) do
      install_plugin(plugins[v], display_win, job_ctx)
    end
  end

  return display_win, job_ctx
end

packer.install = function(...)
  local install_plugins = args_or_all(...)
  local missing_plugins = util.filter(plugin_missing, install_plugins)
  install_helper(missing_plugins)
end

local function get_plugin_status(plugin_name, start_plugins, opt_plugins)
  local status = {}
  local plugin = plugins[plugin_name]
  status.wrong_type = (plugin.type == 'start' and vim.tbl_contains(opt_plugins, util.join_paths(config.opt_dir, plugin_name))) or
    (plugin.type == 'opt' and vim.tbl_contains(start_plugins, util.join_paths(config.start_dir, plugin_name)))
  return status
end

local function fix_plugin_type(plugin)
  local from = nil
  local to = nil
  if plugin.type == 'start' then
    from = util.join_paths(config.opt_dir, plugin.name)
    to   = util.join_paths(config.start_dir, plugin.name)
  else
    from = util.join_paths(config.start_dir, plugin.name)
    to   = util.join_paths(config.opt_dir, plugin.name)
  end

  -- NOTE: If we stored all plugins somewhere off-package-path and used symlinks to put them in the
  -- right directories, this could be lighter-weight
  local success, msg = os.rename(from, to)
  if not success then
    log.error('Failed to move ' .. from .. ' to ' .. to .. ': ' .. msg)
  end
end

local function fix_plugin_types(plugin_names)
  -- NOTE: This function can only be run on plugins already installed
  for _, v in ipairs(plugin_names) do
    local plugin = plugins[v]
    -- TODO: This will have to change when separate packages are implemented
    local install_dir = util.join_paths((plugin.type == 'start') and config.start_dir or config.opt_dir, plugin.name)
    if not vim.fn.isdirectory(install_dir) then
      fix_plugin_type(plugin)
    end
  end
end

local function update_plugin(plugin, status, display_win, job_ctx)
  if plugin.installer_type == 'local' then
    update_helptags(plugin.path)
  else
    local plugin_name = util.get_plugin_full_name(plugin)
    display_win:task_start(plugin_name, 'Updating')
    local updater_job = plugin.updater(status, display_win, job_ctx)
    if status.wrong_type then
      updater_job.before = fix_plugin_type(plugin)
    end
    local install_path = util.join_paths(config.pack_dir, plugin.type, plugin.name)
    updater_job.after = function(result) if result then update_helptags(install_path) end end
    job_ctx:start(updater_job)
  end
end

packer.update = function(...)
  local update_plugins = args_or_all(...)
  local missing_plugins, installed_plugins = util.partition(plugin_missing, update_plugins)
  local opt_plugins, start_plugins = list_installed_plugins()
  local display_win, job_ctx = install_helper(missing_plugins)
  if display_win == nil then
    display_win = display.open(config.display_fn or config.display_cmd)
  end

  if job_ctx == nil then
    job_ctx = jobs.new(config.max_jobs)
  end

  for _, v in ipairs(installed_plugins) do
    local plugin_status = get_plugin_status(v, start_plugins, opt_plugins)
    update_plugin(plugins[v], plugin_status, display_win, job_ctx)
  end
end

packer.sync = function(...)
  local sync_plugins         = args_or_all(...)
  local _, installed_plugins = util.partition(plugin_missing, sync_plugins)

  -- Move any plugins with changed types
  fix_plugin_types(installed_plugins)

  -- Remove any unused plugins
  packer.clean(unpack(sync_plugins))

  -- Finally, update the rest
  return packer.update(unpack(sync_plugins))
end

packer.save = function(output_path)
  local compiled_loader = config.compile_vim and compile.to_vim(plugins) or compile.to_lua(plugins)
  vim.fn.mkdir(vim.fn.fnamemodify(output_path, ":h"), 'p')
  local output_file = io.open(output_path, 'w')
  output_file:write(compiled_loader)
  output_file:close()
end

packer.config = config

return packer
