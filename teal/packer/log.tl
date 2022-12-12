local packer_config = require('packer.config').log

local start_time = vim.loop.hrtime()

-- log.lua
--
-- Inspired by rxi/log.lua
-- Modified by tjdevries and can be found at github.com/tjdevries/vlog.nvim
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.
-- User configuration section

local enum LogLevel
  'trace' 'debug' 'info' 'warn' 'error' 'fatal'
end

local record LogConfig
  active_levels_console: {integer:boolean}
  active_levels_file: {integer:boolean}
  use_file: boolean
  level: LogLevel
  level_file: LogLevel
end

local default_config: LogConfig = {
  -- Should write to a file
  use_file = true,

  -- Any messages above this level will be logged.
  level = 'debug',

  -- Which levels should be logged?

  active_levels_console = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [6] = true
  },

  active_levels_file = { [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [6] = true
  },

  level_file = 'trace',
}

local record LevelConfig
  name: LogLevel
  hl: string
end

  -- Level configuration
local MODES: {LevelConfig} = {
  { name = 'trace', hl = 'Comment' },
  { name = 'debug', hl = 'Comment' },
  { name = 'info' , hl = 'None' },
  { name = 'warn' , hl = 'WarningMsg' },
  { name = 'error', hl = 'ErrorMsg' },
  { name = 'fatal', hl = 'ErrorMsg' },
}

-- Can limit the number of decimals displayed for floats
local FLOAT_PRECISION = 0.01

local level_ids = { trace = 1, debug = 2, info = 3, warn = 4, error = 5, fatal = 6 }

local function round(x: number, increment: integer): number
  increment = increment or 1
  x = x / increment
  return (x > 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)) * increment
end

local function stringify(...): {string}
  local t: {string} = {}
  for i = 1, select('#', ...) do
    local x = select(i, ...)

    if type(x) == 'number' then
      x = tostring(round(x, FLOAT_PRECISION))
    elseif type(x) ~= 'string' then
      x = vim.inspect(x)
    end

    t[#t + 1] = x
  end
  return t
end

local config = vim.deepcopy(default_config)

config.level = packer_config.level

local min_active_level = level_ids[config.level]
if min_active_level then
  for i = min_active_level, 6 do
    config.active_levels_console[i] = true
  end
end

local cache_dir = vim.fn.stdpath('cache')

local outfile = string.format('%s/packer.nvim.log', cache_dir)
vim.fn.mkdir(cache_dir, 'p')

local levels: {LogLevel:integer} = {}

for i, v in ipairs(MODES) do
  levels[v.name] = i
end

local function log_at_level_console(level_config: LevelConfig, message_maker: (function(...:any): string), ...)
  local msg = message_maker(...)
  local info = debug.getinfo(4, 'Sl') as {string:string}
  vim.schedule(function()
    local console_lineinfo = vim.fn.fnamemodify(info.short_src, ':t') .. ':' .. info.currentline
    local console_string = string.format(
      '[%-6s%s] %s: %s',
      level_config.name:upper(),
      os.date('%H:%M:%S'),
      console_lineinfo,
      msg
    )
    -- Heuristic to check for nvim-notify
    local is_fancy_notify = type(vim.notify) == 'table'
    vim.notify(
      string.format([[%s%s]], is_fancy_notify and '' or ('[packer.nvim'), console_string),
      vim.log.levels[level_config.name:upper() as vim.log.Level],
      { title = 'packer.nvim' }
    )
  end)
end

local HOME = vim.env.HOME

local function log_at_level_file(level_config: LevelConfig, message_maker: (function(...:any): string), ...)
  -- Output to log file
  local fp, err = io.open(outfile, 'a')
  if not fp then
    print(err)
    return
  end

  local info = debug.getinfo(4, 'Sl') as {string:string}
  local src = info.short_src:gsub(HOME, '~')
  local lineinfo = src .. ':' .. info.currentline

  fp:write(string.format(
    '[%-6s%s %s] %s: %s\n',
    level_config.name:upper(),
    os.date('%H:%M:%S'),
    vim.loop.hrtime() - start_time,
    lineinfo,
    message_maker(...)
  ))
  fp:close()
end

local function log_at_level(level: integer, level_config: LevelConfig, message_maker: (function(...:any): string), ...)
  if level >= levels[config.level_file] and config.use_file and config.active_levels_file[level] then
    log_at_level_file(level_config, message_maker, ...)
  end
  if level >= levels[config.level] and config.active_levels_console[level] then
    log_at_level_console(level_config, message_maker, ...)
  end
end

local record Log
  trace     : function(...: any)
  debug     : function(...: any)
  info      : function(...: any)
  warn      : function(...: any)
  error     : function(...: any)
  fatal     : function(...: any)

  fmt_trace : function(fmt: string, ...: any)
  fmt_debug : function(fmt: string, ...: any)
  fmt_info  : function(fmt: string, ...: any)
  fmt_warn  : function(fmt: string, ...: any)
  fmt_error : function(fmt: string, ...: any)
  fmt_fatal : function(fmt: string, ...: any)
end

local log: {string:function} = {}

for i, x in ipairs(MODES) do
  log[x.name] = function(...)
    log_at_level(i, x, function(...): string
      return table.concat(stringify(...), ' ')
    end, ...)
  end

  log['fmt_'..x.name] = function(fmt: string, ...)
    log_at_level(i, x, function(...): string
      return fmt:format(unpack(stringify(...)))
    end, ...)
  end
end

return log as Log
