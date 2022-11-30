local M = {}


local destructors = {}

function M.register_destructor(plugins, f)
   local id = #destructors + 1

   destructors[id] = function()
      if destructors[id] then
         f()
         destructors[id] = nil
      end
   end

   for _, p in ipairs(plugins) do
      table.insert(p.destructors, destructors[id])
   end
end

return M