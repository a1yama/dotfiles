# Neovim Plugins

## カラースキーム

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| [folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim) | カラースキーム（透過対応） | - |

## UI/外観

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| [nvim-lualine/lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) | ステータスライン | - |
| [nvim-tree/nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) | ファイルアイコン | - |
| [norcalli/nvim-colorizer.lua](https://github.com/norcalli/nvim-colorizer.lua) | カラーコードのプレビュー | - |
| [lukas-reineke/indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim) | インデントガイド | - |
| [folke/which-key.nvim](https://github.com/folke/which-key.nvim) | キーバインドヘルプ | `<leader>?` |
| [simeji/winresizer](https://github.com/simeji/winresizer) | ウィンドウリサイズ | - |

## ファイル操作/検索

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| [nvim-tree/nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua) | ファイルツリー | `<leader>e` |
| [mikavilpas/yazi.nvim](https://github.com/mikavilpas/yazi.nvim) | yaziファイルマネージャー連携 | `<leader>y`, `<leader>Y` |
| [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | ファジーファインダー | `<leader>p`, `<leader>/`, `<leader>r`, `<leader>b`, `<leader>f`, `<leader>H` |

## Git

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| [tpope/vim-fugitive](https://github.com/tpope/vim-fugitive) | Git操作 | - |
| [tpope/vim-rhubarb](https://github.com/tpope/vim-rhubarb) | GitHub連携（ブラウザでリポジトリを開く） | - |
| [akinsho/git-conflict.nvim](https://github.com/akinsho/git-conflict.nvim) | Gitコンフリクト解決 | - |
| [kdheepak/lazygit.nvim](https://github.com/kdheepak/lazygit.nvim) | LazyGit連携 | `<leader>g` |

## LSP/補完

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| [neovim/nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP設定 | `gD`, `gd`, `gi`, `gr`, `<leader>ca` |
| [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp) | 補完エンジン | `<C-b>`, `<C-f>`, `<C-Space>`, `<C-e>`, `<CR>` |
| [hrsh7th/cmp-nvim-lsp](https://github.com/hrsh7th/cmp-nvim-lsp) | LSP補完ソース | - |
| [hrsh7th/cmp-buffer](https://github.com/hrsh7th/cmp-buffer) | バッファ補完ソース | - |
| [hrsh7th/cmp-path](https://github.com/hrsh7th/cmp-path) | パス補完ソース | - |
| [hrsh7th/cmp-cmdline](https://github.com/hrsh7th/cmp-cmdline) | コマンドライン補完ソース | - |
| [hrsh7th/cmp-nvim-lua](https://github.com/hrsh7th/cmp-nvim-lua) | Lua補完ソース | - |

## シンタックス/フォーマッター

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| [nvim-treesitter/nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | シンタックスハイライト | - |
| [stevearc/conform.nvim](https://github.com/stevearc/conform.nvim) | コードフォーマッター | `<leader>i` |

## AI連携

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| [github/copilot.vim](https://github.com/github/copilot.vim) | GitHub Copilot | - |
| [CopilotC-Nvim/CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim) | Copilot Chat | - |
| [coder/claudecode.nvim](https://github.com/coder/claudecode.nvim) | Claude Code連携 | `<leader>ac`, `<leader>as` (visual) |

## 依存関係

| プラグイン | 説明 |
|-----------|------|
| [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim) | 多くのプラグインが依存するユーティリティ |

## 設定済みLSP

- lua_ls (Lua)
- ts_ls (TypeScript/JavaScript)
- phpactor (PHP)
- gopls (Go)
- ruby_lsp (Ruby)
- ziggy (Zig)

## Treesitterでサポートされている言語

ruby, php, go, gotmpl, gomod, gosum, zig, tsx, javascript, typescript, json, yaml, html, css, lua, luadoc, vim, vimdoc, markdown, markdown_inline, sql, git_config, git_rebase, gitattributes, gitcommit, gitignore, graphql, c, cpp, c_sharp

## conform.nvimでサポートされているフォーマッター

| 言語 | フォーマッター |
|------|---------------|
| Lua | stylua |
| Go | goimports, gofmt |
| PHP | phpcbf |
| JavaScript/TypeScript/React | prettierd |
| JSON | prettierd |
| SQL | sql-formatter |
| Terraform | terraform_fmt |
