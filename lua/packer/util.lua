local util = {}





function util.partition(sub, seq)
   local sub_vals = {}
   for _, val in ipairs(sub) do
      sub_vals[val] = true
   end

   local result = { {}, {} }
   for _, val in ipairs(seq) do
      if sub_vals[val] then
         table.insert(result[1], val)
      else
         table.insert(result[2], val)
      end
   end

   return unpack(result)
end

if jit then
   util.is_windows = jit.os == 'Windows'
else
   util.is_windows = package.config:sub(1, 1) == '\\'
end

util.use_shellslash = util.is_windows and vim.o.shellslash and true

function util.get_separator()
   if util.is_windows and not util.use_shellslash then
      return '\\'
   end
   return '/'
end

function util.strip_trailing_sep(path)
   local res = path:gsub(util.get_separator() .. '$', '', 1)
   return res
end

function util.join_paths(...)
   return table.concat({ ... }, util.get_separator())
end


function util.float(opts)
   local last_win = vim.api.nvim_get_current_win()
   local last_pos = vim.api.nvim_win_get_cursor(last_win)
   local columns = vim.o.columns
   local lines = vim.o.lines
   local width = math.ceil(columns * 0.8)
   local height = math.ceil(lines * 0.8 - 4)
   local left = math.ceil((columns - width) * 0.5)
   local top = math.ceil((lines - height) * 0.5 - 1)

   local buf = vim.api.nvim_create_buf(false, true)
   local win = vim.api.nvim_open_win(buf, true, vim.tbl_deep_extend('force', {
      relative = 'editor',
      style = 'minimal',
      border = 'double',
      width = width,
      height = height,
      col = left,
      row = top,
   }, opts))

   vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      callback = function()
         vim.api.nvim_set_current_win(last_win)
         vim.api.nvim_win_set_cursor(last_win, last_pos)
      end,
   })

   return true, win, buf
end

return util
