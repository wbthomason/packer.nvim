local a    = require('packer/async')
local jobs = require('packer/jobs')
local log  = require('packer/log')
local util = require('packer/util')

local async = a.sync
local await = a.wait

local config = nil
local function cfg(_config)
  config = _config
end

local function setup_local(plugin)
  local from = plugin.path
  local to = util.join_paths((plugin.opt and config.opt_dir or config.start_dir), plugin.name)
  local task
  if vim.fn.executable('ln') then
    task = { 'ln', '-sf', from, to }
  elseif util.is_windows and vim.fn.executable('mklink') then
    task = { 'mklink', from, to }
  else
    log.error('No executable symlink command found!')
    return
  end

  local plugin_name = util.get_plugin_full_name(plugin)
  plugin.installer = function(disp)
    return async(function()
      disp:task_update(plugin_name, 'making symlink...')
      local result = await(jobs.run(task))
      return result.exit_code == 0
    end)
  end

  plugin.updater = function(_) return async(function() return true end) end
end

local local_plugin = {
  setup = setup_local,
  cfg = cfg
}

return local_plugin
