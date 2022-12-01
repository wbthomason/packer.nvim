local api = vim.api
local log = require('packer.log')
local config = require('packer.config')
local awrap = require('packer.async').wrap
local packer_plugins = require('packer.plugin').plugins
local fmt = string.format

local Config = config.Config

local function set_extmark(buf, ns, id, line, col)
   if not api.nvim_buf_is_valid(buf) then
      return
   end
   return api.nvim_buf_set_extmark(buf, ns, line, col, { id = id })
end

local function strip_newlines(raw_lines)
   local lines = {}
   for _, line in ipairs(raw_lines) do
      for _, chunk in ipairs(vim.split(line, '\n')) do
         table.insert(lines, chunk)
      end
   end

   return lines
end

local function unpack_config_value(value, formatter)
   if type(value) == "string" then
      return { value }
   elseif type(value) == "table" then
      local result = {}
      for _, k in ipairs(value) do
         local item = formatter and formatter(k) or k
         table.insert(result, fmt('  - %s', item))
      end
      return result
   end
   return ''
end

local function format_keys(value)
   local mapping, mode
   if type(value) == "string" then
      mapping = value
      mode = ''
   else
      mapping = value[2]
      mode = value[1] ~= '' and 'mode: ' .. value[1] or ''
   end
   return fmt('"%s", %s', mapping, mode)
end

local function format_cmd(value)
   return fmt('"%s"', value)
end


local function format_values(key, value)
   if key == 'url' then
      return fmt('"%s"', value)
   end

   if key == 'keys' then
      return unpack_config_value(value, format_keys)
   end

   if key == 'commands' then
      return unpack_config_value(value, format_cmd)
   end

   if type(value) == 'function' then
      local info = debug.getinfo(value, 'Sl')
      return fmt('<Lua: %s:%s>', info.short_src, info.linedefined)
   end

   local s = vim.inspect(value):gsub('\n', ', ')
   return s
end

local plugin_keys_exclude = {
   full_name = true,
   name = true,
   destructors = true,
}

local function is_plugin_line(line)
   for _, sym in ipairs({
         config.display.item_sym,
         config.display.done_sym,
         config.display.working_sym,
         config.display.error_sym,
      }) do
      if line:find(sym, 1, true) then
         return true
      end
   end
   return false
end

local M = {Display = {Item = {}, Result = {}, Results = {}, MarkIDs = {}, Callbacks = {}, }, }








































































local HEADER_LINES = 2
local TITLE = 'packer.nvim'

local Display = M.Display


local function valid_display(disp)
   return disp and disp.interactive and api.nvim_buf_is_valid(disp.buf) and api.nvim_win_is_valid(disp.win)
end


local function find_nearest_plugin(disp)
   if not valid_display(disp) then
      return
   end

   local current_cursor_pos = api.nvim_win_get_cursor(0)
   local nb_lines = api.nvim_buf_line_count(0)
   local cursor_pos_y = math.max(current_cursor_pos[1], HEADER_LINES + 1)
   if cursor_pos_y > nb_lines then
      return
   end
   for i = cursor_pos_y, 1, -1 do
      local curr_line = api.nvim_buf_get_lines(0, i - 1, i, true)[1]
      if is_plugin_line(curr_line) then
         for name, _ in pairs(disp.items) do
            if string.find(curr_line, name, 1, true) then
               return name, { i, 0 }
            end
         end
      end
   end
end

local function open_preview(commit, lines)
   if not lines or #lines < 1 then
      log.warn('No diff available')
      return
   end
   vim.cmd.pedit(commit)
   vim.cmd.wincmd('P')
   vim.wo.previewwindow = true
   vim.bo.buftype = 'nofile'
   vim.bo.buflisted = false
   api.nvim_buf_set_lines(0, 0, -1, false, lines)
   vim.keymap.set('n', 'q', '<cmd>close!<cr>', { buffer = 0, silent = true, nowait = true })
   vim.bo.filetype = 'git'
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

   local plugin_name = find_nearest_plugin(disp)
   if plugin_name == nil then
      log.warn('No plugin selected!')
      return
   end

   if not disp.items[plugin_name] then
      log.warn('Plugin not available!')
      return
   end

   local plugin = disp.items[plugin_name].plugin
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
         open_preview(commit, lines)
      end)
   end)
end

local function make_update_msg(symbol, status, plugin_name, plugin)
   return fmt(' %s %s %s: %s..%s', symbol, status, plugin_name, plugin.revs[1], plugin.revs[2])
end


local function set_lines(disp, start_idx, end_idx, lines)
   if not valid_display(disp) then
      return
   end
   vim.bo[disp.buf].modifiable = true
   local ok, err = pcall(api.nvim_buf_set_lines, disp.buf, start_idx, end_idx, true, lines), string
   if not ok then
      print(vim.inspect(err))
      error(string.format('Could not set lines %d-%d: %s\n%s', start_idx, end_idx, vim.inspect(err), debug.traceback()))
   end
   vim.bo[disp.buf].modifiable = false
end

local function toggle_update(disp)
   if not disp:is_previewing() then
      return
   end
   local plugin_name = find_nearest_plugin(disp)
   local item = disp.items[plugin_name]
   if not item then
      log.warn('Plugin not available!')
      return
   end

   item.ignore_update = not item.ignore_update

   local mark_ids = disp.marks[plugin_name]
   local start_idx = api.nvim_buf_get_extmark_by_id(disp.buf, disp.ns, mark_ids.start, {})[1]
   local symbol
   local status_msg
   if item.ignore_update then
      status_msg = [[Won't update]]
      symbol = config.display.item_sym
   else
      status_msg = 'Can update'
      symbol = config.display.done_sym
   end
   set_lines(disp, start_idx, start_idx + 1,
   { make_update_msg(symbol, status_msg, plugin_name, item.plugin) })

   disp.marks[plugin_name].start = set_extmark(disp.buf, disp.ns, nil, start_idx, 0)
end

local function continue(disp)
   if not disp:is_previewing() then
      return
   end
   local plugins = {}
   for plugin_name, _ in pairs(disp.results.updates) do
      local item = disp.items[plugin_name]
      if item.ignore_update then
         table.insert(plugins, plugin_name)
      end
   end
   if #plugins > 0 then
      disp.callbacks.update({ pull_head = true, preview_updates = false }, unpack(plugins))
   else
      log.warn('No plugins selected!')
   end
end

local function pad(x)
   local r = {}
   for i, s in ipairs(x) do
      r[i] = '   ' .. s
   end
   return r
end


local function toggle_info(disp)
   if not valid_display(disp) then
      return
   end
   if disp.items == nil or next(disp.items) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
   end

   local plugin_name, cursor_pos = find_nearest_plugin(disp)
   if cursor_pos == nil then
      log.warn('No plugin selected!')
      return
   end

   local item = disp.items[plugin_name]

   if item.displayed then
      set_lines(disp, cursor_pos[1], cursor_pos[1] + #item.lines, {})
      item.displayed = false
   elseif #item.lines > 0 then
      set_lines(disp, cursor_pos[1], cursor_pos[1], pad(item.lines))
      item.displayed = true
   else
      log.info('No further information for ' .. plugin_name)
   end

   api.nvim_win_set_cursor(0, cursor_pos)
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

   local plugin_name = find_nearest_plugin(disp)
   if plugin_name == nil then
      log.warn('No plugin selected!')
      return
   end

   local item = disp.items[plugin_name]
   local plugin = item.plugin
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
      log.warn(plugin_name .. " wasn't updated; can't revert!")
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

   toggle_update = {
      action = 'toggle update',
      rhs = function()
         toggle_update(display)
      end,
   },

   continue = {
      action = 'continue with updates',
      rhs = function()
         continue(display)
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

   retry = {
      action = 'retry failed operations',
      rhs = function()
         if display.any_failed_install then
            log.debug('retrying install')
            display.callbacks.install()
         elseif #display.failed_update_list > 0 then
            log.debug(fmt('retrying updates for: %s', table.concat(display.failed_update_list, '\n')))
            display.callbacks.update(unpack(display.failed_update_list))
         end
      end,
   },
}



local default_keymap_display_order = {
   'quit',
   'toggle_info',
   'diff',
   'prompt_revert',
   'retry',
}

function display:check()
   return not self.running
end


display.task_start = vim.schedule_wrap(function(self, plugin, message)
   if not valid_display(self) then
      return
   end
   if self.marks[plugin] then
      self:task_update(plugin, message)
      return
   end
   display.running = true
   set_lines(self, HEADER_LINES, HEADER_LINES, {
      fmt(' %s %s: %s', config.display.working_sym, plugin, message),
   })

   self.marks[plugin] = self.marks[plugin] or {}
   self.marks[plugin].start = set_extmark(self.buf, self.ns, nil, HEADER_LINES, 0)
end)


local decrement_headline_count = vim.schedule_wrap(function(disp)
   if not valid_display(disp) then
      return
   end
   local headline = api.nvim_buf_get_lines(disp.buf, 0, 1, false)[1]
   local count_start, count_end = headline:find('%d+')
   local count = tonumber(headline:sub(count_start, count_end))
   local updated_headline = headline:sub(1, count_start - 1) ..
   tostring(count - 1) ..
   headline:sub(count_end + 1)
   set_lines(disp, 0, 1, { updated_headline })
end)


local task_done = vim.schedule_wrap(function(self, plugin, message, success)
   if not valid_display(self) then
      return
   end
   local line = api.nvim_buf_get_extmark_by_id(self.buf, self.ns, self.marks[plugin].start, {})
   local icon = success and config.display.done_sym or config.display.error_sym
   set_lines(self, line[1], line[1] + 1, { fmt(' %s %s: %s', icon, plugin, message) })
   api.nvim_buf_del_extmark(self.buf, self.ns, self.marks[plugin].start)
   self.marks[plugin] = nil
   decrement_headline_count(self)
end)


function display:task_succeeded(plugin, message)
   task_done(self, plugin, message, true)
end


function display:task_failed(plugin, message)
   task_done(self, plugin, message, false)
end


display.task_update = vim.schedule_wrap(function(self, plugin, message)
   log.info(string.format('%s: %s', plugin, message))
   if not valid_display(self) then
      return
   end
   if not self.marks[plugin] then
      return
   end
   local line = api.nvim_buf_get_extmark_by_id(self.buf, self.ns, self.marks[plugin].start, {})[1]
   set_lines(self, line, line + 1, { fmt(' %s %s: %s', config.display.working_sym, plugin, message) })
   set_extmark(self.buf, self.ns, self.marks[plugin].start, line, 0)
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


local function setup_status_syntax()
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

local function load_state(plugin)
   if not plugin.loaded then
      if plugin.start then
         return ' (not installed)'
      end
      return ' (not loaded)'
   end

   if plugin.lazy then
      return ' (manually loaded)'
   end

   return ''
end

local function get_plugin_status(plugin)
   local config_lines = {}
   for key, value in pairs(plugin) do
      if not plugin_keys_exclude[key] then
         local details = format_values(key, value)
         if type(details) == "string" then

            table.insert(config_lines, 1, fmt('%s: %s', key, details))
         else
            vim.list_extend(config_lines, { fmt('%s: ', key), unpack(details) })
         end
      end
   end

   return config_lines
end

display.set_status = vim.schedule_wrap(function(self, plugins)
   if not valid_display(self) then
      return
   end
   setup_status_syntax()
   self:update_headline_message(fmt('Total plugins: %d', vim.tbl_count(plugins)))

   local lines = {}

   self.items = self.items or {}

   for plugin_name, plugin in pairs(plugins) do
      lines[#lines + 1] = fmt(' %s %s%s', config.display.item_sym, plugin_name, load_state(plugin))
      self.items[plugin_name] = {
         plugin = plugin,
         lines = get_plugin_status(plugin),
         displayed = false,
      }
   end

   table.sort(lines)
   set_lines(self, HEADER_LINES, -1, lines)
end)

function display:is_previewing()
   local opts = self.opts or {}
   return opts.preview_updates
end

function display:has_changes(plugin)
   if plugin.type ~= 'git' or plugin.revs[1] == plugin.revs[2] then
      return false
   end
   if self:is_previewing() and plugin.commit ~= nil then
      return false
   end
   return true
end


local function show_all_info(disp)
   if not valid_display(disp) then
      return
   end

   if next(disp.items) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
   end

   local line = HEADER_LINES + 1
   for _, plugin_name in ipairs(disp.item_order) do
      local item = disp.items[plugin_name]
      if item and #item.lines > 0 then
         local next_line
         set_lines(disp, line, line, item.lines)
         next_line = line + #item.lines + 1
         item.displayed = true
         disp.marks[plugin_name] = {
            start = set_extmark(disp.buf, disp.ns, nil, line - 1, 0),
            end_ = set_extmark(disp.buf, disp.ns, nil, next_line - 1, 0),
         }
         line = next_line
      else
         line = line + 1
      end
   end
end


display.final_results = vim.schedule_wrap(function(self, results, time, opts)
   self.opts = opts
   if not valid_display(self) then
      return
   end
   local keymap_display_order = {}
   vim.list_extend(keymap_display_order, default_keymap_display_order)
   self.results = results
   setup_status_syntax()
   display.running = false
   time = tonumber(time)
   self:update_headline_message(fmt('finished in %.3fs', time))
   local raw_lines = {}
   local item_order = {}
   if results.removals then
      for _, plugin_dir in ipairs(results.removals) do
         table.insert(item_order, plugin_dir)
         table.insert(raw_lines, fmt(' %s Removed %s', config.display.removed_sym, plugin_dir))
      end
   end

   if results.moves then
      for plugin, result in pairs(results.moves) do
         table.insert(item_order, plugin)
         local from = result.from
         local to = result.to

         table.insert(
         raw_lines,
         fmt(
         ' %s %s %s: %s %s %s',
         not result.err and config.display.done_sym or config.display.error_sym,
         not result.err and 'Moved' or 'Failed to move',
         plugin,
         from,
         config.display.moved_sym,
         to))


      end
   end

   display.any_failed_install = false
   display.failed_update_list = {}

   if results.installs then
      for plugin, result in pairs(results.installs) do
         table.insert(item_order, plugin)
         table.insert(
         raw_lines,
         fmt(
         ' %s %s %s',
         not result.err and config.display.done_sym or config.display.error_sym,
         not result.err and 'Installed' or 'Failed to install',
         plugin))


         display.any_failed_install = display.any_failed_install or result.err ~= nil
      end
   end

   if results.updates then
      local status_msg = 'Updated'
      if self:is_previewing() then
         status_msg = 'Can update'
         table.insert(keymap_display_order, 1, 'continue')
         table.insert(keymap_display_order, 2, 'toggle_update')
      end
      for plugin_name, result in pairs(results.updates) do
         local plugin = packer_plugins[plugin_name]
         local message = {}
         local actual_update = true
         local failed_update = false
         if not result.err then
            if self:has_changes(plugin) then
               table.insert(item_order, plugin_name)
               table.insert(message, make_update_msg(config.display.done_sym, status_msg, plugin_name, plugin))
            else
               actual_update = false
               table.insert(message, fmt(' %s %s is already up to date', config.display.done_sym, plugin_name))
            end
         else
            failed_update = true
            actual_update = false
            table.insert(display.failed_update_list, plugin_name)
            table.insert(item_order, plugin_name)
            table.insert(message, fmt(' %s Failed to update %s', config.display.error_sym, plugin_name))
         end

         if actual_update or failed_update then
            vim.list_extend(raw_lines, message)
         end
      end
   end

   self.item_order = item_order

   if #raw_lines == 0 then
      table.insert(raw_lines, ' Everything already up to date!')
   end

   table.insert(raw_lines, '')
   local show_retry = display.any_failed_install or #display.failed_update_list > 0
   for _, keymap in ipairs(keymap_display_order) do
      local k = keymaps[keymap]
      if k.lhs then
         if not (keymap == 'retry') or show_retry then
            table.insert(raw_lines, fmt(" Press '%s' to %s", k.lhs, k.action))
         end
      end
   end


   local lines = strip_newlines(raw_lines)
   set_lines(self, HEADER_LINES, -1, lines)
   for plugin_name, plugin in pairs(packer_plugins) do
      local item = {
         displayed = false,
         lines = {},
         plugin = plugin,
      }
      if plugin.err and #plugin.err > 0 then
         table.insert(item.lines, '  Errors:')
         for _, line in ipairs(plugin.err) do
            line = vim.trim(line)
            if line:find('\n') then
               for sub_line in line:gmatch('[^\r\n]+') do
                  table.insert(item.lines, '    ' .. sub_line)
               end
            else
               table.insert(item.lines, '    ' .. line)
            end
         end
         table.insert(item.lines, '')
      end

      if plugin.messages and #plugin.messages > 0 then
         table.insert(item.lines, fmt('  URL: %s', plugin.url))
         table.insert(item.lines, '  Commits:')
         for _, msg in ipairs(plugin.messages) do
            for _, line in ipairs(vim.split(msg, '\n')) do
               table.insert(item.lines, string.rep(' ', 4) .. line)
            end
         end

         table.insert(item.lines, '')
      end

      if plugin.breaking_commits and #plugin.breaking_commits > 0 then
         vim.cmd('syntax match packerBreakingChange "' .. plugin_name .. '" containedin=packerStatusSuccess')
         for _, commit_hash in ipairs(plugin.breaking_commits) do
            log.warn('Potential breaking change in commit ' .. commit_hash .. ' of ' .. plugin_name)
            vim.cmd('syntax match packerBreakingChange "' .. commit_hash .. '" containedin=packerHash')
         end
      end

      self.items = self.items or {}
      self.items[plugin_name] = item
   end

   if config.display.show_all_info then
      show_all_info(self)
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
      if m.lhs then
         vim.keymap.set('n', m.lhs, m.rhs, {
            desc = 'Packer: ' .. m.action,
            buffer = bufnr,
            nowait = true,
            silent = true,
         })
      end
   end

   vim.bo[bufnr].buftype = 'nofile'
   vim.bo[bufnr].bufhidden = 'wipe'
   vim.bo[bufnr].buflisted = false
   vim.bo[bufnr].swapfile = false

   local ft_cmds = make_filetype_cmds(
   config.display.working_sym,
   config.display.done_sym,
   config.display.error_sym)


   for _, c in ipairs(ft_cmds) do
      vim.cmd(c)
   end
end


function display.open(cbs)
   if not display.interactive then
      return
   end

   if not (display.win and api.nvim_win_is_valid(display.win)) then
      local opener = config.display.open_cmd
      vim.cmd(opener)
      display.win = api.nvim_get_current_win()
      display.buf = api.nvim_get_current_buf()
      display.ns = api.nvim_create_namespace('packer_display')
      setup_display_buf(display.buf)
   end

   display.callbacks = cbs
   display.results = nil
   display.items = nil
   display.marks = {}
   display.running = false

   set_lines(display, 0, -1, {})
   make_header(display)

   return display
end

return M