#!/bin/bash
# stop-frame-check.sh の判定テスト。`bash tests/stop-frame-check.test.sh` で実行する。
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/stop-frame-check.sh"
pass=0
fail=0

TMPDIR=$(mktemp -d)
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

judge() {
  if printf '%s' "$1" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    echo block
  else
    echo allow
  fi
}

check() {
  local expected="$1" desc="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected=%s actual=%s\n' "$desc" "$expected" "$actual"
  fi
}

# ツール呼び出し1回ぶんの assistant 行
tool_line() {
  printf '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"a.ts"}}]}}\n'
}

# frame-check 実行の痕跡(Skill ツール呼び出しの形)
skill_line() {
  printf '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"frame-check"}}]}}\n'
}

# frame-check 実行の痕跡(スラッシュコマンド起動の形。Skill ツール呼び出しは発生しない)。
# 実 transcript から写した形式。フィクスチャを自作すると、実在しない形に合わせた正規表現が
# 空振りしたまま pass してしまう
command_line() {
  printf '{"type":"user","message":{"role":"user","content":"<command-message>frame-check</command-message>\\n<command-name>/frame-check</command-name>"}}\n'
}

# 組み込みコマンド形式(<command-message> なし・先頭に空白が入る)
command_line_builtin() {
  printf '{"type":"user","message":{"role":"user","content":"   <command-name>/frame-check</command-name>"}}\n'
}

# $1 回ぶんのツール呼び出しを出力
tool_lines() {
  local i=0
  while [ "$i" -lt "$1" ]; do tool_line; i=$((i + 1)); done
}

# run <expected> <説明> <transcript の中身> [追加の入力 JSON マージ] [環境変数指定]
run() {
  local expected="$1" desc="$2" body="$3" extra="${4:-}" env="${5:-}"
  local tpath payload out
  [ -n "$extra" ] || extra='{}'
  tpath="$TMPDIR/transcript-$pass-$fail-$RANDOM.jsonl"
  printf '%s' "$body" > "$tpath"
  payload=$(jq -n --arg t "$tpath" --argjson e "$extra" '{transcript_path:$t} + $e')
  if [ -n "$env" ]; then
    out=$(printf '%s' "$payload" | env "$env" bash "$HOOK")
  else
    out=$(printf '%s' "$payload" | bash "$HOOK")
  fi
  check "$expected" "$desc" "$(judge "$out")"
}

# 既定閾値 400 の境界値(実測に基づく初期値。実データでの発火頻度は hook のコメント参照)
run allow "399回では要求しない" "$(tool_lines 399)"
run block "400回で要求する"     "$(tool_lines 400)"
run allow "中央値規模(83回)では要求しない" "$(tool_lines 83)"
run allow "ツール呼び出しなし"  '{"type":"user","message":{"role":"user","content":"hello"}}'
run allow "空の transcript"     ''

# 以降は閾値を上書きして判定ロジックだけを見る(行数を増やさないため)
D='FC_TOOLCALLS=50'

# 痕跡以降でカウントし直す(点検したらリセットされる)
run allow "点検後 49回なら要求しない" "$(tool_lines 60; skill_line; tool_lines 49)" '{}' "$D"
run block "点検後さらに50回で再要求"  "$(tool_lines 60; skill_line; tool_lines 50)" '{}' "$D"
run allow "点検直後は要求しない"      "$(tool_lines 60; skill_line)"                 '{}' "$D"

# スラッシュコマンド起動も痕跡として数える(取りこぼすと毎ターン差し戻しが続く)
run allow "/frame-check 後 49回なら要求しない" "$(tool_lines 60; command_line; tool_lines 49)" '{}' "$D"
run block "/frame-check 後さらに50回で再要求"  "$(tool_lines 60; command_line; tool_lines 50)" '{}' "$D"
run allow "/frame-check 直後は要求しない"      "$(tool_lines 60; command_line)"                '{}' "$D"
run allow "組み込み形式(空白始まり)も痕跡"     "$(tool_lines 60; command_line_builtin)"        '{}' "$D"

# 写り込み耐性: JSON は / < > をエスケープしないので、ソースやテストデータを読んだ行が
# そのまま痕跡になってはいけない(ユーザー入力そのものがタグで始まることを要求する)
run block "ソース中のタグ文字列は痕跡にしない" \
  "$(tool_lines 60; printf '{"type":"user","message":{"role":"user","content":"     1\\t  /<command-name>/frame-check</command-name>/ {n=NR}"}}\n')" '{}' "$D"
run block "assistant 側のタグは痕跡にしない" \
  "$(tool_lines 60; printf '{"type":"assistant","message":{"role":"assistant","content":"<command-name>/frame-check</command-name> と書けば起動できます"}}\n')" '{}' "$D"

# 偽装・誤検知耐性: Skill ツール呼び出しの形でない "frame-check" は痕跡にしない
run block "本文中の平文 frame-check は痕跡にしない" \
  "$(tool_lines 60; printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"frame-check は今回不要と判断した"}]}}\n'; tool_lines 5)" '{}' "$D"
run block "スキル説明文の記載は痕跡にしない" \
  "$(tool_lines 60; printf '{"type":"user","message":{"role":"user","content":"- frame-check: 方針の監査をする"}}\n')" '{}' "$D"

# サブエージェント側の呼び出しは数えない
# (現行 harness は別ファイルへ分けるため実質 no-op。同一 transcript に混ざる形式に戻ったときの保険)
run allow "サイドチェーンの呼び出しは除外する" \
  "$(tool_lines 10; printf '{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read"}]}}\n%.0s' $(seq 1 60))" '{}' "$D"

# 無限ループ防止: block からの継続後の再停止は素通し
run allow "stop_hook_active=true は素通し" "$(tool_lines 100)" '{"stop_hook_active":true}' "$D"

# 一度差し戻したら、次はさらに閾値ぶん積むまで再要求しない
# (reason が案内する「不要と判断して終える」出口を取っても毎ターン止まらないこと)
tpath="$TMPDIR/transcript-redemand.jsonl"
tool_lines 60 > "$tpath"
payload=$(jq -n --arg t "$tpath" '{transcript_path:$t}')
out=$(printf '%s' "$payload" | env FC_TOOLCALLS=50 bash "$HOOK")
check block "1回目は要求する" "$(judge "$out")"
out=$(printf '%s' "$payload" | env FC_TOOLCALLS=50 bash "$HOOK")
check allow "棄却して次ターンでも再要求しない" "$(judge "$out")"
tool_lines 50 >> "$tpath"
out=$(printf '%s' "$payload" | env FC_TOOLCALLS=50 bash "$HOOK")
check block "さらに閾値ぶん積んだら再要求する" "$(judge "$out")"

# transcript が取れない入力では判定しない
out=$(jq -n '{stop_hook_active:false}' | bash "$HOOK")
check allow "transcript_path なし" "$(judge "$out")"
out=$(jq -n '{transcript_path:"/nonexistent/transcript.jsonl"}' | bash "$HOOK")
check allow "transcript が存在しないパス" "$(judge "$out")"
out=$(printf 'not json' | bash "$HOOK")
check allow "壊れた入力でも落ちない" "$(judge "$out")"

# 閾値の上書きと手動オプトアウト
run block "FC_TOOLCALLS=5 で早く要求する" "$(tool_lines 5)"  '{}' 'FC_TOOLCALLS=5'
run allow "FC_TOOLCALLS=200 で要求しない" "$(tool_lines 60)" '{}' 'FC_TOOLCALLS=200'
run allow "CLAUDE_FRAME_CHECK_OFF=1 で無効化" "$(tool_lines 100)" '{}' 'CLAUDE_FRAME_CHECK_OFF=1'

# 非数値の閾値は既定値に落とす(無効化のつもりの誤記で全 Stop が止まらないように)
run allow "FC_TOOLCALLS=abc は既定値400に落ちる" "$(tool_lines 100)" '{}' 'FC_TOOLCALLS=abc'
run block "FC_TOOLCALLS=abc でも400回超なら要求" "$(tool_lines 400)" '{}' 'FC_TOOLCALLS=abc'
run allow "FC_TOOLCALLS 空文字も既定値"          "$(tool_lines 100)" '{}' 'FC_TOOLCALLS='

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
