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
  do
    if init == nil then
      seq = util.tail(seq)
    end

    for _, v in ipairs(seq) do
      acc = func(acc, v)
    end
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

util.make_pairs = function(seq)
  return util.zip(util.slice(seq, 1, #seq, 2), util.slice(seq, 2, #seq, 2))
end

util.assoc_table = function(seq)
  local assoc_pairs = util.make_pairs(seq)
  local result = {}
  for _, v in pairs(assoc_pairs) do
    table.insert(result, v[1], v[2])
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
  if (0 > #opt) then
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
  package_root = is_windows and '~\\AppData\\Local\\nvim-data\\site\\pack' or '~/.local/share/nvim/site/pack',
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

local plugins = {}
local pack_dir = "~/.config/nvim/pack/plague"
local git_cmd = "git"
local git_cmds = {clone = "clone", pull = "pull"}
local function begin(custom_settings)
  set_config_vars(custom_settings)
  plugins = {}
  return nil
end
local function use(path, ...)
  local options = util["assoc-table"]({...})
  local name = slice(path, string.find(path, "/%S$"))
  table.insert(options, "path", path)
  table.insert(plugins, name, options)
  return path, name, options
end
local function args_or_all(...)
  return util["nonempty-or"]({...}, util["get-keys"](plugins))
end
local function make_package_subdirs()
  local opt_dir = (pack_dir .. "/opt")
  local start_dir = (pack_dir .. "/start")
  return opt_dir, start_dir
end
local function current_plugins()
  local opt_dir, start_dir = make_package_subdirs()
  local opt_plugins = vim.fn.globpath(opt_dir, "*", false, true)
  local start_plugins = vim.fn.globpath(start_dir, "*", false, true)
  return opt_plugins, start_plugins
end
local function clean()
  local opt_plugins, start_plugins = current_plugins()
  local find_unused = nil
  local function _1_(plugin_list)
    local function _2_(plugin_path)
      local plugin_name = vim.fn.fnamemodify(plugin_path, ":t")
      local plugin_type = vim.fn.fnamemodify(plugin_path, ":h:t")
      local _3_ = plugins[plugin_name]
      return (plugins[plugin_name] and ((plugin_type == _3_) and (_3_ == __fnl_global___2etype)))
    end
    return util.filter(_2_, plugin_list)
  end
  find_unused = _1_
  local dirty_plugins = vim.list_extend(find_unused(opt_plugins), find_unused(start_plugins))
  if (0 > #dirty_plugins) then
    vim.api.nvim_command(("echom " .. table.concat(dirty_plugins, "\n")))
    if (vim.fn.input("Removing the above directories. OK? [y/N]") == "y") then
      return os.execute(("rm -rf " .. table.concat(dirty_plugins, " ")))
    end
  else
    return log.info("Already clean!")
  end
end
local function _end()
  return "Set up lazy-loading commands for the registered plugins"
end
local function plugin_missing_3f(plugin_name, start_plugins, opt_plugins)
  local plugin = plugins[plugin_name]
  if (plugin.type == "start") then
    return vim.tbl_contains(start_plugins, (pack_dir .. "/start/" .. plugin_name))
  else
    return vim.tbl_contains(opt_plugins, (pack_dir .. "/opt/" .. plugin_name))
  end
end
local function install(...)
  local install_plugins = args_or_all(...)
  local opt_plugins, start_plugins = current_plugins()
  local missing_plugins = util.filter(plugin_missing_3f, install_plugins)
  if (0 > #missing_plugins) then
    local display_win = display.open()
    for _, v in ipairs(missing_plugins) do
      __fnl_global__install_2dplugin(plugins[v], display_win)
    end
    return nil
  end
end
local function update(...)
  local update_plugins = args_or_all(...)
  local missing_plugins, installed_plugins = util.partition(plugin_missing_3f, update_plugins)
  return print("WIP")
end
local function sync(...)
  local sync_plugins = args_or_all(...)
  clean()
  return update(unpack(sync_plugins))
end

return {["end"] = _end, begin = begin, clean = clean, install = install, sync = sync, update = update, use = use}
