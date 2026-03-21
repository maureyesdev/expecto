local history = require("expecto.history")
local config  = require("expecto.config")

local function fake_req(method, url)
  return { method = method or "GET", url = url or "https://example.com", name = nil }
end

local function fake_resp(status)
  return { status_code = status or 200, headers = {}, body = "", timing = { total = 0.1 } }
end

-- ── push / count / get_all ────────────────────────────────────────────────────

describe("expecto.history — push / get_all", function()
  before_each(function()
    history.clear()
    config.setup({})
  end)

  it("starts empty", function()
    assert.equals(0, history.count())
    assert.same({}, history.get_all())
  end)

  it("stores one entry after push", function()
    history.push(fake_req(), fake_resp())
    assert.equals(1, history.count())
  end)

  it("stores request and response in the entry", function()
    local req  = fake_req("POST", "https://api.example.com/users")
    local resp = fake_resp(201)
    history.push(req, resp)
    local entries = history.get_all()
    assert.equals("POST", entries[1].req.method)
    assert.equals(201, entries[1].response.status_code)
  end)

  it("stores a timestamp", function()
    history.push(fake_req(), fake_resp())
    local entry = history.get_all()[1]
    assert.is_not_nil(entry.timestamp)
    assert.truthy(entry.timestamp > 0)
  end)

  it("newest entry appears first (index 1)", function()
    history.push(fake_req("GET",  "https://first.example.com"), fake_resp(200))
    history.push(fake_req("POST", "https://second.example.com"), fake_resp(201))
    local entries = history.get_all()
    assert.equals("https://second.example.com", entries[1].req.url)
    assert.equals("https://first.example.com",  entries[2].req.url)
  end)

  it("accumulates multiple entries", function()
    for i = 1, 5 do
      history.push(fake_req("GET", "https://example.com/" .. i), fake_resp(200))
    end
    assert.equals(5, history.count())
  end)
end)

-- ── size cap ──────────────────────────────────────────────────────────────────

describe("expecto.history — size capping", function()
  before_each(function()
    history.clear()
  end)

  it("trims to history_size when exceeded", function()
    config.setup({ history_size = 3 })
    for i = 1, 5 do
      history.push(fake_req("GET", "https://example.com/" .. i), fake_resp(200))
    end
    assert.equals(3, history.count())
  end)

  it("keeps the newest entries after trim", function()
    config.setup({ history_size = 2 })
    history.push(fake_req("GET", "https://old.example.com"),   fake_resp(200))
    history.push(fake_req("GET", "https://newer.example.com"), fake_resp(200))
    history.push(fake_req("GET", "https://newest.example.com"), fake_resp(200))
    local entries = history.get_all()
    assert.equals("https://newest.example.com", entries[1].req.url)
    assert.equals("https://newer.example.com",  entries[2].req.url)
  end)

  it("works with history_size = 1", function()
    config.setup({ history_size = 1 })
    history.push(fake_req("GET", "https://a.example.com"), fake_resp(200))
    history.push(fake_req("GET", "https://b.example.com"), fake_resp(200))
    assert.equals(1, history.count())
    assert.equals("https://b.example.com", history.get_all()[1].req.url)
  end)
end)

-- ── clear ─────────────────────────────────────────────────────────────────────

describe("expecto.history — clear", function()
  before_each(function()
    history.clear()
    config.setup({})
  end)

  it("resets count to 0", function()
    history.push(fake_req(), fake_resp())
    history.push(fake_req(), fake_resp())
    history.clear()
    assert.equals(0, history.count())
  end)

  it("returns empty list after clear", function()
    history.push(fake_req(), fake_resp())
    history.clear()
    assert.same({}, history.get_all())
  end)
end)

-- ── get_all isolation ─────────────────────────────────────────────────────────

describe("expecto.history — get_all isolation", function()
  before_each(function()
    history.clear()
    config.setup({})
  end)

  it("mutating get_all() result does not affect history store", function()
    history.push(fake_req(), fake_resp())
    local all = history.get_all()
    all[1] = nil  -- mutate the copy
    assert.equals(1, history.count())
  end)
end)
