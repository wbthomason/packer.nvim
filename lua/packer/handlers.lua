local config = nil

local function cfg(_config)
  config = _config
end

local handlers = {
  cfg = cfg,
}

return handlers
