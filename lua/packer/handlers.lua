--- Handlers:
--- A handler is a table minimally defining the following keys:
---   name: a string uniquely naming the handler
---   startup: a Boolean indicating if the handler needs to be applied at startup or only when plugins are being fully managed
---   process(self, spec): a function which precomputes any information necessary to apply the handler for the given plugin spec
---   apply(self): a function which evaluates the handler's effect
---   reset(self): a function which clears all precomputed state from the handler

local M = {}

local function make_default_handler(spec)
  local state_table_name = spec.name .. 's'
  local handler = { name = spec.name, startup = spec.startup }
  handler[state_table_name] = {}
  if spec.reset then
    handler.reset = spec.reset
  else
    handler.reset = function(_)
      handler[state_table_name] = {}
    end
  end

  if spec.process then
    handler.process = spec.process
  else
    handler.process = function(_, plugin)
      if not plugin[spec.name] then
        return
      end

      if spec.set_loaders ~= false then
        plugin.loaders = plugin.loaders or { _n = 0 }
        plugin.loaders[spec.name] = true
        plugin.loaders._n = plugin.loaders._n + 1
      end

      if type(plugin[spec.name]) == 'string' then
        plugin[spec.name] = { plugin[spec.name] }
      end

      if spec.collect then
        local key_tbl = plugin[spec.name]
        for i = 1, #key_tbl do
          local val = key_tbl[i]
          handler[state_table_name][val] = handler[state_table_name][val] or {}
          handler[state_table_name][val][#handler[state_table_name][val] + 1] = plugin
        end
      else
        handler[state_table_name][#handler[state_table_name] + 1] = plugin
      end
    end
  end

  handler.apply = spec.apply
  return handler
end

-- Default handlers are defined here rather than in their own modules to avoid needing to load a
-- bunch of files on every start
-- TODO: Investigate if having handlers in their own modules and loading them as-needed would lead
-- to performance improvements. Seems likely
local handler_names = {
  [module] = true,
  cmd = true,
  cond = true,
  config = true,
  disable = true,
  event = true,
  fn = true,
  ft = true,
  keys = true,
  load_after = true,
  requires = true,
  rtp = true,
  -- TODO: handle ftdetect stuff with caching?
  setup = true,
}

-- Default handler implementations

local profile = require 'packer.profile'
local timed_run = profile.timed_run
local timed_packadd = profile.timed_packadd
local timed_load = profile.timed_load

-- Handler for the 'setup' key
local setup_handler = make_default_handler {
  name = 'setup',
  startup = true,
  apply = function(self)
    local setups = self.setups
    for i = 1, #setups do
      local plugin = setups[i]
      timed_run(plugin.setup, 'setup for ' .. plugin.short_name, plugin.short_name, plugin)
      -- Check for only setup
      if plugin.loaders._n == 1 then
        timed_packadd(plugin.short_name)
      end
    end
  end,
}

-- Handler for the 'config' key
local config_handler = make_default_handler {
  name = 'config',
  startup = true,
  set_loaders = false,
  apply = function(self)
    local configs = self.configs
    for i = 1, #configs do
      local plugin = configs[i]
      timed_run(plugin.config, 'config for ' .. plugin.short_name, plugin.short_name, plugin)
    end
  end,
}

-- Handler for the 'module' and 'module_pattern' keys
local module_handler = { name = 'module', startup = true, modules = {}, lazy_load_called = { ['packer.load'] = true } }
function module_handler.reset()
  module_handler.modules = {}
  module_handler.lazy_load_called = { ['packer.load'] = true }
end

local function lazy_load_module(module_name)
  local to_load = {}
  if module_handler.lazy_load_called[module_name] then
    return nil
  end

  module_handler.lazy_load_called[module_name] = true
  for module_pat, plugin in pairs(module_handler.modules) do
    if not plugin.loaded and module_name:match(module_pat) then
      to_load[#to_load + 1] = plugin.short_name
    end
  end

  if #to_load > 0 then
    timed_load(to_load, { module = module_name })
    local loaded_mod = package.loaded[module_name]
    if loaded_mod then
      return function(_)
        return loaded_mod
      end
    end
  end
end

function module_handler.process(_, plugin)
  if plugin.module or plugin.module_pattern then
    plugin.loaders = plugin.loaders or { _n = 0 }
    plugin.loaders.module = true
    plugin.loaders._n = plugin.loaders._n + 1
    if plugin.module then
      if type(plugin.module) == 'string' then
        plugin.module = { plugin.module }
      end

      for i = 1, #plugin.module do
        module_handler.modules['^' .. vim.pesc(plugin.module[i])] = plugin
      end
    end

    if plugin.module_pattern then
      if type(plugin.module_pattern) == 'string' then
        plugin.module_pattern = { plugin.module_pattern }
      end

      for i = 1, #plugin.module_pattern do
        module_handler.modules[plugin.module_pattern[i]] = plugin
      end
    end
  end
end

local packer_custom_loader_enabled = false
function module_handler.apply(_)
  if #module_handler.modules > 0 then
    if packer_custom_loader_enabled then
      package.loaders[1] = lazy_load_module
    else
      table.insert(package.loaders, 1, lazy_load_module)
      packer_custom_loader_enabled = true
    end
  end
end

-- Handler for the cmd key
local cmd_handler = make_default_handler {
  name = 'cmd',
  startup = true,
  collect = true,
  apply = function(self)
    local cmds = self.cmds
    local create_command = vim.api.nvim_create_user_command
    for cmd, plugins in pairs(cmds) do
      if string.match(cmd, '^%w+$') then
        create_command(cmd, function(args)
          args.cmd = cmd
          timed_load(plugins, args)
        end, { bang = true, nargs = [[*]], range = true, complete = 'file' })
      end
    end
  end,
}

-- Handler for the cond key
local cond_handler = make_default_handler {
  name = 'cond',
  startup = true,
  collect = true,
  apply = function(self)
    local conds = self.conds
    for cond, plugins in pairs(conds) do
      if type(cond) == 'string' then
        cond = loadstring('return ' .. cond)
      end

      if cond() then
        timed_load(plugins)
      end
    end
  end,
}

local startup_handlers = {
  module_handler,
  cmd_handler,
  cond_handler,
  config_handler,
  disable = true,
  event = true,
  fn = true,
  ft = true,
  keys = true,
  load_after = true,
  rtp = true,
  setup_handler,
}

local num_startup = #startup_handlers
local deferred_handlers = {
  requires = true,
}

local num_deferred = #deferred_handlers

function M.add(handler)
  if handler_names[handler.name] ~= nil then
    require('packer.log').warn('Duplicate handler "' .. handler.name .. '" added. Ignoring!')
  elseif handler.startup then
    num_startup = num_startup + 1
    startup_handlers[num_startup] = handler
    handler_names[handler.name] = true
  else
    num_deferred = num_deferred + 1
    deferred_handlers[num_deferred] = handler
    handler_names[handler.name] = true
  end
end

function M.process_startup(plugin)
  for i = 1, num_startup do
    startup_handlers[i].process(startup_handlers[i], plugin)
  end
end

function M.apply_startup()
  for i = 1, num_startup do
    startup_handlers[i].apply(startup_handlers[i])
  end
end

function M.process_deferred(plugin)
  for i = 1, num_deferred do
    deferred_handlers[i].process(deferred_handlers[i], plugin)
  end
end

function M.apply_deferred()
  for i = 1, num_deferred do
    deferred_handlers[i].apply(deferred_handlers[i])
  end
end

function M.get_startup()
  return startup_handlers
end

function M.get_deferred()
  return deferred_handlers
end

function M.get_all()
  return vim.tbl_extend('error', {}, startup_handlers, deferred_handlers)
end

function M.get_handler(name)
  if startup_handlers[name] then
    return startup_handlers[name]
  end

  if deferred_handlers[name] then
    return deferred_handlers[name]
  end
end

return M
