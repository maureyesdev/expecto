-- Buffer-local settings for http filetype
if vim.b.did_ftplugin_expecto then
  return
end
vim.b.did_ftplugin_expecto = true

-- Comments use # in .http files
vim.opt_local.commentstring = "# %s"

-- No line wrapping — URLs and headers need full width
vim.opt_local.wrap = false

-- Reasonable tab width
vim.opt_local.expandtab = true
vim.opt_local.tabstop = 2
vim.opt_local.shiftwidth = 2

-- Don't auto-indent (messes with body content)
vim.opt_local.autoindent = false
vim.opt_local.smartindent = false
