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

  local variables   = require("expecto.variables")
  local environment = require("expecto.environment")
  local executor    = require("expecto.executor")
  local response    = require("expecto.response")

  -- Resolve variables (file vars + env vars + request chain vars + system vars)
  local env_vars  = environment.get_vars()
  local req_vars  = require("expecto.request_vars").get_all()
  local resolved  = variables.resolve_request(req, env_vars, req_vars)

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
      -- Store named request response for chaining (Phase 5)
      if original_req.name then
        require("expecto.request_vars").store(original_req.name, resp)
      end
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

--- Interactively pick and switch to an environment.
function M.switch_env()
  local env = require("expecto.environment")
  local names = env.list_names()

  if #names == 0 then
    vim.notify(
      "expecto: no environments loaded (create .expecto.json in project root)",
      vim.log.levels.WARN
    )
    return
  end

  local current = env.current_name()
  -- Put current env first in the list for visibility
  table.sort(names, function(a, b)
    if a == current then return true end
    if b == current then return false end
    return a < b
  end)

  vim.ui.select(names, {
    prompt = "expecto — switch environment:",
    format_item = function(name)
      return (name == current) and (name .. "  ← active") or name
    end,
  }, function(choice)
    if choice then env.switch(choice) end
  end)
end

--- Reload the environment file from disk.
function M.reload_env()
  local ok, err = require("expecto.environment").reload()
  if ok then
    vim.notify("expecto: environments reloaded", vim.log.levels.INFO)
  else
    vim.notify("expecto: " .. (err or "reload failed"), vim.log.levels.ERROR)
  end
end

--- Show the curl command for the request under cursor (debugging).
function M.show_curl_command()
  local req = request_at_cursor()
  if not req then
    vim.notify("expecto: no request at cursor", vim.log.levels.WARN)
    return
  end

  local variables   = require("expecto.variables")
  local environment = require("expecto.environment")
  local executor    = require("expecto.executor")

  local env_vars = environment.get_vars()
  local resolved = variables.resolve_request(req, env_vars)
  local cmd = executor.preview_command(resolved)
  local cmd_str = table.concat(cmd, " ")

  -- Show in a floating window / echo area
  vim.notify(cmd_str, vim.log.levels.INFO, { title = "expecto: curl command" })
end

return M
