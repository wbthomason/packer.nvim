--- Support for fine-grained profiling of startup steps
local M = { results = {} }

local function time(name, is_start) end

local profile_data = {}
local hrtime = vim.loop.hrtime
local threshold = nil
require('packer.config').register_hook(function(config)
  threshold = config.profile.threshold
  if config.profile.enable then
    time = function(name, is_start)
      if is_start then
        profile_data[name] = hrtime()
      else
        profile_data[name] = (hrtime() - profile_data[name]) / 1e6
      end
    end
  end
end)

function M.save_profiles()
  M.results = {}
  local sorted_times = {}
  for chunk_name, time_taken in pairs(profile_data) do
    sorted_times[#sorted_times + 1] = { chunk_name, time_taken }
  end

  table.sort(sorted_times, function(a, b)
    return a[2] > b[2]
  end)

  for i, elem in ipairs(sorted_times) do
    if not threshold or threshold and elem[2] > threshold then
      M.results[i] = elem[1] .. ' took ' .. elem[2] .. 'ms'
    end
  end
end

function M.get_profile_data()
  if #M.results == 0 then
    M.save_profiles()
  end

  return M.results
end

function M.timed_run(fn, name, ...)
  time(name, true)
  local success, result = pcall(fn, ...)
  time(name, false)
  if not success then
    vim.schedule(function()
      require('packer.log').error('Failed running ' .. name .. ': ' .. result)
    end)
  end

  return result
end

function M.timed_packadd(name)
  local packadd_cmd = 'packadd ' .. name
  time(packadd_cmd, true)
  vim.cmd(packadd_cmd)
  time(packadd_cmd, false)
end

function M.timed_load(plugins, args)
  local load = require 'packer.load'
  local load_name = 'Loading ' .. vim.inspect(plugins)
  time(load_name, true)
  load(plugins, args)
  time(load_name, false)
end

return M
