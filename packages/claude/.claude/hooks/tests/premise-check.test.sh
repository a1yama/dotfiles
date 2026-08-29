#!/bin/bash
# premise-check.sh(UserPromptSubmit)の判定テスト。`bash tests/premise-check.test.sh` で実行する。
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/premise-check.sh"
pass=0
fail=0

check() {
  local expected="$1" desc="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected=%s actual=%s\n' "$desc" "$expected" "$actual"
  fi
}

# 注入されたかどうかと、どちらの文面かを判定する。none / rework / method
judge() {
  local out="$1" ctx
  ctx=$(printf '%s' "$out" \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  if [ -z "$ctx" ]; then
    echo none
  elif printf '%s' "$ctx" | grep -q '手戻りを検出'; then
    echo rework
  elif printf '%s' "$ctx" | grep -q '数値目標を検出'; then
    echo target
  elif printf '%s' "$ctx" | grep -q '手段の指定を検出'; then
    echo method
  else
    echo unknown
  fi
}

# run <expected> <説明> <prompt> [環境変数指定]
run() {
  local expected="$1" desc="$2" prompt="$3" env="${4:-}"
  local payload out
  payload=$(jq -n --arg p "$prompt" '{hook_event_name:"UserPromptSubmit",prompt:$p}')
  if [ -n "$env" ]; then
    out=$(printf '%s' "$payload" | env "$env" bash "$HOOK")
  else
    out=$(printf '%s' "$payload" | bash "$HOOK")
  fi
  check "$expected" "$desc" "$(judge "$out")"
}

# 手戻り: 「前のが間違っていた、直して」系
run rework "間違っていた"       'さっきの実装、間違っていたので直してください'
run rework "動かない"           'ビルドが動かないんだけど'
run rework "反映されていない"    '設定が反映されてないです'
run rework "元に戻して"         'さっきの変更を元に戻して'
run rework "そうじゃない"       'そうじゃない、もっと単純でいい'
run rework "英語 fix it"        'this is broken, fix it'
run rework "英語 not working"   'the gate is not working'
# 回帰: 事後の指摘。初版は拾えず、規約違反のコミットを指摘されたターンで発火しなかった
run rework "〜が正しいのに"     'git commit -m "update" が正しいのに余計なコメント入れたな'
run rework "〜すべきだった"     '規約どおりに書くべきだった'
run rework "残念"               '残念だったな'

# 数値目標: 数字を形式的に満たすだけの成果物を返してしまう形
run target "カバレッジ"         'カバレッジを80%まで上げて'
run target "全角パーセント"     '成功率を９９％にしたい'
run target "倍で指定"           'スループットを3倍にしてほしい'
run target "最大化"             'キャッシュヒット率を最大化する設定を出して'
run target "できるだけ多く"     'できるだけ多く候補を拾ってほしい'
run target "レイテンシのしきい値" 'p99 を200ms以下にして'
run target "英語 maximize"      'maximize the cache hit rate'
# 実際に失敗した依頼(keiba)。ドメインは違うが同じ形なので回帰テストとして原文のまま置く
run target "実例(回収率1000%)" \
  '的中率を追いすぎているから回収率1000%になる買い目を探してほしい'

# 数値目標は手段指定より優先する(疑うべき対象が深い方を選ぶ)
run target "数値と手段が両方あれば数値優先" \
  'Redis を使って応答を2倍速くして'
# 手戻りは数値目標より優先する(前回の手段を疑う方が先)
run rework "手戻りと数値が両方あれば手戻り優先" \
  '回収率1000%と言ったのに間違っている'

# 手段指定: 「どうやるか」が指定されている
run method "を使って"           'Redis を使ってキャッシュを実装して'
run method "ではなく"           'テーブルではなくカードで並べてほしい'
run method "の代わりに"         'grep の代わりに ripgrep を呼ぶようにして'
run method "に変えて"           'ポーリングに変えてください'
run method "英語 instead of"    'use a cron job instead of a daemon'

# 手戻りと手段指定が両方当たる依頼は手戻りを優先する
# (「前回の手段を疑え」の方が強い指示のため)
run rework "両方当たれば手戻り優先" 'Redis を使って直してください、今のは間違っている'

# 誤発火しない: 手段も手戻りも無い普通の依頼
run none "単純な調査依頼"       'このリポジトリの構造を教えて'
run none "新規実装の依頼"       'ログイン画面を追加してほしい'
run none "質問"                 'このフックはいつ発火しますか'
run none "空プロンプト"         ''

# スラッシュコマンド起動そのものは依頼文ではない
run none "スラッシュコマンド" '<command-message>frame-check</command-message>
<command-name>/frame-check</command-name>'
run none "コマンド定義が当たる文面でも素通し" \
  '<command-name>/fix</command-name> 間違いを直して'

# 手動オプトアウト
run none "CLAUDE_PREMISE_CHECK_OFF=1 で無効化" \
  'さっきの実装、間違っていたので直してください' 'CLAUDE_PREMISE_CHECK_OFF=1'

# 壊れた入力でも落ちない
out=$(printf 'not json' | bash "$HOOK")
check none "非JSON入力" "$(judge "$out")"
out=$(printf '{}' | bash "$HOOK")
check none "prompt キーなし" "$(judge "$out")"

# 注入文には必ず痕跡マーカーの指示が入る(Stop ゲートが探すのはこのマーカー)
out=$(jq -n '{prompt:"さっきの実装、間違っていたので直して"}' | bash "$HOOK")
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
check yes "マーカーの指示を含む" "$(printf '%s' "$ctx" | grep -q '⚖️' && echo yes || echo no)"
check yes "無条件追従の禁止を含む" "$(printf '%s' "$ctx" | grep -q '無条件の追従は禁止' && echo yes || echo no)"
check UserPromptSubmit "hookEventName が正しい" \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')"

# 手戻りの文面は、指摘を前提にせず先に裏取りさせる。
# 「間違っている」というユーザーの事実主張自体が誤っていることがある
check yes "指摘の裏取りを要求する" \
  "$(printf '%s' "$ctx" | grep -q '事実かを実物で確かめる' && echo yes || echo no)"
check yes "認識違いの可能性に言及する" \
  "$(printf '%s' "$ctx" | grep -q 'ユーザーの認識違い' && echo yes || echo no)"
# 反論のバー。これが無いと「鵜呑みをやめろ」が逆張りに振れる
check yes "検証できたときだけ反論させる" \
  "$(printf '%s' "$ctx" | grep -q '確認できたときだけ' && echo yes || echo no)"
check yes "逆張りを禁じる" \
  "$(printf '%s' "$ctx" | grep -q '逆張り' && echo yes || echo no)"

# 数値目標の文面は「数字を満たす成果物」ではなく「成り立つ根拠」を要求する。
# 文面が特定ドメイン(統計・データ分析)の語彙に寄ると、プログラミングの依頼で効かなくなる。
# 抜け道の例がコードの話であることを検査してドメイン汎用性を担保する
out=$(jq -n '{prompt:"カバレッジを80%まで上げて"}' | bash "$HOOK")
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
check yes "根拠と適用範囲を要求する" \
  "$(printf '%s' "$ctx" | grep -q '範囲と条件' && echo yes || echo no)"
check yes "満たせないと言い切る出口がある" \
  "$(printf '%s' "$ctx" | grep -q 'この条件では満たせない' && echo yes || echo no)"
check yes "抜け道の例がコードの話になっている" \
  "$(printf '%s' "$ctx" | grep -q 'アサーションを緩める' && echo yes || echo no)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
