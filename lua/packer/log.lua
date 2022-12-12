local packer_config = require('packer.config').log

local start_time = vim.loop.hrtime()






















local default_config = {

   use_file = true,


   level = 'debug',



   active_levels_console = {
      [1] = true,
      [2] = true,
      [3] = true,
      [4] = true,
      [5] = true,
      [6] = true,
   },

   active_levels_file = { [1] = true,
[2] = true,
[3] = true,
[4] = true,
[5] = true,
[6] = true,
   },

   level_file = 'trace',
}







local MODES = {
   { name = 'trace', hl = 'Comment' },
   { name = 'debug', hl = 'Comment' },
   { name = 'info', hl = 'None' },
   { name = 'warn', hl = 'WarningMsg' },
   { name = 'error', hl = 'ErrorMsg' },
   { name = 'fatal', hl = 'ErrorMsg' },
}


local FLOAT_PRECISION = 0.01

local level_ids = { trace = 1, debug = 2, info = 3, warn = 4, error = 5, fatal = 6 }

local function round(x, increment)
   increment = increment or 1
   x = x / increment
   return (x > 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)) * increment
end

local function stringify(...)
   local t = {}
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

local levels = {}

for i, v in ipairs(MODES) do
   levels[v.name] = i
end

local function log_at_level_console(level_config, message_maker, ...)
   local msg = message_maker(...)
   local info = debug.getinfo(4, 'Sl')
   vim.schedule(function()
      local console_lineinfo = vim.fn.fnamemodify(info.short_src, ':t') .. ':' .. info.currentline
      local console_string = string.format(
      '[%-6s%s] %s: %s',
      level_config.name:upper(),
      os.date('%H:%M:%S'),
      console_lineinfo,
      msg)


      local is_fancy_notify = type(vim.notify) == 'table'
      vim.notify(
      string.format([[%s%s]], is_fancy_notify and '' or ('[packer.nvim'), console_string),
      vim.log.levels[level_config.name:upper()],
      { title = 'packer.nvim' })

   end)
end

local HOME = vim.env.HOME

local function log_at_level_file(level_config, message_maker, ...)

   local fp, err = io.open(outfile, 'a')
   if not fp then
      print(err)
      return
   end

   local info = debug.getinfo(4, 'Sl')
   local src = info.short_src:gsub(HOME, '~')
   local lineinfo = src .. ':' .. info.currentline

   fp:write(string.format(
   '[%-6s%s %s] %s: %s\n',
   level_config.name:upper(),
   os.date('%H:%M:%S'),
   vim.loop.hrtime() - start_time,
   lineinfo,
   message_maker(...)))

   fp:close()
end

local function log_at_level(level, level_config, message_maker, ...)
   if level >= levels[config.level_file] and config.use_file and config.active_levels_file[level] then
      log_at_level_file(level_config, message_maker, ...)
   end
   if level >= levels[config.level] and config.active_levels_console[level] then
      log_at_level_console(level_config, message_maker, ...)
   end
end

















local log = {}

for i, x in ipairs(MODES) do
   log[x.name] = function(...)
      log_at_level(i, x, function(...)
         return table.concat(stringify(...), ' ')
      end, ...)
   end

   log['fmt_' .. x.name] = function(fmt, ...)
      log_at_level(i, x, function(...)
         return fmt:format(unpack(stringify(...)))
      end, ...)
   end
end

return log