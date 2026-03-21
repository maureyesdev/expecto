--- expecto.nvim — response window manager
--- Opens/reuses a split buffer to display HTTP responses.
local M = {}

local config      = require("expecto.config")
local curl_parser = require("expecto.curl_parser")

local RESPONSE_BUF_NAME = "expecto://response"

-- ── Buffer / window helpers ───────────────────────────────────────────────────

--- Find an existing response buffer (by name) or return nil.
local function find_response_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("expecto://response$") then
        return buf
      end
    end
  end
  return nil
end

--- Find a window that is displaying `bufnr`, or nil.
local function find_win_for_buf(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

--- Create or reuse the response buffer. Returns bufnr.
local function get_or_create_buf()
  local buf = find_response_buf()
  if buf then return buf end

  buf = vim.api.nvim_create_buf(false, true)  -- unlisted, scratch
  vim.api.nvim_buf_set_name(buf, RESPONSE_BUF_NAME)

  -- Buffer-local settings
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].swapfile  = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "hide"

  -- Buffer-local keymaps
  local map_opts = { buffer = buf, silent = true, noremap = true }
  vim.keymap.set("n", "q", "<Cmd>close<CR>",   map_opts)
  vim.keymap.set("n", "Q", "<Cmd>bdelete<CR>", map_opts)

  return buf
end

--- Open a window showing `bufnr`, respecting the configured split direction.
--- Returns the window id.
local function open_win(bufnr)
  -- Reuse an existing window for this buffer if one is open
  local existing = find_win_for_buf(bufnr)
  if existing then
    vim.api.nvim_set_current_win(existing)
    return existing
  end

  local cfg  = config.get()
  local size = cfg.response_window_size

  if cfg.response_split == "horizontal" then
    vim.cmd("botright " .. size .. "split")
  else
    vim.cmd("botright " .. size .. "vsplit")
  end

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  return win
end

--- Write lines into the response buffer (makes it temporarily modifiable).
local function set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

-- ── Status line helpers ───────────────────────────────────────────────────────

--- Return a highlight group based on HTTP status code.
local function status_hl(code)
  if not code then return "Comment" end
  if code < 200 then return "Comment"   end
  if code < 300 then return "DiagnosticOk"    end
  if code < 400 then return "DiagnosticWarn"  end
  return "DiagnosticError"
end

--- Format the summary line: "200 OK  │  342ms  │  1.2 KB"
local function make_summary(response)
  local code  = response.status_code  or 0
  local text  = response.status_text  or ""
  local total = (response.timing and response.timing.total_fmt) or "?ms"
  local size  = (response.timing and response.timing.size_fmt)  or "?"
  return ("%d %s  │  %s  │  %s"):format(code, text, total, size)
end

-- ── JSON pretty-printer ───────────────────────────────────────────────────────

--- Try to pretty-print JSON using jq. Falls back to raw string on failure.
local function pretty_json(raw_body)
  if vim.fn.executable("jq") ~= 1 then return raw_body end
  -- Write to a temp file to avoid shell-quoting issues with large bodies
  local tmp = os.tmpname()
  local f = io.open(tmp, "w")
  if not f then return raw_body end
  f:write(raw_body)
  f:close()

  local result = vim.fn.system("jq . " .. vim.fn.shellescape(tmp))
  os.remove(tmp)

  if vim.v.shell_error ~= 0 then return raw_body end
  return result:gsub("%s+$", "")
end

-- ── Loading state ─────────────────────────────────────────────────────────────

--- Show a "Sending request…" placeholder in the response window.
function M.show_loading(req)
  local buf = get_or_create_buf()
  open_win(buf)

  local url = (req and req.url) or "..."
  local method = (req and req.method) or "GET"

  set_lines(buf, {
    ("▶  %s  %s"):format(method, url),
    string.rep("─", 60),
    "",
    "  Sending request…",
    "",
  })

  vim.bo[buf].filetype = "http"
end

-- ── Main render ───────────────────────────────────────────────────────────────

--- Render a Response object in the response window.
---
--- @param response table   Parsed response from curl_parser.parse()
--- @param req table        The original resolved request (for the summary header)
function M.show(response, req)
  local buf = get_or_create_buf()
  local win = open_win(buf)

  local cfg = config.get()

  -- ── Build lines ────────────────────────────────────────────────────────────
  local lines = {}

  -- Request summary line
  local method = (req and req.method) or "?"
  local url    = (req and req.url)    or "?"
  table.insert(lines, ("▶  %s  %s"):format(method, url))
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, "")

  -- Status + timing
  table.insert(lines, "  " .. make_summary(response))
  table.insert(lines, "")
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, "")

  -- Response headers
  local sorted_headers = {}
  for name, value in pairs(response.headers or {}) do
    table.insert(sorted_headers, { name = name, value = value })
  end
  table.sort(sorted_headers, function(a, b) return a.name < b.name end)

  for _, h in ipairs(sorted_headers) do
    table.insert(lines, h.name .. ": " .. h.value)
  end

  table.insert(lines, "")
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, "")

  -- Body
  local body = response.body or ""
  local ft   = curl_parser.mime_to_ft(response.mime)

  if body ~= "" and cfg.format_response_body and ft == "json" then
    body = pretty_json(body)
  end

  if body ~= "" then
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, line)
    end
  else
    table.insert(lines, "  (empty body)")
  end

  -- Write everything
  set_lines(buf, lines)

  -- Set filetype for body highlighting (json/xml/html/etc)
  -- We use http for the whole buffer (covers headers); for rich body
  -- highlighting in a future phase we'll use embedded highlighting.
  vim.bo[buf].filetype = "http"

  -- Apply status-code highlight via extmark on the summary line (line 4, 0-indexed 3)
  local ns = vim.api.nvim_create_namespace("expecto_response")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, status_hl(response.status_code), 3, 0, -1)

  -- Move cursor to the top of the response window
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

--- Show an error message in the response window.
---@param msg string
---@param req table|nil
function M.show_error(msg, req)
  local buf = get_or_create_buf()
  open_win(buf)

  local lines = {
    "▶  " .. ((req and req.method) or "?") .. "  " .. ((req and req.url) or ""),
    string.rep("─", 60),
    "",
    "  ✗  Request failed",
    "",
    string.rep("─", 60),
    "",
  }
  for line in (msg .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, "  " .. line)
  end

  set_lines(buf, lines)
  vim.bo[buf].filetype = "http"

  local ns = vim.api.nvim_create_namespace("expecto_response")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticError", 3, 0, -1)
end

return M
