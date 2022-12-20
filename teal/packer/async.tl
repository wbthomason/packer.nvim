local record Async
  type Thunk = function(function(...:any))

  -- Order by highest number of return types

  void: function             (function()           ): function()
  void: function<A1>         (function(A1)         ): function(A1)
  void: function<A1,A2>      (function(A1,A2)      ): function(A1,A2)
  void: function<A1,A2,A3,A4>(function(A1,A2,A3,A4)): function(A1,A2,A3,A4)

  wrap: function<A1,A2,R1,R2>      (function(A1,A2,      function(R1,R2)), integer): function(A1,A2         ): R1,R2
  wrap: function<A1,A2,R1>         (function(A1,A2,      function(R1)   ), integer): function(A1,A2         ): R1
  wrap: function<A1,A2,A3,R1,R2>   (function(A1,A2,A3,   function(R1,R2)), integer): function(A1,A2,A3      ): R1,R2
  wrap: function<A1,A2,A3,A4,R1>   (function(A1,A2,A3,A4,function(R1)   ), integer): function(A1,A2,A3,A4   ): R1
  wrap: function<A1,A2,A3,R1>      (function(A1,A2,A3,   function(R1)   ), integer): function(A1,A2,A3      ): R1
  wrap: function<A1,A2,A3,A4,A5,R1>(function(A1,A2,A3,A4,A5,function(R1)), integer): function(A1,A2,A3,A4,A5): R1
  wrap: function<A1,A2,A3>         (function(A1,A2,A3,   function())     , integer): function(A1,A2,A3      )

  sync: function<T>(T, integer): T

  main: function()
  join: function(integer, (function(): boolean), {Thunk}): {any}
  curry: function(fn: function, ...: any): Async.Thunk
end

local co = coroutine

---Executes a future with a callback when it is done
local function execute(func: function, callback: function, ...: any)
  local thread = co.create(func)

  local function step(...: any)
    local ret = {co.resume(thread, ...)}
    local stat, nargs, fn_or_ret = unpack(ret) as (boolean, integer, function)

    if not stat then
      error(string.format("The coroutine failed with this message: %s\n%s",
        nargs, debug.traceback(thread)))
    end

    if co.status(thread) == 'dead' then
      if callback then
        callback(unpack(ret, 2))
      end
      return
    end

    local args = {select(4, unpack(ret))}
    args[nargs] = step
    fn_or_ret(unpack(args, 1, nargs))
  end

  step(...)
end

local record M
  main: function
end

---Creates an async function with a callback style function.
---
---@generic F : function
function M.wrap(func: function, argc: integer): function
  return function(...): any...
    if not co.running() or select('#', ...) == argc then
      return func(...)
    end
    return co.yield(argc, func, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
function M.sync(func: function, nargs: integer): function
  nargs = nargs or 0
  return function(...): any...
    if co.running() then
      return func(...)
    end
    local callback = select(nargs+1, ...)
    execute(func, callback, unpack({...}, 1, nargs))
  end
end

---For functions that don't provide a callback as there last argument
function M.void(func: function): function
  return function(...): any...
    if co.running() then
      return func(...)
    end
    execute(func, nil, ...)
  end
end

function M.join(n: integer, interrupt_check: (function(): boolean), thunks: {Async.Thunk}): any
  return co.yield(1, function(finish: function(...:any): any...): any
    if #thunks == 0 then
      return finish()
    end

    local remaining = { select(n + 1, unpack(thunks)) }
    local to_go = #thunks

    local ret = {}

    local function cb(...)
      ret[#ret+1] = {...}
      to_go = to_go - 1
      if to_go == 0 then
        finish(ret)
      elseif not interrupt_check or not interrupt_check() then
        if #remaining > 0 then
          local next_task = table.remove(remaining)
          next_task(cb)
        end
      end
    end

    for i = 1, math.min(n, #thunks) do
      thunks[i](cb)
    end
  end, 1)
end

---Useful for partially applying arguments to an async function
function M.curry(fn: function, ...: any): Async.Thunk
  local args = {...}
  local nargs = select('#', ...)
  return function(...)
    local other = {...}
    for i = 1, select('#', ...) do
      args[nargs+i] = other[i]
    end
    fn(unpack(args))
  end as Async.Thunk
end

---An async function that when called will yield to the Neovim scheduler to be
---able to call the API.
M.main = M.wrap(vim.schedule, 1)

return M as Async
