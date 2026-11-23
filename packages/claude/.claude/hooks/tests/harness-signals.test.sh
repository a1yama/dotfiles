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
  echo '{"type":"assistant","uuid":"k1","timestamp":"2033-05-17T01:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pkg/dir:alpha"}}]}}'
  echo '{"type":"assistant","uuid":"k2","timestamp":"2033-05-16T01:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"alpha"}}]}}'
  echo '{"type":"user","uuid":"k3","timestamp":"2033-04-01T01:00:00.000Z","message":{"content":"<command-name>/beta</command-name>"}}'
  echo '{"type":"assistant","uuid":"k4","timestamp":"2033-01-01T01:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"gamma"}}]}}'
  echo 'これは JSON ではない行'
  echo '[1,2,3]'
} > "$ROOT/projects/proj-a/s1.jsonl"
echo "$deny" > "$ROOT/projects/proj-b/s2.jsonl"
echo "$deny" > "$ROOT/projects/proj-a/sub/agent.jsonl"
echo "$deny" > "$ROOT/projects/proj-b/old.jsonl"
echo "$deny" > "$ROOT/projects/-Users-x--local-state-claude-loop-worktrees-demo/loop.jsonl"
touch -t 203305180333 "$ROOT/projects/-Users-x--local-state-claude-loop-worktrees-demo/loop.jsonl" "$ROOT/projects/proj-a/s1.jsonl" "$ROOT/projects/proj-b/s2.jsonl" "$ROOT/projects/proj-a/sub/agent.jsonl"
touch -t 203301010000 "$ROOT/projects/proj-b/old.jsonl"

for s in alpha beta gamma delta epsilon zeta; do mkdir -p "$ROOT/skills/$s"; echo x > "$ROOT/skills/$s/SKILL.md"; done
# git 管理外なので作成日はファイルの更新時刻で決まる。delta と gamma は期間より前、他は期間内
touch -t 203301010000 "$ROOT/skills/delta/SKILL.md" "$ROOT/skills/gamma/SKILL.md" "$ROOT/skills/epsilon/SKILL.md"
touch -t 203305100000 "$ROOT/skills/zeta/SKILL.md"
mkdir -p "$ROOT/projects/proj-a/s1/subagents"
echo '{"type":"assistant","uuid":"k5","timestamp":"2033-05-17T02:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"epsilon"}}]}}' > "$ROOT/projects/proj-a/s1/subagents/agent-1.jsonl"
echo '{"type":"assistant","uuid":"k6","timestamp":"2033-05-17T02:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"someplugin:delta"}}]}}' >> "$ROOT/projects/proj-a/s1/subagents/agent-1.jsonl"
mkdir -p "$ROOT/skills/not-a-skill"
"$CLI" --projects-dir "$ROOT/projects" --days 7 --skill-days 60 --skills-dir "$ROOT/skills" --now "$NOW" > "$ROOT/out.json"; rc=$?
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

ok "スキルの使用回数を数える(接頭辞つきの名前は同じスキル、スラッシュコマンドも数える)" "$(eq "$(q 'sorted((s["skill"],s["count"]) for s in d["skill_usage"])')" "[('alpha', 2), ('beta', 1), ('epsilon', 1)]")"
ok "手元に定義の無いコマンドとプラグインのスキルは別に数える" "$(eq "$(q 'sorted(s["skill"] for s in d["other_commands"])')" "['fix', 'someplugin:delta']")"
ok "サブエージェントの中で使われたスキルも数える(再発防止: 親のログに残らず未使用に見えた)" "$(eq "$(q '"epsilon" in d["skills_unused"]')" False)"
ok "同じ名前のプラグインのスキルが使われても、手元のスキルは未使用のまま" "$(eq "$(q '"delta" in d["skills_unused"]')" True)"
ok "期間より後に作ったスキルは削除の候補に入れない" "$(eq "$(q '(d["skills_too_new"], "zeta" in d["skills_unused"])')" "(['zeta'], False)")"
ok "読んだ会話の数を返す(少なければ未使用は根拠にならない)" "$(eq "$(q 'd["sessions_scanned"]')" 2)"
ok "最後に使った日を返す" "$(eq "$(q 'd["skill_usage"][0]["last_used"]')" 2033-05-17)"
ok "スキルの集計は手がかりより長い期間で見る(47日前の使用を数え、137日前は数えない)" "$(eq "$(q '"gamma" in d["skills_unused"] and "beta" not in d["skills_unused"]')" True)"
ok "定義されているのに使われていないスキルを返す(SKILL.md の無いディレクトリは除く)" "$(eq "$(q 'd["skills_unused"]')" "['delta', 'gamma']")"
ok "定義されているスキルの数を返す" "$(eq "$(q 'd["skills_defined"]')" 6)"

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
