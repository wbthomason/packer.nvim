-- Compiling plugin specifications to Vimscript/Lua for lazy-loading
local util = require('packer/util')
local compile = {}

compile.opt_keys = { 'defer', 'after', 'cmd', 'ft', 'keys', 'event', 'cond' }

-- Allowed keys:
-- after, cmds, fts, bind, event, cond, defer, config
compile.to_vim = function(plugins)
  -- Filetype loaders
  local fts = {}
  for name, plugin in pairs(util.filter(function(plugin) return plugin.fts ~= nil end, plugins)) do
    for _, ft in ipairs(plugin.fts) do
      if fts[ft] == nil then
        fts[ft] = {}
      end

      table.insert(fts[ft], name)
    end
  end

  local ft_aucmds = {}
  for ft, names in pairs(fts) do
    local loads = vim.fn.join(util.map(function(name) return 'packadd ' .. name end, names), ' | ')
    table.insert(ft_aucmds, 'au FileType ' .. ft .. ' ' .. loads)
  end

  -- Event loaders
  local events = {}
  for name, plugin in pairs(util.filter(function(plugin) return plugin.event ~= nil end, plugins)) do
    for _, event in ipairs(plugin.event) do
      if events[event] == nil then
        events[event] = {}
      end

      table.insert(events[event], name)
    end
  end

  local event_aucmds = {}
  for event, names in pairs(events) do
    local loads = vim.fn.join(util.map(function(name) return 'packadd ' .. name end, names), ' | ')
    table.insert(event_aucmds, 'au ' .. event .. ' * ' .. loads)
  end

  -- Conditional loaders
  -- Keybind loaders
  -- Command loaders
  -- Deferred loaders
  -- Sequence loaders

  -- Output everything
  local result = 'augroup packer_load_aucmds\nau!\n' .. vim.fn.join(ft_aucmds, '\n') .. vim.fn.join(event_aucmds, '\n')

  result = result .. '\naugroup END'
  return result
end

return compile
