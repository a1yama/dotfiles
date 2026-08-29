#!/bin/bash
# Stop フック: 「指示された手段を検証せずに実装して終わる」のを終了前に差し戻す。
#
# premise-check.sh が着手前に注入する前提チェックは、UserPromptSubmit が deny できない
# イベントである以上ただの訓示にすぎず、追従圧が強い局面ほど読み飛ばされる
# (まさにその局面のために作った仕掛けなので、素通しでは意味がない)。
# ここで痕跡の有無だけを機械的に検査して、注入と対にする。
#
# 検査するのは「検討した痕跡があるか」だけで、「検討の中身が妥当か」は見ない。
# 妥当性は意味論でフックには判定できないため、書かせた内容はユーザーが読んで判断する。
# 痕跡さえ書けば通る形式ではあるが、`⚖️ 前提` の3行(目的 / 指定手段の妥当性 / 採否)は
# 埋めるために実際に代替案を1つは生成する必要があり、そこが「何も疑わない」との分かれ目になる。
#
# 発火条件を3つ重ねているのは誤発火対策。誤って毎ターン止めると読み飛ばされて機構ごと死ぬ。
#   1. 直近のユーザー依頼に手戻り/手段指定のシグナルがある
#   2. そのターンで実際にファイルを変更している(調査だけのターンは対象外)
#   3. ツール実行が閾値以上(typo 修正のような些末な依頼で止めない)
#
# CLAUDE_PREMISE_CHECK_OFF=1 で無効化、PG_MINCALLS で閾値を上書きできる。
set -u

[ "${CLAUDE_PREMISE_CHECK_OFF:-}" = "1" ] && exit 0

input=$(cat)

# block からの継続後の再停止は素通しする(無限ループ防止。他の Stop ゲートと同じ)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

threshold="${PG_MINCALLS:-8}"
# 非数値だと [ -lt ] が偽に倒れて「常に block」になる。無効化のつもりの誤記で
# 全セッションの終了が止まる方が害が大きいので、既定値へ落とす(stop-frame-check.sh と同じ)
case "$threshold" in
  ''|*[!0-9]*) threshold=8 ;;
esac

# shellcheck source=premise-signals.sh disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/premise-signals.sh"

# 直近の「人間の発話」。tool_result の user 行(本文が空になる)とサイドチェーンは除く。
# 行番号も一緒に取るのは、以降のツール実行だけを数えるため
meta=$(jq -r '
  select(type == "object")
  | select(.type == "user")
  | select((.isSidechain // false) | not)
  | (.message.content) as $c
  | (if ($c | type) == "string" then $c
     else ([$c[]? | select(.type == "text") | .text] | join("\n")) end) as $t
  | select($t != null and $t != "")
  | "\(input_line_number)\t\($t)"
' "$transcript" 2>/dev/null | tail -n 1)
[ -n "$meta" ] || exit 0

ln="${meta%%$'\t'*}"
prompt="${meta#*$'\t'}"
case "$ln" in
  ''|*[!0-9]*) exit 0 ;;
esac

signal=$(premise_signal "$prompt")
[ -n "$signal" ] || exit 0

rest=$(tail -n +$((ln + 1)) "$transcript" | grep -v '"isSidechain":true')

# ファイル変更の有無は条件にしない。数値目標の失敗(条件を絞り込んで数字だけ合わせた案を
# 本文で提示する)は編集を伴わないため、編集を要求すると一番危ない形をまるごと取りこぼす。
# 些末な依頼を止めないための絞り込みはツール実行数だけで行う
calls=$(printf '%s' "$rest" | grep -o '"type":"tool_use"' | wc -l | tr -d ' ')
[ "${calls:-0}" -lt "$threshold" ] && exit 0

# 前提を検討した痕跡。行頭の ⚖️ だけを見る。
# 本文中で記号に言及しただけの行を拾わないための行頭アンカーで、
# jq の正規表現は既定で ^ が文字列先頭のため (^|\n) で明示する。
#
# 見出し記号 (### ⚖️ 前提) を許すのは、CLAUDE.md が節ラベルの見出し化を認めているため。
# 素の行頭だけを見ていた初版は、規約どおりに書いた最終応答を差し戻した(自分で踏んだ)
if printf '%s' "$rest" | jq -e '
      select(type == "object")
      | select(.type == "assistant")
      | (.message.content) as $c
      | (if ($c | type) == "string" then $c
         else ([$c[]? | select(.type == "text") | .text] | join("\n")) end)
      | select(test("(^|\\n)[ \\t]*(#{1,6}[ \\t]+)?⚖️"))
    ' >/dev/null 2>&1; then
  exit 0
fi

case "$signal" in
  rework)
    head='直近の依頼は「前の成果物が間違っていた」という手戻りですが、指摘の裏取りと原因を検討した痕跡がありません。'
    body='- 事実: <指摘が事実か。何を見て確認したか。認識違い・別原因・既に直っている、もあり得る>
- 原因: <なぜそうなったか。前回選んだ手段そのものが原因ではないかを最初に疑う>
- 採否: <指示された修正が打ち手か、対症療法か。従うなら根拠、変えるなら具体的な代替案>'
    tail_msg='より良い手段があるなら、書くだけで済ませず AskUserQuestion で採否を問うてください。確認して指摘と食い違ったら「違います」と根拠付きで言ってください。ただし確認できたときだけです(逆張りは鵜呑みと同じだけ害があります)。'
    ;;
  target)
    head='直近の依頼に満たすべき数字・条件が含まれていますが、それが目的の代理として妥当かを検討した痕跡がありません。求められているのは数字を満たした成果物ではなく、その数字が成り立つ根拠です。'
    body='- 目的: <数字の背後にある狙い>
- 指定された数値: <その数字>が目的の代理として妥当か
- 採否: 数字が成り立つ根拠と適用範囲、または「満たせない/満たしても目的を外す」という判定'
    tail_msg='出した案が「数字だけ満たす抜け道」になっていないかを点検してください(アサーションを緩めてテストを通す、型を any にしてビルドを通す、測定条件でだけ速くする、条件を後から絞り込んで数字を合わせる)。満たせないなら「この条件では満たせない」と言い切り、代わりに何を見るべきかを出してください。'
    ;;
  *)
    head='直近の依頼に手段の指定が含まれていますが、その手段が最善かを検討した痕跡がありません。'
    body='- 目的: <指示の文面ではなく、達成したいこと>
- 指定された手段: <言われたやり方>が目的に対して最善か
- 採否: 従うなら根拠、変えるなら具体的な代替案'
    tail_msg='より良い手段があるなら、書くだけで済ませず AskUserQuestion で採否を問うてください。'
    ;;
esac

jq -n --arg h "$head" --arg b "$body" --arg m "$tail_msg" \
  '{decision:"block", reason:($h+"\n終了前に、最終応答へ `⚖️ **前提**` 節を置いて3行で残してください。\n"+$b+"\n\n"+$m+"\n指示どおりで妥当なときも「妥当」と根拠付きで書きます。「言われたとおりにした」で終えないでください。")}'
exit 0
