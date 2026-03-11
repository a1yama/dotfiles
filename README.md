# dotfiles

## Installation

```bash
curl -o - https://raw.githubusercontent.com/a1yama/dotfiles/refs/heads/master/install | sh
```

## Packages

| パッケージ | 説明 |
|---|---|
| zsh | シェル設定。`packages/zsh/.zsh/local.zsh`に環境固有の設定を記載 |
| nvim | Neovim設定（lazy.nvim, LSP, copilot等） |
| tmux | ターミナルマルチプレクサ設定 |
| starship | プロンプトテーマ |
| git | gitconfig, global ignore |
| lazygit | lazygit設定 |
| yazi | ファイルマネージャ設定 |
| wezterm | ターミナルエミュレータ設定 |
| zellij | ターミナルマルチプレクサ設定 |
| claude | Claude Code設定（CLAUDE.md, skills等） |
| codex | Codex設定 |
| takt | TAKTピースエンジン設定 |
| life | lifeリポジトリ用ユーティリティ（後述） |

## stowの使い方

各パッケージの反映:
```bash
stow -d packages -t ~ <package-name>
```

全パッケージの反映:
```bash
for pkg in packages/*/; do stow -d packages -t ~ "$(basename "$pkg")"; done
```

## 注意: lifeパッケージ

`packages/life/`はプライベートリポジトリ（a1yama/life）が存在する前提のユーティリティです。

使用前に以下をクローンしてください:
```bash
ghq get git@github.com:a1yama/life.git
```

含まれるスクリプト:
- `life-memo` - ターミナルからワンライナーでメモを追記（AI整形付き）
- `life-issue` - lifeリポジトリのIssue操作
- `daily-reminder` - デイリーリマインダー
