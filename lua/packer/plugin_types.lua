local Display = require('packer.display').Display









local plugin_types = {}

return setmetatable(plugin_types, {
   __index = function(_, k)
      if k == 'git' then
         return require('packer.plugin_types.git')
      elseif k == 'local' then
         return require('packer.plugin_types.local')
      end
   end,
})
