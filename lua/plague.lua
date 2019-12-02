-- TODO: Make OS independent
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
  source_dir = '~/.local/share/nvim/plague',
  package_root = '~/.config/nvim/pack',
  plugin_package = '~/.config/nvim/pack/plugins',
  threads = nil,
  auto_clean = false,
}

plague.fns = {}

plague.threads = {}

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

local function each(func, iter, state, init)
  local key = iter(state, init)
  repeat
    if key ~= nil then
      func(key, state[key])
      key = iter(state, key)
    end
  until key == nil
end

local function filter(func, iter, state, init)
  local result = {}
  local key = iter(state, init)
  while key ~= nil do
    if func(key, state[key]) then
      result[key] = state[key]
    end
    key = iter(state, key)
  end

  return result
end

-- Coroutine stuff
local function schedule(work, after)
  table.insert(plague.threads,
    {work = coroutine.create(work), after = after, val = nil, status = true})
end

local function run_threads()
  local thread_capacity = plague.config.threads or 8
  local front_idx = 1
  while front_idx <= #plague.threads do
    for i=front_idx, math.min(front_idx + thread_capacity, #plague.threads) do
      local thread_obj = plague.threads[i]
      if coroutine.status(thread_obj.work) == "dead" then
        thread_obj.after(thread_obj.val)
        front_idx = front_idx + 1
        thread_capacity = thread_capacity + 1
      else
        thread_capacity = thread_capacity - 1
        -- TODO: Error checks
        thread_obj.status, thread_obj.val = coroutine.resume(thread_obj.work)
      end
    end
  end
end

plague.fns.err = function (msg)
  nvim.nvim_err_writeln('[Plague] ' .. msg)
end

plague.fns.echo = function (msg)
  nvim.nvim_out_write('[Plague] ' .. msg .. '\n')
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

local function dir(path)
  local lines = {}
  for s in string.gmatch(nvim.nvim_eval('globpath("' .. path .. '", "*")'), "[^\r\n]+") do
    table.insert(lines, s)
  end

  return lines
end

-- Plugin specification functions
plague.fns.configure = function (config)
  for config_var, config_val in pairs(config) do
    plague.config[config_var] = config_val
  end
end

plague.fns.check_config = function ()
  if plague.config.source_dir == nil then
    if nvim_vars.source_dir then
      plague.config.source_dir = nvim_vars.source_dir
    elseif #nvim.nvim_list_runtime_paths() > 0 then
      plague.config.source_dir = nvim.nvim_list_runtime_paths()[1] .. '/plague'
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
  return function()
    plague.fns.echo("Installing " .. spec.name)
    -- TODO: Failure/error checks
    local path = concat(plague.config.source_dir, spec.name)
    os.execute('mkdir -p ' .. path)
    if spec.type == 'local' then
      os.execute('ln -s ' .. spec[1] .. ' ' .. path)
    elseif spec.type == 'git' then
      local ph = io.popen('git clone ' .. spec[1] .. ' ' .. path .. ' 2>&1', 'r')
      while ph:read('*a') ~= '' do
        coroutine.yield('Cloning...')
      end
      ph:close()
      plague.fns.handle_branch_rev(spec)
    elseif spec.type == 'github' then
      local ph = io.popen('git clone https://github.com/' .. spec[1] .. ' ' .. path .. ' 2>&1', 'r')
      while ph:read('*a') ~= '' do
        coroutine.yield('Cloning...')
      end
      ph:close()
      plague.fns.handle_branch_rev(spec)
    end
    return 'Installation complete!'
  end
end

plague.fns.handle_branch_rev = function(spec)
  local path = concat(plague.config.source_dir, spec.name)
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
  local path = concat(plague.config.source_dir, plug_name)
  if spec.type == 'local' then os.remove(path)
  else os.execute('rm -rf ' .. path) end
end

plague.fns.disable = function(spec)
  local pack_path = concat(plague.config.package_root, spec.name)
  if spec.defer then
    pack_path = concat(pack_path, 'opt')
  else
    pack_path = concat(pack_path, 'start')
  end

  os.execute('rm -f ' .. pack_path)
end

plague.fns.enable = function(spec)
  local pack_path = plague.config.plugin_package
  local plug_path = concat(plague.config.source_dir, spec.name)
  if spec.defer then
    pack_path = concat(pack_path, 'opt')
  else
    pack_path = concat(pack_path, 'start')
  end

  os.execute('mkdir -p ' .. pack_path)
  os.execute('mv ' .. plug_path .. ' ' .. pack_path)
end

plague.fns.status = function(spec)
  return function(status)
    plague.fns.echo(spec.name .. ': ' .. status)
  end
end

plague.fns.check_install = function(name, spec, installed_plugins)
  if index(name, ipairs(installed_plugins)) == nil then
    schedule(plague.fns.install(spec), plague.fns.status(spec))
  end
end

plague.fns.list_packages = function()
  local result = {}
  for _, v in ipairs(dir(plague.config.source_dir)) do
    table.insert(result, string.match(v, '[^/]-$'))
  end
  return result
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

  -- Ensure plugin dir and package dir
  os.execute('mkdir -p ' .. plague.config.source_dir)
  os.execute('mkdir -p ' .. plague.config.plugin_package)

  -- Setup plugin infrastructure
  plague.triggers = {
    functions = {},
    commands = {},
    filetypes = {},
    events = {},
  }

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
    plague.fns.check_install(name, spec, installed_plugins)
  end

  -- each(curried_install, pairs(filter(function (_, spec) return spec.ensure end, pairs(enabled_plugins))))
  each(curried_install, pairs(enabled_plugins))
  run_threads()
  -- each(function (_, spec) plague.fns.enable(spec) end, pairs(enabled_plugins))

  -- Remove uninstalled plugins
  if plague.config.auto_clean then
    each(plague.fns.uninstall,
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

  plague.plugins = plague.plugins or {}

  plague.plugins[name] = spec
end

return { use = plague.fns.use, sync = plague.fns.sync, configure = plague.fns.configure }
