local vim = vim
local api = vim.api

local display = {}
local config = {
  keymaps = {
    -- TODO: Stop running jobs on quit
    { 'n', 'q', ':q!<cr>', { nowait = true, silent = true } }
  }
}

local display_mt = {
  task_start = function(self, plugin, task)
    vim.fn.appendbufline(self.buf, config.header_lines, vim.fn.printf('%s %s %s...', config.working_sym, task, plugin))
    self.marks[plugin] = api.nvim_buf_set_extmark(self.buf, self.ns, 0, config.header_lines + 1, 0, {})
  end,

  task_succeeded = function(self, plugin, task)
    local line, _ = api.nvim_buf_get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    vim.fn.setbufline(self.buf, line[1], vim.fn.printf('%s %s %s', config.done_sym, task, plugin))
    api.nvim_buf_del_extmark(self.buf, self.ns, self.marks[plugin])
    self.marks[plugin] = nil
  end,

  task_failed = function(self, plugin, task)
    local line, _ = api.nvim_buf_get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    vim.fn.setbufline(self.buf, line[1], vim.fn.printf('%s %s %s', config.error_sym, task, plugin))
    api.nvim_buf_del_extmark(self.buf, self.ns, self.marks[plugin])
    self.marks[plugin] = nil
  end,

  final_results = function(self, installs, updates, removals, time)
    api.nvim_buf_set_lines(self.buf, 0, -1, false, {})
    local headline = config.title .. ' - finished in ' .. time .. 's'
    local width = api.nvim_win_get_width(0)
    local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
    vim.fn.setbufline(self.buf, 1, string.rep(' ', pad_width) .. headline)
    vim.fn.appendbufline(self.buf, 1, ' ' .. string.rep(config.header_sym, width - 2))

    if removals then
      for _, plugin in ipairs(removals) do
        vim.fn.appendbufline(
          self.buf,
          config.header_lines + 1,
          vim.fn.printf(
            '%s Removed %s',
            config.removed_sym,
            plugin
          )
        )
      end
    end

    if installs then
      for _, plugin in ipairs(installs) do
        vim.fn.appendbufline(
          self.buf,
          config.header_lines + 1,
          vim.fn.printf(
            '%s Installed %s',
            config.done_sym,
            plugin
          )
        )
      end
    end

    if updates then
      for plugin, update in pairs(updates) do
        local start_hash, end_hash, messages = update
        vim.fn.appendbufline(
          self.buf,
          config.header_lines + 1,
          vim.fn.printf(
            '%s Updated %s: %s..%s',
            config.done_sym,
            plugin,
            start_hash,
            end_hash
          )
        )
        vim.fn.appendbufline(self.buf, config.header_lines + 2, messages)
      end
    end
  end
}

display_mt.__index = display_mt

-- TODO: Option for no colors
local function make_filetype_cmds(working_sym, done_sym, error_sym)
  return {
    -- Adapted from https://github.com/kristijanhusak/vim-packager
    'setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nowrap nospell',
    'syntax clear',
    'syn match packerWorking /^' .. working_sym .. '/',
    'syn match packerSuccess /^' .. done_sym .. '/',
    'syn match packerFail /^' .. error_sym .. '/',
    'syn match packerStatus /\\(^+.*—\\)\\@<=\\s.*$/',
    'syn match packerStatusSuccess /\\(^' .. done_sym .. '.*—\\)\\@<=\\s.*$/',
    'syn match packerStatusFail /\\(^' .. error_sym .. '.*—\\)\\@<=\\s.*$/',
    'syn match packerStatusCommit /\\(^\\*.*—\\)\\@<=\\s.*$/',
    'syn match packerHash /\\(\\*\\s\\)\\@<=[0-9a-f]\\{4,}/',
    'syn match packerRelDate /([^)]*)$/',
    'syn match packerProgress /\\(\\[\\)\\@<=[\\=]*/',
    'hi def link packerWorking        SpecialKey',
    'hi def link packerSuccess        Question',
    'hi def link packerFail           ErrorMsg',
    'hi def link packerStatus         Constant',
    'hi def link packerStatusCommit   Constant',
    'hi def link packerStatusSuccess  Function',
    'hi def link packerStatusFail     WarningMsg',
    'hi def link packerHash           Identifier',
    'hi def link packerRelDate        Comment',
    'hi def link packerProgress       Boolean',
  }
end

display.set_config = function(working_sym, done_sym, error_sym, removed_sym, header_sym)
  config.working_sym = working_sym
  config.done_sym = done_sym
  config.error_sym = error_sym
  config.removed_sym = removed_sym
  config.header_lines = 2
  config.title = 'packer.nvim'
  config.header_sym = header_sym
  config.filetype_cmds = make_filetype_cmds(working_sym, done_sym, error_sym)
end

local function make_header(disp)
  local width = api.nvim_win_get_width(0)
  local pad_width = math.floor((width - string.len(config.title)) / 2.0)
  api.nvim_set_current_line(string.rep(' ', pad_width) .. config.title)
  vim.fn.appendbufline(disp.buf, 1, ' ' .. string.rep(config.header_sym, width - 2))
end

local function setup_window(disp)
  api.nvim_buf_set_option(disp.buf, 'filetype', 'packer')
  for _, m in ipairs(config.keymaps) do
    api.nvim_buf_set_keymap(disp.buf, m[1], m[2], m[3], m[4])
  end

  for _, c in ipairs(config.filetype_cmds) do
    api.nvim_command(c)
  end
end

display.open = function(opener)
  local disp = setmetatable({}, display_mt)
  if type(opener) == 'string' then
    api.nvim_command(opener)
    disp.win = api.nvim_get_current_win()
    disp.buf = api.nvim_get_current_buf()
  else
    disp.win, disp.buf = opener('[packer]')
  end

  disp.marks = {}
  disp.ns = api.nvim_create_namespace('')
  make_header(disp)
  setup_window(disp)

  return disp
end

return display
