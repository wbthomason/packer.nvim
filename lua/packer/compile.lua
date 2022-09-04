-- Compiling plugin specifications to Lua for lazy-loading
local util = require 'packer.util'
local log = require 'packer.log'
local fmt = string.format
local luarocks = require 'packer.luarocks'

local config
local function cfg(_config)
  config = _config.profile
end

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

local feature_guard_lua = [[
if vim.api.nvim_call_function('has', {'nvim-0.5'}) ~= 1 then
  vim.api.nvim_command('echohl WarningMsg | echom "Invalid Neovim version for packer.nvim! | echohl None"')
  return
end

vim.api.nvim_command('packadd packer.nvim')

local no_errors, error_msg = pcall(function()
]]

local enter_packer_compile = [[
_G._packer = _G._packer or {}
_G._packer.inside_compile = true
]]

local exit_packer_compile = [[

_G._packer.inside_compile = false
if _G._packer.needs_bufread == true then
  vim.cmd("doautocmd BufRead")
end
_G._packer.needs_bufread = false
]]

local catch_errors = [[
catch
  echohl ErrorMsg
  echom "Error in packer_compiled: " .. v:exception
  echom "Please check your config for correctness"
  echohl None
endtry
]]

local catch_errors_lua = [[
end)

if not no_errors then
  error_msg = error_msg:gsub('"', '\\"')
  vim.api.nvim_command('echohl ErrorMsg | echom "Error in packer_compiled: '..error_msg..'" | echom "Please check your config for correctness" | echohl None')
end
]]

---@param should_profile boolean
---@return string
local profile_time = function(should_profile)
  return fmt(
    [[
local time
local profile_info
local should_profile = %s
if should_profile then
  local hrtime = vim.loop.hrtime
  profile_info = {}
  time = function(chunk, start)
    if start then
      profile_info[chunk] = hrtime()
    else
      profile_info[chunk] = (hrtime() - profile_info[chunk]) / 1e6
    end
  end
else
  time = function(chunk, start) end
end
]],
    vim.inspect(should_profile)
  )
end

local profile_output = [[
local function save_profiles(threshold)
  local sorted_times = {}
  for chunk_name, time_taken in pairs(profile_info) do
    sorted_times[#sorted_times + 1] = {chunk_name, time_taken}
  end
  table.sort(sorted_times, function(a, b) return a[2] > b[2] end)
  local results = {}
  for i, elem in ipairs(sorted_times) do
    if not threshold or threshold and elem[2] > threshold then
      results[i] = elem[1] .. ' took ' .. elem[2] .. 'ms'
    end
  end
  if threshold then
    table.insert(results, '(Only showing plugins that took longer than ' .. threshold .. ' ms ' .. 'to load)')
  end

  _G._packer.profile_output = results
end
]]

---@param threshold number
---@return string
local conditionally_output_profile = function(threshold)
  if threshold then
    return fmt(
      [[
if should_profile then save_profiles(%d) end
]],
      threshold
    )
  else
    return [[
if should_profile then save_profiles() end
]]
  end
end

local try_loadstring = [[
local function try_loadstring(s, component, name)
  local success, result = pcall(loadstring(s), name, _G.packer_plugins[name])
  if not success then
    vim.schedule(function()
      vim.api.nvim_notify('packer.nvim: Error running ' .. component .. ' for ' .. name .. ': ' .. result, vim.log.levels.ERROR, {})
    end)
  end
  return result
end
]]

local module_loader = [[
local lazy_load_called = {['packer.load'] = true}
local function lazy_load_module(module_name)
  local to_load = {}
  if lazy_load_called[module_name] then return nil end
  lazy_load_called[module_name] = true
  for module_pat, plugin_name in pairs(module_lazy_loads) do
    if not _G.packer_plugins[plugin_name].loaded and string.match(module_name, module_pat) then
      to_load[#to_load + 1] = plugin_name
    end
  end

  if #to_load > 0 then
    require('packer.load')(to_load, {module = module_name}, _G.packer_plugins)
    local loaded_mod = package.loaded[module_name]
    if loaded_mod then
      return function(modname) return loaded_mod end
    end
  end
end

if not vim.g.packer_custom_loader_enabled then
  table.insert(package.loaders, 1, lazy_load_module)
  vim.g.packer_custom_loader_enabled = true
end
]]

local function timed_chunk(chunk, name, output_table)
  output_table = output_table or {}
  output_table[#output_table + 1] = 'time([[' .. name .. ']], true)'
  if type(chunk) == 'string' then
    output_table[#output_table + 1] = chunk
  else
    vim.list_extend(output_table, chunk)
  end

  output_table[#output_table + 1] = 'time([[' .. name .. ']], false)'
  return output_table
end

local function dump_loaders(loaders)
  local result = vim.deepcopy(loaders)
  for k, _ in pairs(result) do
    if result[k].only_setup or result[k].only_sequence then
      result[k].loaded = true
    end
    result[k].only_setup = nil
    result[k].only_sequence = nil
  end

  return vim.inspect(result)
end

local function make_try_loadstring(item, chunk, name)
  local bytecode = string.dump(item, true)
  local executable_string = 'try_loadstring(' .. vim.inspect(bytecode) .. ', "' .. chunk .. '", "' .. name .. '")'
  return executable_string, bytecode
end

local after_plugin_pattern = table.concat({ 'after', 'plugin', [[**/*.\(vim\|lua\)]] }, util.get_separator())
local function detect_after_plugin(name, plugin_path)
  local path = plugin_path .. util.get_separator() .. after_plugin_pattern
  local glob_ok, files = pcall(vim.fn.glob, path, false, true)
  if not glob_ok then
    if string.find(files, 'E77') then
      return { path }
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
  table.concat({ 'ftdetect', [[**/*.\(vim\|lua\)]] }, util.get_separator()),
  table.concat({ 'after', 'ftdetect', [[**/*.\(vim\|lua\)]] }, util.get_separator()),
}
local function detect_ftdetect(name, plugin_path)
  local paths = {
    plugin_path .. util.get_separator() .. ftdetect_patterns[1],
    plugin_path .. util.get_separator() .. ftdetect_patterns[2],
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

local source_dirs = { 'ftdetect', 'ftplugin', 'after/ftdetect', 'after/ftplugin' }
local function detect_bufread(plugin_path)
  local path = plugin_path
  for i = 1, 4 do
    if #vim.fn.finddir(source_dirs[i], path) > 0 then
      return true
    end
  end
  return false
end

local function make_loaders(_, plugins, output_lua, should_profile)
  local loaders = {}
  local configs = {}
  local rtps = {}
  local setup = {}
  local fts = {}
  local events = {}
  local condition_ids = {}
  local commands = {}
  local keymaps = {}
  local after = {}
  local fns = {}
  local ftdetect_paths = {}
  local module_lazy_loads = {}
  for name, plugin in pairs(plugins) do
    if not plugin.disable then
      plugin.simple_load = true
      local quote_name = "'" .. name .. "'"
      if plugin.config and not plugin.executable_config then
        plugin.simple_load = false
        plugin.executable_config = {}
        if type(plugin.config) ~= 'table' then
          plugin.config = { plugin.config }
        end
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

      local path = plugin.install_path
      if plugin.rtp then
        path = util.join_paths(plugin.install_path, plugin.rtp)
        table.insert(rtps, path)
      end

      loaders[name] = {
        loaded = not plugin.opt,
        config = plugin.config,
        path = path,
        only_sequence = plugin.manual_opt == nil,
        only_setup = false,
      }

      if plugin.opt then
        plugin.simple_load = false
        loaders[name].after_files = detect_after_plugin(name, loaders[name].path)
        if plugin.bufread ~= nil then
          loaders[name].needs_bufread = plugin.bufread
        else
          loaders[name].needs_bufread = detect_bufread(loaders[name].path)
        end
      end

      if plugin.setup then
        plugin.simple_load = false
        if type(plugin.setup) ~= 'table' then
          plugin.setup = { plugin.setup }
        end
        for i, setup_item in ipairs(plugin.setup) do
          if type(setup_item) == 'function' then
            plugin.setup[i], _ = make_try_loadstring(setup_item, 'setup', name)
          end
        end

        loaders[name].only_setup = plugin.manual_opt == nil
        setup[name] = plugin.setup
      end

      -- Keep this as first opt loader to maintain only_cond ?
      if plugin.cond ~= nil then
        plugin.simple_load = false
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        loaders[name].only_cond = true
        if type(plugin.cond) ~= 'table' then
          plugin.cond = { plugin.cond }
        end

        for _, condition in ipairs(plugin.cond) do
          loaders[name].cond = {}
          if type(condition) == 'function' then
            _, condition = make_try_loadstring(condition, 'condition', name)
          elseif type(condition) == 'string' then
            condition = 'return ' .. condition
          end

          condition_ids[condition] = condition_ids[condition] or {}
          table.insert(loaders[name].cond, condition)
          table.insert(condition_ids[condition], name)
        end
      end

      -- Add the git URL for displaying in PackerStatus and PackerSync. https://github.com/wbthomason/packer.nvim/issues/542
      loaders[name].url = plugin.url

      if plugin.ft then
        plugin.simple_load = false
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        loaders[name].only_cond = false
        vim.list_extend(ftdetect_paths, detect_ftdetect(name, loaders[name].path))
        if type(plugin.ft) == 'string' then
          plugin.ft = { plugin.ft }
        end
        for _, ft in ipairs(plugin.ft) do
          fts[ft] = fts[ft] or {}
          table.insert(fts[ft], quote_name)
        end
      end

      if plugin.event then
        plugin.simple_load = false
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        loaders[name].only_cond = false
        if type(plugin.event) == 'string' then
          if not plugin.event:find '%s' then
            plugin.event = { plugin.event .. ' *' }
          else
            plugin.event = { plugin.event }
          end
        end

        for _, event in ipairs(plugin.event) do
          if event:sub(#event, -1) ~= '*' and not event:find '%s' then
            event = event .. ' *'
          end
          events[event] = events[event] or {}
          table.insert(events[event], quote_name)
        end
      end

      if plugin.cmd then
        plugin.simple_load = false
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        loaders[name].only_cond = false
        if type(plugin.cmd) == 'string' then
          plugin.cmd = { plugin.cmd }
        end

        loaders[name].commands = {}
        for _, command in ipairs(plugin.cmd) do
          commands[command] = commands[command] or {}
          table.insert(loaders[name].commands, command)
          table.insert(commands[command], quote_name)
        end
      end

      if plugin.keys then
        plugin.simple_load = false
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        loaders[name].only_cond = false
        if type(plugin.keys) == 'string' then
          plugin.keys = { plugin.keys }
        end
        loaders[name].keys = {}
        for _, keymap in ipairs(plugin.keys) do
          if type(keymap) == 'string' then
            keymap = { '', keymap }
          end
          keymaps[keymap] = keymaps[keymap] or {}
          table.insert(loaders[name].keys, keymap)
          table.insert(keymaps[keymap], quote_name)
        end
      end

      if plugin.after then
        plugin.simple_load = false
        loaders[name].only_setup = false

        if type(plugin.after) == 'string' then
          plugin.after = { plugin.after }
        end

        for _, other_plugin in ipairs(plugin.after) do
          after[other_plugin] = after[other_plugin] or {}
          table.insert(after[other_plugin], name)
        end
      end

      if plugin.wants then
        plugin.simple_load = false
        if type(plugin.wants) == 'string' then
          plugin.wants = { plugin.wants }
        end
        loaders[name].wants = plugin.wants
      end

      if plugin.fn then
        plugin.simple_load = false
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        if type(plugin.fn) == 'string' then
          plugin.fn = { plugin.fn }
        end
        for _, fn in ipairs(plugin.fn) do
          fns[fn] = fns[fn] or {}
          table.insert(fns[fn], quote_name)
        end
      end

      if plugin.module or plugin.module_pattern then
        plugin.simple_load = false
        loaders[name].only_sequence = false
        loaders[name].only_setup = false
        loaders[name].only_cond = false

        if plugin.module then
          if type(plugin.module) == 'string' then
            plugin.module = { plugin.module }
          end

          for _, module_name in ipairs(plugin.module) do
            module_lazy_loads['^' .. vim.pesc(module_name)] = name
          end
        else
          if type(plugin.module_pattern) == 'string' then
            plugin.module_pattern = { plugin.module_pattern }
          end

          for _, module_pattern in ipairs(plugin.module_pattern) do
            module_lazy_loads[module_pattern] = name
          end
        end
      end

      if plugin.config and (not plugin.opt or loaders[name].only_setup) then
        plugin.simple_load = false
        plugin.only_config = true
        configs[name] = plugin.executable_config
      end
    end
  end

  local ft_aucmds = {}
  for ft, names in pairs(fts) do
    table.insert(
      ft_aucmds,
      fmt(
        'vim.cmd [[au FileType %s ++once lua require("packer.load")({%s}, { ft = "%s" }, _G.packer_plugins)]]',
        ft,
        table.concat(names, ', '),
        ft
      )
    )
  end

  local event_aucmds = {}
  for event, names in pairs(events) do
    table.insert(
      event_aucmds,
      fmt(
        'vim.cmd [[au %s ++once lua require("packer.load")({%s}, { event = "%s" }, _G.packer_plugins)]]',
        event,
        table.concat(names, ', '),
        event:gsub([[\]], [[\\]])
      )
    )
  end

  local config_lines = {}
  for name, plugin_config in pairs(configs) do
    local lines = { '-- Config for: ' .. name }
    timed_chunk(plugin_config, 'Config for ' .. name, lines)
    vim.list_extend(config_lines, lines)
  end

  local rtp_line = ''
  for _, rtp in ipairs(rtps) do
    rtp_line = rtp_line .. ' .. ",' .. vim.fn.escape(rtp, '\\,') .. '"'
  end

  if rtp_line ~= '' then
    rtp_line = 'vim.o.runtimepath = vim.o.runtimepath' .. rtp_line
  end

  local setup_lines = {}
  for name, plugin_setup in pairs(setup) do
    local lines = { '-- Setup for: ' .. name }
    timed_chunk(plugin_setup, 'Setup for ' .. name, lines)
    if loaders[name].only_setup then
      timed_chunk('vim.cmd [[packadd ' .. name .. ']]', 'packadd for ' .. name, lines)
    end

    vim.list_extend(setup_lines, lines)
  end

  local conditionals = {}
  for _, names in pairs(condition_ids) do
    for _, name in ipairs(names) do
      if loaders[name].only_cond then
        timed_chunk(
          fmt('  require("packer.load")({"%s"}, {}, _G.packer_plugins)', name),
          'Conditional loading of ' .. name,
          conditionals
        )
      end
    end
  end

  local command_defs = {}
  for command, names in pairs(commands) do
    local command_line
    if string.match(command, '^%w+$') then
      command_line = fmt(
        'pcall(vim.cmd, [[command -nargs=* -range -bang -complete=file %s lua require("packer.load")({%s}, { cmd = "%s", l1 = <line1>, l2 = <line2>, bang = <q-bang>, args = <q-args>, mods = "<mods>" }, _G.packer_plugins)]])',
        command,
        table.concat(names, ', '),
        command
      )
    else
      command_line = fmt(
        'pcall(vim.cmd, [[au CmdUndefined %s ++once lua require"packer.load"({%s}, {}, _G.packer_plugins)]])',
        command,
        table.concat(names, ', ')
      )
    end
    command_defs[#command_defs + 1] = command_line
  end

  local keymap_defs = {}
  for keymap, names in pairs(keymaps) do
    local prefix = nil
    if keymap[1] ~= 'i' then
      prefix = ''
    end
    local escaped_map_lt = string.gsub(keymap[2], '<', '<lt>')
    local escaped_map = string.gsub(escaped_map_lt, '([\\"])', '\\%1')
    local keymap_line = fmt(
      'vim.cmd [[%snoremap <silent> %s <cmd>lua require("packer.load")({%s}, { keys = "%s"%s }, _G.packer_plugins)<cr>]]',
      keymap[1],
      keymap[2],
      table.concat(names, ', '),
      escaped_map,
      prefix == nil and '' or (', prefix = "' .. prefix .. '"')
    )

    table.insert(keymap_defs, keymap_line)
  end

  local sequence_loads = {}
  for pre, posts in pairs(after) do
    if plugins[pre] == nil then
      error(string.format('Dependency %s for %s not found', pre, vim.inspect(posts)))
    end

    if plugins[pre].opt then
      loaders[pre].after = posts
    elseif plugins[pre].only_config then
      loaders[pre].after = posts
      loaders[pre].only_sequence = true
      loaders[pre].only_config = true
    end

    if plugins[pre].simple_load or plugins[pre].opt or plugins[pre].only_config then
      for _, name in ipairs(posts) do
        loaders[name].load_after = {}
        sequence_loads[name] = sequence_loads[name] or {}
        table.insert(sequence_loads[name], pre)
      end
    end
  end

  local fn_aucmds = {}
  for fn, names in pairs(fns) do
    table.insert(
      fn_aucmds,
      fmt(
        'vim.cmd[[au FuncUndefined %s ++once lua require("packer.load")({%s}, {}, _G.packer_plugins)]]',
        fn,
        table.concat(names, ', ')
      )
    )
  end

  local sequence_lines = {}
  local graph = {}
  for name, precedents in pairs(sequence_loads) do
    graph[name] = graph[name] or { in_links = {}, out_links = {} }
    for _, pre in ipairs(precedents) do
      graph[pre] = graph[pre] or { in_links = {}, out_links = {} }
      graph[name].in_links[pre] = true
      table.insert(graph[pre].out_links, name)
    end
  end

  local frontier = {}
  for name, links in pairs(graph) do
    if next(links.in_links) == nil then
      table.insert(frontier, name)
    end
  end

  while next(frontier) ~= nil do
    local plugin = table.remove(frontier)
    if loaders[plugin].only_sequence and not (loaders[plugin].only_setup or loaders[plugin].only_config) then
      table.insert(sequence_lines, 'vim.cmd [[ packadd ' .. plugin .. ' ]]')
      if plugins[plugin].config then
        local lines = { '', '-- Config for: ' .. plugin }
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
      if next(graph[name].in_links) == nil then
        table.insert(frontier, name)
      end
    end

    graph[plugin] = nil
  end

  if next(graph) then
    log.warn 'Cycle detected in sequenced loads! Load order may be incorrect'
    -- TODO: This should actually just output the cycle, then continue with toposort. But I'm too
    -- lazy to do that right now, so.
    for plugin, _ in pairs(graph) do
      table.insert(sequence_lines, 'vim.cmd [[ packadd ' .. plugin .. ' ]]')
      if plugins[plugin].config then
        local lines = { '-- Config for: ' .. plugin }
        vim.list_extend(lines, plugins[plugin].config)
        vim.list_extend(sequence_lines, lines)
      end
    end
  end

  -- Output everything:

  -- First, the Lua code
  local result = { (output_lua and '--' or '"') .. ' Automatically generated packer.nvim plugin loader code\n' }
  if output_lua then
    table.insert(result, feature_guard_lua)
  else
    table.insert(result, feature_guard)
    table.insert(result, 'lua << END')
  end
  table.insert(result, enter_packer_compile)
  table.insert(result, profile_time(should_profile))
  table.insert(result, profile_output)
  timed_chunk(luarocks.generate_path_setup(), 'Luarocks path setup', result)
  timed_chunk(try_loadstring, 'try_loadstring definition', result)
  timed_chunk(fmt('_G.packer_plugins = %s\n', dump_loaders(loaders)), 'Defining packer_plugins', result)
  -- Then the runtimepath line
  if rtp_line ~= '' then
    table.insert(result, '-- Runtimepath customization')
    timed_chunk(rtp_line, 'Runtimepath customization', result)
  end

  -- Then the module lazy loads
  if next(module_lazy_loads) then
    table.insert(result, 'local module_lazy_loads = ' .. vim.inspect(module_lazy_loads))
    table.insert(result, module_loader)
  end

  -- Then setups, configs, and conditionals
  if next(setup_lines) then
    vim.list_extend(result, setup_lines)
  end
  if next(config_lines) then
    vim.list_extend(result, config_lines)
  end
  if next(conditionals) then
    table.insert(result, '-- Conditional loads')
    vim.list_extend(result, conditionals)
  end

  -- The sequenced loads
  if next(sequence_lines) then
    table.insert(result, '-- Load plugins in order defined by `after`')
    timed_chunk(sequence_lines, 'Sequenced loading', result)
  end

  -- The command and keymap definitions
  if next(command_defs) then
    table.insert(result, '\n-- Command lazy-loads')
    timed_chunk(command_defs, 'Defining lazy-load commands', result)
    table.insert(result, '')
  end

  if next(keymap_defs) then
    table.insert(result, '-- Keymap lazy-loads')
    timed_chunk(keymap_defs, 'Defining lazy-load keymaps', result)
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
    timed_chunk(ft_aucmds, 'Defining lazy-load filetype autocommands', result)
  end

  if some_event then
    table.insert(result, '  -- Event lazy-loads')
    timed_chunk(event_aucmds, 'Defining lazy-load event autocommands', result)
  end

  if some_fn then
    table.insert(result, '  -- Function lazy-loads')
    timed_chunk(fn_aucmds, 'Defining lazy-load function autocommands', result)
  end

  if some_ft or some_event or some_fn then
    table.insert(result, 'vim.cmd("augroup END")')
  end
  if next(ftdetect_paths) then
    table.insert(result, 'vim.cmd [[augroup filetypedetect]]')
    for _, path in ipairs(ftdetect_paths) do
      local escaped_path = vim.fn.escape(path, ' ')
      timed_chunk('vim.cmd [[source ' .. escaped_path .. ']]', 'Sourcing ftdetect script at: ' .. escaped_path, result)
    end

    table.insert(result, 'vim.cmd("augroup END")')
  end

  table.insert(result, exit_packer_compile)

  table.insert(result, conditionally_output_profile(config.threshold))
  if output_lua then
    table.insert(result, catch_errors_lua)
  else
    table.insert(result, 'END\n')
    table.insert(result, catch_errors)
  end
  return table.concat(result, '\n')
end

local compile = setmetatable({ cfg = cfg }, { __call = make_loaders })

compile.opt_keys = { 'after', 'cmd', 'ft', 'keys', 'event', 'cond', 'setup', 'fn', 'module', 'module_pattern' }

return compile
