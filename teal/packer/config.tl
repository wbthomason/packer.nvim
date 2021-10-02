local util = require 'packer.util'

local join_paths = util.join_paths
local stdpath = vim.fn.stdpath

-- TODO: Move to display module once ported
global record DisplayIds
  window: integer
  buffer: integer
end

global type DisplayOpenerFn = function({string:any}): DisplayIds

--- Config Schema
local record Config
  auto_clean: boolean
  auto_reload_compiled: boolean
  compile_on_sync: boolean
  compile_path: string
  disable_commands: boolean

  record DisplayConfig
    done_sym: string
    error_sym: string
    header_lines: integer
    header_sym: string

    record DisplayKeybindingsConfig
      quit: string
      toggle_info: string
      diff: string
      prompt_revert: string
    end

    keybindings: DisplayKeybindingsConfig
    moved_sym: string
    non_interactive: boolean
    open_cmd: string
    open_fn: DisplayOpenerFn
    prompt_border: string
    removed_sym: string
    show_all_info: boolean
    title: string
    working_sym: string
  end

  display: DisplayConfig

  ensure_dependencies: boolean

  record GitConfig
    clone_timeout: number
    cmd: string
    default_url_format: string
    depth: integer
    mark_breaking_changes: boolean

    record GitSubcommands
      checkout: string
      current_branch: string
      diff: string
      diff_fmt: string
      fetch: string
      get_bodies: string
      get_header: string
      get_rev: string
      git_diff_fmt: string
      install: string
      revert: string
      submodules: string
      update: string
      update_branch: string
    end

    subcommands: GitSubcommands
  end

  git: GitConfig

  record LogConfig
    level: string
  end

  log: LogConfig

  record LuarocksConfig
    python_cmd: string
  end

  luarocks: LuarocksConfig
  max_jobs: integer
  opt_default: boolean
  package_root: string
  plugin_package: string

  record ProfileConfig
    enable: boolean
  end

  profile: ProfileConfig

  transitive_disable: boolean
  transitive_opt: boolean
end

--- Default configuration values
local defaults: Config = {
  auto_clean = true,
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

local config: Config

local function setup(user_config: Config)
  config = util.deep_extend('force', defaults, user_config)
end

-- TODO: Write an __index that checks if config values are valid, makes config read-only
local M = {
  setup = setup,
  config = config
}

return M
