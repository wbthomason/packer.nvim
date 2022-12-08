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
   if type(x) == 'string' then
      return { { '', x } }
   end
   if x then
      local r = {}
      for _, v in ipairs(x) do
         r[#r + 1] = type(v) == "string" and { '', v } or v
      end
      return r
   end
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
      log.debug('No plugin name provided for spec', spec)
      return {}
   end

   local name, path = get_plugin_name(id)

   if name == '' then
      log.warn(fmt('"%s" is an invalid plugin name!', id))
      return {}
   end

   local existing = M.plugins[name]
   local simple = type(spec0) == "string"

   if existing then
      if simple then
         log.debug('Ignoring simple plugin spec' .. name)
         return { [name] = existing }
      else
         if not existing.simple then
            log.warn(fmt('Plugin "%s" is specified more than once!', name))
            return { [name] = existing }
         end
      end

      log.debug('Overriding simple plugin spec: ' .. name)
   end

   local url, ptype = guess_plugin_type(path)

   local plugin = {
      name = name,
      full_name = get_plugin_full_name(name, spec),
      branch = spec.branch,
      rev = spec.rev,
      tag = spec.tag,
      commit = spec.commit,
      lazy = spec.lazy,
      start = spec.start,
      simple = simple,
      keys = normkeys(spec.keys),
      event = normcond(spec.event),
      ft = normcond(spec.ft),
      cmd = normcond(spec.cmd),
      cond = spec.cond ~= true and spec.cond or nil,
      run = normrun(spec.run),
      lock = spec.lock,
      url = remove_ending_git_url(url),
      type = ptype,
      config_pre = spec.config_pre,
      config = spec.config,
      revs = {},
   }

   if required_by then
      plugin.required_by = plugin.required_by or {}
      table.insert(plugin.required_by, required_by.name)
   end

   if existing and existing.required_by then
      plugin.required_by = plugin.required_by or {}
      vim.list_extend(plugin.required_by, existing.required_by)
   end

   M.plugins[name] = plugin

   if not plugin.lazy then
      plugin.lazy = plugin.keys ~= nil or
      plugin.ft ~= nil or
      plugin.cmd ~= nil or
      plugin.event ~= nil or
      plugin.cond ~= nil or
      (required_by or {}).lazy
   end

   plugin.install_path = util.join_paths(plugin.start and config.start_dir or config.opt_dir, name)

   if spec.requires then
      local sr = spec.requires
      local r = type(sr) == "string" and { sr } or sr

      plugin.requires = {}
      for _, s in ipairs(r) do
         vim.list_extend(plugin.requires, vim.tbl_keys(M.process_spec(s, plugin)))
      end
   end

   return { [name] = plugin }
end

return M