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
keymap.set("n", "<leader>p", "<cmd>Neotree<CR>", { desc = "Neo tree" })

local builtin = require('telescope.builtin')
keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Telescope find files' })
keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Telescope live grep' })
keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Telescope buffers' })
keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Telescope help tags' })