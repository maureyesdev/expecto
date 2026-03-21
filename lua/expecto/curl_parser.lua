--- expecto.nvim — curl output parser
--- Parses the stdout of `curl --include -w "..."` into a Response object.
local M = {}

local TIMING_MARKER = require("expecto.curl_builder").TIMING_MARKER

-- ── Timing section parser ─────────────────────────────────────────────────────

--- Parse the timing block appended by curl's -w flag.
--- Returns a timing table and removes the timing block from the raw string.
local function split_timing(raw)
  local marker_pos = raw:find("\n\n" .. TIMING_MARKER, 1, true)
  if not marker_pos then
    -- Try with just \n (edge case in short responses)
    marker_pos = raw:find("\n" .. TIMING_MARKER, 1, true)
  end

  if not marker_pos then
    return raw, {}
  end

  local response_part = raw:sub(1, marker_pos - 1)
  local timing_part   = raw:sub(marker_pos)

  local timing = {}
  timing.total   = tonumber(timing_part:match("time_total:([%d%.]+)"))      or 0
  timing.dns     = tonumber(timing_part:match("time_namelookup:([%d%.]+)")) or 0
  timing.connect = tonumber(timing_part:match("time_connect:([%d%.]+)"))    or 0
  timing.ttfb    = tonumber(timing_part:match("time_starttransfer:([%d%.]+)")) or 0
  timing.size    = tonumber(timing_part:match("size_download:([%d%.]+)"))   or 0

  return response_part, timing
end

-- ── HTTP status block finder ──────────────────────────────────────────────────

--- When following redirects, curl outputs multiple HTTP/x.x blocks.
--- We want the LAST one (the final response).
--- Returns the offset (byte position) where the last status line begins.
local function find_last_status_block(text)
  local last_pos = 1
  local pos = 1

  while true do
    local s = text:find("^HTTP/", pos)
    if not s then
      -- Try finding mid-string (after a blank line separator from prior redirect)
      s = text:find("\r?\nHTTP/", pos)
      if not s then break end
      s = s + 1  -- skip the leading \n
    end
    last_pos = s
    pos = s + 1
  end

  return last_pos
end

-- ── Header section parser ─────────────────────────────────────────────────────

--- Parse the header section of a response block (everything before the first blank line).
--- Returns (status_line, headers_table, body_start_offset).
local function parse_header_section(text)
  -- Normalise line endings
  text = text:gsub("\r\n", "\n")

  local headers  = {}
  local lines    = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end

  if #lines == 0 then
    return nil, {}, 1
  end

  local status_line = lines[1]
  local body_start  = #text + 1  -- default: no body

  for i = 2, #lines do
    local line = lines[i]
    if line == "" then
      -- Blank line — everything after this is the body
      -- Calculate byte offset: sum of preceding line lengths + newlines
      local offset = 0
      for j = 1, i do
        offset = offset + #lines[j] + 1  -- +1 for the \n
      end
      body_start = offset
      break
    end

    local name, value = line:match("^([%w][%w%-%_]*):%s*(.*)$")
    if name then
      -- Lowercase header names for consistent lookup
      headers[name:lower()] = value
    end
  end

  return status_line, headers, body_start
end

-- ── Status line parser ────────────────────────────────────────────────────────

--- Parse "HTTP/1.1 200 OK" → { version, code, text }
local function parse_status_line(line)
  if not line then return nil, nil, nil end
  local version, code, text = line:match("^(HTTP/%S+)%s+(%d%d%d)%s*(.*)")
  return version, tonumber(code), text
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Parse the combined stdout of `curl --include -w WRITE_OUT`.
---
--- @param raw string  The full stdout string from curl.
--- @return table      Response object:
---   { status_code, status_text, http_version, headers, body,
---     content_type, timing, size, raw_headers }
function M.parse(raw)
  if not raw or raw == "" then
    return {
      status_code  = 0,
      status_text  = "No response",
      http_version = nil,
      headers      = {},
      body         = "",
      content_type = nil,
      timing       = {},
      size         = 0,
    }
  end

  -- 1. Split off timing block
  local response_raw, timing = split_timing(raw)

  -- 2. Find the last HTTP/x.x status block (handles redirects)
  response_raw = response_raw:gsub("\r\n", "\n")
  local last_block_pos = find_last_status_block(response_raw)
  local final_block = response_raw:sub(last_block_pos)

  -- 3. Find the blank line separating headers from body
  local blank_pos = final_block:find("\n\n")
  local header_section, body

  if blank_pos then
    header_section = final_block:sub(1, blank_pos - 1)
    body = final_block:sub(blank_pos + 2)  -- skip \n\n
  else
    header_section = final_block
    body = ""
  end

  -- 4. Parse status + headers
  local status_line, headers, _ = parse_header_section(header_section)
  local http_version, status_code, status_text = parse_status_line(status_line)

  -- 5. Content-Type (case-insensitive lookup already done by lowercase headers)
  local content_type = headers["content-type"]
  local mime = content_type and content_type:match("^([^;%s]+)") or nil

  -- 6. Strip trailing blank lines from body
  body = body:gsub("%s+$", "")

  return {
    status_code  = status_code  or 0,
    status_text  = status_text  or "",
    http_version = http_version or "HTTP/1.1",
    headers      = headers,
    body         = body,
    content_type = content_type,
    mime         = mime,
    timing       = timing,
    size         = timing.size or #body,
  }
end

--- Map a MIME type to a Neovim filetype string.
---@param mime string|nil
---@return string  filetype, e.g. "json", "xml", "html", "text"
function M.mime_to_ft(mime)
  if not mime then return "text" end
  if mime:match("json")       then return "json"       end
  if mime:match("xml")        then return "xml"        end
  if mime:match("html")       then return "html"       end
  if mime:match("javascript") then return "javascript" end
  if mime:match("css")        then return "css"        end
  if mime:match("markdown")   then return "markdown"   end
  if mime:match("yaml")       then return "yaml"       end
  return "text"
end

return M
