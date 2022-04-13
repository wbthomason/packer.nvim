--- Configuration

local util = require 'packer.util'
local join_paths = util.join_paths
local stdpath = vim.fn.stdpath

local defaults = {
  ensure_dependencies = true,
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
  log = { level = 'warn' },
  profile = { enable = false },
}

local M = {}
M.config = {}
function M.configure(user_config)
  user_config = user_config or {}
  local config = M.config
  vim.tbl_deep_extend('force', defaults, user_config)
  config.package_root = string.gsub(vim.fn.fnamemodify(config.package_root, ':p'), util.get_separator() .. '$', '', 1)
  config.pack_dir = join_paths(config.package_root, config.plugin_package)
  config.opt_dir = join_paths(config.pack_dir, 'opt')
  config.start_dir = join_paths(config.pack_dir, 'start')
  config.display.non_interactive = #vim.api.nvim_list_uis() == 0
  return M.config
end

return M
