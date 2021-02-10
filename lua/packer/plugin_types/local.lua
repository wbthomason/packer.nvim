local a = require('packer.async')
local jobs = require('packer.jobs')
local log = require('packer.log')
local util = require('packer.util')
local result = require('packer.result')

local async = a.sync
local await = a.wait

local config = nil
local function cfg(_config) config = _config end
local job_opts = {capture_output = true}

local function setup_local(plugin)
  local from = plugin.path
  local to = plugin.install_path
  local task

  if vim.fn.executable('ln') == 1 then
    task = {'ln', '-sf', from, to}
    -- NOTE: We assume mklink is present on Windows because executable() is apparently not reliable
    -- (see issue #49)
  elseif util.is_windows then
    task = {'cmd', '/C', 'mklink', '/d', to, from}
  else
    log.error('No executable symlink command found!')
    return
  end

  local plugin_name = util.get_plugin_full_name(plugin)
  plugin.installer = function(disp)
    return async(function()
      disp:task_update(plugin_name, 'making symlink...')
      return await(jobs.run(task, job_opts))
    end)
  end

  plugin.updater = function(_) return async(function() return result.ok() end) end
  plugin.revert_last = function(_)
    log.warn("Can't revert a local plugin!")
    return result.ok()
  end
end

return {setup = setup_local, cfg = cfg}
