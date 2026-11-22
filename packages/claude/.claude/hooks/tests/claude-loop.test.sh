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
{ echo "cwd=$PWD"; printf 'arg=%s\n' "$@"; } >> "$STUB_LOG"
[ -n "${STUB_CLAUDE_TOUCH:-}" ] && echo leftover > "$PWD/$STUB_CLAUDE_TOUCH"
if [ -n "${STUB_CLAUDE_COMMIT:-}" ]; then
  echo c > "$PWD/committed.txt"; git add committed.txt
  git -c user.name=t -c user.email=t@example.com commit -q -m "detached のまま積んだコミット"
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
  unset STUB_HOST STUB_CLAUDE_TOUCH STUB_CLAUDE_SLEEP STUB_CLAUDE_RC STUB_CLAUDE_COMMIT STUB_CLAUDE_IGNORE_TERM
  unset CLAUDE_SLACK_WEBHOOK_URL CLAUDE_DISCORD_WEBHOOK_URL
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
