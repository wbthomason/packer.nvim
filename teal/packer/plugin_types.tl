local Display = require 'packer.display'.Display
local Plugin = require'packer.plugin'.Plugin

local record PluginHandler
  installer   : function(Plugin, Display): {string}
  updater     : function(Plugin, Display, opts: table): {string}
  revert_last : function(Plugin): {string}
  diff        : function(Plugin, commit: string, callback: function): {string}
  get_rev     : function(Plugin): string, string
end

local plugin_types: {string:PluginHandler} = {}

return setmetatable(plugin_types, {
  __index = function(_: {string:PluginHandler}, k: string): PluginHandler
    if k == 'git' then
      return require('packer.plugin_types.git')
    elseif k == 'local' then
      return require('packer.plugin_types.local')
    end
  end,
})
