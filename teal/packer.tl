local config = require 'packer.config'

local Config = config.Config

local M = {}

local function apply_config(plugin: Plugin)
  if plugin.config then
    local c = plugin.config
    if c is function() then
      c()
    else
      loadstring(c, plugin.name..'.config()')()
    end
  end
end

local function loader(plugins: {Plugin})
  for _, plugin in ipairs(plugins) do
    if not plugin.loaded then
      -- Set the plugin as loaded before config is run in case something in the
      -- config tries to load this same plugin again
      plugin.loaded = true
      if plugin.opt then
        -- never packadd a start plugin
        vim.cmd.packadd(plugin.name)
      end
      apply_config(plugin)
    end
  end
end

-- Completion user plugins
-- Intended to provide completion for PackerUpdate/Sync/Install command
local function plugin_complete(lead: string, _:string): {string}
  local plugins = require 'packer.plugin'.plugins
  local completion_list = vim.tbl_filter(function(name: string): boolean
    return vim.startswith(name, lead)
  end, vim.tbl_keys(plugins))
  table.sort(completion_list)
  return completion_list
end

local function load_plugin_configs(plugins: {string:Plugin})
  local Handlers = require('packer.handlers')

  for _, plugin in pairs(plugins) do
    if not plugin.opt then
      loader({plugin})
    end
  end

  for _, cond in ipairs(Handlers.types) do
    Handlers[cond](plugins, loader)
  end
end

local function make_commands()
  local actions = setmetatable({}, {
    __index = function(_, k: string): function
      return function(...:any): any...
        return (require'packer.actions' as {string:function})[k](...)
      end
    end
  }) as {string:function}

  for _, cmd in ipairs {
    { 'PackerInstall', '*', actions.install , plugin_complete},
    { 'PackerUpdate' , '*', actions.update  , plugin_complete},
    { 'PackerSync'   , '*', actions.sync                     },
    { 'PackerClean'  , '*', actions.clean                    },
    { 'PackerStatus' , '*', actions.status                   },
  } do
    vim.api.nvim_create_user_command(cmd[1], function(args: vim.api.UserCmdParams)
      cmd[3](unpack(args.fargs))
    end, { nargs = cmd[2], complete = cmd[4] })
  end
end

local record SSpec
  {UserSpec}

  config: Config
end

-- Convenience function for simple setup
-- spec can be a table with a table of plugin specifications as its first
-- element, config overrides as another element.
function M.startup(spec: SSpec)
  assert(type(spec) == 'table')
  assert(type(spec[1]) == 'table')

  config(spec.config)

  for _, dir in ipairs{config.opt_dir, config.start_dir} do
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
    end
  end

  make_commands()

  local plugin = require 'packer.plugin'

  plugin.process_spec(spec[1])

  load_plugin_configs(plugin.plugins)
end

return M
