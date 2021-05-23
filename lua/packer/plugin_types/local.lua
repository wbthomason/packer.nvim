local a = require('packer.async')
local log = require('packer.log')
local util = require('packer.util')
local result = require('packer.result')

local async = a.sync
local await = a.wait

local config = nil
local function cfg(_config) config = _config end

local symlink = a.wrap(vim.loop.fs_symlink)

local function setup_local(plugin)
  local from = plugin.path
  local to = plugin.install_path

  local plugin_name = util.get_plugin_full_name(plugin)
  plugin.installer = function(disp)
    return async(function()
      disp:task_update(plugin_name, 'making symlink...')
      local err, success = await(symlink(from, to, {dir = true}))
      if not success then
        plugin.output = {err = {err}}
        return result.err(err)
      end
      return result.ok()
    end)
  end

  plugin.updater = function(_) return async(function() return result.ok() end) end
  plugin.revert_last = function(_)
    log.warn("Can't revert a local plugin!")
    return result.ok()
  end
end

return {setup = setup_local, cfg = cfg}
