--- Main packer module
local M = {}

-- TODO: Investigate whether using FFI structs for the elements of these tables would be useful
-- and/or faster for operations
local plugins, plugin_specifications, rocks, profile_output

--- Configure and reset packer
function M.init(user_config)
  local config = require('packer.config').configure(user_config)
  M.reset()
  local plugin_utils = require 'packer.plugin_utils'
  plugin_utils.ensure_dirs()
  -- TODO: Maybe this should not go in init, but rather be separately called in startup?
  if not config.disable_commands then
    M.make_commands()
  end
end

--- Reset packer's internal state
function M.reset()
  plugins = {}
  plugin_specifications = {}
  rocks = {}
end

--- packer's predefined commands
local commands = {
  {
    nargs = [[*]],
    complete = [[customlist,v:lua.require'packer'._complete_plugin_names]],
    cmd = [[PackerInstall]],
    operation = [[lua require'packer'.install(<f-args>)]],
  },
  {
    nargs = [[*]],
    complete = [[customlist,v:lua.require'packer'._complete_plugin_names]],
    cmd = [[PackerUpdate]],
    operation = [[lua require'packer'.update(<f-args>)]],
  },
  {
    nargs = [[*]],
    complete = [[customlist,v:lua.require'packer'._complete_plugin_names]],
    cmd = [[PackerSync]],
    operation = [[lua require'packer'.sync(<f-args>)]],
  },
  { cmd = [[PackerClean]], operation = [[lua require'packer'.clean()]] },
  { cmd = [[PackerStatus]], operation = [[lua require'packer'.status()]] },
  { cmd = [[PackerProfileOutput]], operation = [[lua require'packer'.profile_output()]] },
  {
    bang = true,
    nargs = [[+]],
    complete = [[customlist,v:lua.require'packer'._complete_loadable_plugin_names]],
    cmd = [[PackerLoad]],
    operation = [[lua require'packer'.activate_plugins(<f-args>, '<bang>' == '!')]],
  },
}

--- Ensure the existence of packer's standard commands
function M.make_commands() end
for i = 1, #commands do
  local cmd = commands[i]
  local cmd_def = string.format(
    [[command! %s %s %s %s %s]],
    cmd.bang and '-bang' or '',
    cmd.nargs and ('-nargs=' .. cmd.nargs) or '',
    cmd.complete and ('-complete=' .. cmd.complete) or '',
    cmd.cmd,
    cmd.operation
  )

  vim.cmd(cmd_def)
end

--- Utility function to ensure that an object is a table
--- Redefined here from packer.util to avoid an unnecessary require
local function ensure_table(obj)
  if type(obj) ~= 'table' then
    obj = { obj }
  end

  return obj
end

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
      local rock_name = (type(rock) == 'table') and rock[1] or rock
      rocks[rock_name] = rock
    end
  end
end

--- Add a plugin specification key handler to the set which will be run on plugins
---@param handler table describing a handler object
--- See packer.handlers for examples
function M.add_handler(handler)
  require('packer.handlers').add(handler)
end

--- Recursively flatten a potentially nested list of plugin specifications
--- NOTE: This special-cases the `requires` key, as it can nest specifications
---@param plugin_specification string or full plugin specification or list of plugin specifications
local function flatten_specification(plugin_specification)
  if plugin_specification == nil then
    return nil
  end

  if type(plugin_specification) == 'string' then
    plugin_specification = { plugin_specification }
  end

  local result = {}
  local function flatten(specs, from_requires)
    local num_specs = #specs
    for i = 1, num_specs do
      local spec = specs[i]
      spec.from_requires = from_requires
      result[#result + 1] = spec
      if spec.requires then
        ensure_table(spec.requires)
        flatten(spec.requires, true)
      end
    end
  end

  flatten(plugin_specification)
  return result
end

--- Add one or more plugin specifications to the managed set
---@param plugin_specification string, full plugin specification, or list of plugin specifications
--- See main packer documentation for expected format
function M.use(plugin_specification)
  local current_line = debug.getinfo(2, 'l').currentline
  local flattened_specification = flatten_specification(plugin_specification)
  local num_specs = #flattened_specification
  for i = 1, num_specs do
    local plugin = flattened_specification[i]
    plugin_specifications[#plugin_specifications + 1] = {
      spec = plugin,
      line = current_line,
      plugin_index = i,
    }

    process_runtime_handlers(plugin)
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
      local log = require 'packer.log'
      log.error 'You must provide a function or table of specifications as the first element of the argument to startup!'
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
        local log = require 'packer.log'
        log.error('Failure running setup function: ' .. vim.inspect(err))
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
  vim.cmd [[doautocmd User PackerComplete]]
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
  if profile_output then
    require('packer.display').display_profile_output(profile_output)
  else
    local log = require 'packer.log'
    log.warn 'No profile output to display! Set config.profile.enable = true and restart'
  end
end

--- Manually load plugins
--- Takes varargs giving plugin names to load, as either a string of space separated names or a list
--- of names as independent strings
function M.activate_plugins(...)
  ensure_all_plugins_managed()
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
function M._complete_loadable_plugin_names(lead, _, _)
  ensure_all_plugins_managed()
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
function M._complete_plugin_names(lead, _, _)
  ensure_all_plugins_managed()
  local completion_list = vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, vim.tbl_keys(plugins))
  table.sort(completion_list)
  return completion_list
end

return M
