local util = require 'packer.util'

local join_paths = util.join_paths
local stdpath = vim.fn.stdpath

--- Default configuration values
local defaults = {
  --- Should `packer` automatically remove plugins which are installed but not specified as managed?
  auto_clean = true,
  --- Should `packer` automatically reload
  auto_reload_compiled = true,
  compile_on_sync = true,
  compile_path = join_paths(stdpath 'config', 'plugin', 'packer_compiled.lua'),
  disable_commands = false,
  display = {
    done_sym = '✓',
    error_sym = '✗',
    header_lines = 2,
    header_sym = '━',
    keybindings = { quit = 'q', toggle_info = '<CR>', diff = 'd', prompt_revert = 'r' },
    moved_sym = '→',
    non_interactive = false,
    open_cmd = '65vnew',
    open_fn = nil,
    prompt_border = 'double',
    removed_sym = '-',
    show_all_info = true,
    title = 'packer.nvim',
    working_sym = '⟳',
  },
  --- Automatically install and manage plugins specified by the `requires` key
  ensure_dependencies = true,
  git = {
    clone_timeout = 60,
    cmd = 'git',
    default_url_format = 'https://github.com/%s.git',
    depth = 1,
    mark_breaking_changes = true,
    subcommands = {
      checkout = 'checkout %s --',
      current_branch = 'rev-parse --abbrev-ref HEAD',
      diff = 'log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD',
      diff_fmt = '%%h %%s (%%cr)',
      fetch = 'fetch --depth 999999 --progress',
      get_bodies = 'log --color=never --pretty=format:"===COMMIT_START===%h%n%s===BODY_START===%b" --no-show-signature HEAD@{1}...HEAD',
      get_header = 'log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1',
      get_rev = 'rev-parse --short HEAD',
      git_diff_fmt = 'show --no-color --pretty=medium %s',
      install = 'clone --depth %i --no-single-branch --progress',
      revert = 'reset --hard HEAD@{1}',
      submodules = 'submodule update --init --recursive --progress',
      update = 'pull --ff-only --progress --rebase=false',
      update_branch = 'merge --ff-only @{u}',
    },
  },
  log = { level = 'warn' },
  luarocks = { python_cmd = 'python' },
  max_jobs = nil,
  opt_default = false,
  package_root = join_paths(stdpath 'data', 'site', 'pack'),
  plugin_package = 'packer',
  profile = { enable = false },
  transitive_disable = true,
  transitive_opt = true,
}
