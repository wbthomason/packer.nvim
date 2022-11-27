





return function(cond_plugins, loader)
   for _, plugin in pairs(cond_plugins) do
      local cond = plugin.cond
      if type(cond) == "function" then
         if cond() then
            loader({ plugin })
         end
      elseif cond then
         loader({ plugin })
      end
   end
end