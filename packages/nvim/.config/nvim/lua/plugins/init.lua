return {
    -- Neo-tree.nvim
    { 
      "nvim-neo-tree/neo-tree.nvim",
      branch = "v3.x",
      dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
        "MunifTanjim/nui.nvim",
        -- {"3rd/image.nvim", opts = {}}, -- Optional image support in preview window: See `# Preview Mode` for more information
      },
      opts = {
        filesystem = {
            follow_current_file = { enabled = true },
            hijack_netrw_behavior = "open_current",
            use_libuv_file_watcher = true,
            filtered_items = {
              visible = false, -- デフォルトで隠されているかどうか
              show_hidden_count = true,
              hide_dotfiles = false, -- dotfileを隠すかどうか
              hide_gitignored = false, -- gitignoreされているファイルを隠すかどうか
              hide_by_name = {
                "node_modules",
                "thumbs.db",
              },
              never_show = {
                ".git",
                ".DS_Store",
                ".history",
              },
            },
          },
      }
    },
  
    -- telescope.nvim
    { 
      "nvim-telescope/telescope.nvim",
      tag = '0.1.8',
      dependencies = { "nvim-lua/plenary.nvim" },
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
    },
  }