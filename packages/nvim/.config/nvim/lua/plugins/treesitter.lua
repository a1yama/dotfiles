return {
  "nvim-treesitter/nvim-treesitter",
  -- main は書き直し版で nvim-treesitter.configs が無い。下の setup を使う限り master に留める。
  branch = "master",
  lazy = false,
  -- event = { "BufReadPost", "BufNewFile" },
  -- cmd = { "TSInstall", "TSBufEnable", "TSBufDisable", "TSModuleInfo" },
  config = function()
    require('nvim-treesitter.configs').setup {
      ensure_installed = {
        "ruby",
        "php",
        "go",
        "gotmpl",
        "gomod",
        "gosum",
        "zig",
        "tsx",
        "javascript",
        "typescript",
        "json",
        "yaml",
        "html",
        "css",
        "lua",
        "luadoc",
        "vim",
        "vimdoc",
        "markdown_inline",
        "markdown",
        "sql",
        "git_config",
        "git_rebase",
        "gitattributes",
        "gitcommit",
        "gitignore",
        "graphql",
        "c",
        "cpp",
        "c_sharp",
      },
      auto_install = true,
      highlight = {
        enable = true,
      },
    }
  end
}
