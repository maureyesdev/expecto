--- expecto.nvim — response window manager
--- Opens/reuses a split buffer to display HTTP responses.
local M = {}

local config      = require("expecto.config")
local curl_parser = require("expecto.curl_parser")

local RESPONSE_BUF_NAME = "expecto://response"

-- ── Buffer / window helpers ────────────────────────────────────────────────────

local function find_response_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      if vim.api.nvim_buf_get_name(buf):match("expecto://response$") then
        return buf
      end
    end
  end
  return nil
end

local function find_win_for_buf(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

local function get_or_create_buf()
  local buf = find_response_buf()
  if buf then return buf end

  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, RESPONSE_BUF_NAME)
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].swapfile   = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden  = "hide"

  local map_opts = { buffer = buf, silent = true, noremap = true }
  vim.keymap.set("n", "q", "<Cmd>close<CR>",   map_opts)
  vim.keymap.set("n", "Q", "<Cmd>bdelete<CR>", map_opts)

  return buf
end

local function open_win(bufnr)
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

local function set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

-- ── Helpers ────────────────────────────────────────────────────────────────────

local function status_hl(code)
  if not code then return "Comment" end
  if code < 200 then return "Comment"        end
  if code < 300 then return "DiagnosticOk"   end
  if code < 400 then return "DiagnosticWarn" end
  return "DiagnosticError"
end

local function timing_text(response)
  if not response.timing then return nil end
  local total = response.timing.total_fmt
  local size  = response.timing.size_fmt
  if not total and not size then return nil end
  return (total or "") .. "  " .. (size or "")
end

-- ── JSON pretty-printer ────────────────────────────────────────────────────────

local function pretty_json(raw_body)
  if vim.fn.executable("jq") ~= 1 then return raw_body end
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

-- ── Loading state ──────────────────────────────────────────────────────────────

function M.show_loading(req)
  local buf = get_or_create_buf()
  open_win(buf)

  local method = (req and req.method) or "GET"
  local url    = (req and req.url)    or "..."
  set_lines(buf, { "# Sending " .. method .. " " .. url .. " …" })
  vim.bo[buf].filetype = "http"
end

-- ── Main render ────────────────────────────────────────────────────────────────

function M.show(response, req)
  local buf = get_or_create_buf()
  local win = open_win(buf)
  local cfg = config.get()
  local lines = {}

  -- Status line: HTTP/1.1 200 OK
  local version = response.http_version or "HTTP/1.1"
  local code    = response.status_code  or 0
  local text    = response.status_text  or ""
  table.insert(lines, ("%s %d %s"):format(version, code, text))

  -- Headers (original casing, original order)
  for _, h in ipairs(response.raw_headers or {}) do
    table.insert(lines, h.name .. ": " .. h.value)
  end

  -- Blank line separating headers from body
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
  end

  set_lines(buf, lines)

  -- Set filetype to the body language so TreeSitter highlights the body.
  -- For text/plain or no body, fall back to http so headers stay highlighted.
  vim.bo[buf].filetype = (ft ~= "text") and ft or "http"

  -- Extmarks
  local ns = vim.api.nvim_create_namespace("expecto_response")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- Colour status line by code family
  vim.api.nvim_buf_add_highlight(buf, ns, status_hl(code), 0, 0, -1)

  -- Timing as virtual text at end of status line
  local tt = timing_text(response)
  if tt then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_text     = { { "  " .. tt, "Comment" } },
      virt_text_pos = "eol",
    })
  end

  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

-- ── Error ──────────────────────────────────────────────────────────────────────

function M.show_error(msg, req)
  local buf = get_or_create_buf()
  open_win(buf)

  local method = (req and req.method) or "?"
  local url    = (req and req.url)    or ""
  local lines  = { "# Error: " .. method .. " " .. url, "" }

  for line in (msg .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end

  set_lines(buf, lines)
  vim.bo[buf].filetype = "http"

  local ns = vim.api.nvim_create_namespace("expecto_response")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticError", 0, 0, -1)
end

return M
