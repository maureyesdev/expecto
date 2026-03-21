--- expecto.nvim — named request response storage
--- Stores the last response for each named request so subsequent requests
--- can reference it with {{reqName.response.headers.X}} etc.
local M = {}

-- ── State ─────────────────────────────────────────────────────────────────────

--- name → Response object (as returned by curl_parser)
local _store = {}

-- ── Public API ────────────────────────────────────────────────────────────────

--- Store the response for a named request.
---@param name string  The request name (from # @name annotation)
---@param response table  Response object from curl_parser
function M.store(name, response)
  _store[name] = response
end

--- Return a shallow copy of the response storage table.
--- Keys are request names; values are Response objects.
---@return table
function M.get_all()
  local copy = {}
  for k, v in pairs(_store) do
    copy[k] = v
  end
  return copy
end

--- Clear all stored responses.
function M.reset()
  _store = {}
end

return M
