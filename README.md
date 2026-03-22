# expecto.nvim

A Neovim REST client that mirrors the [VSCode REST Client](https://github.com/Huachao/vscode-restclient) experience. Write HTTP requests in plain `.http`/`.rest` files, send them with a keymap, and see the response with proper syntax highlighting — all without leaving Neovim.

## Requirements

- Neovim ≥ 0.9
- `curl` (required — the HTTP engine)
- `jq` (optional — enables JSON pretty-printing in the response window)
- `uuidgen` (optional — enables `{{$guid}}` system variable)

## Installation

**lazy.nvim**

```lua
{
  "maureyesdev/expecto.nvim",
  ft = { "http", "rest" },
  opts = {},
}
```

**packer.nvim**

```lua
use {
  "maureyesdev/expecto.nvim",
  config = function()
    require("expecto").setup()
  end,
}
```

## Configuration

Call `setup()` with any options you want to override. All fields are optional.

```lua
require("expecto").setup({
  -- Direction to open the response window: "vertical" | "horizontal"
  response_split = "vertical",

  -- Width (vertical) or height (horizontal) of the response window
  response_window_size = 60,

  -- Follow 3xx redirects automatically
  follow_redirects = true,

  -- Request timeout in seconds
  timeout = 30,

  -- Auto-format JSON responses (requires jq)
  format_response_body = true,

  -- Show "▶ Send Request" virtual text above each request block
  show_codelens = true,

  -- Maximum number of history entries to keep (per session)
  history_size = 50,

  -- Filename to look for in the project root for environments
  env_file = ".expecto.json",

  -- Global environments file (shared across all projects)
  global_env_file = vim.fn.expand("~/.config/expecto/envs.json"),

  -- Headers added to every request
  default_headers = {
    -- ["User-Agent"] = "expecto.nvim",
  },

  -- Per-host SSL certificate configuration
  certificates = {
    -- ["api.example.com"] = {
    --   cert   = "/path/to/client.crt",
    --   key    = "/path/to/client.key",
    --   ca     = "/path/to/ca.crt",
    --   verify = false,  -- skip verification (insecure)
    -- },
  },
})
```

## Writing requests

Requests live in files with a `.http` or `.rest` extension. Multiple requests in one file are separated by `###`.

### Basic requests

```http
GET https://api.example.com/users

###

POST https://api.example.com/users
Content-Type: application/json

{
  "name": "Alice",
  "email": "alice@example.com"
}

###

DELETE https://api.example.com/users/42
```

All standard HTTP methods are supported: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, `OPTIONS`.

### Headers

```http
GET https://api.example.com/me
Authorization: Bearer my-token
Accept: application/json
```

### Multi-line query strings

Continuation lines starting with `?` or `&` are appended to the URL:

```http
GET https://api.example.com/search
  ?q=neovim
  &limit=20
  &page=1
```

### File variables

Defined once, reused across the whole file. Later blocks inherit earlier definitions.

```http
@baseUrl = https://api.example.com
@version = v2

GET {{baseUrl}}/{{version}}/users
```

### Comments

```http
# This is a comment
// This is also a comment

GET https://api.example.com/users
```

## Variables

Variables use `{{double braces}}` syntax and are resolved in this priority order (highest wins): prompt values → file variables → environment variables.

### System variables

| Variable | Description |
|---|---|
| `{{$guid}}` | Random UUID (requires `uuidgen`) |
| `{{$timestamp}}` | Current Unix timestamp (seconds) |
| `{{$timestamp offset unit}}` | Offset timestamp, e.g. `{{$timestamp -1 d}}` (units: `ms`, `s`, `m`, `h`, `d`, `w`, `M`, `y`) |
| `{{$datetime format}}` | UTC datetime, e.g. `{{$datetime iso8601}}` or `{{$datetime rfc1123}}` |
| `{{$localDatetime format}}` | Local datetime with same format options |
| `{{$randomInt min max}}` | Random integer between min and max (inclusive) |
| `{{$processEnv VAR_NAME}}` | Read from the shell environment (`$VAR_NAME`) |
| `{{$dotenv VAR_NAME}}` | Read from a `.env` file in the project root |

### Environment variables

Defined in `.expecto.json` (see [Environments](#environments)).

```http
GET {{baseUrl}}/users
Authorization: Bearer {{token}}
```

### Prompt variables

Ask for a value at send time with `# @prompt`:

```http
# @prompt username Enter your username
# @prompt password

POST {{baseUrl}}/login
Content-Type: application/json

{"username": "{{username}}", "password": "{{password}}"}
```

### Request chaining

Reference the response of a previously-sent named request:

```http
# @name login
POST {{baseUrl}}/auth/login
Content-Type: application/json

{"username": "alice", "password": "secret"}

###

# Use the token from the login response
GET {{baseUrl}}/profile
Authorization: Bearer {{login.response.body.$.token}}
```

Supported response paths:

| Path | Returns |
|---|---|
| `{{req.response.status}}` | HTTP status code (number) |
| `{{req.response.body}}` | Full response body as text |
| `{{req.response.body.$.field}}` | JSONPath field from response body |
| `{{req.response.body.$.a.b.c}}` | Nested JSONPath |
| `{{req.response.body.$.items[0]}}` | Array index (0-based) |
| `{{req.response.headers.content-type}}` | Response header value |

## Environments

Create a `.expecto.json` file in your project root (or wherever `env_file` points):

```json
{
  "$shared": {
    "version": "v1"
  },
  "development": {
    "baseUrl": "http://localhost:3000/{{$shared version}}",
    "token": "dev-token-123"
  },
  "production": {
    "baseUrl": "https://api.example.com/{{$shared version}}",
    "token": "prod-token-abc"
  }
}
```

- The `$shared` block is available in all environments via `{{$shared key}}`.
- Switch environments with `<leader>he` or `:ExpectoSwitchEnv`.
- Reload from disk with `<leader>hR` or `:ExpectoReloadEnv`.

A global environments file at `~/.config/expecto/envs.json` (same format) is also loaded and merged, so you can keep secrets out of the project repo.

## Annotations

Annotations go above the request line and start with `# @` or `// @`.

| Annotation | Description |
|---|---|
| `# @name <id>` | Name this request for chaining |
| `# @prompt <var> [description]` | Prompt for a variable value before sending |
| `# @no-redirect` | Do not follow redirects for this request |
| `# @no-cookie-jar` | Disable cookie jar for this request |
| `# @note <text>` | Freeform note (displayed in history) |

## Request body

### Inline body

```http
POST https://api.example.com/items
Content-Type: application/json

{"name": "widget", "price": 9.99}
```

### Body from file (literal)

```http
POST https://api.example.com/upload
Content-Type: application/octet-stream

< ./payload.bin
```

### Body from file (with variable substitution)

```http
POST https://api.example.com/users
Content-Type: application/json

<@ ./templates/create-user.json
```

Variables in the file are resolved before sending.

## GraphQL

Add the `X-Request-Type: GraphQL` header. Separate the query from variables with a blank line:

```http
POST https://api.example.com/graphql
Content-Type: application/json
X-Request-Type: GraphQL

query GetUser($id: ID!) {
  user(id: $id) {
    name
    email
  }
}

{"id": "42"}
```

expecto wraps the body as `{"query": "...", "variables": {...}}` automatically.

## SSL / TLS certificates

Configure per-host certificates in `setup()`:

```lua
require("expecto").setup({
  certificates = {
    ["api.internal.com"] = {
      cert   = "/path/to/client.crt",
      key    = "/path/to/client.key",
      ca     = "/path/to/ca.crt",
    },
    ["self-signed.local"] = {
      verify = false,
    },
  },
})
```

## Raw curl pass-through

You can also write raw curl commands — useful for importing commands from docs or `--man` pages:

```http
curl https://api.example.com/users -H "Authorization: Bearer {{token}}"
```

## Keymaps

These keymaps are set automatically on `FileType http` buffers.

| Key | Action |
|---|---|
| `<leader>hr` | Send the request under the cursor |
| `<leader>hc` | Cancel the in-flight request |
| `<leader>hk` | Show the generated curl command (for debugging) |
| `<leader>he` | Switch the active environment |
| `<leader>hR` | Reload environments from disk |
| `<leader>hh` | Browse request history |

## Commands

| Command | Description |
|---|---|
| `:ExpectoRun` | Send the request under the cursor |
| `:ExpectoCancel` | Cancel the in-flight request |
| `:ExpectoCurl` | Show the curl command for the request under cursor |
| `:ExpectoSwitchEnv` | Interactively switch active environment |
| `:ExpectoReloadEnv` | Reload environments from the env file |
| `:ExpectoHistory` | Browse and re-display a previous response |
| `:ExpectoClearHistory` | Clear the session request history |

## Response window

The response window opens in a split and displays the full HTTP response in VSCode REST Client format:

```
HTTP/1.1 200 OK                              342ms  1.2 KB
Content-Type: application/json
X-Request-Id: abc-123

{
  "id": 42,
  "name": "Alice"
}
```

- The status line is colour-coded: green (2xx), yellow (3xx), red (4xx/5xx).
- Timing and response size appear as virtual text at the end of the status line.
- The body is syntax-highlighted according to its content type (JSON, HTML, XML, etc.).
- Press `q` to close the window, `Q` to close and wipe the buffer.

## Code lens

A `▶ Send Request` hint appears above each request block automatically. Enable or disable with `show_codelens` in `setup()`.

## History

Every request sent in the current session is recorded. Browse with `<leader>hh` or `:ExpectoHistory` — select an entry to re-display its response. History is capped at `history_size` entries and cleared when Neovim exits.

## Health check

```
:checkhealth expecto
```

Reports the status of all external dependencies (`curl`, `jq`, `uuidgen`) and the Neovim version.
