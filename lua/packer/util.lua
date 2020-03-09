local util = {}

util.map = function(func, seq)
  local result = {}
  for _, v in ipairs(seq) do
    table.insert(result, func(v))
  end

  return result
end

util.imap = function(func, seq)
  local result = {}
  for k, v in pairs(seq) do
    table.insert(result, func(k, v))
  end

  return result
end

util.zip = function(...)
  local args = {...}
  local result = {}
  local min_length = math.min(unpack(util.map(function(l) return #l end, args)))
  for i = 1, min_length do
    local elem = {}
    for _, l in ipairs(args) do
      table.insert(elem, l[i])
    end

    table.insert(result, elem)
  end

  return result
end

util.tail = function(seq)
  return { unpack(seq, 2, #seq) }
end

util.head = function(seq)
  return seq[1]
end

util.fold = function(func, seq, init)
  local acc = init or seq[1]
  if init == nil then
    seq = util.tail(seq)
  end

  for _, v in ipairs(seq) do
    acc = func(acc, v)
  end

  return acc
end

util.slice = function(seq, start, endpoint, step)
  local result = {}
  endpoint = endpoint or #seq
  step = step or 1
  for i = start, endpoint, step do
    table.insert(result, seq[i])
  end

  return result
end

util.filter = function(func, seq)
  local function f(acc, val)
    if func(val) then
      table.insert(acc, val)
    end

    return acc
  end

  return util.fold(f, seq, {})
end

util.partition = function(func, seq)
  local function f(acc, val)
    if func(val) then
      table.insert(acc[1], val)
    else
      table.insert(acc[2], val)
    end
    return acc
  end

  return unpack(util.fold(f, seq, {{}, {}}))
end

util.nonempty_or = function(opt, alt)
  if #opt > 0 then
    return opt
  else
    return alt
  end
end

util.get_keys = function(tbl)
  local keys = {}
  for k, _ in pairs(tbl) do
    table.insert(keys, k)
  end
  return keys
end

util.is_windows = jit.os == 'Windows'
local function get_separator()
  if util.is_windows then
    return '\\'
  end

  return '/'
end

util.join_paths = function(...)
  local args = {...}
  local result = args[1]
  local separator = get_separator()
  for idx = 2, #args do
    local segment = args[idx]
    result = result .. separator .. segment
  end

  return result
end

util.get_plugin_full_name = function(plugin)
  local plugin_name = plugin.name
  if plugin.branch then
    plugin_name = plugin_name .. ':' .. plugin.branch
  end

  if plugin.rev then
    plugin_name = plugin_name .. '@' .. plugin.rev
  end

  return plugin_name
end

return util
