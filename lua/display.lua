local display = {}

local display_mt = {}

display.open = function(opener)
  local disp = setmetatable({}, display_mt)

  return disp
end

return display
