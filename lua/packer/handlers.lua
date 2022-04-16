--- Handlers:
--- A handler is a table minimally defining the following keys:
---   name: a string uniquely naming the handler
---   startup: a Boolean indicating if the handler needs to be applied at startup or only when plugins are being fully managed
---   process(spec): a function which precomputes any information necessary to apply the handler for the given plugin spec
---   apply(): a function which evaluates the handler's effect
---   reset(): a function which clears all precomputed state from the handler

local M = {}

-- Default handlers are defined here rather than in their own modules to avoid needing to load a
-- bunch of files on every start
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
local timed_load = profile.timed_load

-- Handler for the 'setup' key
local setup_handler = { name = 'setup', startup = true, setups = {} }
function setup_handler.reset()
  setup_handler.setups = {}
end

function setup_handler.process(plugin)
  if plugin.setup == nil then
    plugin.only_setup = false
    return
  end

  -- only_setup may already be false, but should never be true before now
  plugin.only_setup = plugin.only_setup == nil
  plugin.simple_load = false
  setup_handler.setups[#setup_handler.setups + 1] = plugin
end

function setup_handler.apply()
  local setups = setup_handler.setups
  for i = 1, #setups do
    local plugin = setups[i]
    timed_run(plugin.setup, 'setup for ' .. plugin.short_name, plugin.short_name, plugin)
    if plugin.only_setup then
      timed_load(plugin.short_name)
    end
  end
end

-- Handler for the 'config' key
local config_handler = { name = 'config', startup = true, configs = {} }
function config_handler.reset()
  config_handler.configs = {}
end

function config_handler.process(plugin)
  if plugin.config then
    plugin.simple_load = false
    config_handler.configs[#config_handler.configs + 1] = plugin
  end
end

function config_handler.apply()
  local configs = config_handler.configs
  for i = 1, #configs do
    local plugin = configs[i]
    timed_run(plugin.config, 'config for ' .. plugin.short_name, plugin.short_name, plugin)
  end
end

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
    require 'packer.load'(to_load, { module = module_name }, _G.packer_plugins)
    local loaded_mod = package.loaded[module_name]
    if loaded_mod then
      return function(_)
        return loaded_mod
      end
    end
  end
end

function module_handler.process(plugin)
  if plugin.module or plugin.module_pattern then
    plugin.simple_load = false
    plugin.only_sequence = false
    plugin.only_setup = false
    plugin.only_cond = false
    if plugin.module then
      if type(plugin.module) == 'string' then
        plugin.module = { plugin.module }
      end

      for i = 1, #plugin.module do
        module_handler.modules['^' .. vim.pesc(plugin.module[i])] = plugin
      end
    else
      if type(plugin.module_pattern) == 'string' then
        plugin.module_pattern = { plugin.module_pattern }
      end

      for i = 1, #plugin.module_pattern do
        module_handler.modules[plugin.module_pattern[i]] = plugin
      end
    end
  end
end

function module_handler.apply()
  if #module_handler.modules > 0 then
    if vim.g.packer_custom_loader_enabled then
      package.loaders[1] = lazy_load_module
    else
      table.insert(package.loaders, 1, lazy_load_module)
      vim.g.packer_custom_loader_enabled = true
    end
  end
end

local startup_handlers = {
  module_handler,
  cmd = true,
  cond = true,
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
    startup_handlers[i].process(plugin)
  end
end

function M.apply_startup()
  for i = 1, num_startup do
    startup_handlers[i].apply()
  end
end

function M.process_deferred(plugin)
  for i = 1, num_deferred do
    deferred_handlers[i].process(plugin)
  end
end

function M.apply_deferred()
  for i = 1, num_deferred do
    deferred_handlers[i].apply()
  end
end

-- TODO: Probably a function to get all handlers, to get a handler by its name, etc.
function M.get_startup()
  return startup_handlers
end

function M.get_deferred()
  return deferred_handlers
end

return M
