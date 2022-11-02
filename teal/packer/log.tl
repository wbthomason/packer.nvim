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
  active_levels: {integer:boolean}
  use_file: boolean
  level: LogLevel
end

local default_config: LogConfig = {
  -- Should write to a file
  use_file = true,

  -- Any messages above this level will be logged.
  level = 'debug',

  -- Which levels should be logged?
  active_levels = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [6] = true
  },

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

local function make_string(...): string
  local t: {string} = {}
  for i = 1, select('#', ...) do
    local x = select(i, ...)

    if type(x) == 'number' then
      x = tostring(round(x, FLOAT_PRECISION))
    else
      x = vim.inspect(x)
    end

    t[#t + 1] = x
  end
  return table.concat(t, ' ')
end

local console_output = vim.schedule_wrap(function(level_config: LevelConfig, info: {string:string}, nameupper: string, msg: string)
  local console_lineinfo = vim.fn.fnamemodify(info.short_src, ':t') .. ':' .. info.currentline
  local console_string = string.format('[%-6s%s] %s: %s', nameupper, os.date '%H:%M:%S', console_lineinfo, msg)
  -- Heuristic to check for nvim-notify
  local is_fancy_notify = type(vim.notify) == 'table'
  vim.notify(
    string.format([[%s%s]], is_fancy_notify and '' or ('[packer.nvim'), console_string),
    vim.log.levels[level_config.name:upper() as vim.log.Level],
    { title = 'packer.nvim' }
  )
end)

local min_active_level = level_ids[require'packer.config'.log.level]


local config: LogConfig = { active_levels = {} }

if min_active_level then
  for i = min_active_level, 6 do
    config.active_levels[i] = true
  end
end

config = vim.tbl_deep_extend('force', default_config, config)

local outfile = string.format('%s/packer.nvim.log', vim.fn.stdpath 'cache')
vim.fn.mkdir(vim.fn.stdpath 'cache', 'p')

local levels: {LogLevel:integer} = {}

for i, v in ipairs(MODES) do
  levels[v.name] = i
end

local function log_at_level(level: integer, level_config: LevelConfig, message_maker: (function(...:any): string), ...)
  -- Return early if we're below the config.level
  if level < levels[config.level] then
    return
  end
  local nameupper = level_config.name:upper()

  local msg = message_maker(...)
  local info = debug.getinfo(2, 'Sl') as {string:string}
  local lineinfo = info.short_src .. ':' .. info.currentline

  -- Output to console
  if config.active_levels[level] then
    console_output(level_config, info, nameupper, msg)
  end

  -- Output to log file
  if config.use_file and config.active_levels[level] then
    local fp, err = io.open(outfile, 'a')
    if not fp then
      print(err)
      return
    end

    local str = string.format('[%-6s%s %s] %s: %s\n', nameupper, os.date(), vim.loop.hrtime(), lineinfo, msg)
    fp:write(str)
    fp:close()
  end
end

local log: {string:function} = {}

for i, x in ipairs(MODES) do
  log[x.name] = function(...)
    log_at_level(i, x, make_string, ...)
  end

  log[('fmt_%s'):format(x.name)] = function()
    log_at_level(i, x, function(...): string
      local passed = { ... }
      local fmt = table.remove(passed, 1)
      local inspected = {}
      for _, v in ipairs(passed) do
        table.insert(inspected, vim.inspect(v))
      end
      return fmt:format(unpack(inspected))
    end)
  end
end

return log
