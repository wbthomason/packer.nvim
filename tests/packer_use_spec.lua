local packer = require("packer")
local use = packer.use
local packer_path = vim.fn.stdpath("data").."/site/pack/packer/start/"

describe("Packer use tests", function()
  after_each(function()
    packer.reset()
  end)

  it("should set the correct install path", function ()
    local spec = {"test/plugin1"}
    packer.startup(function()
      use(spec)
    end)
    packer.__manage_all()
    assert.truthy(spec.install_path)
    assert.equal(spec.install_path, packer_path .. spec.short_name)
  end)

  it("should add metadata to a plugin from a spec", function ()
    local spec = {"test/plugin1"}
    packer.startup(function()
      use(spec)
    end)
    packer.__manage_all()
    assert.equal(spec.name, "test/plugin1")
    assert.equal(spec.path, "test/plugin1")
  end)
end)
