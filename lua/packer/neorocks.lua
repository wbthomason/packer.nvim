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

-- activate hererocks based on current $SHELL
local function source_activate(install_location, activate_file)
  return string.format('source %s', util.join_paths(install_location, 'bin', activate_file))
end

neorocks._source_string = function(install_location)
  local user_shell = os.getenv("SHELL")
  local shell = user_shell:gmatch("([^/]*)$")()
  if shell == "fish" then
    return source_activate(install_location, 'activate.fish')
  elseif shell == "csh" then
    return source_activate(install_location, 'activate.csh')
  end
  return source_activate(install_location, 'activate')
end

-- neorocks.get_async_installer = function(rocks, plugin_name, display)
--   return async(function(self)
    -- local new_env = setmetatable({}, {
    --   __index = function(t, k)
    --     local val
    --     if k == 'io' then
    --       val = setmetatable({
    --         stdout = { write = function(_, s) display:task_update(plugin_name, string.format('stdout: %s', s)) end, },
    --         stderr = { write = function(_, s) display:task_update(plugin_name, string.format('stderr: %s', s)) end, },
    --       }, { __index = function() error('ACCESSING IO') end })
    --     elseif k == 'os' then
    --       val = setmetatable({exit = function() error('OS.EXIT') end}, {__index = os})
    --     elseif k == 'print' then
    --       val = function(...)
    --         display:task_update(plugin_name, vim.inspect({...}))
    --       end
    --     else
    --       val = _G[k]
    --     end

    --     t[k] = val
    --     return t[k]
    --   end
    -- })

    -- -- Install the package
    -- local exec_luarocks = loadfile(util.join_paths(neorocks._hererocks_install_location, "bin", "luarocks"))
    -- -- Redirect io.stdout & io.stderr
    -- setfenv(exec_luarocks, new_env)('install', rocks[1])

    -- TODO: I would really like to go back to the loadfile method and not shoot this out to a shell...
    --          I'm worried about trying to compile multiple of these at the same time.
    -- TODO: move to io.popen, so we can pipe the output to the display
    -- vim.schedule_wrap(function()
      -- TODO: Figure out how we could queue up these lua rocks commands to do in job start
      --        so they don't happen in parallel.
      --        Until then, let's do them synchronously, so that they can't mess each other up.
      -- local result = vim.fn.systemlist(string.format(
      --   "%s && %s install %s",
      --   neorocks._source_string(neorocks._hererocks_install_location),
      --   util.join_paths(neorocks._hererocks_install_location, "bin", "luarocks"),
      --   rocks[1]
      -- ))

      -- -- In a second we'll try putting it in the floaty window
      -- print(vim.inspect(result))
    -- end)()

    -- return self
  -- end)
-- end

neorocks.install_rocks = function(rocks)
  return async(function()
    await(neorocks.setup_hererocks)

    local r = result.ok(true)
    local opts = {capture_output = jobs.floating_term_table(nil, nil, "Luarocks Installation")}
    print(string.format(
                "bash -c '%s && %s install %s'",
                neorocks._source_string(neorocks._hererocks_install_location),
                util.join_paths(neorocks._hererocks_install_location, "bin", "luarocks"),
                'lua-cjson'
              ))

    local install_outputs = {}
    for _, v in ipairs(rocks) do
      -- install_outputs[v] = vim.fn.systemlist(string.format(
      -- TODO: Fix for windows... sorry windows ppl
      -- TODO: Fix for if you don't have bash...
      -- TODO: Fix to run async etc.
      r = r:and_then(await, jobs.run(
              {
                'bash',
                '-c',
                string.format(
                  "%s && %s install %s",
                  neorocks._source_string(neorocks._hererocks_install_location),
                  util.join_paths(neorocks._hererocks_install_location, "bin", "luarocks"),
                  v
                )
              }, opts)
            ):map_ok(
              function(ok)
                install_outputs[v] = true
                return {status = ok}
              end
            ):map_err(
              function(err)
                install_outputs[v] = false
                print("ERROR: ", vim.inspect(err))
              end
            )

    end

    local failed = {}
    for name, v in pairs(install_outputs) do
      if not v then table.insert(failed, name) end
    end

    -- In a second we'll try putting it in the floaty window
    if vim.tbl_isempty(failed) then
      log.info("Successfully installed all luarocks deps")
      print(string.format(vim.inspect(install_outputs)))
    else
      -- TODO: Should probably make this error more apparent and give them the infos they need
      print(string.format("Failed to install luarocks deps: %s", vim.inspect(failed)))
    end
  end)
end

return neorocks
