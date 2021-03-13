-- Compiling plugin specifications to Lua for lazy-loading
local util = require('packer.util')
local log = require('packer.log')
local fmt = string.format
local luarocks = require('packer.luarocks')

local config
local function cfg(_config) config = _config end

local feature_guard = [[
if !has('nvim-0.5')
  echohl WarningMsg
  echom "Invalid Neovim version for packer.nvim!"
  echohl None
  finish
endif

packadd packer.nvim

try
]]

local catch_errors = [[
catch
  echohl ErrorMsg
  echom "Error in packer_compiled: " .. v:exception
  echom "Please check your config for correctness"
  echohl None
endtry
]]

local try_loadstring = [[
local function try_loadstring(s, component, name)
  local success, result = pcall(loadstring(s))
  if not success then
    print('Error running ' .. component .. ' for ' .. name)
    error(result)
  end
  return result
end
]]

local module_loader = [[
local function lazy_load_module(module_name)
  if module_name == 'packer.load' then return nil end
  local to_load = {}
  local i = 1
  for module_pat, plugin_name in pairs(module_lazy_loads) do
    if not _G.packer_plugins[plugin_name].loaded and string.match(module_name, "^" .. module_pat) then
      to_load[i] = plugin_name
    end
  end

  require('packer.load')(to_load, {module = module_name}, _G.packer_plugins)
end

if not vim.g.packer_custom_loader_enabled then
  table.insert(package.loaders, 2, lazy_load_module)
  vim.g.packer_custom_loader_enabled = true
end
]]

local function dump_loaders(loaders)
  local result = vim.deepcopy(loaders)
  for k, _ in pairs(result) do
    result[k].only_setup = nil
    result[k].only_sequence = nil
  end

  return vim.inspect(result)
end

local function make_try_loadstring(item, chunk, name)
  local bytecode = string.dump(item, true)
  local executable_string = 'try_loadstring(' .. vim.inspect(bytecode) .. ', "' .. chunk .. '", "'
                              .. name .. '")'
  return executable_string, bytecode
end

local after_plugin_pattern = table.concat({'after', 'plugin', '**', '*.vim'}, util.get_separator())
local function detect_after_plugin(name, plugin_path)
  local path = plugin_path .. util.get_separator() .. after_plugin_pattern
  local glob_ok, files = pcall(vim.fn.glob, path, false, true)
  if not glob_ok then
    if string.find(files, 'E77') then
      return {path}
    else
      log.error('Error compiling ' .. name .. ': ' .. vim.inspect(files))
      error(files)
    end
  elseif #files > 0 then
    return files
  end

  return nil
end

local ftdetect_patterns = {
  table.concat({'ftdetect', '**', '*.vim'}, util.get_separator()),
  table.concat({'after', 'ftdetect', '**', '*.vim'}, util.get_separator())
}
local function detect_ftdetect(name, plugin_path)
  local paths = {
    plugin_path .. util.get_separator() .. ftdetect_patterns[1],
    plugin_path .. util.get_separator() .. ftdetect_patterns[2]
  }
  local source_paths = {}
  for i = 1, 2 do
    local path = paths[i]
    local glob_ok, files = pcall(vim.fn.glob, path, false, true)
    if not glob_ok then
      if string.find(files, 'E77') then
        source_paths[#source_paths + 1] = path
      else
        log.error('Error compiling ' .. name .. ': ' .. vim.inspect(files))
        error(files)
      end
    elseif #files > 0 then
      vim.list_extend(source_paths, files)
    end
  end

  return source_paths
end

local source_dirs = {'ftdetect', 'ftplugin', 'after/ftdetect', 'after/ftplugin'}
local function detect_bufread(plugin_path)
  local path = plugin_path
  for i = 1, 4 do if #vim.fn.finddir(source_dirs[i], path) > 0 then return true end end
  return false
end

local function make_loaders(_, plugins)
  local loaders = {}
  local configs = {}
  local rtps = {}
  local setup = {}
  local fts = {}
  local events = {}
  local condition_ids = {}
  local condition_bytecode = {}
  local commands = {}
  local keymaps = {}
  local after = {}
  local fns = {}
  local ftdetect_paths = {}
  local module_lazy_loads = {}
  for name, plugin in pairs(plugins) do
    if not plugin.disable then
      local quote_name = "'" .. name .. "'"
      if plugin.config and not plugin.executable_config then
        plugin.executable_config = {}
        if type(plugin.config) ~= 'table' then plugin.config = {plugin.config} end
        for i, config_item in ipairs(plugin.config) do
          local executable_string = config_item
          if type(config_item) == 'function' then
            local bytecode
            executable_string, bytecode = make_try_loadstring(config_item, 'config', name)
            plugin.config[i] = bytecode
          end

          table.insert(plugin.executable_config, executable_string)
        end
      end

      if plugin.rtp then table.insert(rtps, util.join_paths(plugin.install_path, plugin.rtp)) end

      loaders[name] = {
        loaded = not plugin.opt,
        config = plugin.config,
        path = plugin.install_path .. (plugin.rtp and plugin.rtp or ''),
        only_sequence = plugin.manual_opt == nil,
        only_setup = false
      }

      if plugin.opt then
        loaders[name].after_files = detect_after_plugin(name, loaders[name].path)
        loaders[name].needs_bufread = detect_bufread(loaders[name].path)
      end

      if plugin.setup then
        if type(plugin.setup) ~= 'table' then plugin.setup = {plugin.setup} end
        for i, setup_item in ipairs(plugin.setup) do
          if type(setup_item) == 'function' then
            plugin.setup[i], _ = make_try_loadstring(setup_item, 'setup', name)
          end
        end

        loaders[name].only_setup = plugin.manual_opt == nil
        setup[name] = plugin.setup
      end

      if plugin.ft then
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        vim.list_extend(ftdetect_paths, detect_ftdetect(name, loaders[name].path))
        if type(plugin.ft) == 'string' then plugin.ft = {plugin.ft} end
        for _, ft in ipairs(plugin.ft) do
          fts[ft] = fts[ft] or {}
          table.insert(fts[ft], quote_name)
        end
      end

      if plugin.event then
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        if type(plugin.event) == 'string' then
          if not plugin.event:find('%s') then
            plugin.event = {plugin.event .. ' *'}
          else
            plugin.event = {plugin.event}
          end
        end

        for _, event in ipairs(plugin.event) do
          if event:sub(#event, -1) ~= '*' and not event:find('%s') then
            event = event .. ' *'
          end
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
            condition = vim.inspect(string.dump(condition, true))
            condition_bytecode[condition] = true
          end

          condition_ids[condition] = condition_ids[condition] or {}
          table.insert(condition_ids[condition], name)
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

      if plugin.fn then
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        if type(plugin.fn) == 'string' then plugin.fn = {plugin.fn} end
        for _, fn in ipairs(plugin.fn) do
          fns[fn] = fns[fn] or {}
          table.insert(fns[fn], quote_name)
        end
      end

      if plugin.module then
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        if type(plugin.module) == 'string' then plugin.module = {plugin.module} end
        for _, module_name in ipairs(plugin.module) do module_lazy_loads[module_name] = name end
      end

      if plugin.config and (not plugin.opt or loaders[name].only_setup) then
        plugin.only_config = true
        configs[name] = plugin.executable_config
      end
    end
  end

  local ft_aucmds = {}
  for ft, names in pairs(fts) do
    table.insert(ft_aucmds, fmt(
                   'vim.cmd [[au FileType %s ++once lua require("packer.load")({%s}, { ft = "%s" }, _G.packer_plugins)]]',
                   ft, table.concat(names, ', '), ft))
  end

  local event_aucmds = {}
  for event, names in pairs(events) do
    table.insert(event_aucmds, fmt(
                   'vim.cmd [[au %s ++once lua require("packer.load")({%s}, { event = "%s" }, _G.packer_plugins)]]',
                   event, table.concat(names, ', '), event))
  end

  local config_lines = {}
  for name, plugin_config in pairs(configs) do
    local lines = {'-- Config for: ' .. name}
    vim.list_extend(lines, plugin_config)
    vim.list_extend(config_lines, lines)
  end

  local rtp_line = ''
  for _, rtp in ipairs(rtps) do rtp_line = rtp_line .. ' .. ",' .. vim.fn.escape(rtp, '\\,') .. '"' end

  if rtp_line ~= '' then rtp_line = 'vim.o.runtimepath = vim.o.runtimepath' .. rtp_line end

  local setup_lines = {}
  for name, plugin_setup in pairs(setup) do
    local lines = {'-- Setup for: ' .. name}
    vim.list_extend(lines, plugin_setup)
    if loaders[name].only_setup then table.insert(lines, 'vim.cmd [[packadd ' .. name .. ']]') end
    vim.list_extend(setup_lines, lines)
  end

  local conditionals = {}
  for condition, names in pairs(condition_ids) do
    local conditional_loads = {}
    for _, name in ipairs(names) do
      table.insert(conditional_loads, '\tvim.cmd [[packadd ' .. name .. ']]')
      if plugins[name].config then
        local lines = {'-- Config for: ' .. name}
        vim.list_extend(lines, plugins[name].executable_config)
        vim.list_extend(conditional_loads, lines)
      end
    end
    local executable_conditional = condition
    if condition_bytecode[condition] then
      executable_conditional = 'try_loadstring(' .. condition .. ', "condition", \''
                                 .. vim.inspect(names) .. '\')'
    end

    local conditional = 'if ' .. executable_conditional .. [[ then
]] .. table.concat(conditional_loads, '\n\t') .. '\nend\n'

    table.insert(conditionals, conditional)
  end

  local command_defs = {}
  for command, names in pairs(commands) do
    local command_line = fmt(
                           'vim.cmd [[command! -nargs=* -range -bang -complete=file %s lua require("packer.load")({%s}, { cmd = "%s", l1 = <line1>, l2 = <line2>, bang = <q-bang>, args = <q-args> }, _G.packer_plugins)]]',
                           command, table.concat(names, ', '), command)
    table.insert(command_defs, command_line)
  end

  local keymap_defs = {}
  for keymap, names in pairs(keymaps) do
    local prefix = nil
    if keymap[1] ~= 'i' then prefix = '' end
    local escaped_map_lt = string.gsub(keymap[2], '<', '<lt>')
    local escaped_map = string.gsub(escaped_map_lt, '([\\"])', '\\%1')
    local keymap_line = fmt(
                          'vim.cmd [[%snoremap <silent> %s <cmd>lua require("packer.load")({%s}, { keys = "%s"%s }, _G.packer_plugins)<cr>]]',
                          keymap[1], keymap[2], table.concat(names, ', '), escaped_map,
                          prefix == nil and '' or (', prefix = "' .. prefix .. '"'))

    table.insert(keymap_defs, keymap_line)
  end

  local sequence_loads = {}
  for pre, posts in pairs(after) do
    if plugins[pre].opt then
      loaders[pre].after = posts
    elseif plugins[pre].only_config then
      loaders[pre] = {after = posts, only_sequence = true, only_config = true}
    end

    if plugins[pre].opt or plugins[pre].only_config then
      for _, name in ipairs(posts) do
        loaders[name].load_after = {}
        sequence_loads[name] = sequence_loads[name] or {}
        table.insert(sequence_loads[name], pre)
      end
    end
  end

  local fn_aucmds = {}
  for fn, names in pairs(fns) do
    table.insert(fn_aucmds, fmt(
                   'vim.cmd[[au FuncUndefined %s ++once lua require("packer.load")({%s}, {}, _G.packer_plugins)]]',
                   fn, table.concat(names, ', ')))
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
    if loaders[plugin].only_sequence
      and not (loaders[plugin].only_setup or loaders[plugin].only_config) then
      table.insert(sequence_lines, 'vim.cmd [[ packadd ' .. plugin .. ' ]]')
      if plugins[plugin].config then
        local lines = {'', '-- Config for: ' .. plugin}
        vim.list_extend(lines, plugins[plugin].executable_config)
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
    log.warn('Cycle detected in sequenced loads! Load order may be incorrect')
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
  table.insert(result, luarocks.generate_path_setup())
  table.insert(result, try_loadstring)
  table.insert(result, fmt('_G.packer_plugins = %s\n', dump_loaders(loaders)))
  -- Then the runtimepath line
  if rtp_line ~= '' then
    table.insert(result, '-- Runtimepath customization')
    table.insert(result, rtp_line)
  end

  -- Then the module lazy loads
  if next(module_lazy_loads) then
    table.insert(result, 'local module_lazy_loads = ' .. vim.inspect(module_lazy_loads))
    table.insert(result, module_loader)
  end

  -- Then setups, configs, and conditionals
  if next(setup_lines) then vim.list_extend(result, setup_lines) end
  if next(config_lines) then vim.list_extend(result, config_lines) end
  if next(conditionals) then
    table.insert(result, '-- Conditional loads')
    vim.list_extend(result, conditionals)
  end

  -- The sequenced loads
  if next(sequence_lines) then
    table.insert(result, '-- Load plugins in order defined by `after`')
    vim.list_extend(result, sequence_lines)
  end

  -- The command and keymap definitions
  if next(command_defs) then
    table.insert(result, '\n-- Command lazy-loads')
    vim.list_extend(result, command_defs)
    table.insert(result, '')
  end

  if next(keymap_defs) then
    table.insert(result, '-- Keymap lazy-loads')
    vim.list_extend(result, keymap_defs)
    table.insert(result, '')
  end

  -- The filetype, event and function autocommands
  local some_ft = next(ft_aucmds) ~= nil
  local some_event = next(event_aucmds) ~= nil
  local some_fn = next(fn_aucmds) ~= nil
  if some_ft or some_event or some_fn then
    table.insert(result, 'vim.cmd [[augroup packer_load_aucmds]]\nvim.cmd [[au!]]')
  end

  if some_ft then
    table.insert(result, '  -- Filetype lazy-loads')
    vim.list_extend(result, ft_aucmds)
  end

  if some_event then
    table.insert(result, '  -- Event lazy-loads')
    vim.list_extend(result, event_aucmds)
  end

  if some_fn then
    table.insert(result, '  -- Function lazy-loads')
    vim.list_extend(result, fn_aucmds)
  end

  if some_ft or some_event or some_fn then table.insert(result, 'vim.cmd("augroup END")') end
  if next(ftdetect_paths) then
    table.insert(result, 'vim.cmd [[augroup filetypedetect]]')
    for _, path in ipairs(ftdetect_paths) do
      local escaped_path = vim.fn.escape(path, ' ')
      table.insert(result, 'vim.cmd [[source ' .. escaped_path .. ']]')
    end

    table.insert(result, 'vim.cmd("augroup END")')
  end
  table.insert(result, 'END\n')
  table.insert(result, catch_errors)
  return table.concat(result, '\n')
end

local compile = setmetatable({cfg = cfg}, {__call = make_loaders})

compile.opt_keys = {'after', 'cmd', 'ft', 'keys', 'event', 'cond', 'setup', 'fn', 'module'}

return compile
