-- TODO: Performance analysis/tuning
-- TODO: Merge start plugins?
local util = require 'packer.util'

local join_paths = util.join_paths
local stdpath = vim.fn.stdpath

-- Config
local packer = {}
local config_defaults = {
  ensure_dependencies = true,
  package_root = join_paths(stdpath 'data', 'site', 'pack'),
  compile_path = join_paths(stdpath 'config', 'plugin', 'packer_compiled.lua'),
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
      update = 'pull --ff-only --progress --rebase=false',
      install = 'clone --depth %i --no-single-branch --progress',
      fetch = 'fetch --depth 999999 --progress',
      checkout = 'checkout %s --',
      update_branch = 'merge --ff-only @{u}',
      current_branch = 'rev-parse --abbrev-ref HEAD',
      diff = 'log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD',
      diff_fmt = '%%h %%s (%%cr)',
      git_diff_fmt = 'show --no-color --pretty=medium %s',
      get_rev = 'rev-parse --short HEAD',
      get_msg = 'log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1',
      submodules = 'submodule update --init --recursive --progress',
      revert = 'reset --hard HEAD@{1}',
    },
    depth = 1,
    clone_timeout = 60,
    default_url_format = 'https://github.com/%s.git',
  },
  display = {
    non_interactive = false,
    open_fn = nil,
    open_cmd = '65vnew',
    working_sym = '⟳',
    error_sym = '✗',
    done_sym = '✓',
    removed_sym = '-',
    moved_sym = '→',
    header_sym = '━',
    header_lines = 2,
    title = 'packer.nvim',
    show_all_info = true,
    prompt_border = 'double',
    keybindings = { quit = 'q', toggle_info = '<CR>', diff = 'd', prompt_revert = 'r' },
  },
  luarocks = { python_cmd = 'python' },
  log = { level = 'warn' },
  profile = { enable = false },
}

--- Initialize global namespace for use for callbacks and other data generated whilst packer is
--- running
_G._packer = _G._packer or {}

local config = vim.tbl_extend('force', {}, config_defaults)
local plugins = nil
local plugin_specifications = nil
local rocks = nil

local configurable_modules = {
  clean = false,
  compile = false,
  display = false,
  handlers = false,
  install = false,
  plugin_types = false,
  plugin_utils = false,
  update = false,
  luarocks = false,
  log = false,
}

local function require_and_configure(module_name)
  local fully_qualified_name = 'packer.' .. module_name
  local module = require(fully_qualified_name)
  if not configurable_modules[module_name] and module.cfg then
    configurable_modules[module_name] = true
    module.cfg(config)
    return module
  end

  return module
end

--- Initialize packer
-- Forwards user configuration to sub-modules, resets the set of managed plugins, and ensures that
-- the necessary package directories exist
packer.init = function(user_config)
  user_config = user_config or {}
  config = util.deep_extend('force', config, user_config)
  packer.reset()
  config.package_root = vim.fn.fnameescape(vim.fn.fnamemodify(config.package_root, ':p'))
  config.compile_path = vim.fn.fnameescape(config.compile_path)
  local _
  config.package_root, _ = string.gsub(config.package_root, util.get_separator() .. '$', '', 1)
  config.pack_dir = join_paths(config.package_root, config.plugin_package)
  config.opt_dir = join_paths(config.pack_dir, 'opt')
  config.start_dir = join_paths(config.pack_dir, 'start')
  local plugin_utils = require_and_configure 'plugin_utils'
  plugin_utils.ensure_dirs()
  if not config.disable_commands then
    packer.make_commands()
  end
end

packer.make_commands = function()
  vim.cmd [[command! PackerInstall           lua require('packer').install()]]
  vim.cmd [[command! PackerUpdate            lua require('packer').update()]]
  vim.cmd [[command! PackerSync              lua require('packer').sync()]]
  vim.cmd [[command! PackerClean             lua require('packer').clean()]]
  vim.cmd [[command! -nargs=* PackerCompile  lua require('packer').compile(<q-args>)]]
  vim.cmd [[command! PackerStatus            lua require('packer').status()]]
  vim.cmd [[command! PackerProfile           lua require('packer').profile_output()]]
  vim.cmd [[command! -nargs=+ -complete=customlist,v:lua.require'packer'.loader_complete PackerLoad lua require('packer').loader(<q-args>)]]
end

packer.reset = function()
  plugins = {}
  plugin_specifications = {}
  rocks = {}
end

--- Add a Luarocks package to be managed
packer.use_rocks = function(rock)
  if type(rock) == 'string' then
    rock = { rock }
  end
  if not vim.tbl_islist(rock) and type(rock[1]) == 'string' then
    rocks[rock[1]] = rock
  else
    for _, r in ipairs(rock) do
      local rock_name = (type(r) == 'table') and r[1] or r
      rocks[rock_name] = r
    end
  end
end

--- The main logic for adding a plugin (and any dependencies) to the managed set
-- Can be invoked with (1) a single plugin spec as a string, (2) a single plugin spec table, or (3)
-- a list of plugin specs
-- TODO: This should be refactored into its own module and the various keys should be implemented
-- (as much as possible) as ordinary handlers
local manage = nil
manage = function(plugin_data)
  local plugin_spec = plugin_data.spec
  local spec_line = plugin_data.line
  local spec_type = type(plugin_spec)
  if spec_type == 'string' then
    plugin_spec = { plugin_spec }
  elseif spec_type == 'table' and #plugin_spec > 1 then
    for _, spec in ipairs(plugin_spec) do
      manage { spec = spec, line = spec_line }
    end
    return
  end

  local log = require_and_configure 'log'
  if plugin_spec[1] == vim.NIL or plugin_spec[1] == nil then
    log.warn('No plugin name provided at line ' .. spec_line .. '!')
    return
  end

  local path = vim.fn.expand(plugin_spec[1])
  local name_segments = vim.split(path, util.get_separator())
  local segment_idx = #name_segments
  local name = plugin_spec.as or name_segments[segment_idx]
  while name == '' and segment_idx > 0 do
    name = name_segments[segment_idx]
    segment_idx = segment_idx - 1
  end

  if name == '' then
    log.warn('"' .. plugin_spec[1] .. '" is an invalid plugin name!')
    return
  end

  if plugins[name] and not plugins[name].from_requires then
    log.warn('Plugin "' .. name .. '" is used twice! (line ' .. spec_line .. ')')
    return
  end

  if plugin_spec.as and plugins[plugin_spec.as] then
    log.error(
      'The alias '
        .. plugin_spec.as
        .. ', specified for '
        .. path
        .. ' at '
        .. spec_line
        .. ' is already used as another plugin name!'
    )
    return
  end

  -- Handle aliases
  plugin_spec.short_name = name
  plugin_spec.name = path
  plugin_spec.path = path

  -- Some config keys modify a plugin type
  if plugin_spec.opt then
    plugin_spec.manual_opt = true
  elseif plugin_spec.opt == nil and config.opt_default then
    plugin_spec.manual_opt = true
    plugin_spec.opt = true
  end

  local compile = require_and_configure 'compile'
  for _, key in ipairs(compile.opt_keys) do
    if plugin_spec[key] then
      plugin_spec.opt = true
      break
    end
  end

  plugin_spec.install_path = join_paths(plugin_spec.opt and config.opt_dir or config.start_dir, plugin_spec.short_name)

  local plugin_utils = require_and_configure 'plugin_utils'
  local plugin_types = require_and_configure 'plugin_types'
  local handlers = require_and_configure 'handlers'
  if not plugin_spec.type then
    plugin_utils.guess_type(plugin_spec)
  end
  if plugin_spec.type ~= plugin_utils.custom_plugin_type then
    plugin_types[plugin_spec.type].setup(plugin_spec)
  end
  for k, v in pairs(plugin_spec) do
    if handlers[k] then
      handlers[k](plugins, plugin_spec, v)
    end
  end
  plugins[plugin_spec.short_name] = plugin_spec
  if plugin_spec.rocks then
    packer.use_rocks(plugin_spec.rocks)
  end

  if plugin_spec.requires and config.ensure_dependencies then
    if type(plugin_spec.requires) == 'string' then
      plugin_spec.requires = { plugin_spec.requires }
    end
    for _, req in ipairs(plugin_spec.requires) do
      if type(req) == 'string' then
        req = { req }
      end
      local req_name_segments = vim.split(req[1], '/')
      local req_name = req_name_segments[#req_name_segments]
      -- this flag marks a plugin as being from a require which we use to allow
      -- multiple requires for a plugin without triggering a duplicate warning *IF*
      -- the plugin is from a `requires` field and the full specificaiton has not been called yet.
      -- @see: https://github.com/wbthomason/packer.nvim/issues/258#issuecomment-876568439
      req.from_requires = true
      if not plugins[req_name] then
        if config.transitive_opt and plugin_spec.manual_opt then
          req.opt = true
          if type(req.after) == 'string' then
            req.after = { req.after, plugin_spec.short_name }
          elseif type(req.after) == 'table' then
            local already_after = false
            for _, name in ipairs(req.after) do
              already_after = already_after or (name == plugin_spec.short_name)
            end
            if not already_after then
              table.insert(req.after, plugin_spec.short_name)
            end
          elseif req.after == nil then
            req.after = plugin_spec.short_name
          end
        end

        if config.transitive_disable and plugin_spec.disable then
          req.disable = true
        end

        manage { spec = req, line = spec_line }
      end
    end
  end
end

--- Add a new keyword handler
packer.set_handler = function(name, func)
  require_and_configure('handlers')[name] = func
end

--- Add a plugin to the managed set
packer.use = function(plugin_spec)
  plugin_specifications[#plugin_specifications + 1] = {
    spec = plugin_spec,
    line = debug.getinfo(2, 'l').currentline,
  }
end

local function manage_all_plugins()
  local log = require_and_configure 'log'
  log.debug 'Processing plugin specs'
  if plugins == nil or next(plugins) == nil then
    for _, spec in ipairs(plugin_specifications) do
      manage(spec)
    end
  end
end

packer.__manage_all = manage_all_plugins

--- Hook to fire events after packer operations
packer.on_complete = vim.schedule_wrap(function()
  vim.cmd [[doautocmd User PackerComplete]]
end)

--- Hook to fire events after packer compilation
packer.on_compile_done = function()
  vim.cmd [[doautocmd User PackerCompileDone]]
end

--- Clean operation:
-- Finds plugins present in the `packer` package but not in the managed set
packer.clean = function(results)
  local plugin_utils = require_and_configure 'plugin_utils'
  local a = require 'packer.async'
  local async = a.sync
  local await = a.wait
  local luarocks = require_and_configure 'luarocks'
  local clean = require_and_configure 'clean'
  require_and_configure 'display'

  manage_all_plugins()
  async(function()
    local luarocks_clean_task = luarocks.clean(rocks, results, nil)
    if luarocks_clean_task ~= nil then
      await(luarocks_clean_task)
    end
    local fs_state = await(plugin_utils.get_fs_state(plugins))
    await(clean(plugins, fs_state, results))
    packer.on_complete()
  end)()
end

local function args_or_all(...)
  return util.nonempty_or({ ... }, vim.tbl_keys(plugins))
end

--- Install operation:
-- Takes an optional list of plugin names as an argument. If no list is given, operates on all
-- managed plugins.
-- Installs missing plugins, then updates helptags and rplugins
packer.install = function(...)
  local log = require_and_configure 'log'
  log.debug 'packer.install: requiring modules'
  local plugin_utils = require_and_configure 'plugin_utils'
  local a = require 'packer.async'
  local async = a.sync
  local await = a.wait
  local luarocks = require_and_configure 'luarocks'
  local clean = require_and_configure 'clean'
  local install = require_and_configure 'install'
  local display = require_and_configure 'display'

  manage_all_plugins()
  local install_plugins
  if ... then
    install_plugins = { ... }
  end
  async(function()
    local fs_state = await(plugin_utils.get_fs_state(plugins))
    if not install_plugins then
      install_plugins = vim.tbl_keys(fs_state.missing)
    end
    if #install_plugins == 0 then
      log.info 'All configured plugins are installed'
      packer.on_complete()
      return
    end

    await(a.main)
    local start_time = vim.fn.reltime()
    local results = {}
    await(clean(plugins, fs_state, results))
    await(a.main)
    log.debug 'Gathering install tasks'
    local tasks, display_win = install(plugins, install_plugins, results)
    if next(tasks) then
      log.debug 'Gathering Luarocks tasks'
      local luarocks_ensure_task = luarocks.ensure(rocks, results, display_win)
      if luarocks_ensure_task ~= nil then
        table.insert(tasks, luarocks_ensure_task)
      end
      table.insert(tasks, 1, function()
        return not display.status.running
      end)
      table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
      log.debug 'Running tasks'
      display_win:update_headline_message('installing ' .. #tasks - 2 .. ' / ' .. #tasks - 2 .. ' plugins')
      a.interruptible_wait_pool(unpack(tasks))
      local install_paths = {}
      for plugin_name, r in pairs(results.installs) do
        if r.ok then
          table.insert(install_paths, results.plugins[plugin_name].install_path)
        end
      end

      await(a.main)
      plugin_utils.update_helptags(install_paths)
      plugin_utils.update_rplugins()
      local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
      display_win:final_results(results, delta)
      packer.on_complete()
    else
      log.info 'Nothing to install!'
      packer.on_complete()
    end
  end)()
end

--- Update operation:
-- Takes an optional list of plugin names as an argument. If no list is given, operates on all
-- managed plugins.
-- Fixes plugin types, installs missing plugins, then updates installed plugins and updates helptags
-- and rplugins
packer.update = function(...)
  local log = require_and_configure 'log'
  log.debug 'packer.update: requiring modules'
  local plugin_utils = require_and_configure 'plugin_utils'
  local a = require 'packer.async'
  local async = a.sync
  local await = a.wait
  local luarocks = require_and_configure 'luarocks'
  local clean = require_and_configure 'clean'
  local install = require_and_configure 'install'
  local display = require_and_configure 'display'
  local update = require_and_configure 'update'

  manage_all_plugins()

  local update_plugins = args_or_all(...)
  async(function()
    local start_time = vim.fn.reltime()
    local results = {}
    local fs_state = await(plugin_utils.get_fs_state(plugins))
    local missing_plugins, installed_plugins = util.partition(vim.tbl_keys(fs_state.missing), update_plugins)
    update.fix_plugin_types(plugins, missing_plugins, results, fs_state)
    await(clean(plugins, fs_state, results))
    local _
    _, missing_plugins = util.partition(vim.tbl_keys(results.moves), missing_plugins)
    log.debug 'Gathering install tasks'
    await(a.main)
    local tasks, display_win = install(plugins, missing_plugins, results)
    local update_tasks
    log.debug 'Gathering update tasks'
    await(a.main)
    update_tasks, display_win = update(plugins, installed_plugins, display_win, results)
    vim.list_extend(tasks, update_tasks)
    log.debug 'Gathering luarocks tasks'
    local luarocks_ensure_task = luarocks.ensure(rocks, results, display_win)
    if luarocks_ensure_task ~= nil then
      table.insert(tasks, luarocks_ensure_task)
    end
    table.insert(tasks, 1, function()
      return not display.status.running
    end)
    table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
    display_win:update_headline_message('updating ' .. #tasks - 2 .. ' / ' .. #tasks - 2 .. ' plugins')
    log.debug 'Running tasks'
    a.interruptible_wait_pool(unpack(tasks))
    local install_paths = {}
    for plugin_name, r in pairs(results.installs) do
      if r.ok then
        table.insert(install_paths, results.plugins[plugin_name].install_path)
      end
    end

    for plugin_name, r in pairs(results.updates) do
      if r.ok then
        table.insert(install_paths, results.plugins[plugin_name].install_path)
      end
    end

    await(a.main)
    plugin_utils.update_helptags(install_paths)
    plugin_utils.update_rplugins()
    local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
    display_win:final_results(results, delta)
    packer.on_complete()
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
  local log = require_and_configure 'log'
  log.debug 'packer.sync: requiring modules'
  local plugin_utils = require_and_configure 'plugin_utils'
  local a = require 'packer.async'
  local async = a.sync
  local await = a.wait
  local luarocks = require_and_configure 'luarocks'
  local clean = require_and_configure 'clean'
  local install = require_and_configure 'install'
  local display = require_and_configure 'display'
  local update = require_and_configure 'update'

  manage_all_plugins()

  local sync_plugins = args_or_all(...)
  async(function()
    local start_time = vim.fn.reltime()
    local results = {}
    local fs_state = await(plugin_utils.get_fs_state(plugins))
    local missing_plugins, installed_plugins = util.partition(vim.tbl_keys(fs_state.missing), sync_plugins)

    await(a.main)
    update.fix_plugin_types(plugins, missing_plugins, results, fs_state)
    local _
    _, missing_plugins = util.partition(vim.tbl_keys(results.moves), missing_plugins)
    if config.auto_clean then
      await(clean(plugins, fs_state, results))
      _, installed_plugins = util.partition(vim.tbl_keys(results.removals), installed_plugins)
    end

    await(a.main)
    log.debug 'Gathering install tasks'
    local tasks, display_win = install(plugins, missing_plugins, results)
    local update_tasks
    log.debug 'Gathering update tasks'
    await(a.main)
    update_tasks, display_win = update(plugins, installed_plugins, display_win, results)
    vim.list_extend(tasks, update_tasks)
    log.debug 'Gathering luarocks tasks'
    local luarocks_clean_task = luarocks.clean(rocks, results, display_win)
    if luarocks_clean_task ~= nil then
      table.insert(tasks, luarocks_clean_task)
    end
    local luarocks_ensure_task = luarocks.ensure(rocks, results, display_win)
    if luarocks_ensure_task ~= nil then
      table.insert(tasks, luarocks_ensure_task)
    end
    table.insert(tasks, 1, function()
      return not display.status.running
    end)
    table.insert(tasks, 1, config.max_jobs and config.max_jobs or (#tasks - 1))
    log.debug 'Running tasks'
    display_win:update_headline_message('syncing ' .. #tasks - 2 .. ' / ' .. #tasks - 2 .. ' plugins')
    a.interruptible_wait_pool(unpack(tasks))
    local install_paths = {}
    for plugin_name, r in pairs(results.installs) do
      if r.ok then
        table.insert(install_paths, results.plugins[plugin_name].install_path)
      end
    end

    for plugin_name, r in pairs(results.updates) do
      if r.ok then
        table.insert(install_paths, results.plugins[plugin_name].install_path)
      end
    end

    await(a.main)
    if config.compile_on_sync then
      packer.compile()
    end
    plugin_utils.update_helptags(install_paths)
    plugin_utils.update_rplugins()
    local delta = string.gsub(vim.fn.reltimestr(vim.fn.reltime(start_time)), ' ', '')
    display_win:final_results(results, delta)
    packer.on_complete()
  end)()
end

packer.status = function()
  local async = require('packer.async').sync
  local display = require_and_configure 'display'
  require_and_configure 'log'

  manage_all_plugins()
  async(function()
    local display_win = display.open(config.display.open_fn or config.display.open_cmd)
    display_win:status(_G.packer_plugins)
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
  for k, v in pairs(package.loaded) do
    if type(v) == 'function' then
      reverse_index[v] = k
    end
  end
  for _, plugin in pairs(plugs) do
    local cfg = reload_module(reverse_index[plugin.config])
    local setup = reload_module(reverse_index[plugin.setup])
    if cfg then
      plugin.config = cfg
    end
    if setup then
      plugin.setup = setup
    end
  end
end

local function parse_value(value)
  if value == 'true' then
    return true
  end
  if value == 'false' then
    return false
  end
  return value
end

local function parse_args(args)
  local result = {}
  if args then
    local parts = vim.split(args, ' ')
    for _, part in ipairs(parts) do
      if part then
        if part:find '=' then
          local key, value = unpack(vim.split(part, '='))
          result[key] = parse_value(value)
        end
      end
    end
  end
  return result
end

--- Update the compiled lazy-loader code
--- Takes an optional argument of a path to which to output the resulting compiled code
packer.compile = function(raw_args)
  local compile = require_and_configure 'compile'
  local log = require_and_configure 'log'

  manage_all_plugins()
  local args = parse_args(raw_args)
  local output_path = args.output_path or config.compile_path
  local output_lua = vim.fn.fnamemodify(output_path, ':e') == 'lua'
  local should_profile = args.profile
  -- the user might explicitly choose for this value to be false in which case
  -- an or operator will not work
  if should_profile == nil then
    should_profile = config.profile.enable
  end
  refresh_configs(plugins)
  -- NOTE: we copy the plugins table so the in memory value is not mutated during compilation
  local compiled_loader = compile(vim.deepcopy(plugins), output_lua, should_profile)
  output_path = vim.fn.expand(output_path)
  vim.fn.mkdir(vim.fn.fnamemodify(output_path, ':h'), 'p')
  local output_file = io.open(output_path, 'w')
  output_file:write(compiled_loader)
  output_file:close()
  if config.auto_reload_compiled then
    vim.cmd('source ' .. output_path)
  end
  log.info 'Finished compiling lazy-loaders!'
  packer.on_compile_done()

  -- TODO: remove this after migration period (written 2021/06/28)
  local old_output_path
  if output_lua then
    old_output_path = vim.fn.fnamemodify(output_path, ':r') .. '.vim'
  else
    old_output_path = vim.fn.fnamemodify(output_path, ':r') .. '.lua'
  end

  if vim.loop.fs_stat(old_output_path) then
    os.remove(old_output_path)
    log.warn(
      '"'
        .. vim.fn.fnamemodify(old_output_path, ':~:.')
        .. '" was replaced by "'
        .. vim.fn.fnamemodify(output_path, ':~:.')
        .. '"'
    )
    log.warn 'If you have not updated Neovim since 2021/06/11 you must do so now'
  end
  -- TODO: end migration chunk (2021/07/02)
end

packer.profile_output = function()
  local async = require('packer.async').sync
  local display = require_and_configure 'display'
  local log = require_and_configure 'log'

  manage_all_plugins()
  if _G._packer.profile_output then
    async(function()
      local display_win = display.open(config.display.open_fn or config.display.open_cmd)
      display_win:profile_output(_G._packer.profile_output)
    end)()
  else
    log.warn 'You must run PackerCompile with profiling enabled first e.g. PackerCompile profile=true'
  end
end

-- Load plugins
-- @param plugins string String of space separated plugins names
--                      intended for PackerLoad command
packer.loader = function(plugins_names)
  local plugin_list = vim.tbl_filter(function(name)
    return #name > 0
  end, vim.split(plugins_names, ' '))
  require 'packer.load'(plugin_list, {}, _G.packer_plugins)
end

-- Completion for not yet loaded plugins
-- Intended to provide completion for PackerLoad command
packer.loader_complete = function(lead, _, _)
  local completion_list = {}
  for name, plugin in pairs(_G.packer_plugins) do
    if vim.startswith(name, lead) and not plugin.loaded then
      table.insert(completion_list, name)
    end
  end
  table.sort(completion_list)
  return completion_list
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
  local log = require_and_configure 'log'
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
      log.error 'You must provide a function or table of specifications as the first element of the argument to startup!'
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
    setfenv(user_func, vim.tbl_extend('force', getfenv(), { use = packer.use, use_rocks = packer.use_rocks }))
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
