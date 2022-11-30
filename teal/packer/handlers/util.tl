local M = {}

-- 'strong' table to keep track of destructors
local destructors: {function()} = {}

function M.register_destructor(plugins: {Plugin}, f: function())
  local id = #destructors+1

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
