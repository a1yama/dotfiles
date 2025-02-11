vim.g.mapleader = " "

-- for conciseness
local keymap = vim.keymap

keymap.set("n", "J", "<C-d>")
keymap.set("n", "K", "<C-u>")

-- visual mode
keymap.set("v", "J", "<C-d>")
keymap.set("v", "K", "<c-u>")

-- using leader
keymap.set("n", "<leader>q", "<cmd>q<CR>", { silent = true, desc = "Close buffer" })
keymap.set("n", "<leader>lg", "<cmd>LazyGit<CR>", { desc = "LazyGit" })
