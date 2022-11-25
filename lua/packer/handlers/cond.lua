





return function(cond_plugins, loader)
   for _, plugin in pairs(cond_plugins) do
      if type(plugin.cond) == 'function' and plugin.cond() then
         loader({ plugin })
      end
   end
end