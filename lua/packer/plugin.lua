local util = require('packer.util')
local log = require('packer.log')
local config = require('packer.config')

local fmt = string.format













local M = {Plugin = {}, }












































local function guess_plugin_type(path)
   if vim.fn.isdirectory(path) ~= 0 then
      return path, 'local'
   end

   if vim.startswith(path, 'git://') or
      vim.startswith(path, 'http') or
      path:match('@') then
      return path, 'git'
   end

   path = table.concat(vim.split(path, '\\', true), '/')
   return config.git.default_url_format:format(path), 'git'
end

local function get_plugin_name(text)
   local path = vim.fn.expand(text)
   local name_segments = vim.split(path, util.get_separator())
   local segment_idx = #name_segments
   local name = name_segments[segment_idx]
   while name == '' and segment_idx > 0 do
      name = name_segments[segment_idx]
      segment_idx = segment_idx - 1
   end
   return name, path
end

local function get_plugin_full_name(plugin)
   local plugin_name = plugin.name
   if plugin.branch then

      plugin_name = plugin_name .. '/' .. plugin.branch
   end

   if plugin.rev then
      plugin_name = plugin_name .. '@' .. plugin.rev
   end

   return plugin_name
end

local function remove_ending_git_url(url)
   return vim.endswith(url, '.git') and url:sub(1, -5) or url
end





local function process_spec(plugin_data, plugins)
   local spec = plugin_data.spec
   local spec_line = plugin_data.line

   local speclist = spec
   if type(speclist) == 'table' and #speclist > 1 then
      for _, s in ipairs(speclist) do
         process_spec({ line = spec_line, spec = s }, plugins)
      end
      return
   end

   if type(spec) == 'string' then
      spec = { spec }
   end

   local spec0 = spec[1]
   spec[1] = nil

   if spec0 == nil then
      log.warn(fmt('No plugin name provided at line %s!', spec_line))
      return
   end

   local name, path = get_plugin_name(spec0)

   if name == '' then
      log.warn(fmt('"%s" is an invalid plugin name!', spec0))
      return
   end

   if plugins[name] and not plugins[name].from_requires then
      log.warn(fmt('Plugin "%s" is used twice! (line %s)', name, spec_line))
      return
   end


   spec.name = name
   spec.full_name = get_plugin_full_name(spec)

   local manual_opt = spec.opt

   if spec.keys ~= nil or
      spec.ft ~= nil or
      spec.cmd ~= nil or
      spec.event ~= nil or
      spec.cond ~= nil then
      spec.opt = true
   end


   for _, field in ipairs({ 'cmd', 'ft', 'event', 'run' }) do
      local v = (spec)[field]
      if v and type(v) ~= 'table' then
         (spec)[field] = { v }
      end
   end


   if type(spec.keys) == 'string' then
      spec.keys = { { '', spec.keys } }
   elseif type(spec.keys) == 'table' then
      for i, v in ipairs(spec.keys) do
         if type(v) == 'string' then
            spec.keys[i] = { '', v }
         end
      end
   end

   spec.install_path = util.join_paths(spec.opt and config.opt_dir or config.start_dir, name)

   spec.loaded = not spec.opt and vim.loop.fs_stat(spec.install_path) ~= nil

   spec.url, spec.type = guess_plugin_type(path)


   spec.url = remove_ending_git_url(spec.url)
   spec.revs = {}

   plugins[name] = spec

   if spec.requires then

      if type(spec.requires) == 'string' or (
         type(spec.requires) == 'table' and
         not vim.tbl_islist(spec.requires) and
         #spec.requires == 1) then

         spec.requires = { spec.requires }
      end

      for _, req in ipairs(spec.requires) do
         if type(req) == 'string' then
            req = { req }
         end

         local req_name_segments = vim.split(req[1], '/')
         local req_name = req_name_segments[#req_name_segments]




         req.from_requires = true
         if not plugins[req_name] then
            if manual_opt then
               req.opt = true
            end

            process_spec({ spec = req, line = spec_line }, plugins)
         end
      end
   end
end

function M.process_spec(spec)
   local plugins = {}
   process_spec(spec, plugins)
   return plugins
end

return M