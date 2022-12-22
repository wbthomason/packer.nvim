local log = require 'packer.log'

local M = {}

local function command_complete(): {string}
  local actions = require('packer.actions') as {string:function}
  return vim.tbl_keys(actions)
end

-- Completion user plugins
-- Intended to provide completion for PackerUpdate/Sync/Install command
local function plugin_complete(lead: string, _: string): {string}
  local plugins = require 'packer.plugin'.plugins
  local completion_list = vim.tbl_filter(function(name: string): boolean
    return vim.startswith(name, lead)
  end, vim.tbl_keys(plugins))
  table.sort(completion_list)
  return completion_list
end

function M.complete(arglead: string, line: string): {string}
  local words = vim.split(line, '%s+')
  local n: integer = #words

  local matches: {string} = {}
  if n == 2 then
    matches = command_complete()
  elseif n > 2 then
    matches = plugin_complete(arglead)
  end
  return matches
end

function M.run(params: vim.api.UserCmdParams)
  local func = params.fargs[1]

  if not func then
    log.error('No subcommand provided')
  end

  local actions = require('packer.actions') as {string:function}

  local cmd_func = actions[func]
  if cmd_func then
    cmd_func()
    return
  end

  log.fmt_error('%s is not a valid function or action', func)
end

return M
