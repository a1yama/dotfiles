#!/bin/bash
# harness-signals(会話ログからの手がかり集計)のテスト。`bash tests/harness-signals.test.sh` で実行する。
# shellcheck disable=SC2016,SC2028 # 固定データの JSON とバッククォートを文字のまま書く
set -u
CLI="$(cd "$(dirname "$0")/../../.." && pwd)/.local/bin/harness-signals"
pass=0; fail=0
ok() { if [ "$2" = "1" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; fi; }
eq() { if [ "$1" = "$2" ]; then echo 1; else echo 0; fi; }
q() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$ROOT/out.json" "$1" 2>&1; }

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/projects/proj-a/sub" "$ROOT/projects/proj-b" "$ROOT/projects/-Users-x--local-state-claude-loop-worktrees-demo"
NOW=2000000000

deny='{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"PreToolUse:Bash hook error: ツール選択ルール: `grep` は専用ツールを使ってください。続きの説明"}]}}'
{
  echo "$deny"; echo "$deny"
  echo '{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"ただの失敗 exit 1"}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"# tool-exception: 件数だけ数える\ngrep -c x file"}}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -l"}}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cd /tmp/x && sed -n 1,3p f # tool-exception: 行範囲だけ見る"}}]}}'
  echo '{"type":"user","timestamp":"t1","message":{"content":"それは間違っています。やり直して"}}'
  echo '{"type":"user","message":{"content":"次は表を作ってください"}}'
  echo '{"type":"user","isMeta":true,"message":{"content":"間違っている(メタ)"}}'
  echo '{"type":"user","isSidechain":true,"message":{"content":"間違っている(サブエージェント)"}}'
  echo '{"type":"user","message":{"content":"<command-name>/fix</command-name> 直して"}}'
  echo '{"type":"user","uuid":"u-old","timestamp":"2020-01-01T00:00:00.000Z","message":{"content":"昔の発言: 間違っています"}}'
  echo '{"type":"user","uuid":"u-dup","timestamp":"2033-05-17T00:00:00.000Z","message":{"content":[{"type":"text","text":"画像つき: 動かないです"}]}}'
  echo '{"type":"user","uuid":"u-dup","timestamp":"2033-05-17T00:00:00.000Z","message":{"content":[{"type":"text","text":"画像つき: 動かないです"}]}}'
  echo '{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"PreToolUse:mcp__some-server__do.it hook error: 止めました。詳細"}]}}'
  echo 'これは JSON ではない行'
  echo '[1,2,3]'
} > "$ROOT/projects/proj-a/s1.jsonl"
echo "$deny" > "$ROOT/projects/proj-b/s2.jsonl"
echo "$deny" > "$ROOT/projects/proj-a/sub/agent.jsonl"
echo "$deny" > "$ROOT/projects/proj-b/old.jsonl"
echo "$deny" > "$ROOT/projects/-Users-x--local-state-claude-loop-worktrees-demo/loop.jsonl"
touch -t 203305180333 "$ROOT/projects/-Users-x--local-state-claude-loop-worktrees-demo/loop.jsonl" "$ROOT/projects/proj-a/s1.jsonl" "$ROOT/projects/proj-b/s2.jsonl" "$ROOT/projects/proj-a/sub/agent.jsonl"
touch -t 203301010000 "$ROOT/projects/proj-b/old.jsonl"

"$CLI" --projects-dir "$ROOT/projects" --days 7 --now "$NOW" > "$ROOT/out.json"; rc=$?
ok "正常終了" "$(eq "$rc" 0)"
ok "期間内の直下のログだけ読む(古いログ・サブディレクトリ・無人ループ自身のログを除く)" "$(eq "$(q 'd["files_scanned"]')" 2)"
ok "同じ拒否を1つにまとめて数える" "$(eq "$(q 'd["hook_denials"][0]["count"]')" 3)"
ok "拒否が出たセッション数を数える" "$(eq "$(q 'd["hook_denials"][0]["sessions"]')" 2)"
ok "拒否の種類はフックと対象が分かる先頭の1文" "$(eq "$(q '"`grep`" in d["hook_denials"][0]["key"] and "続き" not in d["hook_denials"][0]["key"]')" True)"
ok "フック以外の失敗は拒否に数えない(ハイフンを含む MCP ツール名の拒否は数える)" "$(eq "$(q 'sorted(x["count"] for x in d["hook_denials"])')" "[1, 3]")"
ok "tool-exception をコマンド別に数える(先頭の cd は飛ばす)" "$(eq "$(q '[(e["command"],e["count"]) for e in d["tool_exceptions"]]')" "[('grep', 1), ('sed', 1)]")"
ok "tool-exception の理由を残す" "$(eq "$(q 'd["tool_exceptions"][0]["reasons"][0]')" "件数だけ数える")"
ok "手戻りの発言は本人の発言だけ数える(メタ・サブエージェント・コマンド・通常の依頼・期間外・重複を除き、text ブロックの発言は数える)" "$(eq "$(q 'd["rework"]["count"]')" 2)"
ok "手戻りの発言の場所を返す" "$(eq "$(q 'd["rework"]["items"][0]["timestamp"]')" t1)"

mkdir "$ROOT/empty"
"$CLI" --projects-dir "$ROOT/empty" --now "$NOW" > "$ROOT/out.json"; rc=$?
ok "ログが1本も無くても正常終了し、件数は0" "$(eq "$rc$(q 'd["files_scanned"]')" 00)"

"$CLI" --projects-dir "$ROOT/nope" >/dev/null 2>&1; ok "ディレクトリが無ければ exit 1" "$(eq "$?" 1)"
echo "# パターンなし" > "$ROOT/nosig.sh"
"$CLI" --projects-dir "$ROOT/projects" --signals-file "$ROOT/nosig.sh" >/dev/null 2>&1
ok "手戻りのパターンを読めなければ exit 1(0件として通さない)" "$(eq "$?" 1)"
"$CLI" --projects-dir "$ROOT/projects" --days 0 >/dev/null 2>&1; ok "--days 0 は不正" "$(eq "$?" 2)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
