# PHP レビューチェックリスト

## よくあるミス

### セキュリティ
- **SQLインジェクション**
  - 説明: プリペアドステートメントを使わずに文字列連結でクエリを構築している

- **XSS（クロスサイトスクリプティング）**
  - 説明: `htmlspecialchars()` や `htmlentities()` でエスケープせずに出力している

### 型・比較
- **緩い比較（`==`）の使用**
  - 説明: 厳密な比較（`===`）を使うべき箇所で `==` を使っている

- **型宣言の欠如**
  - 説明: 関数の引数や戻り値に型宣言がない（PHP 7.0+）

### エラーハンドリング
- **例外の握りつぶし**
  - 説明: catch ブロックで何もしていない、またはログだけで適切な処理がない

### 配列・NULL
- **isset() と empty() の誤用**
  - 説明: 意図しない挙動（`empty("0")` は true）に注意

## 参考資料
- [PHP: The Right Way](https://phptherightway.com/)
- [PSR (PHP Standards Recommendations)](https://www.php-fig.org/psr/)
