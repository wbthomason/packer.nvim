-- Utilities
local nvim = vim.api
local function echo_special(msg, hl)
  nvim.nvim_command('echohl ' .. hl)
  nvim.nvim_command('echom [plague] ' .. msg)
  nvim.nvim_command('echohl None')
end

local log = {
  info = function(msg) echo_special(msg, 'None') end,
  error = function(msg) echo_special(msg, 'ErrorMsg') end,
  warning = function(msg) echo_special(msg, 'WarningMsg') end,
}

local util = {}
util.pmap = function(func, seq)
  local result = {}
  for k, v in pairs(seq) do
    table.insert(result, func(k, v))
  end

  return result
end

util.map = function(func, seq)
  local result = {}
  for _, v in ipairs(seq) do
    table.insert(result, func(v))
  end

  return result
end

util.zip = function(...)
  local args = {...}
  local result = {}
  local min_length = math.min(unpack(util.map(function(s) return #s end, args)))
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
  return {unpack(seq, 2, #seq)}
end

util.head = function(seq)
  return seq[1]
end

local is_windows = jit.os == 'Windows'
util.get_separator = function()
  if is_windows == 'Windows' then
    return '\\'
  end

  return '/'
end

util.join_paths = function(...)
  local args = {...}
  local result = ''
  local separator = util.get_separator()
  for _, segment in ipairs(args) do
    result = result .. separator .. segment
  end

  return result
end

-- Config
local plague = {}
plague.config = {
  dependencies = true,
  package_root = is_windows and '~\\AppData\\Local\\nvim\\site\\pack' or '~/.local/share/nvim/site/pack',
  plugin_package = 'plugins',
  plague_package = 'plague',
  threads = nil,
  auto_clean = false,
}


local function dir(path)
  local lines = {}
  for s in string.gmatch(nvim.nvim_eval('globpath("' .. path .. '", "*")'), "[^\r\n]+") do
    table.insert(lines, s)
  end

  return lines
end

return { use = plague.fns.use, sync = plague.fns.sync, configure = plague.fns.configure }
