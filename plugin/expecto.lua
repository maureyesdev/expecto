-- Plugin guard: only load once
if vim.g.loaded_expecto then return end
vim.g.loaded_expecto = true

-- Require Neovim 0.9+
if vim.fn.has("nvim-0.9") == 0 then
  vim.api.nvim_err_writeln("expecto.nvim requires Neovim >= 0.9")
  return
end

-- Bootstrap (empty opts — user calls setup() in their own config)
require("expecto").setup()

-- ── User commands ─────────────────────────────────────────────────────────────

vim.api.nvim_create_user_command("ExpectoRun", function()
  require("expecto").run()
end, { desc = "Send HTTP request under cursor" })

vim.api.nvim_create_user_command("ExpectoCancel", function()
  require("expecto").cancel()
end, { desc = "Cancel the in-flight HTTP request" })

vim.api.nvim_create_user_command("ExpectoCurl", function()
  require("expecto").show_curl_command()
end, { desc = "Show the curl command for the request under cursor" })

vim.api.nvim_create_user_command("ExpectoSwitchEnv", function()
  require("expecto").switch_env()
end, { desc = "Switch the active environment" })

vim.api.nvim_create_user_command("ExpectoReloadEnv", function()
  require("expecto").reload_env()
end, { desc = "Reload environments from the .expecto.json file" })

-- ── Filetype keymaps (buffer-local, set on FileType http) ────────────────────

vim.api.nvim_create_autocmd("FileType", {
  pattern = "http",
  group   = vim.api.nvim_create_augroup("expecto_keymaps", { clear = true }),
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, {
        buffer  = ev.buf,
        silent  = true,
        noremap = true,
        desc    = "expecto: " .. desc,
      })
    end

    map("<leader>hr", "<Cmd>ExpectoRun<CR>",       "run request at cursor")
    map("<leader>hc", "<Cmd>ExpectoCancel<CR>",   "cancel in-flight request")
    map("<leader>hk", "<Cmd>ExpectoCurl<CR>",     "show curl command")
    map("<leader>he", "<Cmd>ExpectoSwitchEnv<CR>","switch active environment")
    map("<leader>hR", "<Cmd>ExpectoReloadEnv<CR>","reload environments from file")
  end,
})
