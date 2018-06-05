-- Dependencies
local uv = require('luv')
local f = require('fun')

-- Private variables and constants
local nvim = vim.api -- luacheck: ignore

-- Adapted from https://github.com/hkupty/nvimux
local nvim_vars = {}
setmetatable(nvim_vars, {
  __index = function(_, key)
    local key_ = 'g:plague_' .. key
    return nvim.nvim_get_var(key_)
  end
})

local plague = {}
plague.src_repo = 'https://github.com/wbthomason/plague.nvim'
plague.config = {
  compile_viml = false,
  dependencies = true,
  merge = true,
  plugin_dir = '~/.local/share/nvim/plugins',
  threads = nil,
  auto_clean = true,
}

plague.fns = {}

plague.plugins = nil

-- Function definitions
-- Utility functions
plague.fns.err = function (msg)
  nvim.nvim_err_writeln("[Plague] " .. msg)
end

plague.fns.echo = function (msg)
  nvim.nvim_out_write("[Plague] " .. msg .. "\n")
end

-- Plugin specification functions
plague.fns.configure = function (config)
  if config.plugin_dir then
    plague.config.plugin_dir = config.plugin_dir
  end

  if config.dependencies then
    plague.config.dependencies = config.dependencies
  end

  if config.merge then
    plague.config.merge = config.merge
  end

  if config.threads then
    plague.config.threads = config.threads
  end

  if config.auto_clean then
    plague.config.auto_clean = config.auto_clean
  end
end

plague.fns.check_config = function ()
  if plague.config.plugin_dir == nil then
    if nvim_vars['plugin_dir'] then
      plague.config.plugin_dir = nvim_vars['plugin_dir']
    elseif #nvim.nvim_list_runtime_paths() > 0 then
      plague.config.plugin_dir = nvim.nvim_list_runtime_paths()[1] .. '/plugins'
    else
      plague.fns.err("Please set the plugin directory!")
      return false
    end
  end

  for idx, val in pairs(plague.config) do
    if val == nil then
      if nvim_vars[idx] then
        plague.config[idx] = nvim_vars[idx]
      else
        plague.fns.err("Please set the config variable " .. idx)
        return false
      end
    end
  end
  return true
end

plague.fns.sync = function ()
  -- Check basic config
  if not plague.fns.check_config then
    return false
  end

  -- Check that there are plugins to install
  if plague.plugins == nil then
    plague.fns.err("Register plugins with use() before calling sync!")
    return false
  end

  -- Setup plugin infrastructure
  plague.triggers = {
    functions = {},
    commands = {},
    filetypes = {},
    events = {},
  }

  -- Make threadpool context
  local in_ctx = uv.new_work(
    function(plug_name, spec)
      plague.fns.install(spec)
      return plug_name
    end,
    function(plug_name) plague.fns.echo("Installed " .. plug_name) end
  )

  local un_ctx = uv.new_work(
    function(plug_name, spec)
      plague.fns.uninstall(spec)
      return plug_name
    end,
    function(plug_name) plague.fns.echo("Uninstalled " .. plug_name) end
  )

  -- Filter out disabled and enabled plugins
  local disabled_plugins = f.filter(function(_, spec) return spec.disabled end, f.iter(plague.plugins))
  local enabled_plugins = f.filter(function(_, spec) return not spec.disabled end, f.iter(plague.plugins))

  -- Disable the disabled plugins
  disabled_plugins:each(plague.fns.disable)

  -- Install enabled but missing plugins
  local function curried_install(context)
    return function(name, spec) plague.fns.check_install(name, spec, context) end
  end

  enabled_plugins:filter(function (_, spec) return spec.ensure end):each(curried_install(in_ctx))

  -- Remove uninstalled plugins
  if plague.config.auto_clean then
    f.filter(function(name) return plague.plugins[name] end, f.iter(plague.fns.list_packages))
      :each(function (plug_name, spec) uv.queue_work(un_ctx, plug_name, spec) end)
  end

  -- Collect hooks
  local deferred_plugins = enabled_plugins:filter(function(_, spec) return spec.defer end)
  deferred_plugins:each(plague.fns.gather_hooks)

  -- Set up hooks
  plague.fns.set_triggers()
end

plague.fns.use = function (spec)
  local name = spec.name
  if name == nil then
    name = string.match(spec[1], '[^/]-$')
    spec.name = name
  end

  plague.fns.guess_type(spec)

  if plague.plugins == nil then
    plague.plugins = {}
  end

  plague.plugins[name] = spec
end
