return {
  "akinsho/toggleterm.nvim",
  version = "*",
  config = function()
    require("toggleterm").setup({
      size = function(term)
        if term.direction == "horizontal" then
          return 15
        elseif term.direction == "vertical" then
          return vim.o.columns * 0.4
        end
      end,
      open_mapping = [[<C-\>]],
      direction = "float",
      float_opts = {
        border = "curved",
        width = function() return math.floor(vim.o.columns * 0.9) end,
        height = function() return math.floor(vim.o.lines * 0.9) end,
      },
    })

    local Terminal = require("toggleterm.terminal").Terminal

    -- Claude Code
    local claude = Terminal:new({
      cmd = "claude",
      hidden = true,
      direction = "float",
    })
    vim.keymap.set("n", "<leader>tc", function() claude:toggle() end, { desc = "Toggle Claude Code" })

    -- Codex
    local codex = Terminal:new({
      cmd = "codex",
      hidden = true,
      direction = "float",
    })
    vim.keymap.set("n", "<leader>tx", function() codex:toggle() end, { desc = "Toggle Codex" })

    -- 汎用ターミナル
    vim.keymap.set("n", "<leader>tt", "<cmd>ToggleTerm<cr>", { desc = "Toggle Terminal" })

    -- ターミナルモードでEscでノーマルモードに戻る
    vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
    vim.keymap.set("t", "<C-w>", [[<C-\><C-n><C-w>]], { desc = "Window commands in terminal" })

    -- ターミナルに入ったら自動でインサートモードに
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "term://*",
      callback = function()
        vim.cmd("startinsert")
      end,
    })
  end,
}
