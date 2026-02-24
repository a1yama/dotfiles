# Python レビューチェックリスト

## よくあるミス

### デフォルト引数
- **可変デフォルト引数**
  - 説明: `def func(items=[]):` のように可変オブジェクトをデフォルト引数にすると、呼び出し間で共有される
  - 例:
    ```python
    def add_item(item, items=[]):  # NG
        items.append(item)
        return items

    # 正しくは
    def add_item(item, items=None):  # OK
        if items is None:
            items = []
        items.append(item)
        return items
    ```

### 例外処理
- **広すぎる except**
  - 説明: `except Exception:` や `except:` で全ての例外を捕捉してしまう

- **リソースのクローズ忘れ**
  - 説明: `with` ステートメント（context manager）を使うべき

### スコープ・変数
- **グローバル変数の多用**
  - 説明: 不必要にグローバルスコープを使用している

### パフォーマンス
- **ループ内での文字列連結**
  - 説明: `+=` での文字列連結は非効率。`''.join()` を使うべき

- **複雑すぎるリスト内包表記**
  - 説明: 可読性を損なう複雑な内包表記は通常のループに書き直すべき

## 参考資料
- [PEP 8 – Style Guide for Python Code](https://peps.python.org/pep-0008/)
- [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html)
