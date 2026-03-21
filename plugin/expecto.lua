-- Plugin guard: only load once
if vim.g.loaded_expecto then
  return
end
vim.g.loaded_expecto = true

-- Require Neovim 0.9+
if vim.fn.has("nvim-0.9") == 0 then
  vim.api.nvim_err_writeln("expecto.nvim requires Neovim >= 0.9")
  return
end

-- Bootstrap with empty opts; user calls require("expecto").setup({...}) in their config
require("expecto").setup()
