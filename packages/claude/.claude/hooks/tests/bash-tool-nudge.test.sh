#!/bin/bash
# bash-tool-nudge.sh の判定テスト。`bash tests/bash-tool-nudge.test.sh` で実行する。
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-tool-nudge.sh"
pass=0
fail=0

# セッションマーカーの置き場を隔離する(実セッションの痕跡でテストが緩まないように)
TMPDIR=$(mktemp -d)
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

judge() {
  if printf '%s' "$1" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    echo deny
  else
    echo allow
  fi
}

check() {
  local expected="$1" desc="$2" actual="$3" command="$4"
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected=%s actual=%s\n  command=%s\n' \
      "$desc" "$expected" "$actual" "$command"
  fi
}

# run <expected: deny|allow> <説明> <コマンド文字列>
run() {
  local expected="$1" desc="$2" command="$3"
  local payload out
  payload=$(jq -n --arg c "$command" '{tool_name:"Bash",tool_input:{command:$c}}')
  out=$(printf '%s' "$payload" | bash "$HOOK")
  check "$expected" "$desc" "$(judge "$out")" "$command"
}

# run_session <expected> <説明> <コマンド> <session_id> <transcript の中身>
run_session() {
  local expected="$1" desc="$2" command="$3" sid="$4" body="$5"
  local tpath payload out
  tpath="$TMPDIR/transcript-$sid.jsonl"
  printf '%s\n' "$body" > "$tpath"
  payload=$(jq -n --arg c "$command" --arg s "$sid" --arg t "$tpath" \
    '{tool_name:"Bash",tool_input:{command:$c},session_id:$s,transcript_path:$t}')
  out=$(printf '%s' "$payload" | bash "$HOOK")
  check "$expected" "$desc" "$(judge "$out")" "$command"
}

# harness が実際に transcript へ書く形。$1 に不在ツール名、$2 に tool_use_id(既定 toolu_01)。
# ツールを呼んだ assistant 側と、その結果の user 側が id で対になる。
unavailable_line() {
  local tool="$1" id="${2:-toolu_01}"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"%s","input":{}}]}}\n' "$id" "$tool"
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"<tool_use_error>Error: No such tool available: %s. %s is not available in this session — use the Bash tool instead.</tool_use_error>","is_error":true,"tool_use_id":"%s"}]}}' "$tool" "$tool" "$id"
}

# 同じ文言を Bash の出力として吐いただけの行(偽装)。tool_use 側の name は Bash。
spoof_line() {
  local tool="$1" id="toolu_spoof"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"Bash","input":{"command":"echo spoof"}}]}}\n' "$id"
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"<tool_use_error>Error: No such tool available: %s. %s is not available in this session — use the Bash tool instead.</tool_use_error>","is_error":true,"tool_use_id":"%s"}]}}' "$tool" "$tool" "$id"
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
run allow "ls -t は更新時刻順なので許可" 'ls -t /tmp'
run allow "ls -S はサイズ順なので許可"  'ls -S /tmp'
run allow "find -mtime は許可"          'find . -name "*.log" -mtime -1'
run allow "find -exec は許可"           'find . -name "*.tmp" -exec rm {} ;'
run allow "find -size は許可"           'find . -size +10M'

# フラグ判定は最初のコマンドの引数列に限る(後段の引数で免除が成立しないこと)
run deny  "&& の後段の -S では免除しない"     'ls src && sort -S 1M f.txt'
run deny  "パイプ後段の -l では免除しない"    'ls src | column -l'
run deny  "&& の後段の -mtime では免除しない" 'find . -name "*.ts" && backup -mtime 3'
run allow "先頭コマンドの -S は免除する"      'ls -S /tmp | head'

# 短オプションの結合(順序を変えただけで弾かれないこと)
run allow "ls -al は許可"    'ls -al /tmp'
run allow "ls -alt は許可"   'ls -alt /tmp'
run allow "ls -tl は許可"    'ls -tl /tmp'
run deny  "ls -a は対象外フラグなので止める" 'ls -a /tmp'
run deny  "ls --color の l は拾わない"       'ls --color=auto src/'
run allow "echo の後段の 2>&1 に誤反応しない" 'echo start && go test ./... 2>&1'

# 区切り文字の判定は引用符の外だけを見る
run deny  "引用符内の ; でリダイレクト判定を迂回しない" "echo 'a;b' > out.txt"
run allow "引用符内の & は区切りにしない"               'find . -name "a&b" -mtime -1'

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

# 回帰: 代替ツールが存在しないセッションで deny し続ける手詰まりを起こさない
# (harness は「Bash の grep を使え」、フックは「Grep ツールを使え」と言うループ)
run_session allow "Grep 不在なら grep を通す" \
  'grep -n import src/app.ts' sess-a "$(unavailable_line Grep)"
run_session allow "Grep 不在なら rg も通す" \
  'rg foo src/' sess-a2 "$(unavailable_line Grep)"
run_session allow "Glob 不在なら ls を通す" \
  'ls src/' sess-b "$(unavailable_line Glob)"
run_session allow "Glob 不在なら find を通す" \
  'find . -name "*.ts"' sess-b2 "$(unavailable_line Glob)"
run_session allow "Read 不在なら cat を通す" \
  'cat README.md' sess-c "$(unavailable_line Read)"

# 免除はツール単位。別ツールの不在を根拠に他のコマンドまで緩めない
run_session deny  "Grep 不在でも cat は止める" \
  'cat README.md' sess-d "$(unavailable_line Grep)"

# 通常セッション(証跡なし)では今までどおり止める
run_session deny  "証跡なしの transcript では止める" \
  'grep -n import src/app.ts' sess-e '{"type":"user","message":{"role":"user","content":"hello"}}'
run_session deny  "transcript が空でも止める" \
  'grep -n import src/app.ts' sess-f ''

# 偽装耐性: モデルが書いたコマンド文字列にエラー文言が写り込んでも根拠にしない
run_session deny  "コマンド文字列中の同文言は根拠にしない" \
  'grep -n import src/app.ts' sess-g \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","input":{"command":"echo No such tool available: Grep."}}]}}'
run_session deny  "is_error が無い行は根拠にしない" \
  'grep -n import src/app.ts' sess-h \
  '{"type":"user","message":{"content":"<tool_use_error>Error: No such tool available: Grep.</tool_use_error>"}}'

# 偽装耐性: Bash の出力として同じ文言を吐いても免除しない(対になる tool_use が Bash のため)
run_session deny  "Bash の出力による偽装は通さない" \
  'grep -n import src/app.ts' sess-g2 "$(spoof_line Grep)"

# 誤検知耐性: 同一行に別レコードの is_error があっても、対応が取れなければ免除しない
run_session deny  "並列呼び出しの別レコードは根拠にしない" \
  'grep -n import src/app.ts' sess-g3 \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"<tool_use_error>Error: No such tool available: Grep.</tool_use_error>","tool_use_id":"toolu_a"},{"type":"tool_result","content":"Exit code 1","is_error":true,"tool_use_id":"toolu_b"}]}}'

# 対になる tool_use が存在しない(id が食い違う)なら免除しない
run_session deny  "id が対応しない tool_result は根拠にしない" \
  'grep -n import src/app.ts' sess-g4 \
  "$(printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_x","name":"Grep","input":{}}]}}\n{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"<tool_use_error>Error: No such tool available: Grep. x</tool_use_error>","is_error":true,"tool_use_id":"toolu_y"}]}}')"

# transcript_path が指すファイルが無くても落ちずに deny する
out=$(jq -n '{tool_name:"Bash",tool_input:{command:"grep foo a.ts"},session_id:"sess-i",transcript_path:"/nonexistent/transcript.jsonl"}' \
  | bash "$HOOK")
check deny "transcript が存在しないパス" "$(judge "$out")" 'grep foo a.ts'

# 一度検出したらセッション単位でキャッシュし、transcript を読み直さずに通す
run_session allow "キャッシュ前提の初回検出" 'grep foo a.ts' sess-j "$(unavailable_line Grep)"
run_session allow "2回目は証跡が消えても通す" 'grep foo a.ts' sess-j ''

# harness が記録したツール一覧に専用ツールが無ければ、エラーを出させなくても通す
# (再発防止: 「一度呼んでエラーを出す」案内は実行されず、例外の注記が毎回書かれていた)
shape_line() { # 引数: 一覧に入れるツール名
  local names
  names=$(printf '%s\n' "$@" | jq -R '{name: .}' | jq -s -c .)
  printf '{"type":"api-request-shape","sessionId":"s","shape":{"system":[],"tools":%s}}' "$names"
}
run_session allow "一覧に Grep が無ければ grep を通す" 'grep foo a.ts' sess-k "$(shape_line Bash Read Edit)"
run_session allow "一覧に Glob が無ければ ls を通す" 'ls src' sess-l "$(shape_line Bash Read Edit)"
run_session deny  "一覧に Read があれば cat は止める" 'cat a.ts' sess-m "$(shape_line Bash Read Edit)"
run_session deny  "一覧に Grep があれば grep は止める" 'grep foo a.ts' sess-n "$(shape_line Bash Read Grep)"
run_session deny  "最新の一覧を使う(後から Grep が増えたら止める)" 'grep foo a.ts' sess-o \
  "$(shape_line Bash Read; printf '\n'; shape_line Bash Read Grep)"
run_session deny  "一覧として読めない記録(Bash が無い)では通さない" 'grep foo a.ts' sess-p "$(shape_line Read Edit)"
run_session deny  "一覧が空なら通さない" 'grep foo a.ts' sess-q '{"type":"api-request-shape","shape":{"tools":[]}}'
run_session deny  "壊れた記録では通さない" 'grep foo a.ts' sess-r '{"type":"api-request-shape","shape":'
# shellcheck disable=SC2016 # JSON を文字のまま書く
run_session deny  "Bash の出力に一覧を出しても成りすませない" 'grep foo a.ts' sess-s \
  '{"type":"user","message":{"content":[{"type":"tool_result","content":"{\"type\":\"api-request-shape\",\"shape\":{\"tools\":[{\"name\":\"Bash\"}]}}","tool_use_id":"t"}]}}'

# 一覧での判定は残さない: 後から専用ツールが一覧に入ったら、同じ transcript でも止める
run_session allow "一覧に Grep が無い間は通す" 'grep foo a.ts' sess-t "$(shape_line Bash Read)"
run_session deny  "同じ transcript で後から Grep が入ったら止める(再発防止: 許可を残し続けた)" 'grep foo a.ts' sess-t \
  "$(shape_line Bash Read; printf '\n'; shape_line Bash Read Grep)"

# 案内の文面: 代替ツールは先頭のコマンド名だけで決めているので、使い方と合わない名前が出ることがある
# (範囲表示の sed に Edit、書き込みの cat に Read)。案内どおりにしても進めず、例外の注記か
# 別のコマンドでの書き込みに流れていた。止める範囲は変えず、使い方に合うツールを文面に添える。
# check_reason <has|lacks> <説明> <コマンド> <文面に含まれる/含まれない文字列>
check_reason() {
  local mode="$1" desc="$2" command="$3" needle="$4"
  local reason actual=lacks
  reason=$(jq -n --arg c "$command" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | bash "$HOOK" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  case "$reason" in *"$needle"*) actual=has ;; esac
  [ -n "$reason" ] || actual="no-deny"
  check "$mode" "$desc" "$actual" "$command"
}

READ_HINT='offset / limit'
WRITE_HINT='Write(新規・上書き)'
# shellcheck disable=SC2016 # awk のプログラムを文字のまま渡す
{
check_reason has   "範囲表示の sed には Read を案内する(再発防止)" "sed -n '60,70p' a.md" "$READ_HINT"
check_reason has   "後段の -i は先頭の sed の判定に使わない" "sed -n 1,5p a.md && sed -i s/a/b/ b.md" "$READ_HINT"
check_reason has   "awk の抜き出しには Read を案内する" "awk '{print \$1}' a.txt" "$READ_HINT"
check_reason lacks "書き換えの sed -i には Read を案内しない" "sed -i '' 's/a/b/' a.ts" "$READ_HINT"
check_reason lacks "sed --in-place にも Read を案内しない" "sed --in-place 's/a/b/' a.ts" "$READ_HINT"
check_reason has   "追記の cat には Write / Edit を案内する(再発防止)" "cat >> a.md <<'EOF'
x
EOF" "$WRITE_HINT"
check_reason has   "上書きの cat には Write / Edit を案内する" 'cat > a.md' "$WRITE_HINT"
check_reason has   "head の出力を書き込む形にも案内する" 'head -n 3 a.ts > b.ts' "$WRITE_HINT"
check_reason lacks "読むだけの cat には書き込みの案内を出さない" 'cat a.ts' "$WRITE_HINT"
check_reason lacks "エラー出力の捨て先は書き込みに数えない" 'cat a.ts 2>/dev/null' "$WRITE_HINT"
check_reason lacks "2>&1 は書き込みに数えない" 'cat a.ts 2>&1' "$WRITE_HINT"
check_reason lacks "後段のリダイレクトは先頭の cat の判定に使わない" 'cat a.ts | sort > b.ts' "$WRITE_HINT"
check_reason lacks "grep には読み書きの案内を足さない" 'grep foo a.ts' "$READ_HINT"
check_reason lacks "grep には書き込みの案内を足さない" 'grep foo a.ts' "$WRITE_HINT"
# 文頭は変えない(拒否の集計が文頭の1文を種類の名前にしている)
check_reason has   "sed の文頭は変えない" "sed -n '60,70p' a.md" 'ツール選択ルール(CLAUDE.md): `sed` は専用ツール Edit を使ってください。'
check_reason has   "cat の文頭は変えない" 'cat > a.md' 'ツール選択ルール(CLAUDE.md): `cat` は専用ツール Read を使ってください。'
}
# 案内を足しても止める範囲は同じ
run deny  "範囲表示の sed は止める" "sed -n '60,70p' a.md"
run deny  "追記の cat は止める" 'cat >> a.md'

# 手動オプトアウト
out=$(jq -n '{tool_name:"Bash",tool_input:{command:"grep foo a.ts"}}' \
  | CLAUDE_BASH_NUDGE_OFF=1 bash "$HOOK")
check allow "CLAUDE_BASH_NUDGE_OFF=1 で無効化" "$(judge "$out")" 'grep foo a.ts'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
