return {
    -- Neo-tree.nvim
    { 
      "nvim-neo-tree/neo-tree.nvim",
      dependencies = {
        "nvim-lua/popup.nvim",
        "nvim-tree/nvim-web-devicons",
      },
    },
  
    -- telescope.nvim
    { 
      "nvim-telescope/telescope.nvim",
      dependencies = { "nvim-lua/popup.nvim" },
    },
  
    -- lualine.nvim
    { "nvim-lualine/lualine.nvim" },
  
    -- render-markdown.nvim
    { 
      "MeanderingProgrammer/render-markdown.nvim",
      dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    },
  
    -- readermode.nvim
    { "sarrisv/readermode.nvim" },
  
    -- lazygit.nvim
    {
      "kdheepak/lazygit.nvim",
      keys = {
        { "<leader>lg", "<cmd>LazyGit<cr>", desc = "LazyGit" }
      }
    },
  }