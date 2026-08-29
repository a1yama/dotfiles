#!/bin/bash
# claude-tmux spawn が生成するプロンプト/スクリプトの検証。
# `bash tests/claude-tmux-spawn.test.sh` で実行する。
# tmux ペインを実際に作らないよう、PATH 先頭にスタブ tmux を置いて隔離する。
set -u

CLI="$(cd "$(dirname "$0")/../../../.local/bin" && pwd)/claude-tmux"
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

contains() {
  if grep -qF -e "$2" "$1"; then echo 1; else echo 0; fi
}

# サンドボックスを作り、spawn を1回実行して生成物のパスを返す。
# $1: 名前 / $2: CLAUDE_PID に入れる値(空なら未設定) / $3: セッションレジストリの中身(空なら作らない)
setup_and_spawn() {
  local name="$1" pid="$2" registry_json="$3"
  local root
  root=$(mktemp -d)

  mkdir -p "$root/bin" "$root/agents" "$root/home/.claude/sessions" "$root/work"
  cat > "$root/bin/tmux" <<'STUB'
#!/bin/bash
# new-window / split-window は pane-id を、それ以外は無を返す
case "$1" in
  new-window)   echo "%90" ;;
  split-window) echo "%91" ;;
esac
exit 0
STUB
  chmod +x "$root/bin/tmux"

  if [ -n "$registry_json" ] && [ -n "$pid" ]; then
    printf '%s' "$registry_json" > "$root/home/.claude/sessions/${pid}.json"
  fi

  (
    cd "$root/work" || exit 1
    export PATH="$root/bin:$PATH"
    export HOME="$root/home"
    export TMUX="fake,0,0"
    export CLAUDE_TMUX_AGENTS_DIR="$root/agents"
    if [ -n "$pid" ]; then export CLAUDE_PID="$pid"; else unset CLAUDE_PID; fi
    bash "$CLI" spawn "テスト用タスク" --name "$name" >/dev/null 2>&1
  )
  echo "$root"
}

REGISTRY='{"pid":4242,"sessionId":"abc","cwd":"/tmp","name":"hub-x1","nameSource":"derived","status":"idle"}'

# --- 正常系: ハブセッションが解決できる場合 ---
root=$(setup_and_spawn "agent-a" "4242" "$REGISTRY")
prompt="$root/agents/agent-a/enhanced_prompt"
runner="$root/agents/agent-a/runner.sh"
supervisor="$root/agents/agent-a/supervisor.sh"

ok "enhanced_prompt が生成される" "$([ -f "$prompt" ] && echo 1 || echo 0)"
ok "質問経路に SendMessage を案内する" "$(contains "$prompt" 'SendMessage ツールで "hub-x1" 宛')"
ok "ポーリング不要と明示する" "$(contains "$prompt" '返信は会話に自動で届きます')"
# 初回送信は名前だけだと拒否され、"名前 [ref]" での再送が要る
ok "ref 付き再送の手順を案内する" "$(contains "$prompt" '"hub-x1 [ref]" の形式でそのまま送り直して')"

# 再発防止: 旧 question/answer ファイル IPC の指示が残っていないこと
ok "prompt に question ファイルの指示が無い" "$([ "$(contains "$prompt" '/question')" = "0" ] && echo 1 || echo 0)"
ok "prompt に answer ファイルの指示が無い" "$([ "$(contains "$prompt" '/answer')" = "0" ] && echo 1 || echo 0)"
ok "supervisor に question ポーリングが無い" "$([ "$(contains "$supervisor" 'question_file')" = "0" ] && echo 1 || echo 0)"

# runner: cross-session messaging が成立する起動オプション
ok "runner が --name を渡す" "$(contains "$runner" '--name "${name}"')"
ok "runner が crossSessionInbound=accept を渡す" "$(contains "$runner" '{"crossSessionInbound":"accept"}')"
ok "runner が SendMessage を許可する" "$(contains "$runner" 'SendMessage')"

# supervisor の claude -p は出力を grep が読む(VERDICT 判定)。対話用フックが発火すると
# 最終応答に別の節が足されて VERDICT 行が最後から外れ、判定不能で中断する。
# 修正側はプロンプトが「ユーザーへの質問はできません」と書いているのに
# 前提チェックが AskUserQuestion を促すため、指示同士が矛盾する
ok "レビューは前提チェックを止める" "$(contains "$supervisor" 'CLAUDE_PREMISE_CHECK_OFF=1 CLAUDE_FRAME_CHECK_OFF=1')"
ok "レビューと修正の両方で止める" \
  "$([ "$(grep -c 'CLAUDE_PREMISE_CHECK_OFF=1' "$supervisor")" -ge 2 ] && echo 1 || echo 0)"
# 作業者本体はゲートを効かせたままにする(実開発なので発火が妥当)
ok "runner は前提チェックを止めない" \
  "$([ "$(contains "$runner" 'CLAUDE_PREMISE_CHECK_OFF')" = "0" ] && echo 1 || echo 0)"

# 生成スクリプトが壊れていないこと
ok "runner.sh の構文が通る" "$(bash -n "$runner" 2>/dev/null && echo 1 || echo 0)"
ok "supervisor.sh の構文が通る" "$(bash -n "$supervisor" 2>/dev/null && echo 1 || echo 0)"
rm -rf "$root"

# --- エラー経路: ハブが解決できない場合は質問経路を渡さない ---
root=$(setup_and_spawn "agent-b" "" "")
prompt="$root/agents/agent-b/enhanced_prompt"
ok "CLAUDE_PID 未設定なら質問ブロックを出さない" \
  "$([ "$(contains "$prompt" '【質問がある場合】')" = "0" ] && echo 1 || echo 0)"
rm -rf "$root"

root=$(setup_and_spawn "agent-c" "9999" "")
prompt="$root/agents/agent-c/enhanced_prompt"
ok "レジストリが無ければ質問ブロックを出さない" \
  "$([ "$(contains "$prompt" '【質問がある場合】')" = "0" ] && echo 1 || echo 0)"
rm -rf "$root"

# 境界値: レジストリはあるが name が空
root=$(setup_and_spawn "agent-d" "4242" '{"pid":4242,"name":""}')
prompt="$root/agents/agent-d/enhanced_prompt"
ok "name が空なら質問ブロックを出さない" \
  "$([ "$(contains "$prompt" '【質問がある場合】')" = "0" ] && echo 1 || echo 0)"
rm -rf "$root"

# 不正入力: タスク説明なしは失敗する
root=$(mktemp -d)
mkdir -p "$root/bin" "$root/agents"
printf '#!/bin/bash\nexit 0\n' > "$root/bin/tmux"
chmod +x "$root/bin/tmux"
if (
  export PATH="$root/bin:$PATH"
  export TMUX="fake,0,0"
  export CLAUDE_TMUX_AGENTS_DIR="$root/agents"
  bash "$CLI" spawn --name only-name >/dev/null 2>&1
); then
  ok "タスク説明が無ければ異常終了する" 0
else
  ok "タスク説明が無ければ異常終了する" 1
fi
rm -rf "$root"

# 廃止済みサブコマンドが受け付けられないこと
for sub in supervise questions answer; do
  if bash "$CLI" "$sub" >/dev/null 2>&1; then
    ok "廃止済みサブコマンド ${sub} は失敗する" 0
  else
    ok "廃止済みサブコマンド ${sub} は失敗する" 1
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
