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

---@return table Of the form: {
---     lua: Lua Version (5.1, 5.2, etc.)
---     jit: Jit Version (2.1.0-beta3, or nil)
---     dir: Directory of hererocks installation
--- }
neorocks._lua_version = (function()
  if jit then
    return {
      lua = string.gsub(_VERSION, "Lua ", ""),
      jit = string.gsub(jit.version, "LuaJIT ", ""),
      dir = string.gsub(jit.version, "LuaJIT ", "")
    }
  end

  error("NEOROCKS: Unsupported Lua Versions", _VERSION)
end)()

neorocks._base_path = util.join_paths(vim.fn.stdpath('cache'), 'packer_hererocks')
neorocks._hererocks_file = util.join_paths(vim.fn.stdpath('cache'), 'hererocks.py')
neorocks._hererocks_install_location = util.join_paths(neorocks._base_path, neorocks._lua_version.dir)
neorocks._is_setup = vim.fn.isdirectory(util.join_paths(neorocks._hererocks_install_location, "lib")) > 0

--- Determine if the hererocks environment is usable for nvim
---
---@return boolean True if the hererocks environment is already set up
neorocks.is_setup = function()
  return neorocks._is_setup
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
  else
    error('"curl" or "wget" is required to install hererocks')
  end

  local r = result.ok(true)
  return r:and_then(
      await, jobs.run(cmd, {})
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
end)

--- Handle the set up of luarocks
neorocks.setup_hererocks = async(function(force)
  if force == nil then
    force = false
  end

  local r = result.ok(true)
  if not util.path_exists(neorocks._hererocks_file) then
    r:and_then(await, neorocks.get_hererocks)
  end

  if neorocks.is_setup() and not force then
    return
  end


  local cmd
  if neorocks._lua_version.jit then
    cmd = string.format(
      "python %s --verbose -j %s -r %s %s",
      neorocks._hererocks_file,
      neorocks._lua_version.jit,
      "latest",
      neorocks._hererocks_install_location
    )
  else
    error("Only works for lua jit right now")
  end

  local opts = {capture_output = jobs.floating_term_table(nil, nil, "Luarocks Installation")}
  -- local opts = {}

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
        neorocks._is_setup = true

        return {
          status = ok,
          -- TODO: Figure out what we should be doing with the output
          -- output = output
        }
      end
    )
end)

neorocks._get_package_paths = function()
  local lua_version = neorocks._lua_version
  local install_location = neorocks._hererocks_install_location

  local install_path = util.join_paths(
    install_location,
    "lib",
    "luarocks",
    string.format("rocks-%s", lua_version.lua)
  )

  local share_path = util.join_paths(
    install_location,
    "share",
    "lua",
    lua_version.lua
  )

  local gen_pattern = function(directory)
    return string.format(
    "%s/?.lua;%s/&/init.lua",
    directory,
    directory
  )
  end

  return gen_pattern(share_path) .. ';' .. gen_pattern(install_path)
end

neorocks.setup_paths = function(force)
  local lua_version = neorocks._lua_version
  local install_location = neorocks._hererocks_install_location

  local match_install_path = neorocks._get_package_paths()

  if force or not string.find(package.path, match_install_path, 1, true) then
    package.path = match_install_path .. ';' .. package.path
  end

  local install_cpath = util.join_paths(install_location, "lib", "lua", lua_version.lua)
  local match_install_cpath = string.format("%s/?.so", install_cpath)

  if force or not string.find(package.cpath, match_install_cpath, 1, true) then
    package.cpath = match_install_cpath .. ';' .. package.cpath
  end
end

neorocks.get_async_installer = function(rocks)
  return async(function()
    -- TODO: This might be a good thing to include in nvim generally?
    local original_exit = os.exit
    os.exit = function(...)
      print('LUAROCKS EXIT: ', ...)
    end

    local file_redirect = function(prefix)
      return setmetatable(
        { write = function(t, ...) print(prefix, ...) end },
        { __call = function(t,...) t:write(...) end })
    end

    local real_stdout = io.stdout
    io.stdout = file_redirect("STDOUT:")

    local real_stderr = io.stderr
    io.stderr = file_redirect("STDERR:")

    local real_print = print
    -- print = file_redirect("PRINT:")

    print("starting...\n")

    -- Install the package
    loadfile(util.join_paths(neorocks._hererocks_install_location, "bin", "luarocks"))('install', rocks[1])

    print("... Done\n")

    io.stdout = real_stdout
    io.stderr = real_stderr
    print = real_print
    os.exit = original_exit

    -- print("yoooo", vim.inspect(rocks[1]))
    -- require('luarocks.cmd.install').command(rocks[1])
    -- print(".... Finish")
  end)
end

return neorocks
