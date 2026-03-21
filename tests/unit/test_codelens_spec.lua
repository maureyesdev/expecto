local codelens = require("expecto.codelens")
local config   = require("expecto.config")

-- Same name as in codelens.lua — nvim_create_namespace is idempotent.
local NS = vim.api.nvim_create_namespace("expecto_codelens")

--- Create a scratch buffer with the given lines and filetype=http.
local function make_http_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", "http", { buf = bufnr })
  return bufnr
end

-- ── update() ─────────────────────────────────────────────────────────────────

describe("expecto.codelens — update()", function()
  before_each(function()
    config.setup({ show_codelens = true })
  end)

  it("adds an extmark above the request line", function()
    local bufnr = make_http_buf({ "GET https://api.example.com/users" })
    codelens.update(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
    assert.truthy(#marks >= 1)
  end)

  it("adds one extmark per request", function()
    local bufnr = make_http_buf({
      "GET https://api.example.com/users",
      "",
      "###",
      "",
      "POST https://api.example.com/users",
      "Content-Type: application/json",
      "",
      '{"name":"Alice"}',
    })
    codelens.update(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
    assert.equals(2, #marks)
  end)

  it("clears previous marks before re-applying", function()
    local bufnr = make_http_buf({ "GET https://api.example.com/users" })
    codelens.update(bufnr)
    codelens.update(bufnr)  -- call twice
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
    assert.equals(1, #marks)  -- should not double-up
  end)

  it("does nothing when show_codelens is false", function()
    config.setup({ show_codelens = false })
    local bufnr = make_http_buf({ "GET https://api.example.com/users" })
    codelens.update(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
    assert.equals(0, #marks)
  end)

  it("does nothing for a non-http buffer", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "GET https://api.example.com/users" })
    vim.api.nvim_set_option_value("filetype", "text", { buf = bufnr })
    codelens.update(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
    assert.equals(0, #marks)
  end)

  it("handles an empty buffer gracefully", function()
    local bufnr = make_http_buf({})
    assert.has_no.errors(function() codelens.update(bufnr) end)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
    assert.equals(0, #marks)
  end)

  it("handles a buffer with only comments and vars (no requests)", function()
    local bufnr = make_http_buf({
      "# Just a comment",
      "@host = example.com",
    })
    codelens.update(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
    assert.equals(0, #marks)
  end)
end)

-- ── clear() ───────────────────────────────────────────────────────────────────

describe("expecto.codelens — clear()", function()
  before_each(function()
    config.setup({ show_codelens = true })
  end)

  it("removes all codelens extmarks", function()
    local bufnr = make_http_buf({ "GET https://api.example.com/users" })
    codelens.update(bufnr)
    codelens.clear(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
    assert.equals(0, #marks)
  end)

  it("is safe to call on a buffer with no marks", function()
    local bufnr = make_http_buf({})
    assert.has_no.errors(function() codelens.clear(bufnr) end)
  end)
end)
