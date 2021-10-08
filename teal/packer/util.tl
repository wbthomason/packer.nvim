local type PredicateFn = function<T>(T): boolean
local type IteratorFn  = function<T>(): T

local record M
  is_windows: boolean
  separator: string
end

--- partition: split a list-like table into the subset satisfying a given predicate and the subset not satisfying the given predicate
--- @param predicate: A function defining the property to split the set by
--- @param sequence: A list-like table to split
--- @return An included-subset iterator and an excluded-subset iterator
function M.partition<T>(predicate: PredicateFn<T>, sequence: {T}): IteratorFn<T>, IteratorFn<T>
  local sequence_len = #sequence

  local included_idx = 0
  local included_iterator = function(): T
    while included_idx < sequence_len do
      included_idx = included_idx + 1
      if predicate(sequence[included_idx]) then
        return sequence[included_idx]
      end
    end

    return nil
  end

  local excluded_idx = 0
  local excluded_iterator = function(): T
    while excluded_idx < sequence_len do
      excluded_idx = included_idx + 1
      if not predicate(sequence[excluded_idx]) then
        return sequence[excluded_idx]
      end
    end

    return nil
  end

  return included_iterator, excluded_iterator
end

--- collect: build a list-like table containing all elements yielded by a given iterator
--- @param iterator: The iterator to collect elements from
--- @return The list of elements yielded by the iterator
function M.collect<T>(iterator: IteratorFn<T>): {T}
  local result: {T} = {}
  for item in iterator do
    result[#result + 1] = item
  end

  return result
end

--- nonempty_or: return a sequence if it is non-empty, or an alternative otherwise
function M.nonempty_or<T>(sequence: {T}, alternative: {T}): {T}
  if next(sequence) ~= nil then
    return sequence
  end

  return alternative
end

if jit ~= nil then
  M.is_windows = jit.os == 'Windows'
else
  M.is_windows = package.config:sub(1, 1) == '\\'
end

if M.is_windows then
  M.separator = '\\'
else
  M.separator = '/'
end

--- join_paths: combine a list of path components with the OS-appropriate separator string
--- @param ...: a list of path components
--- @return The concatenated, separated path
function M.join_paths(...: string): string
  return table.concat({...}, M.separator)
end

return M
