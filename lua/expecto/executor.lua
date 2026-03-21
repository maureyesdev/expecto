--- expecto.nvim — async HTTP executor
--- Runs curl via vim.fn.jobstart and calls back with a parsed Response.
local M = {}

local curl_builder = require("expecto.curl_builder")
local curl_parser  = require("expecto.curl_parser")

-- Track the running job so we can cancel it
local _current_job = nil

-- ── Internal ──────────────────────────────────────────────────────────────────

--- Format bytes into a human-readable string.
local function fmt_size(bytes)
  bytes = tonumber(bytes) or 0
  if bytes < 1024     then return bytes .. " B"  end
  if bytes < 1048576  then return ("%.1f KB"):format(bytes / 1024)      end
  return                        ("%.1f MB"):format(bytes / 1048576)
end

--- Format seconds into a human-readable string.
local function fmt_time(secs)
  secs = tonumber(secs) or 0
  if secs < 1 then return math.floor(secs * 1000) .. "ms" end
  return ("%.2fs"):format(secs)
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Run an HTTP request asynchronously.
---
--- @param req table      Resolved Request object (from variables.resolve_request)
--- @param opts table     { on_start, on_done, on_error }
---   on_start()                       called when curl is launched
---   on_done(response, req)           called with parsed Response
---   on_error(msg)                    called on job failure
function M.run(req, opts)
  opts = opts or {}

  -- Cancel any in-flight request first
  if _current_job then
    vim.fn.jobstop(_current_job)
    _current_job = nil
  end

  local args = curl_builder.build(req)
  local stdout_chunks = {}
  local stderr_chunks = {}

  if opts.on_start then opts.on_start() end

  local job_id = vim.fn.jobstart(args, {
    on_stdout = function(_, data, _)
      for _, chunk in ipairs(data) do
        table.insert(stdout_chunks, chunk)
      end
    end,

    on_stderr = function(_, data, _)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          table.insert(stderr_chunks, chunk)
        end
      end
    end,

    on_exit = function(_, code, _)
      _current_job = nil

      if code ~= 0 then
        local err = table.concat(stderr_chunks, "\n")
        if err == "" then
          err = ("curl exited with code %d"):format(code)
        end
        if opts.on_error then
          vim.schedule(function() opts.on_error(err) end)
        end
        return
      end

      local raw = table.concat(stdout_chunks, "\n")
      local response = curl_parser.parse(raw)

      -- Attach human-readable timing strings
      response.timing.total_fmt   = fmt_time(response.timing.total)
      response.timing.size_fmt    = fmt_size(response.size)

      if opts.on_done then
        vim.schedule(function() opts.on_done(response, req) end)
      end
    end,
  })

  if job_id <= 0 then
    local msg = "expecto: failed to start curl (job_id=" .. job_id .. ")"
    vim.notify(msg, vim.log.levels.ERROR)
    return
  end

  _current_job = job_id
end

--- Cancel the currently running request (if any).
function M.cancel()
  if _current_job then
    vim.fn.jobstop(_current_job)
    _current_job = nil
    vim.notify("expecto: request cancelled", vim.log.levels.INFO)
  else
    vim.notify("expecto: no request in flight", vim.log.levels.WARN)
  end
end

--- Returns true if a request is currently in flight.
function M.is_running()
  return _current_job ~= nil
end

--- Return the curl command that WOULD be run (for debugging / cURL export).
---@param req table  Resolved request
---@return string[]  argv list
function M.preview_command(req)
  return curl_builder.build(req)
end

return M
