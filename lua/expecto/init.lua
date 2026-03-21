local M = {}

local _setup_done = false

---Setup expecto with user configuration.
---@param opts table|nil
function M.setup(opts)
  if _setup_done then
    return
  end
  _setup_done = true

  require("expecto.config").setup(opts)
end

return M
