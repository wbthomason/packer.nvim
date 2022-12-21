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
   local data = jr.output.data
   return
jr:ok(),
   #data.stdout > 0 and data.stdout or nil,
   #data.stderr > 0 and data.stderr or nil
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

local function checkout(ref, opts)
   local ok, _, err = git_run({
      'checkout',
      '--progress',
      ref,
   }, opts)
   return not ok and err or nil
end


local handle_checkouts = function(plugin, disp, opts)
   local function update_disp(msg)
      if disp then
         disp:task_update(plugin.full_name, msg)
      end
   end

   update_disp('fetching reference...')

   local job_opts = {
      cwd = plugin.install_path,
   }

   if plugin.tag and has_wildcard(plugin.tag) then
      update_disp(fmt('getting tag for wildcard %s...', plugin.tag))
      local tagok, tagout, tagerr = git_run({
         'tag', '-l', plugin.tag,
         '--sort', '-version:refname',
      }, job_opts)
      if tagok then
         plugin.tag = vim.split(tagout[1], '\n')[1]
      else
         log.fmt_warn(
         'Wildcard expansion did not find any tag for plugin %s: defaulting to latest commit...',
         plugin.name)

         plugin.tag = nil
         return tagerr
      end
   end

   if (plugin.branch or (plugin.tag and not opts.preview_updates)) then
      local branch_or_tag = plugin.branch or plugin.tag
      local coerr = checkout(branch_or_tag, job_opts)
      if coerr then
         return coerr
      end
   end

   if plugin.commit then
      local coerr = checkout(plugin.commit, job_opts)
      if coerr then
         return coerr
      end
   end

   return
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
   disp,
   preview_updates)

   disp:task_update(plugin.name, 'checking for breaking changes...')
   local ok, out, err = git_run({
      'log',
      '--color=never',
      '--no-show-signature',
      '--pretty=format:===COMMIT_START===%h%n%s===BODY_START===%b',
      preview_updates and 'HEAD...FETCH_HEAD' or 'HEAD@{1}...HEAD',
   }, {
      cwd = plugin.install_path,
   })
   if ok then
      plugin.breaking_commits = get_breaking_commits(out)
   end
   return ok, out, err
end

local function get_clone_cmd(plugin)
   local clone_cmd = { 'clone' }


   if check_version({ 2, 19, 0 }) then
      vim.list_extend(clone_cmd, {
         "--filter=blob:none",
      })
   end

   vim.list_extend(clone_cmd, {
      '--recurse-submodules',
      '--shallow-submodules',
      '--no-checkout',
      '--single-branch',
      '--progress',
   })

   if plugin.branch or (plugin.tag and not has_wildcard(plugin.tag)) then
      vim.list_extend(clone_cmd, { '--branch', plugin.branch or plugin.tag })
   end

   vim.list_extend(clone_cmd, { plugin.url, plugin.install_path })

   return clone_cmd
end


local function install(plugin, disp)
   disp:task_update(plugin.full_name, 'cloning...')

   local ok, out, err = git_run(get_clone_cmd(plugin), { timeout = config.git.clone_timeout })
   if not ok then
      return nil, err
   end

   local coerr = checkout(plugin.commit or 'HEAD', { cwd = plugin.install_path })
   if coerr then
      return nil, coerr
   end

   return out
end

M.installer = async(function(plugin, disp)
   local stdout, stderr = install(plugin, disp)

   if stdout then
      plugin.messages = stdout
      return
   end

   plugin.err = stderr

   return plugin.err
end, 2)

local function file_lines(file)
   local text = {}
   if not vim.loop.fs_stat(file) then
      return
   end
   for line in io.lines(file) do
      text[#text + 1] = line
   end
   return text
end

local function get_ref(plugin, ...)
   local lines = file_lines(util.join_paths(plugin.install_path, '.git', ...))
   if lines then
      return lines[1]
   end
end




local function get_current_branch(plugin)

   local remote_head = get_ref(plugin, 'refs', 'remotes', 'origin', 'HEAD')
   if remote_head then
      local branch = remote_head:match('^ref: refs/remotes/origin/(.*)')
      if branch then
         return branch
      end
   end
end

local function log_err(plugin, msg, x)
   local x1 = type(x) == "string" and x or table.concat(x, '\n')
   log.fmt_debug('%s: $s: %s', plugin.name, msg, x1)
end


local function update(plugin, disp, opts)
   disp:task_update(plugin.full_name, 'checking current commit...')

   plugin.revs[1] = get_ref(plugin, 'HEAD')

   disp:task_update(plugin.full_name, 'fetching updates...')
   local ok, _, err = git_run({
      'fetch',
      '--update-shallow',
      '--recurse-submodules',
      '--progress',
   }, {
      cwd = plugin.install_path,
   })
   if not ok then
      return err
   end

   local coerr = handle_checkouts(plugin, disp, opts)

   if coerr then
      log_err(plugin, 'failed checkout', coerr)
      return coerr
   end

   disp:task_update(plugin.full_name, 'pulling updates...')
   local target
   if plugin.commit then
      target = plugin.commit
   elseif plugin.tag then
      target = 'tags/' .. plugin.tag
   else
      local branch = get_current_branch(plugin)
      target = get_ref(plugin, 'remotes', 'origin', branch) or
      get_ref(plugin, 'refs', 'heads', branch)
   end

   coerr = checkout(target, { cwd = plugin.install_path })
   if coerr then
      log_err(plugin, 'failed getting updates', coerr)
      return coerr
   end

   plugin.revs[2] = get_ref(plugin, 'HEAD')

   if plugin.revs[1] ~= plugin.revs[2] then
      disp:task_update(plugin.full_name, 'getting commit messages...')
      local out
      ok, out, err = git_run({
         'log',
         '--color=never',
         '--pretty=format:%h %s (%cr)',
         '--no-show-signature',
         fmt('%s...%s', plugin.revs[1], plugin.revs[2]),
      }, {
         cwd = plugin.install_path,
      })

      if not ok then
         log_err(plugin, 'failed getting commit messages', err)
         return err
      end

      plugin.messages = out

      ok, out, err = mark_breaking_changes(plugin, disp, opts.preview_updates)
      if not ok then
         print('DDD2')
         log_err(plugin, 'failed marking breaking changes', err)
         return err
      end
   end

   return
end

M.updater = async(function(plugin, disp, opts)
   plugin.err = update(plugin, disp, opts)
   return plugin.err
end, 4)

M.remote_url = async(function(plugin)
   local ok, out = git_run({ 'remote', 'get-url', 'origin' }, {
      cwd = plugin.install_path,
   })

   if ok then
      return out[1]
   end
end, 1)

M.diff = async(function(plugin, commit, callback)
   local ok, out, err = git_run({
      'show', '--no-color',
      '--pretty=medium',
      commit,
   }, {
      cwd = plugin.install_path,
   })

   if ok then
      return callback(split_messages(out))
   else
      return callback(nil, err)
   end
end, 3)

M.revert_last = async(function(plugin)
   local ok, _, err = git_run({ 'reset', '--hard', 'HEAD@{1}' }, {
      cwd = plugin.install_path,
   })

   if not ok then
      log.fmt_error('Reverting update for %s failed!', plugin.full_name)
      return err
   end

   if (plugin.tag or plugin.commit or plugin.branch) ~= nil then
      local coerr = handle_checkouts(plugin, nil, {})
      if coerr then
         log.fmt_error('Reverting update for %s failed!', plugin.full_name)
         return coerr
      end
   end
   log.fmt_info('Reverted update for %s', plugin.full_name)
end, 1)


M.revert_to = async(function(plugin, commit)
   assert(type(commit) == 'string', fmt("commit: string expected but '%s' provided", type(commit)))
   log.fmt_debug("Reverting '%s' to commit '%s'", plugin.name, commit)
   local ok, _, err = git_run({ 'reset', '--hard', commit, '--' }, {
      cwd = plugin.install_path,
   })

   if not ok then
      return err
   end
end, 2)


M.get_rev = async(function(plugin)
   return get_ref(plugin, 'HEAD')
end, 1)

return M