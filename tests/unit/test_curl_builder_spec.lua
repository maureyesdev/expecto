local builder = require("expecto.curl_builder")
local config  = require("expecto.config")

-- before_each must live inside a describe block in plenary/busted.
-- Each describe that mutates config resets it in its own before_each.

--- Build a minimal request table for testing.
local function req(overrides)
  return vim.tbl_deep_extend("force", {
    method   = "GET",
    url      = "https://example.com/api",
    headers  = {},
    body     = nil,
    body_file = nil,
    body_file_vars = false,
    meta     = { no_redirect = false, no_cookie_jar = false },
    file_vars = {},
  }, overrides or {})
end

-- ── Basic structure ───────────────────────────────────────────────────────────

describe("expecto.curl_builder — basic structure", function()
  it("starts with curl", function()
    local args = builder.build(req())
    assert.equals("curl", args[1])
  end)

  it("includes --silent and --show-error", function()
    local args = builder.build(req())
    assert.truthy(vim.tbl_contains(args, "--silent"))
    assert.truthy(vim.tbl_contains(args, "--show-error"))
  end)

  it("includes --include for response headers", function()
    local args = builder.build(req())
    assert.truthy(vim.tbl_contains(args, "--include"))
  end)

  it("includes -w with timing write-out", function()
    local args = builder.build(req())
    local w_idx = nil
    for i, v in ipairs(args) do
      if v == "-w" then w_idx = i break end
    end
    assert.is_not_nil(w_idx)
    assert.is_not_nil(args[w_idx + 1])
    assert.truthy(args[w_idx + 1]:find(builder.TIMING_MARKER, 1, true))
  end)

  it("includes --max-time with config timeout", function()
    local args = builder.build(req())
    local mt_idx = nil
    for i, v in ipairs(args) do
      if v == "--max-time" then mt_idx = i break end
    end
    assert.is_not_nil(mt_idx)
    assert.equals("30", args[mt_idx + 1])
  end)

  it("URL is the last argument", function()
    local r = req({ url = "https://example.com/test" })
    local args = builder.build(r)
    assert.equals("https://example.com/test", args[#args])
  end)
end)

-- ── HTTP method ───────────────────────────────────────────────────────────────

describe("expecto.curl_builder — HTTP method", function()
  it("omits -X for GET (curl default)", function()
    local args = builder.build(req({ method = "GET" }))
    assert.is_false(vim.tbl_contains(args, "-X"))
  end)

  it("adds -X POST for POST", function()
    local args = builder.build(req({ method = "POST" }))
    local x_idx = nil
    for i, v in ipairs(args) do
      if v == "-X" then x_idx = i break end
    end
    assert.is_not_nil(x_idx)
    assert.equals("POST", args[x_idx + 1])
  end)

  it("adds -X DELETE for DELETE", function()
    local args = builder.build(req({ method = "DELETE" }))
    assert.truthy(vim.tbl_contains(args, "DELETE"))
  end)

  it("adds -X PATCH for PATCH", function()
    local args = builder.build(req({ method = "PATCH" }))
    assert.truthy(vim.tbl_contains(args, "PATCH"))
  end)

  it("adds -X PUT for PUT", function()
    local args = builder.build(req({ method = "PUT" }))
    assert.truthy(vim.tbl_contains(args, "PUT"))
  end)
end)

-- ── Headers ───────────────────────────────────────────────────────────────────

describe("expecto.curl_builder — headers", function()
  before_each(function() config.setup({}) end)

  it("adds -H for each header", function()
    local args = builder.build(req({
      headers = { ["Content-Type"] = "application/json" }
    }))
    local found = false
    for i, v in ipairs(args) do
      if v == "-H" and args[i + 1] == "Content-Type: application/json" then
        found = true
        break
      end
    end
    assert.is_true(found)
  end)

  it("adds multiple -H flags for multiple headers", function()
    local args = builder.build(req({
      headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
      }
    }))
    local h_count = 0
    for _, v in ipairs(args) do
      if v == "-H" then h_count = h_count + 1 end
    end
    assert.equals(2, h_count)
  end)

  it("adds default headers from config", function()
    config.setup({ default_headers = { ["X-Client"] = "expecto" } })
    local args = builder.build(req({ headers = {} }))
    local found = false
    for i, v in ipairs(args) do
      if v == "-H" and args[i + 1] == "X-Client: expecto" then
        found = true break
      end
    end
    assert.is_true(found)
  end)

  it("does not duplicate headers already in request", function()
    config.setup({ default_headers = { ["X-Client"] = "expecto" } })
    local args = builder.build(req({
      headers = { ["X-Client"] = "override" }
    }))
    local count = 0
    for i, v in ipairs(args) do
      if v == "-H" and (args[i+1] or ""):find("X-Client") then
        count = count + 1
      end
    end
    assert.equals(1, count)
  end)
end)

-- ── Auth schemes ──────────────────────────────────────────────────────────────

describe("expecto.curl_builder — auth schemes", function()
  it("converts Basic user passwd to -u flag", function()
    local args = builder.build(req({
      headers = { Authorization = "Basic alice secret" }
    }))
    local found = false
    for i, v in ipairs(args) do
      if v == "-u" and args[i + 1] == "alice:secret" then
        found = true break
      end
    end
    assert.is_true(found)
    -- Original Authorization header should NOT appear
    local has_auth_header = false
    for i, v in ipairs(args) do
      if v == "-H" and (args[i+1] or ""):match("^Authorization:") then
        has_auth_header = true break
      end
    end
    assert.is_false(has_auth_header)
  end)

  it("converts Digest user passwd to --digest -u", function()
    local args = builder.build(req({
      headers = { Authorization = "Digest alice secret" }
    }))
    assert.truthy(vim.tbl_contains(args, "--digest"))
    local found = false
    for i, v in ipairs(args) do
      if v == "-u" and args[i + 1] == "alice:secret" then found = true break end
    end
    assert.is_true(found)
  end)

  it("passes Bearer token header as-is", function()
    local args = builder.build(req({
      headers = { Authorization = "Bearer abc123" }
    }))
    local found = false
    for i, v in ipairs(args) do
      if v == "-H" and args[i+1] == "Authorization: Bearer abc123" then
        found = true break
      end
    end
    assert.is_true(found)
  end)
end)

-- ── Request body ──────────────────────────────────────────────────────────────

describe("expecto.curl_builder — request body", function()
  it("adds --data-binary for inline body", function()
    local args = builder.build(req({
      method = "POST",
      body   = '{"name":"test"}',
    }))
    local found = false
    for i, v in ipairs(args) do
      if v == "--data-binary" and args[i + 1] == '{"name":"test"}' then
        found = true break
      end
    end
    assert.is_true(found)
  end)

  it("does not add body for HEAD requests", function()
    local args = builder.build(req({
      method = "HEAD",
      body   = "some body",
    }))
    assert.is_false(vim.tbl_contains(args, "--data-binary"))
  end)

  it("adds @filepath for file body", function()
    local args = builder.build(req({
      method    = "POST",
      body_file = "./payload.json",
    }))
    local found = false
    for i, v in ipairs(args) do
      if v == "--data-binary" and args[i + 1] == "@./payload.json" then
        found = true break
      end
    end
    assert.is_true(found)
  end)
end)

-- ── Redirect + timeout ────────────────────────────────────────────────────────

describe("expecto.curl_builder — redirects and timeout", function()
  before_each(function() config.setup({}) end)

  it("adds -L when follow_redirects is true", function()
    config.setup({ follow_redirects = true })
    local args = builder.build(req())
    assert.truthy(vim.tbl_contains(args, "-L"))
  end)

  it("omits -L when follow_redirects is false", function()
    config.setup({ follow_redirects = false })
    local args = builder.build(req())
    assert.is_false(vim.tbl_contains(args, "-L"))
  end)

  it("omits -L when # @no-redirect is set", function()
    config.setup({ follow_redirects = true })
    local args = builder.build(req({ meta = { no_redirect = true, no_cookie_jar = false } }))
    assert.is_false(vim.tbl_contains(args, "-L"))
  end)

  it("respects custom timeout from opts", function()
    local args = builder.build(req(), { timeout = 10 })
    local mt_idx = nil
    for i, v in ipairs(args) do
      if v == "--max-time" then mt_idx = i break end
    end
    assert.equals("10", args[mt_idx + 1])
  end)
end)

-- ── Cookie jar ────────────────────────────────────────────────────────────────

describe("expecto.curl_builder — cookie jar", function()
  it("adds -b and -c when cookie_jar is provided", function()
    local args = builder.build(req(), { cookie_jar = "/tmp/cookies.txt" })
    assert.truthy(vim.tbl_contains(args, "-b"))
    assert.truthy(vim.tbl_contains(args, "-c"))
    assert.truthy(vim.tbl_contains(args, "/tmp/cookies.txt"))
  end)

  it("omits cookie jar when # @no-cookie-jar is set", function()
    local args = builder.build(
      req({ meta = { no_redirect = false, no_cookie_jar = true } }),
      { cookie_jar = "/tmp/cookies.txt" }
    )
    assert.is_false(vim.tbl_contains(args, "-b"))
  end)
end)
