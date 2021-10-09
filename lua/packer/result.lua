-- A simple Result<V, E> type to simplify control flow with installers and updaters
local result = {}

local ok_result_mt = {
  and_then = function(self, f, ...)
    local r = f(...)
    if r == nil then
      return result.err('Nil result in and_then! ' .. vim.inspect(debug.traceback()))
    end

    self.ok = r.ok
    self.err = r.err
    setmetatable(self, getmetatable(r))
    return self
  end,
  or_else = function(self)
    return self
  end,
  map_ok = function(self, f)
    self.ok = f(self.ok) or self.ok
    return self
  end,
  map_err = function(self)
    return self
  end,
}

ok_result_mt.__index = ok_result_mt

local err_result_mt = {
  and_then = function(self)
    return self
  end,
  or_else = function(self, f, ...)
    local r = f(...)
    if r == nil then
      return result.err('Nil result in or_else! ' .. vim.inspect(debug.traceback()))
    end

    self.ok = r.ok
    self.err = r.err
    setmetatable(self, getmetatable(r))
    return self
  end,
  map_ok = function(self)
    return self
  end,
  map_err = function(self, f)
    self.err = f(self.err) or self.err
    return self
  end,
}

err_result_mt.__index = err_result_mt

result.ok = function(val)
  if val == nil then
    val = true
  end
  local r = setmetatable({}, ok_result_mt)
  r.ok = val
  return r
end

result.err = function(err)
  if err == nil then
    err = true
  end
  local r = setmetatable({}, err_result_mt)
  r.err = err
  return r
end

return result
