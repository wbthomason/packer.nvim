-- A simple Result<V, E> type to simplify control flow with installers and updaters
local result = {}

local ok_result_mt = {
  and_then = function(self, f, ...)
    local r = f(...)
    if r.ok then
      self.ok = r.ok
      return self
    elseif r.err then
      return r
    end
  end,
  or_else = function(self) return self end,
  map_ok = function(self, f)
    self.ok = f(self.ok) or self.ok
    return self
  end,
  map_err = function(self) return self end
}

ok_result_mt.__index = ok_result_mt

local err_result_mt = {
  and_then = function(self) return self end,
  or_else = function(self, f, ...)
    local r = f(...)
    if r.ok then
      return r
    elseif r.err then
      self.err = r.err
      return self
    end
  end,
  map_ok = function(self) return self end,
  map_err = function(self, f)
    self.err = f(self.err) or self.err
    return self
  end
}

err_result_mt.__index = err_result_mt

result.ok = function(val)
  local r = setmetatable({}, ok_result_mt)
  r.ok = val
  return r
end

result.err = function(err)
  local r = setmetatable({}, err_result_mt)
  r.err = err
  return r
end

result.wrap = function(fst, snd)
  if fst then return result.ok(fst) end
  return result.err(snd)
end

return result
