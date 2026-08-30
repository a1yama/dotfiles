#!/bin/bash
# stop-premise-gate.sh の判定テスト。`bash tests/stop-premise-gate.test.sh` で実行する。
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/stop-premise-gate.sh"
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

# 人間の発話1行
user_line() {
  jq -nc --arg t "$1" '{type:"user",isSidechain:false,message:{role:"user",content:$t}}'
}

# tool_result の user 行(本文が空になる = 人間の発話ではない)
tool_result_line() {
  printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}\n'
}

# 読み取り1回ぶんの assistant 行
read_line() {
  printf '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"a.ts"}}]}}\n'
}

# 編集1回ぶんの assistant 行
edit_line() {
  printf '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"a.ts"}}]}}\n'
}

# 前提を検討した痕跡(行頭の ⚖️)
premise_line() {
  printf '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"✅ **結論**\\n直した\\n\\n⚖️ **前提**\\n- 原因: 手段の選択ミス\\n- 採否: 代替案を採用"}]}}\n'
}

# 見出し形式の痕跡。CLAUDE.md が節ラベルの見出し化を認めているため、これも通す必要がある
premise_heading_line() {
  printf '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"### ✅ 結論\\n直した\\n\\n### ⚖️ 前提\\n- 原因: 手段の選択ミス"}]}}\n'
}

# $1 回ぶんの読み取りを出力
read_lines() {
  local i=0
  while [ "$i" -lt "$1" ]; do read_line; i=$((i + 1)); done
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

REWORK='さっきの実装、間違っていたので直してください'
TARGET='カバレッジを80%まで上げて'
METHOD='Redis を使ってキャッシュを実装して'
PLAIN='このリポジトリの構造を教えて'

# シグナル + 閾値超えで差し戻す
run block "手戻り + 閾値超え"   "$(user_line "$REWORK"; read_lines 10; edit_line)"
run block "数値目標 + 閾値超え" "$(user_line "$TARGET"; read_lines 10; edit_line)"
run block "手段指定 + 閾値超え" "$(user_line "$METHOD"; read_lines 10; edit_line)"

# 痕跡があれば通す
run allow "⚖️ 前提 があれば通す" \
  "$(user_line "$REWORK"; read_lines 10; edit_line; premise_line)"

# 回帰: 見出し形式 (### ⚖️ 前提) も痕跡として認める。
# 初版は素の行頭だけを見ていたため、CLAUDE.md の規約どおりに書いた最終応答を差し戻した
run allow "見出し形式の ⚖️ 前提 も通す" \
  "$(user_line "$REWORK"; read_lines 10; edit_line; premise_heading_line)"

# シグナルが無ければ対象外
run allow "普通の依頼は対象外" \
  "$(user_line "$PLAIN"; read_lines 10; edit_line)"

# 回帰: ファイル変更の有無は条件にしない。
# 数値目標の失敗は「調べて本文で案を提示する」形で起き、編集を伴わないことがある。
# 編集を要求すると、その一番危ない形をまるごと取りこぼす
run block "編集なしの調査ターンでも差し戻す" \
  "$(user_line "$TARGET"; read_lines 20)"

# 些末な依頼で止めない(既定閾値 8)
run allow "ツール実行が閾値未満なら対象外" \
  "$(user_line "$REWORK"; read_lines 3; edit_line)"
run block "閾値ちょうどで差し戻す" \
  "$(user_line "$REWORK"; read_lines 7; edit_line)"

# 判定に使うのは直近の人間の発話。tool_result の user 行に引きずられない
# (引きずられると本文が空になり、どのターンも素通しになる)
run block "tool_result 行は発話として数えない" \
  "$(user_line "$REWORK"; read_lines 10; tool_result_line; edit_line)"

# 前のターンの手戻り依頼で、今のターンまで止め続けない
run allow "直近の依頼にシグナルが無ければ通す" \
  "$(user_line "$REWORK"; read_lines 10; edit_line; user_line "$PLAIN"; read_lines 10; edit_line)"

# 痕跡は「今回の依頼以降」のものだけを見る。前ターンの ⚖️ で今回を通してはいけない
run block "前ターンの痕跡は今回に使えない" \
  "$(user_line "$REWORK"; premise_line; user_line "$REWORK"; read_lines 10; edit_line)"

# 行頭でない ⚖️ は痕跡にしない(記号に言及しただけの行で通さない)
run block "本文中の ⚖️ は痕跡にしない" \
  "$(user_line "$REWORK"; read_lines 10; edit_line
     printf '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"フックは ⚖️ を探します"}]}}\n')"

# tool_result への写り込みを痕跡にしない。
# CLAUDE.md やこのフック自身を読むと `⚖️ **前提**` が tool_result に入るため、
# assistant の本文に限定していないとフックの保守中は常に素通しになる
run block "tool_result への写り込みは痕跡にしない" \
  "$(user_line "$REWORK"; read_lines 10; edit_line
     printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","content":"⚖️ **前提**\\n- 目的: ..."}]}}\n')"

# サブエージェント側の呼び出しは数えない
run allow "サイドチェーンの呼び出しは数えない" \
  "$(user_line "$REWORK"; read_lines 3
     printf '{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read"}]}}\n%.0s' $(seq 1 20))"

# 無限ループ防止: block からの継続後の再停止は素通し
run allow "stop_hook_active=true は素通し" \
  "$(user_line "$REWORK"; read_lines 10; edit_line)" '{"stop_hook_active":true}'

# transcript が取れない入力では判定しない
out=$(jq -n '{stop_hook_active:false}' | bash "$HOOK")
check allow "transcript_path なし" "$(judge "$out")"
out=$(jq -n '{transcript_path:"/nonexistent/transcript.jsonl"}' | bash "$HOOK")
check allow "transcript が存在しないパス" "$(judge "$out")"
out=$(printf 'not json' | bash "$HOOK")
check allow "壊れた入力でも落ちない" "$(judge "$out")"
run allow "空の transcript" ''
run allow "JSON でない行が混ざっても落ちない" \
  "$(printf 'garbage\n'; user_line "$REWORK"; read_lines 10; edit_line
     printf 'garbage\n')" '{}' ''

# 閾値の上書きと手動オプトアウト
run block "PG_MINCALLS=2 で早く差し戻す" \
  "$(user_line "$REWORK"; read_lines 2; edit_line)" '{}' 'PG_MINCALLS=2'
run allow "PG_MINCALLS=100 なら差し戻さない" \
  "$(user_line "$REWORK"; read_lines 10; edit_line)" '{}' 'PG_MINCALLS=100'
run allow "CLAUDE_PREMISE_CHECK_OFF=1 で無効化" \
  "$(user_line "$REWORK"; read_lines 10; edit_line)" '{}' 'CLAUDE_PREMISE_CHECK_OFF=1'

# 非数値の閾値は既定値に落とす(無効化のつもりの誤記で全 Stop が止まらないように)
run allow "PG_MINCALLS=abc は既定値8に落ちる" \
  "$(user_line "$REWORK"; read_lines 3; edit_line)" '{}' 'PG_MINCALLS=abc'
run block "PG_MINCALLS=abc でも閾値超えなら差し戻す" \
  "$(user_line "$REWORK"; read_lines 10; edit_line)" '{}' 'PG_MINCALLS=abc'

# 差し戻し文面は手戻りと手段指定で切り替わる
tpath="$TMPDIR/transcript-reason.jsonl"
{ user_line "$REWORK"; read_lines 10; edit_line; } > "$tpath"
reason=$(jq -n --arg t "$tpath" '{transcript_path:$t}' | bash "$HOOK" | jq -r '.reason')
check yes "手戻りの理由に原因の特定を含む" \
  "$(printf '%s' "$reason" | grep -q '原因' && echo yes || echo no)"
check yes "手戻りの理由が指摘の裏取りを求める" \
  "$(printf '%s' "$reason" | grep -q '指摘が事実か' && echo yes || echo no)"
check yes "手戻りの理由が逆張りにバーを付ける" \
  "$(printf '%s' "$reason" | grep -q '逆張り' && echo yes || echo no)"
{ user_line "$METHOD"; read_lines 10; edit_line; } > "$tpath"
reason=$(jq -n --arg t "$tpath" '{transcript_path:$t}' | bash "$HOOK" | jq -r '.reason')
check yes "手段指定の理由に目的を含む" \
  "$(printf '%s' "$reason" | grep -q '目的' && echo yes || echo no)"
check yes "理由に AskUserQuestion の案内を含む" \
  "$(printf '%s' "$reason" | grep -q 'AskUserQuestion' && echo yes || echo no)"

{ user_line "$TARGET"; read_lines 10; } > "$tpath"
reason=$(jq -n --arg t "$tpath" '{transcript_path:$t}' | bash "$HOOK" | jq -r '.reason')
check yes "数値目標の理由が「根拠」を要求する" \
  "$(printf '%s' "$reason" | grep -q '根拠' && echo yes || echo no)"
# 差し戻し文面が特定ドメインの語彙に寄ると、プログラミングの依頼で抑止にならない
check yes "抜け道の例がコードの話になっている" \
  "$(printf '%s' "$reason" | grep -q '型を any' && echo yes || echo no)"
check yes "数値目標の理由に「満たせない」出口がある" \
  "$(printf '%s' "$reason" | grep -q 'この条件では満たせない' && echo yes || echo no)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
