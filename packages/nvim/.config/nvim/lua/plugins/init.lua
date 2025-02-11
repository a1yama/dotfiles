return {
    -- Neo-tree.nvim
    { 
      "nvim-neo-tree/neo-tree.nvim",
      branch = "v3.x",
      dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
      },
      opts = {
        filesystem = {
            follow_current_file = { enabled = true },
            hijack_netrw_behavior = "open_current",
            use_libuv_file_watcher = true,
            filtered_items = {
              visible = false,
              show_hidden_count = true,
              hide_dotfiles = false,
              hide_gitignored = false,
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
      config = function()
        require('telescope').setup {
          defaults = {
            vimgrep_arguments = {
              'rg',
              '--color=never',
              '--no-heading',
              '--with-filename',
              '--line-number',
              '--column',
              '--smart-case',
              '--hidden',
              '--glob', '!.git/*'
            },
            file_ignore_patterns = { "%.git/" },
            follow = true,
          },
          pickers = {
            find_files = {
              hidden = true,
              follow = true,
              find_command = { 'fd', '--type', 'f', '--hidden', '--follow' }
            }
          }
        }
      end
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