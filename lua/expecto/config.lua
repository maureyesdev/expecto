local M = {}

---@class ExpectoConfig
---@field response_split "vertical"|"horizontal" Direction to open the response window
---@field follow_redirects boolean Follow 3xx redirects automatically
---@field timeout number Request timeout in seconds
---@field env_file string Filename to look for environment definitions (relative to cwd)
---@field global_env_file string Absolute path for global environments file
---@field history_size number Maximum number of history entries to keep
---@field show_codelens boolean Show "▶ Send Request" virtual text above each request block
---@field response_window_size number Width (vertical) or height (horizontal) of the response window
---@field format_response_body boolean Auto-format JSON/XML response bodies (requires jq for JSON)
---@field default_headers table<string, string> Headers added to every request
---@field certificates table<string, table> Per-host SSL certificate configuration
---@field cookie_jar string|false Path to the cookie jar file; false disables cookie persistence

local defaults = {
  response_split = "vertical",
  follow_redirects = true,
  timeout = 30,
  env_file = ".expecto.json",
  global_env_file = vim.fn.expand("~/.config/expecto/envs.json"),
  history_size = 50,
  show_codelens = true,
  response_window_size = 60,
  format_response_body = true,
  default_headers = {},
  certificates = {},
  cookie_jar = vim.fn.stdpath("cache") .. "/expecto/cookies.txt",
}

---@type ExpectoConfig
local current = vim.deepcopy(defaults)

---Configure expecto with user options (merged into defaults).
---@param opts ExpectoConfig|nil
function M.setup(opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---Return the current configuration.
---@return ExpectoConfig
function M.get()
  return current
end

---Return the raw defaults (for testing).
---@return ExpectoConfig
function M.defaults()
  return vim.deepcopy(defaults)
end

return M
