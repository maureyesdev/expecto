local rv   = require("expecto.request_vars")
local vars = require("expecto.variables")

-- ── request_vars: store / get_all / reset ─────────────────────────────────────

describe("expecto.request_vars — storage", function()
  before_each(function() rv.reset() end)

  it("starts empty", function()
    assert.same({}, rv.get_all())
  end)

  it("stores a response under its name", function()
    rv.store("login", { status_code = 200, headers = {}, body = "" })
    local all = rv.get_all()
    assert.is_not_nil(all["login"])
    assert.equals(200, all["login"].status_code)
  end)

  it("overwrites the previous response for the same name", function()
    rv.store("login", { status_code = 401, headers = {}, body = "" })
    rv.store("login", { status_code = 200, headers = {}, body = "{}" })
    assert.equals(200, rv.get_all()["login"].status_code)
  end)

  it("stores multiple named responses independently", function()
    rv.store("login",   { status_code = 200, headers = {}, body = "" })
    rv.store("profile", { status_code = 200, headers = {}, body = "" })
    local all = rv.get_all()
    assert.is_not_nil(all["login"])
    assert.is_not_nil(all["profile"])
  end)

  it("reset() clears all entries", function()
    rv.store("login", { status_code = 200, headers = {}, body = "" })
    rv.reset()
    assert.same({}, rv.get_all())
  end)

  it("get_all() returns a shallow copy (mutations do not affect store)", function()
    rv.store("req", { status_code = 200, headers = {}, body = "" })
    local all = rv.get_all()
    all["req"] = nil
    assert.is_not_nil(rv.get_all()["req"])
  end)
end)

-- ── variable resolution — request chaining ────────────────────────────────────

local function make_resp(status, headers, body)
  return {
    status_code = status,
    headers     = headers or {},
    body        = body or "",
  }
end

describe("expecto.variables — request chaining: status", function()
  before_each(function() rv.reset() end)

  it("resolves {{req.response.status}} to the status code", function()
    rv.store("login", make_resp(200, {}, ""))
    local result = vars.resolve("{{login.response.status}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("200", result)
  end)

  it("resolves 404 status correctly", function()
    rv.store("check", make_resp(404, {}, ""))
    local result = vars.resolve("{{check.response.status}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("404", result)
  end)

  it("leaves ref unresolved when name not in store", function()
    local result = vars.resolve("{{unknown.response.status}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("{{unknown.response.status}}", result)
  end)
end)

describe("expecto.variables — request chaining: headers", function()
  before_each(function() rv.reset() end)

  it("resolves {{req.response.headers.x-token}}", function()
    rv.store("login", make_resp(200, { ["x-token"] = "abc123" }, ""))
    local result = vars.resolve("{{login.response.headers.x-token}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("abc123", result)
  end)

  it("is case-insensitive for header names (uses lowercased store)", function()
    -- Response headers are always stored lowercased by curl_parser
    rv.store("auth", make_resp(200, { ["authorization"] = "Bearer tok" }, ""))
    local result = vars.resolve("{{auth.response.headers.authorization}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("Bearer tok", result)
  end)

  it("leaves ref unresolved when header not present", function()
    rv.store("req", make_resp(200, {}, ""))
    local result = vars.resolve("{{req.response.headers.missing}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("{{req.response.headers.missing}}", result)
  end)
end)

describe("expecto.variables — request chaining: body (raw)", function()
  before_each(function() rv.reset() end)

  it("resolves {{req.response.body}} to the raw body string", function()
    rv.store("data", make_resp(200, {}, "hello world"))
    local result = vars.resolve("{{data.response.body}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("hello world", result)
  end)

  it("returns empty string body as-is", function()
    rv.store("empty", make_resp(204, {}, ""))
    local result = vars.resolve("{{empty.response.body}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("", result)
  end)
end)

describe("expecto.variables — request chaining: JSONPath body extraction", function()
  before_each(function() rv.reset() end)

  it("extracts a top-level field with $.field", function()
    rv.store("login", make_resp(200, {}, '{"token":"secret","userId":42}'))
    local result = vars.resolve("{{login.response.body.$.token}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("secret", result)
  end)

  it("extracts a numeric field as string", function()
    rv.store("login", make_resp(200, {}, '{"userId":42}'))
    local result = vars.resolve("{{login.response.body.$.userId}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("42", result)
  end)

  it("extracts a nested field with $.a.b", function()
    rv.store("req", make_resp(200, {}, '{"user":{"id":"u-1","name":"Alice"}}'))
    local result = vars.resolve("{{req.response.body.$.user.id}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("u-1", result)
  end)

  it("extracts an array element with $.array[0]", function()
    rv.store("req", make_resp(200, {}, '{"items":["first","second","third"]}'))
    local result = vars.resolve("{{req.response.body.$.items[0]}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("first", result)
  end)

  it("extracts the second array element with [1]", function()
    rv.store("req", make_resp(200, {}, '{"ids":[10,20,30]}'))
    local result = vars.resolve("{{req.response.body.$.ids[1]}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("20", result)
  end)

  it("leaves ref unresolved when path does not exist", function()
    rv.store("req", make_resp(200, {}, '{"a":1}'))
    local result = vars.resolve("{{req.response.body.$.b}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("{{req.response.body.$.b}}", result)
  end)

  it("leaves ref unresolved when body is not valid JSON", function()
    rv.store("req", make_resp(200, {}, "plain text"))
    local result = vars.resolve("{{req.response.body.$.field}}", {
      request_vars = rv.get_all(),
    })
    assert.equals("{{req.response.body.$.field}}", result)
  end)

  it("encodes nested object as JSON string", function()
    rv.store("req", make_resp(200, {}, '{"meta":{"page":1,"total":5}}'))
    local result = vars.resolve("{{req.response.body.$.meta}}", {
      request_vars = rv.get_all(),
    })
    -- Should be a JSON string of the object
    assert.truthy(result:find("page"))
    assert.truthy(result:find("total"))
  end)
end)

describe("expecto.variables — request chaining: used in full request", function()
  before_each(function() rv.reset() end)

  it("substitutes chained token into Authorization header", function()
    rv.store("login", make_resp(200, {}, '{"accessToken":"jwt-abc"}'))

    local req = {
      method  = "GET",
      url     = "https://api.example.com/me",
      headers = { Authorization = "Bearer {{login.response.body.$.accessToken}}" },
      body    = nil,
      file_vars = {},
    }
    local resolved = vars.resolve_request(req, {}, rv.get_all())
    assert.equals("Bearer jwt-abc", resolved.headers["Authorization"])
  end)

  it("substitutes chained token into URL", function()
    rv.store("auth", make_resp(200, { ["x-session"] = "sess-99" }, ""))

    local req = {
      method    = "GET",
      url       = "https://api.example.com/session/{{auth.response.headers.x-session}}",
      headers   = {},
      body      = nil,
      file_vars = {},
    }
    local resolved = vars.resolve_request(req, {}, rv.get_all())
    assert.equals("https://api.example.com/session/sess-99", resolved.url)
  end)
end)
