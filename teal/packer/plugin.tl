local record Plugin
  enum Type
    'git'
    'local'
    'custom'
  end

  type: Type

  setup: function()
  short_name: string
  full_name: string
end

local function get_full_name(plugin: Plugin): string
  local full_name = plugin.short_name
  if plugin.type == 'git' then
    if plugin.git.branch then
      full_name = full_name .. '/' .. plugin.git.branch 
    end

    if plugin.git.rev then
      full_name = full_name .. '@' .. plugin.git.rev
    end
  end

  return full_name
end

return Plugin
