-- Dependencies
local uv = require('luv')

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
}

plague.fns = {}

plague.plugins = nil

-- Function definitions
-- Utility functions
plague.fns.err = function (msg)
  nvim.nvim_err_writeln("[Plague] " .. msg)
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
    plague.fns.err("Register plugins with use_plugin first!")
    return false
  end

  -- Setup plugin infrastructure
  plague.triggers = {
    functions = {},
    commands = {},
    filetypes = {},
    events = {},
  }

  local ctx = uv.new_work(
    function(n) --work,in threadpool
        local uv = require('luv')
        local t = uv.thread_self()
        uv.sleep(100)
        return n*n,n 
    end, 
    function(r,n) print(string.format('%d => %d',n,r)) end    --after work, in loop thread
)

  -- Iterate through the plugins and handle installation
  for plug_name, spec in pairs(plague.plugins) do
    if spec.ensure then
      plague.fns.check_install(plug_name, spec)
    end
  end
end

plague.fns.use_plugin = function (spec)
end
