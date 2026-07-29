#!/bin/bash
# bash-tool-nudge.sh の判定テスト。`bash tests/bash-tool-nudge.test.sh` で実行する。
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-tool-nudge.sh"
pass=0
fail=0

# run <expected: deny|allow> <説明> <コマンド文字列>
run() {
  local expected="$1" desc="$2" command="$3"
  local payload out actual
  payload=$(jq -n --arg c "$command" '{tool_name:"Bash",tool_input:{command:$c}}')
  out=$(printf '%s' "$payload" | bash "$HOOK")
  if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    actual="deny"
  else
    actual="allow"
  fi
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected=%s actual=%s\n  command=%s\n' \
      "$desc" "$expected" "$actual" "$command"
  fi
}

# 正常系: 専用ツールで代替できるものは止める
run deny  "grep でファイル検索"        'grep -n "foo" src/app.ts'
run deny  "rg でファイル検索"          'rg foo src/'
run deny  "cat でファイル読み"          'cat README.md'
run deny  "head でファイル読み"         'head -20 README.md'
run deny  "tail でファイル読み"         'tail -20 app.log'
run deny  "ls で一覧"                   'ls src/'
run deny  "find で検索"                 'find . -name "*.ts"'
run deny  "sed で編集"                  'sed -i "" "s/a/b/" file.txt'
run deny  "awk で加工"                  'awk -F, "{print}" data.txt'
run deny  "echo の上書きリダイレクト"   'echo "hello" > out.txt'
run deny  "echo の追記リダイレクト"     'echo "hello" >> out.txt'

# 正常系: 対象外のコマンドは素通しする
run allow "make は対象外"               'make test'
run allow "git は対象外"                'git status'
run allow "パイプ先の grep は対象外"    'git log --oneline | grep fix'
run allow "リダイレクトなし echo"       'echo hello'

# 代替不能なフラグは自動で許可する
run allow "tail -f は追従なので許可"    'tail -f /var/log/app.log'
run allow "tail -F も許可"              'tail -F /var/log/app.log'
run allow "ls -l は権限表示なので許可"  'ls -l /tmp'
run allow "ls -la も許可"               'ls -la ~/.claude'
run allow "find -mtime は許可"          'find . -name "*.log" -mtime -1'
run allow "find -exec は許可"           'find . -name "*.tmp" -exec rm {} ;'
run allow "find -size は許可"           'find . -size +10M'

# 理由付き例外は通す
run allow "末尾コメントで理由明示"      'grep -c foo big.log # tool-exception: 件数だけ必要'
run allow "先頭コメントで理由明示"      '# tool-exception: 巨大ログの集計
grep foo huge.log | wc -l'

# 境界値・不正入力
run deny  "先頭のコメント行は読み飛ばす" '# 依存を調べる
grep -n import src/app.ts'
run deny  "先頭の空行は読み飛ばす"      '
grep -n import src/app.ts'
run deny  "インデント付きコマンド"      '   grep foo file.txt'
run allow "空コマンド"                  ''
run allow "コメントのみ"                '# 何もしない'

# tool_input.command が無い/壊れた入力でも落ちない(素通し)
for payload in '{"tool_name":"Read","tool_input":{"file_path":"a.ts"}}' '{}' 'not json'; do
  out=$(printf '%s' "$payload" | bash "$HOOK")
  status=$?
  if [ $status -eq 0 ] && ! printf '%s' "$out" | grep -q '"deny"'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: 不正入力で素通ししない payload=%s status=%s out=%s\n' "$payload" "$status" "$out"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
