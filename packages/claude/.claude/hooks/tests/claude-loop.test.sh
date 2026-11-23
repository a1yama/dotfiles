#!/bin/bash
# claude-loop の検証。`bash tests/claude-loop.test.sh` で実行する。
# claude / launchctl / hostname は PATH 先頭のスタブに差し替え、git は一時リポジトリで実物を使う。
set -u

CLI="$(cd "$(dirname "$0")/../../../.local/bin" && pwd)/claude-loop"
pass=0
fail=0

ok() {
  local desc="$1" cond="$2"
  if [ "$cond" = "1" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n' "$desc"
  fi
}
has() { if printf '%s' "$1" | grep -qF -e "$2"; then echo 1; else echo 0; fi; }
eq() { if [ "$1" = "$2" ]; then echo 1; else echo 0; fi; }

# 呼び出し元が差し込んだ git の設定を持ち込まない。push を禁じた無人ループの中から実行されると、
# 一時リポジトリへの push まで失敗してテストが崩れる
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
for v in $(compgen -v | grep '^GIT_CONFIG_'); do unset "$v"; done

ROOTS=()
cleanup() { [ "${#ROOTS[@]}" -gt 0 ] && rm -rf "${ROOTS[@]}"; return 0; }
trap cleanup EXIT

# サンドボックス: origin(bare) → 対話用 clone、スタブ、設定ディレクトリを作る
setup() {
  ROOT=$(mktemp -d)
  ROOTS+=("$ROOT")
  mkdir -p "$ROOT/bin" "$ROOT/conf" "$ROOT/state" "$ROOT/agents"
  git init -q --bare "$ROOT/origin.git"
  git clone -q "$ROOT/origin.git" "$ROOT/repo" 2>/dev/null
  (
    cd "$ROOT/repo" || exit 1
    git checkout -q -b main
    printf '.env\n' > .gitignore
    echo one > file.txt
    git add . && git -c user.name=t -c user.email=t@example.com commit -q -m init
    git push -q -u origin main
  )
  echo "SECRET=1" > "$ROOT/repo/.env"

  cat > "$ROOT/bin/hostname" <<'STUB'
#!/bin/bash
echo "${STUB_HOST:-loopbox}"
STUB
  # 呼ばれた引数と作業ディレクトリを記録する。STUB_CLAUDE_* で挙動を変える
  cat > "$ROOT/bin/claude" <<'STUB'
#!/bin/bash
{ echo "cwd=$PWD"; printf 'arg=%s\n' "$@"; echo "token=${CLAUDE_CODE_OAUTH_TOKEN:-none}"; } >> "$STUB_LOG"
[ -n "${STUB_CLAUDE_TOUCH:-}" ] && echo leftover > "$PWD/$STUB_CLAUDE_TOUCH"
if [ -n "${STUB_CLAUDE_COMMIT:-}" ]; then
  echo c > "$PWD/committed.txt"; git add committed.txt
  git -c user.name=t -c user.email=t@example.com commit -q -m "detached のまま積んだコミット"
fi
if [ -n "${STUB_CLAUDE_PUSH:-}" ]; then
  git checkout -q -b "${STUB_CLAUDE_BRANCH:-loop-branch}"
  echo p > "$PWD/pushed.txt"; git add pushed.txt
  git -c user.name=t -c user.email=t@example.com commit -q -m "push を試みるコミット"
  git push -q origin HEAD 2>/dev/null; echo "push_origin_rc=$?" >> "$STUB_LOG"
  git push -q "$STUB_CLAUDE_PUSH" HEAD 2>/dev/null; echo "push_url_rc=$?" >> "$STUB_LOG"
  git push -q "$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1]))' "$STUB_CLAUDE_PUSH")" HEAD 2>/dev/null; echo "push_rel_rc=$?" >> "$STUB_LOG"
  git -c remote.origin.pushurl= -c url.x.pushInsteadOf= push -q origin HEAD 2>/dev/null; echo "push_hook_rc=$?" >> "$STUB_LOG"
fi
[ -n "${STUB_CLAUDE_IGNORE_TERM:-}" ] && trap '' TERM
[ -n "${STUB_CLAUDE_SLEEP:-}" ] && sleep "$STUB_CLAUDE_SLEEP"
echo "claude の出力"
exit "${STUB_CLAUDE_RC:-0}"
STUB
  cat > "$ROOT/bin/launchctl" <<'STUB'
#!/bin/bash
echo "launchctl $*" >> "$STUB_LOG"
exit 0
STUB
  chmod +x "$ROOT/bin/"*
  export STUB_LOG="$ROOT/stub.log"
  : > "$STUB_LOG"
  unset STUB_CLAUDE_PUSH STUB_CLAUDE_BRANCH STUB_HOST STUB_CLAUDE_TOUCH STUB_CLAUDE_SLEEP STUB_CLAUDE_RC STUB_CLAUDE_COMMIT STUB_CLAUDE_IGNORE_TERM
  unset CLAUDE_SLACK_WEBHOOK_URL CLAUDE_DISCORD_WEBHOOK_URL CLAUDE_CODE_OAUTH_TOKEN
}

conf() { # $1: 名前 / 残り: 追加・上書きする行
  local name="$1"; shift
  {
    echo "REPO=$ROOT/repo"
    echo "PROMPT=手順書を実行してください"
    echo "HOST=loopbox"
    echo "HOUR=6"
    echo "MINUTE=40"
    printf '%s\n' "$@"
  } > "$ROOT/conf/$name.conf"
}

run_cli() {
  PATH="$ROOT/bin:$PATH" \
    CLAUDE_LOOP_CONF_DIR="$ROOT/conf" CLAUDE_LOOP_STATE_DIR="$ROOT/state" \
    CLAUDE_LOOP_LAUNCH_AGENTS_DIR="$ROOT/agents" CLAUDE_LOOP_SELF="/opt/bin/claude-loop" \
    CLAUDE_LOOP_KILL_GRACE_SEC=1 \
    bash "$CLI" "$@" 2>&1
}
status_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$ROOT/state/$1.last.json" 2>/dev/null; }

# --- 正常系: 専用 worktree で claude を起動する ---
setup; conf demo "LINKS=.env"
out=$(run_cli run demo); rc=$?
ok "正常終了で exit 0" "$(eq "$rc" 0)"
ok "PATH の先頭に置いた偽の claude が使われる(再発防止: 実行器の PATH 補正でテストから本物が起動した)" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 1)"
ok "標準入力は閉じて起動する" "$(has "$(cat "$ROOT"/state/logs/demo/*.log)" "claude の出力")"
ok "結果が ok で残る" "$(eq "$(status_of demo)" ok)"
ok "claude は専用 worktree の中で動く(対話用 clone ではない)" "$(has "$(cat "$STUB_LOG")" "cwd=$ROOT/state/worktrees/demo")"
ok "PROMPT を渡す" "$(has "$(cat "$STUB_LOG")" "arg=手順書を実行してください")"
ok "権限モードは auto" "$(has "$(cat "$STUB_LOG")" "arg=auto")"
ok "無人実行であることを追記する" "$(has "$(cat "$STUB_LOG")" "AskUserQuestion を使わず")"
ok "LINKS のファイルを対話用 clone から symlink する" "$([ -L "$ROOT/state/worktrees/demo/.env" ] && echo 1 || echo 0)"
ok "実行後にロックを外す" "$([ ! -e "$ROOT/state/demo.lock" ] && echo 1 || echo 0)"
ok "対話用 clone の作業ツリーは変えない" "$(eq "$(git -C "$ROOT/repo" status --porcelain)" "")"

# --- 2回目: origin の進みを取り込む ---
( cd "$ROOT/repo" && echo two > file.txt && git -c user.name=t -c user.email=t@example.com commit -q -am second && git push -q )
( cd "$ROOT/repo" && git reset -q --hard HEAD~1 ) # 対話用 clone が遅れていても origin から取る
out=$(run_cli run demo); rc=$?
ok "2回目も exit 0" "$(eq "$rc" 0)"
ok "毎回 BASE(origin/main)の最新から始める" "$(eq "$(cat "$ROOT/state/worktrees/demo/file.txt")" two)"

# --- 前回の変更が残っていたら止める(捨てない) ---
setup; conf demo
STUB_CLAUDE_TOUCH=leftover.txt run_cli run demo >/dev/null
: > "$STUB_LOG"
out=$(run_cli run demo); rc=$?
ok "残骸があれば exit 1" "$(eq "$rc" 1)"
ok "結果は prepare_failed" "$(eq "$(status_of demo)" prepare_failed)"
ok "残ったファイル名を出す" "$(has "$out" "leftover.txt")"
ok "残骸があるとき claude を起動しない" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 0)"
ok "残骸を消さない" "$([ -f "$ROOT/state/worktrees/demo/leftover.txt" ] && echo 1 || echo 0)"

# --- ブランチを切らずに積んだ未 push のコミットも残骸として止める ---
setup; conf demo
STUB_CLAUDE_COMMIT=1 run_cli run demo >/dev/null
: > "$STUB_LOG"
out=$(run_cli run demo); rc=$?
ok "detached HEAD に未 push のコミットがあれば exit 1" "$(eq "$rc" 1)"
ok "未 push のコミットがあると知らせる" "$(has "$out" "未 push のコミット")"
ok "未 push のコミットがあるとき claude を起動しない" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 0)"

# --- 必要なコマンドが無い環境は準備の失敗として記録する ---
# 補う PATH を空にして、どのマシンでも本物の claude が見つからない状態を作る。
# ここを環境まかせにすると、claude が標準の場所にあるマシンで本物が起動する
setup; conf demo
rm "$ROOT/bin/claude"
if PATH="$ROOT/bin:/usr/bin:/bin" command -v claude >/dev/null 2>&1; then
  ok "検査の前提: /usr/bin と /bin に claude が無いこと" 0
else
  out=$(PATH="$ROOT/bin:/usr/bin:/bin" CLAUDE_LOOP_EXTRA_PATH="" \
    CLAUDE_LOOP_CONF_DIR="$ROOT/conf" CLAUDE_LOOP_STATE_DIR="$ROOT/state" /bin/bash "$CLI" run demo 2>&1); rc=$?
  ok "claude が見つからなければ exit 1" "$(eq "$rc" 1)"
  ok "見つからないコマンド名を記録する" "$(has "$out" "コマンドが見つかりません: claude")"
  ok "結果は prepare_failed" "$(eq "$(status_of demo)" prepare_failed)"
fi

# --- LINKS の先が対話用 clone でなければ止める ---
setup; conf demo "LINKS=.env"
run_cli run demo >/dev/null
rm "$ROOT/state/worktrees/demo/.env"; echo "OLD=1" > "$ROOT/state/worktrees/demo/.env"
: > "$STUB_LOG"
out=$(run_cli run demo); rc=$?
ok "リンクが実ファイルに置き換わっていたら exit 1" "$(eq "$rc" 1)"
ok "置き換わったパスを知らせる" "$(has "$out" "LINKS の先が対話用 clone を指していません")"
ok "そのとき claude を起動しない" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 0)"

# --- 知らない引数では起動しない ---
setup; conf demo
out=$(run_cli run demo --dryrun); rc=$?
ok "--dryrun の打ち間違いはエラー" "$(has "$out" "不明な引数です")"
ok "打ち間違いで claude を起動しない" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 0)"
out=$(run_cli run demo --dry-run extra)
ok "余分な引数もエラー" "$(has "$out" "不明な引数です")"

# --- 準備の出力は Claude のログとは別に残る ---
setup; conf demo "SETUP=echo 準備の出力です"
run_cli run demo >/dev/null
ok "準備の出力が残る" "$(has "$(cat "$ROOT"/state/logs/demo/*.prepare.log)" "準備の出力です")"
ok "Claude のログは別ファイル" "$(has "$(cat "$ROOT"/state/logs/demo/*[0-9].log)" "claude の出力")"

# --- 実行中に外から止められたら、対象を止めてから結果を残す ---
setup; conf demo
STUB_CLAUDE_SLEEP=30 PATH="$ROOT/bin:$PATH" CLAUDE_LOOP_CONF_DIR="$ROOT/conf" CLAUDE_LOOP_STATE_DIR="$ROOT/state" \
  CLAUDE_LOOP_KILL_GRACE_SEC=2 bash "$CLI" run demo >/dev/null 2>&1 &
loop_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q '^cwd=' "$STUB_LOG" 2>/dev/null && break; /bin/sleep 0.5; done
kill -TERM "$loop_pid"; wait "$loop_pid" 2>/dev/null
ok "外から止められたら結果は interrupted" "$(eq "$(status_of demo)" interrupted)"
ok "止められたあとロックを外す" "$([ ! -e "$ROOT/state/demo.lock" ] && echo 1 || echo 0)"
ok "対象のプロセスを残さない" "$(eq "$(pgrep -f "$ROOT/bin/claude" | wc -l | tr -d ' ')" 0)"

# --- LINKS を張れなければ止める ---
setup; conf demo "LINKS=sub/secret.json"
mkdir -p "$ROOT/repo/sub"; echo '{}' > "$ROOT/repo/sub/secret.json"
out=$(run_cli run demo); rc=$?
ok "リンク先の親ディレクトリが無ければ exit 1" "$(eq "$rc" 1)"
ok "張れなかったパスを知らせる" "$(has "$out" "LINKS を張れません")"

# --- 通知用の env ファイル: 引用符と export を外して読む ---
setup; conf demo
cat > "$ROOT/bin/curl" <<'STUB'
#!/bin/bash
echo "curl ${*: -1}" >> "$STUB_LOG"
STUB
chmod +x "$ROOT/bin/curl"
printf 'export CLAUDE_SLACK_WEBHOOK_URL="https://hooks.example.test/a"  \r\nOTHER=x\n' > "$ROOT/conf/env"
STUB_CLAUDE_RC=3 run_cli run demo >/dev/null
ok "引用符と export を外した URL に通知する" "$(has "$(cat "$STUB_LOG")" "curl https://hooks.example.test/a")"

# --- 認証トークン: env ファイルにあれば claude に渡し、無ければ渡さない ---
setup; conf demo
run_cli run demo >/dev/null
ok "env ファイルが無ければトークンを渡さない" "$(has "$(cat "$STUB_LOG")" "token=none")"
setup; conf demo 'SETUP=printf "setup_token=%s\n" "${CLAUDE_CODE_OAUTH_TOKEN:-none}" >> "$STUB_LOG"'
printf "CLAUDE_CODE_OAUTH_TOKEN='dummy-token-for-test'\n" > "$ROOT/conf/env"
out=$(run_cli run demo)
ok "env ファイルのトークンを claude に渡す" "$(has "$(cat "$STUB_LOG")" "token=dummy-token-for-test")"
ok "準備コマンド(SETUP)にはトークンを渡さない(再発防止: 依存のスクリプトが長期トークンを読める)" "$(has "$(cat "$STUB_LOG")" "setup_token=none")"
ok "トークンを実行ログや出力に書かない" "$(eq "$(grep -rc 'dummy-token-for-test' "$ROOT/state" | grep -vc ':0$')$(has "$out" dummy-token-for-test)" 00)"

# --- NO_PUSH: Claude からの push を止める(origin 宛ても URL 直書きも) ---
setup; conf demo "NO_PUSH=1"
STUB_CLAUDE_PUSH="$ROOT/origin.git" run_cli run demo >/dev/null
ok "NO_PUSH=1 のテストで push を実際に試みている" "$(has "$(cat "$STUB_LOG")" "push_origin_rc=")"
ok "NO_PUSH=1 なら origin への push が失敗する" "$(eq "$(grep -c 'push_origin_rc=0' "$STUB_LOG")" 0)"
ok "NO_PUSH=1 なら URL 直書きの push も失敗する" "$(eq "$(grep -c 'push_url_rc=0' "$STUB_LOG")" 0)"
ok "NO_PUSH=1 なら相対パスへの push も失敗する" "$(eq "$(grep -c 'push_rel_rc=0' "$STUB_LOG")" 0)"
ok "NO_PUSH=1 なら宛先の書き換えを外されても pre-push で止まる" "$(eq "$(grep -c 'push_hook_rc=0' "$STUB_LOG")" 0)"
ok "NO_PUSH=1 のテストで4通りの push を試みている" "$(eq "$(grep -c '^push_.*_rc=' "$STUB_LOG")" 4)"
ok "NO_PUSH=1 なら origin にブランチが増えない" "$(eq "$(git -C "$ROOT/origin.git" branch --list loop-branch | wc -l | tr -d ' ')" 0)"
ok "NO_PUSH=1 なら gh を道具ごと禁じる" "$(has "$(cat "$STUB_LOG")" "arg=Bash(gh *)")"
ok "NO_PUSH=1 なら git push を道具ごと禁じる" "$(has "$(cat "$STUB_LOG")" "arg=Bash(git push *)")"
ok "NO_PUSH=1 なら MCP サーバを読み込まない" "$(has "$(cat "$STUB_LOG")" "arg=--strict-mcp-config")"
ok "NO_PUSH=1 なら push 禁止を Claude に伝える" "$(has "$(cat "$STUB_LOG")" "git push と PR の作成を禁じています")"
ok "commit はローカルのブランチに残る" "$(eq "$(git -C "$ROOT/repo" branch --list loop-branch | wc -l | tr -d ' ')" 1)"
out=$(run_cli run demo --dry-run); rc=$?
ok "ブランチに積んだ未 push のコミットは次回の準備を止めない" "$(eq "$rc" 0)"

# --- NO_PUSH の成果を届ける: 確認待ちのブランチを数えて結果と通知に出す ---
setup; conf demo "NO_PUSH=1"
cat > "$ROOT/bin/curl" <<'STUB'
#!/bin/bash
echo "curl-data $*" >> "$STUB_LOG"
STUB
chmod +x "$ROOT/bin/curl"
printf 'CLAUDE_SLACK_WEBHOOK_URL=https://hooks.example.test/a\n' > "$ROOT/conf/env"
run_cli run demo >/dev/null
ok "確認待ちが無ければ成功を通知しない" "$(eq "$(grep -c 'curl-data' "$STUB_LOG")" 0)"
ok "接頭辞を Claude に伝える" "$(has "$(cat "$STUB_LOG")" "loop-demo/")"
STUB_CLAUDE_BRANCH=loop-demo/20260101-x STUB_CLAUDE_PUSH="$ROOT/origin.git" run_cli run demo >/dev/null
ok "確認待ちのブランチ数を結果に残す" "$(has "$(cat "$ROOT/state/demo.last.json")" "確認待ちのブランチ 1本 (loop-demo/")"
ok "確認待ちがあれば成功でも通知する" "$(has "$(cat "$STUB_LOG")" "curl-data")"
ok "結果は ok のまま" "$(eq "$(status_of demo)" ok)"
# 未 merge のコミットを持たせる。merge 済みだと、接頭辞を見なくても数えから外れてしまう
( cd "$ROOT/repo" && git checkout -q -b other-work && echo o > other.txt && git add other.txt \
  && git -c user.name=t -c user.email=t@example.com commit -q -m other && git checkout -q main )
run_cli run demo --dry-run >/dev/null; : > "$STUB_LOG"; run_cli run demo >/dev/null
ok "接頭辞の違うブランチは数えない" "$(has "$(cat "$ROOT/state/demo.last.json")" "確認待ちのブランチ 1本 (loop-demo/")"

setup; conf demo
STUB_CLAUDE_PUSH="$ROOT/origin.git" run_cli run demo >/dev/null
ok "NO_PUSH が無ければ push できる(既定の挙動を変えない)" "$(has "$(cat "$STUB_LOG")" "push_origin_rc=0")"
ok "NO_PUSH が無ければ道具を禁じない" "$(eq "$(grep -c 'disallowedTools' "$STUB_LOG")" 0)"
ok "NO_PUSH が無ければ PR にするよう伝える" "$(has "$(cat "$STUB_LOG")" "ブランチを切って PR にしてください")"

setup; conf demo "NO_PUSH=1"
git -C "$ROOT/repo" config remote.origin.pushurl "$ROOT/origin.git"
out=$(run_cli run demo); rc=$?
ok "NO_PUSH=1 で origin に pushurl があれば起動しない(再発防止: 足した pushurl は既存の値を置き換えない)" "$(eq "$rc" 1)"
ok "pushurl が原因だと知らせる" "$(has "$out" "pushurl が設定されています")"
ok "そのとき claude を起動しない" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 0)"

setup; conf demo "NO_PUSH=yes"
out=$(run_cli run demo 2>&1); rc=$?
ok "NO_PUSH の不正な値は止める" "$(eq "$rc" 1)"

# --- LINKS の symlink は残骸として数えない(gitignore の書き方に依らず) ---
setup; conf demo "LINKS=untracked-link"
echo x > "$ROOT/repo/untracked-link"
run_cli run demo >/dev/null
out=$(run_cli run demo); rc=$?
ok "LINKS で張った管理外ファイルがあっても2回目が通る" "$(eq "$rc" 0)"
ok "張ったリンクは git から未追跡として見えない(再発防止: 無人実行がリンクをコミットに含めうる)" "$(eq "$(git -C "$ROOT/state/worktrees/demo" status --porcelain)" "")"
ok "除外の登録は重複させない" "$(eq "$(grep -c '^/untracked-link$' "$ROOT/repo/.git/info/exclude")" 1)"

# --- 失敗と時間切れ ---
setup; conf demo
out=$(STUB_CLAUDE_RC=3 run_cli run demo); rc=$?
ok "claude が失敗したら exit 1" "$(eq "$rc" 1)"
ok "結果は failed" "$(eq "$(status_of demo)" failed)"

setup; conf demo "TIMEOUT_MIN=1"
# 60秒待たずに確かめるため、sleep をスタブして時間切れを即時に起こす
cat > "$ROOT/bin/sleep" <<'STUB'
#!/bin/bash
[ "$1" = "60" ] && exit 0
exec /bin/sleep "$@"
STUB
chmod +x "$ROOT/bin/sleep"
out=$(STUB_CLAUDE_SLEEP=5 run_cli run demo); rc=$?
ok "時間切れで exit 1" "$(eq "$rc" 1)"
ok "結果は timeout" "$(eq "$(status_of demo)" timeout)"

# TERM を無視する相手も、猶予のあと強制終了して戻ってくる(戻らないとロックを握り続ける)
setup; conf demo "TIMEOUT_MIN=1"
cp "${ROOTS[${#ROOTS[@]}-2]}/bin/sleep" "$ROOT/bin/sleep"
start=$(date +%s)
out=$(STUB_CLAUDE_IGNORE_TERM=1 STUB_CLAUDE_SLEEP=20 run_cli run demo); rc=$?
elapsed=$(( $(date +%s) - start ))
ok "TERM を無視されても timeout として終わる" "$(eq "$(status_of demo)" timeout)"
ok "20秒待たずに戻る(強制終了している)" "$([ "$elapsed" -lt 15 ] && echo 1 || echo 0)"
ok "時間切れのあとロックを外す" "$([ ! -e "$ROOT/state/demo.lock" ] && echo 1 || echo 0)"

# --- 実行しない条件 ---
setup; conf demo
out=$(STUB_HOST=laptop run_cli run demo); rc=$?
ok "HOST が違うマシンでは実行しない(exit 0)" "$(eq "$rc" 0)"
ok "HOST が違うとき claude を起動しない" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 0)"
ok "HOST が違ったことを結果に残す(ホスト名が変わって黙って止まるのを防ぐ)" "$(eq "$(status_of demo)" skipped_host)"

setup; conf demo "ENABLED=0"
out=$(run_cli run demo)
ok "ENABLED=0 では claude を起動しない" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 0)"

setup; conf demo
mkdir -p "$ROOT/state/demo.lock"; echo $$ > "$ROOT/state/demo.lock/pid"
out=$(run_cli run demo); rc=$?
ok "前回がまだ動いていれば実行しない" "$(has "$out" "まだ動いています")"
ok "動いているロックは消さない" "$([ -d "$ROOT/state/demo.lock" ] && echo 1 || echo 0)"

setup; conf demo
mkdir -p "$ROOT/state/demo.lock"; echo 999999 > "$ROOT/state/demo.lock/pid"
out=$(run_cli run demo); rc=$?
ok "持ち主のいないロックは外して実行する" "$(eq "$(status_of demo)" ok)"

setup; conf demo
out=$(run_cli run demo --dry-run); rc=$?
ok "--dry-run は準備まで行い exit 0" "$(eq "$rc" 0)"
ok "--dry-run は claude を起動しない" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 0)"
ok "--dry-run でも worktree は作る" "$([ -d "$ROOT/state/worktrees/demo" ] && echo 1 || echo 0)"

# --- 設定の検証 ---
setup
printf 'REPO=%s\nPROMPT=x\nHOUR=6\nMINUTE=40\n' "$ROOT/repo" > "$ROOT/conf/nohost.conf"
out=$(run_cli run nohost); rc=$?
ok "HOST の無い設定はエラー(全マシンで動かさない)" "$(has "$out" "HOST がありません")"

setup; conf demo "HOUR=24"
ok "HOUR の範囲外はエラー" "$(has "$(run_cli run demo)" "HOUR は 0〜23")"
setup; conf demo "MINUTE=60"
ok "MINUTE の範囲外はエラー" "$(has "$(run_cli run demo)" "MINUTE は 0〜59")"
setup; conf demo "TIMEOUT_MIN=0"
ok "TIMEOUT_MIN の 0 はエラー" "$(has "$(run_cli run demo)" "TIMEOUT_MIN は正の整数")"
setup; conf demo "TIMEOUT=30"
ok "不明なキーはエラー(打ち間違いを黙って無視しない)" "$(has "$(run_cli run demo)" "不明なキーです: TIMEOUT")"
setup; conf demo 'echo pwned > /tmp/claude-loop-test-pwned'
out=$(run_cli run demo)
ok "KEY=VALUE でない行はエラーにし、コードとして実行しない" "$(has "$out" "KEY=VALUE の形ではありません")"
setup
ok "設定が無い名前はエラー" "$(has "$(run_cli run nothing)" "設定がありません")"
ok "名前に使えない文字はエラー" "$(has "$(run_cli run '../etc')" "ループ名は")"
ok "引数なしは使い方を出して exit 1" "$(run_cli >/dev/null; eq "$?" 1)"

# --- launchd ---
setup; conf demo "WEEKDAY=1"
plist=$(run_cli render demo)
ok "plist のラベル" "$(has "$plist" "<string>local.claude-loop.demo</string>")"
ok "plist の起動時刻" "$(has "$plist" "<key>Hour</key><integer>6</integer>")"
ok "plist の分" "$(has "$plist" "<key>Minute</key><integer>40</integer>")"
ok "plist の曜日" "$(has "$plist" "<key>Weekday</key><integer>1</integer>")"
ok "plist は run <name> を呼ぶ" "$(has "$plist" "exec /opt/bin/claude-loop run demo")"
if command -v plutil >/dev/null 2>&1; then
  printf '%s' "$plist" > "$ROOT/t.plist"
  ok "plist として正しい形式" "$(plutil -lint "$ROOT/t.plist" >/dev/null 2>&1 && echo 1 || echo 0)"
fi
setup; conf demo
ok "WEEKDAY が無ければ曜日を出さない" "$(eq "$(has "$(run_cli render demo)" "Weekday")" 0)"

setup; conf demo; conf other "HOST=laptop"; conf off "ENABLED=0"
touch "$ROOT/agents/local.claude-loop.other.plist"
out=$(run_cli install)
ok "このマシン向けのループを登録する" "$([ -f "$ROOT/agents/local.claude-loop.demo.plist" ] && echo 1 || echo 0)"
ok "launchctl bootstrap を呼ぶ" "$(has "$(cat "$STUB_LOG")" "bootstrap gui/")"
ok "別マシン向けは登録せず、残っていた plist も消す" "$([ ! -e "$ROOT/agents/local.claude-loop.other.plist" ] && echo 1 || echo 0)"
ok "ENABLED=0 は登録しない" "$([ ! -e "$ROOT/agents/local.claude-loop.off.plist" ] && echo 1 || echo 0)"
ok "登録件数を出す" "$(has "$out" "登録 1 件")"

# 設定を消したループの登録は install で外す
rm "$ROOT/conf/demo.conf"
: > "$STUB_LOG"
out=$(run_cli install)
ok "設定が無くなったループの plist を消す" "$([ ! -e "$ROOT/agents/local.claude-loop.demo.plist" ] && echo 1 || echo 0)"
ok "設定が無くなったループを bootout する" "$(has "$(cat "$STUB_LOG")" "bootout gui/")"
conf demo; run_cli install >/dev/null

out=$(run_cli uninstall)
ok "uninstall で plist を消す" "$([ ! -e "$ROOT/agents/local.claude-loop.demo.plist" ] && echo 1 || echo 0)"
ok "uninstall で bootout を呼ぶ" "$(has "$(cat "$STUB_LOG")" "bootout gui/")"

setup; conf demo
run_cli run demo >/dev/null
out=$(run_cli list)
ok "list に時刻と直近の結果を出す" "$(has "$out" "06:40")"
ok "list に結果の状態を出す" "$(has "$out" " ok ")"

# --- doctor: 足りない設定を1つずつ知らせ、揃っていれば exit 0 ---
doctor_stubs() { # $1: 固定ホスト名 / $2: 自動ログインの利用者 / $3: launchctl print の終了コード
  printf '#!/bin/bash\n[ "$1" = "--get" ] && { [ -n "%s" ] && echo "%s" || exit 1; }\n' "$1" "$1" > "$ROOT/bin/scutil"
  printf '#!/bin/bash\n[ -n "%s" ] && echo "%s" || exit 1\n' "$2" "$2" > "$ROOT/bin/defaults"
  printf '#!/bin/bash\necho "launchctl $*" >> "$STUB_LOG"\n[ "$1" = "print" ] && exit %s\nexit 0\n' "$3" > "$ROOT/bin/launchctl"
  # 実機の FileVault の状態で結果が変わらないよう、必ず差し替える。STUB_FILEVAULT: On / Off(既定) / error
  cat > "$ROOT/bin/fdesetup" <<'STUB'
#!/bin/bash
[ "${STUB_FILEVAULT:-Off}" = "error" ] && exit 1
echo "FileVault is ${STUB_FILEVAULT:-Off}."
STUB
  chmod +x "$ROOT/bin/scutil" "$ROOT/bin/defaults" "$ROOT/bin/launchctl" "$ROOT/bin/fdesetup"
}
doctor_ready() { # 自動ログイン以外が揃った状態を作る。$1: 自動ログインの利用者
  setup; conf demo; doctor_stubs loopbox "$1" 0
  printf 'CLAUDE_SLACK_WEBHOOK_URL=https://hooks.example.test/a\nCLAUDE_CODE_OAUTH_TOKEN=dummy-token-for-test\n' > "$ROOT/conf/env"
  chmod 600 "$ROOT/conf/env"
  run_cli install >/dev/null; run_cli run demo >/dev/null
}
setup; conf demo; doctor_stubs "" "" 1
out=$(run_cli doctor); rc=$?
ok "doctor: 足りないものがあれば exit 1" "$(eq "$rc" 1)"
ok "doctor: ホスト名が固定されていないと知らせ、直すコマンドを出す" "$(has "$out" "sudo scutil --set HostName loopbox")"
ok "doctor: 通知先が無いと知らせる" "$(has "$out" "通知先がありません")"
ok "doctor: 認証トークンが無いと知らせる" "$(has "$out" "認証トークンがありません")"
ok "doctor: 自動ログインが無効だと知らせる" "$(has "$out" "自動ログインが無効です")"
ok "doctor: 登録されていないループを知らせる" "$(has "$out" "[demo] launchd に登録されていません")"
ok "doctor: claude を起動しない" "$(eq "$(grep -c '^cwd=' "$STUB_LOG")" 0)"

setup; conf demo "NO_PUSH=1"; conf other "HOST=laptop"; doctor_stubs loopbox "$(id -un)" 0
printf 'CLAUDE_SLACK_WEBHOOK_URL=https://hooks.example.test/a\nCLAUDE_CODE_OAUTH_TOKEN=dummy-token-for-test\n' > "$ROOT/conf/env"
chmod 600 "$ROOT/conf/env"
run_cli install >/dev/null; run_cli run demo >/dev/null
out=$(run_cli doctor); rc=$?
ok "doctor: 揃っていれば exit 0" "$(eq "$rc" 0)"
ok "doctor: 揃っていると言い切る" "$(has "$out" "要対応はありません")"
ok "doctor: 直近の結果を出す" "$(has "$out" "[demo] 直近の結果: ok")"
ok "doctor: 別マシン向けのループは点検しない" "$(eq "$(has "$out" "[other]")" 0)"
ok "doctor: 秘密の値を出力に写さない" "$(eq "$(has "$out" "dummy-token-for-test")$(has "$out" "hooks.example.test")" 00)"

chmod 644 "$ROOT/conf/env"
out=$(run_cli doctor); rc=$?
ok "doctor: env ファイルを他の利用者が読めるなら exit 1" "$(eq "$rc" 1)"
ok "doctor: 権限を直すコマンドを出す" "$(has "$out" "chmod 600")"
chmod 600 "$ROOT/conf/env"
STUB_CLAUDE_RC=3 run_cli run demo >/dev/null
out=$(run_cli doctor); rc=$?
ok "doctor: 直近の実行が失敗なら exit 1" "$(eq "$rc" 1)"
ok "doctor: 失敗の状態を出す" "$(has "$out" "[demo] 直近の結果: failed")"
STUB_CLAUDE_BRANCH=loop-demo/20260101-x STUB_CLAUDE_PUSH="$ROOT/origin.git" run_cli run demo >/dev/null
out=$(run_cli doctor)
ok "doctor: 確認待ちのブランチ数を出す" "$(has "$out" "確認待ちのブランチが 1本あります")"
git -C "$ROOT/repo" config remote.origin.pushurl "$ROOT/origin.git"
out=$(run_cli doctor); rc=$?
ok "doctor: NO_PUSH のループで pushurl があれば exit 1" "$(eq "$rc" 1)"

chmod 400 "$ROOT/conf/env"; git -C "$ROOT/repo" config --unset-all remote.origin.pushurl
out=$(run_cli doctor)
ok "doctor: 権限 400 は本人だけが読めるので OK" "$(has "$out" "env ファイルは本人だけが読めます")"

# ループを動かさないマシンでは、マシン単位の設定が無くても要対応にしない
setup; conf other "HOST=laptop"; doctor_stubs loopbox "" 0
out=$(run_cli doctor); rc=$?
ok "doctor: このマシン向けのループが無いことを知らせる" "$(has "$out" "向けのループはありません")"
ok "doctor: ループの無いマシンでは exit 0" "$(eq "$rc" 0)"
ok "doctor: ループの無いマシンでは通知先などを要対応にしない" "$(eq "$(has "$out" "要対応  通知先")" 0)"

# ホスト名が固定されておらず、今の名前に合うループが無い = 名前がずれた専用マシンかもしれない
setup; conf demo "HOST=fixedbox"; doctor_stubs "" "" 0
out=$(STUB_HOST=dhcp-123 run_cli doctor); rc=$?
ok "doctor: 名前がずれている可能性を要対応にする" "$(eq "$rc" 1)"
ok "doctor: 固定する名前は設定の HOST から出す(再発防止: ずれた今の名前で固定させる案内を出した)" "$(has "$out" "sudo scutil --set HostName fixedbox")"
ok "doctor: ずれた今の名前を固定先にしない" "$(eq "$(has "$out" "--set HostName dhcp-123")" 0)"

setup; conf demo "HOST=fixedbox"; conf second "HOST=otherbox"; doctor_stubs "" "" 0
out=$(STUB_HOST=dhcp-123 run_cli doctor)
ok "doctor: HOST の候補が複数でも、ずれた今の名前を固定先にしない" "$(eq "$(has "$out" "--set HostName dhcp-123")" 0)"
ok "doctor: 候補を並べて選ばせる" "$(has "$out" "次のどれか: fixedbox otherbox")"

setup; conf demo; doctor_stubs loopbox.local "$(id -un)" 0
out=$(run_cli doctor)
ok "doctor: FQDN で固定していても固定済みと判定する" "$(has "$out" "ホスト名は固定されています")"

# 対話シェルで export 済みの通知先は数えない(launchd には届かない)
setup; conf demo; doctor_stubs loopbox "$(id -un)" 0
out=$(CLAUDE_SLACK_WEBHOOK_URL=https://hooks.example.test/a run_cli doctor); rc=$?
ok "doctor: env ファイルに無い通知先は、環境変数にあっても要対応(再発防止: 対話シェルの値で OK と出た)" "$(has "$out" "要対応  通知先がありません")"
ok "doctor: そのとき exit 1" "$(eq "$rc" 1)"

# 壊れた設定が1つあっても、ほかの点検を続ける
setup; conf demo; doctor_stubs loopbox "$(id -un)" 0
printf 'REPO=x\nBROKEN\n' > "$ROOT/conf/aaa-broken.conf"
out=$(run_cli doctor); rc=$?
ok "doctor: 壊れた設定を要対応として知らせる" "$(has "$out" "[aaa-broken] 設定を読めません")"
ok "doctor: 壊れた設定の後ろのループも点検する" "$(has "$out" "[demo]")"

doctor_ready ""
out=$(STUB_FILEVAULT=On run_cli doctor); rc=$?
ok "doctor: FileVault が有効なら自動ログインを要対応にしない(再発防止: 設定できない案内を出し続けた)" "$(eq "$(has "$out" "要対応  自動ログイン")" 0)"
ok "doctor: FileVault が理由だと知らせる" "$(has "$out" "情報    FileVault が有効なので自動ログインは使えません")"
ok "doctor: FileVault 以外が揃っていれば exit 0" "$(eq "$rc" 0)"

doctor_ready ""
out=$(STUB_FILEVAULT=Off run_cli doctor); rc=$?
ok "doctor: FileVault が無効なら自動ログインを要対応にする" "$(has "$out" "要対応  自動ログインが無効です")"
ok "doctor: FileVault が無効で自動ログインも無効なら exit 1" "$(eq "$rc" 1)"

doctor_ready ""
out=$(STUB_FILEVAULT=error run_cli doctor)
ok "doctor: FileVault の状態を読めないときは要対応のままにする" "$(has "$out" "要対応  自動ログインが無効です")"

doctor_ready "$(id -un)"
out=$(STUB_FILEVAULT=On run_cli doctor)
ok "doctor: 自動ログインが有効なら FileVault の表示より優先する" "$(has "$out" "OK      自動ログインが有効です")"

out=$(run_cli); rc=$?
ok "使い方に doctor が出る" "$(has "$out" "claude-loop doctor")"
ok "使い方にコードの行が混ざらない" "$(eq "$(has "$out" "set -uo pipefail")" 0)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
