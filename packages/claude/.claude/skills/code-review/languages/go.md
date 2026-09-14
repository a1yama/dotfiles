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

### 画像・バイナリ変換
- **透過 PNG をアルファ無しフォーマットへ変換すると透過部が黒に潰れる**
  - 説明: `image/draw` は乗算済みアルファを扱うため、`image.NewRGBA` の初期値 `(0,0,0,0)` に `draw.Over` で合成すると alpha = 0 の領域が `(0,0,0)` になる。これを RGB565 や RGB888 など alpha を持たない形式へ書き出すと、透過背景や白抜き部分が一律で黒になる。コンパイルもテストも通り、実機の表示を見るまで気づけない
  - 対策: 合成先を先に不透明色で塗ってから元画像を重ねる。レビュー時は、アルファ無し形式への変換コードで合成先キャンバスが初期化されているかを確認する
  - 例:
    ```go
    // NG: 初期値が透明（乗算済みで黒）のキャンバスに Over で合成
    dst := image.NewRGBA(image.Rect(0, 0, w, h))
    draw.ApproxBiLinear.Scale(dst, dst.Bounds(), src, src.Bounds(), draw.Over, nil)

    // OK: 背景を不透明色で塗ってから重ねる
    dst := image.NewRGBA(image.Rect(0, 0, w, h))
    draw.Draw(dst, dst.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)
    draw.ApproxBiLinear.Scale(dst, dst.Bounds(), src, src.Bounds(), draw.Over, nil)
    ```

### 組込み・TinyGo
- **移動平均や差分計算を符号なし整数で書くと減算のラップで巨大値になる**
  - 説明: `smoothed += (x - smoothed) / 4` のような指数移動平均・差分フィルタを `uint32` / `uint16` で書くと、入力が下降した瞬間に `x - smoothed` が 2^32 近傍にラップし、÷4 して約 1.07e9 という値が残り続ける。コンパイルもテストも通り、センサー値が上昇するケースだけ試すと気づけない
  - 対策: 中間計算を `int32` など符号付きにする。レビュー時は符号なし変数どうしの減算を探し、被減数が減数より小さくなり得るかを確認する
  - 例:
    ```go
    // NG: 値が下降すると (raw - smoothed) がラップする
    var smoothed uint32
    smoothed += (uint32(sensor.Get()) - smoothed) / 4 // 40000 -> 1000 で 1073772074

    // OK: 符号付きで計算する
    var smoothed int32
    smoothed += (int32(sensor.Get()) - smoothed) / 4 // 30250
    ```
- **ドライバが設定済みのピンを PWM や別機能として奪うとき、ドライバ側の参照箇所を全数確認していない**
  - 説明: `st7789` のように `Configure()` でバックライトピンを Output + High にするドライバの場合、その後 `machine.PWMx.Channel(pin)` で FUNCSEL を奪うのは動く。しかしドライバの他メソッド（`EnableBacklight` 等）が後から `pin.High()` / `pin.Low()` を呼ぶと PWM 設定が壊れる
  - 対策: ドライバのソースを当該ピンのフィールド名で grep し、参照が初期化系メソッドだけに閉じているかを確認する。呼んではいけないメソッドはコード側のコメントに明示する
- **RP2040 の PWM はスライス単位で周期を共有するのにピン割り当てで衝突を確認していない**
  - 説明: RP2040 の PWM スライス番号は `(gpio >> 1) & 7`、チャネルは `gpio & 1` で決まる。GPIO14 と GPIO15 のような隣接ピンは同一スライスになり TOP / DIV を共有するため、片方を 1kHz の調光、もう片方を 38kHz の赤外線搬送波のように使うことはできない
  - 対策: 新たに PWM 化したピンについてスライス番号を計算し、同一スライスの相方ピンが他の用途で PWM を使っていないかを確認する

## 参考資料
- [Effective Go](https://go.dev/doc/effective_go)
- [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)
