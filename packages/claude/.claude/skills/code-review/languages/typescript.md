# TypeScript/JavaScript レビューチェックリスト

## よくあるミス

### 型安全性
- **`any` の多用**
  - 説明: 型安全性を失う原因となる。`unknown` や具体的な型を使うべき

- **型アサーション（`as`）の乱用**
  - 説明: 型の安全性を無視することになる。型ガードを使うべき

### 非同期処理
- **Promise の unhandled rejection**
  - 説明: async 関数の呼び出しで `.catch()` や try-catch が不足している

- **async/await の誤用**
  - 説明: 並列実行可能な処理を await で直列実行している

### null/undefined
- **null/undefined チェックの欠如**
  - 説明: Optional chaining（`?.`）や Nullish coalescing（`??`）を活用すべき

### React 固有
- **useEffect の依存配列の不備**
  - 説明: 依存する値が配列に含まれていない、または不要な値が含まれている

- **key prop の欠如**
  - 説明: リスト要素に一意な key が設定されていない

## 参考資料
- [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/intro.html)
- [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html)
- [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript)
