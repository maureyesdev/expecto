--- expecto.nvim — code lens (virtual text hints above each request)
--- Shows "▶ Run · ⌨  <leader>hr" above each HTTP request line.
local M = {}

local NS = vim.api.nvim_create_namespace("expecto_codelens")

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Format a code lens label for a request.
---@param req table  Request object from parser
---@return string
local function label(req)
  local name = req.name and ("[" .. req.name .. "] ") or ""
  return name .. "▶ Run · ✕ Cancel"
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Refresh code lens virtual text in a buffer.
---@param bufnr number  Buffer to update (0 = current)
function M.update(bufnr)
  if not require("expecto.config").get().show_codelens then return end

  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  -- Only act on http buffers
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  if ft ~= "http" then return end

  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)

  local parser = require("expecto.parser")
  local lines  = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local requests = parser.parse(lines)

  for _, req in ipairs(requests) do
    local lnum = req.line_start - 1  -- convert to 0-based
    if lnum >= 0 then
      vim.api.nvim_buf_set_extmark(bufnr, NS, lnum, 0, {
        virt_lines = {
          { { label(req), "Comment" } },
        },
        virt_lines_above = true,
      })
    end
  end
end

--- Clear all code lens extmarks from a buffer.
---@param bufnr number
function M.clear(bufnr)
  bufnr = bufnr or 0
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  end
end

return M
