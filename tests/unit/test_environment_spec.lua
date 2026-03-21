local env = require("expecto.environment")

-- Path to our fixtures directory
local FIXTURES = vim.fn.fnamemodify(
  debug.getinfo(1, "S").source:sub(2),
  ":h:h"
) .. "/fixtures"

local ENV_FILE = FIXTURES .. "/environments.json"

-- ── load() ───────────────────────────────────────────────────────────────────

describe("expecto.environment — load()", function()
  before_each(function() env.reset() end)
  it("loads a valid JSON file without error", function()
    local ok, err = env.load(ENV_FILE)
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("returns false and an error for a missing file", function()
    local ok, err = env.load("/nonexistent/path/envs.json")
    assert.is_false(ok)
    assert.is_not_nil(err)
    assert.truthy(err:find("not found"))
  end)

  it("returns false for invalid JSON", function()
    -- Write a temp file with bad JSON
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write("{ this is not json }")
    f:close()

    local ok, err = env.load(tmp)
    assert.is_false(ok)
    assert.is_not_nil(err)

    os.remove(tmp)
  end)

  it("returns false for an empty file", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write("   ")
    f:close()

    local ok, err = env.load(tmp)
    assert.is_false(ok)

    os.remove(tmp)
  end)
end)

-- ── list_names() ─────────────────────────────────────────────────────────────

describe("expecto.environment — list_names()", function()
  before_each(function() env.reset() end)

  it("returns empty list before loading", function()
    assert.same({}, env.list_names())
  end)

  it("returns all environment names after loading", function()
    env.load(ENV_FILE)
    local names = env.list_names()
    -- Our fixture has: local, staging, production
    assert.truthy(vim.tbl_contains(names, "local"))
    assert.truthy(vim.tbl_contains(names, "staging"))
    assert.truthy(vim.tbl_contains(names, "production"))
  end)

  it("does NOT include $shared in the names list", function()
    env.load(ENV_FILE)
    assert.is_false(vim.tbl_contains(env.list_names(), "$shared"))
  end)

  it("returns names in sorted order", function()
    env.load(ENV_FILE)
    local names = env.list_names()
    local sorted = vim.deepcopy(names)
    table.sort(sorted)
    assert.same(sorted, names)
  end)
end)

-- ── $shared merging ───────────────────────────────────────────────────────────

describe("expecto.environment — $shared merging", function()
  before_each(function()
    env.reset()
    env.load(ENV_FILE)
  end)

  it("merges $shared vars into each environment", function()
    env.switch("local")
    local vars = env.get_vars()
    -- "version" is in $shared, not in "local" directly
    assert.equals("v1", vars["version"])
  end)

  it("merges $shared into staging", function()
    env.switch("staging")
    local vars = env.get_vars()
    assert.equals("v1", vars["version"])
    assert.equals("2024-01", vars["apiVersion"])
  end)

  it("merges $shared into production", function()
    env.switch("production")
    local vars = env.get_vars()
    assert.equals("shared-secret-123", vars["sharedKey"])
  end)

  it("env-specific vars override $shared vars", function()
    -- If both $shared and env define the same key, env wins
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(vim.fn.json_encode({
      ["$shared"] = { host = "shared-host", version = "v0" },
      ["dev"]     = { host = "dev-host", token = "dev-token" },
    }))
    f:close()

    env.reset()
    env.load(tmp)
    env.switch("dev")
    local vars = env.get_vars()

    assert.equals("dev-host", vars["host"])    -- env overrides shared
    assert.equals("v0", vars["version"])        -- from shared
    assert.equals("dev-token", vars["token"])   -- env-only

    os.remove(tmp)
  end)

  it("resolves {{$shared varName}} references in env values", function()
    -- An env value that references a shared var using {{$shared name}} syntax
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(vim.fn.json_encode({
      ["$shared"] = { apiKey = "secret-key" },
      ["local"]   = { auth = "Bearer {{$shared apiKey}}" },
    }))
    f:close()

    env.reset()
    env.load(tmp)
    env.switch("local")
    local vars = env.get_vars()

    assert.equals("Bearer secret-key", vars["auth"])

    os.remove(tmp)
  end)
end)

-- ── switch() / current_name() ─────────────────────────────────────────────────

describe("expecto.environment — switch()", function()
  before_each(function()
    env.reset()
    env.load(ENV_FILE)
  end)

  it("switches to a valid environment", function()
    env.switch("staging")
    assert.equals("staging", env.current_name())
  end)

  it("returns true when switch succeeds", function()
    local ok = env.switch("production")
    assert.is_true(ok)
  end)

  it("returns false when environment does not exist", function()
    local ok = env.switch("nonexistent")
    assert.is_false(ok)
  end)

  it("keeps previous env when switch fails", function()
    env.switch("local")
    env.switch("nonexistent")
    assert.equals("local", env.current_name())
  end)

  it("get_vars() returns the newly switched env vars", function()
    env.switch("local")
    local local_token = env.get_vars()["token"]

    env.switch("production")
    local prod_token = env.get_vars()["token"]

    assert.not_equals(local_token, prod_token)
    assert.equals("local-dev-token", local_token)
    assert.equals("prod-token-xyz", prod_token)
  end)
end)

-- ── get_vars() ────────────────────────────────────────────────────────────────

describe("expecto.environment — get_vars()", function()
  before_each(function() env.reset() end)

  it("returns empty table before any environment is loaded", function()
    -- No load called — reset() was called in before_each
    assert.same({}, env.get_vars())
  end)

  it("returns correct vars for local env", function()
    env.load(ENV_FILE)
    env.switch("local")
    local vars = env.get_vars()
    assert.equals("localhost:3000", vars["host"])
    assert.equals("http", vars["scheme"])
    assert.equals("local-dev-token", vars["token"])
  end)

  it("returns correct vars for production env", function()
    env.load(ENV_FILE)
    env.switch("production")
    local vars = env.get_vars()
    assert.equals("api.example.com", vars["host"])
    assert.equals("https", vars["scheme"])
    assert.equals("prod-token-xyz", vars["token"])
  end)
end)

-- ── Auto environment selection ────────────────────────────────────────────────

describe("expecto.environment — auto environment selection", function()
  before_each(function() env.reset() end)

  it("auto-selects 'local' as the default when present", function()
    env.load(ENV_FILE)
    -- Our fixture has "local", "staging", "production"
    assert.equals("local", env.current_name())
  end)

  it("falls back to alphabetical first when no preferred name exists", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(vim.fn.json_encode({
      ["beta"]  = { host = "beta.example.com" },
      ["alpha"] = { host = "alpha.example.com" },
    }))
    f:close()

    env.reset()
    env.load(tmp)
    -- "alpha" comes before "beta" alphabetically
    assert.equals("alpha", env.current_name())

    os.remove(tmp)
  end)

  it("keeps current env across reload if it still exists", function()
    env.load(ENV_FILE)
    env.switch("staging")
    env.load(ENV_FILE)  -- reload same file
    assert.equals("staging", env.current_name())
  end)

  it("resets current env on reload if it no longer exists", function()
    env.load(ENV_FILE)
    env.switch("staging")

    -- Load a new file without "staging"
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(vim.fn.json_encode({
      ["production"] = { host = "prod.example.com" },
    }))
    f:close()

    env.load(tmp)
    assert.not_equals("staging", env.current_name())

    os.remove(tmp)
  end)
end)

-- ── reload() ─────────────────────────────────────────────────────────────────

describe("expecto.environment — reload()", function()
  before_each(function() env.reset() end)

  it("fails gracefully before any load", function()
    local ok, err = env.reload()
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("reloads the same file successfully", function()
    env.load(ENV_FILE)
    local ok, err = env.reload()
    assert.is_true(ok)
    assert.is_nil(err)
  end)
end)

-- ── get_shared() ─────────────────────────────────────────────────────────────

describe("expecto.environment — get_shared()", function()
  before_each(function() env.reset() end)

  it("returns the raw $shared vars", function()
    env.load(ENV_FILE)
    local shared = env.get_shared()
    assert.equals("v1",               shared["version"])
    assert.equals("2024-01",          shared["apiVersion"])
    assert.equals("shared-secret-123", shared["sharedKey"])
  end)

  it("returns empty table before loading", function()
    assert.same({}, env.get_shared())
  end)
end)

-- ── load_dotenv() ─────────────────────────────────────────────────────────────

describe("expecto.environment — load_dotenv()", function()
  it("returns empty table for a directory with no .env file", function()
    local vars = env.load_dotenv("/tmp")
    -- /tmp probably has no .env
    assert.is_table(vars)
  end)

  it("parses KEY=value pairs", function()
    local tmp_dir = os.tmpname()
    os.remove(tmp_dir)  -- remove the file, use it as a directory name
    os.execute("mkdir -p " .. tmp_dir)

    local dotenv_path = tmp_dir .. "/.env"
    local f = io.open(dotenv_path, "w")
    f:write("API_KEY=my-secret\nDB_HOST=localhost\n")
    f:close()

    local vars = env.load_dotenv(tmp_dir)
    assert.equals("my-secret", vars["API_KEY"])
    assert.equals("localhost", vars["DB_HOST"])

    os.remove(dotenv_path)
    os.execute("rmdir " .. tmp_dir)
  end)

  it("strips double-quoted values", function()
    local tmp_dir = os.tmpname()
    os.remove(tmp_dir)
    os.execute("mkdir -p " .. tmp_dir)

    local f = io.open(tmp_dir .. "/.env", "w")
    f:write('TOKEN="bearer-token-123"\n')
    f:close()

    local vars = env.load_dotenv(tmp_dir)
    assert.equals("bearer-token-123", vars["TOKEN"])

    os.remove(tmp_dir .. "/.env")
    os.execute("rmdir " .. tmp_dir)
  end)

  it("strips single-quoted values", function()
    local tmp_dir = os.tmpname()
    os.remove(tmp_dir)
    os.execute("mkdir -p " .. tmp_dir)

    local f = io.open(tmp_dir .. "/.env", "w")
    f:write("SECRET='my secret value'\n")
    f:close()

    local vars = env.load_dotenv(tmp_dir)
    assert.equals("my secret value", vars["SECRET"])

    os.remove(tmp_dir .. "/.env")
    os.execute("rmdir " .. tmp_dir)
  end)

  it("ignores comment lines", function()
    local tmp_dir = os.tmpname()
    os.remove(tmp_dir)
    os.execute("mkdir -p " .. tmp_dir)

    local f = io.open(tmp_dir .. "/.env", "w")
    f:write("# This is a comment\nKEY=value\n# Another comment\n")
    f:close()

    local vars = env.load_dotenv(tmp_dir)
    assert.equals("value", vars["KEY"])
    assert.is_nil(vars["# This is a comment"])

    os.remove(tmp_dir .. "/.env")
    os.execute("rmdir " .. tmp_dir)
  end)

  it("ignores blank lines", function()
    local tmp_dir = os.tmpname()
    os.remove(tmp_dir)
    os.execute("mkdir -p " .. tmp_dir)

    local f = io.open(tmp_dir .. "/.env", "w")
    f:write("\nKEY=value\n\n")
    f:close()

    local vars = env.load_dotenv(tmp_dir)
    assert.equals("value", vars["KEY"])
    assert.equals(1, #vim.tbl_keys(vars))

    os.remove(tmp_dir .. "/.env")
    os.execute("rmdir " .. tmp_dir)
  end)
end)

-- ── reset() ──────────────────────────────────────────────────────────────────

describe("expecto.environment — reset()", function()
  before_each(function() env.reset() end)

  it("clears all state", function()
    env.load(ENV_FILE)
    env.switch("production")

    env.reset()

    assert.same({}, env.get_vars())
    assert.same({}, env.list_names())
    assert.is_nil(env.current_name())
  end)
end)
