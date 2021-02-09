local api = vim.api
local log = require('packer.log')
local a = require('packer.async')
local plugin_utils = require('packer.plugin_utils')
local fmt = string.format

local in_headless = #api.nvim_list_uis() == 0

-- Temporary wrappers to compensate for the updated extmark API, until most people have updated to
-- the latest HEAD (2020-09-04)
local function set_extmark(buf, ns, id, line, col)
  if not api.nvim_buf_is_valid(buf) then return end
  local opts = {id = id}
  local result, mark_id = pcall(api.nvim_buf_set_extmark, buf, ns, line, col, opts)
  if result then return mark_id end
  -- We must be in an older version of Neovim
  if not id then id = 0 end
  return api.nvim_buf_set_extmark(buf, ns, id, line, col, {})
end

local function get_extmark_by_id(buf, ns, id)
  local result, line, col = pcall(api.nvim_buf_get_extmark_by_id, buf, ns, id, {})
  if result then
    return line, col
  else
    log.error('Failed to get extmark: ' .. line)
  end
  -- We must be in an older version of Neovim
  return api.nvim_buf_get_extmark_by_id(buf, ns, id)
end

local function strip_newlines(raw_lines)
  local lines = {}
  for _, line in ipairs(raw_lines) do
    for _, chunk in ipairs(vim.split(line, '\n')) do table.insert(lines, chunk) end
  end

  return lines
end

local config = nil
local keymaps = {
  quit = {rhs = '<cmd>lua require"packer.display".quit()<cr>', action = 'quit'},
  diff = {rhs = '<cmd>lua require"packer.display".diff()<cr>', action = 'show the diff'},
  toggle_info = {
    rhs = '<cmd>lua require"packer.display".toggle_info()<cr>',
    action = 'show more info'
  },
  prompt_revert = {
    rhs = '<cmd>lua require"packer.display".prompt_revert()<cr>',
    action = 'revert an update'
  }
}

--- The order of the keys in a dict-like table isn't guaranteed, meaning the display window can
--- potentially show the keybindings in a different order every time
local keymap_display_order = {
  [1] = 'quit',
  [2] = 'toggle_info',
  [3] = 'diff',
  [4] = 'prompt_revert'
}

--- Utility function to prompt a user with a question in a floating window
local function prompt_user(headline, body, callback)
  if config.non_interactive then
    callback(true)
    return
  end

  local buf = api.nvim_create_buf(false, true)
  local longest_line = 0
  for _, line in ipairs(body) do
    local line_length = string.len(line)
    if line_length > longest_line then longest_line = line_length end
  end

  local width = math.min(longest_line + 2, math.floor(0.9 * vim.o.columns))
  local height = #body + 3
  local x = (vim.o.columns - width) / 2.0
  local y = (vim.o.lines - height) / 2.0
  local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
  api.nvim_buf_set_lines(buf, 0, -1, true, vim.list_extend(
                           {
      string.rep(' ', pad_width) .. headline .. string.rep(' ', pad_width), ''
    }, body))
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
    if not api.nvim_win_is_valid(win) then return end
    vim.loop.prepare_stop(check)
    if not prompted then
      prompted = true
      local ans = string.lower(vim.fn.input('OK to remove? [y/N] ')) == 'y'
      api.nvim_win_close(win, true)
      callback(ans)
    end
  end))
end

local display = {}
local display_mt = {
  --- Check if we have a valid display window
  valid_display = function(self)
    return self and self.interactive and api.nvim_buf_is_valid(self.buf)
             and api.nvim_win_is_valid(self.win)
  end,
  --- Update the text of the display buffer
  set_lines = function(self, start_idx, end_idx, lines)
    if not self:valid_display() then return end
    api.nvim_buf_set_option(self.buf, 'modifiable', true)
    api.nvim_buf_set_lines(self.buf, start_idx, end_idx, true, lines)
    api.nvim_buf_set_option(self.buf, 'modifiable', false)
  end,
  get_current_line = function(self)
    if not self:valid_display() then return end
    return api.nvim_get_current_line()
  end,
  --- Start displaying a new task
  task_start = vim.schedule_wrap(function(self, plugin, message)
    if not self:valid_display() then return end
    if self.marks[plugin] then
      self:task_update(plugin, message)
      return
    end
    display.status.running = true
    self:set_lines(config.header_lines, config.header_lines,
                   {fmt(' %s %s: %s', config.working_sym, plugin, message)})
    self.marks[plugin] = set_extmark(self.buf, self.ns, nil, config.header_lines, 0)
  end),

  --- Decrement the count of active operations in the headline
  decrement_headline_count = vim.schedule_wrap(function(self)
    if not self:valid_display() then return end
    local cursor_pos = api.nvim_win_get_cursor(self.win)
    api.nvim_win_set_cursor(self.win, {1, 0})
    api.nvim_buf_set_option(self.buf, 'modifiable', true)
    vim.fn.execute('normal! ')
    api.nvim_buf_set_option(self.buf, 'modifiable', false)
    api.nvim_win_set_cursor(self.win, cursor_pos)
  end),

  --- Update a task as having successfully completed
  task_succeeded = vim.schedule_wrap(function(self, plugin, message)
    if not self:valid_display() then return end
    local line, _ = get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    self:set_lines(line[1], line[1] + 1, {fmt(' %s %s: %s', config.done_sym, plugin, message)})
    api.nvim_buf_del_extmark(self.buf, self.ns, self.marks[plugin])
    self.marks[plugin] = nil
    self:decrement_headline_count()
  end),

  --- Update a task as having unsuccessfully failed
  task_failed = vim.schedule_wrap(function(self, plugin, message)
    if not self:valid_display() then return end
    local line, _ = get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    self:set_lines(line[1], line[1] + 1, {fmt(' %s %s: %s', config.error_sym, plugin, message)})
    api.nvim_buf_del_extmark(self.buf, self.ns, self.marks[plugin])
    self.marks[plugin] = nil
    self:decrement_headline_count()
  end),

  --- Update the status message of a task in progress
  task_update = vim.schedule_wrap(function(self, plugin, message)
    if not self:valid_display() then return end
    if not self.marks[plugin] then return end
    local line, _ = get_extmark_by_id(self.buf, self.ns, self.marks[plugin])
    self:set_lines(line[1], line[1] + 1, {fmt(' %s %s: %s', config.working_sym, plugin, message)})
    set_extmark(self.buf, self.ns, self.marks[plugin], line[1], 0)
  end),

  open_preview = function(_, commit, lines)
    if not lines or #lines < 1 then return log.warn('No diff available') end
    vim.cmd("pedit " .. commit)
    vim.cmd [[wincmd P]]
    vim.wo.previewwindow = true
    vim.bo.filetype = "git"
    vim.bo.buftype = "nofile"
    vim.bo.buflisted = false
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_buf_set_keymap(0, "n", "q", "<cmd>pclose!<CR>",
                                {silent = true, noremap = true, nowait = true})
  end,

  --- Update the text of the headline message
  update_headline_message = vim.schedule_wrap(function(self, message)
    if not self:valid_display() then return end
    local headline = config.title .. ' - ' .. message
    local width = api.nvim_win_get_width(self.win) - 2
    local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
    self:set_lines(0, config.header_lines - 1,
                   {string.rep(' ', pad_width) .. headline .. string.rep(' ', pad_width)})
  end),

  --- Setup new syntax group links for the status window
  setup_status_syntax = function(self)
    local highlights = {
      'hi def link packerStatus         Type', 'hi def link packerStatusCommit   Constant',
      'hi def link packerStatusSuccess  Constant', 'hi def link packerStatusFail     WarningMsg'
    }
    for _, c in ipairs(highlights) do vim.cmd(c) end
  end,

  --- Display the final results of an operation
  final_results = vim.schedule_wrap(function(self, results, time)
    if not self:valid_display() then return end
    self:setup_status_syntax()
    display.status.running = false
    time = tonumber(time)
    self:update_headline_message(fmt('finished in %.3fs', time))
    local raw_lines = {}
    local item_order = {}
    local rocks_items = {}
    if results.removals then
      for _, plugin_dir in ipairs(results.removals) do
        table.insert(item_order, plugin_dir)
        table.insert(raw_lines, fmt(' %s Removed %s', config.removed_sym, plugin_dir))
      end
    end

    if results.moves then
      for plugin, result in pairs(results.moves) do
        table.insert(item_order, plugin)
        table.insert(raw_lines,
                     fmt(' %s %s %s: %s %s %s',
                         result.result.ok and config.done_sym or config.error_sym,
                         result.result.ok and 'Moved' or 'Failed to move', plugin, result.from,
                         config.moved_sym, result.to))
      end
    end

    if results.installs then
      for plugin, result in pairs(results.installs) do
        table.insert(item_order, plugin)
        table.insert(raw_lines, fmt(' %s %s %s', result.ok and config.done_sym or config.error_sym,
                                    result.ok and 'Installed' or 'Failed to install', plugin))
      end
    end

    if results.updates then
      for plugin_name, result in pairs(results.updates) do
        local plugin = results.plugins[plugin_name]
        local message = {}
        local actual_update = true
        local failed_update = false
        if result.ok then
          if plugin.type ~= plugin_utils.git_plugin_type or plugin.revs[1] == plugin.revs[2] then
            actual_update = false
            table.insert(message, fmt(' %s %s is already up to date', config.done_sym, plugin_name))
          else
            table.insert(item_order, plugin_name)
            table.insert(message, fmt(' %s Updated %s: %s..%s', config.done_sym, plugin_name,
                                      plugin.revs[1], plugin.revs[2]))
          end
        else
          failed_update = true
          actual_update = false
          table.insert(item_order, plugin_name)
          table.insert(message, fmt(' %s Failed to update %s', config.error_sym, plugin_name))
        end

        plugin.actual_update = actual_update
        if actual_update or failed_update then vim.list_extend(raw_lines, message) end
      end
    end

    if results.luarocks then
      if results.luarocks.installs then
        for package, result in pairs(results.luarocks.installs) do
          if result.err then
            rocks_items[package] = {lines = strip_newlines(result.err.output.data.stderr)}
          end

          table.insert(raw_lines,
                       fmt(' %s %s %s', result.ok and config.done_sym or config.error_sym,
                           result.ok and 'Installed' or 'Failed to install', package))
        end
      end

      if results.luarocks.removals then
        for package, result in pairs(results.luarocks.removals) do
          if result.err then
            rocks_items[package] = {lines = strip_newlines(result.err.output.data.stderr)}
          end

          table.insert(raw_lines,
                       fmt(' %s %s %s', result.ok and config.done_sym or config.error_sym,
                           result.ok and 'Removed' or 'Failed to remove', package))
        end
      end
    end

    if #raw_lines == 0 then table.insert(raw_lines, ' Everything already up to date!') end

    table.insert(raw_lines, '')
    for _, keymap in ipairs(keymap_display_order) do
      if keymaps[keymap].lhs then
        table.insert(raw_lines,
                     fmt(" Press '%s' to %s", keymaps[keymap].lhs, keymaps[keymap].action))
      end
    end

    -- Ensure there are no newlines
    local lines = strip_newlines(raw_lines)
    self:set_lines(config.header_lines, -1, lines)
    local plugins = {}
    for plugin_name, plugin in pairs(results.plugins) do
      local plugin_data = {displayed = false, lines = {}, spec = plugin}
      if plugin.output then
        if plugin.output.err and #plugin.output.err > 0 then
          table.insert(plugin_data.lines, '  Errors:')
          for _, line in ipairs(plugin.output.err) do
            line = vim.trim(line)
            if line:find('\n') then
              for sub_line in line:gmatch("[^\r\n]+") do
                table.insert(plugin_data.lines, '    ' .. sub_line)
              end
            else
              table.insert(plugin_data.lines, '    ' .. line)
            end
          end
        end
      end

      if plugin.messages and #plugin.messages > 0 then
        table.insert(plugin_data.lines, '  Commits:')
        for _, msg in ipairs(plugin.messages) do
          for _, line in ipairs(vim.split(msg, '\n')) do
            table.insert(plugin_data.lines, string.rep(' ', 4) .. line)
          end
        end

        table.insert(plugin_data.lines, '')
      end

      plugins[plugin_name] = plugin_data
    end

    self.items = vim.tbl_extend('keep', plugins, rocks_items)
    self.item_order = item_order
    if config.show_all_info then self:show_all_info() end
  end),

  --- Toggle the display of detailed information for all plugins in the final results display
  show_all_info = function(self)
    if not self:valid_display() then return end
    if next(self.items) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
    end

    local line = config.header_lines + 1
    for _, plugin_name in pairs(self.item_order) do
      local plugin_data = self.items[plugin_name]
      if plugin_data and plugin_data.spec.actual_update and #plugin_data.lines > 0 then
        self:set_lines(line, line, plugin_data.lines)
        line = line + #plugin_data.lines + 1
        plugin_data.displayed = true
      else
        line = line + 1
      end
    end
  end,

  --- Toggle the display of detailed information for a plugin in the final results display
  toggle_info = function(self)
    if not self:valid_display() then return end
    if self.items == nil or next(self.items) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
    end

    local plugin_name, cursor_pos = self:find_nearest_plugin()
    if plugin_name == nil then
      log.warn('No plugin selected!')
      return
    end

    local plugin_data = self.items[plugin_name]
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

  diff = function(self)
    if not self:valid_display() then return end
    if next(self.items) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
    end

    local plugin_name, _ = self:find_nearest_plugin()
    if plugin_name == nil then
      log.warn('No plugin selected!')
      return
    end

    if not self.items[plugin_name] or not self.items[plugin_name].spec then
      log.warn('Plugin not available!')
      return
    end

    local plugin_data = self.items[plugin_name].spec
    local current_line = self:get_current_line()
    local commit_hash = vim.fn.matchstr(current_line, [[\X*\zs[0-9a-f]\{7,9}]])
    if not commit_hash then
      log.warn('Unable to find the diff for this line')
      return
    end
    plugin_data.diff(commit_hash, function(diff, err)
      if err then return log.warn('Unable to get diff!') end
      local lines = vim.split(diff[1], '\n')
      vim.schedule(function() self:open_preview(commit_hash, lines) end)
    end)
  end,

  --- Prompt a user to revert the latest update for a plugin
  prompt_revert = function(self)
    if not self:valid_display() then return end
    if next(self.items) == nil then
      log.info('Operations are still running; plugin info is not ready yet')
      return
    end

    local plugin_name, _ = self:find_nearest_plugin()
    if plugin_name == nil then
      log.warn('No plugin selected!')
      return
    end

    local plugin_data = self.items[plugin_name].spec
    if plugin_data.actual_update then
      prompt_user('Revert update for ' .. plugin_name .. '?', {
        'Do you want to revert ' .. plugin_name .. ' from ' .. plugin_data.revs[2] .. ' to '
          .. plugin_data.revs[1] .. '?'
      }, function(ans)
        if ans then
          local r = plugin_data.revert_last()
          if r.ok then
            log.info('Reverted update for ' .. plugin_name)
          else
            log.error('Reverting update for ' .. plugin_name .. ' failed!')
          end
        end
      end)
    else
      log.warn(plugin_name .. " wasn't updated; can't revert!")
    end
  end,

  --- Heuristically find the plugin nearest to the cursor for displaying detailed information
  find_nearest_plugin = function(self)
    if not self:valid_display() then return end
    local cursor_pos = api.nvim_win_get_cursor(0)
    -- TODO: this is a dumb hack
    for i = cursor_pos[1], 1, -1 do
      local curr_line = api.nvim_buf_get_lines(0, i - 1, i, true)[1]
      for name, _ in pairs(self.items) do
        if string.find(curr_line, name, 1, true) then return name, {i, 0} end
      end
    end
  end
}

display_mt.__index = display_mt

-- TODO: Option for no colors
local function make_filetype_cmds(working_sym, done_sym, error_sym)
  return {
    -- Adapted from https://github.com/kristijanhusak/vim-packager
    'setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nowrap nospell nonumber norelativenumber nofoldenable signcolumn=no',
    'syntax clear', 'syn match packerWorking /^ ' .. working_sym .. '/',
    'syn match packerSuccess /^ ' .. done_sym .. '/',
    'syn match packerFail /^ ' .. error_sym .. '/',
    'syn match packerStatus /\\(^+.*—\\)\\@<=\\s.*$/',
    'syn match packerStatusSuccess /\\(^ ' .. done_sym .. '.*\\)\\@<=\\s.*$/',
    'syn match packerStatusFail /\\(^ ' .. error_sym .. '.*\\)\\@<=\\s.*$/',
    'syn match packerStatusCommit /\\(^\\*.*—\\)\\@<=\\s.*$/',
    'syn match packerHash /\\(\\s\\)[0-9a-f]\\{7,8}\\(\\s\\)/',
    'syn match packerRelDate /([^)]*)$/', 'syn match packerProgress /\\(\\[\\)\\@<=[\\=]*/',
    'syn match packerOutput /\\(Output:\\)\\|\\(Commits:\\)\\|\\(Errors:\\)/',
    'hi def link packerWorking        SpecialKey', 'hi def link packerSuccess        Question',
    'hi def link packerFail           ErrorMsg', 'hi def link packerHash           Identifier',
    'hi def link packerRelDate        Comment', 'hi def link packerProgress       Boolean',
    'hi def link packerOutput         Type'
  }
end

display.cfg = function(_config)
  config = _config.display
  if config.keybindings then
    for name, lhs in pairs(config.keybindings) do
      if keymaps[name] then keymaps[name].lhs = lhs end
    end
  end
  config.filetype_cmds = make_filetype_cmds(config.working_sym, config.done_sym, config.error_sym)
end

--- Utility to make the initial display buffer header
local function make_header(disp)
  local width = api.nvim_win_get_width(0)
  local pad_width = math.floor((width - string.len(config.title)) / 2.0)
  api.nvim_buf_set_lines(disp.buf, 0, 1, true, {
    string.rep(' ', pad_width) .. config.title,
    ' ' .. string.rep(config.header_sym, width - 2) .. ' '
  })
end

--- Initialize options, settings, and keymaps for display windows
local function setup_window(disp)
  api.nvim_buf_set_option(disp.buf, 'filetype', 'packer')
  for _, m in pairs(keymaps) do
    if m.lhs then
      api.nvim_buf_set_keymap(disp.buf, 'n', m.lhs, m.rhs, {nowait = true, silent = true})
    end
  end
  for _, c in ipairs(config.filetype_cmds) do vim.cmd(c) end
end

--- Open a new display window
-- Takes either a string representing a command or a function returning a (window, buffer) pair.
display.open = function(opener)
  if display.status.disp then
    if api.nvim_win_is_valid(display.status.disp.win) then
      api.nvim_win_close(display.status.disp.win, true)
    end

    display.status.disp = nil
  end

  local disp = setmetatable({}, display_mt)
  disp.marks = {}
  disp.plugins = {}
  disp.interactive = not config.non_interactive and not in_headless

  if disp.interactive then
    if type(opener) == 'string' then
      vim.cmd(opener)
      disp.win = api.nvim_get_current_win()
      disp.buf = api.nvim_get_current_buf()
    else
      local status, win, buf = opener('[packer]')
      if not status then
        log.error('Failure running opener function: ' .. vim.inspect(win))
        error(win)
      end

      disp.win = win
      disp.buf = buf
    end

    disp.ns = api.nvim_create_namespace('')
    make_header(disp)
    setup_window(disp)
    display.status.disp = disp
  end

  return disp
end

display.status = {running = false, disp = nil}

--- Close a display window and signal that any running operations should terminate
display.quit = function()
  display.status.running = false
  vim.fn.execute('q!', 'silent')
end

display.toggle_info =
  function() if display.status.disp then display.status.disp:toggle_info() end end

display.diff = function() if display.status.disp then display.status.disp:diff() end end

display.prompt_revert = function()
  if display.status.disp then display.status.disp:prompt_revert() end
end

--- Async prompt_user
display.ask_user = a.wrap(prompt_user)

return display
