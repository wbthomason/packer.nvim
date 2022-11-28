local util = require('packer.util')

local join_paths = util.join_paths

















































local default_config = {
   package_root = join_paths(vim.fn.stdpath('data'), 'site', 'pack'),
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

local function set(_, user_config)
   config = vim.tbl_deep_extend('force', config, user_config or {})
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
   __index = function(_, k)
      return (config)[k]
   end,
   __call = set,
})

return M