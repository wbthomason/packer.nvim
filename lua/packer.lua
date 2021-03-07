-- TODO: Performance analysis/tuning
-- TODO: Merge start plugins?
local a = require('packer.async')
local clean = require('packer.clean')
local compile = require('packer.compile')
local display = require('packer.display')
local handlers = require('packer.handlers')
local install = require('packer.install')
local log = require('packer.log')
local luarocks = require('packer.luarocks')
local plugin_types = require('packer.plugin_types')
local plugin_utils = require('packer.plugin_utils')
local update = require('packer.update')
local util = require('packer.util')

local async = a.sync
local await = a.wait

-- Config
local packer = {}
local config_defaults = {
  ensure_dependencies = true,
  package_root = util.join_paths(vim.fn.stdpath('data'), 'site', 'pack'),
  compile_path = util.join_paths(vim.fn.stdpath('config'), 'plugin', 'packer_compiled.vim'),
  plugin_package = 'packer',
  max_jobs = nil,
  auto_clean = true,
  compile_on_sync = true,
  disable_commands = false,
  opt_default = false,
  transitive_opt = true,
  transitive_disable = true,
  auto_reload_compiled = true,
  git = {
    cmd = 'git',
    subcommands = {
      update = '-C %s pull --ff-only --progress --rebase=false',
      install = 'clone %s %s --depth %i --no-single-branch --progress',
      fetch = '-C %s fetch --depth 999999 --progress',
      checkout = '-C %s checkout %s --',
      update_branch = '-C %s merge --ff-only @{u}',
      current_branch = '-C %s rev-parse --abbrev-ref HEAD',
      diff = '-C %s log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD',
      diff_fmt = '%%h %%s (%%cr)',
      git_diff_fmt = "-C %s show --no-color --pretty=medium %s",
      get_rev = '-C %s rev-parse --short HEAD',
      get_msg = '-C %s log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1',
      submodules = '-C %s submodule update --init --recursive --progress',
      revert = '-C %s reset --hard HEAD@{1}'
    },
    depth = 1,
    clone_timeout = 60
  },
  display = {
    non_interactive = false,
    open_fn = nil,
    open_cmd = '65vnew [packer]',
    working_sym = '⟳',
    error_sym = '✗',
    done_sym = '✓',
    removed_sym = '-',
    moved_sym = '→',
    header_sym = '━',
    header_lines = 2,
    title = 'packer.nvim',
    show_all_info = true,
    keybindings = {quit = 'q', toggle_info = '<CR>', diff = 'd', prompt_revert = 'r'}
  },
  luarocks = {python_cmd = 'python'},
  log = {level = 'warn'}
}

local config = vim.tbl_extend('force', {}, config_defaults)
local plugins = nil
local rocks = nil

--- Initialize packer
-- Forwards user configuration to sub-modules, resets the set of managed plugins, and ensures that
-- the necessary package directories exist
packer.init = function(user_config)
  user_config = user_config or {}
  config = util.deep_extend('force', config, user_config)
  packer.reset()
  config.package_root = vim.fn.fnamemodify(config.package_root, ':p')
  local _
  config.package_root, _ = string.gsub(config.package_root, util.get_separator() .. '$', '', 1)
  config.pack_dir = util.join_paths(config.package_root, config.plugin_package)
  config.opt_dir = util.join_paths(config.pack_dir, 'opt')
  config.start_dir = util.join_paths(config.pack_dir, 'start')

  for _, mod in ipairs({
    clean, compile, display, handlers, install, plugin_types, plugin_utils, update, luarocks, log
  }) do mod.cfg(config) end

  plugin_utils.ensure_dirs()

  if not config.disable_commands then
    vim.cmd [[command! PackerInstall  lua require('packer').install()]]
    vim.cmd [[command! PackerUpdate   lua require('packer').update()]]
    vim.cmd [[command! PackerSync     lua require('packer').sync()]]
    vim.cmd [[command! PackerClean    lua require('packer').clean()]]
    vim.cmd [[command! PackerCompile  lua require('packer').compile()]]
  end
end

packer.reset = function()
  plugins = {}
  rocks = {}
end

--- Add a Luarocks package to be managed
local function use_rocks(rock)
  if type(rock) == 'string' then rock = {rock} end
  if not vim.tbl_islist(rock) and type(rock[1]) == "string" then
    rocks[rock[1]] = rock
  else
    for _, r in ipairs(rock) do
      local rock_name = (type(r) == 'table') and r[1] or r
      rocks[rock_name] = r
    end
  end
end

packer.use_rocks = use_rocks

--- The main logic for adding a plugin (and any dependencies) to the managed set
-- Can be invoked with (1) a single plugin spec as a string, (2) a single plugin spec table, or (3)
-- a list of plugin specs
local manage = nil
manage = function(plugin)
  if type(plugin) == 'string' then
    plugin = {plugin}
  elseif type(plugin) == 'table' and #plugin > 1 then
    for _, spec in ipairs(plugin) do manage(spec) end
    return
  end

  if plugin[1] == vim.NIL or plugin[1] == nil then
    log.warn('Nil plugin name provided!')
    return
  end

  local path = vim.fn.expand(plugin[1])
  local name_segments = vim.split(path, util.get_separator())

  local segment_idx = #name_segments
  local name = plugin.as or name_segments[segment_idx]
  while name == '' and segment_idx > 0 do
    name = name_segments[segment_idx]
    segment_idx = segment_idx - 1
  end

  if name == '' then
    log.warn('"' .. plugin[1] .. '" is an invalid plugin name!')
    return
  end

  if plugins[name] then
    log.warn('Plugin "' .. name .. '" is used twice!')
    return
  end

  if plugin.as and plugins[plugin.as] then
    log.error('The alias ' .. plugin.as .. ', specified for ' .. path
                .. ', is already used as another plugin name!')
    return
  end

  -- Handle aliases
  plugin.short_name = name
  plugin.name = path
  plugin.path = path

  -- Some config keys modify a plugin type
  if plugin.opt then
    plugin.manual_opt = true
  elseif plugin.opt == nil and config.opt_default then
    plugin.manual_opt = true
    plugin.opt = true
  end

  for _, key in ipairs(compile.opt_keys) do
    if plugin[key] then
      plugin.opt = true
      break
    end
  end

  plugin.install_path = util.join_paths(plugin.opt and config.opt_dir or config.start_dir,
                                        plugin.short_name)

  if not plugin.type then plugin_utils.guess_type(plugin) end
  if plugin.type ~= plugin_utils.custom_plugin_type then plugin_types[plugin.type].setup(plugin) end
  for k, v in pairs(plugin) do if handlers[k] then handlers[k](plugins, plugin, v) end end
  plugins[plugin.short_name] = plugin
  if plugin.rocks then use_rocks(plugin.rocks) end

  if plugin.requires and config.ensure_dependencies then
    if type(plugin.requires) == 'string' then plugin.requires = {plugin.requires} end
    for _, req in ipairs(plugin.requires) do
      if type(req) == 'string' then req = {req} end
      local req_name_segments = vim.split(req[1], '/')
      local req_name = req_name_segments[#req_name_segments]
      if not plugins[req_name] then
        if config.transitive_opt and plugin.manual_opt then
          req.opt = true
          if type(req.after) == 'string' then
            req.after = {req.after, plugin.short_name}
          elseif type(req.after) == 'table' then
            local already_after = false
            for _, name in ipairs(req.after) do
              already_after = already_after or (name == plugin.short_name)
            end
            if not already_after then table.insert(req.after, plugin.short_name) end
          elseif req.after == nil then
            req.after = plugin.short_name
          end
        end

        if config.transitive_disable and plugin.disable then req.disable = true end

        manage(req)
      end
    end
  end
end

--- Add a new keyword handler
packer.set_handler = function(name, func) handlers[name] = func end

--- Add a plugin to the managed set
packer.use = manage

--- Clean operation:
-- Finds plugins present in the `packer` package but not in the managed set
packer.clean = function(results)
  async(function()
    await(luarocks.clean(rocks, results, nil))
    await(clean(plugins, results))
  end)()
end

local function args_or_all(...) return util.nonempty_or({...}, vim.tbl_keys(plugins)) end

--- Install operation:
-- Takes an optional list of plugin names as an argument. If no list is given, operates on all
-- managed plugins.
-- Installs missing plugins, then updates helptags and rplugins
packer.install = function(...)
  local install_plugins
  if ... then
    install_plugins = {...}
  else
    install_plugins = plugin_utils.find_missing_plugins(plugins)
  end

  if #install_plugins == 0 then
    log.info('All configured plugins are installed')
    return
  end

  async(function()
    local start_time = vim.fn.reltime()
    local results = {}
    await(clean(plugins, results))
    local tasks, display_win = install(plugins, install_plugins, results)
    if next(tasks) then
      table.insert(tasks, luarocks.ensure(rocks, results, display_win))
      table.insert(tasks, 1, function() return not display.status.running end)
      table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
      display_win:update_headline_message('installing ' .. #tasks - 2 .. ' / ' .. #tasks - 2
                                            .. ' plugins')
      a.interruptible_wait_pool(unpack(tasks))
      local install_paths = {}
      for plugin_name, r in pairs(results.installs) do
        if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
      end

      await(a.main)
      plugin_utils.update_helptags(install_paths)
      plugin_utils.update_rplugins()
      local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
      display_win:final_results(results, delta)
    else
      log.info('Nothing to install!')
    end
  end)()
end

--- Update operation:
-- Takes an optional list of plugin names as an argument. If no list is given, operates on all
-- managed plugins.
-- Fixes plugin types, installs missing plugins, then updates installed plugins and updates helptags
-- and rplugins
packer.update = function(...)
  local update_plugins = args_or_all(...)
  async(function()
    local start_time = vim.fn.reltime()
    local results = {}
    await(clean(plugins, results))
    local missing_plugins, installed_plugins = util.partition(
                                                 plugin_utils.find_missing_plugins(plugins),
                                                 update_plugins)

    update.fix_plugin_types(plugins, missing_plugins, results)
    local _
    _, missing_plugins = util.partition(vim.tbl_keys(results.moves), missing_plugins)
    local tasks, display_win = install(plugins, missing_plugins, results)
    local update_tasks
    update_tasks, display_win = update(plugins, installed_plugins, display_win, results)
    vim.list_extend(tasks, update_tasks)
    table.insert(tasks, luarocks.ensure(rocks, results, display_win))
    table.insert(tasks, 1, function() return not display.status.running end)
    table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
    display_win:update_headline_message('updating ' .. #tasks - 2 .. ' / ' .. #tasks - 2
                                          .. ' plugins')
    a.interruptible_wait_pool(unpack(tasks))
    local install_paths = {}
    for plugin_name, r in pairs(results.installs) do
      if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
    end

    for plugin_name, r in pairs(results.updates) do
      if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
    end

    await(a.main)
    plugin_utils.update_helptags(install_paths)
    plugin_utils.update_rplugins()
    local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
    display_win:final_results(results, delta)
  end)()
end

--- Sync operation:
-- Takes an optional list of plugin names as an argument. If no list is given, operates on all
-- managed plugins.
-- Runs (in sequence):
--  - Update plugin types
--  - Clean stale plugins
--  - Install missing plugins and update installed plugins
--  - Update helptags and rplugins
packer.sync = function(...)
  local sync_plugins = args_or_all(...)
  async(function()
    local start_time = vim.fn.reltime()
    local results = {}
    local missing_plugins, installed_plugins = util.partition(
                                                 plugin_utils.find_missing_plugins(plugins),
                                                 sync_plugins)

    update.fix_plugin_types(plugins, missing_plugins, results)
    local _
    _, missing_plugins = util.partition(vim.tbl_keys(results.moves), missing_plugins)
    if config.auto_clean then
      await(clean(plugins, results))
      _, installed_plugins = util.partition(vim.tbl_keys(results.removals), installed_plugins)
    end

    local tasks, display_win = install(plugins, missing_plugins, results)
    local update_tasks
    update_tasks, display_win = update(plugins, installed_plugins, display_win, results)
    vim.list_extend(tasks, update_tasks)
    table.insert(tasks, luarocks.clean(rocks, results, display_win))
    table.insert(tasks, luarocks.ensure(rocks, results, display_win))
    table.insert(tasks, 1, function() return not display.status.running end)
    table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
    display_win:update_headline_message(
      'syncing ' .. #tasks - 2 .. ' / ' .. #tasks - 2 .. ' plugins')
    a.interruptible_wait_pool(unpack(tasks))
    local install_paths = {}
    for plugin_name, r in pairs(results.installs) do
      if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
    end

    for plugin_name, r in pairs(results.updates) do
      if r.ok then table.insert(install_paths, results.plugins[plugin_name].install_path) end
    end

    await(a.main)

    if config.compile_on_sync then packer.compile() end
    plugin_utils.update_helptags(install_paths)
    plugin_utils.update_rplugins()
    local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
    display_win:final_results(results, delta)
  end)()
end

local function reload_module(name)
  if name then
    package.loaded[name] = nil
    return require(name)
  end
end

--- Search through all the loaded packages for those that
--- return a function, then cross reference them with all
--- the plugin configs and setups and if there are any matches
--- reload the user module.
local function refresh_configs(plugs)
  local reverse_index = {}
  for k, v in pairs(package.loaded) do if type(v) == "function" then reverse_index[v] = k end end
  for _, plugin in pairs(plugs) do
    local cfg = reload_module(reverse_index[plugin.config])
    local setup = reload_module(reverse_index[plugin.setup])
    if cfg then plugin.config = cfg end
    if setup then plugin.setup = setup end
  end
end

--- Update the compiled lazy-loader code
-- Takes an optional argument of a path to which to output the resulting compiled code
packer.compile = function(output_path)
  output_path = output_path or config.compile_path
  refresh_configs(plugins)
  -- NOTE: we copy the plugins table so the in memory value is not mutated during compilation
  local compiled_loader = compile(vim.deepcopy(plugins))
  output_path = vim.fn.expand(output_path)
  vim.fn.mkdir(vim.fn.fnamemodify(output_path, ":h"), 'p')
  local output_file = io.open(output_path, 'w')
  output_file:write(compiled_loader)
  output_file:close()
  if config.auto_reload_compiled then vim.cmd("source " .. output_path) end
  log.info('Finished compiling lazy-loaders!')
end

packer.config = config

--- Convenience function for simple setup
-- Can be invoked as follows:
--  spec can be a function:
--  packer.startup(function() use 'tjdevries/colorbuddy.vim' end)
--
--  spec can be a table with a function as its first element and config overrides as another
--  element:
--  packer.startup({function() use 'tjdevries/colorbuddy.vim' end, config = { ... }})
--
--  spec can be a table with a table of plugin specifications as its first element and config
--  overrides as another element:
--  packer.startup({{'tjdevries/colorbuddy.vim'}, config = { ... }})
packer.startup = function(spec)
  local user_func = nil
  local user_config = nil
  local user_plugins = nil
  if type(spec) == 'function' then
    user_func = spec
  elseif type(spec) == 'table' then
    if type(spec[1]) == 'function' then
      user_func = spec[1]
    elseif type(spec[1]) == 'table' then
      user_plugins = spec[1]
    else
      log.error(
        'You must provide a function or table of specifications as the first element of the argument to startup!')
      return
    end

    -- NOTE: It might be more convenient for users to allow arbitrary config keys to be specified
    -- and to merge them, but I feel that only avoids a single layer of nesting and adds more
    -- complication here, so I'm not sure if the benefit justifies the cost
    user_config = spec.config
  end

  packer.init(user_config)
  packer.reset()

  if user_func then
    setfenv(user_func,
            vim.tbl_extend('force', getfenv(), {use = packer.use, use_rocks = packer.use_rocks}))
    local status, err = pcall(user_func, packer.use, packer.use_rocks)
    if not status then
      log.error('Failure running setup function: ' .. vim.inspect(err))
      error(err)
    end
  else
    packer.use(user_plugins)
  end

  return packer
end

return packer
