# claude パッケージ

Claude Code の設定・スキル・CLIツールを管理するパッケージ。

## セットアップ

```bash
stow -d packages -t ~ -R claude
```

## claude-tmux

tmux × Claude Code の並列エージェント実行を自動化するCLIツール。
`~/.local/bin/claude-tmux` にリンクされる。

### サブコマンド

```bash
# ヘッドレスエージェントを起動
claude-tmux spawn "READMEを日本語に翻訳して" --name translate-readme

# 名前・作業ディレクトリを指定して起動
claude-tmux spawn "テストを追加" --name add-tests --dir ~/projects/myapp

# 複数のGitHub Issueを並列処理
claude-tmux issues 42 43 44

# 実行中のエージェント一覧
claude-tmux status

# ログをリアルタイム表示
claude-tmux logs translate-readme

# エージェントを停止
claude-tmux kill translate-readme
claude-tmux kill all
```

## スキル

| スキル | 種類 | 説明 |
|---|---|---|
| `/spawn-agents` | ユーザー実行 | タスクをサブタスクに分解し、並列エージェントを起動 |
| `/code-review` | ユーザー実行 / 自動 | 実装完了後にサブエージェントでコードレビュー |
| `dotfiles-structure` | 自動参照 | リポジトリ構造・stowの使い方をClaudeが自動参照 |

## tmux キーバインド

| キー | 動作 |
|---|---|
| `C-q a` | カレントディレクトリで新しいClaude Codeウィンドウを起動 |
