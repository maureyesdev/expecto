--- expecto.nvim — environment manager
--- Loads .expecto.json (or global envs.json), merges $shared vars,
--- and tracks the active environment for the session.
local M = {}

-- ── Session state ─────────────────────────────────────────────────────────────

local _envs         = {}   -- name → merged vars table (after $shared merge)
local _raw          = {}   -- name → raw (pre-merge) vars table
local _shared       = {}   -- $shared vars
local _current_name = nil  -- active environment name
local _loaded_path  = nil  -- path of the last successfully loaded file

-- ── Dotenv loader ─────────────────────────────────────────────────────────────

--- Load a `.env` file and return its key=value pairs as a table.
--- Silently returns {} if the file does not exist.
---@param dir string  Directory to look for .env in
---@return table
function M.load_dotenv(dir)
  local path = dir .. "/.env"
  local f = io.open(path, "r")
  if not f then return {} end

  local vars = {}
  for line in f:lines() do
    -- Skip blank lines and comments
    if not line:match("^%s*#") and not line:match("^%s*$") then
      -- NAME=value  or  NAME="value"  or  NAME='value'
      local name, raw_value = line:match("^%s*([%w_][%w_%d]*)%s*=%s*(.*)")
      if name then
        -- Strip surrounding quotes
        local value = raw_value:match('^"(.*)"$')
          or raw_value:match("^'(.*)'$")
          or raw_value
        vars[name] = value
      end
    end
  end
  f:close()
  return vars
end

-- ── $shared reference resolver ────────────────────────────────────────────────

--- Resolve `{{$shared varName}}` references inside a value string.
--- This is evaluated at load time (not request time).
local function resolve_shared_refs(value, shared)
  return value:gsub("{{%$shared%s+([^}]+)}}", function(ref)
    ref = vim.trim(ref)
    return shared[ref] or ("{{$shared " .. ref .. "}}")
  end)
end

--- Apply shared-ref resolution to all string values in a vars table.
local function apply_shared_refs(vars, shared)
  local result = {}
  for k, v in pairs(vars) do
    result[k] = (type(v) == "string") and resolve_shared_refs(v, shared) or v
  end
  return result
end

-- ── JSON loader ───────────────────────────────────────────────────────────────

--- Load and parse the JSON from `path`.
--- Returns (data_table, nil) on success or (nil, error_string) on failure.
local function read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil, "file not found: " .. path
  end
  local content = f:read("*a")
  f:close()

  if not content or content:match("^%s*$") then
    return nil, "empty file: " .. path
  end

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok then
    return nil, "JSON parse error in " .. path .. ": " .. tostring(data)
  end

  return data, nil
end

-- ── Public: load ─────────────────────────────────────────────────────────────

--- Load environments from a JSON file.
--- Clears and replaces any previously loaded environments.
---
--- File format:
--- ```json
--- {
---   "$shared": { "version": "v1" },
---   "local":   { "host": "localhost", "token": "{{$shared version}}-local" },
---   "prod":    { "host": "api.example.com" }
--- }
--- ```
---
---@param path string  Absolute or relative path to the envs JSON file
---@return boolean ok
---@return string|nil error_message
function M.load(path)
  local data, err = read_json(path)
  if not data then
    return false, err
  end

  -- Extract $shared first
  local shared = {}
  if type(data["$shared"]) == "table" then
    shared = data["$shared"]
  end

  -- Build merged environments
  local envs = {}
  local raw  = {}

  for name, vars in pairs(data) do
    if name ~= "$shared" and type(vars) == "table" then
      raw[name] = vars
      -- Merge: shared is the base, env-specific vars override
      local merged = vim.tbl_extend("force", {}, shared, vars)
      -- Resolve {{$shared varName}} references inside env values
      merged = apply_shared_refs(merged, shared)
      envs[name] = merged
    end
  end

  _envs         = envs
  _raw          = raw
  _shared       = shared
  _loaded_path  = path

  -- Keep the current env if it still exists, else reset to first available
  if _current_name and not envs[_current_name] then
    _current_name = nil
  end

  if not _current_name then
    -- Pick a stable default: "local" → "dev" → "staging" → first alphabetical
    for _, preferred in ipairs({ "local", "dev", "development", "staging" }) do
      if envs[preferred] then
        _current_name = preferred
        break
      end
    end
    if not _current_name then
      local names = vim.tbl_keys(envs)
      table.sort(names)
      _current_name = names[1]
    end
  end

  return true, nil
end

-- ── Public: auto-load ────────────────────────────────────────────────────────

--- Try to load environments automatically from the project or global config.
--- Called lazily on first `get_vars()` call if nothing has been loaded yet.
local function try_auto_load()
  local cfg = require("expecto.config").get()

  -- 1. Project-level env file (relative to cwd)
  local project_path = vim.fn.getcwd() .. "/" .. cfg.env_file
  if vim.fn.filereadable(project_path) == 1 then
    M.load(project_path)
    return
  end

  -- 2. Global env file
  local global_path = cfg.global_env_file
  if global_path and vim.fn.filereadable(global_path) == 1 then
    M.load(global_path)
    return
  end
  -- Neither found — _envs stays empty, which is fine
end

-- ── Public: accessors ────────────────────────────────────────────────────────

--- Return the merged variable table for the current environment.
--- Returns {} if no environment is loaded or selected.
---@return table
function M.get_vars()
  if not _loaded_path then
    try_auto_load()
  end
  if not _current_name then return {} end
  return _envs[_current_name] or {}
end

--- Return the name of the currently active environment (or nil).
---@return string|nil
function M.current_name()
  return _current_name
end

--- Return a list of all available environment names (sorted).
---@return string[]
function M.list_names()
  local names = vim.tbl_keys(_envs)
  table.sort(names)
  return names
end

--- Switch to a named environment.
---@param name string
---@return boolean  true if the environment exists and was switched to
function M.switch(name)
  if not _envs[name] then
    return false
  end
  _current_name = name
  vim.notify("expecto: switched to environment '" .. name .. "'", vim.log.levels.INFO)
  return true
end

--- Return the $shared vars table (raw, unmerged).
---@return table
function M.get_shared()
  return vim.deepcopy(_shared)
end

--- Return all environments as a table (name → merged vars).
---@return table
function M.get_all()
  return vim.deepcopy(_envs)
end

--- Clear all loaded state (useful for testing).
function M.reset()
  _envs         = {}
  _raw          = {}
  _shared       = {}
  _current_name = nil
  _loaded_path  = nil
end

--- Reload from the same file that was previously loaded.
---@return boolean, string|nil
function M.reload()
  if not _loaded_path then
    return false, "no environment file loaded"
  end
  return M.load(_loaded_path)
end

return M
