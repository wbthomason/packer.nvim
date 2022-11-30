





return function(plugins, loader)
   for _, plugin in pairs(plugins) do
      local enable = plugin.enable
      if type(enable) == "function" then
         if enable() then
            loader({ plugin })
         end
      end

   end
end
