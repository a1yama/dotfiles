#!/bin/bash
# claude-tmux の agents / wait のテスト。`bash tests/claude-tmux-agents.test.sh` で実行する。
#
# 中心にあるのは「harness の status(busy/idle)に blocked を重ねる」合成ロジック。
# harness は AskUserQuestion の回答待ちでも busy を返すため、busy をそのまま信じると
# 人間を待っているエージェントを「作業中」と誤認する。その上書きを重点的に見る。
set -u

CLI="$(cd "$(dirname "$0")/../../../.local/bin" && pwd)/claude-tmux"
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

# tmux スタブ。生存ペイン一覧と blocked 値をファイルで与える。
#   $d/alive-panes : 生きているペインID(1行1件)
#   $d/blocked-<ペインIDのサニタイズ> : 存在すれば blocked
make_env() {
  local d="$1"
  mkdir -p "$d/bin" "$d/sessions"
  cat >"$d/bin/tmux" <<EOF
#!/bin/bash
case "\$1" in
  list-panes) cat "$d/alive-panes" 2>/dev/null ;;
  show-options)
    # -t の次の引数がペインID
    p=""
    while [ \$# -gt 0 ]; do
      [ "\$1" = "-t" ] && p="\$2"
      shift
    done
    f="$d/blocked-\$(printf '%s' "\$p" | tr -d '%')"
    if [ -f "\$f" ]; then cat "\$f"; else exit 1; fi
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$d/bin/tmux"
  : >"$d/alive-panes"
}

add_session() {
  local d="$1" pid="$2" name="$3" pane="$4" status="$5"
  printf '{"pid":%s,"name":"%s","tmux":"main:@1.%s","status":"%s"}\n' \
    "$pid" "$name" "$pane" "$status" >"$d/sessions/$pid.json"
}

add_offline_session() {
  local d="$1" pid="$2" name="$3"
  printf '{"pid":%s,"name":"%s","status":null,"tmux":null}\n' "$pid" "$name" >"$d/sessions/$pid.json"
}

alive() { printf '%s\n' "$2" >>"$1/alive-panes"; }
mark_blocked() { printf '1700000000\n' >"$1/blocked-$(printf '%s' "$2" | tr -d '%')"; }

run_cli() {
  local d="$1"; shift
  env PATH="$d/bin:$PATH" CLAUDE_SESSIONS_DIR="$d/sessions" bash "$CLI" "$@"
}

# 名前で行を絞り、実効状態の列だけ返す。先頭列は絵文字プレフィックス付きの名前だが、
# そこは表示上の都合なのでテストでは固定しない(状態の合成結果だけを見る)。
agent_line() { run_cli "$1" agents 2>/dev/null | awk -v n="$2" '$0 ~ n { print $2 }'; }

# --- 正常系: busy / idle がそのまま出る -----------------------------------
d="$TMPROOT/basic"; make_env "$d"
add_session "$d" 100 "worker-a" "%1" "busy"
add_session "$d" 101 "worker-b" "%2" "idle"
alive "$d" "%1"; alive "$d" "%2"
check "busy がそのまま出る" "busy" "$(agent_line "$d" worker-a)"
check "idle がそのまま出る" "idle" "$(agent_line "$d" worker-b)"

# --- 再発防止: blocked が busy を上書きする -------------------------------
# harness は AskUserQuestion 待ちでも busy を返す。ここを上書きできないと
# 「人間を待っているのに作業中に見える」という当初の問題がそのまま残る。
mark_blocked "$d" "%1"
check "blocked が harness の busy を上書きする" "blocked" "$(agent_line "$d" worker-a)"
check "blocked は他のセッションに漏れない" "idle" "$(agent_line "$d" worker-b)"

# --- 境界: 死んだペイン ---------------------------------------------------
d="$TMPROOT/dead"; make_env "$d"
add_session "$d" 200 "gone" "%9" "busy"
check "生存していないペインは dead" "dead" "$(agent_line "$d" gone)"

# --- 境界: tmux 外のセッションは一覧に出ない ------------------------------
d="$TMPROOT/offline"; make_env "$d"
add_offline_session "$d" 300 "desktop-only"
check "status:null のセッションは一覧に出ない" "" "$(agent_line "$d" desktop-only)"
check "対象ゼロでも異常終了しない" "0" "$(run_cli "$d" agents >/dev/null 2>&1; echo $?)"

# --- 空: レジストリディレクトリが存在しない -------------------------------
d="$TMPROOT/empty"; make_env "$d"; rm -rf "$d/sessions"
check "レジストリが無くても異常終了しない" "0" "$(run_cli "$d" agents >/dev/null 2>&1; echo $?)"

# --- wait: 正常系 ---------------------------------------------------------
d="$TMPROOT/wait"; make_env "$d"
add_session "$d" 400 "w" "%1" "idle"
alive "$d" "%1"
check "wait: 既に目的状態なら即座に返す" "idle" \
  "$(run_cli "$d" wait w --until idle --timeout 0 2>/dev/null)"

# --- wait: timeout -------------------------------------------------------
check "wait: 到達しなければ exit 3" "3" \
  "$(run_cli "$d" wait w --until blocked --timeout 0 >/dev/null 2>&1; echo $?)"

# --- wait: blocked を待てる ----------------------------------------------
mark_blocked "$d" "%1"
check "wait: blocked に遷移していれば返る" "blocked" \
  "$(run_cli "$d" wait w --until blocked --timeout 0 2>/dev/null)"

# --- wait: ペイン消滅は待ち続けずに落とす --------------------------------
d="$TMPROOT/waitdead"; make_env "$d"
add_session "$d" 500 "z" "%3" "busy"
check "wait: ペインが死んでいたら exit 2" "2" \
  "$(run_cli "$d" wait z --until idle --timeout 5 >/dev/null 2>&1; echo $?)"

# --- 不正入力 -------------------------------------------------------------
d="$TMPROOT/bad"; make_env "$d"
add_session "$d" 600 "w" "%1" "idle"
alive "$d" "%1"
check "wait: 未知のセッション名は exit 1" "1" \
  "$(run_cli "$d" wait nosuch --until idle --timeout 0 >/dev/null 2>&1; echo $?)"
check "wait: 不正な --until は exit 1" "1" \
  "$(run_cli "$d" wait w --until bogus --timeout 0 >/dev/null 2>&1; echo $?)"
check "wait: --until 省略は exit 1" "1" \
  "$(run_cli "$d" wait w >/dev/null 2>&1; echo $?)"
check "wait: 名前省略は exit 1" "1" \
  "$(run_cli "$d" wait --until idle >/dev/null 2>&1; echo $?)"
check "wait: 未知のオプションは exit 1" "1" \
  "$(run_cli "$d" wait w --until idle --bogus >/dev/null 2>&1; echo $?)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
