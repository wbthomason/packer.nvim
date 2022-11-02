local a = require('packer.async')
local util = require('packer.util')
local log = require('packer.log')
local plugin_utils = require('packer.plugin_utils')
local async = a.sync
local fmt = string.format
local uv = vim.loop

local config = require('packer.config')

local M = {SResult = {Completed = {}, }, Completion = {}, }




















M.completion = {}



M.completion.snapshot = function(lead, _, _)
   local completion_list = {}
   if config.snapshot_path == nil then
      return completion_list
   end

   local dir = uv.fs_opendir(config.snapshot_path)

   if dir ~= nil then
      local res = uv.fs_readdir(dir)
      while res ~= nil do
         for _, entry in ipairs(res) do
            if entry.type == 'file' and vim.startswith(entry.name, lead) then
               completion_list[#completion_list + 1] = entry.name
            end
         end

         res = uv.fs_readdir(dir)
      end
   end

   dir:closedir()
   return completion_list
end



local function plugin_complete(lead, _, _)
   local completion_list = vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
   end, vim.tbl_keys(_G.packer_plugins))
   table.sort(completion_list)
   return completion_list
end



M.completion.create = function(lead, cmdline, pos)
   local cmd_args = (vim.split(cmdline, '%s+'))

   if #cmd_args > 1 then
      return plugin_complete(lead, cmdline, pos)
   end

   return {}
end




M.completion.rollback = function(lead, cmdline, pos)
   local cmd_args = vim.split(cmdline, ' ')

   if #cmd_args > 2 then
      return plugin_complete(lead)
   else
      return M.completion.snapshot(lead, cmdline, pos)
   end
end


local generate_snapshot = async(function(plugins)
   local completed = {}
   local failed = {}
   local opt, start = plugin_utils.list_installed_plugins()
   local installed = vim.tbl_extend('error', start, opt)

   plugins = vim.tbl_filter(function(plugin)
      if installed[plugin.install_path] and plugin.type == 'git' then
         return true
      end
      return false
   end, plugins)

   for _, plugin in pairs(plugins) do
      local plugin_type = require('packer.plugin_types')[plugin.type]
      local rev, err = plugin_type.get_rev(plugin)

      if err then
         failed[plugin.name] = 
         fmt("Snapshotting %s failed because of error '%s'", plugin.name, err)
      else
         completed[plugin.name] = { commit = rev }
      end
   end

   return { failed = failed, completed = completed }
end, 1)






M.create = async(function(snapshot_path, plugins)
   assert(type(snapshot_path) == 'string', fmt("filename needs to be a string but '%s' provided", type(snapshot_path)))
   assert(type(plugins) == 'table', fmt("plugins needs to be an array but '%s' provided", type(plugins)))
   local commits = generate_snapshot(plugins)

   a.main()

   local snapshot_content = vim.json.encode(commits.completed)

   local status, res = pcall(function()
      return vim.fn.writefile({ snapshot_content }, snapshot_path) == 0
   end)

   if status and res then
      return {
         message = fmt("Snapshot '%s' complete", snapshot_path),
         completed = commits.completed,
         failed = commits.failed,
      }
   else
      return {
         err = true,
         message = fmt("Error on creation of snapshot '%s': '%s'", snapshot_path, res),
      }
   end
end, 2)



M.rollback = async(function(_snapshot_path, _plugins)
   return { message = 'Not implemented' }












































end, 2)


function M.delete(snapshot_name)
   assert(type(snapshot_name) == 'string', fmt('Expected string, got %s', type(snapshot_name)))
   local snapshot_path = uv.fs_realpath(snapshot_name) or
   uv.fs_realpath(util.join_paths(config.snapshot_path, snapshot_name))

   if snapshot_path == nil then
      log.warn(fmt("Snapshot '%s' is wrong or doesn't exist", snapshot_name))
      return
   end

   log.debug('Deleting ' .. snapshot_path)
   if uv.fs_unlink(snapshot_path) then
      log.info('Deleted ' .. snapshot_path)
   else
      log.warn("Couldn't delete " .. snapshot_path)
   end
end

return M