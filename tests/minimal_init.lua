-- Minimal init for test runner
vim.opt.rtp:prepend("/tmp/plenary.nvim")
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Ensure plenary is loaded
require("plenary")
