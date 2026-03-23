local config = require("expecto.config")

describe("expecto.config", function()
  -- Reset config before each test by re-calling setup with no opts
  before_each(function()
    config.setup({})
  end)

  describe("defaults", function()
    it("has vertical response split", function()
      assert.equals("vertical", config.defaults().response_split)
    end)

    it("follows redirects by default", function()
      assert.is_true(config.defaults().follow_redirects)
    end)

    it("has 30 second timeout", function()
      assert.equals(30, config.defaults().timeout)
    end)

    it("uses .expecto.json as env file", function()
      assert.equals(".expecto.json", config.defaults().env_file)
    end)

    it("has 50 history entries limit", function()
      assert.equals(50, config.defaults().history_size)
    end)

    it("shows codelens by default", function()
      assert.is_true(config.defaults().show_codelens)
    end)

    it("has response window size of 60", function()
      assert.equals(60, config.defaults().response_window_size)
    end)

    it("formats response body by default", function()
      assert.is_true(config.defaults().format_response_body)
    end)

    it("has empty default headers", function()
      assert.same({}, config.defaults().default_headers)
    end)

    it("has empty certificates table", function()
      assert.same({}, config.defaults().certificates)
    end)

    it("has a default cookie_jar path inside stdpath cache", function()
      local jar = config.defaults().cookie_jar
      assert.is_string(jar)
      assert.truthy(jar:find("expecto"))
    end)

    it("allows cookie_jar to be disabled by setting false", function()
      config.setup({ cookie_jar = false })
      assert.is_false(config.get().cookie_jar)
    end)
  end)

  describe("setup()", function()
    it("merges user opts over defaults", function()
      config.setup({ response_split = "horizontal", timeout = 60 })
      local cfg = config.get()
      assert.equals("horizontal", cfg.response_split)
      assert.equals(60, cfg.timeout)
    end)

    it("keeps defaults for unspecified keys", function()
      config.setup({ timeout = 10 })
      local cfg = config.get()
      assert.equals(50, cfg.history_size)
      assert.is_true(cfg.follow_redirects)
    end)

    it("deep-merges nested tables", function()
      config.setup({ default_headers = { ["X-Custom"] = "value" } })
      local cfg = config.get()
      assert.equals("value", cfg.default_headers["X-Custom"])
    end)

    it("accepts nil opts gracefully", function()
      config.setup(nil)
      local cfg = config.get()
      assert.equals("vertical", cfg.response_split)
    end)

    it("accepts empty table opts", function()
      config.setup({})
      local cfg = config.get()
      assert.equals(30, cfg.timeout)
    end)
  end)

  describe("get()", function()
    it("returns the current config", function()
      config.setup({ history_size = 100 })
      assert.equals(100, config.get().history_size)
    end)

    it("reflects the last setup() call", function()
      config.setup({ timeout = 5 })
      assert.equals(5, config.get().timeout)
      config.setup({ timeout = 15 })
      assert.equals(15, config.get().timeout)
    end)
  end)

  describe("defaults() immutability", function()
    it("does not mutate defaults when config is changed", function()
      config.setup({ timeout = 999 })
      assert.equals(30, config.defaults().timeout)
    end)
  end)
end)
