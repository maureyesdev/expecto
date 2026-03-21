--- expecto.nvim — curl command builder
--- Converts a resolved Request object into a curl argv list.
local M = {}

local config = require("expecto.config")

-- ── Timing write-out marker ───────────────────────────────────────────────────
-- Must not appear in normal HTTP response bodies.
M.TIMING_MARKER = "--expecto-timing--"

local WRITE_OUT = table.concat({
  "\n\n", M.TIMING_MARKER, "\n",
  "time_total:%{time_total}\n",
  "time_namelookup:%{time_namelookup}\n",
  "time_connect:%{time_connect}\n",
  "time_starttransfer:%{time_starttransfer}\n",
  "size_download:%{size_download}\n",
  "http_code:%{response_code}\n",
}, "")

-- ── Auth scheme handling ──────────────────────────────────────────────────────

--- Detect and handle special Authorization header schemes.
--- Returns extra curl flags (list) and whether to suppress the original header.
local function handle_auth(header_value, args)
  -- Basic with space-separated credentials: "Basic user passwd"
  local basic_user, basic_pass = header_value:match("^Basic%s+([^%s:]+)%s+([^%s]+)%s*$")
  if basic_user then
    vim.list_extend(args, { "-u", basic_user .. ":" .. basic_pass })
    return true  -- suppress the original Authorization header
  end

  -- Digest: "Digest user passwd"
  local digest_user, digest_pass = header_value:match("^Digest%s+([^%s:]+)%s+([^%s]+)%s*$")
  if digest_user then
    vim.list_extend(args, { "--digest", "-u", digest_user .. ":" .. digest_pass })
    return true
  end

  -- AWS SigV4: "AWS keyId keySecret [token:T] [region:R] [service:S]"
  local key_id, key_secret, rest = header_value:match("^AWS%s+(%S+)%s+(%S+)%s*(.*)")
  if key_id then
    local region  = (rest:match("region:(%S+)")  or "us-east-1"):gsub(",", "")
    local service = (rest:match("service:(%S+)") or "execute-api"):gsub(",", "")
    local token   = rest:match("token:(%S+)")

    vim.list_extend(args, {
      "--aws-sigv4", ("aws:amz:%s:%s"):format(region, service),
      "--user", key_id .. ":" .. key_secret,
    })
    if token then
      vim.list_extend(args, { "-H", "x-amz-security-token: " .. token })
    end
    return true
  end

  return false  -- not a special scheme — pass header as-is
end

-- ── Main builder ──────────────────────────────────────────────────────────────

--- Build a curl argv list from a resolved Request object.
---
--- @param req table    Resolved Request (URLs and headers already have vars resolved)
--- @param opts table|nil  Overrides: { timeout, follow_redirects, cookie_jar }
--- @return string[]   argv list suitable for vim.fn.jobstart()
function M.build(req, opts)
  local cfg  = config.get()
  opts = opts or {}

  local timeout         = opts.timeout         or cfg.timeout
  local follow_redirects = opts.follow_redirects
  if follow_redirects == nil then
    follow_redirects = (not req.meta.no_redirect) and cfg.follow_redirects
  end
  local cookie_jar = opts.cookie_jar

  local args = {
    "curl",
    "--silent",           -- suppress progress meter
    "--show-error",       -- but do show errors
    "--include",          -- include response headers in output
    "-w", WRITE_OUT,
    "--max-time", tostring(timeout),
  }

  -- Follow redirects
  if follow_redirects then
    table.insert(args, "-L")
  end

  -- Cookie jar
  if cookie_jar and not req.meta.no_cookie_jar then
    vim.list_extend(args, { "-b", cookie_jar, "-c", cookie_jar })
  end

  -- HTTP method (omit for GET since it's curl's default)
  if req.method ~= "GET" then
    vim.list_extend(args, { "-X", req.method })
  end

  -- Headers
  for name, value in pairs(req.headers or {}) do
    if name:lower() == "authorization" then
      local suppressed = handle_auth(value, args)
      if not suppressed then
        vim.list_extend(args, { "-H", name .. ": " .. value })
      end
    else
      vim.list_extend(args, { "-H", name .. ": " .. value })
    end
  end

  -- Default headers from config (only if not already set)
  local lower_headers = {}
  for name in pairs(req.headers or {}) do
    lower_headers[name:lower()] = true
  end
  for name, value in pairs(cfg.default_headers or {}) do
    if not lower_headers[name:lower()] then
      vim.list_extend(args, { "-H", name .. ": " .. value })
    end
  end

  -- Request body
  if req.body_file then
    if req.body_file_vars then
      -- Body file with variable processing — would need to write a temp file
      -- For Phase 3: read the file and pass content directly
      vim.list_extend(args, { "--data-binary", "@" .. req.body_file })
    else
      vim.list_extend(args, { "--data-binary", "@" .. req.body_file })
    end
  elseif req.body and req.body ~= "" then
    -- Inline body
    -- HEAD requests have no body by convention
    if req.method ~= "HEAD" then
      vim.list_extend(args, { "--data-binary", req.body })
    end
  end

  -- URL (last positional arg)
  table.insert(args, req.url)

  return args
end

return M
