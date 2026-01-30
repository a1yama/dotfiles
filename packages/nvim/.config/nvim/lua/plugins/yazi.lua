return {
  "mikavilpas/yazi.nvim",
  event = "VeryLazy",
  keys = {
    {
      "<leader>y",
      "<cmd>Yazi<cr>",
      desc = "Open yazi at the current file",
    },
    {
      "<leader>Y",
      "<cmd>Yazi cwd<cr>",
      desc = "Open yazi in nvim's working directory",
    },
  },
  opts = {
    -- Optional: Configure yazi.nvim behavior
    open_for_directories = false,
    keymaps = {
      show_help = '<f1>',
    },
    -- yazi設定ファイルのパスを明示的に指定
    yazi_floating_window_border = "rounded",
  },
}
