# Neovim プラグイン一覧

## プラグインマネージャー

| プラグイン | 説明 |
|-----------|------|
| **folke/lazy.nvim** | 高速な遅延読み込み対応プラグインマネージャー |

---

## エディタUI・外観

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| **folke/tokyonight.nvim** | カラースキーム（tokyonight-storm使用、透過設定あり） | - |
| **nvim-lualine/lualine.nvim** | ステータスライン（モード、ファイル名、ブランチ等を表示） | - |
| **nvim-tree/nvim-web-devicons** | ファイルタイプ別アイコン表示 | - |
| **lukas-reineke/indent-blankline.nvim** | インデントガイドライン表示 | - |
| **norcalli/nvim-colorizer.lua** | カラーコード（#FF0000等）をハイライト表示 | - |
| **folke/which-key.nvim** | キーマップのヒント表示 | `<leader>?` |

---

## ファイル操作・検索

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| **nvim-telescope/telescope.nvim** | ファジーファインダー（ファイル検索、grep等） | `<leader>p` ファイル検索<br>`<leader>g` 文字列検索<br>`<leader>r` 前回の検索再開<br>`<leader>b` 前回のpicker<br>`<leader>f` quickfix |
| **nvim-tree/nvim-tree.lua** | ファイルツリー（サイドバー） | `<leader>e` ツリー開閉 |

---

## LSP・補完

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| **neovim/nvim-lspconfig** | LSPクライアント設定（lua, ts, php, go, ruby, zig対応） | `gd` 定義へ<br>`gD` 宣言へ<br>`gi` 実装へ<br>`gr` 参照一覧<br>`<leader>ca` コードアクション |
| **hrsh7th/nvim-cmp** | 自動補完エンジン | `<C-Space>` 補完開始<br>`<CR>` 確定<br>`<C-e>` キャンセル |
| **hrsh7th/cmp-nvim-lsp** | LSP補完ソース | - |
| **hrsh7th/cmp-buffer** | バッファ内単語補完 | - |
| **hrsh7th/cmp-path** | ファイルパス補完 | - |
| **hrsh7th/cmp-cmdline** | コマンドライン補完 | - |

---

## シンタックス・フォーマット

| プラグイン | 説明 | キーマップ |
|-----------|------|-----------|
| **nvim-treesitter/nvim-treesitter** | 構文解析によるハイライト（多数の言語対応） | - |
| **stevearc/conform.nvim** | コードフォーマッター（保存時自動整形対応） | `<leader>i` フォーマット実行 |

---

## Git連携

| プラグイン | 説明 |
|-----------|------|
| **tpope/vim-fugitive** | Git操作（:Git コマンド） |
| **tpope/vim-rhubarb** | GitHubをブラウザで開く（:GBrowse） |
| **akinsho/git-conflict.nvim** | Gitコンフリクトのハイライト・解決支援 |

---

## AI・Copilot

| プラグイン | 説明 |
|-----------|------|
| **github/copilot.vim** | GitHub Copilot（AIコード補完） |
| **CopilotC-Nvim/CopilotChat.nvim** | Copilotとのチャット機能 |

---

## ウィンドウ操作

| プラグイン | 説明 |
|-----------|------|
| **simeji/winresizer** | ウィンドウサイズ調整（`<C-e>` で起動、hjklでリサイズ） |

---

## 主要キーマップまとめ

| キー | 動作 |
|------|------|
| `<leader>` | スペースキー |
| `<leader>e` | ファイルツリー開閉 |
| `<leader>p` | ファイル検索 |
| `<leader>g` | 文字列検索（grep） |
| `<leader>i` | コードフォーマット |
| `<leader>ca` | コードアクション |
| `<leader>?` | キーマップヘルプ表示 |
| `gd` | 定義へジャンプ |
| `gr` | 参照一覧 |
