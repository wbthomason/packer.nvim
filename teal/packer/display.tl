local api = vim.api
local log = require 'packer.log'
local config = require 'packer.config'
local awrap = require 'packer.async'.wrap
local packer_plugins = require'packer.plugin'.plugins
local fmt = string.format

local Plugin = require'packer.plugin'.Plugin

local function is_plugin_line(line: string): boolean
  for _, sym in ipairs {
    config.display.item_sym,
    config.display.done_sym,
    config.display.working_sym,
    config.display.error_sym
  } do
    if line:find(sym, 1, true) then
      return true
    end
  end
  return false
end

local ns = api.nvim_create_namespace 'packer_display'

local record M

  record Display
    record Item
      enum Status
        'running'
        'failed'
        'success'
        'done'
      end

      status: Status

      message: string

      -- Additional info that can be collapsed
      info: {string}

      -- Whether info is being displayed
      expanded: boolean

      -- Extmark used track the location of the item in the buffer
      mark: integer
    end

    interactive   : boolean
    buf           : integer
    win           : integer

    items: {string:Item}

    running: boolean

    open                    : function(Display.Callbacks): Display
    check                   : function(Display): boolean
    task_update             : function(Display, plugin: string, msg: string, info: {string})
    task_start              : function(Display, plugin: string, msg: string, info: {string})
    task_succeeded          : function(Display, plugin: string, msg: string, info: {string})
    task_done               : function(Display, plugin: string, msg: string, info: {string})
    task_failed             : function(Display, plugin: string, msg: string, info: {string})
    update_headline_message : function(Display, string)
    finish                  : function(Display, number)
    ask_user                : function(string, {string}): boolean

    record Callbacks
      diff: function(plugin: Plugin, commit: string, callback: function): {string}
      revert_last: function(Plugin)
    end

    callbacks: Callbacks
  end

  display: Display
end

local HEADER_LINES <const> = 2
local TITLE <const> = 'packer.nvim'

local Display = M.Display

--- Check if we have a valid display window
local function valid_display(disp: Display): boolean
  return disp and disp.interactive and api.nvim_buf_is_valid(disp.buf) and api.nvim_win_is_valid(disp.win)
end

--- Heuristically find the plugin nearest to the cursor for displaying detailed information
local function find_nearest_plugin(disp: Display): string, {integer}
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

local function open_win(inner: boolean): integer, integer
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
    col = (vim.o.columns - width ) / 2
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

local function diff(disp: Display)
  if not valid_display(disp) then
    return
  end

  if next(disp.items) == nil then
    log.info 'Operations are still running; plugin info is not ready yet'
    return
  end

  local plugin_name = find_nearest_plugin(disp)
  if plugin_name == nil then
    log.warn 'No plugin selected!'
    return
  end

  local plugin = packer_plugins[plugin_name]

  if not plugin then
    log.warn 'Plugin not available!'
    return
  end

  local current_line = api.nvim_get_current_line()
  local commit = vim.fn.matchstr(current_line, COMMIT_RANGE_PAT)
  if commit == '' then
    commit = vim.fn.matchstr(current_line, COMMIT_SINGLE_PAT)
  end

  if commit == '' then
    log.warn 'Unable to find the diff for this line'
    return
  end

  disp.callbacks.diff(plugin, commit, function(lines: {string}, err: string)
    if err then
      log.warn 'Unable to get diff!'
      return
    end
    vim.schedule(function()
      if not lines or #lines < 1 then
        log.warn 'No diff available'
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

--- Update the text of the display buffer
local function set_lines(disp: Display, srow: integer, erow: integer, lines: {string})
  vim.bo[disp.buf].modifiable = true
  api.nvim_buf_set_lines(disp.buf, srow, erow, true, lines)
  vim.bo[disp.buf].modifiable = false
end

local function get_task_region(self: Display, plugin: string): integer, integer
  local mark = self.items[plugin].mark

  if not mark then
    return
  end

  local info = api.nvim_buf_get_extmark_by_id(self.buf, ns, mark, {details=true})

  local srow = info[1]
  local erow = info[3].end_row or srow

  -- TODO(lewis6991): sometimes the end_row will be lower and start_row. Could
  -- be an extmark bug?
  if srow > erow then
    srow, erow = erow, srow
  end

  return srow, erow
end

local function clear_task(self: Display, plugin: string)
  local srow, erow = get_task_region(self, plugin)
  set_lines(self, srow, erow, {})
  local item = self.items[plugin]
  api.nvim_buf_del_extmark(self.buf, ns, item.mark)
  item.mark = nil
end

local enum TaskPos
  'top'
  'bottom'
end

local function update_task_lines(self: Display, plugin: string, message: {string}, pos: TaskPos)
  local item = self.items[plugin]

  -- If pos is given, task will be rendered at the top or bottom of the buffer.
  -- If not given then will use last position, if exists, else bottom.
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
    end_row = srow + #message,
    id = item.mark
  })
end

local function pad(x: {string}): {string}
  local r = {}
  for i, s in ipairs(x) do
    r[i] = '   '..s
  end
  return r
end

local function render_task(self: Display, plugin: string)
  local item = self.items[plugin]

  local icon: string
  if not item.status then
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

  local pos: TaskPos = (item.status == 'success' or item.status == 'failed') and 'top' or nil

  update_task_lines(self, plugin, lines, pos)
end

  --- Toggle the display of detailed information for a plugin in the final results display
local function toggle_info(disp: Display)
  if not valid_display(disp) then
    return
  end

  if disp.items == nil or next(disp.items) == nil then
    log.info 'Operations are still running; plugin info is not ready yet'
    return
  end

  local plugin_name, cursor_pos = find_nearest_plugin(disp)
  if cursor_pos == nil then
    log.warn 'No plugin selected!'
    return
  end

  local item = disp.items[plugin_name]
  item.expanded = not item.expanded
  render_task(disp, plugin_name)
  api.nvim_win_set_cursor(disp.win, cursor_pos)
end

--- Utility function to prompt a user with a question in a floating window
local function prompt_user(headline: string, body: {string}, callback: function(boolean))
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
      local ans = string.lower(vim.fn.input 'OK to remove? [y/N] ') == 'y'
      api.nvim_win_close(win, true)
      callback(ans)
    end
  end))
end

--- Prompt a user to revert the latest update for a plugin
local function prompt_revert(disp: Display)
  if not valid_display(disp) then
    return
  end
  if next(disp.items) == nil then
    log.info 'Operations are still running; plugin info is not ready yet'
    return
  end

  local plugin_name = find_nearest_plugin(disp)
  if plugin_name == nil then
    log.warn 'No plugin selected!'
    return
  end

  local plugin = packer_plugins[plugin_name]
  local actual_update = plugin.revs[1] ~= plugin.revs[2]
  if actual_update then
    prompt_user('Revert update for ' .. plugin_name .. '?', {
      'Do you want to revert '
        .. plugin_name
        .. ' from '
        .. plugin.revs[2]
        .. ' to '
        .. plugin.revs[1]
        .. '?',
    }, function(ans: boolean)
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

local record Keymap
  action: string
  lhs: string|{string}
  rhs: function()
end

local keymaps: {string:Keymap} = {
  quit = {
    action = 'quit',
    rhs = function()
      -- Close a display window and signal that any running operations should terminate
      display.running = false
      vim.fn.execute('q!', 'silent')
    end,

  },

  diff = {
    action = 'show the diff',
    rhs = function()
      diff(display)
    end
  },

  toggle_info = {
    action = 'show more info',
    rhs = function()
      toggle_info(display)
    end
  },

  prompt_revert = {
    action = 'revert an update',
    rhs = function()
      prompt_revert(display)
    end
  },

}

function display:check(): boolean
  return not self.running
end

--- Start displaying a new task
display.task_start = vim.schedule_wrap(function(self: Display, plugin: string, message: string)
  if not valid_display(self) then
    return
  end

  local item = self.items[plugin]
  item.status = 'running'
  item.message = message

  render_task(self, plugin)
end)

--- Decrement the count of active operations in the headline
local function decrement_headline_count(disp: Display)
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
      headline:sub(count_end + 1)
    )
    set_lines(disp, 0, HEADER_LINES - 1, { updated_headline })
  end
end

local function normalize_lines(x: {string}): {string}
  local r: {string} = {}
  for _, l in ipairs(x) do
    for _, i in ipairs(vim.split(l, '\n')) do
      r[#r+1] = i
    end
  end
  return r
end

local task_done = vim.schedule_wrap(function(self: Display, plugin: string, message: string, info: {string}, success: boolean)
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

--- Update a task as having passively completed
function display:task_done(plugin: string, message: string, info: {string})
  task_done(self, plugin, message, info, nil)
end

--- Update a task as having successfully completed
function display:task_succeeded(plugin: string, message: string, info: {string})
  task_done(self, plugin, message, info, true)
end

--- Update a task as having unsuccessfully failed
function display:task_failed(plugin: string, message: string, info: {string})
  task_done(self, plugin, message, info, false)
end

--- Update the status message of a task in progress
display.task_update = vim.schedule_wrap(function(self: Display, plugin: string, message: string, info: {string})
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

--- Update the text of the headline message
display.update_headline_message = vim.schedule_wrap(function(self: Display, message: string)
  if not valid_display(self) then
    return
  end
  local headline = TITLE .. ' - ' .. message
  local width = api.nvim_win_get_width(self.win) - 2
  local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
  set_lines(self, 0, HEADER_LINES - 1, { string.rep(' ', pad_width) .. headline })
end)

--- Display the final results of an operation
display.finish = vim.schedule_wrap(function(self: Display, time: number)
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

local function look_back(str: string): string
  return fmt([[\(%s\)\@%d<=]], str, #str)
end

-- TODO: Option for no colors
local function make_filetype_cmds(working_sym: string, done_sym: string, error_sym: string): {string}
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

--- Utility to make the initial display buffer header
local function make_header(d: Display)
  local width = api.nvim_win_get_width(0)
  local pad_width = math.floor((width - TITLE:len()) / 2.0)
  set_lines(d, 0, 1, {
    (' '):rep(pad_width) .. TITLE,
    ' ' .. config.display.header_sym:rep(width - 2),
  })
end

--- Initialize options, settings, and keymaps for display windows
local function setup_display_buf(bufnr: integer)
  vim.bo[bufnr].filetype = 'packer'
  api.nvim_buf_set_name(bufnr, '[packer]')
  set_config_keymaps()
  for _, m in pairs(keymaps) do
    local lhs = m.lhs
    if lhs is string then
      lhs = {lhs}
    end
    lhs = lhs as {string}
    for _, x in ipairs(lhs) do
      vim.keymap.set('n', x, m.rhs, {
        desc = 'Packer: '..m.action,
        buffer = bufnr,
        nowait = true,
        silent = true,
      })
    end
  end

  local ft_cmds = make_filetype_cmds(
    config.display.working_sym,
    config.display.done_sym,
    config.display.error_sym
  )

  for _, c in ipairs(ft_cmds) do
    vim.cmd(c)
  end

  for _, c in ipairs{
    { 'packerStatus'          , 'Type'},
    { 'packerStatusCommit'    , 'Constant'},
    { 'packerStatusSuccess'   , 'Constant'},
    { 'packerStatusFail'      , 'ErrorMsg'},
    { 'packerPackageName'     , 'Title'},
    { 'packerPackageNotLoaded', 'Comment'},
    { 'packerString'          , 'String'},
    { 'packerBool'            , 'Boolean'},
    { 'packerBreakingChange'  , 'WarningMsg'},
  } do
    api.nvim_set_hl(0, c[1], { link = c[2], default = true, })
  end
end

--- Open a new display window
function display.open(cbs: Display.Callbacks): Display
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
    __index = function(t: {string:Display.Item}, k: string): Display.Item
      t[k] = { expanded = false }
      return t[k]
    end
  })

  set_lines(display, 0, -1, {})
  make_header(display)

  return display
end

return M
