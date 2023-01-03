local a = require('packer.async')
local config = require('packer.config')
local jobs = require('packer.jobs')
local log = require('packer.log')
local util = require('packer.util')
local Display = require('packer.display').Display
local Plugin = require('packer.plugin').Plugin

local async = a.sync

local fmt = string.format

local M = {}









local job_env = {}

do
   local blocked_env_vars = {
      GIT_DIR = true,
      GIT_INDEX_FILE = true,
      GIT_OBJECT_DIRECTORY = true,
      GIT_TERMINAL_PROMPT = true,
      GIT_WORK_TREE = true,
      GIT_COMMON_DIR = true,
   }

   for k, v in pairs(vim.fn.environ()) do
      if not blocked_env_vars[k] then
         job_env[#job_env + 1] = k .. '=' .. v
      end
   end

   job_env[#job_env + 1] = 'GIT_TERMINAL_PROMPT=0'
end

local function has_wildcard(tag)
   return tag and tag:match('*') ~= nil
end

local BREAK_TAG_PAT = '[[bB][rR][eE][aA][kK]!?:]'
local BREAKING_CHANGE_PAT = '[[bB][rR][eE][aA][kK][iI][nN][gG][ _][cC][hH][aA][nN][gG][eE]]'
local TYPE_EXCLAIM_PAT = '[[a-zA-Z]+!:]'
local TYPE_SCOPE_EXPLAIN_PAT = '[[a-zA-Z]+%([^)]+%)!:]'

local function is_breaking(x)
   return x and (
   x:match(BREAKING_CHANGE_PAT) or
   x:match(BREAK_TAG_PAT) or
   x:match(TYPE_EXCLAIM_PAT) or
   x:match(TYPE_SCOPE_EXPLAIN_PAT)) ~=
   nil
end

local function get_breaking_commits(commit_bodies)
   local ret = {}
   local commits = vim.gsplit(table.concat(commit_bodies, '\n'), '===COMMIT_START===', true)

   for commit in commits do
      local commit_parts = vim.split(commit, '===BODY_START===')
      local body = commit_parts[2]
      local lines = vim.split(commit_parts[1], '\n')
      if is_breaking(body) or is_breaking(lines[2]) then
         ret[#ret + 1] = lines[1]
      end
   end
   return ret
end

local function git_run(args, opts)
   opts = opts or {}
   opts.env = opts.env or job_env
   local jr = jobs.run({ config.git.cmd, unpack(args) }, opts)
   local ok = jr.exit_code == 0
   if ok then
      return true, jr.stdout
   end
   return true, jr.stderr
end

local git_version

local function parse_version(version)
   assert(version:match('%d+%.%d+%.%w+'), 'Invalid git version: ' .. version)
   local parts = vim.split(version, '%.')
   local ret = {}
   ret[1] = tonumber(parts[1])
   ret[2] = tonumber(parts[2])

   if parts[3] == 'GIT' then
      ret[3] = 0
   else
      ret[3] = tonumber(parts[3])
   end

   return ret
end


local function set_version()
   if git_version then
      return
   end

   local vok, out = git_run({ '--version' })
   if vok then
      local line = out[1]
      local ok, err = pcall(function()
         assert(vim.startswith(line, 'git version'), 'Unexpected output: ' .. line)
         local parts = vim.split(line, '%s+')
         git_version = parse_version(parts[3])
      end)
      if not ok then
         log.error(err)
         return
      end
   end
end


local function check_version(version)
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

local function head(...)
   local lines = util.file_lines(util.join_paths(...))
   if lines then
      return lines[1]
   end
end

local SHA_PAT = string.rep('%x', 40)

local function resolve_ref(dir, ref)
   if ref:match(SHA_PAT) then
      return ref
   end
   local ptr = ref:match('^ref: (.*)')
   if ptr then
      return head(dir, '.git', unpack(vim.split(ptr, '/')))
   end
end

local function get_head(dir)
   return resolve_ref(dir, head(dir, '.git', 'HEAD'))
end


local function get_current_branch(plugin)

   local remote_head = head(plugin.install_path, '.git', 'refs', 'remotes', 'origin', 'HEAD')
   if remote_head then
      local branch = remote_head:match('^ref: refs/remotes/origin/(.*)')
      if branch then
         return branch
      end
   end


   local local_head = head(plugin.install_path, '.git', 'HEAD')

   if local_head then
      local branch = local_head:match('^ref: refs/heads/(.*)')
      if branch then
         return branch
      end
   end

   error('Could not get current branch for ' .. plugin.install_path)
end

local function resolve_tag(plugin)
   local tag = plugin.tag
   local ok, out = git_run({
      'tag', '-l', tag,
      '--sort', '-version:refname',
   }, {
      cwd = plugin.install_path,
   })

   if ok then
      tag = vim.split(out[#out], '\n')[1]
      return tag
   end

   log.fmt_warn(
   'Wildcard expansion did not find any tag for plugin %s: defaulting to latest commit...',
   plugin.name)

   tag = nil
   return nil, out
end


local function checkout(plugin, disp)
   local function update_disp(msg)
      if disp then
         disp:task_update(plugin.full_name, msg)
      end
   end

   update_disp('fetching reference...')

   local tag = plugin.tag


   if tag and has_wildcard(tag) then
      update_disp(fmt('getting tag for wildcard %s...', tag))
      local tagerr
      tag, tagerr = resolve_tag(plugin)
      if not tag then
         return false, tagerr
      end
   end

   local target
   if plugin.commit then
      target = plugin.commit
   elseif tag then
      target = 'tags/' .. tag
   else
      local branch = plugin.branch or get_current_branch(plugin)
      target = head(plugin.install_path, '.git', 'refs', 'remotes', 'origin', branch) or
      head(plugin.install_path, '.git', 'refs', 'heads', branch)
   end

   assert(target, 'Could not determine target for ' .. plugin.install_path)

   return git_run({ 'checkout', '--progress', target }, { cwd = plugin.install_path })
end

local function split_messages(messages)
   local lines = {}
   for _, message in ipairs(messages) do
      vim.list_extend(lines, vim.split(message, '\n'))
      table.insert(lines, '')
   end
   return lines
end

local function mark_breaking_changes(
   plugin,
   disp)

   disp:task_update(plugin.name, 'checking for breaking changes...')
   local ok, out = git_run({
      'log',
      '--color=never',
      '--no-show-signature',
      '--pretty=format:===COMMIT_START===%h%n%s===BODY_START===%b',
      'HEAD@{1}...HEAD',
   }, {
      cwd = plugin.install_path,
   })
   if ok then
      plugin.breaking_commits = get_breaking_commits(out)
   end
   return ok, out
end

local function clone(plugin, timeout)
   local clone_cmd = {
      'clone',
      '--no-checkout',
      '--progress',
   }


   if check_version({ 2, 19, 0 }) then
      vim.list_extend(clone_cmd, {
         "--filter=blob:none",
      })
   end

   vim.list_extend(clone_cmd, { plugin.url, plugin.install_path })

   return git_run(clone_cmd, { timeout = timeout })
end


local function install(plugin, disp)
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

M.installer = async(function(plugin, disp)
   local ok, out = install(plugin, disp)

   if ok then
      plugin.messages = out
      return
   end

   plugin.err = out

   return out
end, 2)

local function log_err(plugin, msg, x)
   local x1 = type(x) == "string" and x or table.concat(x, '\n')
   log.fmt_debug('%s: $s: %s', plugin.name, msg, x1)
end


local function update(plugin, disp)
   disp:task_update(plugin.full_name, 'checking current commit...')

   plugin.revs[1] = get_head(plugin.install_path)

   disp:task_update(plugin.full_name, 'fetching updates...')
   local ok, out = git_run({
      'fetch',
      '--tags',
      '--force',
      '--update-shallow',
      '--progress',
   }, {
      cwd = plugin.install_path,
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

   plugin.revs[2] = get_head(plugin.install_path)

   if plugin.revs[1] ~= plugin.revs[2] then
      disp:task_update(plugin.full_name, 'getting commit messages...')
      ok, out = git_run({
         'log',
         '--color=never',
         '--pretty=format:%h %s (%cr)',
         '--no-show-signature',
         fmt('%s...%s', plugin.revs[1], plugin.revs[2]),
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

M.updater = async(function(plugin, disp)
   local ok, out = update(plugin, disp)
   if not ok then
      plugin.err = out
      return plugin.err
   end
end, 2)

M.remote_url = async(function(plugin)
   local ok, out = git_run({ 'remote', 'get-url', 'origin' }, {
      cwd = plugin.install_path,
   })

   if ok then
      return out[1]
   end
end, 1)

M.diff = async(function(plugin, commit, callback)
   local ok, out = git_run({
      'show', '--no-color',
      '--pretty=medium',
      commit,
   }, {
      cwd = plugin.install_path,
   })

   if ok then
      return callback(split_messages(out))
   else
      return callback(nil, out)
   end
end, 3)

M.revert_last = async(function(plugin)
   local ok, out = git_run({ 'reset', '--hard', 'HEAD@{1}' }, {
      cwd = plugin.install_path,
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


M.revert_to = async(function(plugin, commit)
   assert(type(commit) == 'string', fmt("commit: string expected but '%s' provided", type(commit)))
   log.fmt_debug("Reverting '%s' to commit '%s'", plugin.name, commit)
   local ok, out = git_run({ 'reset', '--hard', commit, '--' }, {
      cwd = plugin.install_path,
   })

   if not ok then
      return out
   end
end, 2)


M.get_rev = async(function(plugin)
   return get_head(plugin.install_path)
end, 1)

return M