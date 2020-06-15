-- TODO: Allow separate packages
-- TODO: Fetch/manage LuaRocks dependencies
-- TODO: Allow overriding plugin type detection

local display = require('packer/display')
local git     = require('packer/git')
local jobs    = require('packer/jobs')
local log     = require('packer/log')
local util    = require('packer/util')
local compile = require('packer/compile')
local a       = require('packer/async')
local async   = a.sync
local await   = a.wait

local api = vim.api

local function ensure_dirs(config)
  if vim.fn.isdirectory(config.opt_dir) == 0 then
    vim.fn.mkdir(config.opt_dir, 'p')
  end

  if vim.fn.isdirectory(config.start_dir) == 0 then
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
  git_cmd        = 'git',
  git_commands = {
    update        = '-C %s pull --ff-only',
    install       = 'clone %s %s --no-single-branch',
    fetch         = '-C %s fetch --depth 999999',
    checkout      = '-C %s checkout %s --',
    update_branch = '-C %s merge --ff-only @{u}',
    diff          = "-C %s log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD",
    diff_fmt = '%%h %%s (%%cr)',
    get_rev       = '-C %s rev-parse --short HEAD',
    get_msg       = '-C %s log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1'
  },
  depth       = 1,
  -- This can be a function that returns a window and buffer ID pair
  display_fn  = nil,
  display_cmd = '57vnew [packer]',
  working_sym = '🔄',
  error_sym = '❌',
  done_sym = '✅',
  removed_sym = '⮾',
  header_sym = '━'
}

local config    = {}
local config_mt = {
  __index = config_defaults
}

setmetatable(config, config_mt)

local plugins = nil

-- Initialize any customizations and the plugin table
packer.init = function(user_config)
  user_config = user_config or {}
  config = vim.tbl_extend('force', config, user_config)
  setmetatable(config, config_mt)
  plugins = {}
  config.package_root = vim.fn.fnamemodify(config.package_root, ':p')
  config.package_root = string.sub(config.package_root, 1, string.len(config.package_root) - 1)
  config.pack_dir = util.join_paths(config.package_root, config.plugin_package)
  config.opt_dir = util.join_paths(config.pack_dir, 'opt')
  config.start_dir = util.join_paths(config.pack_dir, 'start')
  ensure_dirs(config)
  git.set_config(config.git_cmd, config.git_commands, config.package_root, config.plugin_package)
  display.set_config(config.working_sym, config.done_sym, config.error_sym, config.removed_sym, config.header_sym)
end

local function setup_local(plugin)
  local from = plugin.path
  local to = util.join_paths((plugin.opt and config.opt_dir or config.start_dir), plugin.name)
  local task
  if vim.fn.executable('ln') then
    task = { 'ln', '-sf', from, to }
  elseif util.is_windows and vim.fn.executable('mklink') then
    task = { 'mklink', from, to }
  else
    log.error('No executable symlink command found!')
    return
  end

  local plugin_name = util.get_plugin_full_name(plugin)
  plugin.installer = function(disp)
    return async(function()
      disp:task_update(plugin_name, 'making symlink...')
      local result = await(jobs.run(task))
      return result.exit_code == 0
    end)
  end

  plugin.updater = function(_) return async(function() return true end) end
end

local function setup_installer(plugin)
  if plugin.installer then
    plugin.installer_type = 'custom'
  elseif vim.fn.isdirectory(plugin.path) ~= 0 then
    plugin.installer_type = 'local'
    plugin.url = plugin.path
    setup_local(plugin)
  elseif util.slice(plugin.path, 1, 6) == 'git://' or
    util.slice(plugin.path, 1, 4) == 'http' or
    string.match(plugin.path, '@') then
    plugin.url = plugin.path
    plugin.installer_type = 'git'
    git.make_installer(plugin)
  else
    plugin.url = 'https://github.com/' .. plugin.path
    plugin.installer_type = 'git'
    git.make_installer(plugin)
  end
end

-- Add a plugin to the managed set
packer.use = function(plugin)
  if type(plugin) == 'string' then
    plugin = { plugin }
  end

  local path = plugin[1]
  local name = string.sub(path, string.find(path, '/%S+$') + 1)
  plugin.short_name = name
  plugin.name = path
  plugin.path = path

  -- Some config keys modify a plugin type
  for _, key in ipairs(compile.opt_keys) do
    if plugin[key] then
      plugin.opt = true
      break
    end
  end

  setup_installer(plugin)
  plugins[name] = plugin

  if plugin.requires and config.dependencies then
    for _, req_path in ipairs(plugin.requires) do
      local req_name = util.slice(req_path, string.find(req_path, '/%S$'))
      if not plugins[req_name] then
        local requirement = { req_path, path = req_path, name = req_name }
        setup_installer(requirement)
        plugins[req_name] = requirement
      end
    end
  end
end

local function list_installed_plugins()
  local opt_plugins   = vim.fn.globpath(config.opt_dir, '*', true, true)
  local start_plugins = vim.fn.globpath(config.start_dir, '*', true, true)
  return opt_plugins, start_plugins
end

-- Find and remove any plugins not currently configured for use
local function clean_plugins(results)
  results = results or {}
  results.removals = results.removals or {}
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

  local dirty_plugins = {}
  vim.list_extend(dirty_plugins, find_unused(opt_plugins))
  vim.list_extend(dirty_plugins, find_unused(start_plugins))

  if #dirty_plugins > 0 then
    local lines = {}
    for _, path in ipairs(dirty_plugins) do
      table.insert(lines, '\t- ' .. path)
    end

    if await(display.ask_user('Removing the following directories. OK? (y/N)', lines)) then
      results.removals = dirty_plugins
      return os.execute('rm -rf ' .. table.concat(dirty_plugins, ' '))
    else
      log.warning('Cleaning cancelled!')
    end
  else
    log.info("Already clean!")
  end
end

packer.clean = clean_plugins

local function plugin_missing(opt_plugins, start_plugins)
  return function(plugin_name)
    local plugin = plugins[plugin_name]
    if not plugin.opt then
      return not vim.tbl_contains(start_plugins, util.join_paths(config.start_dir, plugin.short_name))
    else
      return not vim.tbl_contains(opt_plugins, util.join_paths(config.opt_dir, plugin.short_name))
    end
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

local update_helptags = vim.schedule_wrap(function(plugin_dir)
  local doc_dir = util.join_paths(plugin_dir, 'doc')
  if helptags_stale(doc_dir) then
    api.nvim_command('silent! helptags ' .. vim.fn.fnameescape(doc_dir))
  end
end)

local update_rplugins = vim.schedule_wrap(function()
  api.nvim_command('UpdateRemotePlugins')
end)

local function install_plugin(plugin, display_win, results)
  local plugin_name = util.get_plugin_full_name(plugin)
  -- TODO: This will have to change when multiple packages are added
  local install_path = util.join_paths(config.pack_dir, plugin.opt and 'opt' or 'start', plugin.name)
  return async(function()
    display_win:task_start(plugin_name, 'installing...')
    local r = await(plugin.installer(display_win))
    if r.ok then
      if plugin.run then
        plugin.run(install_path)
      end
      update_helptags(install_path)
      display_win:task_succeeded(plugin_name, 'installed')
    else
      display_win:task_failed(plugin_name, 'failed to install')
    end

    results.installs[plugin_name] = r
    results.plugins[plugin_name] = plugin
  end)
end

local function do_install(missing_plugins, results)
  results = results or {}
  results.installs = results.installs or {}
  results.plugins = results.plugins or {}
  local display_win = nil
  local tasks = {}
  if #missing_plugins > 0 then
    display_win = display.open(config.display_fn or config.display_cmd)
    for _, v in ipairs(missing_plugins) do
      if not plugins[v].disable then
        table.insert(tasks, install_plugin(plugins[v], display_win, results))
      end
    end
  end

  return tasks, display_win
end

packer.install = function(...)
  local install_plugins
  if ... then
    install_plugins = {...}
  else
    local opt_plugins, start_plugins = list_installed_plugins()
    install_plugins = util.filter(plugin_missing(opt_plugins, start_plugins), vim.tbl_keys(plugins))
  end
  async(function()
    if #install_plugins == 0 then
      log.info('All configured plugins are installed')
      return
    end

    local start_time = vim.fn.reltime()
    local results = {}
    local tasks, display_win = do_install(install_plugins, results)
    table.insert(tasks, 1, function() return not display.status.running end)
    table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
    display_win:update_headline_message('installing ' .. #tasks - 2 .. ' / ' .. #tasks - 2 .. ' plugins')
    a.interruptible_wait_pool(unpack(tasks))
    update_rplugins()
    await(a.main)
    local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
    display_win:final_results(results, delta)
  end)()
end

local function get_plugin_status(plugin_name, start_plugins, opt_plugins)
  local status = {}
  local plugin = plugins[plugin_name]
  status.wrong_type = (plugin.opt and vim.tbl_contains(start_plugins, util.join_paths(config.start_dir, plugin_name))) or
    (vim.tbl_contains(opt_plugins, util.join_paths(config.opt_dir, plugin_name)))
  return status
end

local function fix_plugin_type(plugin, results)
  local plugin_name = util.get_plugin_full_name(plugin)
  local from
  local to
  if plugin.opt then
    from = util.join_paths(config.start_dir, plugin.name)
    to   = util.join_paths(config.opt_dir, plugin.name)
  else
    from = util.join_paths(config.opt_dir, plugin.name)
    to   = util.join_paths(config.start_dir, plugin.name)
  end

  -- NOTE: If we stored all plugins somewhere off-package-path and used symlinks to put them in the
  -- right directories, this could be lighter-weight
  local success, msg = os.rename(from, to)
  if not success then
    log.error('Failed to move ' .. from .. ' to ' .. to .. ': ' .. msg)
  end

  results.moves[plugin_name] = { from = from, to = to, result = success }
end

local function fix_plugin_types(plugin_names, results)
  results = results or {}
  results.moves = results.moves or {}
  -- NOTE: This function can only be run on plugins already installed
  for _, v in ipairs(plugin_names) do
    local plugin = plugins[v]
    -- TODO: This will have to change when separate packages are implemented
    local install_dir = util.join_paths(plugin.opt and config.start_dir or config.opt_dir, plugin.name)
    if vim.fn.isdirectory(install_dir) == 1 then
      fix_plugin_type(plugin, results)
    end
  end
end

local function update_plugin(plugin, status, display_win, results)
  local plugin_name = util.get_plugin_full_name(plugin)
  -- TODO: This will have to change when separate packages are implemented
  local install_path = util.join_paths(config.pack_dir, plugin.opt and 'opt' or 'start', plugin.name)
  return async(function()
    display_win:task_start(plugin_name, 'updating...')
    if status.wrong_type then
      fix_plugin_type(plugin)
    end

    local r, info = unpack(await(plugin.updater(display_win)))
    if r.ok then
      local actual_update = info.revs[1] ~= info.revs[2]
      local msg = actual_update
        and ('updated: ' .. info.revs[1] .. '...' .. info.revs[2])
        or 'already up to date'
      if actual_update then
        if plugin.run then
          plugin.run(install_path)
        end

        update_helptags(install_path)
      end

      display_win:task_succeeded(plugin_name, msg)
    else
      display_win:task_failed(plugin_name, 'failed to update')
    end

    results.updates[plugin_name] = { r, plugin }
    results.plugins[plugin_name] = plugin
  end)
end

local function do_update(update_plugins, results)
  results                                  = results or {}
  results.updates                          = results.updates or {}
  results.plugins                          = results.plugins or {}
  local opt_plugins, start_plugins         = list_installed_plugins()
  local missing_plugins, installed_plugins = util.partition(
    plugin_missing(opt_plugins, start_plugins),
    update_plugins
  )

  local tasks, display_win = do_install(missing_plugins, results)
  if display_win == nil then
    display_win = display.open(config.display_fn or config.display_cmd)
  end

  for _, v in ipairs(installed_plugins) do
    local plugin_status = get_plugin_status(v, start_plugins, opt_plugins)
    table.insert(tasks, update_plugin(plugins[v], plugin_status, display_win, results))
  end

  return tasks, display_win
end

packer.update = function(...)
  local update_plugins     = args_or_all(...)
  async(function()
    local start_time         = vim.fn.reltime()
    local results            = {}
    local tasks, display_win = do_update(update_plugins, results)
    table.insert(tasks, 1, function() return not display.status.running end)
    table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
    display_win:update_headline_message('updating ' .. #tasks - 2 .. ' / ' .. #tasks - 2 .. ' plugins')
    a.interruptible_wait_pool(unpack(tasks))
    update_rplugins()
    await(a.main)
    local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
    display_win:final_results(results, delta)
  end)()
end

packer.sync = function(...)
  local sync_plugins = args_or_all(...)
  async(function()
    local start_time                 = vim.fn.reltime()
    local opt_plugins, start_plugins = list_installed_plugins()
    local _, installed_plugins       = util.partition(
      plugin_missing(opt_plugins, start_plugins),
      sync_plugins
    )

    local results = {}

    -- Move any plugins with changed types
    fix_plugin_types(installed_plugins, results)

    -- Remove any unused plugins
    clean_plugins(results)

    -- Finally, update the rest
    local tasks, display_win = do_update(sync_plugins, results)
    table.insert(tasks, 1, function() return not display.status.running end)
    table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
    display_win:update_headline_message('syncing ' .. #tasks - 2 .. ' / ' .. #tasks - 2 .. ' plugins')
    a.interruptible_wait_pool(unpack(tasks))
    update_rplugins()
    await(a.main)
    local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
    display_win:final_results(results, delta)
  end)()
end

packer.compile = function(output_path)
  local compiled_loader = compile.to_lua(plugins)
  vim.fn.mkdir(vim.fn.fnamemodify(output_path, ":h"), 'p')
  local output_file = io.open(output_path, 'w')
  output_file:write(compiled_loader)
  output_file:close()
end

packer.config = config

return packer
