local log = require('packer.log')

local M = {}

local function command_complete()
   local actions = require('packer.actions')
   return vim.tbl_keys(actions)
end



local function plugin_complete(lead, _)
   local plugins = require('packer.plugin').plugins
   local completion_list = vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
   end, vim.tbl_keys(plugins))
   table.sort(completion_list)
   return completion_list
end

function M.complete(arglead, line)
   local words = vim.split(line, '%s+')
   local n = #words

   local matches = {}
   if n == 2 then
      matches = command_complete()
   elseif n > 2 then
      matches = plugin_complete(arglead)
   end
   return matches
end

function M.run(params)
   local func = params.fargs[1]

   if not func then
      log.error('No subcommand provided')
   end

   local actions = require('packer.actions')

   local cmd_func = actions[func]
   if cmd_func then
      cmd_func()
      return
   end

   log.fmt_error('%s is not a valid function or action', func)
end

return M