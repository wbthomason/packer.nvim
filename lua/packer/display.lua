local api  = vim.api
local log  = require('packer/log')
local a    = require('packer/async')

local config = nil
local keymaps = {
  { 'n', 'q', '<cmd>lua require"packer/display".quit()<cr>', { nowait = true, silent = true } },
  { 'n', '<cr>', '<cmd>lua require"packer/display".toggle_info()<cr>', { nowait = true, silent = true } }
}

local display = {}
local display_mt = {
  set_lines = function(self, start_idx, end_idx, lines)
    api.nvim_buf_set_option(self.buf, 'modifiable', true)
    api.nvim_buf_set_lines(self.buf, start_idx, end_idx, true, lines)
    api.nvim_buf_set_option(self.buf, 'modifiable', false)
  end,
  task_start = vim.schedule_wrap(function(self, plugin, message)
    if not api.nvim_buf_is_valid(self.buf) then
      return
    end

    display.status.running = true
    self:set_lines(
      config.header_lines,
      config.header_lines,
      { string.format('%s %s: %s', config.working_sym, plugin, message) }
    )
    self.marks[plugin] = api.nvim_buf_set_extmark(self.buf, self.ns, 0, config.header_lines, 0, {})
  end),

  decrement_headline_count = vim.schedule_wrap(function(self)
    if not api.nvim_win_is_valid(self.win) then
      return
    end

    local cursor_pos = api.nvim_win_get_cursor(self.win)
    api.nvim_win_set_cursor(self.win, {1, 0})
    api.nvim_buf_set_option(self.buf, 'modifiable', true)
    vim.fn.execute('normal! ')
    api.nvim_buf_set_option(self.buf, 'modifiable', false)
    api.nvim_win_set_cursor(self.win, cursor_pos)
  end),

  task_succeeded = vim.schedule_wrap(function(self, plugin, message)
    if not api.nvim_buf_is_valid(self.buf) then
      return
    end

    local line, _ = api.nvim_buf_get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    self:set_lines(
      line[1],
      line[1] + 1,
      { string.format('%s %s: %s', config.done_sym, plugin, message) }
    )
    api.nvim_buf_del_extmark(self.buf, self.ns, self.marks[plugin])
    self.marks[plugin] = nil
    self:decrement_headline_count()
  end),

  task_failed = vim.schedule_wrap(function(self, plugin, message)
    if not api.nvim_buf_is_valid(self.buf) then
      return
    end

    local line, _ = api.nvim_buf_get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    self:set_lines(
      line[1],
      line[1] + 1,
      { string.format('%s %s: %s', config.error_sym, plugin, message) }
    )
    api.nvim_buf_del_extmark(self.buf, self.ns, self.marks[plugin])
    self.marks[plugin] = nil
    self:decrement_headline_count()
  end),

  task_update = vim.schedule_wrap(function(self, plugin, message)
    if not api.nvim_buf_is_valid(self.buf) then
      return
    end

    local line, _ = api.nvim_buf_get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    self:set_lines(
      line[1],
      line[1] + 1,
      { string.format('%s %s: %s', config.working_sym, plugin, message) }
    )
    api.nvim_buf_set_extmark(self.buf, self.ns, self.marks[plugin], line[1], 0, {})
  end),

  update_headline_message = vim.schedule_wrap(function(self, message)
    if not api.nvim_buf_is_valid(self.buf) or not api.nvim_win_is_valid(self.win) then
      return
    end

    local headline = config.title .. ' - ' .. message
    local width = api.nvim_win_get_width(self.win) - 2
    local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
    self:set_lines(
      0,
      config.header_lines - 1,
      { string.rep(' ', pad_width) .. headline .. string.rep(' ', pad_width) }
    )
  end),

  increment_headline_count = vim.schedule_wrap(function(self)
    if not api.nvim_win_is_valid(self.win) then
      return
    end

    local cursor_pos = api.nvim_win_get_cursor(self.win)
    api.nvim_win_set_cursor(self.win, {1, 0})
    api.nvim_buf_set_option(self.buf, 'modifiable', true)
    vim.fn.execute('normal! ')
    api.nvim_buf_set_option(self.buf, 'modifiable', false)
    api.nvim_win_set_cursor(self.win, cursor_pos)
  end),

  final_results = vim.schedule_wrap(function(self, results, time)
    if not api.nvim_buf_is_valid(self.buf) or not api.nvim_win_is_valid(self.win) then
      return
    end

    display.status.running = false
    time = tonumber(time)
    self:update_headline_message(string.format('finished in %.3fs', time))
    local raw_lines = {}
    if results.removals then
      for _, plugin_dir in pairs(results.removals) do
        table.insert(
          raw_lines,
          string.format(
            '%s Removed %s',
            config.removed_sym,
            plugin_dir
          )
        )
      end
    end

    if results.moves then
      for plugin, result in pairs(results.moves) do
        table.insert(
          raw_lines,
          string.format(
            '%s %s %s: %s %s %s',
            result.result.ok and config.done_sym or config.error_sym,
            result.result.ok and 'Moved' or 'Failed to move',
            plugin,
            result.from,
            config.moved_sym,
            result.to
          )
        )
      end
    end

    if results.installs then
      for plugin, result in pairs(results.installs) do
        table.insert(
          raw_lines,
          string.format(
            '%s %s %s',
            result.ok and config.done_sym or config.error_sym,
            result.ok and 'Installed' or 'Failed to install',
            plugin
          )
        )
      end
    end

    if results.updates then
      for plugin_name, result in pairs(results.updates) do
        local plugin = results.plugins[plugin_name]
        local message = {}
        local actual_update = true
        if result.ok then
          if plugin.type ~= 'git' or plugin.revs[1] == plugin.revs[2] then
            actual_update = false
            table.insert(message, string.format('%s %s is already up to date', config.done_sym, plugin_name))
          else
            table.insert(message, string.format(
              '%s Updated %s: %s..%s',
              config.done_sym,
              plugin_name,
              plugin.revs[1],
              plugin.revs[2]
            ))
          end
        else
          table.insert(
            message,
            string.format(
              '%s Failed to update %s: %s',
              config.error_sym,
              plugin_name,
              vim.inspect(result.err)
            )
          )
        end

        if actual_update then
          vim.list_extend(raw_lines, message)
        end
      end
    end

    if #raw_lines == 0 then
      table.insert(raw_lines, 'Everything already up to date!')
    end

    -- Ensure there are no newlines
    local lines = {}
    for _, line in ipairs(raw_lines) do
      for _, chunk in ipairs(vim.split(line, '\n')) do
        table.insert(lines, chunk)
      end
    end

    self:set_lines(config.header_lines, -1, lines)
    local plugins = {}
    for plugin_name, plugin in pairs(results.plugins) do
      local plugin_data = { displayed = false, lines = {} }
      if plugin.output then
        if plugin.output.err and #plugin.output.err > 0 then
          table.insert(plugin_data.lines, '  Errors:')
          for _, line in ipairs(plugin.output.err) do
            line = string.gsub(vim.trim(line), '\n', ' ')
            table.insert(plugin_data.lines, '    ' .. line)
          end
        end
      end

      if plugin.messages then
        table.insert(plugin_data.lines, '  Commits:')
        for _, msg in ipairs(plugin.messages) do
          for _, line in ipairs(vim.split(msg, '\n')) do
            table.insert(plugin_data.lines, string.rep(' ', 4) .. line)
          end
        end
      end
      plugins[plugin_name] = plugin_data
    end

    self.plugins = plugins
  end),

  toggle_info = function(self)
    if not api.nvim_buf_is_valid(self.buf)
      or not api.nvim_win_is_valid(self.win) then
      return
    end

    if next(self.plugins) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
    end

    local plugin_name, cursor_pos = self:find_nearest_plugin()
    if plugin_name == nil then
      log.warning('nil plugin name!')
      return
    end

    local plugin_data = self.plugins[plugin_name]
    if plugin_data.displayed then
      self:set_lines(cursor_pos[1], cursor_pos[1] + #plugin_data.lines, {})
      plugin_data.displayed = false
    elseif #plugin_data.lines > 0 then
      self:set_lines(cursor_pos[1], cursor_pos[1], plugin_data.lines)
      plugin_data.displayed = true
    else
      log.info('No further information for ' .. plugin_name)
    end
  end,

  find_nearest_plugin = function(self)
    local cursor_pos = api.nvim_win_get_cursor(0)
    -- TODO: this is a dumb hack
    for i = cursor_pos[1], 1, -1 do
      local curr_line = api.nvim_buf_get_lines(0, i - 1, i, true)[1]
      for name, _ in pairs(self.plugins) do
        if string.find(curr_line, name, 1, true) then
          return name, { i, 0 }
        end
      end
    end
  end
}

display_mt.__index = display_mt

-- TODO: Option for no colors
local function make_filetype_cmds(working_sym, done_sym, error_sym)
  return {
    -- Adapted from https://github.com/kristijanhusak/vim-packager
    'setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nowrap nospell nonumber norelativenumber nofoldenable signcolumn=yes:2',
    'syntax clear',
    'syn match packerWorking /^' .. working_sym .. '/',
    'syn match packerSuccess /^' .. done_sym .. '/',
    'syn match packerFail /^' .. error_sym .. '/',
    'syn match packerStatus /\\(^+.*—\\)\\@<=\\s.*$/',
    'syn match packerStatusSuccess /\\(^' .. done_sym .. '.*—\\)\\@<=\\s.*$/',
    'syn match packerStatusFail /\\(^' .. error_sym .. '.*—\\)\\@<=\\s.*$/',
    'syn match packerStatusCommit /\\(^\\*.*—\\)\\@<=\\s.*$/',
    'syn match packerHash /\\(\\s\\)[0-9a-f]\\{7,8}\\(\\s\\)/',
    'syn match packerRelDate /([^)]*)$/',
    'syn match packerProgress /\\(\\[\\)\\@<=[\\=]*/',
    'syn match packerOutput /\\(Output:\\)\\|\\(Commits:\\)\\|\\(Errors:\\)/',
    'hi def link packerWorking        SpecialKey',
    'hi def link packerSuccess        Question',
    'hi def link packerFail           ErrorMsg',
    'hi def link packerStatus         Constant',
    'hi def link packerStatusCommit   Constant',
    'hi def link packerStatusSuccess  Function',
    'hi def link packerStatusFail     WarningMsg',
    'hi def link packerHash           Identifier',
    'hi def link packerRelDate        Comment',
    'hi def link packerProgress       Boolean',
    'hi def link packerOutput         Type',
  }
end

display.cfg = function(_config)
  config = _config.display
  config.filetype_cmds = make_filetype_cmds(
    config.working_sym,
    config.done_sym,
    config.error_sym
  )
end

local function make_header(disp)
  local width = api.nvim_win_get_width(0) - 2
  local pad_width = math.floor((width - string.len(config.title)) / 2.0)
  api.nvim_buf_set_lines(
    disp.buf,
    0,
    1,
    true,
    {
      string.rep(' ', pad_width) .. config.title,
      ' ' .. string.rep(config.header_sym, width - 4) .. ' '
    }
  )
end

local function setup_window(disp)
  api.nvim_buf_set_option(disp.buf, 'filetype', 'packer')
  for _, m in ipairs(keymaps) do
    api.nvim_buf_set_keymap(disp.buf, m[1], m[2], m[3], m[4])
  end

  for _, c in ipairs(config.filetype_cmds) do
    api.nvim_command(c)
  end
end

display.open = function(opener)
  if display.status.disp then
    if api.nvim_win_is_valid(display.status.disp.win) then
      api.nvim_win_close(display.status.disp.win, true)
    end

    display.status.disp = nil
  end

  local disp = setmetatable({}, display_mt)
  if type(opener) == 'string' then
    api.nvim_command(opener)
    disp.win = api.nvim_get_current_win()
    disp.buf = api.nvim_get_current_buf()
  else
    disp.win, disp.buf = opener('[packer]')
  end

  disp.marks = {}
  disp.plugins = {}
  disp.ns = api.nvim_create_namespace('')
  make_header(disp)
  setup_window(disp)

  display.status.disp = disp

  return disp
end

display.status = { running = false, disp = nil }

display.quit = function()
  display.status.running = false
  vim.fn.execute('q!', 'silent')
end

display.toggle_info = function()
  if display.status.disp then
    display.status.disp:toggle_info()
  end
end

display.ask_user = a.wrap(function(headline, body, callback)
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
  api.nvim_buf_set_lines(buf, 0, -1, true,
    vim.list_extend({ string.rep(' ', pad_width) .. headline .. string.rep(' ', pad_width), '' }, body))
  api.nvim_buf_set_option(buf, 'modifiable', false)
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = x,
    row = y,
    focusable = false,
    style = 'minimal'
  }

  local win = api.nvim_open_win(buf, false, opts)
  local check = vim.loop.new_prepare()
  local prompted = false
  vim.loop.prepare_start(check, vim.schedule_wrap(function()
    if not api.nvim_win_is_valid(win) then
      return
    end

    vim.loop.prepare_stop(check)
    if not prompted then
      prompted = true
      local ans = string.lower(vim.fn.input('OK to remove? [y/N] ')) == 'y'
      api.nvim_win_close(win, true)
      callback(ans)
    end
  end))
end)

return display
