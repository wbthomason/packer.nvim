local log    = require 'packer.log'
local config = require 'packer.config'
local plugin = require 'packer.plugin'
local loader = require 'packer.loader'

local UserSpec = plugin.UserSpec

local Config = config.Config

local did_setup = false

local function setup(user_config: Config)
  log.debug('setup')

  config(user_config)

  for _, dir in ipairs{config.opt_dir, config.start_dir} do
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
    end
  end

  did_setup = true
end

local M = {}

function M.add(spec: UserSpec)
  if not did_setup then
    setup()
  end

  log.debug('PROCESSING PLUGIN SPEC')
  plugin.process_spec(spec)

  log.debug('LOADING PLUGINS')
  loader.setup(plugin.plugins)
end

-- This should be safe to call multiple times.
function M.setup(user_config: Config, user_spec: UserSpec)
  setup(user_config)

  if user_spec then
    M.add(user_spec)
  end
end

-- @deprecated use setup() instead
-- Convenience function for simple setup
-- spec can be a table with a table of plugin specifications as its first
-- element, config overrides as another element.
function M.startup(spec: table)
  log.debug('STARTING')
  assert(type(spec) == 'table')

  local user_spec = spec[1] as UserSpec
  assert(user_spec is UserSpec)

  M.setup(spec.config as Config)
  M.add(user_spec)
end

return M
