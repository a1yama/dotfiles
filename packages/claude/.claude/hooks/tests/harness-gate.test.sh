#!/bin/bash
# harness-gate(ハーネス改善ループの反映前検査)のテスト。`bash tests/harness-gate.test.sh` で実行する。
set -u
CLI="$(cd "$(dirname "$0")/../../.." && pwd)/.local/bin/harness-gate"
pass=0; fail=0
ok() { if [ "$2" = "1" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; fi; }
eq() { if [ "$1" = "$2" ]; then echo 1; else echo 0; fi; }
has() { case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }

# 呼び出し元が差し込んだ git の設定を持ち込まない。push を禁じた無人ループの中から実行されると、
# 一時リポジトリへの push まで失敗してテストが崩れる
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
for v in $(compgen -v | grep '^GIT_CONFIG_'); do unset "$v"; done

ROOTS=(); trap '[ "${#ROOTS[@]}" -gt 0 ] && rm -rf "${ROOTS[@]}"' EXIT
G() { git -C "$ROOT/repo" -c user.name=t -c user.email=t@example.com "$@"; }

# 公開済みの木(base)と、非公開の名前を持つ ghq、通るテスト1本を用意する
setup() {
  ROOT=$(mktemp -d); ROOTS+=("$ROOT")
  mkdir -p "$ROOT/repo/packages/claude/hooks" "$ROOT/repo/other" "$ROOT/tests" \
    "$ROOT/ghq/github.com/someowner/secretproj" "$ROOT/ghq/github.com/someowner/publicproj" \
    "$ROOT/ghq/github.com/someowner/abc"
  git init -q "$ROOT/repo"; G checkout -q -b master
  echo "publicproj は既に公開している" > "$ROOT/repo/packages/claude/README.md"
  echo x > "$ROOT/repo/other/file"
  G add . && G commit -q -m base
  printf '#!/bin/bash\nexit 0\n' > "$ROOT/tests/a.test.sh"
  : > "$ROOT/deny"
}
# 本物のテスト一式を呼ばない(このテスト自身を再帰で起動してしまう)
gate() {
  (cd "$ROOT/repo" && HARNESS_GATE_GHQ_ROOT="$ROOT/ghq" HARNESS_GATE_DENYLIST="$ROOT/deny" \
    HARNESS_GATE_TESTS_DIR="$ROOT/tests" "$CLI" --base master "$@" 2>&1)
}
add() { printf '%s\n' "$2" >> "$ROOT/repo/$1"; }

setup; add packages/claude/hooks/new.sh "echo 改善"
out=$(gate); rc=$?
ok "許可した範囲の変更でテストが通れば exit 0" "$(eq "$rc" 0)"
ok "未追跡の新規ファイルも変更として数える" "$(has "$out" "変更 1 ファイル")"

setup; out=$(gate); ok "変更が無ければ exit 1(空の通過を作らない)" "$(eq "$?" 1)"

setup; G checkout -q -b work; add packages/claude/hooks/new.sh "echo x"; G add . && G commit -q -m c
out=$(gate); ok "commit 済みの変更も base との差分として検査する" "$(eq "$?" 0)"
G checkout -q master; G checkout -q -b work2; add other/file "y"; G add . && G commit -q -m c2
out=$(gate); ok "commit 済みでも範囲の外なら exit 1" "$(eq "$?" 1)"

setup; add other/file "y"
out=$(gate); rc=$?
ok "範囲の外の変更は exit 1" "$(eq "$rc" 1)"
ok "範囲の外のファイルを知らせる" "$(has "$out" "許可した範囲の外: other/file")"

for f in packages/claude/.claude/settings.json packages/claude/.claude/settings.local.json \
         packages/claude/.claude/settings.json.bak-1 packages/claude/.config/claude-loop/denylist \
         packages/claude/.config/claude-loop/some.conf packages/claude/.claude/loops/harness-improve.md \
         packages/claude/.local/bin/harness-gate packages/claude/.local/bin/claude-loop \
         packages/claude/.claude/hooks/tests/harness-gate.test.sh; do
  setup; mkdir -p "$ROOT/repo/$(dirname "$f")"; add "$f" "{}"
  out=$(gate); rc=$? # 説明文の $(basename) が $? を上書きするので先に取る
  ok "触ってはいけないファイルは exit 1: $(basename "$f")" "$(eq "$rc" 1)"
done

leak() { # $1: 説明 / $2: 追加する行
  setup; add packages/claude/hooks/new.sh "$2"
  out=$(gate); ok "漏えいを止める: $1" "$(eq "$?" 1)"
}
# 検査の正規表現に当たる値を1行に書くと、このテスト自身が検査に掛かる。分けて組み立てる
SLACK_HOST="hooks.slack"; DISCORD_HOST="discord"; KEY_HEAD="sk"; GH_HEAD="ghp"; PEM="PRIVATE"
HOME_ROOT="/Users"
AT="@"
leak "Slack の webhook" "url=https://$SLACK_HOST.com/services/T00000000/B00000000/abcdefgh"
leak "Discord の webhook" "https://$DISCORD_HOST.com/api/webhooks/123456789012345678/token"
leak "API キー" "key=$KEY_HEAD-abcdefghijklmnopqrstuvwxyz012345"
leak "GitHub のトークン" "${GH_HEAD}_abcdefghijklmnopqrstuvwxyz0123"
leak "秘密鍵" "-----BEGIN OPENSSH $PEM KEY-----"
leak "メールアドレス" "連絡先は someone${AT}mail.invalidname.jp です"
leak "ホームディレクトリの絶対パス" "cd $HOME_ROOT/realname/work"
leak "ホームのパス(末尾が / でない)" "HOME=$HOME_ROOT/realname"
leak "ホームのパス(除外語に続きがある)" "cd $HOME_ROOT/user.real/x"
leak "ghq にある非公開のリポジトリ名" "SecretProj の作業で見つけた"
leak "ghq にある非公開の所有者名" "someowner の環境"

pass_line() { # $1: 説明 / $2: 追加する行
  setup; add packages/claude/hooks/new.sh "$2"
  out=$(gate); ok "誤検知しない: $1" "$(eq "$?" 0)"
}
pass_line "例示用のメールアドレス" "git -c user.email=t@example.com commit"
pass_line "git@ の接続先" "git clone git@github.com:owner/repo.git"
pass_line "既に公開している名前" "publicproj を参照する"
pass_line "短すぎる名前(誤検知の元)" "abc という文字列"
# shellcheck disable=SC2016 # 展開させずに文字のまま書き込む
pass_line "例示用のホームのパス" "cd $HOME_ROOT/you/work と $HOME_ROOT/<名前>/work"
pass_line "\$HOME を使ったパス" 'cd "$HOME/work" && ls ~/work'

setup; echo "社内コード名" > "$ROOT/deny"; add packages/claude/hooks/new.sh "社内コード名の件"
out=$(gate); rc=$?
ok "自分で書いた禁止語を止める" "$(eq "$rc" 1)"
ok "禁止語そのものを出力に写さない" "$(eq "$(has "$out" "社内コード名")" 0)"
setup; echo "publicproj" > "$ROOT/deny"; add packages/claude/hooks/new.sh "publicproj の件"
out=$(gate); ok "禁止語は既に公開済みの名前でも止める" "$(eq "$?" 1)"

setup; G checkout -q -b work; add packages/claude/hooks/new.sh "echo x"; G add . && G commit -q -m c
add packages/claude/hooks/new.sh "${GH_HEAD}_abcdefghijklmnopqrstuvwxyz0123"
out=$(gate); ok "commit 後に作業ツリーへ足した秘密の値も止める" "$(eq "$?" 1)"

# --- 差分の読み方: 内容が ++ で始まる行の後ろを取りこぼさない ---
setup; printf 'a\n' > "$ROOT/repo/packages/claude/hooks/t.sh"; G add . && G commit -q -m t
printf 'a\n++ x\n%s_abcdefghijklmnopqrstuvwxyz0123\n' "$GH_HEAD" > "$ROOT/repo/packages/claude/hooks/t.sh"
out=$(gate); ok "++ で始まる行の後ろにある秘密の値も止める(再発防止: 見出しと取り違えて以降を見逃した)" "$(eq "$?" 1)"
setup; printf 'a\n' > "$ROOT/repo/packages/claude/hooks/t.sh"; G add . && G commit -q -m t
G config diff.noprefix true
printf 'a\n%s_abcdefghijklmnopqrstuvwxyz0123\n' "$GH_HEAD" > "$ROOT/repo/packages/claude/hooks/t.sh"
out=$(gate); ok "diff.noprefix の設定があっても追加行を検査する" "$(eq "$?" 1)"

# --- リネームで禁止ファイルを範囲内の別名へ移しても通さない ---
setup; mkdir -p "$ROOT/repo/packages/claude/.claude"; echo '{}' > "$ROOT/repo/packages/claude/.claude/settings.json"
G add . && G commit -q -m s
G mv packages/claude/.claude/settings.json packages/claude/.claude/renamed.json
out=$(gate); ok "禁止ファイルのリネームを止める(変更前の名前も見る)" "$(eq "$?" 1)"

# --- テストを消して通すことはできない ---
setup; mkdir -p "$ROOT/repo/packages/claude/.claude/hooks/tests"
echo 'exit 0' > "$ROOT/repo/packages/claude/.claude/hooks/tests/some.test.sh"; G add . && G commit -q -m t
G rm -q packages/claude/.claude/hooks/tests/some.test.sh
out=$(gate); rc=$?
ok "テストの削除は exit 1" "$(eq "$rc" 1)"; ok "消したテストを知らせる" "$(has "$out" "テストを消しています")"
setup; mkdir -p "$ROOT/repo/packages/claude/.claude/hooks/tests"
echo 'exit 0' > "$ROOT/repo/packages/claude/.claude/hooks/tests/some.test.sh"; G add . && G commit -q -m t
G mv packages/claude/.claude/hooks/tests/some.test.sh packages/claude/.claude/hooks/tests/some.sh
out=$(gate); ok "テストのリネーム(実行対象から外す)も exit 1" "$(eq "$?" 1)"

setup; ln -s "$HOME_ROOT/realname/target.txt" "$ROOT/repo/packages/claude/hooks/link"
out=$(gate); ok "未追跡のシンボリックリンクは、リンク先のパス文字列を検査する" "$(eq "$?" 1)"
setup; ln -s ../README.md "$ROOT/repo/packages/claude/hooks/link"
out=$(gate); ok "問題の無いリンクは通す" "$(eq "$?" 0)"

setup; printf 'bin\0ary' > "$ROOT/repo/packages/claude/hooks/blob.bin"
out=$(gate); rc=$?
ok "未追跡のバイナリを止める" "$(eq "$rc" 1)"; ok "バイナリだと知らせる" "$(has "$out" "バイナリ")"
setup; printf 'x\n' > "$ROOT/repo/packages/claude/hooks/b.bin"; G add . && G commit -q -m b
printf 'bin\0ary' > "$ROOT/repo/packages/claude/hooks/b.bin"
out=$(gate); ok "追跡済みファイルがバイナリに変わったら止める" "$(eq "$?" 1)"

setup; for i in $(seq 1 12); do add packages/claude/hooks/new.sh "echo $i"; done
out=$(gate --max-lines 10); rc=$?
ok "変更が上限行数を超えたら exit 1" "$(eq "$rc" 1)"; ok "大きすぎると知らせる" "$(has "$out" "変更が大きすぎます")"
out=$(gate --max-lines 20); ok "上限以内なら通す" "$(eq "$?" 0)"

setup; add packages/claude/hooks/new.sh "echo x"
out=$(cd "$ROOT/repo" && HARNESS_GATE_GHQ_ROOT="$ROOT/no-ghq" HARNESS_GATE_DENYLIST="$ROOT/deny" \
  HARNESS_GATE_TESTS_DIR="$ROOT/tests" "$CLI" --base master 2>&1); rc=$?
ok "ghq のルートが無ければ exit 2(照合0件のまま通さない)" "$(eq "$rc" 2)"
out=$(cd "$ROOT/repo" && HARNESS_GATE_GHQ_ROOT="$ROOT/no-ghq" HARNESS_GATE_DENYLIST="$ROOT/deny" \
  HARNESS_GATE_TESTS_DIR="$ROOT/tests" "$CLI" --base master --no-ghq 2>&1); rc=$?
ok "--no-ghq を明示すれば照合を省いて通す" "$(eq "$rc" 0)"
out=$(gate); ok "照合した固有名の件数を出す" "$(has "$out" "照合した固有名 2 件")"

# --- push を禁じた環境から呼ばれても、テストにその設定を引き継がない ---
setup; add packages/claude/hooks/new.sh "echo x"
printf '#!/bin/bash\n[ -z "${GIT_CONFIG_COUNT:-}" ]\n' > "$ROOT/tests/env.test.sh"
out=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.pushurl GIT_CONFIG_VALUE_0=no-push://x/ gate); rc=$?
ok "git の設定の環境変数をテストに渡さない(再発防止: 無人ループの中で検査が必ず落ちた)" "$(eq "$rc" 0)"

setup; G checkout -q -b "fix-secretproj-hook"; add packages/claude/hooks/new.sh "echo x"
out=$(gate); rc=$?
ok "ブランチ名の非公開の固有名を止める" "$(eq "$rc" 1)"; ok "ブランチ名が原因だと知らせる" "$(has "$out" "(ブランチ名)")"
setup; add packages/claude/hooks/secretproj.sh "echo x"
out=$(gate); ok "ファイル名の非公開の固有名を止める" "$(eq "$?" 1)"
setup; G checkout -q -b work; add packages/claude/hooks/new.sh "echo x"; G add . && G commit -q -m "secretproj の件を直す"
out=$(gate); rc=$?
ok "コミットメッセージの非公開の固有名を止める" "$(eq "$rc" 1)"; ok "コミットメッセージが原因だと知らせる" "$(has "$out" "(コミットメッセージ)")"

setup; add packages/claude/hooks/new.sh "echo x"
printf '#!/bin/bash\necho "3 passed, 1 failed"\nexit 1\n' > "$ROOT/tests/b.test.sh"
out=$(gate); rc=$?
ok "テストが1本でも落ちれば exit 1" "$(eq "$rc" 1)"
ok "落ちたテストを知らせる" "$(has "$out" "b.test.sh")"
out=$(gate --skip-tests); rc=$?
ok "--skip-tests ならテストを回さずに範囲と漏えいだけ見る" "$(eq "$rc" 0)"
ok "テストを省略したことを出力に残す" "$(has "$out" "テストは省略")"

setup; add packages/claude/hooks/new.sh "echo x"; rm "$ROOT/tests/a.test.sh"
out=$(gate); ok "テストが1本も無ければ exit 2(検査できていないのに通さない)" "$(eq "$?" 2)"

setup; add packages/claude/hooks/new.sh "echo x"
out=$(cd "$ROOT/repo" && HARNESS_GATE_TESTS_DIR="$ROOT/tests" "$CLI" --base no-such-ref 2>&1)
ok "base が無ければ exit 2" "$(eq "$?" 2)"
out=$(cd "$ROOT" && "$CLI" --base master 2>&1); ok "git リポジトリの外では exit 2" "$(eq "$?" 2)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
