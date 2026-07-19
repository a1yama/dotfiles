---
name: parallel-dev
description: Claude Code での並列開発の手法選択ガイド。"並列開発"、"parallel"、"どの並列手法"と言われたら使用する。状況に応じてサブエージェント/fork/branch/spawn/worktree のどれを使うべきか判断する。
user-invocable: true
---

# 並列開発プレイブック

状況に応じて最適な並列化手法を選択し、ユーザーに提案または実行する。

## 手法選択ガイド

| 状況 | 手法 | 備考 |
|---|---|---|
| 調査・検索・読み取りの並列化 | サブエージェント(Agent ツール) | ネイティブ機能。メインのコンテキストを汚さない |
| コンテキストを分けたい別タスク | `/branch` | 会話を完全に分岐。ユーザーが実行する |
| コンテキストを継承した派生作業 | `/fork` | 結果はメイン会話に返る。ユーザーが実行する |
| セッションを止めずに質問したい | `/btw` | 会話履歴を参照できるがツール実行はしない |
| PR の CI 失敗の自動修正 | `/autofix-pr` | クラウド実行。`claude --teleport` でローカルに戻せる |
| 実装タスクの並列実行(ファイル衝突なし) | `claude-tmux spawn` | tmux ウィンドウで作業者+監督ペイン起動 |
| 実装タスクの並列実行(ファイル衝突の可能性あり) | `claude-tmux spawn --worktree` | エージェントごとに専用 worktree で衝突回避 |
| 複数 GitHub Issue の一括処理 | `claude-tmux issues [--worktree] 42 43` | Issue ごとに並列エージェント |
| 人間が手動で並行作業したい | `git wt add <branch>` | `<repo>/.worktrees/<branch>` に worktree 作成 |

タスク分解と spawn の詳細手順は spawn-agents スキルを参照。

## git worktree 運用(git-wt)

- `git wt add <branch> [base]` — worktree 作成。`.worktreeinclude` があれば記載パターンの未追跡ファイル(`.env` 等)を自動コピー
- `git wt list` / `git wt rm [branch] [--branch]` / `git wt clean`(マージ済みを一括削除)
- worktree の場所: `<repo>/.worktrees/<branch>`(グローバル gitignore 済み)

**`.worktreeinclude` の書き方**(リポジトリルートに配置):

```
.env
.env.*
```

gitignore されたファイルは新規 worktree に存在しないため、必要なものをここに列挙する。

## マージフロー(worktree 並列開発の後始末)

1. `git wt list` で worktree とブランチを確認
2. 各ブランチの diff を人間がレビュー
3. メインブランチへマージ
4. `git wt rm <branch>` または `git wt clean` で worktree を削除

## Remote Control(任意設定)

スマートフォンから claude.ai 経由でローカルセッションを操作する場合、PC のスリープを防ぐ必要がある:

```
sudo pmset -a disablesleep 1
```

※ システム全体のスリープを無効化する設定のため、ユーザーが手動で実行する(自動実行しない)。戻すときは `sudo pmset -a disablesleep 0`。
