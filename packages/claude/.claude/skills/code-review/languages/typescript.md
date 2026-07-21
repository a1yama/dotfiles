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

- **非同期イベントハンドラで await を挟んだ後に closure 由来の state で setState すると更新を取りこぼす**
  - 説明: async ハンドラ内で await(確認ダイアログ・fetch 等) を挟んでから、レンダー時に捕捉した state 変数を基に setState(newValue)(非関数型更新)すると、await 中に他の更新で変化した最新 state を上書きして変更を失う恐れがある。await をまたぐ更新は必ず関数型更新 setState(prev => ...) にするか、更新に必要な値を await 前に確定させる

- **コントロールド数値入力で「範囲外なら早期return」すると途中入力・クリアができなくなる**
  - 説明: input type=number の value を state 由来の値にバインドしつつ onChange で範囲外・空文字を早期 return して setState しないと、React が入力を元の値へ巻き戻すため、ユーザーが数字を1桁ずつ組み立てたり一旦クリアしたりできなくなる(スピナーのみ機能)。入力中は文字列をそのまま保持し、onBlur/Enter でクランプ確定するか、途中値・空文字を許容して確定時のみ検証する

- **条件付き disabled な要素への autoFocus はフォーカスが当たらずダイアログの Escape 閉じが壊れる**
  - 説明: モーダルの初期フォーカスを「状況により disabled になりうる先頭要素」に置くと、disabled 時にブラウザがフォーカスを付与せず、オーバーレイの onKeyDown にイベントがバブルしないため Escape での閉鎖が効かなくなる。初期フォーカスは常時有効な要素に置くか、オーバーレイ自体に tabIndex を付与する

### 描画・画像処理
- **画像をCanvas/PDF/imgへ貼るとき幅と高さに別々の縮尺を使うと縦横比が崩れる**
  - 説明: `addImage(url, 'PNG', x, y, W, H)` のような貼り込みで、Wを固定値(コンテナ幅)・Hを別の係数で算出すると、元画像の実寸(widthScale等で可変)と縮尺が食い違い、片方向だけ潰れて中身(音符・図形)が伸縮して見える。縦横比を保つには W・H に必ず同一のスケール係数を掛ける。貼り込み先の実際の描画幅(canvas.width/pixelRatio)から縮尺を決めるのが安全

### 状態管理(reducer)
- **コンテキスト切替アクションで関連stateをリセットし忘れる**
  - 説明: setActivePartのような「対象切替」アクションで、切替対象に依存するサブ状態(例: activeStaff)をリセット/クランプせず持ち越すと、新対象で不正な既定値や不正なフィールド付与が起き、データ破損につながる。切替時は対象に整合するよう関連stateを明示的に正規化する

## データモデル・シリアライズ

- **向き依存パラメータを常に始点へ格納すると外部フォーマットで意味が反転する**
  - 説明: ヘアピンのspreadのように「向きによって始点/終点どちらの値か」が変わる属性を、内部モデルの都合で一律に始点イベントへ持たせて MusicXML 等へ出力すると、crescendo/diminuendoの一方で仕様と逆の意味になり外部ツールで誤描画される。内部ラウンドトリップが通っても外部相互運用は別途検証し、向きに応じて出力先(start/stop)を切り替える

- **関連付けの「親」フラグを外す際に付随データを消し忘れると孤児フィールドが残り再利用時に復活する**
  - 説明: wedgeStartを外すのにwedgeSpreadを残すように、開始マーカーをundefinedにしても付随パラメータをクリアしないと、同じ要素に機能を張り直したとき古い値が予期せず甦る。マーカー解除時は依存フィールドも一括で初期化する

## 参考資料
- [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/intro.html)
- [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html)
- [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript)
