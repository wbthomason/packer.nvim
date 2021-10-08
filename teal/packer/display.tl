local DisplayIds = require 'packer.display_ids'

local record M 
end

-- TODO: Maybe should be moved to display module?
--- open_float: a reasonable default floating window display opener
--- @param options: a table of floating window options; see nvim_open_win
--- @return The window and buffer ids for the opened window
-- Credit to @crs for the original function
function M.open_float(opts: {string:any}): DisplayIds
  local last_win = vim.api.nvim_get_current_win()
  local last_pos = vim.api.nvim_win_get_cursor(last_win)
  local columns = vim.o.columns
  local lines = vim.o.lines
  local width = math.ceil(columns * 0.8)
  local height = math.ceil(lines * 0.8 - 4)
  local left = math.ceil((columns - width) * 0.5)
  local top = math.ceil((lines - height) * 0.5 - 1)

  vim.tbl_deep_extend('keep', opts or {}, {
    relative = 'editor',
    style = 'minimal',
    border = 'double',
    width = width,
    height = height,
    col = left,
    row = top,
  })

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, opts)

  _G._packer.restore_cursor = function()
    vim.api.nvim_set_current_win(last_win)
    vim.api.nvim_win_set_cursor(last_win, last_pos)
  end

  vim.cmd 'autocmd! BufWipeout <buffer> lua _G._packer.restore_cursor()'
  return {window = win, buffer = buf}
end

function M.float(opts: {string:any}): DisplayIds
  vim.notify('packer.nvim: The packer.util.float() function is deprecated. Use packer.display.open_float() instead.', vim.log.levels.WARN, {})
  return M.open_float(opts)
end
