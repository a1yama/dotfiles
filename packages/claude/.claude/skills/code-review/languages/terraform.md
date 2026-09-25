# Terraform レビューチェックリスト

## よくあるミス

### セキュリティ
- **`lifecycle.ignore_changes` は state への平文保存を止めない**
  - 説明: `ignore_changes` は plan の差分計算から外すだけで、refresh / import は実機の値をそのまま state に書き込む。実機に平文の環境変数として載っている秘密値は、ignore_changes の有無に関わらず tfstate に平文で残る。バケットに versioning が効いていれば後から消しても過去バージョンから読める
  - 例:
    ```hcl
    # NG: 「Terraform に値を持たせないから安全」は成り立たない
    env {
      name  = "CANARY_PASSWORD"
      value = var.canary_password  # 既定値は空。実値はワークフローが設定
    }
    lifecycle {
      ignore_changes = [template[0].template[0].containers[0].env]
    }

    # OK: 参照型に寄せる。state に載るのはシークレット名だけ
    env {
      name = "CANARY_PASSWORD"
      value_source {
        secret_key_ref {
          secret  = "canary-password"
          version = "latest"
        }
      }
    }
    ```
  - 対策: 秘密値は `secret_key_ref` などの参照型へ寄せる。即時に難しければ state バケットの IAM をシークレット閲覧者と同等まで絞り、「tfstate は機密」と README に明記する

### バグ・ロジックエラー
- **`count` で gate したリソースを `import` ブロックの対象にしている**
  - 説明: `count = var.flag ? 1 : 0` のリソースに対する `import { to = res[0] }` は、flag が false のとき対象インスタンスが存在せず plan がエラーで止まる。さらに import 済みの state で flag を false にすると「管理外にする」ではなく **destroy が計画される**。公開アクセス(`allUsers` への `roles/run.invoker`)や IAM バインディングをこの形で gate すると、フラグ1つで本番障害になる
  - 例:
    ```hcl
    # NG: manage_iam = false が「IAM を触らない」ではなく「IAM を消す」になる
    resource "google_cloud_run_v2_service_iam_member" "invoker" {
      count  = var.manage_iam ? 1 : 0
      member = "allUsers"
      role   = "roles/run.invoker"
    }
    import {
      to = google_cloud_run_v2_service_iam_member.invoker[0]
      id = "projects/…/services/… roles/run.invoker allUsers"
    }
    ```
  - 対策: 管理から外したいだけなら `terraform state rm` / `removed` ブロック / `-target` を使う。可用性に効くバインディングを bool フラグでぶら下げない

### 一貫性
- **既存のフラグに後から別責務を足していないか**
  - 説明: 既存の bool 変数(例 `manage_iam`)に新しいリソースをぶら下げると、変数の description や README が説明している影響範囲と実際の影響範囲がずれる。「Cloud SQL 用の逃げ道」として作られたフラグが、いつの間にか本番 Cloud Run の公開アクセスまで握っている、という形で事故になる
  - 対策: 新しい責務には新しい変数を割り当てる。既存フラグを再利用するなら description と README を同じコミットで追随させる

### 保守性
- **`.terraform.lock.hcl` を env ごとにコミットしているか**
  - 説明: CI で `terraform init` を回す構成では、lock ファイルが無いと `~> x.y` の解決結果が CI と各人のローカルでずれる。provider のマイナー更新で plan が変わっても誰も気づけない。`.gitignore` に `.terraform.lock.hcl` が入っているリポジトリでは、env ディレクトリを新設しても lock が入らないまま気づかれない
  - 対策: 各 env の `.terraform.lock.hcl` をコミットし、`.gitignore` の該当行を外す。新しい env ディレクトリを追加したら lock ファイルも一緒にコミットする

### コメント・ドキュメント
- **import 済みの実態とコメントが矛盾していないか**
  - 説明: import は「まず取り込まない方針を書く → 調査して取り込む」の順で進むため、`# --- 未取り込み ---` のような見出しの直下に import ブロックが並ぶ状態が残りやすい。次に触る人が「まだ state に無い」と誤認して二重 import や誤った判断をする
  - 対策: `imports.tf` は最後に読み直し、見出しと文言を取り込み済みの実態に合わせる
