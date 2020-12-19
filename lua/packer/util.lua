local util = {}

util.map = function(func, seq)
  local result = {}
  for _, v in ipairs(seq) do table.insert(result, func(v)) end

  return result
end

util.partition = function(sub, seq)
  local sub_vals = {}
  for _, val in ipairs(sub) do sub_vals[val] = true end

  local result = {{}, {}}
  for _, val in ipairs(seq) do
    if sub_vals[val] then
      table.insert(result[1], val)
    else
      table.insert(result[2], val)
    end
  end

  return unpack(result)
end

util.nonempty_or = function(opt, alt)
  if #opt > 0 then
    return opt
  else
    return alt
  end
end

util.is_windows = jit.os == 'Windows'

util.get_separator = function()
  if util.is_windows then return '\\' end
  return '/'
end

util.join_paths = function(...)
  local separator = util.get_separator()
  return table.concat({...}, separator)
end

util.get_plugin_full_name = function(plugin)
  local plugin_name = plugin.name
  if plugin.branch and plugin.branch ~= 'master' then
    -- NOTE: maybe have to change the seperator here too
    plugin_name = plugin_name .. '/' .. plugin.branch
  end

  if plugin.rev then plugin_name = plugin_name .. '@' .. plugin.rev end

  return plugin_name
end

util.memoize = function(func)
  return setmetatable({}, {
    __index = function(self, k)
      local v = func(k);
      self[k] = v;
      return v
    end,
    __call = function(self, k) return self[k] end
  })
end

util.deep_extend = function(policy, ...)
  local result = {}
  local function helper(policy, k, v1, v2)
    if type(v1) ~= 'table' or type(v2) ~= 'table' then
      if policy == 'error' then
        error('Key ' .. vim.inspect(k) .. ' is already present with value ' .. vim.inspect(v1))
      elseif policy == 'force' then
        return v2
      else
        return v1
      end
    else
      return util.deep_extend(policy, v1, v2)
    end
  end

  for _, t in ipairs({...}) do
    for k, v in pairs(t) do
      if result[k] ~= nil then
        result[k] = helper(policy, k, result[k], v)
      else
        result[k] = v
      end
    end
  end

  return result
end

-- Credit to @crs for the original function
util.float = function()
  local last_win = vim.api.nvim_get_current_win()
  local last_pos = vim.api.nvim_win_get_cursor(last_win)
  local columns, lines = vim.o.columns, vim.o.lines
  local win_width = math.ceil(columns * 0.8)
  local win_height = math.ceil(lines * 0.8 - 4)
  local col = math.ceil((columns - win_width) / 2)
  local row = math.ceil((lines - win_height) / 2 - 1)

  local bg_buf = vim.api.nvim_create_buf(false, true)

  local border_lines = { '┌' .. string.rep('─', win_width) .. '┐' }
  local middle_line = '|' .. string.rep(' ', win_width) .. '|'
  for _ =1, win_height do
    table.insert(border_lines, middle_line)
  end
  table.insert(border_lines, '└' .. string.rep('─', win_width) .. '┘')

  local opts = {
    relative = 'editor',
    style = 'minimal',
    width = win_width + 2,
    height = win_height + 2,
    col = col - 1,
    row = row - 1,
  }

  vim.api.nvim_buf_set_lines(bg_buf, 0, -1, false, border_lines)
  local bg_win = vim.api.nvim_open_win(bg_buf, true, opts)
  vim.fn.nvim_win_set_option(bg_win, 'winhl', 'Normal:Normal')

  opts.width = win_width
  opts.height = win_height
  opts.col = col
  opts.row = row

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, opts)

  function restore_cursor()
    vim.api.nvim_buf_delete(bg_buf, {})
    vim.api.nvim_set_current_win(last_win)
    vim.api.nvim_win_set_cursor(last_win, last_pos)
  end

  vim.cmd('autocmd! BufWipeout <buffer> lua restore_cursor()')

  return true, win, buf
end

return util
