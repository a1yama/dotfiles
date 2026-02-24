# Rust レビューチェックリスト

## よくあるミス

### エラーハンドリング
- **unwrap/expect の多用**
  - 説明: 本番コードで `.unwrap()` や `.expect()` を多用するとパニックのリスクがある。`?` 演算子を使うべき

- **Result の無視**
  - 説明: `#[must_use]` 属性のついた Result を無視している

### 所有権・借用
- **不必要な clone()**
  - 説明: 借用で済むところで `.clone()` を使っている

- **借用チェッカーの回避**
  - 説明: `unsafe` や `Rc<RefCell<T>>` で借用チェッカーを回避しようとしている

### unsafe
- **正当な理由のない unsafe**
  - 説明: unsafe ブロックに明確なコメントがない、または安全な代替手段がある

- **不変条件の文書化不足**
  - 説明: unsafe コードの前提条件が明確に記述されていない

### ライフタイム
- **不必要な明示的ライフタイム**
  - 説明: コンパイラが推論できるライフタイムを明示的に書いている

- **'static の多用**
  - 説明: より短いライフタイムで済むところで 'static を使っている

### 並行性
- **Arc/Mutex の過剰使用**
  - 説明: データ構造の再設計で解決できる問題を Arc/Mutex で解決しようとしている

## 参考資料
- [The Rust Programming Language](https://doc.rust-lang.org/book/)
- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
