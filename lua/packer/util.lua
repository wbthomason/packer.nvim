local util = {}

util.map = function(func, seq)
  local result = {}
  for _, v in ipairs(seq) do table.insert(result, func(v)) end

  return result
end

util.partition = function(sub, seq)
  local sub_vals = {}
  for _, val in ipairs(sub) do sub_vals[val] = true end

  local result = {{}, {}}
  for _, val in ipairs(seq) do
    if sub_vals[val] then
      table.insert(result[1], val)
    else
      table.insert(result[2], val)
    end
  end

  return unpack(result)
end

util.nonempty_or = function(opt, alt)
  if #opt > 0 then
    return opt
  else
    return alt
  end
end

util.is_windows = jit.os == 'Windows'
local function get_separator()
  if util.is_windows then return '\\' end

  return '/'
end

util.join_paths = function(...)
  local separator = get_separator()
  return table.concat({...}, separator)
end

util.get_plugin_full_name = function(plugin)
  local plugin_name = plugin.name
  if plugin.branch and plugin.branch ~= 'master' then
    plugin_name = plugin_name .. '/' .. plugin.branch
  end

  if plugin.rev then plugin_name = plugin_name .. '@' .. plugin.rev end

  return plugin_name
end

util.memoize = function(func)
  return setmetatable({}, {
    __index = function(self, k)
      local v = func(k);
      self[k] = v;
      return v
    end,
    __call = function(self, k) return self[k] end
  })
end

util.deep_extend = function(policy, ...)
  local result = {}
  local function helper(policy, k, v1, v2)
    if type(v1) ~= 'table' or type(v2) ~= 'table' then
      if policy == 'error' then
        error('Key ' .. vim.inspect(k) .. ' is already present with value ' .. vim.inspect(v1))
      elseif policy == 'force' then
        return v2
      else
        return v1
      end
    else
      return util.deep_extend(policy, v1, v2)
    end
  end

  for _, t in ipairs({...}) do
    for k, v in pairs(t) do
      if result[k] ~= nil then
        result[k] = helper(policy, k, result[k], v)
      else
        result[k] = v
      end
    end
  end

  return result
end

return util
