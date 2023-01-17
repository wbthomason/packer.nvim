local api = vim.api
local log = require('packer.log')
local config = require('packer.config')
local awrap = require('packer.async').wrap
local packer_plugins = require('packer.plugin').plugins
local fmt = string.format

local Plugin = require('packer.plugin').Plugin

local ns = api.nvim_create_namespace('packer_display')

local M = {Display = {Item = {}, Callbacks = {}, }, }






















































local HEADER_LINES = 2
local TITLE = 'packer.nvim'

local Display = M.Display


local function valid_display(disp)
   return disp and disp.interactive and api.nvim_buf_is_valid(disp.buf) and api.nvim_win_is_valid(disp.win)
end

local function get_plugin(disp)
   local row = unpack(api.nvim_win_get_cursor(0)) - 1




   local es = api.nvim_buf_get_extmarks(0, ns, { row, 0 }, { row, -1 }, {})
   if not es[1] then
      print('no marks')
      return
   end

   local id, start, col = unpack(es[1])

   for name, item in pairs(disp.items) do
      if item.mark == id then
         return name, { start + 1, col }
      end
   end
end

local function open_win(inner)
   local vpad = inner and 8 or 6
   local hpad = inner and 14 or 10
   local width = math.min(vim.o.columns - hpad * 2, 200)
   local height = math.min(vim.o.lines - vpad * 2, 70)
   local buf = api.nvim_create_buf(false, true)
   local win = api.nvim_open_win(buf, true, {
      relative = "editor",
      style = "minimal",
      width = width,
      border = inner and 'rounded' or nil,
      height = height,
      noautocmd = true,
      row = (vim.o.lines - height) / 2,
      col = (vim.o.columns - width) / 2,
   })

   if inner then
      vim.wo[win].previewwindow = true
   end
   vim.bo[buf].buftype = 'nofile'
   vim.bo[buf].buflisted = false
   vim.bo[buf].swapfile = false
   vim.bo[buf].bufhidden = 'wipe'

   return buf, win
end

local COMMIT_PAT = [[[0-9a-f]\{7,9}]]
local COMMIT_SINGLE_PAT = fmt([[\<%s\>]], COMMIT_PAT)
local COMMIT_RANGE_PAT = fmt([[\<%s\.\.%s\>]], COMMIT_PAT, COMMIT_PAT)

local function diff(disp)
   if not valid_display(disp) then
      return
   end

   if next(disp.items) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
   end

   local plugin_name = get_plugin(disp)
   if plugin_name == nil then
      log.warn('No plugin selected!')
      return
   end

   local plugin = packer_plugins[plugin_name]

   if not plugin then
      log.warn('Plugin not available!')
      return
   end

   local current_line = api.nvim_get_current_line()
   local commit = vim.fn.matchstr(current_line, COMMIT_RANGE_PAT)
   if commit == '' then
      commit = vim.fn.matchstr(current_line, COMMIT_SINGLE_PAT)
   end

   if commit == '' then
      log.warn('Unable to find the diff for this line')
      return
   end

   disp.callbacks.diff(plugin, commit, function(lines, err)
      if err then
         log.warn('Unable to get diff!')
         return
      end
      vim.schedule(function()
         if not lines or #lines < 1 then
            log.warn('No diff available')
            return
         end
         local buf = open_win(true)
         api.nvim_buf_set_lines(buf, 0, -1, false, lines)
         api.nvim_buf_set_name(buf, commit)
         vim.keymap.set('n', 'q', '<cmd>close!<cr>', { buffer = buf, silent = true, nowait = true })
         vim.bo[buf].filetype = 'git'
      end)
   end)
end


local function set_lines(disp, srow, erow, lines)
   vim.bo[disp.buf].modifiable = true
   api.nvim_buf_set_lines(disp.buf, srow, erow, true, lines)
   vim.bo[disp.buf].modifiable = false
end

local function get_task_region(self, plugin)
   local mark = self.items[plugin].mark

   if not mark then
      return
   end

   local info = api.nvim_buf_get_extmark_by_id(self.buf, ns, mark, { details = true })

   local srow, erow = info[1], info[3].end_row

   if not erow then
      return srow, srow
   end



   if srow > erow then
      srow, erow = erow, srow
   end

   return srow, erow + 1
end

local function clear_task(self, plugin)
   local srow, erow = get_task_region(self, plugin)
   set_lines(self, srow, erow, {})
   local item = self.items[plugin]
   api.nvim_buf_del_extmark(self.buf, ns, item.mark)
   item.mark = nil
end






local MAX_COL = 10000

local function update_task_lines(self, plugin, message, pos)
   local item = self.items[plugin]



   if pos ~= nil or not item.mark then
      if item.mark then
         clear_task(self, plugin)
      end

      local new_row = pos == 'top' and HEADER_LINES or api.nvim_buf_line_count(self.buf)
      item.mark = api.nvim_buf_set_extmark(self.buf, ns, new_row, 0, {})
   end

   local srow, erow = get_task_region(self, plugin)
   set_lines(self, srow, erow, message)

   api.nvim_buf_set_extmark(self.buf, ns, srow, 0, {
      end_row = srow + #message - 1,
      end_col = MAX_COL,
      strict = false,
      id = item.mark,
   })
end

local function pad(x)
   local r = {}
   for i, s in ipairs(x) do
      r[i] = '   ' .. s
   end
   return r
end

local function render_task(self, plugin, static)
   local item = self.items[plugin]

   local icon
   if not item.status or item.status == 'done' then
      icon = config.display.item_sym
   elseif item.status == 'running' then
      icon = config.display.working_sym
   elseif item.status == 'failed' then
      icon = config.display.error_sym
   else
      icon = config.display.done_sym
   end

   local lines = { fmt(' %s %s: %s', icon, plugin, item.message) }

   if item.info and item.expanded then
      vim.list_extend(lines, pad(item.info))
   end

   local pos
   if not static then
      pos = (item.status == 'success' or item.status == 'failed') and 'top' or nil
   end

   update_task_lines(self, plugin, lines, pos)
end


local function toggle_info(disp)
   if not valid_display(disp) then
      return
   end

   if disp.items == nil or next(disp.items) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
   end

   local plugin_name, cursor_pos = get_plugin(disp)
   if cursor_pos == nil then
      log.warn('No plugin selected!')
      return
   end

   local item = disp.items[plugin_name]
   item.expanded = not item.expanded
   render_task(disp, plugin_name, true)
   api.nvim_win_set_cursor(disp.win, cursor_pos)
end


local function prompt_user(headline, body, callback)
   if config.display.non_interactive then
      callback(true)
      return
   end

   local buf = api.nvim_create_buf(false, true)
   local longest_line = 0
   for _, line in ipairs(body) do
      local line_length = string.len(line)
      if line_length > longest_line then
         longest_line = line_length
      end
   end

   local width = math.min(longest_line + 2, math.floor(0.9 * vim.o.columns))
   local height = #body + 3
   local x = (vim.o.columns - width) / 2.0
   local y = (vim.o.lines - height) / 2.0
   local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
   local lines = vim.list_extend({
      string.rep(' ', pad_width) .. headline .. string.rep(' ', pad_width),
      '',
   }, body)
   api.nvim_buf_set_lines(buf, 0, -1, true, lines)
   vim.bo[buf].modifiable = true

   local win = api.nvim_open_win(buf, false, {
      relative = 'editor',
      width = width,
      height = height,
      col = x,
      row = y,
      focusable = false,
      style = 'minimal',
      border = config.display.prompt_border,
      noautocmd = true,
   })

   local check = vim.loop.new_prepare()
   assert(check)
   local prompted = false
   check:start(vim.schedule_wrap(function()
      if not api.nvim_win_is_valid(win) then
         return
      end
      check:stop()
      if not prompted then
         prompted = true
         local ans = string.lower(vim.fn.input('OK to remove? [y/N] ')) == 'y'
         api.nvim_win_close(win, true)
         callback(ans)
      end
   end))
end


local function prompt_revert(disp)
   if not valid_display(disp) then
      return
   end
   if next(disp.items) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
   end

   local plugin_name = get_plugin(disp)
   if plugin_name == nil then
      log.warn('No plugin selected!')
      return
   end

   local plugin = packer_plugins[plugin_name]
   local actual_update = plugin.revs[1] ~= plugin.revs[2]
   if actual_update then
      prompt_user('Revert update for ' .. plugin_name .. '?', {
         'Do you want to revert ' ..
         plugin_name ..
         ' from ' ..
         plugin.revs[2] ..
         ' to ' ..
         plugin.revs[1] ..
         '?',
      }, function(ans)
         if ans then
            disp.callbacks.revert_last(plugin)
         end
      end)
   else
      log.fmt_warn("%s wasn't updated; can't revert!", plugin_name)
   end
end

local in_headless = #api.nvim_list_uis() == 0

M.display = setmetatable({}, { __index = Display })

local display = M.display

display.interactive = not config.display.non_interactive and not in_headless
display.ask_user = awrap(prompt_user, 3)







local keymaps = {
   quit = {
      action = 'quit',
      rhs = function()

         display.running = false
         vim.fn.execute('q!', 'silent')
      end,

   },

   diff = {
      action = 'show the diff',
      rhs = function()
         diff(display)
      end,
   },

   toggle_info = {
      action = 'show more info',
      rhs = function()
         toggle_info(display)
      end,
   },

   prompt_revert = {
      action = 'revert an update',
      rhs = function()
         prompt_revert(display)
      end,
   },

}

function display:check()
   return not self.running
end


display.task_start = vim.schedule_wrap(function(self, plugin, message)
   if not valid_display(self) then
      return
   end

   local item = self.items[plugin]
   item.status = 'running'
   item.message = message

   render_task(self, plugin)
end)


local function decrement_headline_count(disp)
   if not valid_display(disp) then
      return
   end
   local headline = api.nvim_buf_get_lines(disp.buf, 0, 1, false)[1]
   local count_start, count_end = headline:find('%d+')
   if count_start then
      local count = tonumber(headline:sub(count_start, count_end))
      local updated_headline = string.format(
      '%s%s%s',
      headline:sub(1, count_start - 1),
      count - 1,
      headline:sub(count_end + 1))

      set_lines(disp, 0, HEADER_LINES - 1, { updated_headline })
   end
end

local function normalize_lines(x)
   local r = {}
   for _, l in ipairs(x) do
      for _, i in ipairs(vim.split(l, '\n')) do
         r[#r + 1] = i
      end
   end
   return r
end

local task_done = vim.schedule_wrap(function(self, plugin, message, info, success)
   if not valid_display(self) then
      return
   end

   local item = self.items[plugin]

   if success == true then
      item.status = 'success'
   elseif success == false then
      item.status = 'failed'
   else
      item.status = 'done'
   end

   item.message = message

   if info then
      item.info = normalize_lines(info)
   end

   render_task(self, plugin)
   decrement_headline_count(self)
end)


function display:task_done(plugin, message, info)
   task_done(self, plugin, message, info, nil)
end


function display:task_succeeded(plugin, message, info)
   task_done(self, plugin, message, info, true)
end


function display:task_failed(plugin, message, info)
   task_done(self, plugin, message, info, false)
end


display.task_update = vim.schedule_wrap(function(self, plugin, message, info)
   log.fmt_debug('%s: %s', plugin, message)
   if not valid_display(self) then
      return
   end

   local item = self.items[plugin]
   item.message = message

   if info then
      item.info = info
   end

   render_task(self, plugin)
end)


display.update_headline_message = vim.schedule_wrap(function(self, message)
   if not valid_display(self) then
      return
   end
   local headline = TITLE .. ' - ' .. message
   local width = api.nvim_win_get_width(self.win) - 2
   local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
   set_lines(self, 0, HEADER_LINES - 1, { string.rep(' ', pad_width) .. headline })
end)


display.finish = vim.schedule_wrap(function(self, time)
   if not valid_display(self) then
      return
   end

   display.running = false
   self:update_headline_message(fmt('finished in %.3fs', time))

   for plugin_name, _ in pairs(self.items) do
      local plugin = packer_plugins[plugin_name]
      if plugin.breaking_commits and #plugin.breaking_commits > 0 then
         vim.cmd('syntax match packerBreakingChange "' .. plugin_name .. '" containedin=packerStatusSuccess')
         for _, commit_hash in ipairs(plugin.breaking_commits) do
            log.fmt_warn('Potential breaking change in commit %s of %s', commit_hash, plugin_name)
            vim.cmd('syntax match packerBreakingChange "' .. commit_hash .. '" containedin=packerHash')
         end
      end
   end
end)

local function look_back(str)
   return fmt([[\(%s\)\@%d<=]], str, #str)
end


local function make_filetype_cmds(working_sym, done_sym, error_sym)
   return {
      'setlocal nolist nowrap nospell nonumber norelativenumber nofoldenable signcolumn=no',
      'syntax clear',
      'syn match packerWorking /^ ' .. working_sym .. '/',
      'syn match packerSuccess /^ ' .. done_sym .. '/',
      'syn match packerFail /^ ' .. error_sym .. '/',
      'syn match packerStatus /^+.*—\\zs\\s.*$/',
      'syn match packerStatusSuccess /' .. look_back('^ ' .. done_sym) .. '\\s.*$/',
      'syn match packerStatusFail /' .. look_back('^ ' .. error_sym) .. '\\s.*$/',
      'syn match packerStatusCommit /^\\*.*—\\zs\\s.*$/',
      'syn match packerHash /\\(\\s\\)[0-9a-f]\\{7,8}\\(\\s\\)/',
      'syn match packerRelDate /([^)]*)$/',
      'syn match packerProgress /\\[\\zs[\\=]*/',
      'syn match packerOutput /\\(Output:\\)\\|\\(Commits:\\)\\|\\(Errors:\\)/',
      [[syn match packerTimeHigh /\d\{3\}\.\d\+ms/]],
      [[syn match packerTimeMedium /\d\{2\}\.\d\+ms/]],
      [[syn match packerTimeLow /\d\.\d\+ms/]],
      [[syn match packerTimeTrivial /0\.\d\+ms/]],
      [[syn match packerPackageNotLoaded /(not loaded)$/]],
      [[syn match packerString /\v(''|""|(['"]).{-}[^\\]\2)/]],
      [[syn match packerBool /\<\(false\|true\)\>/]],
      [[syn match packerPackageName /^\ • \zs[^ ]*/]],
      'hi def link packerWorking        SpecialKey',
      'hi def link packerSuccess        Question',
      'hi def link packerFail           ErrorMsg',
      'hi def link packerHash           Identifier',
      'hi def link packerRelDate        Comment',
      'hi def link packerProgress       Boolean',
      'hi def link packerOutput         Type',
   }
end

local function set_config_keymaps()
   local dcfg = config.display
   if dcfg.keybindings then
      for name, lhs in pairs(dcfg.keybindings) do
         if keymaps[name] then
            keymaps[name].lhs = lhs
         end
      end
   end
end


local function make_header(d)
   local width = api.nvim_win_get_width(0)
   local pad_width = math.floor((width - TITLE:len()) / 2.0)
   set_lines(d, 0, 1, {
      (' '):rep(pad_width) .. TITLE,
      ' ' .. config.display.header_sym:rep(width - 2),
   })
end


local function setup_display_buf(bufnr)
   vim.bo[bufnr].filetype = 'packer'
   api.nvim_buf_set_name(bufnr, '[packer]')
   set_config_keymaps()
   for _, m in pairs(keymaps) do
      local lhs = m.lhs
      if type(lhs) == "string" then
         lhs = { lhs }
      end
      lhs = lhs
      for _, x in ipairs(lhs) do
         vim.keymap.set('n', x, m.rhs, {
            desc = 'Packer: ' .. m.action,
            buffer = bufnr,
            nowait = true,
            silent = true,
         })
      end
   end

   local ft_cmds = make_filetype_cmds(
   config.display.working_sym,
   config.display.done_sym,
   config.display.error_sym)


   for _, c in ipairs(ft_cmds) do
      vim.cmd(c)
   end

   for _, c in ipairs({
         { 'packerStatus', 'Type' },
         { 'packerStatusCommit', 'Constant' },
         { 'packerStatusSuccess', 'Constant' },
         { 'packerStatusFail', 'ErrorMsg' },
         { 'packerPackageName', 'Title' },
         { 'packerPackageNotLoaded', 'Comment' },
         { 'packerString', 'String' },
         { 'packerBool', 'Boolean' },
         { 'packerBreakingChange', 'WarningMsg' },
      }) do
      api.nvim_set_hl(0, c[1], { link = c[2], default = true })
   end
end


function display.open(cbs)
   if not display.interactive then
      return
   end

   if not (display.win and api.nvim_win_is_valid(display.win)) then
      display.buf, display.win = open_win()
      setup_display_buf(display.buf)
   end

   display.callbacks = cbs
   display.running = true

   display.items = setmetatable({}, {
      __index = function(t, k)
         t[k] = { expanded = false }
         return t[k]
      end,
   })

   set_lines(display, 0, -1, {})
   make_header(display)

   return display
end

return M