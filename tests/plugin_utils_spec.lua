local a = require('plenary.async_lib.tests')
local await = require('packer.async').wait
local async = require('packer.async').sync
local plugin_utils = require('packer.plugin_utils')
local helpers = require("tests.helpers")

local fmt = string.format

a.describe('Plugin utils -', function()

  a.describe('find_missing_plugins', function()
    local repo_name = "test.nvim"
    local path

    plugin_utils.cfg({start_dir = helpers.base_dir})

    before_each(function() path = helpers.create_git_dir(repo_name) end)

    after_each(function() helpers.cleanup_dirs("tmp/packer") end)

    a.it('should pick up plugins with a different remote URL', function()
      local test_repo_name = fmt('user2/%s', repo_name)
      local plugins = {
        [repo_name] = {
          opt = false,
          type = "git",
          name = fmt("user1/%s", repo_name),
          short_name = repo_name,
          remote_url = function()
            return async(function()
              return {ok = {remote = fmt('https://github.com/%s', test_repo_name)}}
            end)
          end
        }
      }
      local result = await(plugin_utils.find_missing_plugins(plugins, {}, {[path] = true}))
      assert.truthy(result)
      assert.equal(1, #vim.tbl_keys(result))
    end)

    a.it('should not pick up plugins with the same remote URL', function()
      local test_repo_name = fmt('user1/%s', repo_name)
      local plugins = {
        [repo_name] = {
          opt = false,
          type = "git",
          name = test_repo_name,
          short_name = repo_name,
          remote_url = function()
            return async(function()
              return {ok = {remote = fmt('https://github.com/%s', test_repo_name)}}
            end)
          end
        }
      }
      local result = await(plugin_utils.find_missing_plugins(plugins, {}, {[path] = true}))
      assert.truthy(result)
      assert.equal(0, #result)
    end)

    a.it('should handle ssh git urls', function()
      local test_repo_name = fmt('user2/%s', repo_name)
      local plugins = {
        [repo_name] = {
          opt = false,
          type = "git",
          name = fmt("user1/%s", repo_name),
          short_name = repo_name,
          remote_url = function()
            return async(function()
              return {ok = {remote = fmt('git@github.com:%s.git', test_repo_name)}}
            end)
          end
        }
      }
      local result = await(plugin_utils.find_missing_plugins(plugins, {}, {[path] = true}))
      assert.truthy(result)
      assert.equal(1, #vim.tbl_keys(result))
    end)
  end)
end)
