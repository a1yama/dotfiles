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
- **エージェントからの質問は Cross-session messaging でこのセッションに直接届く。** ポーリングは不要で、届いたら `SendMessage` で同じ相手に返信する

## claude-tmux リファレンス

### サブコマンド

| コマンド | 説明 |
|---|---|
| `claude-tmux spawn "タスク説明" [--name NAME] [--dir DIR] [--no-review] [--worktree]` | 新しいtmuxペインでエージェントを起動 |
| `claude-tmux issues [--worktree] 42 43 44` | 複数のGitHub Issueを並列エージェントで処理 |
| `claude-tmux status` | spawn したエージェントのライフサイクル(running/completed 等)とペイン生存確認 |
| `claude-tmux agents` | tmux 上の全 Claude セッションの実行状態(busy/idle/blocked/unknown/dead)を一覧 |
| `claude-tmux wait <name> --until <idle\|blocked\|busy> [--timeout 秒]` | 目的の状態になるまでブロックして待つ |
| `claude-tmux kill [name\|all]` | エージェントペイン停止とディレクトリ削除 |
| `claude-tmux clean` | 完了/死亡したエージェントのディレクトリをクリーンアップ |

### 仕様

- エージェントディレクトリ: `/tmp/claude-agents/<name>/`
  - `pane-id`, `prompt`, `enhanced_prompt`, `status`, `review-result`
- ペイン分割: 左右分割（`-h`）、複数なら上下にも分割（`-v`）
- 実行モード: インタラクティブモード（tmuxセッション外ではエラー）

### 実行状態の監視（`agents` / `wait`）

`claude-tmux agents` が返す状態は2つの情報を合成している。

| 状態 | 意味 | 出どころ |
|---|---|---|
| `busy` | 実際に作業中 | harness のセッションレジストリ |
| `idle` | 手が空いている | 同上 |
| `blocked` | AskUserQuestion や許可待ちで**人間の入力を待っている** | フック(`agent-status.sh`) |
| `unknown` | 状態不明だがペインは生きている | レジストリに status が無い |
| `dead` | ペインが消滅した | tmux |

**harness の status は `busy` と `idle` の2値しか持たず、AskUserQuestion の回答待ちでも
`busy` を返す。** そのため「働いている」と「人を待っている」は `blocked` の重ね合わせ
でしか区別できない。`busy` を見て「作業中だから待とう」と判断してはいけない。

**制約: `spawn` した作業者(`claude -p`)は `status` を持たないため `unknown` になる。**
ペイン紐付けと `blocked` の検出は効くが、busy/idle の判定はできない。
作業者に対して `wait --until idle` は成立しないので、完了検知には従来どおり
`claude-tmux status` のライフサイクル(`completed`)か Cross-session messaging を使う。

### 質問のやりとり（Cross-session messaging）

1. `spawn` は起動元セッション名を `~/.claude/sessions/$CLAUDE_PID.json` から取得し、作業者のプロンプトに宛先として埋め込む
2. 作業者は判断に迷ったとき `SendMessage` でその名前宛に質問を送る。初回は名前だけだと確認を求めるエラーになり、`名前 [ref]` での再送が要る（プロンプトに手順を含めてある）
3. 質問は起動元セッションの会話にそのまま届く。`SendMessage` で返信すると作業者の会話に届く。作業者がツール実行中でも中断されない
4. 作業者は `claude -p --name <agent名> --settings '{"crossSessionInbound":"accept"}'` で起動される。`-p` セッションは承認ダイアログを出せないため、`accept` が無いと返信が hold されたまま届かない

起動元が Claude セッションでない（素の端末から `claude-tmux` を叩いた）場合は質問経路を渡さず、作業者は自律判断で進む。

**制約**: Cross-session messaging は Claude Code v2.1.224 以降・macOS/Linux のみ。旧バージョンで起動したままのセッションは宛先として見えない（`/list-agents` で確認できる）。

### 自動コードレビュー

- タスク完了後、エージェント自身がgit diffでコードレビューを実施
- `--no-review` でスキップ可能

### worktree モード(`--worktree`)

- エージェントごとに `<repo>/.worktrees/agent-<name>/` に専用 worktree(ブランチ `agent/<name>`)を作成して作業させる
- エージェントは完了時に変更をコミットする(push・マージはしない)
- 完了後、監督ペインが独立レビュアー(headless claude)で差分を外部レビューし、指摘があれば修正エージェントを自動再投入する(最大2周、`--no-review` で無効)。最終レビューは `/tmp/claude-agents/<name>/external-review` に保存される
- 完了後のフロー: `git wt list` で確認 → 人間がレビュー・マージ → `git wt rm`(マージ済みは `git wt clean` で一括削除)
- `kill` / `clean` では worktree は削除されない(マージ判断は人間が行う)

## ユーザーの指示

$ARGUMENTS
