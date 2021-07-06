-- Adapted from https://ms-jpq.github.io/neovim-async-tutorial/
local log = require 'packer.log'
local yield = coroutine.yield
local resume = coroutine.resume
local thread_create = coroutine.create

local function EMPTY_CALLBACK() end
local function step(func, callback)
  local thread = thread_create(func)
  local tick = nil
  tick = function(...)
    local ok, val = resume(thread, ...)
    if ok then
      if type(val) == 'function' then
        val(tick)
      else
        (callback or EMPTY_CALLBACK)(val)
      end
    else
      log.error('Error in coroutine: ' .. val);
      (callback or EMPTY_CALLBACK)(nil)
    end
  end

  tick()
end

local function wrap(func)
  return function(...)
    local params = { ... }
    return function(tick)
      params[#params + 1] = tick
      return func(unpack(params))
    end
  end
end

local function join(...)
  local thunks = { ... }
  local thunk_all = function(s)
    if #thunks == 0 then
      return s()
    end
    local to_go = #thunks
    local results = {}
    for i, thunk in ipairs(thunks) do
      local callback = function(...)
        results[i] = { ... }
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

local function wait_all(...)
  return yield(join(...))
end

local function pool(n, interrupt_check, ...)
  local thunks = { ... }
  return function(s)
    if #thunks == 0 then
      return s()
    end
    local remaining = { select(n + 1, unpack(thunks)) }
    local results = {}
    local to_go = #thunks
    local make_callback = nil
    make_callback = function(idx, left)
      local i = (left == nil) and idx or (idx + left)
      return function(...)
        results[i] = { ... }
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

local function wait_pool(limit, ...)
  return yield(pool(limit, false, ...))
end

local function interruptible_wait_pool(limit, interrupt_check, ...)
  return yield(pool(limit, interrupt_check, ...))
end

local function main(f)
  vim.schedule(f)
end

local M = {
  --- Wrapper for functions that do not take a callback to make async functions
  sync = wrap(step),
  --- Alias for yielding to await the result of an async function
  wait = yield,
  --- Await the completion of a full set of async functions
  wait_all = wait_all,
  --- Await the completion of a full set of async functions, with a limit on how many functions can
  --  run simultaneously
  wait_pool = wait_pool,
  --- Like wait_pool, but additionally checks at every function completion to see if a condition is
  --  met indicating that it should keep running the remaining tasks
  interruptible_wait_pool = interruptible_wait_pool,
  --- Wrapper for functions that do take a callback to make async functions
  wrap = wrap,
  --- Convenience function to ensure a function runs on the main "thread" (i.e. for functions which
  --  use Neovim functions, etc.)
  main = main,
}

return M
