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

return util