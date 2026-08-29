#!/bin/bash
# stop-dispatch.sh の結合テスト。`bash tests/stop-dispatch.test.sh` で実行する。
#
# 各ゲート単体のテストでは検出できない「前段が block したら後段が一度も走らない」を見る。
# 前段で打ち切ると、継続後の再停止は stop_hook_active=true で後段も即 exit するため、
# そのターンで後段のゲートが丸ごと迂回される。
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/stop-dispatch.sh"
pass=0
fail=0

TMPDIR=$(mktemp -d)
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected=%s\n  actual=%s\n' "$desc" "$expected" "$actual"
  fi
}

# 差し替え用のスタブ置き場。$1 に frame-check、$2 に quality-gate、$3 に premise-gate が
# 返す reason(空文字なら何も出力しない = allow)
stub_dir() {
  local dir
  dir=$(mktemp -d "$TMPDIR/hooks.XXXXXX")
  for pair in "stop-frame-check.sh:$1" "stop-quality-gate.sh:$2" "stop-premise-gate.sh:${3:-}"; do
    local name="${pair%%:*}" reason="${pair#*:}"
    printf '#!/bin/bash\ncat >"%s/%s.stdin"\n' "$dir" "$name" > "$dir/$name"
    if [ -n "$reason" ]; then
      # 差し戻しの中身は生成時に確定させる(スタブ側では cat するだけ)
      jq -n --arg r "$reason" '{decision:"block",reason:$r}' > "$dir/$name.json"
      printf 'cat "%s/%s.json"\n' "$dir" "$name" >> "$dir/$name"
    fi
    chmod +x "$dir/$name"
  done
  # 通知の代わりに呼び出しを記録するだけのスタブ
  printf '#!/bin/bash\ncat >"%s/notify.stdin"\n' "$dir" > "$dir/notify"
  chmod +x "$dir/notify"
  printf '%s' "$dir"
}

run_dispatch() {
  local dir="$1"
  printf '{"stop_hook_active":false,"cwd":"/tmp"}' \
    | CLAUDE_HOOKS_DIR="$dir" CLAUDE_NOTIFY_BIN="$dir/notify" bash "$HOOK"
}

# frame-check だけが差し戻す
dir=$(stub_dir "方針を点検してください" "")
out=$(run_dispatch "$dir")
check "frame だけ block: decision" block "$(printf '%s' "$out" | jq -r '.decision')"
check "frame だけ block: reason"  "方針を点検してください" "$(printf '%s' "$out" | jq -r '.reason')"
check "frame だけ block: 通知しない" "no" "$([ -f "$dir/notify.stdin" ] && echo yes || echo no)"

# quality-gate だけが差し戻す
dir=$(stub_dir "" "テストが失敗しました")
out=$(run_dispatch "$dir")
check "gate だけ block: reason" "テストが失敗しました" "$(printf '%s' "$out" | jq -r '.reason')"

# 回帰: frame-check が block しても quality-gate は必ず走り、理由が両方載る
dir=$(stub_dir "方針を点検してください" "テストが失敗しました")
out=$(run_dispatch "$dir")
check "両方 block: quality-gate も実行される" "yes" \
  "$([ -f "$dir/stop-quality-gate.sh.stdin" ] && echo yes || echo no)"
check "両方 block: 理由を連結する" \
  "方針を点検してください

テストが失敗しました" "$(printf '%s' "$out" | jq -r '.reason')"
check "両方 block: decision は1つ" block "$(printf '%s' "$out" | jq -r '.decision')"

# 連結できない出力でも差し戻しを落とさない(安全網)
dir=$(stub_dir "" "")
printf '#!/bin/bash\ncat >/dev/null\nprintf "壊れた出力"\n' > "$dir/stop-frame-check.sh"
chmod +x "$dir/stop-frame-check.sh"
out=$(run_dispatch "$dir")
check "非JSONのゲート出力でも素通ししない" "壊れた出力" "$(printf '%s' "$out" | jq -r '.reason' 2>/dev/null | tail -1)"
check "非JSONでも有効な block になる" block "$(printf '%s' "$out" | jq -r '.decision' 2>/dev/null)"

# 両方壊れていても harness が解釈できる block を返す(そのまま連結すると無視され通知も消える)
dir=$(stub_dir "" "")
for g in stop-frame-check.sh stop-quality-gate.sh; do
  printf '#!/bin/bash\ncat >/dev/null\nprintf "壊れた%s"\n' "$g" > "$dir/$g"
  chmod +x "$dir/$g"
done
out=$(run_dispatch "$dir")
check "両方壊れても block になる" block "$(printf '%s' "$out" | jq -r '.decision' 2>/dev/null)"
check "両方壊れたら通知しない" "no" "$([ -f "$dir/notify.stdin" ] && echo yes || echo no)"

# 回帰: 片方が壊れていても、もう片方の正当な差し戻しを捨てない
dir=$(stub_dir "" "テストが失敗しました")
printf '#!/bin/bash\ncat >/dev/null\nprintf "壊れた出力"\n' > "$dir/stop-frame-check.sh"
chmod +x "$dir/stop-frame-check.sh"
out=$(run_dispatch "$dir")
check "壊れた出力と併存しても gate の理由が残る" "テストが失敗しました" \
  "$(printf '%s' "$out" | jq -r '.reason')"
check "非JSONのとき通知しない" "no" "$([ -f "$dir/notify.stdin" ] && echo yes || echo no)"

# reason が空のゲート出力は連結に使わない(理由なしの差し戻しを作らない)
dir=$(stub_dir "" "テストが失敗しました")
printf '#!/bin/bash\ncat >/dev/null\nprintf '"'"'{"decision":"block"}'"'"'\n' > "$dir/stop-frame-check.sh"
chmod +x "$dir/stop-frame-check.sh"
out=$(run_dispatch "$dir")
check "reason 欠落を混ぜても理由が残る" "テストが失敗しました" "$(printf '%s' "$out" | jq -r '.reason')"

# どちらも差し戻さない
dir=$(stub_dir "" "")
out=$(run_dispatch "$dir")
check "block なし: 出力は空" "" "$out"
check "block なし: 通知する" "yes" "$([ -f "$dir/notify.stdin" ] && echo yes || echo no)"

# premise-gate だけが差し戻す
dir=$(stub_dir "" "" "指示された手段を検証してください")
out=$(run_dispatch "$dir")
check "premise だけ block: reason" "指示された手段を検証してください" "$(printf '%s' "$out" | jq -r '.reason')"
check "premise だけ block: 通知しない" "no" "$([ -f "$dir/notify.stdin" ] && echo yes || echo no)"

# 回帰: 前段が block しても premise-gate は必ず走り、理由が3つとも載る
dir=$(stub_dir "方針を点検してください" "テストが失敗しました" "指示された手段を検証してください")
out=$(run_dispatch "$dir")
check "3つ block: premise も実行される" "yes" \
  "$([ -f "$dir/stop-premise-gate.sh.stdin" ] && echo yes || echo no)"
check "3つ block: 理由を連結する" \
  "方針を点検してください

テストが失敗しました

指示された手段を検証してください" "$(printf '%s' "$out" | jq -r '.reason')"

# 入力は各ゲートにそのまま渡る
dir=$(stub_dir "" "" "")
run_dispatch "$dir" >/dev/null
check "frame へ入力が渡る" '{"stop_hook_active":false,"cwd":"/tmp"}' "$(cat "$dir/stop-frame-check.sh.stdin")"
check "gate へ入力が渡る"  '{"stop_hook_active":false,"cwd":"/tmp"}' "$(cat "$dir/stop-quality-gate.sh.stdin")"
check "premise へ入力が渡る" '{"stop_hook_active":false,"cwd":"/tmp"}' "$(cat "$dir/stop-premise-gate.sh.stdin")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
