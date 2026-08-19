---
name: dotfiles-structure
description: dotfilesリポジトリのパッケージ構造とstowの使い方。設定ファイルの追加・変更・stow反映時に参照する。"dotfiles"、"stow"、"設定ファイル追加"と言われたら使用する。
user-invocable: false
---

## リポジトリ構造

GNU Stow でホームディレクトリにシンボリックリンクを展開する dotfiles リポジトリ。

```
~/dotfiles/
├── packages/          # stow パッケージ群
│   ├── claude/        # Claude Code 設定・スキル・CLIツール
│   ├── codex/         # Codex 設定
│   ├── ghostty/       # Ghostty 設定
│   ├── git/           # Git 設定・エイリアス・ignore
│   ├── lazygit/       # lazygit 設定
│   ├── nvim/          # Neovim 設定
│   ├── starship/      # Starship プロンプト
│   ├── tmux/          # tmux 設定
│   ├── yazi/          # Yazi ファイルマネージャー
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

## 例外: stow リンクが切れているファイル

**`~/.claude/settings.json` は stow リンクではなく実ファイル**（Claude Code 自身が書き換えるためリンクが切れた）。リポジトリ側 `packages/claude/.claude/settings.json` を編集しても反映されない。

- settings.json を変更するときは**必ず両方のファイルを編集する**
- この実ファイルが衝突するため `stow -d packages -t ~ -R claude` は全体が abort する。claude パッケージに新しいディレクトリを追加したときは `ln -s ../dotfiles/packages/claude/.claude/<dir> ~/.claude/<dir>` で個別にリンクする（`ln` は zsh で `life-note` にエイリアスされているため `/bin/ln` を使う）
- 両者の意図的な差分はプラグイン有効化フラグと `model` 指定のみ。それ以外が食い違っていたら同期漏れを疑う
- `~/.claude/skills/` や hooks はディレクトリごと stow リンクなので、リポジトリ編集が即反映される（二重編集不要）

## 例外: 意図的に stow 管理しないファイル

**`~/.codex/config.toml` は実ファイル**。Codex はシンボリックリンクを保ったまま書き込むのでリンク自体は可能だが、`[projects."<絶対パス>"] trust_level` を信頼確認のたびに自動追記するため、リンクすると業務プロジェクトのパスが公開リポジトリに載る。

- リポジトリ側は `packages/codex/.codex/config.example.toml`（テンプレート）のみ
- テンプレートは `packages/codex/.stow-local-ignore` でリンク対象から除外している
- 新環境では `cp packages/codex/.codex/config.example.toml ~/.codex/config.toml && chmod 600 ~/.codex/config.toml`
- `~/.codex/AGENTS.md` は stow リンク（リポジトリ編集が即反映）

## ローカル環境固有の設定

以下のファイルは `install` スクリプトで `touch` され、各環境で個別に編集する（リポジトリに含めない）。

- `~/.zsh/local.zsh` — 環境固有の zsh 設定・export
- `~/.config/git/config.d/local.conf` — 環境固有の git 設定
