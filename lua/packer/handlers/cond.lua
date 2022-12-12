








local Plugin = require('packer.plugin').Plugin



return function(plugins, loader)
   for _, plugin in pairs(plugins) do
      local cond = plugin.cond

      local function load_plugin()
         loader({ plugin })
      end

      if type(cond) == "table" then
         for _, c in ipairs(cond) do
            if c(load_plugin) then
               load_plugin()
            end
         end
      elseif type(cond) == "function" then
         if cond(load_plugin) then
            load_plugin()
         end
      end

   end
end