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

- **「試行済み」フラグを危険操作の前に立てると、途中の例外で中間状態が残り、以降黙ってフォールバックする**
  - 説明: 一度きりの初期化（ログイン・接続・トークン取得）を `_TRIED = True` で番人するとき、フラグをネットワークI/Oより前に立てると、想定外の例外（ConnectionError / Timeout / ライブラリ固有例外）で「成功でも失敗でもない」状態が残る。2回目以降の呼び出しは「試行済みでエラーも無い」と判断して None を返し、認証なしの経路へ黙って降格する。テストは想定した失敗（認証エラー）しか流さないので緑のまま通る。フラグは成否が確定してから（`finally` か成功/失敗の各分岐で）立てるか、想定外の例外も専用エラー型に包んで保存すること。
  - 例:
    ```python
    # NG: POST が ConnectionError で抜けると _TRIED だけ True になり、
    #     2回目以降は「試行済み・エラー無し」として None を返す
    def session():
        global _SESSION, _ERROR, _TRIED
        if _TRIED:
            if _ERROR: raise _ERROR
            return _SESSION
        _TRIED = True
        s = login()          # ここで想定外の例外が出ると中間状態が残る
        _SESSION = s
        return s

    # OK: 成否が確定してから立て、想定外の例外も専用型に包む
    def session():
        global _SESSION, _ERROR, _TRIED
        if _TRIED:
            if _ERROR: raise _ERROR
            return _SESSION
        try:
            s = login()
        except LoginError as ex:
            _ERROR = ex; raise
        except Exception as ex:
            _ERROR = LoginError(f"{type(ex).__name__}: {ex}")
            raise _ERROR from ex
        finally:
            _TRIED = True
        _SESSION = s
        return s
    ```

- **時刻フォーマットの精度を上げると、粗い精度が暗黙のガードになっていた集約が壊れる**
  - 説明: `%H:%M` を `%H:%M:%S` に変えるなど時刻文字列の精度を上げるとき、その文字列を dict のキーやグルーピングキーに使っている箇所を必ず洗う。粗い精度は「同じ分に2回実行しても1件に統合される」という重複排除として偶然機能していることがあり、精度を上げた瞬間に「N件以上あれば実行する」という下流の件数ガードが数秒差の連続実行で通ってしまう。フォーマット変更の動機（ソート順の一意化など）と、そのキーが使われている全箇所の意味は別物なので、列名・キー名の使用箇所を grep で全部確認すること。

- **追記専用CSVを読む側でキー重複を前提にしないと、merge で静かに二重計上される**
  - 説明: 収集スクリプトが `open(path, "a")` の追記のみで重複排除も冪等性ガードも持たない場合、同じ日付・同じIDを2回収集すると行が重複する。それを読む分析・検証側が `df.merge(..., on="id")` すると行数が掛け算になり、件数・発生率・回収率がすべて倍化するが、**比率は偶然もっともらしい値になるため気づけない**。書く側を冪等にしたうえで、読む側も `drop_duplicates(key, keep="last")` を入れるか merge 前後の行数一致を確認すること。

- **`sort_values().drop_duplicates(keep="last")` は非安定ソートなのでキーが同値だと任意の行が残る**
  - 説明: 「レースごと・ユーザーごとの最新1行を取る」定型として `df.sort_values(ts).drop_duplicates(key, keep="last")` が使われるが、`sort_values` の既定 kind は "quicksort" で非安定。タイムスタンプが分単位・日単位などの粗い解像度だと同値が普通に発生し、追記順で後ろにある正しい行ではなく古い行が残ることがある。同値が無い間はテストも実データも通るため気づけない。`kind="stable"` を明示するか、秒精度のタイムスタンプを持たせること。

### セキュリティ・認証
- **認証の成否を「失敗マーカーの有無」だけで判定すると、相手側のHTML変更で成功が失敗に化ける**
  - 説明: スクレイピングの自動ログインで「レスポンスにログインフォーム（`name="password"` 等）が残っていたら失敗」という negative check だけを使うと、相手サイトがログイン後もヘッダにフォームを残す作りに変わった瞬間、成功しているのに全実行が異常終了する。とくに「アカウントロック回避のため再試行しない」設計と組み合わさると、コードを直すまで完全に動かなくなる。判定は positive signal（発行されたセッションCookie名、ログアウトリンク、マイページ要素）を主にし、negative check は補助に回す。加えて誤判定時にコード修正なしで回避できる環境変数フラグを用意する。

- **認証状態を「設定値の有無」で判定し、実際に成功したかを検証しないまま表示・分岐する**
  - 説明: 環境変数やファイルの存在だけを見て「認証済み」と表示する関数は、資格情報が誤っていても成功時と同じ表示になる。実際の認証処理が別の場所（遅延実行・例外握り潰しの内側）で失敗していると、ユーザーは正常動作だと信じたまま劣化したデータを蓄積する。判定は「認証処理の戻り値」を使うか、それが遅延実行なら表示文言を「設定値」であると分かる語（例:「認証設定:」）に変える。あわせて、資格情報を使う最初の呼び出しを起動直後に置いて fail-fast させると、長時間バッチの終了後に初めて気づく事態を防げる。

- **認証失敗時に別経路へ自動フォールバックすると、認証が壊れていることに気づけない**
  - 説明: 「ID/パスワードで失敗したら Cookie を使う」のような降格は、可用性のつもりで劣化を隠す。とくに取得データの品質が認証状態で変わる場合（有料項目・全件/一部）、壊れたまま走り続けて劣化データが蓄積する。別経路は「主経路を設定しない場合の選択肢」に留め、主経路の失敗時は止める。ドキュメントの「代替手段」という表現も実挙動に合わせること。

- **Slack に流す外部由来テキストの無害化が `<!channel>` / `<!here>` / `<!everyone>` だけで、ユーザーグループへのメンションが漏れる**
  - 説明: LLM の出力やログ由来の文字列を Slack に投稿するとき、`<!subteam^ID>` 形式のユーザーグループへのメンションが残ると特定チームに通知が飛ぶ。`<!` で始まる制御シーケンスをまとめて扱い、無害なもの（`<!date^...>` など）だけを残す形にする

### ライブラリ固有（requests）
- **`session.cookies[name]` は同名Cookieが複数あると `CookieConflictError` を投げる**
  - 説明: `RequestsCookieJar.__getitem__` は `_find_no_duplicates` を通るため、同名Cookieが複数の domain / path に存在すると `CookieConflictError`（`RuntimeError` 派生で `KeyError` ではない）を送出する。リダイレクトを伴うログインでは、同名Cookieが親ドメインとサブドメインの両方に付くことが実際にある。なお `name in session.cookies` は requests 2.34.2 では `RequestsCookieJar` 独自の `__contains__` があり例外にならないが、バージョンを固定していないなら `any(c.name == NAME for c in session.cookies)` と書くのが版に依存せず安全。
  - 例:
    ```python
    # NG: 同名Cookieが複数ドメインに付くと例外
    if session.cookies[AUTH_COOKIE]:
        ...

    # OK: 版に依存しない
    if any(c.name == AUTH_COOKIE for c in session.cookies):
        ...
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
- **分母の違う順位を平均・混在させない**
  - 説明: 「Aがある馬の中の順位（1..k_a）」と「Bがある馬の中の順位（1..k_b）」をそのまま平均したり、片方だけの馬と同じ列で並べ直したりすると、被覆が少ない側の馬が系統的に前（上位）へ寄る。平均する前に順位を割合（r/k）へそろえ、被覆率で分けて検証する。発見: 2026-11-10 keiba lane_forecast.combined_front_back_ranks の code-review。
  - 例:
    ```python
    # NG: 履歴3頭の中の1位(1) と 全12頭の中の12位 を平均 → 6.5 で、E だけの7位より前に来る
    val = (rank_a[m] + rank_e[m]) / 2

    # OK: 分母でそろえてから平均する
    val = ((rank_a[m] - 0.5) / k_a + (rank_e[m] - 0.5) / k_e) / 2
    ```

### ML 配信
- **保存済みモデルの特徴量リストで推論列を選ぶ**
  - 説明: 学習時に `--drop` などで列を外して保存できる場合、配信側が定数の特徴量リスト全体を Booster に渡すと、列数が合わずに落ちる（API が 500）。保存したメタ情報（`features`）で列を選び直し、無い列名があれば「版が違う」として予測を出さない。学習スクリプトの `apply()` が列を選んでいるなら配信も同じにする（2026-11-10 keiba `lane_serve.py` の code-review）。

### DB マイグレーション
- **スキーマ初期化で、後から ALTER で足す列に張るインデックスを ALTER より前に置く**
  - 説明: `CREATE TABLE IF NOT EXISTS` と `CREATE INDEX` を並べた初期化リストの後で `add_column_if_not_exists` を流す構成では、後から足した列にインデックスを張ると、列の無い古い DB で「no such column」になり接続そのものが失敗する。列を足す ALTER の後に置く。本番 PG の大きな表（keiba の horse_results は130万行）では初回接続の中で普通の `CREATE INDEX` を流さず、事前に `CREATE INDEX CONCURRENTLY IF NOT EXISTS` で作っておき、コードの DDL は no-op にする（複数ワーカーの同時起動で作成が競合することもある）。2026-11-09 keiba `idx_hr_date_rno` の code-review で発覚。

### SQL・データ取得
- **SQL での事前絞り込みが、Python 側の代替照合（fallback）で必要になる行まで落としている**
  - 説明: 主キー（例: レース番号）で WHERE を絞り、欠けている行だけ別キー（例: レース名）で照合する二段構えにすると、`col IN (主キーの集合) OR col IS NULL` の絞り込みが代替経路の相手の行（別の番号を持つ）も落とす。代替経路が要る入力があるときは絞り込みを外すか、別クエリで引く。テストの入力が1件だけだと絞り込み条件が空になって通ってしまうので、主キーを持つ行と持たない行を同じ呼び出しに混ぜたケースで確かめる（2026-11-09 keiba `card.graded_beaten` の code-review 3回目）。

### データ結合
- **レースを (日付, 場, レース名) で識別すると、同日・同場の同名レースが衝突する**
  - 説明: 「未勝利」「1勝クラス」のような条件名だけのレースは、同じ日・同じ場で複数走る（2025/10/12 東京の「2歳未勝利」は3鞍）。対戦相手の突き合わせや集計のキーに名前を使うと別レースの馬が混ざり、数が水増しされる。キーには `race_number` や `race_id` のような一意の列を使い、無い行だけ名前で代替する。テストには「同日・同場・同名・別レース」のケースを入れる（2026-11-09 keiba `card.graded_beaten` の code-review で発覚）。
  - 例:
    ```python
    # NG: 同じ日・同じ場の「2歳未勝利」3鞍が1つのレースに見える
    key = (race_date, venue, race_name)

    # OK: レース番号で識別し、番号が無い行（0.15%）だけ名前で代替する
    key = (race_date, venue, race_number) if race_number else (race_date, venue, None, race_name)
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

- **main() に実環境のファイルを読む新しいチェックを足すと、既存の main 系テストが環境依存になる**
  - 説明: CLI の `main()` に `~/.xxx` の成果物（鮮度や有無）を見る警告を足して終了コードに乗せると、その関数を差し替えていない既存テストの `assert main() == 0` が、開発機に成果物があるときだけ通る状態になる。CI・新しい環境・成果物が古くなった日に初めて落ちる。チェックを足したら、main を呼ぶ全テストで同種の関数（既存の `_artifact_built_at` 差し替えなど）と同じように monkeypatch（autouse fixture が楽）しているかを grep で確かめ、`HOME` を差し替えて1回実行して確認する（2026-11-10 keiba `check_ledger_milestone` の code-review）。

- **「モジュールの `_connect` だけを差し替える fixture」は、別モジュールから直接 import した DB 関数には効かない**
  - 説明: テストが `monkeypatch.setattr(ptm, "_connect", ...)` で DB を一時ファイルに向けていても、`from keiba.infra.db.races import load_odds_snapshots` のように直接 import した関数は、元のモジュールの `_connect` で本物の DB を開く。本番コードにこの種の関数呼び出しを足すと、差し替えていない既存テストは開発機に本物の DB があるときだけ通り、CI・サンドボックス・新しい環境で初めて落ちる。足したら、共通の fixture で既定値（空の結果）に差し替え、HOME を一時ディレクトリにして1回実行して確かめる。発見: 2026-11-11 keiba paper_trade_model2 `_scratched`。既存の「`~/.xxx` の成果物チェックを main に足す」項目と同じ型だが、こちらは DB アクセスの経路が違う。

- **パッチをタプルで返すヘルパーに要素を足したら、添字で開いている箇所も直す**
  - 説明: `_patches()` のようにパッチのタプルを返すヘルパーに要素を足しても、`with ps[0], ps[1], …` と添字で一部だけ開くテストには新しいパッチが掛からず、本物の DB や台帳ファイルを読みに行く。パッチは ExitStack などでまとめて開くヘルパーに一本化し、添字で開くのをやめる。発見: 2026-11-10 keiba tests/test_formation_api.py の code-review。
  - 例:
    ```python
    # NG: 後から足した ps[7]〜ps[9] が掛からない
    ps = _patches()
    with ps[0], ps[1], ps[2]:
        body = client.get(URL)

    # OK: 全部まとめて開くヘルパーに一本化する
    def _get(**kw):
        with ExitStack() as st:
            for p in _patches(**kw):
                st.enter_context(p)
            return client.get(URL)
    ```

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

### 互換性
- **`X | None` の型注釈は Python 3.9 では import 時に TypeError になる**
  - 説明: 関数シグネチャの注釈は定義時に評価されるため、PEP 604 の union 構文は 3.10 未満でモジュールの読み込み自体を失敗させる。CI は新しい Python で通るのに、macOS 標準の python3（3.9）でのローカル実行やテストだけが落ちる
  - 対策: `from __future__ import annotations` を入れるか、対応バージョンを明記する

### ファイル I/O
- **アトミック書き込みの tmp を固定名にしない**
  - 説明: `path.with_suffix(".tmp")` のような固定名の tmp → os.replace は、複数のプロセスやスレッドが同時に書くと、同じ inode への書き込みが混ざって壊れる。後から replace した側は FileNotFoundError になる。`tempfile.mkstemp(dir=同じディレクトリ)` で一意の名前にし、失敗したら unlink する。発見: 2026-11-11 keiba api/model2.py `_save_gap_flags` の code-review。

### ドメイン（競馬の清算）
- **「着順に無い＝取消」と判定しない**
  - 説明: finishing_order には競走中止と失格の馬も載らない（着順を int にできた行だけ残す）。返還の対象は取消・除外だけで、中止はハズレになる。取消かどうかは発走前の最後のオッズ（JRA 公式は取消馬をオッズから落とす）にキーがあるかで見分ける。発見: 2026-11-11 keiba paper_trade_model2 reconcile の code-review。

### パフォーマンス
- **ループ内での文字列連結**
  - 説明: `+=` での文字列連結は非効率。`''.join()` を使うべき

- **複雑すぎるリスト内包表記**
  - 説明: 可読性を損なう複雑な内包表記は通常のループに書き直すべき

### アーキテクチャ
- **スクリプトとAPIでビジネスロジックが重複していないか**
  - 説明: スクリプト（scripts/）とAPI（api.py）で同じビジネスロジックを個別に実装すると、差異が生まれて異なる結果を返す原因になる。共通ロジックは専用モジュール（例: analyzer.py）に集約し、スクリプト・APIの両方からそれを呼ぶこと。過去にscrape_historical.pyとapi.pyで予測ロジックが重複し、スクリプト側でオッズの戻り値を捨ててDB経由で読み直す冗長な経路を通っていたため、APIと異なる結果（推奨0件）になる事故が発生した。

### 並行処理

- **FastAPI の同期 def ハンドラで、モジュール変数を読んで判定してから書く制限処理にロックが無い**
  - 説明: FastAPI の同期 `def` エンドポイントはスレッドプールで並列に動く。モジュールのグローバル変数で「前回時刻を読む → 判定 → 書く」という間隔制限や重複防止を書くと、同時に来たリクエストが両方とも判定を通る。読む処理と書く処理の間に I/O があるとすき間はさらに広がる。`threading.Lock` の中で判定と書き込みを続けて行うこと。逐次で呼ぶ単体テストでは見つからない。発見: 2026-11-21 keiba api/races.py `tyb_now` の code-review。

## 参考資料
- [PEP 8 – Style Guide for Python Code](https://peps.python.org/pep-0008/)
- [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html)
