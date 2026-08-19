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
  list-panes)
    # -F に @claude_blocked が含まれるかで出力形を変える。
    # is_pane_alive はペインIDだけを期待し、statusline は2列を期待するため。
    want_blocked=0
    for a in "\$@"; do case "\$a" in *@claude_blocked*) want_blocked=1 ;; esac; done
    while read -r p; do
      [ -n "\$p" ] || continue
      if [ "\$want_blocked" = 1 ]; then
        f="$d/blocked-\$(printf '%s' "\$p" | tr -d '%')"
        if [ -f "\$f" ]; then printf '%s %s\n' "\$p" "\$(cat "\$f")"; else printf '%s \n' "\$p"; fi
      else
        printf '%s\n' "\$p"
      fi
    done < "$d/alive-panes"
    ;;
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
  switch-client|select-window|select-pane) printf '%s\n' "\$*" >> "$d/goto.log" ;;
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

# spawn した作業者(claude -p)の形。ペインは紐づくが harness が status を書かない
add_worker_session() {
  local d="$1" pid="$2" name="$3" pane="$4"
  printf '{"pid":%s,"name":"%s","tmux":"main:@1.%s","status":null}\n' \
    "$pid" "$name" "$pane" >"$d/sessions/$pid.json"
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

# --- 再発防止: idle のときは残留フラグを信用しない ------------------------
# AskUserQuestion を Esc で閉じるとツールがキャンセルされ PostToolUse も Stop も
# 発火せず、@claude_blocked が立ったまま残る。harness の idle を優先しないと
# ステータスバーが blocked のまま固まる(実際に発生した)。
d="$TMPROOT/stale"; make_env "$d"
add_session "$d" 750 "escaped" "%1" "idle"
alive "$d" "%1"
mark_blocked "$d" "%1"
check "idle + 残留フラグ → idle(フラグを無視)" "idle" "$(agent_line "$d" escaped)"

# busy のときは残留と区別できないので blocked を優先する(取りこぼしを避ける)
d="$TMPROOT/stale2"; make_env "$d"
add_session "$d" 751 "working" "%1" "busy"
alive "$d" "%1"
mark_blocked "$d" "%1"
check "busy + フラグ → blocked" "blocked" "$(agent_line "$d" working)"

# --- harness 自身の waiting も blocked として扱う --------------------------
# レジストリが "waiting" を返すことがある(実測)。フックが書けていない経路でも
# 人待ちを取りこぼさないよう、waiting 単独でも blocked になること。
d="$TMPROOT/waiting"; make_env "$d"
add_session "$d" 800 "wait-sess" "%6" "waiting"
alive "$d" "%6"
check "harness の waiting は blocked 扱い" "blocked" "$(agent_line "$d" wait-sess)"

# --- 境界: 死んだペイン ---------------------------------------------------
d="$TMPROOT/dead"; make_env "$d"
add_session "$d" 200 "gone" "%9" "busy"
check "生存していないペインは dead" "dead" "$(agent_line "$d" gone)"

# --- 境界: status が無い作業者(claude -p)も一覧から落とさない --------------
# 落とすと spawn した作業者が丸ごと見えなくなり、dispatch 用途で使い物にならない。
d="$TMPROOT/worker"; make_env "$d"
add_worker_session "$d" 700 "spawned-w" "%4"
alive "$d" "%4"
check "status が無い作業者は unknown として残る" "unknown" "$(agent_line "$d" spawned-w)"
mark_blocked "$d" "%4"
check "status が無くても blocked は重なる" "blocked" "$(agent_line "$d" spawned-w)"

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
# 実際にブロックするときはターンが動いている(harness は busy か waiting)。
# idle のままフラグだけ立てるのは残留フラグの形なので、ここでは再現にならない。
add_session "$d" 400 "w" "%1" "busy"
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

# --- statusline: 並び順・切り詰め・除外 -----------------------------------
# ステータスバーは1行しかないので、人を待たせているものが常に左端に来ることと、
# 長い名前が幅を食い潰さないことが要件になる。
# スタイル指定と記号(非ASCII)を落として、名前の並びだけを取り出す
statusline_plain() {
  run_cli "$1" statusline 2>/dev/null \
    | sed -e 's/#\[[^]]*\]//g' -e 's/[^ -~]//g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

d="$TMPROOT/statusline"; make_env "$d"
add_session "$d" 900 "aaa-idle" "%1" "idle"
add_session "$d" 901 "bbb-busy" "%2" "busy"
add_session "$d" 902 "ccc-waiting" "%3" "waiting"
alive "$d" "%1"; alive "$d" "%2"; alive "$d" "%3"
check "statusline: blocked → busy → idle の順に並ぶ" \
  "ccc-waiting bbb-busy aaa-idle" "$(statusline_plain "$d")"

# フック由来の blocked でも先頭に来る(harness が busy を返していても上書きされる)
d="$TMPROOT/statusline2"; make_env "$d"
add_session "$d" 910 "zzz-idle" "%1" "idle"
add_session "$d" 911 "yyy-hookblocked" "%2" "busy"
alive "$d" "%1"; alive "$d" "%2"
mark_blocked "$d" "%2"
# harness が busy を返していてもフックの blocked が勝ち、かつ先頭に来る。
# 併せて 14 桁超の切り詰め("yyy-hookblocked" → "yyy-hookblock…")も見る。
check "statusline: フックの blocked が先頭に来る／長い名前を切り詰める" \
  "yyy-hookblock zzz-idle" "$(statusline_plain "$d")"

# 死んだペインは出さない
d="$TMPROOT/statusline3"; make_env "$d"
add_session "$d" 920 "ghost" "%9" "busy"
check "statusline: 死んだペインは出さない" "" "$(statusline_plain "$d")"

# 対象ゼロなら空文字(ステータスバーに余白を作らない)
d="$TMPROOT/statusline4"; make_env "$d"
add_offline_session "$d" 930 "desktop"
check "statusline: 対象ゼロなら空" "" "$(statusline_plain "$d")"

# --- goto-blocked / pick --------------------------------------------------
# キーボードからの移動。どのペインを狙ったかを tmux スタブのログで確認する。
goto_target() { awk '{ print $NF }' "$1/goto.log" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//'; }

d="$TMPROOT/gotoblocked"; make_env "$d"
add_session "$d" 1000 "calm" "%1" "idle"
add_session "$d" 1001 "needs-you" "%2" "busy"
alive "$d" "%1"; alive "$d" "%2"
mark_blocked "$d" "%2"
run_cli "$d" goto-blocked >/dev/null 2>&1
check "goto-blocked: blocked のペインを狙う" "%2" "$(goto_target "$d")"
check "goto-blocked: 3段(switch/select-window/select-pane)とも呼ぶ" "3" \
  "$(wc -l < "$d/goto.log" | tr -d ' ')"

d="$TMPROOT/gotonone"; make_env "$d"
add_session "$d" 1010 "calm" "%1" "idle"
alive "$d" "%1"
check "goto-blocked: 待ちが居なければ何もせず正常終了" "0" \
  "$(run_cli "$d" goto-blocked >/dev/null 2>&1; echo $?)"
check "goto-blocked: 待ちが居なければ移動もしない" "" "$(goto_target "$d")"

# pick は fzf をスタブして「先頭行を選んだ」ことにする
d="$TMPROOT/pick"; make_env "$d"
add_session "$d" 1020 "calm" "%1" "idle"
add_session "$d" 1021 "needs-you" "%2" "busy"
alive "$d" "%1"; alive "$d" "%2"
mark_blocked "$d" "%2"
printf '#!/bin/bash\nhead -1\n' > "$d/bin/fzf"; chmod +x "$d/bin/fzf"
run_cli "$d" pick >/dev/null 2>&1
check "pick: 先頭候補(blocked)のペインへ移動する" "%2" "$(goto_target "$d")"

d="$TMPROOT/pickcancel"; make_env "$d"
add_session "$d" 1030 "calm" "%1" "idle"
alive "$d" "%1"
printf '#!/bin/bash\ncat >/dev/null\nexit 130\n' > "$d/bin/fzf"; chmod +x "$d/bin/fzf"
check "pick: Esc で中止しても正常終了" "0" "$(run_cli "$d" pick >/dev/null 2>&1; echo $?)"
check "pick: 中止したら移動しない" "" "$(goto_target "$d")"

d="$TMPROOT/pickempty"; make_env "$d"
check "pick: 対象ゼロでも正常終了" "0" "$(run_cli "$d" pick >/dev/null 2>&1; echo $?)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
