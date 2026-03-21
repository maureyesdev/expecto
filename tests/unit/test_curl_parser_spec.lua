local curl_parser = require("expecto.curl_parser")

-- ── Helpers ───────────────────────────────────────────────────────────────────

local TIMING_MARKER = require("expecto.curl_builder").TIMING_MARKER

--- Build a synthetic curl -i -w output string.
local function make_curl_output(status_line, headers, body, timing_overrides)
  local parts = {}
  table.insert(parts, status_line)
  for name, value in pairs(headers or {}) do
    table.insert(parts, name .. ": " .. value)
  end
  table.insert(parts, "")  -- blank line before body
  table.insert(parts, body or "")

  local timing = vim.tbl_extend("force", {
    time_total         = "0.342",
    time_namelookup    = "0.001",
    time_connect       = "0.010",
    time_starttransfer = "0.300",
    size_download      = "1234",
    http_code          = "200",
  }, timing_overrides or {})

  local timing_block = "\n\n" .. TIMING_MARKER .. "\n"
    .. "time_total:"         .. timing.time_total         .. "\n"
    .. "time_namelookup:"    .. timing.time_namelookup    .. "\n"
    .. "time_connect:"       .. timing.time_connect       .. "\n"
    .. "time_starttransfer:" .. timing.time_starttransfer .. "\n"
    .. "size_download:"      .. timing.size_download      .. "\n"
    .. "http_code:"          .. timing.http_code          .. "\n"

  return table.concat(parts, "\n") .. timing_block
end

-- ── Status line parsing ───────────────────────────────────────────────────────

describe("expecto.curl_parser — status line", function()
  it("parses 200 OK", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {}, "")
    local resp = curl_parser.parse(raw)
    assert.equals(200, resp.status_code)
    assert.equals("OK", resp.status_text)
    assert.equals("HTTP/1.1", resp.http_version)
  end)

  it("parses 201 Created", function()
    local raw = make_curl_output("HTTP/1.1 201 Created", {}, "")
    local resp = curl_parser.parse(raw)
    assert.equals(201, resp.status_code)
    assert.equals("Created", resp.status_text)
  end)

  it("parses 404 Not Found", function()
    local raw = make_curl_output("HTTP/1.1 404 Not Found", {}, "")
    local resp = curl_parser.parse(raw)
    assert.equals(404, resp.status_code)
    assert.equals("Not Found", resp.status_text)
  end)

  it("parses 500 Internal Server Error", function()
    local raw = make_curl_output("HTTP/1.1 500 Internal Server Error", {}, "")
    local resp = curl_parser.parse(raw)
    assert.equals(500, resp.status_code)
    assert.equals("Internal Server Error", resp.status_text)
  end)

  it("parses HTTP/2 response", function()
    local raw = make_curl_output("HTTP/2 200 ", {}, "")
    local resp = curl_parser.parse(raw)
    assert.equals(200, resp.status_code)
    assert.equals("HTTP/2", resp.http_version)
  end)

  it("parses 204 No Content with empty body", function()
    local raw = make_curl_output("HTTP/1.1 204 No Content", {}, "")
    local resp = curl_parser.parse(raw)
    assert.equals(204, resp.status_code)
    assert.equals("", resp.body)
  end)
end)

-- ── Header parsing ────────────────────────────────────────────────────────────

describe("expecto.curl_parser — headers", function()
  it("parses content-type header (lowercased)", function()
    local raw = make_curl_output("HTTP/1.1 200 OK",
      { ["Content-Type"] = "application/json" }, "")
    local resp = curl_parser.parse(raw)
    assert.equals("application/json", resp.headers["content-type"])
  end)

  it("parses multiple headers", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {
      ["Content-Type"] = "application/json",
      ["X-Request-Id"] = "abc123",
    }, "")
    local resp = curl_parser.parse(raw)
    assert.equals("application/json", resp.headers["content-type"])
    assert.equals("abc123", resp.headers["x-request-id"])
  end)

  it("sets content_type from Content-Type header", function()
    local raw = make_curl_output("HTTP/1.1 200 OK",
      { ["Content-Type"] = "application/json; charset=utf-8" }, "")
    local resp = curl_parser.parse(raw)
    assert.equals("application/json; charset=utf-8", resp.content_type)
  end)

  it("sets mime stripping charset", function()
    local raw = make_curl_output("HTTP/1.1 200 OK",
      { ["Content-Type"] = "application/json; charset=utf-8" }, "")
    local resp = curl_parser.parse(raw)
    assert.equals("application/json", resp.mime)
  end)

  it("handles response with no headers", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {}, "body")
    local resp = curl_parser.parse(raw)
    assert.equals(200, resp.status_code)
  end)
end)

-- ── Body parsing ──────────────────────────────────────────────────────────────

describe("expecto.curl_parser — body", function()
  it("parses JSON body", function()
    local raw = make_curl_output("HTTP/1.1 200 OK",
      { ["Content-Type"] = "application/json" },
      '{"name":"test"}')
    local resp = curl_parser.parse(raw)
    assert.equals('{"name":"test"}', resp.body)
  end)

  it("parses multi-line JSON body", function()
    local body = '{\n  "name": "test",\n  "value": 42\n}'
    local raw = make_curl_output("HTTP/1.1 200 OK",
      { ["Content-Type"] = "application/json" }, body)
    local resp = curl_parser.parse(raw)
    assert.truthy(resp.body:find('"name"'))
    assert.truthy(resp.body:find('"value"'))
  end)

  it("returns empty string for empty body", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {}, "")
    local resp = curl_parser.parse(raw)
    assert.equals("", resp.body)
  end)

  it("strips trailing whitespace from body", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {}, "body content   \n\n")
    local resp = curl_parser.parse(raw)
    assert.equals("body content", resp.body)
  end)
end)

-- ── Timing parsing ────────────────────────────────────────────────────────────

describe("expecto.curl_parser — timing", function()
  it("parses time_total", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {}, "",
      { time_total = "0.342" })
    local resp = curl_parser.parse(raw)
    assert.is_near(0.342, resp.timing.total, 0.0001)
  end)

  it("parses time_namelookup (dns)", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {}, "",
      { time_namelookup = "0.001" })
    local resp = curl_parser.parse(raw)
    assert.is_near(0.001, resp.timing.dns, 0.0001)
  end)

  it("parses time_connect", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {}, "",
      { time_connect = "0.010" })
    local resp = curl_parser.parse(raw)
    assert.is_near(0.010, resp.timing.connect, 0.0001)
  end)

  it("parses time_starttransfer (ttfb)", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {}, "",
      { time_starttransfer = "0.300" })
    local resp = curl_parser.parse(raw)
    assert.is_near(0.300, resp.timing.ttfb, 0.0001)
  end)

  it("parses size_download", function()
    local raw = make_curl_output("HTTP/1.1 200 OK", {}, "",
      { size_download = "1234" })
    local resp = curl_parser.parse(raw)
    assert.equals(1234, resp.timing.size)
  end)

  it("returns zero timing when marker is absent", function()
    local resp = curl_parser.parse("HTTP/1.1 200 OK\n\nbody")
    assert.equals(0, resp.timing.total or 0)
  end)
end)

-- ── MIME to filetype mapping ──────────────────────────────────────────────────

describe("expecto.curl_parser — mime_to_ft", function()
  it("maps application/json to json", function()
    assert.equals("json", curl_parser.mime_to_ft("application/json"))
  end)

  it("maps text/xml to xml", function()
    assert.equals("xml", curl_parser.mime_to_ft("text/xml"))
  end)

  it("maps application/xml to xml", function()
    assert.equals("xml", curl_parser.mime_to_ft("application/xml"))
  end)

  it("maps text/html to html", function()
    assert.equals("html", curl_parser.mime_to_ft("text/html"))
  end)

  it("maps text/javascript to javascript", function()
    assert.equals("javascript", curl_parser.mime_to_ft("text/javascript"))
  end)

  it("maps text/css to css", function()
    assert.equals("css", curl_parser.mime_to_ft("text/css"))
  end)

  it("maps unknown types to text", function()
    assert.equals("text", curl_parser.mime_to_ft("application/octet-stream"))
  end)

  it("handles nil mime gracefully", function()
    assert.equals("text", curl_parser.mime_to_ft(nil))
  end)
end)

-- ── Empty / error input ───────────────────────────────────────────────────────

describe("expecto.curl_parser — edge cases", function()
  it("handles empty string gracefully", function()
    local resp = curl_parser.parse("")
    assert.equals(0, resp.status_code)
  end)

  it("handles nil gracefully", function()
    local resp = curl_parser.parse(nil)
    assert.equals(0, resp.status_code)
  end)

  it("handles response with redirect (multiple status blocks)", function()
    -- Simulate 301 → 200 redirect output from curl -L -i
    local raw = table.concat({
      "HTTP/1.1 301 Moved Permanently",
      "Location: https://example.com/new",
      "",
      "",
      "HTTP/1.1 200 OK",
      "Content-Type: application/json",
      "",
      '{"redirected":true}',
      "",
      "",
      TIMING_MARKER,
      "time_total:0.5",
      "time_namelookup:0.001",
      "time_connect:0.01",
      "time_starttransfer:0.4",
      "size_download:18",
      "http_code:200",
    }, "\n")

    local resp = curl_parser.parse(raw)
    -- Must reflect the FINAL response, not the redirect
    assert.equals(200, resp.status_code)
    assert.truthy(resp.body:find("redirected"))
  end)
end)
