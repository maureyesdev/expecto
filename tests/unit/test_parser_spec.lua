local parser = require("expecto.parser")

-- ── Helper ────────────────────────────────────────────────────────────────────

--- Parse a heredoc string (trim leading newline added by [[ ]]).
local function http(s)
  return parser.parse(s:gsub("^\n", ""))
end

--- Parse and return the first (and usually only) request.
local function first(s)
  local reqs = http(s)
  return reqs[1]
end

-- ── Request line ──────────────────────────────────────────────────────────────

describe("expecto.parser — request line", function()
  it("parses a basic GET request", function()
    local r = first("GET https://example.com/api HTTP/1.1")
    assert.equals("GET", r.method)
    assert.equals("https://example.com/api", r.url)
    assert.equals("HTTP/1.1", r.http_version)
  end)

  it("parses GET without HTTP version", function()
    local r = first("GET https://example.com/api")
    assert.equals("GET", r.method)
    assert.equals("https://example.com/api", r.url)
    assert.is_nil(r.http_version)
  end)

  it("defaults to GET when only a URL is given", function()
    local r = first("https://example.com/api")
    assert.equals("GET", r.method)
    assert.equals("https://example.com/api", r.url)
  end)

  it("parses POST", function()
    local r = first("POST https://example.com/api")
    assert.equals("POST", r.method)
  end)

  it("parses PUT", function()
    local r = first("PUT https://example.com/resource/1")
    assert.equals("PUT", r.method)
  end)

  it("parses DELETE", function()
    local r = first("DELETE https://example.com/resource/1")
    assert.equals("DELETE", r.method)
  end)

  it("parses PATCH", function()
    local r = first("PATCH https://example.com/resource/1")
    assert.equals("PATCH", r.method)
  end)

  it("parses HEAD", function()
    local r = first("HEAD https://example.com/api")
    assert.equals("HEAD", r.method)
  end)

  it("parses OPTIONS", function()
    local r = first("OPTIONS https://example.com/api")
    assert.equals("OPTIONS", r.method)
  end)

  it("parses HTTP/2 version", function()
    local r = first("GET https://example.com/api HTTP/2")
    assert.equals("HTTP/2", r.http_version)
  end)

  it("parses https URLs", function()
    local r = first("GET https://secure.example.com/api")
    assert.equals("https://secure.example.com/api", r.url)
  end)

  it("parses URL with query string inline", function()
    local r = first("GET https://example.com/api?page=1&size=10")
    assert.equals("https://example.com/api?page=1&size=10", r.url)
  end)

  it("records line_start for request line", function()
    -- Call parser.parse directly (bypassing the http() helper's \n strip)
    -- so we control the exact line numbers.
    local r = parser.parse("\n\nGET https://example.com/api")[1]
    assert.equals(3, r.line_start)
  end)
end)

-- ── Multi-line query params ───────────────────────────────────────────────────

describe("expecto.parser — multi-line query params", function()
  it("appends ? continuation to URL", function()
    local r = first([[
GET https://example.com/api
    ?page=1
    &size=10]])
    assert.equals("https://example.com/api?page=1&size=10", r.url)
  end)

  it("handles multiple continuations", function()
    local r = first([[
GET https://example.com/search
    ?q=hello
    &lang=en
    &page=2]])
    assert.equals("https://example.com/search?q=hello&lang=en&page=2", r.url)
  end)

  it("transitions from URL_CONT to headers correctly", function()
    local r = first([[
GET https://example.com/api
    ?foo=bar
Accept: application/json]])
    assert.equals("https://example.com/api?foo=bar", r.url)
    assert.equals("application/json", r.headers["Accept"])
  end)
end)

-- ── Headers ───────────────────────────────────────────────────────────────────

describe("expecto.parser — headers", function()
  it("parses a single header", function()
    local r = first([[
GET https://example.com/api
Accept: application/json]])
    assert.equals("application/json", r.headers["Accept"])
  end)

  it("parses multiple headers", function()
    local r = first([[
POST https://example.com/api
Content-Type: application/json
Accept: application/json
Authorization: Bearer token123]])
    assert.equals("application/json", r.headers["Content-Type"])
    assert.equals("application/json", r.headers["Accept"])
    assert.equals("Bearer token123", r.headers["Authorization"])
  end)

  it("parses headers with hyphens in name", function()
    local r = first([[
GET https://example.com/api
X-Request-Id: abc123
X-Custom-Header: custom]])
    assert.equals("abc123", r.headers["X-Request-Id"])
    assert.equals("custom", r.headers["X-Custom-Header"])
  end)

  it("handles header with empty value", function()
    local r = first([[
GET https://example.com/api
X-Empty:]])
    assert.equals("", r.headers["X-Empty"])
  end)

  it("returns empty headers when none present", function()
    local r = first("GET https://example.com/api")
    assert.same({}, r.headers)
  end)
end)

-- ── Request body ─────────────────────────────────────────────────────────────

describe("expecto.parser — request body", function()
  it("parses JSON body after blank line", function()
    local r = first([[
POST https://example.com/api
Content-Type: application/json

{"name":"test"}]])
    assert.equals('{"name":"test"}', r.body)
  end)

  it("parses multi-line JSON body", function()
    local r = first([[
POST https://example.com/api
Content-Type: application/json

{
  "name": "test",
  "value": 42
}]])
    assert.equals('{\n  "name": "test",\n  "value": 42\n}', r.body)
  end)

  it("strips trailing blank lines from body", function()
    local r = first("POST https://example.com/api\n\nbody line\n\n\n")
    assert.equals("body line", r.body)
  end)

  it("returns nil body when no body present", function()
    local r = first("GET https://example.com/api\nAccept: application/json")
    assert.is_nil(r.body)
  end)

  it("parses URL-encoded body", function()
    local r = first([[
POST https://example.com/login
Content-Type: application/x-www-form-urlencoded

name=foo
&password=bar]])
    assert.equals("name=foo\n&password=bar", r.body)
  end)
end)

-- ── Body file references ──────────────────────────────────────────────────────

describe("expecto.parser — body file references", function()
  it("parses < file reference", function()
    local r = first([[
POST https://example.com/api

< ./payload.json]])
    assert.equals("./payload.json", r.body_file)
    assert.is_false(r.body_file_vars)
    assert.is_nil(r.body_encoding)
    assert.is_nil(r.body)
  end)

  it("parses <@ file reference with variable processing", function()
    local r = first([[
POST https://example.com/api

<@ ./payload.json]])
    assert.equals("./payload.json", r.body_file)
    assert.is_true(r.body_file_vars)
    assert.is_nil(r.body_encoding)
  end)

  it("parses <@latin1 file reference with encoding", function()
    local r = first([[
POST https://example.com/api

<@latin1 ./payload.xml]])
    assert.equals("./payload.xml", r.body_file)
    assert.is_true(r.body_file_vars)
    assert.equals("latin1", r.body_encoding)
  end)

  it("parses absolute path file reference", function()
    local r = first([[
POST https://example.com/api

< /Users/mau/payload.json]])
    assert.equals("/Users/mau/payload.json", r.body_file)
  end)
end)

-- ── Comments ──────────────────────────────────────────────────────────────────

describe("expecto.parser — comments", function()
  it("skips # comment lines before request", function()
    local r = first([[
# This is a comment
GET https://example.com/api]])
    assert.equals("GET", r.method)
    assert.equals("https://example.com/api", r.url)
  end)

  it("skips // comment lines before request", function()
    local r = first([[
// This is a comment
GET https://example.com/api]])
    assert.equals("GET", r.method)
  end)

  it("skips multiple comment lines", function()
    local r = first([[
# Comment 1
# Comment 2
// Comment 3
GET https://example.com/api]])
    assert.equals("https://example.com/api", r.url)
  end)

  it("does NOT treat # @annotation as a comment", function()
    local r = first([[
# @name myRequest
GET https://example.com/api]])
    assert.equals("myRequest", r.name)
  end)

  it("does NOT treat // @annotation as a comment", function()
    local r = first([[
// @name myRequest
GET https://example.com/api]])
    assert.equals("myRequest", r.name)
  end)
end)

-- ── File variables ────────────────────────────────────────────────────────────

describe("expecto.parser — file variables", function()
  it("parses a file variable definition", function()
    local r = first([[
@baseUrl = https://example.com
GET {{baseUrl}}/api]])
    assert.equals("https://example.com", r.file_vars["baseUrl"])
  end)

  it("parses multiple file variable definitions", function()
    local r = first([[
@host = example.com
@port = 8080
GET https://{{host}}:{{port}}/api]])
    assert.equals("example.com", r.file_vars["host"])
    assert.equals("8080", r.file_vars["port"])
  end)

  it("accumulates file vars across blocks", function()
    local reqs = http([[
@host = example.com

###

@token = abc123
GET https://{{host}}/api]])
    -- The second block's request should have both vars
    assert.equals("example.com", reqs[1].file_vars["host"])
    assert.equals("abc123", reqs[1].file_vars["token"])
  end)

  it("file vars from prior blocks are available in later blocks", function()
    local reqs = http([[
@baseUrl = https://example.com

###

GET {{baseUrl}}/users]])
    assert.equals("https://example.com", reqs[1].file_vars["baseUrl"])
  end)

  it("parses file var with spaces in value", function()
    local r = first([[
@greeting = Hello World
GET https://example.com/api]])
    assert.equals("Hello World", r.file_vars["greeting"])
  end)

  it("parses file var with empty value", function()
    local r = first([[
@empty =
GET https://example.com/api]])
    assert.equals("", r.file_vars["empty"])
  end)
end)

-- ── Annotations ───────────────────────────────────────────────────────────────

describe("expecto.parser — annotations", function()
  it("parses # @name annotation", function()
    local r = first([[
# @name loginRequest
POST https://example.com/login]])
    assert.equals("loginRequest", r.name)
  end)

  it("parses // @name annotation", function()
    local r = first([[
// @name loginRequest
POST https://example.com/login]])
    assert.equals("loginRequest", r.name)
  end)

  it("parses # @no-redirect", function()
    local r = first([[
# @no-redirect
GET https://example.com/api]])
    assert.is_true(r.meta.no_redirect)
  end)

  it("parses # @no-cookie-jar", function()
    local r = first([[
# @no-cookie-jar
GET https://example.com/api]])
    assert.is_true(r.meta.no_cookie_jar)
  end)

  it("parses # @note with value", function()
    local r = first([[
# @note This is a critical request
GET https://example.com/api]])
    assert.equals("This is a critical request", r.meta.note)
  end)

  it("meta flags default to false/nil", function()
    local r = first("GET https://example.com/api")
    assert.is_false(r.meta.no_redirect)
    assert.is_false(r.meta.no_cookie_jar)
    assert.is_nil(r.meta.note)
  end)

  it("parses # @prompt with name only", function()
    local r = first([[
# @prompt username
POST https://example.com/login]])
    assert.equals(1, #r.prompts)
    assert.equals("username", r.prompts[1].name)
    assert.is_nil(r.prompts[1].description)
  end)

  it("parses # @prompt with name and description", function()
    local r = first([[
# @prompt otp Your one-time password
POST https://example.com/verify]])
    assert.equals("otp", r.prompts[1].name)
    assert.equals("Your one-time password", r.prompts[1].description)
  end)

  it("parses multiple @prompt annotations", function()
    local r = first([[
# @prompt username
# @prompt password Your password
POST https://example.com/login]])
    assert.equals(2, #r.prompts)
    assert.equals("username", r.prompts[1].name)
    assert.equals("password", r.prompts[2].name)
  end)
end)

-- ── Multiple requests (separators) ───────────────────────────────────────────

describe("expecto.parser — separators and multiple requests", function()
  it("splits two requests separated by ###", function()
    local reqs = http([[
GET https://example.com/one

###

POST https://example.com/two]])
    assert.equals(2, #reqs)
    assert.equals("GET", reqs[1].method)
    assert.equals("https://example.com/one", reqs[1].url)
    assert.equals("POST", reqs[2].method)
    assert.equals("https://example.com/two", reqs[2].url)
  end)

  it("splits three requests", function()
    local reqs = http([[
GET https://a.com

###

GET https://b.com

###

GET https://c.com]])
    assert.equals(3, #reqs)
    assert.equals("https://a.com", reqs[1].url)
    assert.equals("https://b.com", reqs[2].url)
    assert.equals("https://c.com", reqs[3].url)
  end)

  it("ignores blocks with no request line (only file vars)", function()
    local reqs = http([[
@host = example.com

###

GET https://{{host}}/api]])
    assert.equals(1, #reqs)
    assert.equals("example.com", reqs[1].file_vars["host"])
  end)

  it("accepts ### with a label", function()
    local reqs = http([[
GET https://example.com/one

### Second request

GET https://example.com/two]])
    assert.equals(2, #reqs)
  end)

  it("accepts #### (4+ hashes) as a separator", function()
    local reqs = http([[
GET https://example.com/one

####

GET https://example.com/two]])
    assert.equals(2, #reqs)
  end)
end)

-- ── GraphQL ───────────────────────────────────────────────────────────────────

describe("expecto.parser — GraphQL", function()
  it("detects GraphQL via X-REQUEST-TYPE header", function()
    local r = first([[
POST https://api.example.com/graphql
Content-Type: application/json
X-REQUEST-TYPE: GraphQL

query { user { id name } }]])
    assert.is_true(r.is_graphql)
  end)

  it("detects GraphQL case-insensitively", function()
    local r = first([[
POST https://api.example.com/graphql
X-Request-Type: graphql

query { user { id } }]])
    assert.is_true(r.is_graphql)
  end)

  it("splits GraphQL query and variables on blank line", function()
    local r = first([[
POST https://api.example.com/graphql
X-REQUEST-TYPE: GraphQL

query ($id: ID!) {
  user(id: $id) { name }
}

{"id": "123"}]])
    assert.equals('query ($id: ID!) {\n  user(id: $id) { name }\n}', r.body)
    assert.equals('{"id": "123"}', r.graphql_variables)
  end)

  it("is_graphql is false for regular POST", function()
    local r = first([[
POST https://api.example.com/data
Content-Type: application/json

{"query": "not graphql"}]])
    assert.is_false(r.is_graphql)
  end)
end)

-- ── cURL blocks ───────────────────────────────────────────────────────────────

describe("expecto.parser — cURL blocks", function()
  it("detects a curl command", function()
    local r = first("curl https://example.com/api")
    assert.is_true(r.is_curl)
  end)

  it("captures curl raw command", function()
    local r = first("curl -X POST https://example.com/api -H 'Content-Type: application/json'")
    assert.is_true(r.is_curl)
    assert.is_not_nil(r.curl_raw)
  end)

  it("handles multi-line curl with backslash continuation", function()
    local r = first([[
curl -X POST https://example.com/api \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}']])
    assert.is_true(r.is_curl)
  end)
end)

-- ── Edge cases ────────────────────────────────────────────────────────────────

describe("expecto.parser — edge cases", function()
  it("returns empty list for empty content", function()
    local reqs = http("")
    assert.same({}, reqs)
  end)

  it("returns empty list for content with only comments", function()
    local reqs = http([[
# comment 1
# comment 2
// comment 3]])
    assert.same({}, reqs)
  end)

  it("returns empty list for content with only file vars", function()
    local reqs = http([[
@host = example.com
@port = 8080]])
    assert.same({}, reqs)
  end)

  it("accepts table of lines as input", function()
    local reqs = parser.parse({ "GET https://example.com/api" })
    assert.equals(1, #reqs)
    assert.equals("GET", reqs[1].method)
  end)

  it("handles CRLF line endings", function()
    local r = first("GET https://example.com/api\r\nAccept: application/json")
    assert.equals("GET", r.method)
    assert.equals("application/json", r.headers["Accept"])
  end)

  it("handles request with body but no headers", function()
    local r = first([[
POST https://example.com/api

raw body content]])
    assert.equals("POST", r.method)
    assert.equals("raw body content", r.body)
    assert.same({}, r.headers)
  end)

  it("does not carry name across requests", function()
    local reqs = http([[
# @name firstRequest
GET https://example.com/one

###

GET https://example.com/two]])
    assert.equals("firstRequest", reqs[1].name)
    assert.is_nil(reqs[2].name)
  end)

  it("each request gets independent file_vars snapshot", function()
    local reqs = http([[
@v = one
GET https://example.com/one

###

@v = two
GET https://example.com/two]])
    assert.equals("one", reqs[1].file_vars["v"])
    assert.equals("two", reqs[2].file_vars["v"])
  end)

  it("request with no headers and no body has empty body", function()
    local r = first("GET https://example.com/api")
    assert.is_nil(r.body)
    assert.is_nil(r.body_file)
  end)

  it("prompts list defaults to empty", function()
    local r = first("GET https://example.com/api")
    assert.same({}, r.prompts)
  end)
end)

-- ── _parse_block (internal) ───────────────────────────────────────────────────

describe("expecto.parser._parse_block", function()
  it("returns nil for empty block", function()
    local req, vars = parser._parse_block({}, 1, {})
    assert.is_nil(req)
    assert.same({}, vars)
  end)

  it("returns nil for comment-only block", function()
    local req, vars = parser._parse_block({ "# comment" }, 1, {})
    assert.is_nil(req)
  end)

  it("returns new_file_vars even when no request found", function()
    local req, vars = parser._parse_block({ "@foo = bar" }, 1, {})
    assert.is_nil(req)
    assert.equals("bar", vars["foo"])
  end)

  it("inherits file vars from inherited_vars", function()
    local req, _ = parser._parse_block(
      { "GET https://example.com/api" },
      1,
      { host = "example.com" }
    )
    assert.equals("example.com", req.file_vars["host"])
  end)

  it("new vars in block are returned in new_file_vars", function()
    local req, new_vars = parser._parse_block(
      { "@token = abc", "GET https://example.com/api" },
      1,
      {}
    )
    assert.is_not_nil(req)
    assert.equals("abc", new_vars["token"])
  end)

  it("does not modify inherited_vars table directly", function()
    local inherited = { foo = "original" }
    parser._parse_block({ "@foo = changed", "GET https://example.com" }, 1, inherited)
    -- inherited must be untouched (we deepcopy it)
    assert.equals("original", inherited["foo"])
  end)
end)
