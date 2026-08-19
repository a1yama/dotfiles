#!/bin/bash
# agent-status.sh のテスト。`bash tests/agent-status.test.sh` で実行する。
#
# このフックは「書かないこと」が仕様の大半を占める(tmux 外・tmux 未導入・ペイン不明)。
# 誤って書くと tmux 外のセッションでフックがエラーを出し、通常利用を壊すため、
# 何もしない経路を正常系と同じ密度で確認する。
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/agent-status.sh"
pass=0
fail=0

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected=%s\n  actual=%s\n' "$desc" "$expected" "$actual"
  fi
}

# tmux を差し替えて呼び出し引数だけ記録する。実サーバに触れずに
# 「どのペインにどのオプションを set/unset したか」を検証するため。
make_tmux_stub() {
  local dir="$1" exit_code="${2:-0}"
  mkdir -p "$dir"
  cat >"$dir/tmux" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$dir/tmux.log"
exit $exit_code
EOF
  chmod +x "$dir/tmux"
}

# レジストリのフィクスチャを作る。tmux_ref を空にすると tmux フィールドなしになる。
make_registry() {
  local dir="$1" pid="$2" tmux_ref="${3:-}"
  mkdir -p "$dir"
  if [ -n "$tmux_ref" ]; then
    printf '{"pid":%s,"name":"t","tmux":"%s","status":"busy"}\n' "$pid" "$tmux_ref" >"$dir/$pid.json"
  else
    printf '{"pid":%s,"name":"t","status":null}\n' "$pid" >"$dir/$pid.json"
  fi
}

run_hook() {
  # フックは stdin から JSON を受け取るので、実運用と同じく必ず何か流し込む
  printf '{"hook_event_name":"test"}' | "$@"
}

# --- 正常系: TMUX_PANE があれば自分のペインに書く -------------------------
d="$TMPROOT/case1"; make_tmux_stub "$d/bin"
run_hook env PATH="$d/bin:$PATH" TMUX_PANE="%7" CLAUDE_PID="" \
  CLAUDE_SESSIONS_DIR="$d/none" bash "$HOOK" block >/dev/null 2>&1
got=$(sed 's/[0-9]\{6,\}/<epoch>/' "$d/bin/tmux.log" 2>/dev/null || echo "(呼ばれず)")
check "block: TMUX_PANE のペインに epoch を set する" \
  "set-option -p -t %7 @claude_blocked <epoch>" "$got"

# --- 正常系: unblock は -u で消す -----------------------------------------
d="$TMPROOT/case2"; make_tmux_stub "$d/bin"
run_hook env PATH="$d/bin:$PATH" TMUX_PANE="%7" CLAUDE_PID="" \
  CLAUDE_SESSIONS_DIR="$d/none" bash "$HOOK" unblock >/dev/null 2>&1
check "unblock: -u でオプションを消す" \
  "set-option -p -u -t %7 @claude_blocked" "$(cat "$d/bin/tmux.log" 2>/dev/null)"

# --- 境界: TMUX_PANE が無ければレジストリの tmux から解決する -------------
d="$TMPROOT/case3"; make_tmux_stub "$d/bin"; make_registry "$d/sessions" 4242 "main:@5.%7"
run_hook env PATH="$d/bin:$PATH" TMUX_PANE="" CLAUDE_PID=4242 \
  CLAUDE_SESSIONS_DIR="$d/sessions" bash "$HOOK" block >/dev/null 2>&1
got=$(sed 's/[0-9]\{6,\}/<epoch>/' "$d/bin/tmux.log" 2>/dev/null || echo "(呼ばれず)")
check "レジストリの main:@5.%7 から %7 を取り出す" \
  "set-option -p -t %7 @claude_blocked <epoch>" "$got"

# --- 何もしない経路: tmux 外のセッション(レジストリに tmux なし) ----------
d="$TMPROOT/case4"; make_tmux_stub "$d/bin"; make_registry "$d/sessions" 4243 ""
run_hook env PATH="$d/bin:$PATH" TMUX_PANE="" CLAUDE_PID=4243 \
  CLAUDE_SESSIONS_DIR="$d/sessions" bash "$HOOK" block >/dev/null 2>&1
check "tmux 外のセッションでは tmux を呼ばない" "なし" \
  "$([ -f "$d/bin/tmux.log" ] && cat "$d/bin/tmux.log" || echo "なし")"

# --- 何もしない経路: レジストリ自体が無い --------------------------------
d="$TMPROOT/case5"; make_tmux_stub "$d/bin"
run_hook env PATH="$d/bin:$PATH" TMUX_PANE="" CLAUDE_PID=9999 \
  CLAUDE_SESSIONS_DIR="$d/empty" bash "$HOOK" block >/dev/null 2>&1
check "レジストリが無ければ tmux を呼ばない" "なし" \
  "$([ -f "$d/bin/tmux.log" ] && cat "$d/bin/tmux.log" || echo "なし")"

# --- 何もしない経路: CLAUDE_PID 未設定 -----------------------------------
d="$TMPROOT/case6"; make_tmux_stub "$d/bin"; make_registry "$d/sessions" 4244 "main:@5.%7"
run_hook env PATH="$d/bin:$PATH" TMUX_PANE="" CLAUDE_SESSIONS_DIR="$d/sessions" \
  bash "$HOOK" block >/dev/null 2>&1
check "CLAUDE_PID が無ければ tmux を呼ばない" "なし" \
  "$([ -f "$d/bin/tmux.log" ] && cat "$d/bin/tmux.log" || echo "なし")"

# --- 不正入力: 未知の action は何もしない --------------------------------
d="$TMPROOT/case7"; make_tmux_stub "$d/bin"
run_hook env PATH="$d/bin:$PATH" TMUX_PANE="%7" bash "$HOOK" bogus >/dev/null 2>&1
check "未知の action では tmux を呼ばない" "なし" \
  "$([ -f "$d/bin/tmux.log" ] && cat "$d/bin/tmux.log" || echo "なし")"

# --- 不正入力: 引数なし ---------------------------------------------------
d="$TMPROOT/case8"; make_tmux_stub "$d/bin"
run_hook env PATH="$d/bin:$PATH" TMUX_PANE="%7" bash "$HOOK" >/dev/null 2>&1
check "引数なしでも異常終了しない" "0" "$?"

# --- エラー経路: tmux が失敗しても異常終了しない --------------------------
# ペインが既に死んでいる場合に set-option が失敗する。フックが非ゼロで返ると
# Claude Code 側が「フック失敗」として扱うため、握り潰せていることを確認する。
d="$TMPROOT/case9"; make_tmux_stub "$d/bin" 1
run_hook env PATH="$d/bin:$PATH" TMUX_PANE="%7" bash "$HOOK" block >/dev/null 2>&1
check "死んだペインへの書き込み失敗を握り潰す" "0" "$?"

# --- エラー経路: tmux 未インストール --------------------------------------
# tmux は Homebrew 側にしか無いので、システムの bin だけに絞れば未導入環境を再現できる
# (PATH を空にすると bash 自体が見つからず、フックではなくテストが壊れる)
d="$TMPROOT/case10"; mkdir -p "$d/bin"
run_hook env PATH="$d/bin:/bin:/usr/bin" TMUX_PANE="%7" bash "$HOOK" block >/dev/null 2>&1
check "tmux が無い環境でも正常終了する" "0" "$?"

# --- 結合: 実際の tmux サーバに書いて読み戻す -----------------------------
# スタブでは「tmux がその引数を受け付けるか」を検証できない。
# 専用ソケットで実サーバを立て、set したものが list-panes から読めることまで見る。
if command -v tmux >/dev/null 2>&1; then
  sock="agentstatus-test-$$"
  tmux -L "$sock" new-session -d -s t -x 80 -y 24 2>/dev/null
  real_pane=$(tmux -L "$sock" list-panes -a -F '#{pane_id}' 2>/dev/null | head -1)
  if [ -n "$real_pane" ]; then
    # 実運用と同じく TMUX_PANE 経由。socket は TMUX 環境変数で決まるため、
    # サーバのソケットパスを渡して bare tmux がテスト用サーバを向くようにする
    sockpath=$(tmux -L "$sock" display-message -p '#{socket_path}' 2>/dev/null)
    run_hook env TMUX="${sockpath},0,0" TMUX_PANE="$real_pane" \
      bash "$HOOK" block >/dev/null 2>&1
    val=$(tmux -L "$sock" list-panes -a -F '#{@claude_blocked}' 2>/dev/null | head -1)
    check "実 tmux: block した値が list-panes から読める" "あり" \
      "$([ -n "$val" ] && echo あり || echo なし)"

    run_hook env TMUX="${sockpath},0,0" TMUX_PANE="$real_pane" \
      bash "$HOOK" unblock >/dev/null 2>&1
    val=$(tmux -L "$sock" list-panes -a -F '#{@claude_blocked}' 2>/dev/null | head -1)
    check "実 tmux: unblock で値が消える" "なし" \
      "$([ -n "$val" ] && echo あり || echo なし)"
  fi
  tmux -L "$sock" kill-server 2>/dev/null || true
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
