local window = {}

local function default_win_opts()
  local opts = {
    relative = 'editor',
    style    = 'minimal'
  }

  return opts
end


--- Create window that takes up certain percentags of the current screen.
---
--- Works regardless of current buffers, tabs, splits, etc.
--@param col_range number | Table:
--                  If number, then center the window taking up this percentage of the screen.
--                  If table, first index should be start, second_index should be end
--@param row_range number | Table:
--                  If number, then center the window taking up this percentage of the screen.
--                  If table, first index should be start, second_index should be end
window.percentage_range_window = function(col_range, row_range, options)
  options = options or {
    winblend = 15
  }

  local win_opts = default_win_opts(options)

  local height_percentage, row_start_percentage
  if type(row_range) == 'number' then
    assert(row_range <= 1)
    assert(row_range > 0)
    height_percentage = row_range
    row_start_percentage = (1 - height_percentage) / 2
  elseif type(row_range) == 'table' then
    height_percentage = row_range[2] - row_range[1]
    row_start_percentage = row_range[1]
  else
    error(string.format("Invalid type for 'row_range': %p", row_range))
  end

  win_opts.height = math.ceil(vim.o.lines * height_percentage)
  win_opts.row = math.ceil(vim.o.lines *  row_start_percentage)

  local width_percentage, col_start_percentage
  if type(col_range) == 'number' then
    assert(col_range <= 1)
    assert(col_range > 0)
    width_percentage = col_range
    col_start_percentage = (1 - width_percentage) / 2
  elseif type(col_range) == 'table' then
    width_percentage = col_range[2] - col_range[1]
    col_start_percentage = col_range[1]
  else
    error(string.format("Invalid type for 'col_range': %p", col_range))
  end

  win_opts.col = math.floor(vim.o.columns * col_start_percentage)
  win_opts.width = math.floor(vim.o.columns * width_percentage)

  local buf = options.bufnr or vim.fn.nvim_create_buf(false, true)
  local win = vim.fn.nvim_open_win(buf, true, win_opts)
  vim.api.nvim_win_set_buf(win, buf)

  vim.cmd('setlocal nocursorcolumn')
  vim.fn.nvim_win_set_option(win, 'winblend', options.winblend)

  vim.cmd(string.format(
    [[autocmd BufLeave <buffer=%s> :call nvim_win_close(%s, v:true)]],
    buf,
    win
  ))

  return win, buf
end

return window
