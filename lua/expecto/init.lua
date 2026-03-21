--- expecto.nvim — public API
local M = {}

local _setup_done = false

-- ── Setup ─────────────────────────────────────────────────────────────────────

---@param opts table|nil
function M.setup(opts)
  if _setup_done then return end
  _setup_done = true
  require("expecto.config").setup(opts)
end

-- ── Core actions ──────────────────────────────────────────────────────────────

--- Find the request block the cursor is in.
--- Returns the Request object or nil.
local function request_at_cursor()
  local parser  = require("expecto.parser")
  local lines   = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor  = vim.api.nvim_win_get_cursor(0)[1]  -- 1-based
  local requests = parser.parse(lines)

  if #requests == 0 then return nil end

  -- Walk backwards: find the last request whose line_start <= cursor
  local target = nil
  for i = #requests, 1, -1 do
    if requests[i].line_start <= cursor then
      target = requests[i]
      break
    end
  end

  -- Fallback: cursor is before the first request line — use first request
  if not target then target = requests[1] end

  return target
end

--- Send the HTTP request under the cursor.
function M.run()
  local ft = vim.bo.filetype
  if ft ~= "http" then
    vim.notify("expecto: not an .http/.rest file", vim.log.levels.WARN)
    return
  end

  local req = request_at_cursor()
  if not req then
    vim.notify("expecto: no request found at cursor", vim.log.levels.WARN)
    return
  end

  local variables = require("expecto.variables")
  local executor  = require("expecto.executor")
  local response  = require("expecto.response")

  -- Resolve variables (file vars + system vars)
  local resolved = variables.resolve_request(req)

  -- Validate URL before sending
  if not resolved.url or resolved.url == "" then
    vim.notify("expecto: request has no URL", vim.log.levels.ERROR)
    return
  end

  -- Show loading indicator
  response.show_loading(resolved)

  -- Fire the request
  executor.run(resolved, {
    on_done = function(resp, original_req)
      response.show(resp, original_req)
    end,
    on_error = function(msg)
      response.show_error(msg, resolved)
    end,
  })
end

--- Cancel the currently in-flight request.
function M.cancel()
  require("expecto.executor").cancel()
end

--- Show the curl command for the request under cursor (debugging).
function M.show_curl_command()
  local req = request_at_cursor()
  if not req then
    vim.notify("expecto: no request at cursor", vim.log.levels.WARN)
    return
  end

  local variables = require("expecto.variables")
  local executor  = require("expecto.executor")

  local resolved = variables.resolve_request(req)
  local cmd = executor.preview_command(resolved)
  local cmd_str = table.concat(cmd, " ")

  -- Show in a floating window / echo area
  vim.notify(cmd_str, vim.log.levels.INFO, { title = "expecto: curl command" })
end

return M
