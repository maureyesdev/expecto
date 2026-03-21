--- expecto.nvim — request/response history
--- Keeps the last N request+response pairs in memory (session only).
local M = {}

-- ── State ─────────────────────────────────────────────────────────────────────

local _entries = {}   -- newest first: { req, response, timestamp }

-- ── Public API ────────────────────────────────────────────────────────────────

--- Push a completed request+response onto the history stack.
--- Automatically trims to the configured history_size limit.
---@param req table      Resolved request object
---@param response table Response object from curl_parser
function M.push(req, response)
  local cfg = require("expecto.config").get()
  local max = (cfg.history_size and cfg.history_size > 0) and cfg.history_size or 50

  table.insert(_entries, 1, {
    req       = req,
    response  = response,
    timestamp = os.time(),
  })

  -- Trim to max
  while #_entries > max do
    table.remove(_entries)
  end
end

--- Return a copy of all history entries (newest first).
---@return table[]
function M.get_all()
  local copy = {}
  for i, e in ipairs(_entries) do
    copy[i] = e
  end
  return copy
end

--- Return the number of entries currently stored.
---@return number
function M.count()
  return #_entries
end

--- Clear all history entries.
function M.clear()
  _entries = {}
end

return M
