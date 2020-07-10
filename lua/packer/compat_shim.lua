-- We have to patch in some functions from Neovim 0.5.0+ on earlier versions. Much of this code is
-- copied from the Neovim runtime
vim.fn = vim.fn or setmetatable({}, {
  __index = function(t, key)
    local function _fn(...) return vim.api.nvim_call_function(key, {...}) end
    t[key] = _fn
    return _fn
  end
})

vim.o = vim.o or setmetatable({}, {
  __index = function(_, key) return vim.api.nvim_get_option(key) end,
  __newindex = function(_, k, v) return vim.api.nvim_set_option(k, v) end
})

vim.v = vim.v or setmetatable({}, {
  __index = function(_, key)
    local status, val = pcall(vim.api.nvim_get_vvar(key))
    if status then return val end
  end,
  __newindex = function(_, k, v) return vim.api.nvim_set_vvar(k, v) end
})

vim.list_extend = vim.list_extend or function(dst, src, start, finish)
  for i = start or 1, finish or #src do table.insert(dst, src[i]) end
  return dst
end

vim.trim = vim.trim or function(s) return s:match('^%s*(.*%S)') or '' end

vim.gsplit = vim.gsplit or function(s, sep, plain)
  local start = 1
  local done = false

  local function _pass(i, j, ...)
    if i then
      assert(j + 1 > start, "Infinite loop detected")
      local seg = s:sub(start, i - 1)
      start = j + 1
      return seg, ...
    else
      done = true
      return s:sub(start)
    end
  end

  return function()
    if done or (s == '' and sep == '') then return end
    if sep == '' then
      if start == #s then done = true end
      return _pass(start + 1, start)
    end
    return _pass(s:find(sep, start, plain))
  end
end

vim.split = vim.split or function(s, sep, plain)
  local t = {}
  for c in vim.gsplit(s, sep, plain) do table.insert(t, c) end
  return t
end

vim.tbl_extend = vim.tbl_extend or function(behavior, ...)
  local ret = {}
  for i = 1, select('#', ...) do
    local tbl = select(i, ...)
    if tbl then
      for k, v in pairs(tbl) do
        if behavior ~= 'force' and ret[k] ~= nil then
          if behavior == 'error' then error('key found in more than one map: ' .. k) end
        else
          ret[k] = v
        end
      end
    end
  end
  return ret
end

vim.tbl_keys = vim.tbl_keys or function(t)
  local keys = {}
  for k, _ in pairs(t) do table.insert(keys, k) end
  return keys
end

vim.tbl_contains = vim.tbl_contains or function(t, value)
  for _, v in ipairs(t) do if v == value then return true end end
  return false
end

vim.tbl_values = vim.tbl_values or function(t)
  local values = {}
  for _, v in pairs(t) do table.insert(values, v) end
  return values
end
