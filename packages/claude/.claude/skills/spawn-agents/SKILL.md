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
3. すべてのエージェントを起動した後、`claude-tmux status` で起動結果を確認し報告する

## 注意事項

- 各サブタスクの説明は、他のエージェントが単独で理解・実行できるよう十分に具体的に記述すること
- 依存関係があるタスクは直列化するのではなく、依存情報をプロンプトに含めること
- エージェントはインタラクティブモードでtmuxペイン分割実行される
- エージェントが質問する場合、監督エージェント（`/supervise`）が自動的に判断して回答する
- すべてのエージェント起動後、必要に応じて `/supervise` スキルを実行して質問に対応すること

## claude-tmux リファレンス

### サブコマンド

| コマンド | 説明 |
|---|---|
| `claude-tmux spawn "タスク説明" [--name NAME] [--dir DIR] [--no-review]` | 新しいtmuxペインでエージェントを起動 |
| `claude-tmux issues 42 43 44` | 複数のGitHub Issueを並列エージェントで処理 |
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
2. 監督が `/supervise` スキルまたは `claude-tmux supervise` で質問を分析・回答
3. エージェントが `/tmp/claude-agents/<name>/answer` から回答を読み取り続行

### 自動コードレビュー

- タスク完了後、エージェント自身がgit diffでコードレビューを実施
- `--no-review` でスキップ可能

## ユーザーの指示

$ARGUMENTS
