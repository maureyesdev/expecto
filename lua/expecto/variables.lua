--- expecto.nvim — variable resolution
--- Resolves {{varName}}, {{$systemVar}}, and {{%varName}} references.
--- Phase 3: file vars + core system vars.
--- Phase 4 will add env vars, dotenv, and prompt vars.
local M = {}

local MAX_PASSES = 10  -- prevent infinite loops in circular var references

-- ── UUID fallback (when uuidgen is unavailable) ───────────────────────────────

local function lua_uuid()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format("%x", v)
  end)
end

local function generate_guid()
  if vim.fn.executable("uuidgen") == 1 then
    return vim.trim(vim.fn.system("uuidgen"):lower())
  end
  return lua_uuid()
end

-- ── Offset parsing for $timestamp / $datetime ────────────────────────────────

local UNIT_SECS = {
  ms = 0.001, s = 1, m = 60, h = 3600,
  d = 86400, w = 604800, M = 2592000, y = 31536000,
}

--- Parse an offset string like "-3 h" or "2 d" into seconds.
--- Returns 0 if no offset given.
local function parse_offset(args_str)
  if not args_str or args_str == "" then return 0 end
  local sign, amount, unit = args_str:match("^%s*([+-]?)(%d+)%s*(%a+)")
  if not amount then return 0 end
  local mult = UNIT_SECS[unit] or 0
  local secs = tonumber(amount) * mult
  return (sign == "-") and -secs or secs
end

-- ── Date format helpers ───────────────────────────────────────────────────────

local function to_strftime(fmt)
  if fmt == "rfc1123" then return "%a, %d %b %Y %H:%M:%S GMT" end
  if fmt == "iso8601" then return "%Y-%m-%dT%H:%M:%SZ" end
  -- Custom format: convert moment.js-ish tokens to strftime
  return fmt
    :gsub("YYYY", "%%Y"):gsub("YY", "%%y")
    :gsub("MM", "%%m"):gsub("DD", "%%d")
    :gsub("HH", "%%H"):gsub("mm", "%%M"):gsub("ss", "%%S")
end

-- ── System variable resolver ──────────────────────────────────────────────────

--- Resolve a {{$...}} system variable reference.
--- `ref` is the full string inside {{ }}, e.g. "$guid" or "$randomInt 1 100".
local function resolve_system_var(ref)
  -- Strip leading $
  local body = ref:sub(2)
  local name, args = body:match("^(%S+)%s*(.*)")
  name = name or body
  args = args or ""

  if name == "guid" then
    return generate_guid()
  end

  if name == "randomInt" then
    local lo, hi = args:match("^(%d+)%s+(%d+)")
    lo, hi = tonumber(lo) or 0, tonumber(hi) or 100
    return tostring(math.random(lo, hi - 1))
  end

  if name == "timestamp" then
    local offset = parse_offset(args)
    return tostring(math.floor(os.time() + offset))
  end

  if name == "datetime" then
    local fmt, rest = args:match("^([^%s]+)%s*(.*)")
    fmt = fmt or "iso8601"
    local offset = parse_offset(rest)
    local t = os.time() + offset
    return os.date("!" .. to_strftime(fmt), t)
  end

  if name == "localDatetime" then
    local fmt, rest = args:match("^([^%s]+)%s*(.*)")
    fmt = fmt or "iso8601"
    local offset = parse_offset(rest)
    local t = os.time() + offset
    return os.date(to_strftime(fmt), t)
  end

  if name == "processEnv" then
    local var = vim.trim(args)
    return os.getenv(var) or ("{{" .. ref .. "}}")
  end

  if name == "dotenv" then
    -- Deferred to Phase 4 (requires file reading at execution time)
    return ("{{" .. ref .. "}}")
  end

  return nil  -- unknown system var — leave unresolved
end

-- ── Core resolver ─────────────────────────────────────────────────────────────

--- Resolve all variable references in `text`.
---
--- Resolution order (highest precedence first):
---   1. System variables  {{$name [args]}}
---   2. Request chaining  {{reqName.response...}}  (Phase 5)
---   3. File variables    {{varName}}
---   4. Env variables     {{varName}}  (Phase 4)
---
--- @param text string
--- @param context table  { file_vars=table, env_vars=table, request_vars=table }
--- @return string
function M.resolve(text, context)
  if not text or text == "" then return text end
  context = context or {}
  local file_vars    = context.file_vars    or {}
  local env_vars     = context.env_vars     or {}
  local request_vars = context.request_vars or {}

  math.randomseed(os.time())

  for _ = 1, MAX_PASSES do
    local prev = text

    text = text:gsub("({{([^{}]+)}})", function(whole, inner)
      inner = vim.trim(inner)

      -- System variable
      if inner:sub(1, 1) == "$" then
        local resolved = resolve_system_var(inner)
        return resolved or whole
      end

      -- Percent-encoded variable  {{%varName}}
      if inner:sub(1, 1) == "%" then
        local var_name = inner:sub(2)
        local val = file_vars[var_name] or env_vars[var_name]
        if val then
          return vim.uri_encode and vim.uri_encode(val) or val
        end
        return whole
      end

      -- Request chaining variable  {{reqName.response.*}}  (Phase 5)
      if inner:match("%.response%.") then
        local resolved = request_vars[inner]
        return resolved or whole
      end

      -- Plain variable — file vars take precedence over env vars
      local val = file_vars[inner] or env_vars[inner]
      return val or whole
    end)

    if text == prev then break end
  end

  return text
end

--- Resolve all variable references inside a Request object.
--- Returns a new (shallow-copied) request table with resolved values.
---
--- @param req table  Request object from parser
--- @param env_vars table|nil  Environment variables (Phase 4)
--- @param request_vars table|nil  Named request response vars (Phase 5)
--- @return table  Resolved request (new table, original is not mutated)
function M.resolve_request(req, env_vars, request_vars)
  local ctx = {
    file_vars    = req.file_vars or {},
    env_vars     = env_vars      or {},
    request_vars = request_vars  or {},
  }

  local resolved = vim.deepcopy(req)

  -- Resolve URL
  resolved.url = M.resolve(req.url, ctx)

  -- Resolve header values (not names)
  resolved.headers = {}
  for name, value in pairs(req.headers or {}) do
    resolved.headers[name] = M.resolve(value, ctx)
  end

  -- Resolve body
  if req.body then
    resolved.body = M.resolve(req.body, ctx)
  end

  return resolved
end

return M
