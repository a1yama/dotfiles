# Go レビューチェックリスト

## よくあるミス

### 定数定義
- **iota を使った const の途中に新しい定数を追加**
  - 説明: iota で定義された定数の途中に新しい定数を追加すると、それ以降の定数の値が全てずれてしまう
  - 例:
    ```go
    const (
        StatusPending = iota  // 0
        StatusActive          // 1
        StatusNew             // 2 ← 新規追加
        StatusInactive        // 3 ← 元々2だったのが3に
        StatusCompleted       // 4 ← 元々3だったのが4に
    )
    ```
  - 対策: 新しい定数は末尾に追加するか、明示的に値を指定する

- **機能固有ファイルに汎用名のパッケージレベル const を置く**
  - 説明: Go の const/var/func はファイルスコープを持たずパッケージ全体で一意である必要がある。`dateFormat` や `defaultTimeout` のような汎用名を1機能のファイルに定義すると、同じパッケージの別ファイルが同名を定義した時点でコンパイルエラーになり、また既存の同名 const を意図せず使い回して意味の異なる値が適用される事故も起きる
  - 例:
    ```go
    // adapter/job/upsert_monthly_fee_billing_setting.go
    const dateFormat = "2006-01-02" // package job 全体を占める。他の29ファイルと衝突しうる

    const mfbDateFormat = "2006-01-02" // 機能接頭辞を付ける
    ```
  - 対策: パッケージ内で1つに絞れないなら機能接頭辞を付けるか、共有パッケージへ切り出す

### エラーハンドリング
- **エラーの無視（`_ = err`）**
  - 説明: エラーを意図的に無視している場合、コメントで理由を明記すべき

- **エラーのラップ不足**
  - 説明: `fmt.Errorf` で `%w` を使わずにエラー情報が失われる

- **共通エラーレスポンスが拾わない型でエラーを返して本文が unexpected_error に潰れる**
  - 説明: `adapter/webapi/error_response.go` の `newErrorResponse` は `perror.PError` と `werrors.InvalidArgument` しか本文に反映しない。`werrors.NotFoundErrorWith(err)` / `UnprocessableEntityErrorWith(err)` を素の error に対して使うと、HTTP ステータスは意図どおりでも本文は `{"code":"unexpected_error","message":"unexpected error"}` になる。さらに `renderErrorResponse` は 500 以外でも `datadog.SetErrorTag` を呼び `ext.Error=true` / `ManualKeep=true` を立てるため、想定内の 404/422 が APM の予期しないエラーとして強制サンプリングで積まれる
  - 対策: 新しいステータスコードを返す差分を見たら `werrors.XxxErrorWith(perror.NewPError(code, msg))` の形になっているかを確認する（既存例: `error/error.go` の `ErrNotFoundUser`、`ErrInsufficientAccountMoney`）
  - 例: PR #2512 `adapter/webapi/monthly_fee_invoice_pdf.go`。PDF 未生成の 422 も他サービスの 404 も、本文は同じ `unexpected_error` になり console が区別できない

### テスト

- **テナント分離を SQL の WHERE 句で担保したのに、テストがリポジトリモックだけ**
  - 説明: 「取得後に照合するのではなく検索条件に `service_id` を入れる」という設計は正しいが、その保証は WHERE 句1行に集約される。usecase / handler のテストで `FindByXxx` のモックに NotFound を返させても、条件が消えた回帰は検知できない
  - 対策: 検索条件に認可用のカラムを足す差分では、同じディレクトリの `*_integration_test.go`（実 PostgreSQL の suite）に「別テナントの id で NotFound」ケースが追加されているかを確認する。判定は「その条件を差分から削ってテストが落ちるか」
  - 例: PR #2512 `adapter/domainimpl/repository/monthly_fee_invoice.go` の `FindByIDAndServiceID`。`AND service_id = ?` を削除して全テストを回したが、統合テストを含めて全部緑のままだった

### 並行処理
- **goroutine リーク**
  - 説明: context のキャンセルや done チャネルでの適切な終了処理がない

- **defer のループ内使用**
  - 説明: ループ内で defer を使うとリソースがループ終了まで解放されない

### nil 処理
- **nil ポインタチェックの欠如**
  - 説明: ポインタや interface の nil チェックが不足している

### DI・コード生成
- **wire の provider を増減したのに inject.go と wire_gen.go が食い違う**
  - 説明: `cmd/*/inject.go` の provider set から `repository.NewXxx` を削除・追加した際、`wire_gen.go` は手編集ではなく再生成して整合させる。生成物側にだけ古い provider 呼び出しやローカル変数が残るとコンパイルは通るのに未使用の依存が生き続け、逆に inject.go だけ直して wire_gen.go が古いままだと実行時の依存が意図と食い違う
  - 対策: レビュー時は inject.go の差分行と wire_gen.go の差分行が1対1で対応しているかを見る。provider が不要になったら inject.go 側からも消す（wire は未使用 provider をエラーにする）

### 不要コード
- **機能削除時にテストとヘルパーの残骸を消し漏らす**
  - 説明: 本番コードから機能を削除しても、その機能のためだけに書かれたテスト・コメント・ヘルパー関数が残ることがある。残ると「まだこの処理をしている」という誤った仕様理解を招き、未使用のエクスポート関数が生き続ける
  - 対策: 削除 PR では grep で当該ヘルパーの呼び出し元を確認し、テストのみが参照している状態になっていないかを見る

### 可読性・保守性
- **定数を新設したのに同一ファイル内の同じリテラルが残る**
  - 説明: 日付フォーマット等のマジックリテラルを const に切り出す変更で、着手した1〜2箇所だけ置換して同ファイル内の残りがリテラルのまま、という中途半端な抽出が起きやすい
  - 対策: const を新設した差分を見たら、そのファイル（できれば同パッケージ）を同じリテラルで grep して取り残しが無いか確認する。取り残すなら抽出自体を見送る方が一貫する

### 数値・型変換
- **表示・帳票への詰め替えで float64 を int64 に素キャストして検算が崩れる**
  - 説明: DB が float64（numeric）で持つ単価・数量を、PDF や CSV など「受け取った側が数量×単価で検算する」出力に `int64(v)` で詰め替えると、小数分が黙って切り捨てられ、同時に出力する合計金額（DB 側で decimal 計算済み）と辻褄が合わなくなる。丸め誤差対策として `math.Round` を使っている箇所が同じファイルにあるのに、別の箇所だけ素キャスト、という不揃いになりやすい
  - 対策: 差分内の float から `int64(` / `int(` への変換を洗い出し、(1) 元の値が小数を取りうるか、(2) 出力先で他の値との整合が要求されるか を確認する。整数前提なら黙って切り捨てず、明示的にバリデーションしてエラーにする
  - 例: PR #2510 `usecase/store_monthly_fee_invoice_pdf.go` の `toInvoiceItem`。単価 27.5 円 × 10 件で明細金額 275 円なのに、請求書には「数量 10 / 単価 27 / 金額 275」と出て検算が合わない

### データ整合性
- **過去の証憑を再生成する処理でマスタの一部だけ Unscoped にして片手落ちになる**
  - 説明: 発行済みの請求書・帳票を後から組み立て直す処理では、参照するマスタが論理削除・名称変更されている可能性がある。片方（消費税マスタなど）だけ Unscoped 取得を用意し、他方（パートナー名・サービス名など）は通常スコープのままにすると、論理削除された瞬間に再生成が恒久的に失敗したり、発行時と異なる内容の証憑ができたりする
  - 対策: 「発行時点の値が要る」と説明されている参照が差分にあれば、同じ再生成パスで引く他のマスタ参照もすべて同じ扱い（スナップショット保存 or Unscoped）になっているかを確認する
  - 例: PR #2510。消費税マスタは Unscoped で引くのに宛名は通常スコープで、`disable-partner` が partners を論理削除すると PDF 再生成が NotFound で恒久失敗する

## 参考資料
- [Effective Go](https://go.dev/doc/effective_go)
- [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)
