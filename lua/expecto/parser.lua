--- expecto.nvim — .http/.rest file parser
--- Converts raw buffer content into a list of Request objects.
--- Pure Lua, no side-effects — fully unit-testable.
local M = {}

-- ── Constants ─────────────────────────────────────────────────────────────────

local HTTP_METHODS = {
  GET = true, POST = true, PUT = true, DELETE = true,
  PATCH = true, HEAD = true, OPTIONS = true, CONNECT = true, TRACE = true,
}

-- ── Line classifiers ──────────────────────────────────────────────────────────

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

local function is_separator(line)
  return line:match("^###") ~= nil
end

--- A comment is `#` or `//` but NOT an annotation (`# @something` or `// @something`).
--- The annotation `@` may be preceded by whitespace, so we must exclude those first.
local function is_comment(line)
  -- Annotations take priority — they are NOT comments
  if line:match("^#%s*@") or line:match("^//%s*@") then
    return false
  end
  return line:match("^#") ~= nil or line:match("^//") ~= nil
end

--- An annotation is `# @something` or `// @something`.
local function is_annotation(line)
  return line:match("^#%s*@") ~= nil or line:match("^//%s*@") ~= nil
end

local function is_file_var(line)
  return line:match("^@%S+%s*=") ~= nil
end

local function is_curl(line)
  return line:match("^curl%s") ~= nil
end

-- ── Line parsers ──────────────────────────────────────────────────────────────

--- Returns (name, value|nil) from a `# @name [value]` or `// @name [value]` line.
local function parse_annotation(line)
  local name, rest = line:match("^[#/]+%s*@(%S+)%s*(.*)")
  return name, (rest and rest ~= "") and rest or nil
end

--- Returns (name, value) from `@name = value`.
local function parse_file_var(line)
  local name, value = line:match("^@(%S+)%s*=%s*(.*)")
  return name, value or ""
end

--- Tries to parse a request line. Returns (method, url, version|nil) or nil.
--- URLs may be absolute (https://...), relative (/path), or variable-interpolated
--- ({{baseUrl}}/path) — we accept any non-whitespace token as the URL here;
--- validation happens at execution time.
local function parse_request_line(line)
  -- METHOD URL HTTP/version
  local method, url, version = line:match("^(%u+)%s+(%S+)%s+(HTTP/%d[%d%.]*)%s*$")
  if method and HTTP_METHODS[method] then
    return method, url, version
  end

  -- METHOD URL (no version)
  method, url = line:match("^(%u+)%s+(%S+)%s*$")
  if method and HTTP_METHODS[method] then
    return method, url, nil
  end

  -- Bare https?:// URL only (defaults to GET — no METHOD keyword present)
  url = line:match("^(https?://%S+)%s*$")
  if url then
    return "GET", url, nil
  end

  return nil
end

--- Tries to parse a header line. Returns (name, value) or nil.
local function parse_header_line(line)
  local name, value = line:match("^([%w][%w%-%_]*):%s(.*)$")
  if name then
    return name, value
  end
  -- Header with empty value ("Name:")
  name = line:match("^([%w][%w%-%_]*):$")
  if name then
    return name, ""
  end
  return nil
end

--- Parse a body file reference line: `< path`, `<@ path`, `<@encoding path`.
--- Returns (body_file_vars, encoding|nil, path) or nil if not a file ref.
local function parse_body_file_ref(line)
  -- Pattern: < [@[encoding]] path
  local with_at, encoding, path = line:match("^<(@?)([%a%d_%-]*)%s+(.*)")
  if with_at ~= nil then
    return with_at == "@", (encoding ~= "" and encoding or nil), vim.trim(path)
  end
  return nil
end

-- ── Block splitter ────────────────────────────────────────────────────────────

--- Split lines into blocks separated by `###`.
--- Returns a list of {lines={line_string,...}, first_line=int}.
local function split_blocks(lines)
  local blocks = {}
  local current = { lines = {}, first_line = 1 }

  for i, line in ipairs(lines) do
    if is_separator(line) then
      table.insert(blocks, current)
      current = { lines = {}, first_line = i + 1 }
    else
      table.insert(current.lines, line)
    end
  end
  table.insert(blocks, current)
  return blocks
end

-- ── Block parser ──────────────────────────────────────────────────────────────

--- Parse a single block. Returns (request|nil, new_file_vars).
--- `inherited_vars` is read-only — file vars defined in THIS block are returned
--- in `new_file_vars` and must be merged by the caller.
function M._parse_block(lines, first_line, inherited_vars)
  inherited_vars = inherited_vars or {}

  ---@type table
  local req = {
    method        = "GET",
    url           = nil,
    http_version  = nil,
    headers       = {},
    body          = nil,
    body_file     = nil,
    body_file_vars = false,
    body_encoding = nil,
    is_graphql    = false,
    graphql_variables = nil,
    name          = nil,
    meta          = { no_redirect = false, no_cookie_jar = false, note = nil },
    file_vars     = vim.deepcopy(inherited_vars),
    prompts       = {},
    line_start    = first_line,
    is_curl       = false,
    curl_raw      = nil,
  }

  local new_file_vars = {}
  local found_request = false
  local state = "PREAMBLE"  -- PREAMBLE | URL_CONT | HEADERS | BODY | CURL
  local body_lines = {}

  for line_offset, line in ipairs(lines) do
    local lineno = first_line + line_offset - 1

    if state == "PREAMBLE" then
      if is_blank(line) or is_comment(line) then
        -- skip

      elseif is_annotation(line) then
        local ann, val = parse_annotation(line)
        if not ann then goto continue end

        if ann == "name" then
          req.name = val
        elseif ann == "no-redirect" then
          req.meta.no_redirect = true
        elseif ann == "no-cookie-jar" then
          req.meta.no_cookie_jar = true
        elseif ann == "note" then
          req.meta.note = val
        elseif ann == "prompt" then
          if val then
            local var_name, desc = val:match("^(%S+)%s*(.*)")
            if var_name then
              table.insert(req.prompts, {
                name = var_name,
                description = (desc and desc ~= "") and desc or nil,
              })
            end
          end
        end

      elseif is_file_var(line) then
        local name, value = parse_file_var(line)
        if name then
          req.file_vars[name] = value
          new_file_vars[name] = value
        end

      elseif is_curl(line) then
        req.is_curl = true
        req.curl_raw = line
        req.line_start = lineno
        found_request = true
        state = "CURL"

      else
        local method, url, version = parse_request_line(line)
        if method then
          req.method = method
          req.url    = url
          req.http_version = version
          req.line_start   = lineno
          found_request    = true
          state = "URL_CONT"
        end
        -- unrecognised line in PREAMBLE → skip
      end

    elseif state == "URL_CONT" then
      if line:match("^%s*[?&]") then
        -- Multi-line query param — strip leading whitespace, append to URL
        req.url = req.url .. line:match("^%s*(.+)")

      elseif is_blank(line) then
        -- Blank line before any headers → jump straight to BODY
        state = "BODY"

      else
        local hname, hval = parse_header_line(line)
        if hname then
          req.headers[hname] = hval
          state = "HEADERS"
        else
          -- Not a header either — treat as body start (no blank-line separator)
          state = "BODY"
          table.insert(body_lines, line)
        end
      end

    elseif state == "HEADERS" then
      if is_blank(line) then
        state = "BODY"
      else
        local hname, hval = parse_header_line(line)
        if hname then
          req.headers[hname] = hval
        else
          -- Non-header in header section → body started without blank separator
          state = "BODY"
          table.insert(body_lines, line)
        end
      end

    elseif state == "BODY" then
      table.insert(body_lines, line)

    elseif state == "CURL" then
      -- Continuation lines for multi-line curl commands (ends with \)
      if req.curl_raw:match("\\%s*$") then
        req.curl_raw = req.curl_raw:gsub("\\%s*$", "") .. " " .. vim.trim(line)
      end
      -- If no trailing \, curl command is complete — ignore further lines
    end

    ::continue::
  end

  if not found_request then
    return nil, new_file_vars
  end

  -- ── Post-process body ──────────────────────────────────────────────────────

  -- Strip trailing blank lines from body
  while #body_lines > 0 and is_blank(body_lines[#body_lines]) do
    table.remove(body_lines)
  end

  if #body_lines > 0 then
    local first_body = body_lines[1]
    local is_vars, encoding, path = parse_body_file_ref(first_body)

    if is_vars ~= nil then
      -- File reference
      req.body_file      = path
      req.body_file_vars = is_vars
      req.body_encoding  = encoding
    else
      req.body = table.concat(body_lines, "\n")
    end
  end

  -- ── GraphQL detection ──────────────────────────────────────────────────────
  for hname, hval in pairs(req.headers) do
    if hname:lower() == "x-request-type" and hval:lower() == "graphql" then
      req.is_graphql = true

      -- Split body on first blank line: above = query, below = variables JSON
      if req.body then
        local query, vars = req.body:match("^(.-)\n\n(.+)$")
        if query then
          req.body              = query
          req.graphql_variables = vars
        end
      end
      break
    end
  end

  return req, new_file_vars
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Parse .http/.rest file content into a list of Request objects.
---
--- @param content string|table  Raw content as a string or table of lines.
--- @return table[]              List of Request objects (may be empty).
function M.parse(content)
  if type(content) == "table" then
    content = table.concat(content, "\n")
  end

  -- Split into lines (handle \r\n and \n)
  local lines = {}
  for line in (content:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end

  local blocks = split_blocks(lines)
  local requests = {}
  local global_vars = {}  -- accumulates across all blocks

  for _, block in ipairs(blocks) do
    local req, new_vars = M._parse_block(block.lines, block.first_line, global_vars)

    -- Merge new file vars into global scope for subsequent blocks
    for k, v in pairs(new_vars) do
      global_vars[k] = v
    end

    if req then
      table.insert(requests, req)
    end
  end

  return requests
end

return M
