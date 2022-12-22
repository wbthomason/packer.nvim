local util = require 'packer.util'

local join_paths = util.join_paths

local record Config
  record Display
    non_interactive : boolean
    prompt_border   : string
    working_sym     : string
    error_sym       : string
    done_sym        : string
    removed_sym     : string
    moved_sym       : string
    item_sym        : string
    header_sym      : string
    keybindings     : {string: string|{string}}
  end

  record Git
    cmd                   : string
    depth                 : integer
    clone_timeout         : integer
    default_url_format    : string
  end

  record Log
    enum Level
      'trace' 'debug' 'info' 'warn' 'error' 'fatal'
    end
    level: Level
  end

  record Lockfile
    path: string
  end

  package_root    : string
  pack_dir        : string
  max_jobs        : integer
  start_dir       : string
  opt_dir         : string
  auto_clean      : boolean
  autoremove      : boolean
  display         : Display
  git             : Git
  log             : Log
  lockfile        : Lockfile

  Config: Config

  metamethod __call: function(Config, Config): Config
end

local default_config: Config = {
  package_root = join_paths(vim.fn.stdpath 'data', 'site', 'pack'),
  max_jobs = nil,
  auto_clean = true,
  git = {
    cmd = 'git',
    depth = 1,
    clone_timeout = 60,
    default_url_format = 'https://github.com/%s.git',
  },
  display = {
    non_interactive = false,
    working_sym = '⟳',
    error_sym = '✗',
    done_sym = '✓',
    removed_sym = '-',
    moved_sym = '→',
    item_sym = '•',
    header_sym = '━',
    prompt_border = 'double',
    keybindings = {
      quit = 'q',
      toggle_info = {'za', '<CR>'},
      diff = 'd',
      prompt_revert = 'r',
    },
  },
  log = { level = 'info' },
  lockfile = {
    path = util.join_paths(vim.fn.stdpath 'config', 'packer', 'lockfile.lua')
  },
  autoremove = false,
}

local config = vim.deepcopy(default_config)

local function set(_, user_config: Config): Config
  config = vim.tbl_deep_extend('force', config, user_config or {}) as Config
  config.package_root = vim.fn.fnamemodify(config.package_root, ':p')
  config.package_root = config.package_root:gsub(util.get_separator() .. '$', '', 1)
  config.pack_dir = join_paths(config.package_root, 'packer')
  config.opt_dir = join_paths(config.pack_dir, 'opt')
  config.start_dir = join_paths(config.pack_dir, 'start')

  if #vim.api.nvim_list_uis() == 0 then
    config.display.non_interactive = true
  end

  return config
end

local M = {}

setmetatable(M, {
  __index = function(_, k: string): any
    return (config as table)[k]
  end,
  __call = set
})

return M as Config
