local a = require('plenary.async_lib.tests')
local await = require('packer.async').wait
local local_plugin = require('packer.plugin_types.local')
local packer_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/'
local helpers = require('tests.helpers')

a.describe('Local plugin -', function()
  a.describe('installer', function()
    local local_plugin_path
    local repo_name = 'test.nvim'
    local plugin_install_path = packer_path .. repo_name

    before_each(function()
      vim.fn.mkdir(packer_path, 'p')
      local_plugin_path = helpers.create_git_dir(repo_name)
    end)

    after_each(function() helpers.cleanup_dirs(local_plugin_path, plugin_install_path) end)

    a.it('should create a symlink', function()
      local plugin_spec = {
        name = local_plugin_path,
        path = local_plugin_path,
        install_path = plugin_install_path
      }

      local_plugin.setup(plugin_spec)
      await(plugin_spec.installer({task_update = function() end}))

      assert.equal('link', vim.loop.fs_lstat(plugin_install_path).type)
    end)
  end)
end)
