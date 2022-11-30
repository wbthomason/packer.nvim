local a = require('packer.async')
local log = require('packer.log')
local util = require('packer.util')
local Display = require('packer.display').Display

local fmt = string.format

local uv = vim.loop

local M = {}










local symlink_fn
if util.is_windows then
   symlink_fn = function(path, new_path, flags, callback)
      flags = flags or {}
      flags.junction = true
      return uv.fs_symlink(path, new_path, flags, callback)
   end
else
   symlink_fn = uv.fs_symlink
end

local symlink = a.wrap(symlink_fn, 4)
local unlink = a.wrap(uv.fs_unlink, 2)

M.installer = a.sync(function(plugin, disp)
   local from = uv.fs_realpath(util.strip_trailing_sep(plugin.url))
   local to = util.strip_trailing_sep(plugin.install_path)

   disp:task_update(plugin.full_name, 'making symlink...')
   local err, success = symlink(from, to, { dir = true })
   if not success then
      plugin.err = { err }
      return plugin.err
   end
end, 2)

local sleep = a.wrap(function(ms, cb)
   vim.defer_fn(cb, ms)
end, 2)

M.updater = a.sync(function(plugin, disp)
   local from = uv.fs_realpath(util.strip_trailing_sep(plugin.url))
   local to = util.strip_trailing_sep(plugin.install_path)




   sleep(200)

   disp:task_update(plugin.full_name, 'checking symlink...')

   sleep(200)

   local is_link = uv.fs_lstat(to).type == 'link'
   if not is_link then
      log.debug(fmt('%s: %s is not a link', plugin.name, to))
      return { to .. ' is not a link' }
   end

   if uv.fs_realpath(to) ~= from then
      disp:task_update(plugin.full_name, fmt('updating symlink from %s to %s', from, to))
      local err, success = unlink(to)
      if err then
         log.debug(fmt('%s: failed to unlink %s: %s', plugin.name, to, err))
         return err
      end
      assert(success)
      log.debug(fmt('%s: did unlink', plugin.name))
      err = symlink(from, to, { dir = true })
      if err then
         log.debug(fmt('%s: failed to link from %s to %s: %s', plugin.name, from, to, err))
         return { err }
      end
   end
end, 1)

M.revert_last = function(_)
   log.warn("Can't revert a local plugin!")
end

M.diff = function(_, _, _)
   log.warn("Can't diff a local plugin!")
end

return M
