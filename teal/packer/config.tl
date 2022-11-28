local util = require 'packer.util'

local join_paths = util.join_paths

local record Config
  record Display
    open_cmd        : string
    preview_updates : boolean
    non_interactive : boolean
    prompt_border   : string
    working_sym     : string
    error_sym       : string
    done_sym        : string
    removed_sym     : string
    moved_sym       : string
    item_sym        : string
    header_sym      : string
    show_all_info   : boolean
    keybindings     : {string: string}
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

  package_root    : string
  pack_dir        : string
  max_jobs        : integer
  start_dir       : string
  opt_dir         : string
  preview_updates : boolean
  auto_clean      : boolean
  autoremove      : boolean
  display         : Display
  git             : Git
  log             : Log

  Config: Config

  metamethod __call: function(Config, Config): Config
end

local default_config: Config = {
  package_root = join_paths(vim.fn.stdpath 'data', 'site', 'pack'),
  max_jobs = nil,
  auto_clean = true,
  preview_updates = false,
  git = {
    cmd = 'git',
    depth = 1,
    clone_timeout = 60,
    default_url_format = 'https://github.com/%s.git',
  },
  display = {
    non_interactive = false,
    open_cmd = '65vnew',
    working_sym = '⟳',
    error_sym = '✗',
    done_sym = '✓',
    removed_sym = '-',
    moved_sym = '→',
    item_sym = '•',
    header_sym = '━',
    show_all_info = true,
    prompt_border = 'double',
    keybindings = {
      quit = 'q',
      toggle_update = 'u',
      continue = 'c',
      toggle_info = '<CR>',
      diff = 'd',
      prompt_revert = 'r',
      retry = 'R',
    },
  },
  log = { level = 'warn' },
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
