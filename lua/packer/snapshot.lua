local a = require 'packer.async'
local async = a.sync
local await = a.wait
local fmt = string.format
local log = require 'packer.log'
local plugin_utils = require 'packer.plugin_utils'
local util = require 'packer.util'

local function cfg(_config)
  config = _config
end

---Serializes a table of git-plugins with `short_name` as table key and another
---table with `commit`; the serialized tables will be written in the path `filename`
---provided, if there is already a snapshot it will be overwritten
---Snapshotting work only with `plugin_utils.git_plugin_type` type of plugins,
---other will be ignored.
---@param filename string
---@param plugins Plugin[]
---@return function
local function do_snapshot(_, filename, plugins)
  assert(type(filename) == "string",
    fmt("filename needs to be a string but '%s' provided", type(filename)))
  assert(type(plugins) == "table",
    fmt("plugins needs to be an array but '%s' provided", type(plugins)))

  return async(function()
    local snapshot_plugins = {}
    local opt, start = plugin_utils.list_installed_plugins()
    local installed = {}

    for key, _ in pairs(opt) do installed[key] = key end
    for key, _ in pairs(start) do installed[key] = key end

    for _, plugin in pairs(plugins) do
      if installed[plugin.install_path] ~= nil then -- this plugin is installed
        log.debug(fmt("Snapshotting '%s'", plugin.short_name))
        if plugin.type == plugin_utils.git_plugin_type then
          local rev = await(plugin.get_rev())

          if rev == "" or rev == nil then
            local msg = fmt('Snapshotting %s failed', plugin.short_name)
            log.warn(msg)
            error(msg)
          else
            snapshot_plugins[plugin.short_name] = {commit = rev}
          end
        end
      end
    end
    local snapshot = "return " .. vim.inspect(snapshot_plugins)
--    local result = await(a.main(function ()
--      return vim.fn.writefile({snapshot}, filename) == 0
--    end))
-- Doesn't work using vim.fn.writefile

--    vim.schedule_wrap(function ()
--      if vim.fn.writefile(snapshot, filename) ~= 0 then
--        log.warn("Couldn't save snapshot")
--      else
--        log.info("Snapshot saved succesfully")
--      end
--    end)
local file, err = io.open(filename, 'w+')
    if err then
      log.warn(err)
      error(err)
    else
      file:write(snapshot)
    end

    if file ~= nil then
      file:close()
    end
  end)
end

local snapshot = setmetatable(
  { cfg = cfg }, { __call = do_snapshot }
)

return snapshot
