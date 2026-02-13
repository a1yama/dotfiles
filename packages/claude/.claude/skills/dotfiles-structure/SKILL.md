---
description: dotfilesリポジトリのパッケージ構造とstowの使い方。設定ファイルの追加・変更・stow反映時に参照する。
user-invocable: false
---

## リポジトリ構造

GNU Stow でホームディレクトリにシンボリックリンクを展開する dotfiles リポジトリ。

```
~/dotfiles/
├── packages/          # stow パッケージ群
│   ├── claude/        # Claude Code 設定・スキル・CLIツール
│   ├── codex/         # Codex 設定
│   ├── git/           # Git 設定・エイリアス・ignore
│   ├── lazygit/       # lazygit 設定
│   ├── nvim/          # Neovim 設定
│   ├── starship/      # Starship プロンプト
│   ├── tmux/          # tmux 設定
│   ├── wezterm/       # WezTerm 設定
│   ├── yazi/          # Yazi ファイルマネージャー
│   ├── zellij/        # Zellij 設定
│   └── zsh/           # Zsh 設定・エイリアス
├── install            # セットアップスクリプト
└── Brewfile           # Homebrew パッケージ一覧
```

## stow の使い方

パッケージのリンク先はホームディレクトリ。`-t ~` の指定が必須。

```bash
# 単一パッケージの反映
stow -d packages -t ~ -R <パッケージ名>

# 全パッケージの反映
stow -vd packages -t ~ $(ls packages)
```

`-d packages` と `-t ~` を省略すると正しくリンクされないので注意。

## パッケージ内のディレクトリ規約

パッケージ内のパスがそのままホームディレクトリからの相対パスになる。

| パッケージ内のパス | リンク先 |
|---|---|
| `packages/tmux/.tmux.conf` | `~/.tmux.conf` |
| `packages/nvim/.config/nvim/init.lua` | `~/.config/nvim/init.lua` |
| `packages/claude/.claude/skills/foo/SKILL.md` | `~/.claude/skills/foo/SKILL.md` |
| `packages/claude/.local/bin/claude-tmux` | `~/.local/bin/claude-tmux` |

## 新しい設定ファイルを追加するとき

1. 対応するパッケージの配下に、ホームディレクトリからの相対パスでファイルを配置する
2. `stow -d packages -t ~ -R <パッケージ名>` で反映する
3. 新しいツールの場合は `packages/<ツール名>/` にパッケージを新規作成する

## ローカル環境固有の設定

以下のファイルは `install` スクリプトで `touch` され、各環境で個別に編集する（リポジトリに含めない）。

- `~/.zsh/local.zsh` — 環境固有の zsh 設定・export
- `~/.config/git/config.d/local.conf` — 環境固有の git 設定
