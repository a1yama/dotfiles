# CLAUDE.md

## Conversation Guidelines

- 常に日本語で会話する
- タスクが完了したらsayコマンドで通知する
- 実装中に技術的に詰まったところやわからないところ、解決できないエラーなどがあればo3 mcpに英語で相談して。

## Coding Policy

- **すべてのコーディングタスクはcodex mcpを使用してcodexに任せてください（英語で指示）**
  - オプションとして、workspace には、 workspace-write をapproval-policy には、 never をつけて、Codex MCPを使用してください。
  - また、Codexに振るタスクは細分化して、細かく投げて、進捗を追いやすくしてください。
- バグ修正、機能追加、リファクタリング、テスト追加など、コード変更を伴うタスクすべて
- ファイルの読み取りのみの調査タスクは除く
- 例外: ユーザーが明示的に「直接修正して」と指示した場合のみ
- 迷った場合はcodex mcpを使うか直接対応するか、ユーザーに確認してください

## Git Commit Guidelines

- コミットメッセージは1行のみで簡潔に記述する
- 「🤖 Generated with Claude Code」の署名は追加しない
- 「Co-Authored-By: Claude」は追加しない
- コミットメッセージの形式: `git commit -m "簡潔なメッセージ"`

例:
```bash
git commit -m "fix: 認証情報を含むGitHub URLのパース処理を修正"
```

## Development Philosophy

