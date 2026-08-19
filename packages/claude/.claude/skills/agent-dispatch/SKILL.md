---
name: agent-dispatch
description: チーム機能(Agent/SendMessage/TaskUpdate)のハブセッションで、サブエージェントの idle 通知をまとめて処理し次のタスクを割り当てる。"エージェントに割り当て"、"次のタスクを配って"、"idle 通知の処理"と言われたら使用する。
user-invocable: true
---

# サブエージェント割当

idle 通知が来るたびにユーザーへ確認を挟むと、ハブセッションが通知さばきで埋まる。
通知は蓄積し、このスキルでまとめて処理する。

対象は Agent / SendMessage / TaskList などのチーム機能。tmux ペインでの並列実行は
spawn-agents スキル、手法選択は parallel-dev スキルを参照。

`claude-tmux spawn` で起動した作業者も Cross-session messaging でこのセッション宛に
質問を送ってくる。宛先は `ListAgents` に出る作業者名で、返信も `SendMessage` で行う。
チームのタスク管理下には無いため `TaskUpdate` の対象にはならない。

## 手順

1. **状況を集める**
   - `TaskList` で未着手・進行中・ブロック中のタスクを取得する
   - `claude-tmux agents` で tmux 上の各セッションの実行状態を見る。
     idle 通知の記憶に頼るより確実で、通知を取りこぼしていても現在値が取れる
   - 直近の idle 通知も併せて、手が空いているエージェント名を洗い出す

2. **依存の解けたタスクを1件だけ割り当てる**
   - ブロッカーが残っているタスクは割り当てない
   - `SendMessage` で該当エージェントに渡す。渡す内容は、そのエージェントが単独で完了できるだけの具体性を持たせる(対象ファイル、完了条件、参照すべき既存実装)
   - 1エージェントに複数タスクを同時に渡さない

3. **割当結果を記録する**
   - `TaskUpdate` で担当と状態を更新する。記録しないと次の割当で二重発注になる

4. **報告は最後に1回**
   - 割り当てられるタスクが無い場合、またはユーザーの判断が要るブロッカーがある場合のみ、まとめてユーザーに報告する
   - 個々の idle 通知ごとに報告しない

## 状態の読み方

`claude-tmux agents` の `blocked` は **AskUserQuestion や許可待ちで人間の入力を
待っている**状態。harness の `busy` は AskUserQuestion の回答待ちでも `busy` のままなので、
`busy` だけを見て「作業中だから触らない」と判断すると、人間を待っているエージェントを
放置することになる。**`blocked` を最優先で拾う。**

特定のエージェントの手が空くまで待ちたいときはポーリングを書かずに次を使う。

```bash
claude-tmux wait <name> --until blocked --timeout 600
```

ただし `spawn` した作業者(`claude -p`)は `status` を持たず `unknown` になる。
作業者の完了検知には `claude-tmux status` のライフサイクルか
Cross-session messaging を使う(詳細は spawn-agents スキル)。

## やらないこと

- 未完了タスクを埋めるためだけの新規タスク生成
- ブロッカーの解消をエージェントに丸投げすること(依存関係の判断はハブ側の責任)
- 割当のたびにユーザーへ確認を取ること

## ユーザーの指示

$ARGUMENTS
