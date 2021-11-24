local before_each = require('plenary.busted').before_each
local path        = require('plenary.path')
local a           = require('plenary.async_lib.tests')
local mocked_plugin_utils = require('packer.plugin_utils')
local log = require('packer.log')

local await       = require('packer.async').wait
local fmt         = string.format
local packer      = require('packer')

local config = {
  snapshot_path = vim.fn.stdpath("cache") .. "/" .. "packer",
  display = {
    non_interactive = true,
    open_cmd = '65vnew \\[packer\\]',
  },
  log = { level = 'trace' }
}

--[[ For testing purposes the spec file is made up so that when running `packer`
it could manage itself as if it was in `~/.local/share/nvim/site/pack/packer/start/` --]]
local install_path = vim.fn.getcwd()

mocked_plugin_utils.list_installed_plugins = function ()
  return {[install_path] = true}, {}
end

local old_require = _G.require

_G.require = function (modname)
  if modname == 'plugin_utils' then
    return mocked_plugin_utils
  end

  return old_require(modname)
end

local spec = {'wbthomason/packer.nvim'}

local cache_path = path:new(config.snapshot_path)
vim.fn.mkdir(tostring(cache_path), "p")

a.describe('Packer testing ', function ()
  local snapshot_name = "test"
  local test_path = path:new(config.snapshot_path .. "/" .. snapshot_name)
  local snapshot = require 'packer.snapshot'

  before_each(function ()
    packer.reset()
    packer.init(config)
    packer.use(spec)
    packer.__manage_all()
    spec.install_path = install_path
  end)

  after_each(function ()
    spec = {'wbthomason/packer.nvim'}
    spec.install_path = install_path
  end)

  a.describe('packer.snapshot()', function ()
    a.it(fmt("create snapshot in '%s'", test_path), function ()
      await(snapshot(tostring(test_path), {spec}))
      assert.True(test_path:exists())
    end)

    a.it("checking if snapshot content corresponds to plugins'", function ()
      local snapshotted_plugins = dofile(tostring(test_path))
      log.debug(vim.inspect(snapshotted_plugins))
      local expected_rev = await(spec.get_rev())
      assert.are.equals(expected_rev, snapshotted_plugins["packer.nvim"].commit)
    end)
  end)

  a.describe('packer.rollback()', function ()
    a.it(fmt("restore 'packer' to the commit saved in '%s' snapshot", snapshot_name), function ()
      packer.rollback(snapshot_name)
      log.debug(fmt("spec = %s", vim.inspect(spec)))
      local snapshotted_plugins = dofile(tostring(test_path))
      assert.are.equals(snapshotted_plugins["packer.nvim"].commit, spec.commit)
    end)
  end)

  a.describe("packer.delete()", function ()
    a.it(fmt("delete '%s' snapshot", snapshot_name), function ()
      packer.delete(snapshot_name)
      assert.False(test_path:exists())
    end)
  end)
end)