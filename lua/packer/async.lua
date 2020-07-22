-- Adapted from https://ms-jpq.github.io/neovim-async-tutorial/
local co = coroutine

local function step(func, callback)
  local thread = co.create(func)
  local tick = nil
  tick = function(...)
    local ok, val = co.resume(thread, ...)
    if ok then
      if type(val) == 'function' then
        val(tick)
      else
        (callback or function() end)(val)
      end
    end
  end

  tick()
end

local function wrap(func)
  return function(...)
    local params = {...}
    return function(tick)
      table.insert(params, tick)
      return func(unpack(params))
    end
  end
end

local function join(...)
  local thunks = {...}
  local thunk_all = function(s)
    if #thunks == 0 then return s() end
    local to_go = #thunks
    local results = {}
    for i, thunk in ipairs(thunks) do
      local callback = function(...)
        results[i] = {...}
        if to_go == 1 then
          s(unpack(results))
        else
          to_go = to_go - 1
        end
      end

      thunk(callback)
    end
  end

  return thunk_all
end

local function wait_all(...) return co.yield(join(...)) end

local function pool(n, interrupt_check, ...)
  local thunks = {...}
  return function(s)
    if #thunks == 0 then return s() end
    local remaining = select(n, thunks)
    local results = {}
    local to_go = #thunks
    local make_callback = nil
    make_callback = function(idx, left)
      local i = (left == nil) and idx or (idx + left)
      return function(...)
        results[i] = {...}
        to_go = to_go - 1
        if to_go == 0 then
          s(unpack(results))
        elseif not interrupt_check or not interrupt_check() then
          if remaining and #remaining > 0 then
            local next_task = table.remove(remaining)
            next_task(make_callback(n, #remaining + 1))
          end
        end
      end
    end

    for i = 1, math.min(n, #thunks) do
      local thunk = thunks[i]
      thunk(make_callback(i))
    end
  end
end

local function wait_pool(limit, ...) return co.yield(pool(limit, false, ...)) end

local function interruptible_wait_pool(limit, interrupt_check, ...)
  return co.yield(pool(limit, interrupt_check, ...))
end

local function main(f) vim.schedule(f) end

local M = {
  sync = wrap(step),
  wait = co.yield,
  wait_all = wait_all,
  wait_pool = wait_pool,
  interruptible_wait_pool = interruptible_wait_pool,
  wrap = wrap,
  main = main
}

return M
