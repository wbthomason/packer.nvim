local Screen = require('test.functional.ui.screen')
local helpers = require('test.functional.helpers')()

local clear    = helpers.clear
local exec     = helpers.exec
local exec_lua = helpers.exec_lua
local system   = helpers.funcs.system
local eq       = helpers.eq

local scratch = os.getenv('PJ_ROOT')..'/scratch'

local function setup_packer(spec, config)
  spec = spec or {}
  config = config or {}
  config.package_root = scratch
  exec_lua([[
      local spec, config = ...
      require('packer').startup{spec, config = config}
    ]], spec, config)
end

local TIMEOUT = 4000

--- @param cond fun()
--- @param interval? number
local function expectf(cond, interval)
  local duration = 0
  interval = interval or 1
  while duration < TIMEOUT do
    local ok, err = pcall(cond)
    if ok then
      return
    end
    -- print(err)
    duration = duration + interval
    helpers.sleep(interval)
    interval = interval * 1.5
  end
  cond()
end

--- @param i integer
--- @return string
local function get_line(i)
  return helpers.bufmeths.get_lines(0, i - 1, i, false)[1]
end

-- local function get_lines()
--   return helpers.bufmeths.get_lines(0, 0, -1, false)
-- end

describe('packer.nvim', function()
  local screen

  before_each(function()
    clear()

    screen = Screen.new(20, 17)
    screen:attach({ext_messages=true})

    system{"rm", "-rf", scratch}
    system{"mkdir", "-p", scratch}
    exec_lua('package.path = ...', package.path)
    exec[[
      set rtp+=$PJ_ROOT
      packadd packer.nvim
    ]]
  end)

  after_each(function()
    system{"rm", "-rf", scratch}
  end)

  it('can process a simple plugin', function()
    setup_packer { 'tpope/vim-surround' }
  end)

  it('can install a simple plugin', function()
    setup_packer { 'tpope/vim-surround' }
    exec 'PackerInstall'

    expectf(function()
      eq(' ⟳ vim-surround: cloning...', get_line(3))
    end)

    expectf(function()
      eq(' ✓ Installed vim-surround', get_line(3))
    end)
  end)
end)
