-- Add support for installing and cleaning Luarocks dependencies
-- Based originally off of plenary/neorocks/init.lua in https://github.com/nvim-lua/plenary.nvim
local a = require('packer.async')
local jobs = require('packer.jobs')
local log = require('packer.log')
local result = require('packer.result')
local util = require('packer.util')

local fmt = string.format
local async = a.sync
local await = a.wait

local lua_version = nil
if jit then
  local jit_version = string.gsub(jit.version, 'LuaJIT ', '')
  lua_version = {lua = string.gsub(_VERSION, 'Lua ', ''), jit = jit_version, dir = jit_version}
end

local cache_path = vim.fn.stdpath('cache')
local rocks_path = util.join_paths(cache_path, 'packer_hererocks')
local hererocks_file = util.join_paths(cache_path, 'hererocks.py')
local hererocks_install_dir = util.join_paths(rocks_path, lua_version.dir)
local function hererocks_is_setup()
  return vim.fn.isdirectory(util.join_paths(hererocks_install_dir, 'lib')) > 0
end

local function hererocks_installer(disp)
  return async(function()
    local hererocks_url = 'https://raw.githubusercontent.com/luarocks/hererocks/latest/hererocks.py'
    local command
    if vim.fn.executable('curl') > 0 then
      command = 'curl ' .. hererocks_url .. ' -o ' .. hererocks_file
    elseif vim.fn.executable('wget') > 0 then
      command = 'wget ' .. hererocks_url .. ' -O ' .. hererocks_file .. ' --verbose'
    else
      return result.err('"curl" or "wget" is required to install hererocks')
    end

    local r = result.ok()
    if disp ~= nil then disp:task_update('luarocks', 'installing hererocks...') end

    local output = jobs.make_output_table()
    local callbacks = {
      stdout = jobs.logging_callback(output.err.stdout, output.data.stdout, nil, disp, 'luarocks'),
      stderr = jobs.logging_callback(output.err.stderr, output.data.stderr)
    }

    local opts = {capture_output = callbacks}
    return r:and_then(await, jobs.run(command, opts)):map_err(
    function(err)
      return {msg = 'Error installing hererocks', data = err, output = output}
    end)
  end)
end

local function package_patterns(dir) return fmt('%s?.lua;%s&/init.lua', dir, dir) end
local package_paths = (function()
  local install_path = util.join_paths(hererocks_install_dir, 'lib', 'luarocks',
  fmt('rocks-%s', lua_version.lua))
  local share_path = util.join_paths(hererocks_install_dir, 'share', 'lua', lua_version.lua)
  return package_patterns(share_path) .. ';' .. package_patterns(install_path)
end)()

local nvim_paths_are_setup = false
local function setup_nvim_paths()
  if not hererocks_is_setup() then
    log.warning('Tried to setup Neovim Lua paths before hererocks was setup!')
    return
  end

  if nvim_paths_are_setup then
    log.warning('Tried to setup Neovim Lua paths redundantly!')
    return
  end

  if not string.find(package.path, package_paths, 1, true) then
    package.path = package.path .. ';' .. package_paths
  end

  local install_cpath = util.join_paths(hererocks_install_dir, 'lib', 'lua', lua_version.lua)
  local install_cpath_pattern = fmt('%s?.so', install_cpath)
  if not string.find(package.cpath, install_cpath_pattern, 1, true) then
    package.cpath = package.cpath .. ';' .. install_cpath_pattern
  end

  nvim_paths_are_setup = true
end

local function activate_hererocks_cmd(install_path)
  local activate_file = 'activate'
  local user_shell = os.getenv('SHELL')
  local shell = user_shell:gmatch('([^/]*)$')()
  if shell == 'fish' then
    activate_file = 'activate.fish'
  elseif shell == 'csh' then
    activate_file = 'activate.csh'
  end

  return fmt('source %s', util.join_paths(install_path, 'bin', activate_file))
end

local function run_luarocks(args, disp)
  local cmd = {
    os.getenv('SHELL'), '-c',
    fmt('%s && luarocks %s', activate_hererocks_cmd(hererocks_install_dir), args)
  }
  return async(function()
    local output = jobs.make_output_table()
    local callbacks = {
      stdout = jobs.logging_callback(output.err.stdout, output.data.stdout, nil, disp, 'luarocks'),
      stderr = jobs.logging_callback(output.err.stderr, output.data.stderr)
    }

    local opts = {capture_output = callbacks}
    local r = result.ok()
    return r:and_then(await, jobs.run(cmd, opts)):map_err(
    function(err)
      return {msg = fmt('Error running luarocks %s', args), data = err, output = output}
    end):map_ok(function(data) return {data = data, output = output} end)
  end)
end

local function luarocks_install(package, disp)
  return async(function()
    local r = await(hererocks_installer(disp))
    return r.and_then(await, run_luarocks('install ' .. package, disp))
  end)
end

local function install_packages(packages, disp)
  return async(function()
    if not hererocks_is_setup() then return result.ok() end
    local r = result.ok()
    for _, name in ipairs(packages) do
      r = r.and_then(await, luarocks_install(name, disp))
    end

    return r
  end)
end

local function luarocks_list(disp)
  return async(function()
    if not hererocks_is_setup() then return result.ok({}) end
    local r = await(run_luarocks('list --porcelain', disp))
    return r.map_ok(function(data)
      local results = {}
      for _, line in ipairs(data.output.stdout) do
        for l_package, version, status, install_path in string.gmatch(line, "([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)") do
          table.insert(results, {
            name = l_package,
            version = version,
            status = status,
            install_path = install_path
          })
        end
      end

      return results
    end)
  end)
end

local function luarocks_remove(package, disp)
  return async(function()
    if not hererocks_is_setup() then return result.ok() end
    return await(run_luarocks('remove ' .. package, disp))
  end)
end

local function uninstall_packages(packages, disp)
  return async(function()
    if not hererocks_is_setup() then return result.ok() end
    local r = result.ok()
    for _, name in ipairs(packages) do
      r = r.and_then(await, luarocks_remove(name, disp))
    end

    return r
  end)
end

local function clean_packages(plugins, disp)
  return async(function()
    if not hererocks_is_setup() then return result.ok() end
    local r = await(luarocks_list(disp))
    r = r.map_ok(function(installed_packages)
      local to_remove = {}
      for _, package in ipairs(installed_packages) do
        to_remove[package.name] = package
      end

      for _, plugin in pairs(plugins) do
        if plugin.rocks then
          for _, rock in ipairs(plugin.rocks) do
            if type(rock) == 'table'  then
              if to_remove[rock[1]] and to_remove[rock[1]].version == rock[2] then
                to_remove[rock[1]] = nil
              end
            else
              to_remove[rock] = nil
            end
          end
        end
      end

      return vim.tbl_keys(to_remove)
    end)

    return r.and_then(await, uninstall_packages(r.ok, disp))
  end)
end

local function ensure_packages(plugins, disp)
  return async(function()
    if not hererocks_is_setup() then return result.ok() end
    local r = await(luarocks_list(disp))
    r = r.map_ok(function(installed_packages)
      local to_install = {}
      for _, plugin in pairs(plugins) do
        if plugin.rocks then
          for _, rock in ipairs(plugin.rocks) do
            if type(rock) == 'table' then
              to_install[rock[1]] = rock
            else
              to_install[rock] = true
            end
          end
        end
      end

      for _, package in ipairs(installed_packages) do
        local spec = to_install[package.name]
        if spec then
          if type(spec) == 'table' then
            if  spec[2] == package.version then
              to_install[package.name] = nil
            end
          else
            to_install[package.name] = nil
          end
        end
      end

      local package_names = {}
      for name, data in pairs(to_install) do
        if type(data) == 'table' then
          table.insert(package_names, fmt('%s %s', name, data[2]))
        else
          table.insert(package_names, name)
        end
      end

      return package_names
    end)

    return r.and_then(await, install_packages(r.ok, disp))
  end)
end

-- TODO: Add logic to compiler to output necessary path modifications

return {
  list = luarocks_list,
  install_hererocks = hererocks_installer,
  setup_paths = setup_nvim_paths,
  uninstall = uninstall_packages,
  clean = clean_packages,
  install = install_packages,
  ensure = ensure_packages
}
