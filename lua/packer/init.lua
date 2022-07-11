--- Main packer module
local M = {}

-- TODO: Add design for hooks after operations finish

-- TODO: Investigate whether using FFI structs for the elements of these tables would be useful
-- and/or faster for operations
local plugins, plugin_specifications, rocks, config

local handlers = require 'packer.handlers'

local function ensure_dir(path)
  local path_info = vim.loop.fs_stat(path)
  if path_info == nil or path_info.type ~= 'directory' then
    -- TODO: Investigate if rolling our own mkdir -p with vim.loop.fs_mkdir is faster
    if vim.fn.mkdir(path, 'p') ~= 1 then
      require('packer.log').warn("Couldn't create path: " .. path)
    end
  end
end

--- Configure and reset packer
function M.init(user_config)
  if vim.fn.has 'nvim-0.7' ~= 1 then
    require('packer.log').error 'Invalid Neovim version for packer.nvim!'
    error 'Tried to use packer.nvim with Neovim <v0.7!'
  end

  config = require('packer.config').configure(user_config)
  M.reset()
  ensure_dir(config.opt_dir)
  ensure_dir(config.start_dir)
  ensure_dir(config.snapshot_path)

  -- TODO: Maybe this should not go in init, but rather be separately called in startup?
  if not config.disable_commands then
    M.make_commands()
  end
end

--- Reset packer's internal state
function M.reset()
  plugin_specifications = {}
  plugins = {}
  rocks = {}
end

-- Redefined here from packer.util to avoid an unnecessary require
--- Utility function to ensure that an object is a table
local function ensure_table(obj)
  return (type(obj) == 'table' and obj) or { obj }
end

--- TODO: Should this be special-cased like this? It seems as though this might be better as a
--- normal handler
--- Add one or more Luarocks packages to the managed set
--- Primarily designed for use with non-plugin-specific rocks
---@param rock_specifications string, full rock specification, or list of rock specifications
--- See packer.luarocks documentation for rock specification format
function M.use_rocks(rock_specifications)
  rock_specifications = ensure_table(rock_specifications)
  -- Is this a single rock specification?
  if type(rock_specifications[1]) == 'string' and not vim.tbl_islist(rock_specifications) then
    rocks[rock_specifications[1]] = rock_specifications
  else
    -- If not, handle each specified rock
    for i = 1, #rock_specifications do
      local rock = rock_specifications[i]
      local rock_name = (type(rock) == 'string' and rock) or rock[1]
      rocks[rock_name] = rock
    end
  end
end

--- Add a plugin specification key handler to the set which will be run on plugins
---@param handler table describing a handler object
--- See packer.handlers for examples
M.add_handler = handlers.add

local expand = vim.fn.expand
local path_utils = require 'packer.path'
local path_separator = path_utils.path_separator
--- Get the canonical short name for a plugin. Defined here to avoid a require
---@param plugin table plugin spec
local function get_plugin_short_name(plugin)
  local expanded_path = expand(plugin[1])
  local name_segments = vim.split(expanded_path, path_separator)
  local idx = #name_segments
  -- NOTE: special-cased key here; should this be a handler?
  local name = plugin.as or name_segments[idx]
  while name == '' and idx > 0 do
    name = name_segments[idx]
    idx = idx - 1
  end

  return name, expanded_path
end

--- Utility function to get the canonical names of top-level plugins from a table of specifications
---@param specs table of plugin specs
local function get_plugin_names(specs)
  local names = {}
  for i = 1, #specs do
    names[#names + 1] = get_plugin_short_name(specs[i])
  end

  return names
end

--- Utility function to recursively flatten a potentially nested list of plugin specifications. Used by flatten_specification
---@param specs table of (potentially nested) plugin specifications
---@param result table modified in place with the flattened list of specs
local function flatten(specs, from_requires, result)
  local num_specs = #specs
  for i = 1, num_specs do
    local spec = specs[i]
    spec.from_requires = from_requires
    result[#result + 1] = spec
    if spec.requires then
      ensure_table(spec.requires)
      flatten(spec.requires, true)
      spec.requires = get_plugin_names(spec.requires)
    end
  end
end

--- Recursively flatten a potentially nested list of plugin specifications
---@param plugin_specification string or full plugin specification or list of plugin specifications
local function flatten_specification(plugin_specification)
  plugin_specification = ensure_table(plugin_specification)
  local result = {}
  flatten(plugin_specification, false, result)
  return result
end

--- Utility function responsible for consistently setting plugin metadata that may be used by
--- handlers
local function set_plugin_metadata(plugin)
  local name, path = get_plugin_short_name(plugin)
  -- Check name/alias validity
  if name == '' then
    require('packer.log').warn([["]] .. plugin[1] .. [[" is an invalid plugin name!]])
    return false
  end

  if plugins[name] and not plugins[name].from_requires then
    require('packer.log').warn([[Plugin "]] .. name .. [[" is used twice! (line ]] .. plugin.line .. [[)]])
    return false
  end

  if plugin.as and plugins[plugin.as] then
    require('packer.log').error(
      string.format(
        [[The alias %s specified for %s at line %d is already used as a plugin name!]],
        plugin.as,
        path,
        plugin.line
      )
    )
    return false
  end

  -- Set plugin name and path
  -- TODO: Eliminate use of plugin.name in the rest of the code and call plugin.short_name plugin.name
  plugin.short_name = name
  plugin.name = path
  plugin.path = path

  -- Set manual optness
  if plugin.opt then
    plugin.manual_opt = true
  elseif plugin.opt == nil and config.opt_default then
    plugin.manual_opt = true
    plugin.opt = true
  end

  return true
end

local getinfo = debug.getinfo
--- Add one or more plugin specifications to the managed set
---@param plugin_specification string, full plugin specification, or list of plugin specifications
--- See main packer documentation for expected format
function M.use(plugin_specification)
  local current_line = getinfo(2, 'l').currentline
  local flattened_specification = flatten_specification(plugin_specification)
  local num_specs = #flattened_specification
  for i = 1, num_specs do
    local plugin = flattened_specification[i]
    if not plugin[1] then
      require('packer.log').warn('No plugin name provided for spec at line ' .. current_line)
    else
      plugin_specifications[#plugin_specifications + 1] = {
        spec = plugin,
        line = current_line,
        plugin_index = i,
      }

      set_plugin_metadata(plugin)
      handlers.process_startup(plugin)
      plugins[plugin.short_name] = plugin
    end
  end
end

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
function M.startup(spec)
  local user_func, user_config, user_plugins
  if type(spec) == 'function' then
    user_func = spec
  elseif type(spec) == 'table' then
    if type(spec[1]) == 'function' then
      user_func = spec[1]
    elseif type(spec[1]) == 'table' then
      user_plugins = spec[1]
    else
      require('packer.log').error 'You must provide a function or table of specifications as the first element of the argument to startup!'
      return
    end

    user_config = spec.config
  end

  M.init(user_config)
  if user_func then
    if user_func then
      setfenv(user_func, vim.tbl_extend('force', getfenv(), { use = M.use, use_rocks = M.use_rocks }))
      local status, err = pcall(user_func, M.use, M.use_rocks)
      if not status then
        require('packer.log').error('Failure running setup function: ' .. vim.inspect(err))
        error(err)
      end
    else
      M.use(user_plugins)
    end

    M.load()
    return M
  end
end

--- Generate lazy-loaders and run plugin config/setup functions to finish the startup stage
-- TODO: Not sure this is the right name to pick
function M.load()
  error 'Not implemented!'
end

--- Hook to fire events after completion of packer operations
M.on_complete = vim.schedule_wrap(function()
  vim.api.nvim_exec_autocmds('User', { pattern = 'PackerComplete' })
end)

--- Clean operation
--- Finds and removes plugins which are installed but not managed
function M.clean()
  require('packer.operations').clean()
end

--- Install operation
--- Takes varargs for plugin names to install, or nothing to install all managed plugins
function M.install(...)
  require('packer.operations').install(...)
end

--- Update operation
--- Takes varargs for plugin names to update, or nothing to update all managed plugins
function M.update(...)
  require('packer.operations').update(...)
end

--- Sync operation
--- Takes varargs for plugin names to sync, or nothing to sync all managed plugins
function M.sync(...)
  require('packer.operations').sync(...)
end

--- Show the current status of the managed plugins
function M.status()
  require('packer.status').status()
end

--- Show the output, if any exists, of packer's profiler
function M.profile_output()
  local profiles = require('packer.profile').get_profile_data()
  if profiles then
    require('packer.display').display_profile_output(profiles)
  else
    local log = require 'packer.log'
    log.warn 'No profile output to display! Set config.profile.enable = true and restart'
  end
end

--- Manually load plugins
--- Takes varargs giving plugin names to load, as either a string of space separated names or a list
--- of names as independent strings
function M.activate_plugins(...)
  local plugin_names = { ... }
  local force = plugin_names[#plugin_names] == true
  if type(plugin_names[#plugin_names]) == 'boolean' then
    plugin_names[#plugin_names] = nil
  end

  -- We make a new table here because it's more convenient than expanding a space-separated string
  -- into the existing plugin_names
  local plugin_list = {}
  for _, plugin_name in ipairs(plugin_names) do
    vim.list_extend(
      plugin_list,
      vim.tbl_filter(function(name)
        return #name > 0
      end, vim.split(plugin_name, ' '))
    )
  end

  require 'packer.load'(plugin_list, {}, plugins, force)
end

--- Completion for not-yet-loaded plugin names
--- Used by PackerLoad command
local function complete_loadable_plugin_names(lead, _, _)
  local completion_list = {}
  for name, plugin in pairs(plugins) do
    if vim.startswith(name, lead) and not plugin.loaded then
      table.insert(completion_list, name)
    end
  end
  table.sort(completion_list)
  return completion_list
end

--- Completion for managed plugin names
--- Used by PackerInstall/Update/Sync commands
local function complete_plugin_names(lead, _, _)
  local completion_list = vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, vim.tbl_keys(plugins))
  table.sort(completion_list)
  return completion_list
end

--- packer's predefined commands
local commands = {
  {
    name = [[PackerInstall]],
    command = function(args)
      M.install(unpack(args.fargs))
    end,
    opts = {
      nargs = [[*]],
      complete = complete_plugin_names,
    },
  },
  {
    name = [[PackerUpdate]],
    command = function(args)
      M.update(unpack(args.fargs))
    end,
    opts = {
      nargs = [[*]],
      complete = complete_plugin_names,
    },
  },
  {
    name = [[PackerSync]],
    command = function(args)
      M.sync(unpack(args.fargs))
    end,
    opts = {
      nargs = [[*]],
      complete = complete_plugin_names,
    },
  },
  { name = [[PackerClean]], command = M.clean },
  { name = [[PackerStatus]], command = M.status },
  { name = [[PackerProfileOutput]], command = M.profile_output },
  {
    name = [[PackerLoad]],
    command = function(args)
      M.activate_plugins(unpack(args.fargs), args.bang)
    end,
    opts = {
      bang = true,
      nargs = [[+]],
      complete = complete_loadable_plugin_names,
    },
  },
}

--- Ensure the existence of packer's standard commands
function M.make_commands()
  local create_command = vim.api.nvim_create_user_command
  for i = 1, #commands do
    local cmd = commands[i]
    create_command(cmd.name, cmd.command, cmd.opts)
  end
end

return M
