local vars = require("expecto.variables")

-- ── File variable resolution ──────────────────────────────────────────────────

describe("expecto.variables — file vars", function()
  it("resolves a simple file variable", function()
    local result = vars.resolve("{{host}}", {
      file_vars = { host = "example.com" }
    })
    assert.equals("example.com", result)
  end)

  it("resolves multiple vars in one string", function()
    local result = vars.resolve("https://{{host}}:{{port}}/api", {
      file_vars = { host = "example.com", port = "8080" }
    })
    assert.equals("https://example.com:8080/api", result)
  end)

  it("resolves nested variable references", function()
    -- @host = example.com
    -- @baseUrl = https://{{host}}
    -- Result: https://example.com
    local result = vars.resolve("{{baseUrl}}", {
      file_vars = {
        host    = "example.com",
        baseUrl = "https://{{host}}",
      }
    })
    assert.equals("https://example.com", result)
  end)

  it("leaves unresolved vars as-is (curly intact)", function()
    local result = vars.resolve("{{unknown}}", { file_vars = {} })
    assert.equals("{{unknown}}", result)
  end)

  it("resolves env vars when file var is absent", function()
    local result = vars.resolve("{{token}}", {
      file_vars = {},
      env_vars  = { token = "env-token-123" },
    })
    assert.equals("env-token-123", result)
  end)

  it("file vars take precedence over env vars", function()
    local result = vars.resolve("{{token}}", {
      file_vars = { token = "file-token" },
      env_vars  = { token = "env-token" },
    })
    assert.equals("file-token", result)
  end)

  it("resolves empty string as empty string", function()
    local result = vars.resolve("", { file_vars = {} })
    assert.equals("", result)
  end)

  it("passes through strings with no vars unchanged", function()
    local result = vars.resolve("plain text", { file_vars = {} })
    assert.equals("plain text", result)
  end)
end)

-- ── System variables ──────────────────────────────────────────────────────────

describe("expecto.variables — system vars", function()
  it("resolves {{$guid}} to a non-empty string", function()
    local result = vars.resolve("{{$guid}}", {})
    assert.is_not_nil(result)
    assert.is_true(#result > 0)
    assert.is_false(result:find("{{", 1, true) ~= nil)
  end)

  it("resolves {{$guid}} to something that looks like a UUID", function()
    local result = vars.resolve("{{$guid}}", {})
    -- UUID format: 8-4-4-4-12 hex chars
    assert.truthy(result:match("^[0-9a-f%-]+$"))
  end)

  it("resolves {{$timestamp}} to a number string", function()
    local result = vars.resolve("{{$timestamp}}", {})
    local n = tonumber(result)
    assert.is_not_nil(n)
    -- Should be a plausible Unix timestamp (after 2020-01-01)
    assert.is_true(n > 1577836800)
  end)

  it("resolves {{$timestamp 1 d}} to tomorrow's timestamp", function()
    local now = os.time()
    local result = vars.resolve("{{$timestamp 1 d}}", {})
    local n = tonumber(result)
    assert.is_not_nil(n)
    -- Should be approximately now + 86400
    assert.is_true(math.abs(n - (now + 86400)) < 5)
  end)

  it("resolves {{$timestamp -1 h}} to one hour ago", function()
    local now = os.time()
    local result = vars.resolve("{{$timestamp -1 h}}", {})
    local n = tonumber(result)
    assert.is_not_nil(n)
    assert.is_true(math.abs(n - (now - 3600)) < 5)
  end)

  it("resolves {{$randomInt 1 10}} to a number in [1,9]", function()
    local result = vars.resolve("{{$randomInt 1 10}}", {})
    local n = tonumber(result)
    assert.is_not_nil(n)
    assert.is_true(n >= 1)
    assert.is_true(n <= 9)
  end)

  it("resolves {{$randomInt 0 1}} to 0", function()
    -- math.random(0, 0) always returns 0 (hi-1 = 0)
    local result = vars.resolve("{{$randomInt 0 1}}", {})
    assert.equals("0", result)
  end)

  it("resolves {{$datetime iso8601}} to an ISO8601-looking string", function()
    local result = vars.resolve("{{$datetime iso8601}}", {})
    -- ISO8601: 2026-03-21T20:30:00Z
    assert.truthy(result:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"))
  end)

  it("resolves {{$datetime rfc1123}} to an RFC1123-looking string", function()
    local result = vars.resolve("{{$datetime rfc1123}}", {})
    -- RFC1123: Sat, 21 Mar 2026 20:30:00 GMT
    assert.truthy(result:match("%a+, %d+ %a+ %d+ %d+:%d+:%d+ GMT"))
  end)

  it("resolves {{$processEnv PATH}} to a non-empty string", function()
    local result = vars.resolve("{{$processEnv PATH}}", {})
    assert.is_not_nil(result)
    assert.is_true(#result > 0)
    -- PATH should contain at least one slash
    assert.truthy(result:find("/"))
  end)

  it("leaves {{$processEnv NONEXISTENT_12345}} unresolved", function()
    local result = vars.resolve("{{$processEnv NONEXISTENT_12345}}", {})
    assert.truthy(result:find("{{", 1, true))
  end)

  it("does not leave {{ }} after resolution", function()
    local result = vars.resolve("id={{$guid}}", {})
    assert.is_false(result:find("{{", 1, true) ~= nil)
  end)
end)

-- ── resolve_request ───────────────────────────────────────────────────────────

--- Shared helper: build a minimal Request object for resolve_request tests.
local function make_req(overrides)
  return vim.tbl_deep_extend("force", {
    method   = "GET",
    url      = "https://example.com/api",
    headers  = {},
    body     = nil,
    file_vars = {},
    meta     = { no_redirect = false, no_cookie_jar = false },
    prompts  = {},
    is_curl  = false,
    is_graphql = false,
    body_file = nil,
    body_file_vars = false,
  }, overrides or {})
end

describe("expecto.variables — resolve_request", function()
  it("resolves file vars in URL", function()
    local req = make_req({
      url = "{{baseUrl}}/users",
      file_vars = { baseUrl = "https://api.example.com" },
    })
    local resolved = vars.resolve_request(req)
    assert.equals("https://api.example.com/users", resolved.url)
  end)

  it("resolves file vars in header values", function()
    local req = make_req({
      headers = { Authorization = "Bearer {{token}}" },
      file_vars = { token = "abc123" },
    })
    local resolved = vars.resolve_request(req)
    assert.equals("Bearer abc123", resolved.headers["Authorization"])
  end)

  it("resolves file vars in body", function()
    local req = make_req({
      body = '{"user":"{{username}}"}',
      file_vars = { username = "mau" },
    })
    local resolved = vars.resolve_request(req)
    assert.equals('{"user":"mau"}', resolved.body)
  end)

  it("does not mutate the original request", function()
    local req = make_req({
      url = "{{base}}/api",
      file_vars = { base = "https://example.com" },
    })
    vars.resolve_request(req)
    -- Original url must be unchanged
    assert.equals("{{base}}/api", req.url)
  end)

  it("resolves system vars in body", function()
    local req = make_req({
      body = '{"id":"{{$guid}}"}',
    })
    local resolved = vars.resolve_request(req)
    assert.is_false(resolved.body:find("{{", 1, true) ~= nil)
  end)

  it("handles request with no body gracefully", function()
    local req = make_req({ body = nil })
    local resolved = vars.resolve_request(req)
    assert.is_nil(resolved.body)
  end)
end)

-- ── Body file with variable resolution (<@ syntax) ────────────────────────────

describe("expecto.variables — body file var resolution", function()
  it("reads file content and resolves vars when body_file_vars=true", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write('{"token":"{{token}}","host":"{{host}}"}')
    f:close()

    local req = make_req({
      body           = nil,
      body_file      = tmp,
      body_file_vars = true,
      file_vars      = { token = "abc", host = "localhost" },
    })
    local resolved = vars.resolve_request(req)

    assert.equals('{"token":"abc","host":"localhost"}', resolved.body)
    assert.is_nil(resolved.body_file)  -- promoted to inline body

    os.remove(tmp)
  end)

  it("resolves env_vars in body file content", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write("Bearer {{token}}")
    f:close()

    local req = make_req({
      body           = nil,
      body_file      = tmp,
      body_file_vars = true,
    })
    local resolved = vars.resolve_request(req, { token = "env-tok" })

    assert.equals("Bearer env-tok", resolved.body)

    os.remove(tmp)
  end)

  it("does NOT read file when body_file_vars=false (plain < ref)", function()
    local req = make_req({
      body           = nil,
      body_file      = "/some/file.json",
      body_file_vars = false,
    })
    local resolved = vars.resolve_request(req)

    -- body_file preserved; body stays nil
    assert.equals("/some/file.json", resolved.body_file)
    assert.is_nil(resolved.body)
  end)
end)
