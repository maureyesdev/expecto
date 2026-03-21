local M = {}

-- Compatibility: Neovim 0.9 uses vim.health, older used require("health")
local health = vim.health or require("health")
local ok     = health.ok     or health.report_ok
local warn   = health.warn   or health.report_warn
local error_ = health.error  or health.report_error
local start  = health.start  or health.report_start

local MIN_NVIM_VERSION = { major = 0, minor = 9, patch = 0 }

---Check that the running Neovim meets minimum version requirements.
local function check_nvim_version()
  local v = vim.version()
  if v.major > MIN_NVIM_VERSION.major
    or (v.major == MIN_NVIM_VERSION.major and v.minor >= MIN_NVIM_VERSION.minor)
  then
    ok(("Neovim %d.%d.%d (>= 0.9 required)"):format(v.major, v.minor, v.patch))
  else
    error_(("Neovim %d.%d.%d found — expecto requires >= 0.9"):format(v.major, v.minor, v.patch))
  end
end

---Check that curl is available in PATH.
local function check_curl()
  if vim.fn.executable("curl") == 1 then
    local version = vim.fn.system("curl --version 2>&1"):match("curl%s+([%d%.]+)")
    ok(("curl found: %s"):format(version or "(unknown version)"))
  else
    error_("curl not found in PATH — expecto requires curl to send HTTP requests")
  end
end

---Check that jq is available (optional, used for JSON pretty-printing).
local function check_jq()
  if vim.fn.executable("jq") == 1 then
    local version = vim.fn.system("jq --version 2>&1"):gsub("%s+$", "")
    ok(("jq found: %s (optional — used for JSON formatting)"):format(version))
  else
    warn("jq not found — JSON response bodies will use basic Lua formatting instead")
  end
end

---Check that uuidgen is available (optional, used for {{$guid}}).
local function check_uuidgen()
  if vim.fn.executable("uuidgen") == 1 then
    ok("uuidgen found (used for {{$guid}} system variable)")
  else
    -- Fallback: we can generate a UUID in Lua — not critical
    warn("uuidgen not found — {{$guid}} will use a Lua fallback UUID generator")
  end
end

---Entry point called by :checkhealth expecto
function M.check()
  start("expecto.nvim")
  check_nvim_version()
  check_curl()
  check_jq()
  check_uuidgen()
end

return M
