local a      = require 'packer.async'
local config = require 'packer.config'
local jobs   = require 'packer.jobs'
local log    = require 'packer.log'
local util   = require 'packer.util'
local Display = require 'packer.display'.Display
local Plugin = require'packer.plugin'.Plugin

local async = a.sync

local fmt = string.format

local record M
  installer   : function(Plugin, Display): {string}
  updater     : function(Plugin, Display, opts: table): {string}
  revert_last : function(Plugin): {string}
  revert_to   : function(Plugin, commit: string): {string}
  remote_url  : function(Plugin): string
  diff        : function(Plugin, commit: string, callback: function): {string}
  get_rev     : function(Plugin): string, string
end

local job_env: {string} = {}

do
  local blocked_env_vars: {string:boolean} = {
    GIT_DIR = true,
    GIT_INDEX_FILE = true,
    GIT_OBJECT_DIRECTORY = true,
    GIT_TERMINAL_PROMPT = true,
    GIT_WORK_TREE = true,
    GIT_COMMON_DIR = true,
  }

  for k, v in pairs(vim.fn.environ()) do
    if not blocked_env_vars[k] then
      job_env[#job_env+1] = k .. '=' .. v
    end
  end

  job_env[#job_env+1] = 'GIT_TERMINAL_PROMPT=0'
end

local function has_wildcard(tag: string): boolean
  return tag and tag:match('*') ~= nil
end

local BREAK_TAG_PAT          = '[[bB][rR][eE][aA][kK]!?:]'
local BREAKING_CHANGE_PAT    = '[[bB][rR][eE][aA][kK][iI][nN][gG][ _][cC][hH][aA][nN][gG][eE]]'
local TYPE_EXCLAIM_PAT       = '[[a-zA-Z]+!:]'
local TYPE_SCOPE_EXPLAIN_PAT = '[[a-zA-Z]+%([^)]+%)!:]'

local function is_breaking(x: string): boolean
    return x and (
      x:match(BREAKING_CHANGE_PAT)
      or x:match(BREAK_TAG_PAT)
      or x:match(TYPE_EXCLAIM_PAT)
      or x:match(TYPE_SCOPE_EXPLAIN_PAT)
    ) ~= nil
end

local function get_breaking_commits(commit_bodies: {string}): {string}
  local ret = {}
  local commits = vim.gsplit(table.concat(commit_bodies, '\n'), '===COMMIT_START===', true)

  for commit in commits do
    local commit_parts = vim.split(commit, '===BODY_START===')
    local body = commit_parts[2]
    local lines = vim.split(commit_parts[1], '\n')
    if is_breaking(body) or is_breaking(lines[2]) then
      ret[#ret+1] = lines[1]
    end
  end
  return ret
end

local function git_run(args: {string}, opts: jobs.Opts): boolean, {string}
  opts = opts or {}
  opts.env = opts.env or job_env
  local jr = jobs.run({ config.git.cmd, unpack(args) }, opts)
  local ok = jr.exit_code == 0
  if ok then
    return true, jr.stdout
  end
  return true, jr.stderr
end

local git_version: {integer, integer, integer}

local function parse_version(version: string): {integer, integer, integer}
  assert(version:match('%d+%.%d+%.%w+'), 'Invalid git version: '..version)
  local parts = vim.split(version, '%.')
  local ret = {}
  ret[1] = tonumber(parts[1]) as integer
  ret[2] = tonumber(parts[2]) as integer

  if parts[3] == 'GIT' then
    ret[3] = 0
  else
    ret[3] = tonumber(parts[3]) as integer
  end

  return ret
end

--- @async
local function set_version()
  if git_version then
    return
  end

  local vok, out = git_run{'--version'}
  if vok then
    local line = out[1]
    local ok, err = pcall(function(): any
      assert(vim.startswith(line, 'git version'), 'Unexpected output: '..line)
      local parts = vim.split(line, '%s+')
      git_version = parse_version(parts[3])
    end)
    if not ok then
      log.error(err)
      return
    end
  end
end

--- @async
local function check_version(version: {integer,integer,integer}): boolean
  set_version()

  if not git_version then
    return false
  end

  if git_version[1] < version[1] then
    return false
  end

  if version[2] and git_version[2] < version[2] then
    return false
  end

  if version[3] and git_version[3] < version[3] then
    return false
  end

  return true
end

local function get_ref(plugin: Plugin, ...: string): string
  local lines = util.file_lines(util.join_paths(plugin.install_path, '.git', ...))
  if lines then
    return lines[1]
  end
end

---@async
local function get_current_branch(plugin: Plugin): string
  -- first try local HEAD
  local remote_head = get_ref(plugin, 'refs', 'remotes', 'origin', 'HEAD')
  if remote_head then
    local branch = remote_head:match('^ref: refs/remotes/origin/(.*)')
    if branch then
      return branch
    end
  end
end

local function resolve_tag(plugin: Plugin): string, {string}
  local tag = plugin.tag
  local ok, out = git_run({
    'tag', '-l', tag,
    '--sort', '-version:refname'
  }, {
    cwd = plugin.install_path
  })

  if ok then
    tag = vim.split(out[#out], '\n')[1]
    return tag
  end

  log.fmt_warn(
    'Wildcard expansion did not find any tag for plugin %s: defaulting to latest commit...',
    plugin.name
  )
  tag = nil -- Wildcard is not found, then we bypass the tag
  return nil, out
end

---@async
local function checkout(plugin: Plugin, disp: Display): boolean, {string}
  local function update_disp(msg: string)
    if disp then
      disp:task_update(plugin.full_name, msg)
    end
  end

  update_disp('fetching reference...')

  local tag = plugin.tag

  -- Resolve tag
  if tag and has_wildcard(tag) then
    update_disp(fmt('getting tag for wildcard %s...', tag))
    local tagerr: {string}
    tag, tagerr = resolve_tag(plugin)
    if not tag then
      return false, tagerr
    end
  end

  local target: string
  if plugin.commit then
    target = plugin.commit
  elseif tag then
    target = 'tags/'..tag
  else
    local branch = plugin.branch or get_current_branch(plugin)
    target = get_ref(plugin, 'refs', 'remotes', 'origin', branch)
          or get_ref(plugin, 'refs', 'heads', branch)
  end

  return git_run({ 'checkout', '--progress', target }, { cwd = plugin.install_path })
end

local function split_messages(messages: {string}): {string}
  local lines = {}
  for _, message in ipairs(messages) do
    vim.list_extend(lines, vim.split(message, '\n'))
    table.insert(lines, '')
  end
  return lines
end

local function mark_breaking_changes(
  plugin: Plugin,
  disp: Display
): boolean, {string}, {string}
  disp:task_update(plugin.name, 'checking for breaking changes...')
  local ok, out = git_run({
    'log',
    '--color=never',
    '--no-show-signature',
    '--pretty=format:===COMMIT_START===%h%n%s===BODY_START===%b',
    'HEAD@{1}...HEAD'
  }, {
    cwd = plugin.install_path
  })
  if ok then
    plugin.breaking_commits = get_breaking_commits(out)
  end
  return ok, out
end

local function clone(plugin: Plugin, timeout: integer): boolean, {string}
  local clone_cmd = { 'clone' }

  -- partial clone support
  if check_version{2, 19, 0} then
    vim.list_extend(clone_cmd, {
      "--filter=blob:none",
    })
  end

  vim.list_extend(clone_cmd, {
    '--no-checkout',
    '--single-branch',
    '--progress'
  })

  vim.list_extend(clone_cmd, { plugin.url, plugin.install_path })

  return git_run(clone_cmd, { timeout = timeout })
end

---@async
local function install(plugin: Plugin, disp: Display): boolean, {string}
  disp:task_update(plugin.full_name, 'cloning...')

  local ok, out = clone(plugin, config.git.clone_timeout)
  if not ok then
    return nil, out
  end

  ok, out = checkout(plugin, disp)
  if not ok then
    return nil, out
  end

  return true, out
end

M.installer = async(function(plugin: Plugin, disp: Display): {string}
  local ok, out = install(plugin, disp)

  if ok then
    plugin.messages = out
    return
  end

  plugin.err = out

  return out
end, 2)

local function log_err(plugin: Plugin, msg: string, x: string|{string})
  local x1 = x is string and x or table.concat(x as {string}, '\n')
  log.fmt_debug('%s: $s: %s', plugin.name, msg, x1)
end

---@async
local function update(plugin: Plugin, disp: Display): boolean, {string}
  disp:task_update(plugin.full_name, 'checking current commit...')

  plugin.revs[1] = get_ref(plugin, 'HEAD')

  disp:task_update(plugin.full_name, 'fetching updates...')
  local ok, out = git_run({
    'fetch',
    '--update-shallow',
    '--progress',
  }, {
    cwd = plugin.install_path
  })
  if not ok then
    return false, out
  end

  disp:task_update(plugin.full_name, 'pulling updates...')
  ok, out = checkout(plugin, disp)

  if not ok then
    log_err(plugin, 'failed checkout', out)
    return false, out
  end

  plugin.revs[2] = get_ref(plugin, 'HEAD')

  if plugin.revs[1] ~= plugin.revs[2] then
    disp:task_update(plugin.full_name, 'getting commit messages...')
    ok, out = git_run({
      'log',
      '--color=never',
      '--pretty=format:%h %s (%cr)',
      '--no-show-signature',
      fmt('%s...%s',  plugin.revs[1], plugin.revs[2])
    }, {
      cwd = plugin.install_path,
    })

    if not ok then
      log_err(plugin, 'failed getting commit messages', out)
      return false, out
    end

    plugin.messages = out

    ok, out = mark_breaking_changes(plugin, disp)
    if not ok then
      log_err(plugin, 'failed marking breaking changes', out)
      return false, out
    end
  end

  return true
end

M.updater = async(function(plugin: Plugin, disp: Display): {string}
  local ok, out = update(plugin, disp)
  if not ok then
    plugin.err = out
    return plugin.err
  end
end, 2)

M.remote_url = async(function(plugin: Plugin): string
  local ok, out = git_run({ 'remote', 'get-url', 'origin' }, {
    cwd = plugin.install_path
  })

  if ok then
    return out[1]
  end
end, 1)

M.diff = async(function(plugin: Plugin, commit: string, callback: function({string}, {string}): {string}): {string}
  local ok, out = git_run({
    'show', '--no-color',
    '--pretty=medium',
    commit
  }, {
    cwd = plugin.install_path
  })

  if ok then
    return callback(split_messages(out))
  else
    return callback(nil, out)
  end
end, 3)

M.revert_last = async(function(plugin: Plugin): {string}
  local ok, out = git_run({ 'reset', '--hard', 'HEAD@{1}' }, {
    cwd = plugin.install_path
  })

  if not ok then
    log.fmt_error('Reverting update for %s failed!', plugin.full_name)
    return out
  end

  ok, out = checkout(plugin)
  if not ok then
    log.fmt_error('Reverting update for %s failed!', plugin.full_name)
    return out
  end

  log.fmt_info('Reverted update for %s', plugin.full_name)
end, 1)

--- Reset the plugin to `commit`
M.revert_to = async(function(plugin: Plugin, commit: string): {string}
  assert(type(commit) == 'string', fmt("commit: string expected but '%s' provided", type(commit)))
  log.fmt_debug("Reverting '%s' to commit '%s'", plugin.name, commit)
  local ok, out = git_run({ 'reset', '--hard', commit, '--' }, {
    cwd = plugin.install_path
  })

  if not ok then
    return out
  end
end, 2)

--- Returns HEAD's short hash
M.get_rev = async(function(plugin: Plugin): string, string
  return get_ref(plugin, 'HEAD')
end, 1)

return M
