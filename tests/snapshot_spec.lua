local before_each = require('plenary.busted').before_each
local a = require 'plenary.async_lib.tests'
local util = require 'packer.util'
local mocked_plugin_utils = require 'packer.plugin_utils'
local log = require 'packer.log'
local async = require('packer.async').sync
local await = require('packer.async').wait
local wait_all = require('packer.async').wait_all
local main = require('packer.async').main
local packer = require 'packer'
local jobs = require 'packer.jobs'
local git = require 'packer.plugin_types.git'
local join_paths = util.join_paths
local stdpath = vim.fn.stdpath
local fmt = string.format

local config = {
  ensure_dependencies = true,
  snapshot = nil,
  snapshot_path = join_paths(stdpath 'cache', 'packer.nvim'),
  package_root = join_paths(stdpath 'data', 'site', 'pack'),
  compile_path = join_paths(stdpath 'config', 'plugin', 'packer_compiled.lua'),
  plugin_package = 'packer',
  max_jobs = nil,
  auto_clean = true,
  compile_on_sync = true,
  disable_commands = false,
  opt_default = false,
  transitive_opt = true,
  transitive_disable = true,
  auto_reload_compiled = true,
  git = {
    mark_breaking_changes = true,
    cmd = 'git',
    subcommands = {
      update = 'pull --ff-only --progress --rebase=false',
      install = 'clone --depth %i --no-single-branch --progress',
      fetch = 'fetch --depth 999999 --progress',
      checkout = 'checkout %s --',
      update_branch = 'merge --ff-only @{u}',
      current_branch = 'rev-parse --abbrev-ref HEAD',
      diff = 'log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD',
      diff_fmt = '%%h %%s (%%cr)',
      git_diff_fmt = 'show --no-color --pretty=medium %s',
      get_rev = 'rev-parse --short HEAD',
      get_header = 'log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1',
      get_bodies = 'log --color=never --pretty=format:"===COMMIT_START===%h%n%s===BODY_START===%b" --no-show-signature HEAD@{1}...HEAD',
      submodules = 'submodule update --init --recursive --progress',
      revert = 'reset --hard HEAD@{1}',
      revert_to = 'reset --hard %s --',
    },
    depth = 1,
    clone_timeout = 60,
    default_url_format = 'https://github.com/%s.git',
  },
  display = {
    non_interactive = false,
    open_fn = nil,
    open_cmd = '65vnew',
    working_sym = '⟳',
    error_sym = '✗',
    done_sym = '✓',
    removed_sym = '-',
    moved_sym = '→',
    header_sym = '━',
    header_lines = 2,
    title = 'packer.nvim',
    show_all_info = true,
    prompt_border = 'double',
    keybindings = { quit = 'q', toggle_info = '<CR>', diff = 'd', prompt_revert = 'r' },
  },
  luarocks = { python_cmd = 'python' },
  log = { level = 'trace' },
  profile = { enable = false },
}

git.cfg(config)

--[[ For testing purposes the spec file is made up so that when running `packer`
it could manage itself as if it was in `~/.local/share/nvim/site/pack/packer/start/` --]]
local install_path = vim.fn.getcwd()

mocked_plugin_utils.list_installed_plugins = function()
  return { [install_path] = true }, {}
end

local old_require = _G.require

_G.require = function(modname)
  if modname == 'plugin_utils' then
    return mocked_plugin_utils
  end

  return old_require(modname)
end

local spec = { 'wbthomason/packer.nvim' }

local snapshotted_plugins = {}
a.describe('Packer testing ', function()
  local snapshot_name = 'test'
  local test_path = join_paths(config.snapshot_path, snapshot_name)
  local snapshot = require 'packer.snapshot'
  snapshot.cfg(config)

  before_each(function()
    packer.reset()
    packer.init(config)
    packer.use(spec)
    packer.__manage_all()
  end)

  after_each(function()
    spec = { 'wbthomason/packer.nvim' }
    spec.install_path = install_path
  end)

  a.describe('snapshot.create()', function()
    a.it(fmt("create snapshot in '%s'", test_path), function()
      local result = await(snapshot.create(test_path, { spec }))
      local stat = vim.loop.fs_stat(test_path)
      assert.truthy(stat)
    end)

    a.it("checking if snapshot content corresponds to plugins'", function()
      async(function()
        local file_content = vim.fn.readfile(test_path)
        snapshotted_plugins = vim.fn.json_decode(file_content)
        local expected_rev = await(spec.get_rev())
        assert.are.equals(expected_rev.ok, snapshotted_plugins['packer.nvim'].commit)
      end)()
    end)
  end)

  a.describe('packer.delete()', function()
    a.it(fmt("delete '%s' snapshot", snapshot_name), function()
      snapshot.delete(snapshot_name)
      local stat = vim.loop.fs_stat(test_path)
      assert.falsy(stat)
    end)
  end)

  a.describe('packer.rollback()', function()
    local rollback_snapshot_name = 'rollback_test'
    local rollback_test_path = join_paths(config.snapshot_path, rollback_snapshot_name)
    local prev_commit_cmd = 'git rev-parse --short HEAD~5'

    local opts = { capture_output = true, cwd = spec.install_path, options = { env = git.job_env } }

    a.it("restore 'packer' to the commit hash HEAD~5", function()
      async(function()
        local r = await(jobs.run(prev_commit_cmd, opts))
        _, snapshotted_plugins['packer.nvim'].commit = next(r.ok.output.data.stdout)
        await(main)
        local encoded_json = vim.fn.json_encode(snapshotted_plugins)
        vim.fn.writefile({ encoded_json }, rollback_test_path)
        -- wait_all(snapshot.rollback(rollback_test_path, {spec}))
        local job = snapshot.rollback(rollback_test_path, { spec })
        await(job[1])
        local rev = await(spec.get_rev())
        assert.are.equals(snapshotted_plugins['packer.nvim'].commit, rev.ok)
      end)()
    end)
  end)
end)
