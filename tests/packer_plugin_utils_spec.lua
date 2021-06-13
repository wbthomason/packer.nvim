local a = require('plenary.async_lib.tests')
local await = require('packer.async').wait
local plugin_utils = require("packer.plugin_utils")
local packer_path = vim.fn.stdpath("data") .. "/site/pack/packer/start/"

a.describe("Packer post update hooks", function()
  local test_plugin_path = packer_path .. "test_plugin/"
  local run_hook = plugin_utils.post_update_hook

  before_each(function() vim.fn.mkdir(test_plugin_path, "p") end)

  after_each(function() vim.fn.delete(test_plugin_path, "rf") end)

  a.it("should run the command in the correct folder", function()
    local plugin_spec = {
      name = "test/test_plugin",
      install_path = test_plugin_path,
      run = "touch 'this_file_should_exist'"
    }

    await(run_hook(plugin_spec, {task_update = function() end}))

    assert.truthy(vim.loop.fs_stat(test_plugin_path .. "this_file_should_exist"))
  end)
end)
