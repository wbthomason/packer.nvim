local util = require('packer.util')
local log = require('packer.log')
local config = require('packer.config')

local fmt = string.format

local M = {UserSpec = {}, Plugin = {}, }


























































M.plugins = {}

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

local function get_plugin_full_name(name, user)
   if user.branch then

      name = name .. '/' .. user.branch
   end

   if user.rev then
      name = name .. '@' .. user.rev
   end

   return name
end

local function remove_ending_git_url(url)
   return vim.endswith(url, '.git') and url:sub(1, -5) or url
end

local function normspec(x)
   return type(x) == "string" and { x } or x
end

local function normcond(x)
   if type(x) == "string" then
      return { x }
   end
   return x
end

local function normkeys(x)
   if type(x) == "string" then
      return { { '', x } }
   end
   return x
end

local function normrun(x)
   if type(x) == "function" or type(x) == "string" then
      return { x }
   end
   return x
end




function M.process_spec(
   spec0,
   required_by)

   local spec = normspec(spec0)

   if #spec > 1 then
      local r = {}
      for _, s in ipairs(spec) do
         r = vim.tbl_extend('error', r, M.process_spec(s, required_by))
      end
      return r
   end

   local id = spec[1]
   spec[1] = nil

   if id == nil then
      log.warn('No plugin name provided!')
      return {}
   end

   local name, path = get_plugin_name(id)

   if name == '' then
      log.warn(fmt('"%s" is an invalid plugin name!', id))
      return {}
   end

   if M.plugins[name] then
      if required_by then
         M.plugins[name].required_by = M.plugins[name].required_by or {}
         table.insert(M.plugins[name].required_by, required_by.name)
      else
         log.warn(fmt('Plugin "%s" is specified more than once!', name))
      end

      return { [name] = M.plugins[name] }
   end

   local url, ptype = guess_plugin_type(path)

   local plugin = {
      name = name,
      full_name = get_plugin_full_name(name, spec),
      branch = spec.branch,
      rev = spec.rev,
      tag = spec.tag,
      commit = spec.commit,
      keys = normkeys(spec.keys),
      event = normcond(spec.event),
      ft = normcond(spec.ft),
      cmd = normcond(spec.cmd),
      enable = spec.enable ~= true and spec.enable or nil,
      run = normrun(spec.run),
      lock = spec.lock,
      url = remove_ending_git_url(url),
      type = ptype,
      config = spec.config,
      required_by = required_by and { required_by.name } or nil,
      revs = {},
   }

   M.plugins[name] = plugin

   if plugin.opt == nil then
      plugin.opt = plugin.keys ~= nil or
      plugin.ft ~= nil or
      plugin.cmd ~= nil or
      plugin.event ~= nil or
      plugin.enable ~= nil or
      (required_by or {}).opt
   end

   plugin.install_path = util.join_paths(plugin.opt and config.opt_dir or config.start_dir, name)

   if spec.requires then
      if required_by then
         log.warn(fmt('(%s) Nested requires are not support', name))
      else
         local sr = spec.requires
         local r = type(sr) == "string" and { sr } or sr


         plugin.requires = {}
         for _, s in ipairs(r) do
            vim.list_extend(plugin.requires, vim.tbl_keys(M.process_spec(s, plugin)))
         end
      end
   end

   return { [name] = plugin }
end

return M