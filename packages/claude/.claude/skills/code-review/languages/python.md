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

- **下位関数の広い except で、呼び出し側の `except SpecificError` が到達不能になる**
  - 説明: 呼び出し側で `except RateLimitError: abort()` と書いても、呼び出し先が `except Exception: return None` で包んでいれば特定例外は永遠に飛んでこず、安全機構（即時中断・リトライ抑止）が黙って無効になる。テストで呼び出し先をモックして例外を投げると「動いているように見える」ため検出しにくい。特定例外を握り潰す層では `except SpecificError: raise` を先に置いて再送出すること。既存の同種経路と挙動が揃っているかも確認する。
  - 例:
    ```python
    # NG: 下位が全部飲むので、上位の except RateLimitError に到達しない
    def scrape(...):
        try:
            return fetch(url)
        except Exception as e:
            print(e)
            return None

    # OK: 特定例外だけ再送出する
    def scrape(...):
        try:
            return fetch(url)
        except RateLimitError:
            raise
        except Exception as e:
            print(e)
            return None
    ```

### スコープ・変数
- **グローバル変数の多用**
  - 説明: 不必要にグローバルスコープを使用している

### バグ・ロジックエラー
- **ゼロ除算ガードを移動したら、元の除算が先に評価されてガードが到達不能になる**
  - 説明: `x / (len(a) or 1)` のような暗黙ガードを外して別の行へ `if a else float("nan")` を移すとき、同じ空判定に依存する除算が先に実行される位置に残っていると、新ガードはデッドコードになり実際には ZeroDivisionError で落ちる。ガードは「その集合を最初に消費する箇所」に置くか、関数入口で早期リターン / raise して1か所に集約する。
  - 例:
    ```python
    # NG: recs が空だと 1行目で落ち、2行目の nan ガードは到達しない
    out[lab] = (dd, top1 / len(recs))
    mean = sum(dd) / len(dd) if dd else float("nan")

    # OK: 空集合の扱いを入口に集約する
    if not recs:
        raise ValueError("評価対象が0件（絞り込み条件を確認）")
    ```

### 定数・設定
- **「既存挙動を固定する定数」を実運用の起動引数・実データと突き合わせていない**
  - 説明: 後方互換のために既存の系列名やタグを据え置く定数を追加するとき、その値が実際の cron / launchd / シェルスクリプトの引数や既存データの実測値と一致しているかを必ず確認する。一致していないと、互換維持のための変更が逆に系列を分断する。テストが定数の値をそのまま assert しているだけだと回帰を検出できない。検証手段は「起動元スクリプト / plist の grep」「`git log -S` で該当引数の履歴」「実データ（台帳・DB）の値の集計」の3点。
  - 例:
    ```python
    # NG: 実際の起動は --near 40 なのに 30 を据え置き値にした
    _LEGACY_NEAR_MIN = 30  # → 次回実行から別タグになり既存系列が割れる

    # OK: 起動引数と一致させ、一致自体をテストで固定する
    _LEGACY_NEAR_MIN = 40  # scripts/raceday_paper_sweep.sh の --near 40 に由来
    ```

### テスト
- **設定ファイルやシェルスクリプトを正規表現で検証するテストが、コメント行に先にマッチして無効化される**
  - 説明: `re.search` は最初のマッチを返すため、同じ文字列がコメント・docstring・ヘルプ文にも書かれていると、検証したい実行行ではなくそちらを拾う。値がたまたま一致している間はテストが緑のまま通り続け、実行行だけ変更しても検出できない。コメント行を除去してから検索するか、実行対象（コマンド名・キー名）を含む形にアンカーすること。追加後は「実行行だけ変えるとテストが落ちるか」を実際に試して確認する。
  - 例:
    ```python
    # NG: ヘッダコメントの同じ文字列に先にマッチする
    m = re.search(r"--near\s+(\d+)\s+--snapshots", script_text)

    # OK: コメント行を落としてから探す
    body = "\n".join(ln for ln in script_text.splitlines()
                     if not ln.lstrip().startswith("#"))
    m = re.search(r"--near\s+(\d+)\s+--snapshots", body)
    ```

- **モジュールグローバルを直接代入して復元されない**
  - 説明: `db_mod.DB_PATH = tmp_path / "test.db"` のようにモジュール属性を直接書き換えると、テスト終了後に復元されず同一 pytest セッションの後続テストへ漏れる（削除済み tmp ディレクトリを指し続ける）。`monkeypatch.setattr(mod, "ATTR", value)` を使えば自動で復元される。引数に `monkeypatch` を宣言しながら使っていないテストは、この漏れのサイン。

### 実験・分析スクリプト
- **集計の出力ラベルが選択ロジックと一致していない**
  - 説明: 分析スクリプトは表の1行がそのまま意思決定の根拠になるため、ラベルの誤りはコードのバグと同等の害がある。「コメント・docstring・出力ラベル・実ロジック」の4点が同じことを言っているかを突き合わせる（コメントが正しくラベルだけ間違っている場合が多い）。併せて、比較軸ごとに母集団が変わる集計は共通集合を先に確定すること、欠損時の fallback 値が比較軸と相関しないことも確認する。
  - 例:
    ```python
    # NG: cutoff 以前の最新を採る（＝b分「以上前」）のにラベルは「以内」
    cand = [(ts, w) for ts, w in snaps if ts <= start - timedelta(minutes=b)]
    label = f"発走{b}分以内"

    # NG: bucket ごとに欠損で母集団が変わる／fallback が比較軸と相関する
    payout_sum += official_payout or odds_at_that_bucket * 100
    ```

### パフォーマンス
- **ループ内での文字列連結**
  - 説明: `+=` での文字列連結は非効率。`''.join()` を使うべき

- **複雑すぎるリスト内包表記**
  - 説明: 可読性を損なう複雑な内包表記は通常のループに書き直すべき

### アーキテクチャ
- **スクリプトとAPIでビジネスロジックが重複していないか**
  - 説明: スクリプト（scripts/）とAPI（api.py）で同じビジネスロジックを個別に実装すると、差異が生まれて異なる結果を返す原因になる。共通ロジックは専用モジュール（例: analyzer.py）に集約し、スクリプト・APIの両方からそれを呼ぶこと。過去にscrape_historical.pyとapi.pyで予測ロジックが重複し、スクリプト側でオッズの戻り値を捨ててDB経由で読み直す冗長な経路を通っていたため、APIと異なる結果（推奨0件）になる事故が発生した。

## 参考資料
- [PEP 8 – Style Guide for Python Code](https://peps.python.org/pep-0008/)
- [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html)
