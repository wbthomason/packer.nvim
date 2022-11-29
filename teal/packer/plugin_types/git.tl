local a      = require 'packer.async'
local config = require 'packer.config'
local jobs   = require 'packer.jobs'
local log    = require 'packer.log'
local util   = require 'packer.util'
local Display = require 'packer.display'.Display

local async = a.sync

local fmt = string.format

local record UpdateOpts
  preview_updates: boolean
  pull_head: boolean
end

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

local function git_run(args: {string}, opts: jobs.Opts): jobs.JobResult
  opts.env = opts.env or job_env
  return jobs.run({ config.git.cmd, unpack(args) }, opts)
end

local function checkout(ref: string, opts: jobs.Opts, disp: Display): jobs.JobResult
  if disp then
    disp:task_update(fmt('checking out %s...', ref))
  end
  return git_run({'checkout', ref, '--' }, opts)
end

---@async
local handle_checkouts = function(plugin: Plugin, disp: Display, opts: UpdateOpts): {string}
  local function update_disp(msg: string)
    if disp then
      disp:task_update(plugin.full_name, msg)
    end
  end

  update_disp('fetching reference...')

  local job_opts: jobs.Opts = {
    cwd = plugin.install_path
  }

  if plugin.tag and has_wildcard(plugin.tag) then
    update_disp(fmt('getting tag for wildcard %s...', plugin.tag))
    local jr = git_run({
      'tag', '-l', plugin.tag,
      '--sort', '-version:refname'
    }, job_opts)
    if jr:ok() then
      local data = jr.output.data.stdout[1]
      plugin.tag = vim.split(data, '\n')[1]
    else
      log.warn(fmt(
        'Wildcard expansion did not find any tag for plugin %s: defaulting to latest commit...',
        plugin.name
      ))
      plugin.tag = nil -- Wildcard is not found, then we bypass the tag
      return jr.output.data.stderr
    end
  end

  if (plugin.branch or (plugin.tag and not opts.preview_updates)) then
    local branch_or_tag = plugin.branch or plugin.tag
    local jr = checkout(branch_or_tag, job_opts, disp)
    if not jr:ok() then
      return jr.output.data.stderr
    end
  end

  if plugin.commit then
    local jr = checkout(plugin.commit, job_opts, disp)
    if not jr:ok() then
      return jr.output.data.stderr
    end
  end

  return
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
  disp: Display,
  preview_updates: boolean
): jobs.JobResult
  disp:task_update(plugin.name, 'checking for breaking changes...')
  local r = git_run({
    'log',
    '--color=never',
    '--no-show-signature',
    '--pretty=format:===COMMIT_START===%h%n%s===BODY_START===%b',
    preview_updates and 'HEAD...FETCH_HEAD' or 'HEAD@{1}...HEAD'
  }, {
    cwd = plugin.install_path
  })
  if r:ok() then
    plugin.breaking_commits = get_breaking_commits(r.output.data.stdout)
  end
  return r
end

local function get_install_cmd(plugin: Plugin): {string}
  local install_cmd = {
    'clone',
    '--depth', tostring(plugin.commit and 999999 or config.git.depth),
    -- TODO(lewis6991,clason): is this option needed? It can inflate the
    -- checkout size, and it's not clear why we want to pull in all branches.
    -- If you switch to a branch in the spec, it's cleaner to remove and
    -- re-clone anyway. And --depth 1 already prevents you from using the clone
    -- as an actual local repo.
    '--no-single-branch',
    '--progress'
  }

  if plugin.branch or (plugin.tag and not has_wildcard(plugin.tag)) then
    vim.list_extend(install_cmd, { '--branch', plugin.branch or plugin.tag })
  end

  vim.list_extend(install_cmd, { plugin.url, plugin.install_path })

  return install_cmd
end

---@async
local function install(plugin: Plugin, disp: Display): jobs.JobResult
  disp:task_update(plugin.full_name, 'cloning...')

  local jr = git_run(get_install_cmd(plugin), { timeout = config.git.clone_timeout })
  if not jr:ok() then
    return jr
  end

  if plugin.commit then
    jr = checkout(plugin.commit, { cwd = plugin.install_path }, disp)
    if not jr:ok() then
      return jr
    end
  end

  -- TODO(lewis6991): why do this?
  -- Get current commit
  -- jr = git_run({
  --   'log',
  --   '--color=never',
  --   '--pretty=format:%h %s (%cr)',
  --   '--no-show-signature',
  --   'HEAD',
  --   '-n', '1'
  -- }, {
  --   cwd = plugin.install_path
  -- })

  return jr
end

M.installer = async(function(plugin: Plugin, disp: Display): {string}
  local jr = install(plugin, disp)

  if jr:ok() then
    plugin.messages = jr.output.data.stdout
    return
  end

  plugin.err = jr.output.data.stderr

  return plugin.err
end, 2)

---@async
local function get_current_branch(plugin: Plugin): string, string
  -- local branch_cmd = {config.git.cmd, 'rev-parse', '--abbrev-ref', 'HEAD'}
  local jr = git_run({ 'branch', '--show-current' }, {
    cwd = plugin.install_path
  })
  local current_branch, er: string, string
  if jr:ok() then
    current_branch = jr.output.data.stdout[1]
  else
    er = table.concat(jr.output.data.stderr, '\n')
  end
  return current_branch, er
end

---@async
local function get_ref(plugin: Plugin, ref: string): string, string
  local jr = git_run({ 'rev-parse', '--short', ref }, {
    cwd = plugin.install_path
  })

  local ref1, er: string, string
  if jr:ok() then
    ref1 = jr.output.data.stdout[1]
  else
    er = table.concat(jr.output.data.stderr, '\n')
  end

  return ref1, er
end

local function file_lines(file: string): {string}
  local text: {string} = {}
  for line in io.lines(file) do
    text[#text+1] = line
  end
  return text
end

local function log_err(plugin: Plugin, msg: string, x: string|{string})
  local x1 = x is string and x or table.concat(x as {string}, '\n')
  log.debug(fmt('%s: $s: %s', plugin.name, msg, x1))
end

---@async
local function update(plugin: Plugin, disp: Display, opts: table): {string}
  disp:task_update(plugin.full_name, 'checking current commit...')
  local current_commit, ccerr = get_ref(plugin, 'HEAD')
  if ccerr then
    log_err(plugin, 'failed getting current commit', ccerr)
    return {ccerr}
  end

  plugin.revs[1] = current_commit

  disp:task_update(plugin.full_name, 'checking current branch...')

  local current_branch, cberr = get_current_branch(plugin)
  if cberr then
    log_err(plugin, 'failed getting current branch', cberr)
    return {cberr}
  end

  local needs_checkout = (plugin.tag or plugin.commit or plugin.branch) ~= nil

  if not needs_checkout then
    local origin_branch = ''
    disp:task_update(plugin.full_name, 'checking origin branch...')
    -- TODO(lewis6991): Don't assume 'origin' is the upstream name
    local origin_refs_path = util.join_paths(plugin.install_path, '.git', 'refs', 'remotes', 'origin', 'HEAD')
    if vim.loop.fs_stat(origin_refs_path) then
      local origin_refs = file_lines(origin_refs_path)
      if #origin_refs > 0 then
        origin_branch = string.match(origin_refs[1], [[^ref: refs/remotes/origin/(.*)]])
      end
    end

    if current_branch ~= origin_branch then
      needs_checkout = true
      plugin.branch = origin_branch
    end
  end

  if needs_checkout then
    local jr = git_run({ 'fetch', '--depth', '999999', '--progress' }, {
      cwd = plugin.install_path
    })
    if not jr:ok() then
      return jr.output.data.stderr
    end

    local coerr = handle_checkouts(plugin, disp, opts as UpdateOpts)

    if coerr then
      log_err(plugin, 'failed checkout', coerr)
      return coerr
    end
  end

  do
    local fetch_cmd = { 'fetch', '--depth', '999999', '--progress' }

    local cmd, msg: {string}, string
    if opts.preview_updates then
      cmd = fetch_cmd
      msg = 'fetching updates...'
    elseif opts.pull_head then
      cmd = { 'merge', 'FETCH_HEAD' }
      msg = 'pulling updates from head...'
    elseif plugin.commit or plugin.tag then
      cmd = fetch_cmd
      msg = 'pulling updates...'
    else
      cmd = { 'pull', '--ff-only', '--progress', '--rebase=false' }
      msg = 'pulling updates...'
    end

    disp:task_update(plugin.full_name, msg)
    local jr = git_run(cmd, {
      cwd = plugin.install_path
    })
    if not jr:ok() then
      local err = jr.output.data.stderr
      log_err(plugin, 'failed getting updates', err)
      return err
    end
  end

  -- NOTE that any tag wildcard should already been expanded to a specific commit at this point
  local ref = plugin.tag ~= nil and fmt('%s^{}', plugin.tag) or 'FETCH_HEAD'

  disp:task_update(plugin.full_name, 'checking updated commit...')

  local new_rev, crerr = get_ref(plugin, ref)
  if crerr then
    log_err(plugin, 'failed getting new revision', crerr)
    return {crerr}
  end

  plugin.revs[2] = new_rev

  if plugin.revs[1] ~= plugin.revs[2] then
    disp:task_update(plugin.full_name, 'getting commit messages...')
    local jr = git_run({
      'log',
      '--color=never',
      '--pretty=format:%h %s (%cr)',
      '--no-show-signature',
      fmt('%s...%s',  plugin.revs[1], plugin.revs[2])
    }, {
      cwd = plugin.install_path,
    })

    if not jr:ok() then
      local err = jr.output.data.stderr
      log_err(plugin, 'failed getting commit messages', err)
      return err
    end

    plugin.messages = jr.output.data.stdout

    jr = mark_breaking_changes(plugin, disp, opts.preview_updates as boolean)
    if not jr:ok() then
      local err = jr.output.data.stderr
      log_err(plugin, 'failed marking breaking changes', err)
      return err
    end
  end

  return nil
end

M.updater = async(function(plugin: Plugin, disp: Display, opts: table): {string}
  plugin.err = update(plugin, disp, opts)
  return plugin.err
end, 4)

M.remote_url = async(function(plugin: Plugin): string
  local r = git_run({ 'remote', 'get-url', 'origin' }, {
    cwd = plugin.install_path
  })

  if r:ok() then
    return r.output.data.stdout[1]
  end
end, 1)

M.diff = async(function(plugin: Plugin, commit: string, callback: function({string}, {string}): {string}): {string}
  local jr = git_run({
    'show', '--no-color',
    '--pretty=medium',
    commit
  }, {
    cwd = plugin.install_path
  })

  if jr:ok() then
    return callback(split_messages(jr.output.data.stdout))
  else
    return callback(nil, jr.output.data.stderr)
  end
end, 3)

M.revert_last = async(function(plugin: Plugin): {string}
  local jr = git_run({ 'reset', '--hard', 'HEAD@{1}' }, {
    cwd = plugin.install_path
  })

  if not jr:ok() then
    log.error(fmt('Reverting update for %s failed!', plugin.full_name))
    return jr.output.data.stderr
  end

  if (plugin.tag or plugin.commit or plugin.branch) ~= nil then
    local coerr = handle_checkouts(plugin, nil, {})
    if coerr then
      log.error(fmt('Reverting update for %s failed!', plugin.full_name))
      return coerr
    end
  end
  log.info('Reverted update for ' .. plugin.full_name)
end, 1)

--- Reset the plugin to `commit`
M.revert_to = async(function(plugin: Plugin, commit: string): {string}
  assert(type(commit) == 'string', fmt("commit: string expected but '%s' provided", type(commit)))
  require('packer.log').debug(fmt("Reverting '%s' to commit '%s'", plugin.name, commit))
  local jr = git_run({ 'reset', '--hard', commit, '--' }, {
    cwd = plugin.install_path
  })

  if not jr:ok() then
    return jr.output.data.stderr
  end
end, 2)

--- Returns HEAD's short hash
M.get_rev = async(function(plugin: Plugin): string, string
  return get_ref(plugin, 'HEAD')
end, 1)

return M
