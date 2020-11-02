-- Compiling plugin specifications to Lua for lazy-loading
local util = require('packer.util')
local log = require('packer.log')
local fmt = string.format

local config = nil

local function cfg(_config) config = _config end

local feature_guard = [[
if !has('nvim')
  finish
endif
]]

local vim_loader = [[
function! s:load(names, cause) abort
call luaeval('_packer_load(_A[1], _A[2])', [a:names, a:cause])
endfunction
]]

local lua_loader = [[
local function handle_bufread(names)
  for _, name in ipairs(names) do
    local path = plugins[name].path
    for _, dir in ipairs({ 'ftdetect', 'ftplugin', 'after/ftdetect', 'after/ftplugin' }) do
      if #vim.fn.finddir(dir, path) > 0 then
        vim.cmd('doautocmd BufRead')
        return
      end
    end
  end
end

_packer_load = nil

local function handle_after(name, before)
  local plugin = plugins[name]
  plugin.load_after[before] = nil
  if next(plugin.load_after) == nil then
    _packer_load({name}, {})
  end
end

_packer_load = function(names, cause)
  local some_unloaded = false
  for _, name in ipairs(names) do
    if not plugins[name].loaded then
      some_unloaded = true
      break
    end
  end

  if not some_unloaded then return end

  local fmt = string.format
  local del_cmds = {}
  local del_maps = {}
  for _, name in ipairs(names) do
    if plugins[name].commands then
      for _, cmd in ipairs(plugins[name].commands) do
        del_cmds[cmd] = true
      end
    end

    if plugins[name].keys then
      for _, key in ipairs(plugins[name].keys) do
        del_maps[key] = true
      end
    end
  end

  for cmd, _ in pairs(del_cmds) do
    vim.cmd('silent! delcommand ' .. cmd)
  end

  for key, _ in pairs(del_maps) do
    vim.cmd(fmt('silent! %sunmap %s', key[1], key[2]))
  end

  for _, name in ipairs(names) do
    if not plugins[name].loaded then
      vim.cmd('packadd ' .. name)
      if plugins[name].config then
        for _i, config_line in ipairs(plugins[name].config) do
          loadstring(config_line)()
        end
      end

      if plugins[name].after then
        for _, after_name in ipairs(plugins[name].after) do
          handle_after(after_name, name)
          vim.cmd('redraw')
        end
      end

      plugins[name].loaded = true
    end
  end

  handle_bufread(names)

  if cause.cmd then
    local lines = cause.l1 == cause.l2 and '' or (cause.l1 .. ',' .. cause.l2)
    vim.cmd(fmt('%s%s%s %s', lines, cause.cmd, cause.bang, cause.args))
  elseif cause.keys then
    local keys = cause.keys
    local extra = ''
    while true do
      local c = vim.fn.getchar(0)
      if c == 0 then break end
      extra = extra .. vim.fn.nr2char(c)
    end

    if cause.prefix then
      local prefix = vim.v.count and vim.v.count or ''
      prefix = prefix .. '"' .. vim.v.register .. cause.prefix
      if vim.fn.mode('full') == 'no' then
        if vim.v.operator == 'c' then
          prefix = '' .. prefix
        end

        prefix = prefix .. vim.v.operator
      end

      vim.fn.feedkeys(prefix, 'n')
    end

    -- NOTE: I'm not sure if the below substitution is correct; it might correspond to the literal
    -- characters \<Plug> rather than the special <Plug> key.
    vim.fn.feedkeys(string.gsub(string.gsub(cause.keys, '^<Plug>', '\\<Plug>') .. extra, '<[cC][rR]>', '\r'))
  elseif cause.event then
    vim.cmd(fmt('doautocmd <nomodeline> %s', cause.event))
  elseif cause.ft then
    vim.cmd(fmt('doautocmd <nomodeline> %s FileType %s', 'filetypeplugin', cause.ft))
    vim.cmd(fmt('doautocmd <nomodeline> %s FileType %s', 'filetypeindent', cause.ft))
  end
end
]]

local function make_loaders(_, plugins)
  local loaders = {}
  local configs = {}
  local rtps = {}
  local setup = {}
  local fts = {}
  local events = {}
  local conditions = {}
  local commands = {}
  local keymaps = {}
  local after = {}
  for name, plugin in pairs(plugins) do
    if not plugin.disable then
      local quote_name = "'" .. name .. "'"
      if plugin.config then
        plugin.executable_config = {}
        if type(plugin.config) ~= 'table' then plugin.config = {plugin.config} end
        for i, config_item in ipairs(plugin.config) do
          local executable_string = config_item
          if type(config_item) == 'function' then
            local stringified = string.dump(config_item, true)
            executable_string = 'loadstring(' .. vim.inspect(stringified) .. ')()'
            if not plugin.opt then stringified = executable_string end
            plugin.config[i] = stringified
          end

          table.insert(plugin.executable_config, executable_string)
        end
      end

      if plugin.config and not plugin.opt then configs[name] = plugin.config end

      if plugin.rtp then table.insert(rtps, util.join_paths(plugin.install_path, plugin.rtp)) end

      if plugin.opt then
        loaders[name] = {
          loaded = false,
          config = plugin.config,
          path = plugin.install_path .. (plugin.rtp and plugin.rtp or ''),
          only_sequence = plugin.manual_opt == nil,
          only_setup = false
        }

        if plugin.setup then
          if type(plugin.setup) ~= 'table' then plugin.setup = {plugin.setup} end
          for i, setup_item in ipairs(plugin.setup) do
            if type(setup_item) == 'function' then
              local stringified = vim.inspect(string.dump(setup_item, true))
              plugin.setup[i] = 'loadstring(' .. stringified .. ')()'
            end
          end

          loaders[name].only_setup = plugin.manual_opt == nil
          setup[name] = plugin.setup
        end

        if plugin.ft then
          loaders[name].only_sequence = false
          loaders[name].only_setup = false
          if type(plugin.ft) == 'string' then plugin.ft = {plugin.ft} end

          for _, ft in ipairs(plugin.ft) do
            fts[ft] = fts[ft] or {}
            table.insert(fts[ft], quote_name)
          end
        end

        if plugin.event then
          loaders[name].only_sequence = false
          loaders[name].only_setup = false
          if type(plugin.event) == 'string' then plugin.event = {plugin.event} end

          for _, event in ipairs(plugin.event) do
            events[event] = events[event] or {}
            table.insert(events[event], quote_name)
          end
        end

        if plugin.cond then
          loaders[name].only_sequence = false
          loaders[name].only_setup = false
          if type(plugin.cond) == 'string' or type(plugin.cond) == 'function' then
            plugin.cond = {plugin.cond}
          end

          for _, condition in ipairs(plugin.cond) do
            if type(condition) == 'function' then
              condition = 'loadstring(' .. vim.inspect(string.dump(condition, true)) .. ')()'
            end

            conditions[condition] = conditions[condition] or {}
            table.insert(conditions[condition], name)
          end
        end

        if plugin.cmd then
          loaders[name].only_sequence = false
          loaders[name].only_setup = false
          if type(plugin.cmd) == 'string' then plugin.cmd = {plugin.cmd} end

          loaders[name].commands = {}
          for _, command in ipairs(plugin.cmd) do
            commands[command] = commands[command] or {}
            table.insert(loaders[name].commands, command)
            table.insert(commands[command], quote_name)
          end
        end

        if plugin.keys then
          loaders[name].only_sequence = false
          loaders[name].only_setup = false
          if type(plugin.keys) == 'string' then plugin.keys = {plugin.keys} end
          loaders[name].keys = {}
          for _, keymap in ipairs(plugin.keys) do
            if type(keymap) == 'string' then keymap = {'', keymap} end
            keymaps[keymap] = keymaps[keymap] or {}
            table.insert(loaders[name].keys, keymap)
            table.insert(keymaps[keymap], quote_name)
          end
        end

        if plugin.after then
          loaders[name].only_setup = false

          if type(plugin.after) == 'string' then plugin.after = {plugin.after} end

          for _, other_plugin in ipairs(plugin.after) do
            after[other_plugin] = after[other_plugin] or {}
            table.insert(after[other_plugin], name)
          end
        end
      end
    end
  end

  local ft_aucmds = {}
  for ft, names in pairs(fts) do
    table.insert(ft_aucmds, fmt('  au FileType %s ++once call s:load([%s], { "ft": "%s" })', ft,
    table.concat(names, ', '), ft))
  end

  local event_aucmds = {}
  for event, names in pairs(events) do
    table.insert(event_aucmds, fmt('  au %s ++once call s:load([%s], { "event": "%s" })', event,
    table.concat(names, ', '), event))
  end

  local config_lines = {}
  for name, plugin_config in pairs(configs) do
    local lines = {'-- Config for: ' .. name}
    vim.list_extend(lines, plugin_config)
    vim.list_extend(config_lines, lines)
  end

  local rtp_line = ''
  for _, rtp in ipairs(rtps) do rtp_line = rtp_line .. '",' .. vim.fn.escape(rtp, '\\,') .. '"' end

  if rtp_line ~= '' then rtp_line = 'vim.o.runtimepath = vim.o.runtimepath .. ' .. rtp_line end

  local setup_lines = {}
  for name, plugin_setup in pairs(setup) do
    local lines = {'-- Setup for: ' .. name}
    vim.list_extend(lines, plugin_setup)
    if loaders[name].only_setup then table.insert(lines, 'vim.cmd("packadd ' .. name .. '")') end

    vim.list_extend(setup_lines, lines)
  end

  local conditionals = {}
  for condition, names in pairs(conditions) do
    local conditional_loads = {}
    for _, name in ipairs(names) do
      table.insert(conditional_loads, 'vim.cmd("packadd ' .. name .. '")')
      if plugins[name].config then
        local lines = {'', '-- Config for: ' .. name}
        vim.list_extend(lines, plugins[name].executable_config)
        table.insert(lines, '')
        vim.list_extend(conditional_loads, lines)
      end
    end

    local conditional = [[if
    ]] .. condition .. [[

    then
      ]] .. table.concat(conditional_loads, '\n\t') .. [[

    end
    ]]

    table.insert(conditionals, conditional)
  end

  local command_defs = {}
  for command, names in pairs(commands) do
    local command_line = fmt(
    'command! -nargs=* -range -bang -complete=file %s call s:load([%s], { "cmd": "%s", "l1": <line1>, "l2": <line2>, "bang": <q-bang>, "args": <q-args> })',
    command, table.concat(names, ', '), command)
    table.insert(command_defs, command_line)
  end

  local keymap_defs = {}
  for keymap, names in pairs(keymaps) do
    local prefix = nil
    if keymap[1] ~= 'i' then prefix = '' end
    local cr_escaped_map = string.gsub(keymap[2], '<[cC][rR]>', '\\<CR\\>')
    local keymap_line = fmt(
    '%snoremap <silent> %s <cmd>call <SID>load([%s], { "keys": "%s"%s })<cr>',
    keymap[1], keymap[2], table.concat(names, ', '), cr_escaped_map,
    prefix == nil and '' or (', "prefix": "' .. prefix .. '"'))

    table.insert(keymap_defs, keymap_line)
  end

  local sequence_loads = {}
  for pre, posts in pairs(after) do
    if plugins[pre].opt then
      loaders[pre].after = posts
      for _, name in ipairs(posts) do
        loaders[name].load_after = {}
        sequence_loads[name] = sequence_loads[name] or {}
        table.insert(sequence_loads[name], pre)
      end
    end
  end

  local sequence_lines = {}
  local graph = {}
  for name, precedents in pairs(sequence_loads) do
    graph[name] = graph[name] or {in_links = {}, out_links = {}}
    for _, pre in ipairs(precedents) do
      graph[pre] = graph[pre] or {in_links = {}, out_links = {}}
      graph[name].in_links[pre] = true
      table.insert(graph[pre].out_links, name)
    end
  end

  local frontier = {}
  for name, links in pairs(graph) do
    if next(links.in_links) == nil then table.insert(frontier, name) end
  end

  while next(frontier) ~= nil do
    local plugin = table.remove(frontier)
    if loaders[plugin].only_sequence and not loaders[plugin].only_setup then
      table.insert(sequence_lines, 'vim.cmd [[ packadd ' .. plugin .. ' ]]')
      if plugins[plugin].config then
        local lines = {'', '-- Config for: ' .. plugin}
        vim.list_extend(lines, plugins[plugin].config)
        table.insert(lines, '')
        vim.list_extend(sequence_lines, lines)
      end
    end

    for _, name in ipairs(graph[plugin].out_links) do
      if not loaders[plugin].only_sequence then
        loaders[name].only_sequence = false
        loaders[name].load_after[plugin] = true
      end

      graph[name].in_links[plugin] = nil
      if next(graph[name].in_links) == nil then table.insert(frontier, name) end
    end

    graph[plugin] = nil
  end

  if next(graph) then
    log.warning('Cycle detected in sequenced loads! Load order may be incorrect')
    -- TODO: This should actually just output the cycle, then continue with toposort. But I'm too
    -- lazy to do that right now, so.
    for plugin, _ in pairs(graph) do
      table.insert(sequence_lines, 'vim.cmd [[ packadd ' .. plugin .. ' ]]')
      if plugins[plugin].config then
        local lines = {'-- Config for: ' .. plugin}
        vim.list_extend(lines, plugins[plugin].config)
        vim.list_extend(sequence_lines, lines)
      end
    end
  end

  -- Output everything:

  -- First, the Lua code
  local result = {'" Automatically generated packer.nvim plugin loader code\n'}
  table.insert(result, feature_guard)
  table.insert(result, 'lua << END')
  table.insert(result, fmt('local plugins = %s\n', vim.inspect(loaders)))
  table.insert(result, lua_loader)
  -- Then the runtimepath line
  table.insert(result, '-- Runtimepath customization')
  table.insert(result, rtp_line)
  table.insert(result, '-- Pre-load configuration')
  vim.list_extend(result, setup_lines)
  table.insert(result, '-- Post-load configuration')
  vim.list_extend(result, config_lines)
  table.insert(result, '-- Conditional loads')
  vim.list_extend(result, conditionals)

  -- The sequenced loads
  table.insert(result, '-- Load plugins in order defined by `after`')
  vim.list_extend(result, sequence_lines)

  table.insert(result, 'END\n')

  -- Then the Vim loader function
  table.insert(result, vim_loader)

  -- The command and keymap definitions
  table.insert(result, '\n" Command lazy-loads')
  vim.list_extend(result, command_defs)
  table.insert(result, '')
  table.insert(result, '" Keymap lazy-loads')
  vim.list_extend(result, keymap_defs)
  table.insert(result, '')

  -- The filetype and event autocommands
  table.insert(result, 'augroup packer_load_aucmds\n  au!')
  table.insert(result, '  " Filetype lazy-loads')
  vim.list_extend(result, ft_aucmds)
  table.insert(result, '  " Event lazy-loads')
  vim.list_extend(result, event_aucmds)
  table.insert(result, 'augroup END\n')

  -- And a final package path update
  return table.concat(result, '\n')
end

local compile = setmetatable({cfg = cfg}, {__call = make_loaders})

compile.opt_keys = {'after', 'cmd', 'ft', 'keys', 'event', 'cond', 'setup'}

return compile
