local util   = require 'packer.util'
local log    = require 'packer.log'
local config = require('packer.config')

local fmt = string.format

local record M
  type Loader = function(function()): boolean

  record UserSpec
    {string}

    branch     : string
    rev        : string
    tag        : string
    commit     : string
    lazy       : boolean
    start      : boolean
    keys       : string|{string|{string,string}}
    event      : string|{string}
    ft         : string|{string}
    cmd        : string|{string}
    cond       : boolean|Loader|{Loader}
    run        : string|function|{string|function}
    config_pre : string|function()
    config     : string|function()
    lock       : boolean
    requires   : string|{string|UserSpec}
  end

  record Plugin
    branch       : string
    rev          : string
    tag          : string
    commit       : string
    install_path : string
    keys         : {{string,string}}
    event        : {string}
    ft           : {string}
    cmd          : {string}
    cond         : boolean|Loader|{Loader}
    run          : {string|function}
    config_pre   : string|function()
    config       : string|function()
    requires     : {string}

    name         : string
    full_name    : string -- Includes rev and branch
    revs         : {string, string}
    required_by  : {string}

    enum Type
      'git'
      'local'
      'unknown'
    end

    type             : Type
    url              : string
    lock             : boolean
    breaking_commits : {string}

    -- Lazy loaded
    lazy: boolean

    -- Install as a 'start' plugin
    start: boolean

    loaded: boolean

    -- Built from a simple plugin spec (a string)
    simple: boolean

    messages: {string}
    err: {string}
  end

  plugins: {string:Plugin}
end

M.plugins = {}

local function guess_plugin_type(path: string): string, M.Plugin.Type
  if vim.fn.isdirectory(path) ~= 0 then
    return path, 'local'
  end

  if vim.startswith(path, 'git://')
    or vim.startswith(path, 'http')
    or path:match('@') as boolean then
    return path, 'git'
  end

  path = table.concat(vim.split(path, '\\', true), '/')
  return config.git.default_url_format:format(path), 'git'
end

local function get_plugin_name(text: string): string, string
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

local function get_plugin_full_name(name: string, user: M.UserSpec): string
  if user.branch then
    -- NOTE: maybe have to change the seperator here too
    name = name .. '/' .. user.branch
  end

  if user.rev then
    name = name .. '@' .. user.rev
  end

  return name
end

local function remove_ending_git_url(url: string): string
  return vim.endswith(url, '.git') and url:sub(1, -5) or url
end

local function normspec(x: string|M.UserSpec): M.UserSpec
  return x is string and { x } or x as M.UserSpec
end

local function normcond(x: string|{string}): {string}
  if x is string then
    return { x }
  end
  return x as {string}
end

local function normkeys(x: string|{string|{string,string}}): {{string,string}}
  if type(x) == 'string' then
    return {{ '', x as string }}
  end
  if x then
    local r: {{string,string}} = {}
    for _, v in ipairs(x as {string|{string,string}})do
      r[#r+1] = v is string and  { '', v } or v
    end
    return r
  end
end

local function normrun(x: string|function|{string|function}): {string|function}
  if x is function or x is string then
    return { x }
  end
  return x as {string|function}
end

--- The main logic for adding a plugin (and any dependencies) to the managed set
-- Can be invoked with (1) a single plugin spec as a string, (2) a single plugin spec table, or (3)
-- a list of plugin specs
function M.process_spec(
  spec0: string|M.UserSpec,
  required_by: M.Plugin
): {string:M.Plugin}
  local spec = normspec(spec0)

  if #spec > 1 then
    local r: {string:M.Plugin} = {}
    for _, s in ipairs(spec) do
      r = vim.tbl_extend('error', r, M.process_spec(s, required_by))
    end
    return r
  end

  local id = spec[1] as string
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
  local simple = spec0 is string

  if existing then
    if simple then
      log.debug('Ignoring simple plugin spec'..name)
      return {[name] = existing}
    else
      if not existing.simple then
        log.warn(fmt('Plugin "%s" is specified more than once!', name))
        return {[name] = existing}
      end
    end

    log.debug('Overriding simple plugin spec: '..name)
  end

  local url, ptype = guess_plugin_type(path)

  local plugin: M.Plugin = {
    name        = name,
    full_name   = get_plugin_full_name(name, spec),
    branch      = spec.branch,
    rev         = spec.rev,
    tag         = spec.tag,
    commit      = spec.commit,
    lazy        = spec.lazy,
    start       = spec.start,
    simple      = simple,
    keys        = normkeys(spec.keys),
    event       = normcond(spec.event),
    ft          = normcond(spec.ft   ),
    cmd         = normcond(spec.cmd  ),
    cond        = spec.cond ~= true and spec.cond or nil,  -- must be function or 'false'
    run         = normrun(spec.run),
    lock        = spec.lock,
    url         = remove_ending_git_url(url),
    type        = ptype,
    config_pre  = spec.config_pre,
    config      = spec.config,
    revs        = {},
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
    plugin.lazy = plugin.keys ~= nil
      or plugin.ft ~= nil
      or plugin.cmd ~= nil
      or plugin.event ~= nil
      or plugin.cond ~= nil
      or (required_by or {}).lazy
  end

  plugin.install_path = util.join_paths(plugin.start and config.start_dir or config.opt_dir, name)

  if spec.requires then
    local sr = spec.requires
    local r: {string|M.UserSpec} = sr is string and {sr} or  sr

    plugin.requires = {}
    for _, s in ipairs(r) do
      vim.list_extend(plugin.requires, vim.tbl_keys(M.process_spec(s, plugin)))
    end
  end

  return {[name] = plugin}
end

return M
