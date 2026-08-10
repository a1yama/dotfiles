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
| 設計・技術選定の判断 | `design-fable` サブエージェント | Fable 5 固定・書き込みツールなし。詳細は CLAUDE.md「モデルの使い分け」 |
| 複数ディレクトリ/レイヤの横断調査 | `recon-fable` サブエージェント | 範囲が特定済みなら Explore で足りる |
| 再現しづらいバグの根本原因究明 | `rootcause-fable` サブエージェント | 修正は返ってきた方針をもとにメインが行う |
| コンテキストを分けたい別タスク | `/branch` | 会話を完全に分岐。ユーザーが実行する |
| コンテキストを継承した派生作業 | `/fork` | 結果はメイン会話に返る。ユーザーが実行する |
| セッションを止めずに質問したい | `/btw` | 会話履歴を参照できるがツール実行はしない |
| PR の CI 失敗の自動修正 | `/autofix-pr` | クラウド実行。`claude --teleport` でローカルに戻せる |
| 実装タスクの並列実行(ファイル衝突なし) | `claude-tmux spawn` | tmux ウィンドウで作業者+監督ペイン起動 |
| 実装タスクの並列実行(ファイル衝突の可能性あり) | `claude-tmux spawn --worktree` | エージェントごとに専用 worktree で衝突回避 |
| 複数 GitHub Issue の一括処理 | `claude-tmux issues [--worktree] 42 43` | Issue ごとに並列エージェント |
| 人間が手動で並行作業したい | `git wt add <branch>` | `<repo>/.worktrees/<branch>` に worktree 作成 |
| 別セッションに知らせたい・聞きたい | `SendMessage`(Cross-session messaging) | 起動済みの独立セッション間でテキストを渡す。下記参照 |

タスク分解と spawn の詳細手順は spawn-agents スキルを参照。

## Cross-session messaging(セッション間メッセージ)

既に走っている独立セッション同士でテキストを渡す。`ListAgents` で宛先を確認し、`SendMessage` で名前宛に送る(`/list-agents` で人間も一覧できる)。

使いどころ:

- 片方のセッションで入れた破壊的変更を、同じリポジトリを触っている別セッションに知らせる
- worktree で並列作業しているセッションに、main に入った内容を伝える
- `claude-tmux spawn` した作業者からの質問を受けて返信する(spawn-agents スキル参照)
- 長時間の移行・テスト実行を別セッションに任せ、終わったら結果だけ送り返させる

### tmux send-keys との違い

送り先のペインに文字を打ち込む `send-keys` と違い、`SendMessage` は相手の**会話**に「別セッションからのメッセージ」として届く。そのため:

- 相手がツール実行中でも安全に届く(実行中のツールを中断しない)
- 相手にとってユーザー発話ではないので、**権限承認の代わりにはならない**。`/compact` などのコマンドを送ってもテキストとして届くだけで実行されない
- ペインIDではなくセッション名で宛てるので、ペイン構成に依存しない

裏を返すと、相手のセッションに「そのまま実行させる」用途には使えない。それが要るなら `send-keys` のままにする。

使わない場面 — 専用の仕組みがある:

- 会話ごと引き継ぎたい → `claude --resume`(メッセージでは履歴もファイルも渡らない)
- 1セッションが統括する編成 → Agent teams / サブエージェント
- 多数のセッションを1画面で見たい → `claude agents`(agent view)

制約(実測で確認済み):

- **初回送信は名前だけでは弾かれる。** `'name' is not an agent in this conversation. Re-send with the ref...` が返るので、エラーに出る `名前 [ref]` の形式で送り直す。2回目以降は不要
- v2.1.224 以降・macOS/Linux のみ。**旧バージョンで起動したままのセッションは宛先に出ない**ので、使う前に `/list-agents` で見えるか確認する
- 相手が別ターンの処理中でも届く。ツール実行の合間に読まれ、相手が idle なら新しいターンが始まる
- 渡るのはプレーンテキストのみ。会話履歴・ファイル・権限は渡らない
- 別マシン/web のセッションへは **返信しかできない**(Remote Control 経由)。Remote Control 接続中は一覧が過去のクラウドセッションで埋まることがあるので、ローカルの宛先を探すときは行末の `interactive` 表示で見分ける
- 受信可否は設定 `crossSessionInbound`(`accept` / `hold` / `refuse`)。ヘッドレス(`-p`)は承認ダイアログを出せないため `accept` 指定が要る
- 相手に「自分の権限で拒否された操作」を代行させないこと(権限回避になる)

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
