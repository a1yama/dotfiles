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

- **条件付き disabled な要素への autoFocus はフォーカスが当たらずダイアログの Escape 閉じが壊れる**
  - 説明: モーダルの初期フォーカスを「状況により disabled になりうる先頭要素」に置くと、disabled 時にブラウザがフォーカスを付与せず、オーバーレイの onKeyDown にイベントがバブルしないため Escape での閉鎖が効かなくなる。初期フォーカスは常時有効な要素に置くか、オーバーレイ自体に tabIndex を付与する

### 描画・画像処理
- **画像をCanvas/PDF/imgへ貼るとき幅と高さに別々の縮尺を使うと縦横比が崩れる**
  - 説明: `addImage(url, 'PNG', x, y, W, H)` のような貼り込みで、Wを固定値(コンテナ幅)・Hを別の係数で算出すると、元画像の実寸(widthScale等で可変)と縮尺が食い違い、片方向だけ潰れて中身(音符・図形)が伸縮して見える。縦横比を保つには W・H に必ず同一のスケール係数を掛ける。貼り込み先の実際の描画幅(canvas.width/pixelRatio)から縮尺を決めるのが安全

### 状態管理(reducer)
- **コンテキスト切替アクションで関連stateをリセットし忘れる**
  - 説明: setActivePartのような「対象切替」アクションで、切替対象に依存するサブ状態(例: activeStaff)をリセット/クランプせず持ち越すと、新対象で不正な既定値や不正なフィールド付与が起き、データ破損につながる。切替時は対象に整合するよう関連stateを明示的に正規化する

## 参考資料
- [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/intro.html)
- [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html)
- [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript)
