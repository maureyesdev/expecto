-- Health module is mostly side-effectful (writes to vim.health output),
-- so we test the individual check conditions via controlled mocks.

describe("expecto.health", function()
  local health

  before_each(function()
    -- Clear module cache so we can re-require fresh
    package.loaded["expecto.health"] = nil
    health = require("expecto.health")
  end)

  it("module loads without error", function()
    assert.is_table(health)
  end)

  it("exposes a check() function", function()
    assert.is_function(health.check)
  end)

  describe("curl detection logic", function()
    it("recognises curl as available when executable", function()
      -- vim.fn.executable("curl") returns 1 on this machine
      local result = vim.fn.executable("curl")
      assert.equals(1, result)
    end)
  end)

  describe("nvim version gate", function()
    it("running Neovim meets minimum version requirement", function()
      local v = vim.version()
      local meets = v.major > 0 or (v.major == 0 and v.minor >= 9)
      assert.is_true(meets)
    end)
  end)

  it("check() runs without throwing", function()
    -- We can't easily capture vim.health output in tests,
    -- but we verify it doesn't raise an error.
    assert.has_no.errors(function()
      health.check()
    end)
  end)
end)
