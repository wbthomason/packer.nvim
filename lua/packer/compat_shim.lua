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
