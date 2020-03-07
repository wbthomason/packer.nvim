local api     = vim.api

local display = {}
local config = {}
local display_mt = {
  task_start = function(self, plugin, task)
    vim.fn.appendbufline(self.buf, 1, vim.fn.printf('%s %s %s...', config.working_sym, task, plugin))
    self.marks[plugin] = api.nvim_buf_set_extmark(self.buf, self.ns, 0, 1, 0, {})
  end,
  task_succeeded = function(self, plugin, task)
    local line, _ = api.nvim_buf_get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    vim.fn.setbufline(self.buf, line, vim.fn.printf('%s %s %s', config.done_sym, task, plugin))
    api.nvim_buf_del_extmark(self.buf, self.ns, self.marks[plugin])
    self.marks[plugin] = nil
  end,
  task_failed = function(self, plugin, task)
    local line, _ = api.nvim_buf_get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    vim.fn.setbufline(self.buf, line, vim.fn.printf('%s %s %s', config.error_sym, task, plugin))
    api.nvim_buf_del_extmark(self.buf, self.ns, self.marks[plugin])
    self.marks[plugin] = nil
  end,
}

display.set_config = function(working_sym, done_sym, error_sym)
  config.working_sym = working_sym
  config.done_sym = done_sym
  config.error_sym = error_sym
end

display.open = function(opener)
  local disp = setmetatable({}, display_mt)
  if type(opener) == 'string' then
    api.nvim_command(opener)
    disp.win = api.nvim_get_current_win()
    disp.buf = api.nvim_get_current_buf()
  else
    disp.win, disp.buf = opener()
  end

  disp.marks = {}
  disp.ns = api.nvim_create_namespace()
  api.nvim_set_current_line('packer.nvim')

  -- TODO: Set up keybindings and autocommands for update window
  return disp
end

return display
