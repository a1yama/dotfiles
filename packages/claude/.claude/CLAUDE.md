# CLAUDE.md

## Conversation Guidelines

- 常に日本語で会話する
- タスクが完了したらsayコマンドで通知する
- 指示が曖昧だったり疑問があった場合にはそのまま作業に入らず質問をしてください。
  - 間違った認識のまま対応することを防ぐためです。
- 必要に応じてチームで対応してください。

## Coding Policy

## Git Commit Guidelines

- コミットメッセージは1行のみで簡潔に記述する
- 「🤖 Generated with Claude Code」の署名は追加しない
- 「Co-Authored-By: Claude」は追加しない
- コミットメッセージの形式: `git commit -m "簡潔なメッセージ"`
- 勝手にコミットしないこと

例:
```bash
git commit -m "fix: 認証情報を含むGitHub URLのパース処理を修正"
```

## Development Philosophy

- 独立したサブタスクが複数ある場合は、`claude-tmux spawn` で並列エージェントの活用を検討する

## claude-tmux

tmux内でClaude Codeのヘッドレスエージェントを並列実行するためのCLIツール。

### サブコマンド

| コマンド | 説明 |
|---|---|
| `claude-tmux spawn "タスク説明" [--name NAME] [--dir DIR]` | 新しいtmuxウィンドウでヘッドレスエージェントを起動 |
| `claude-tmux issues 42 43 44` | 複数のGitHub Issueを並列エージェントで処理 |
| `claude-tmux status` | 実行中のエージェント一覧と最新ログを表示 |
| `claude-tmux logs <name>` | 特定エージェントのログを `less` で表示 |
| `claude-tmux kill [name\|all]` | エージェントウィンドウを停止 |

### スキル

- `/spawn-agents タスクの説明` — タスクをサブタスクに分解し、`claude-tmux spawn` で並列エージェントを起動する

### tmux キーバインド

- `C-q a` — カレントディレクトリで新しいClaude Codeインタラクティブウィンドウを起動

### 仕様

- ログ出力先: `/tmp/claude-agents/<name>.log`
- ウィンドウ名: `🤖<name>` でtmux内で識別可能
- 完了時に macOS `say` で通知、`read` で待機
- tmuxセッション外での実行時はエラー
