---
name: skill-trigger-eval
description: 手元のスキルが実際に発火するか、別のスキルに横取りされていないかを `claude -p` を並列に走らせて実測する。「スキル評価」「スキルが発火しない」「トリガー精度を測りたい」「description を直したい」「スキルが呼ばれない」と言われたら必ず使う。スキルの description を書き換える前と後に必ず1回ずつ回すこと。SKILL.md を読んで良し悪しを推測するだけで済ませない（静的な予想は実測と食い違う。実例は下記「静的レビューは当てにならない」）。skill-creator の run_eval.py / run_loop.py は使わない（thinking モデルで全件 not-triggered になるバグがある。理由は下記）。スキルの新規作成そのものや SKILL.md 本文の設計には使わない。
user-invocable: true
---

# スキルのトリガー実測

`~/.claude/skills` のスキル群をそのまま載せた状態で `claude -p` を走らせ、
クエリごとに **どのスキルが発火したか** を記録する。

## 使い方

```bash
cd <このスキル>/scripts
python3 probe.py --eval-set ../evals/review.json --cwd /path/to/fixture --runs 3
```

出力は多数決で HIT / MISS を判定し、期待と違うスキルが取った回だけ tool 列を出す。

```
HIT  期待=code-review  発火={'code-review': 3}
MISS 期待=None  発火={'codebase-recon': 3}
     列: Skill
```

主なオプション。

| フラグ | 意味 |
|---|---|
| `--runs` | 1クエリあたりの実行回数（既定3。揺らぎを見るため2以上にする） |
| `--max-tools` | 何本目の tool まで見て打ち切るか（既定4） |
| `--cwd` | `claude -p` の作業ディレクトリ。fixture を指す |
| `--workers` | 並列数（既定6） |

## eval セットの書き方

```json
[
  {"expected": "code-review", "query": "今の差分、バグ入ってないか見てほしい"},
  {"expected": null,          "query": "この関数の意図を説明してほしい"}
]
```

`expected` に発火してほしいスキル名、発火してほしくないなら `null`。

- **クエリは具体的に書く。** 実在するファイルパス、仕事の背景、口語、typo を混ぜる。
  「文章を整えて」のような抽象的な一文は、実際のユーザーが打つ形ではないので測る意味がない
- **否定ケースは near-miss にする。** 語彙が重なるが別の手段を使うべき依頼を選ぶ。
  「フィボナッチ関数を書いて」のような明らかな無関係は何も検証していない
- **参照するファイルは必ず実在させる。** 存在しないパスを書くと Claude が探索に走り、
  スキルの良し悪しと無関係な MISS が出る（実際にこれで3件を誤検出した）

`evals/` に実測済みのセットがある。`scripts/make_fixture.sh` が対応する fixture を作る。

## 落とし穴

### 「最初の tool_use」で判定しない

`Bash → Skill` の順で発火する経路がある。最初の1本だけを見ると取りこぼす。
`--max-tools` 本まで見ること。

### 静的レビューは当てにならない

2026-09-04 の実測では、SKILL.md を読んで予想した「スキル同士の衝突」3組が
**すべて外れた**（108回中0件）。実際の問題は全部 undertrigger だった。
description を読んで直す前に、必ず測ってから直す。

### 押しを強めると誤発火が出る

「自力でできそうでも先に読め」と押すと発火率は上がるが、隣接する依頼まで吸う。
実測では codebase-recon がこれで「この関数の意図を説明して」まで取った。
**押しと否定条件（使わない場合）はセットで書く。** 片方だけ足して終わらせない。

### skill-creator の run_eval.py は使わない

`~/.claude/plugins/marketplaces/anthropic-agent-skills/skills/skill-creator/scripts/run_eval.py`
には2つの欠陥がある。

1. `elif event.get("type") == "assistant":` が、content に tool_use が無くても
   `return triggered`（False）で打ち切る。thinking を出すモデルでは thinking ブロックの
   assistant が tool_use の `content_block_start` より先に届くため、ほぼ全件が
   not-triggered になる
2. description だけ入れた偽のスラッシュコマンドを評価する。本物のスキルは
   同時にロードされたままなので、本物が勝つと not-triggered と数える。
   さらに発火/未発火の二値なので、どのスキルが横取りしたかが残らない

## テスト

パース部分は純粋関数に分けてある。プロセスを起動せずに走る。

```bash
python3 scripts/test_probe.py
```
