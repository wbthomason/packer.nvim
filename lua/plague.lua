-- Dependencies
local uv = require('luv')
local p = require('paths')

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
  plugin_dir = '~/.local/share/nvim/plague',
  package_dir = '~/.local/share/nvim/pack',
  threads = nil,
  auto_clean = false,
}

plague.fns = {}

plague.plugins = nil

-- Function definitions
-- Utility functions
local function index(val, iter, state, key)
  repeat
    if state[key] == val then
      return key
    end

    key = iter(state, key)
  until key == nil

  return nil
end

local function each(func, iter, state, key)
  repeat
    if key ~= nil then
      key = func(key, iter(state, key)) or key
    end
  until key == nil
end

local function filter(func, iter, state, init)
  local result = {}
  local key = iter(state, init)
  while key ~= nil do
    if func(key, state[key]) then
      table.insert(result, state[key])
    end
    key = iter(state, key)
  end

  return result
end

plague.fns.err = function (msg)
  nvim.nvim_err_writeln("[Plague] " .. msg)
end

plague.fns.echo = function (msg)
  nvim.nvim_out_write("[Plague] " .. msg .. "\n")
end

local concat = function(...)
  -- TODO: Make OS independent
  local result = ''
  local arg = {...}
  for _, v in ipairs(arg) do
    result = result .. '/' .. v
  end

  return string.sub(result, 2)
end

-- Plugin specification functions
plague.fns.configure = function (config)
  for config_var, config_val in pairs(config) do
    plague.config[config_var] = config_val
  end
end

plague.fns.check_config = function ()
  if plague.config.plugin_dir == nil then
    if nvim_vars.plugin_dir then
      plague.config.plugin_dir = nvim_vars.plugin_dir
    elseif #nvim.nvim_list_runtime_paths() > 0 then
      plague.config.plugin_dir = nvim.nvim_list_runtime_paths()[1] .. '/plugins'
    else
      plague.fns.err("Please set the plugin directory!")
      return false
    end
  end

  for idx, val in pairs(plague.config) do
    if val == nil then
      if nvim_vars[idx] then plague.config[idx] = nvim_vars[idx]
      else
        plague.fns.err("Please set the config variable " .. idx)
        return false
      end
    end
  end
  return true
end

plague.fns.install = function(spec)
  -- TODO: Failure/error checks
  local path = concat(plague.config.plugin_dir, spec.name)
  if spec.type == 'local' then
    -- TODO: Make OS independent
    os.execute('ln -s ' .. spec[1] .. ' ' .. path)
  elseif spec.type == 'git' then
    os.execute('git clone ' .. spec[1] .. ' ' .. path)
    plague.fns.handle_branch_rev(spec)
  elseif spec.type == 'github' then
    os.execute('git clone https://github.com/' .. spec[1] .. ' ' .. path)
    plague.fns.handle_branch_rev(spec)
  end
end

plague.fns.handle_branch_rev = function(spec)
  local path = concat(plague.config.plugin_dir, spec.name)
  if spec.branch then
    os.execute('cd ' .. path .. ' && git checkout ' .. spec.branch)
  end

  if spec.commit then
    os.execute('cd ' .. path .. ' && git checkout ' .. spec.commit)
  end

  if spec.tag then
    os.execute('cd ' .. path .. ' && git checkout ' .. spec.tag)
  end
end

plague.fns.uninstall = function(plug_name)
  local spec = plague.plugins[plug_name]
  local path = concat(plague.config.plugin_dir, plug_name)
  if spec.type == 'local' then os.remove(path)
  else p.rmall(path, 'yes') end
end

plague.fns.enable = function(spec)
  local plug_path = concat(plague.config.plugin_dir, spec.name)
  local pack_path = concat(plague.config.package_dir, spec.name)
  -- TODO: OS independence
  if spec.defer then
    os.execute('ln -s ' .. plug_path .. ' ' .. concat(pack_path, 'opt'))
  else
    print('ln -s ' .. plug_path .. ' ' .. concat(pack_path, 'start'))
    os.execute('ln -s ' .. plug_path .. ' ' .. concat(pack_path, 'start'))
  end
end

plague.fns.disable = function(spec)
  local pack_path = concat(plague.config.package_dir, spec.name)
  if spec.defer then
    pack_path = concat(pack_path, 'opt')
  else
    pack_path = concat(pack_path, 'start')
  end

  -- TODO: OS independence
  os.execute('rm -f ' .. pack_path)
end

plague.fns.check_install = function(name, spec, context, installed_plugins)
  if index(name, ipairs(installed_plugins)) == nil then
    uv.queue_work(context, name, spec)
  end
end

plague.fns.list_packages = function()
  return p.dir(plague.config.plugin_dir)
end

plague.fns.gather_hooks = function(spec)
end

plague.fns.set_triggers = function()
end

plague.fns.guess_type = function(spec)
  -- A series of heuristics to guess the type of a plugin
  -- TODO: Add more plugin types later once more installation methods are supported
  if spec.type then return end

  local plugin = spec[1]
  if string.sub(plugin, 1, 1) == '/' then
    spec.type = 'local'
    return
  end

  if string.sub(plugin, 1, 5) == 'https'
    or string.sub(plugin, 1, 3) == 'ssh'
    or string.sub(plugin, 1, 3) == 'git' then
    spec.type = 'git'
    return
  end

  if string.match(plugin, '/') then
    spec.type = 'github'
    return
  end

  spec.type = 'unknown'
end

plague.fns.sync = function ()
  -- Check basic config
  if not plague.fns.check_config then return false end

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

  local installed_plugins = plague.fns.list_packages()

  -- TODO: Dependency sorting
  -- TODO: Before/after config
  -- Filter out disabled and enabled plugins
  local disabled_plugins = filter(function(_, spec) return spec.disabled end, pairs(plague.plugins))
  local enabled_plugins = filter(function(_, spec) return not spec.disabled end, pairs(plague.plugins))

  -- Disable the disabled plugins
  each(function (_, spec) plague.fns.disable(spec) end, pairs(disabled_plugins))

  -- Install enabled but missing plugins
  local curried_install = function(name, spec)
    plague.fns.check_install(name, spec, installed_plugins, in_ctx)
  end

  each(curried_install, pairs(filter(function (_, spec) return spec.ensure end, pairs(enabled_plugins))))
  each(function (spec) plague.fns.enable(spec) end, pairs(enabled_plugins))

  -- Remove uninstalled plugins
  if plague.config.auto_clean then
    each(function (plug_name, spec) uv.queue_work(un_ctx, plug_name, spec) end,
      pairs(filter(function(_, plug_name) return plague.plugins[plug_name] end, pairs(installed_plugins))))
  end

  -- Collect hooks
  local deferred_plugins = filter(function(_, spec) return spec.defer end, pairs(enabled_plugins))
  each(plague.fns.gather_hooks, pairs(deferred_plugins))

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

  if plague.plugins == nil then plague.plugins = {} end

  plague.plugins[name] = spec
end

return { use = plague.fns.use, sync = plague.fns.sync, configure = plague.fns.configure }
