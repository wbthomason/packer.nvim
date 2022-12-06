local record util
  is_windows: boolean
  use_shellslash: boolean
end

--- Partition seq using values in sub
function util.partition<T>(sub: {T}, seq: {T}): {T}, {T}
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

-- TODO(lewis6991): use vim.loop.os_uname().sysname
if jit then
  util.is_windows = jit.os == 'Windows'
else
  util.is_windows = package.config:sub(1, 1) == '\\'
end

util.use_shellslash = util.is_windows and vim.o.shellslash and true

function util.get_separator(): string
  if util.is_windows and not util.use_shellslash then
    return '\\'
  end
  return '/'
end

function util.strip_trailing_sep(path: string): string
  local res = path:gsub( util.get_separator() .. '$', '', 1)
  return res
end

function util.join_paths(...: string): string
  return table.concat({ ... }, util.get_separator())
end

function util.measure(f: function()): number
  local start_time = vim.loop.hrtime()
  f()
  return (vim.loop.hrtime() - start_time) / 1e9
end


return util
