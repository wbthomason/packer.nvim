package.loaded['packer.util'] = nil
package.loaded['packer.neorocks'] = nil
package.loaded['packer.window'] = nil

local a      = require('packer.async')
local jobs   = require('packer.jobs')
local log    = require('packer.log')
local result = require('packer.result')
local util   = require('packer.util')
local window = require('packer.window')

local await = a.wait
local async = a.sync

local neorocks = {}

--- Location of hererocks.py
neorocks._hererocks_file = util.join_paths(vim.fn.stdpath('cache'), 'hererocks.py')

--- Determine the location where neorcks should install a particular version of lua
---
---@param lua_version table The lua version table
neorocks._hererocks_install_location = function(lua_version)
  return util.join_paths(vim.fn.stdpath('cache'), 'neorocks_install', lua_version.dir)
end

--- Determine if the hererocks environment is usable for nvim
---
---@return boolean True if the hererocks environment is already set up
neorocks.is_setup = function()
  local lua_version = neorocks.get_lua_version()
  local install_location = neorocks._hererocks_install_location(lua_version)

  if vim.fn.isdirectory(vim.fn.fnamemodify(util.join_paths(install_location, "lib"), ":p")) > 0 then
    return true
  else
    return false
  end
end

neorocks.get_hererocks = async(function()
  local url_loc = 'https://raw.githubusercontent.com/luarocks/hererocks/latest/hererocks.py'

  local cmd
  if vim.fn.executable('curl') > 0 then
    cmd = string.format(
      'curl %s -o %s',
      url_loc,
      util.absolute_path(neorocks._hererocks_file)
    )
  elseif vim.fn.executable('wget') > 0 then
    cmd = string.format(
      'wget %s -O %s --verbose',
      url_loc,
      util.absolute_path(neorocks._hererocks_file)
    )
  end

  local win, buf = window.percentage_range_window(0.8, 0.8)

  local function stdout_capture(err, data)
    if data ~= nil then
      vim.schedule_wrap(function()
        log.info(string.format("DATA: %s", data))
        for k, v in ipairs(vim.split(data, "\n")) do
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, {v})
        end
      end)()
    end
  end

  local opts = { capture_output = { stdout = stdout_capture, stderr = stdout_capture } }
  -- local opts = { capture_output = true }
  local r = result.ok(true)
  return r:and_then(
      await, jobs.run(cmd, opts)
    ):map_err(
      function(err)
        return {
          msg = "Failed to get hererocks",
          data = err
        }
      end
    ):map_ok(
      function(ok)
        return {
          status = ok,
          -- TODO: Figure out what we should be doing with the output
          -- output = output
        }
      end
    )


  -- TODO: Delete this, I don't think we need it anymore
  -- -- Just make sure to wait til we can actually read the file.
  -- -- Sometimes the job exists before we get a chacne to do so.
  -- vim.wait(10000, function() return vim.fn.filereadable(neorocks._hererocks_file:absolute()) ~= 0 end)
  -- vim.fn.input("[Press enter to continue]")
  -- print("All done....")
  -- win_float.clear(run_buf)
end)


--- Get the current lua version running right now.
---
---@return table Of the form: {
---     lua: Lua Version (5.1, 5.2, etc.)
---     jit: Jit Version (2.1.0-beta3, or nil)
---     dir: Directory of hererocks installation
--- }
---
neorocks.get_lua_version = function()
  if jit then
    return {
      lua = string.gsub(_VERSION, "Lua ", ""),
      jit = string.gsub(jit.version, "LuaJIT ", ""),
      dir = string.gsub(jit.version, "LuaJIT ", "")
    }
  end

  error("NEOROCKS: Unsupported Lua Versions", _VERSION)
end

return neorocks
