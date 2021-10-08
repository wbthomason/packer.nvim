local yield = coroutine.yield

local type PredicateFn = function(any): boolean
local type IteratorFn  = function(): any

local record M
  partition: function(PredicateFn, {any}): IteratorFn, IteratorFn
  collect: function(IteratorFn)
  nonempty_or: function({any}, {any}): {any}

  is_windows: boolean
  separator: string
end

--- partition: split a list-like table into the subset satisfying a given predicate and the subset not satisfying the given predicate
--- @param predicate: A function defining the property to split the set by
--- @param sequence: A list-like table to split
--- @return An included-subset iterator and an excluded-subset iterator
local function partition(predicate: PredicateFn, sequence: {any}): IteratorFn, IteratorFn
  local included_iterator = function(): any 
    for _, elem in ipairs(sequence) do
      if predicate(elem) then 
        yield(elem)
      end
    end
  end

  local excluded_iterator = function(): any
    for _, elem in ipairs(sequence) do
      if not predicate(elem) then
        yield(elem)
      end
    end
  end

  return included_iterator, excluded_iterator
end

--- collect: build a list-like table containing all elements yielded by a given iterator
--- @param iterator: The iterator to collect elements from
--- @return The list of elements yielded by the iterator
local function collect(iterator: IteratorFn): {any}
  local result: {any} = {}
  for item in iterator do
    result[#result + 1] = item
  end

  return result
end

--- nonempty_or: return a sequence if it is non-empty, or an alternative otherwise
local function nonempty_or(sequence: {any}, alternative: {any}): {any}
  if next(sequence) ~= nil then
    return sequence
  end

  return alternative
end

local is_windows: boolean
if jit ~= nil then
  is_windows = jit.os == 'Windows'
else
  is_windows = package.config:sub(1, 1) == '\\'
end

local separator: string
if is_windows then
  separator = '\\'
else
  separator = '/'
end

--- join_paths: combine a list of path components with the OS-appropriate separator string
--- @param ...: a list of path components
--- @return The concatenated, separated path
end

return M
