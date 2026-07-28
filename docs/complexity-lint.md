# 複雑度リント

「差分を読まなくても壊れない」ための機械的な上限。バグ検出ではなく**読めない関数を作らせない**ことが目的。

## 仕組み

`packages/claude/.claude/hooks/post-edit-check.sh`（PostToolUse フック）が、Claude がファイルを編集した直後に実行する。

- **Go** — `golangci-lint`。リポジトリに `.golangci.yml` があればそれを、無ければ共有設定 `~/.claude/lint/golangci-complexity.yml` を使う
- **TS/JS** — 共有設定 `~/.claude/lint/eslint-complexity.mjs` を**常に**実行する。加えてリポジトリ側の ESLint 設定 + `node_modules/.bin/eslint` が揃っていればそれも実行する（repo 固有ルール担当）

いずれも**ブロックしない**。検出内容は `additionalContext` でモデルに返り、その場で自己修正させる。パッケージ単位で走る Go 側は、編集したファイル以外の既存債務を出力から捨てる（無関係な指摘でノイズを出さないため）。30秒でタイムアウトし、超過時は黙って諦める。

## 共有設定の閾値

`packages/claude/.claude/lint/golangci-complexity.yml`

| linter | 閾値 |
|---|---|
| `funlen` | 60行 / 40ステートメント |
| `gocyclo`（循環的複雑度） | 20 |
| `gocognit`（認知的複雑度） | 15 |
| `nestif`（ネストの深さ） | 4 |
| `dupl`（重複） | 150トークン |

テストファイルは `funlen` / `dupl` / `gocognit` の対象外（表形式テストは長く重複するのが正常なため）。

## TS/JS 共有設定（専用 lint 環境）

`packages/claude/.claude/lint/` に ESLint と `@typescript-eslint/parser` を専用インストールしている。**対象リポジトリの `node_modules` に依存しない**ため、依存を入れていない新規リポジトリでも初日から効く。

```
packages/claude/.claude/lint/
├── package.json           # eslint + @typescript-eslint/parser + typescript
├── package-lock.json      # コミットする（node_modules は gitignore）
├── eslint-complexity.mjs  # 共有の複雑度ルール
└── golangci-complexity.yml
```

| ルール | 閾値 |
|---|---|
| `max-lines-per-function` | 60行（コメント・空行除く） |
| `complexity` | 20 |
| `max-depth` | 4 |
| `max-nested-callbacks` | 4 |

`*.test.*` / `*.spec.*` / `__tests__` / `test(s)/` は `max-lines-per-function` と `max-nested-callbacks` の対象外。

フックは `--no-config-lookup --config <共有設定>` で呼ぶため、リポジトリ側の ESLint 設定とは干渉しない。両方に複雑度ルールがあると同じ指摘が二重に出るので、リポジトリ側に書くのは複雑度**以外**のルールにする。

`--no-inline-config` を付けている。共有環境に入っていないプラグイン（`react-hooks` など）向けの `eslint-disable` コメントが「Definition for rule was not found」という誤検知になるため。副作用として、複雑度ルールをインラインコメントで抑止することもできない（記事の「インライン `eslint-disable` を許さない」方針と一致する）。例外を認めるなら共有設定側に書く。

セットアップは `install` スクリプトの `npm ci` で行う。依存を更新するときは:

```bash
cd packages/claude/.claude/lint && npm update && npm audit
```

認知的複雑度（`sonarjs/cognitive-complexity`）が要る場合は、この専用環境に `eslint-plugin-sonarjs` を足す。

## 運用: 既存債務は凍結し、新規分だけ止める

このフックは**編集したファイルの指摘しか返さない**。Go はパッケージ単位で走るため他ファイルの指摘を出力から捨て、TS/JS は編集ファイル1件だけを ESLint に渡す。

つまり既存の違反は普段は表示されず、そのファイルを触ったときだけ出る。既存債務を凍結して新規分だけ止めている状態なので、**導入時に既存違反をゼロにする作業（drain）は要らない**。

### drain / ratchet が必要になるとき

記事の「drain してから ratchet」は、リポジトリ全体を毎回見る CI を前提にした手順。

| 用語 | 意味 |
|---|---|
| drain | 既存の違反を分割・整理してゼロにする |
| ratchet | ゼロにした状態を `error` に引き上げて固定する（逆回転しない歯車） |

順番が逆だと層が死ぬ。既存違反を残したまま `error` にすると CI が最初から赤くなり、「既存分だから無視でいい」という判断が常態化して新規の違反も一緒に無視される。だから **CI に載せる段階で初めて** drain → ratchet を行う。

CI を使わない現状ではこの手順は不要。CI に載せるなら:

1. 対象リポジトリの違反数を数える（下記コマンド）
2. ゼロにする（drain）
3. リポジトリ側の設定で `error` に上げ、CI に載せる（ratchet）

新規リポジトリは違反ゼロから始まるので、最初から `error` でよい。

### 現状の違反数を数える

```bash
# TS/JS
~/.claude/lint/node_modules/.bin/eslint --no-config-lookup \
  --config ~/.claude/lint/eslint-complexity.mjs --no-inline-config \
  --no-error-on-unmatched-pattern "src/**/*.{ts,tsx,js,jsx}"

# Go
golangci-lint run -c ~/.claude/lint/golangci-complexity.yml \
  --max-issues-per-linter 0 --max-same-issues 0 ./...
```

ビルド生成物やベンダリングされたバンドルを拾うと桁が変わるので、ソースディレクトリを明示して数える。
