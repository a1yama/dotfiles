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

## 参考資料
- [Effective Go](https://go.dev/doc/effective_go)
- [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)
