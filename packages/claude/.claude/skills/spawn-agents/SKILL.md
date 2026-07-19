---
name: spawn-agents
description: タスクを並列サブタスクに分解し、claude-tmux spawnで複数エージェントを起動する。"並列で"、"エージェント起動"、"spawn"と言われたら使用する。
user-invocable: true
---

ユーザーの指示を分析し、並列実行可能なサブタスクに分解してください。

## 手順

1. 以下の指示内容を分析し、独立して並列実行できるサブタスクに分解する
2. 各サブタスクについて `claude-tmux spawn "タスクの説明" --name <適切な名前>` コマンドをBashツールで実行し、別エージェントを起動する
   - `--name` にはタスクを端的に表す英語のケバブケース名を付ける
   - 必要に応じて `--dir` で作業ディレクトリを指定する
   - **サブタスク同士が同じファイルを触る可能性がある場合は必ず `--worktree` を付ける**(エージェントごとに専用 git worktree + `agent/<name>` ブランチで作業させ、衝突を防ぐ)。読み取り専用・完全に独立したファイルのみを触るタスクだけ従来モードでよい
3. すべてのエージェントを起動した後、`claude-tmux status` で起動結果を確認し報告する

## 注意事項

- 各サブタスクの説明は、他のエージェントが単独で理解・実行できるよう十分に具体的に記述すること
- 依存関係があるタスクは直列化するのではなく、依存情報をプロンプトに含めること
- エージェントはインタラクティブモードでtmuxペイン分割実行される
- エージェントが質問する場合、`claude-tmux supervise` が質問を検知して回答を仲介する
- すべてのエージェント起動後、`claude-tmux questions` で質問の有無を定期確認し、必要に応じて `claude-tmux supervise` を実行して対応すること

## claude-tmux リファレンス

### サブコマンド

| コマンド | 説明 |
|---|---|
| `claude-tmux spawn "タスク説明" [--name NAME] [--dir DIR] [--no-review] [--worktree]` | 新しいtmuxペインでエージェントを起動 |
| `claude-tmux issues [--worktree] 42 43 44` | 複数のGitHub Issueを並列エージェントで処理 |
| `claude-tmux status` | 実行中のエージェント一覧とペイン生存確認 |
| `claude-tmux questions` | 質問待ちのエージェント一覧を表示 |
| `claude-tmux answer <name> <回答>` | 質問に回答 |
| `claude-tmux kill [name\|all]` | エージェントペイン停止とディレクトリ削除 |
| `claude-tmux clean` | 完了/死亡したエージェントのディレクトリをクリーンアップ |

### 仕様

- エージェントディレクトリ: `/tmp/claude-agents/<name>/`
  - `pane-id`, `prompt`, `question`, `answer`, `status`
- ペイン分割: 左右分割（`-h`）、複数なら上下にも分割（`-v`）
- 実行モード: インタラクティブモード（tmuxセッション外ではエラー）

### オーケストレーション（監督機能）

1. エージェントが `/tmp/claude-agents/<name>/question` に質問を書き込む
2. 監督が `claude-tmux supervise` で質問を分析・回答
3. エージェントが `/tmp/claude-agents/<name>/answer` から回答を読み取り続行

### 自動コードレビュー

- タスク完了後、エージェント自身がgit diffでコードレビューを実施
- `--no-review` でスキップ可能

### worktree モード(`--worktree`)

- エージェントごとに `<repo>/.worktrees/agent-<name>/` に専用 worktree(ブランチ `agent/<name>`)を作成して作業させる
- エージェントは完了時に変更をコミットする(push・マージはしない)
- 完了後のフロー: `git wt list` で確認 → 人間がレビュー・マージ → `git wt rm`(マージ済みは `git wt clean` で一括削除)
- `kill` / `clean` では worktree は削除されない(マージ判断は人間が行う)

## ユーザーの指示

$ARGUMENTS
