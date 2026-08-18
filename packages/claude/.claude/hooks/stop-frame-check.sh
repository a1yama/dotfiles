#!/bin/bash
# Stop フック: 作業が一定量たまったら frame-check スキル(方針の監査)を要求する。
#
# 狙いは「進行方向が間違っていることに、進んでいる本人が気づけない」失敗。
# 単一の評価軸で全ての選択肢を裁く、捨てたものの価値を再検査しない、他エージェントの
# 助言を記録だけして実行しない — いずれも数時間〜数日続いてユーザーの指摘で初めて露見した。
#
# 起動判断をモデルに任せる設計(スキル単体・CLAUDE.md への訓示)は原理的に効かない。
# 「立ち止まるべきだ」と気づく判断そのものが壊れているのが本症状なので、
# トリガーだけは外部から機械的に引く必要がある。一方「枠組みが妥当か」は意味論であり
# フックには判定できないため、判定はスキル + frame-review-fable(別コンテキスト)に委ねる。
#
# 閾値はターン単位ではなく transcript 累積(前回の frame-check 痕跡以降)で数える。
# 対象の失敗は「1つの長いターン」ではなく「中規模のターンが何日も続く」形で起きるため、
# ターン毎にリセットすると永久に閾値へ届かない。
#
# 閾値 400 は実測から決めた。~/.claude/projects の 51 セッション(2026-08-10 時点、
# 中央値 83 / 平均 312 / 最大 2802 コール)に当てた場合の発火回数:
#   閾値  50 → 総 297 回・最重量セッションで 56 回(監査が常時走るのと変わらずコスト倒れ)
#   閾値 400 → 総  27 回・最重量セッションで  7 回・発火するのは 51 本中 14 本
# 中央値規模の短いセッションは発火せず、長時間の重い作業だけが対象になる。
#
# CLAUDE_FRAME_CHECK_OFF=1 で無効化、FC_TOOLCALLS で閾値を上書きできる。
set -u

[ "${CLAUDE_FRAME_CHECK_OFF:-}" = "1" ] && exit 0

input=$(cat)

# block からの継続後の再停止は素通しする(無限ループ防止。stop-quality-gate.sh と同じ)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

threshold="${FC_TOOLCALLS:-400}"
# 非数値だと [ -lt ] が偽に倒れて「常に block」になる。無効化のつもりの誤記で
# 全セッションの終了が止まる方が害が大きいので、既定値へ落とす
case "$threshold" in
  ''|*[!0-9]*) threshold=400 ;;
esac

# 直近の frame-check 実行の行番号。実行の記録形式は2つあり、両方を見る必要がある。
#   - Skill ツール呼び出し     → "skill":"frame-check"
#   - スラッシュコマンド起動   → <command-name>/frame-check</command-name>(Skill 呼び出しは発生しない)
# 前者だけを見ると、ユーザーが /frame-check で監査させてもカウンタがリセットされない。
#
# 前者はクォートを含むため、このファイルやテストを読んでも JSON エスケープされて一致しない。
# 後者はそうならない — JSON は / < > をエスケープしないので、単純な文字列一致だと
# このフックのソース・テストデータ・git diff 出力を読んだ行そのものが「実行の痕跡」になり、
# フックの保守作業中(=まさに長時間作業)にカウンタがリセットされる。
# そのため候補行を構造で検証し、「ユーザー入力そのものがタグで始まる」ことまで要求する。
# 実データの形は `<command-message>frame-check</command-message>\n<command-name>/frame-check</command-name>`
# (組み込みコマンドは <command-message> が無く、先頭に空白が入ることもある)。
# 形式を推測して ^<command-name> にアンカーすると、スキル由来の起動を丸ごと取りこぼす。
last=$(awk '/"skill"[[:space:]]*:[[:space:]]*"[^"]*frame-check"/{n=NR} END{print n+0}' "$transcript")

while IFS=: read -r ln rest; do
  [ -n "${ln:-}" ] || continue
  printf '%s' "$rest" | jq -e '
      select(.type == "user")
      | .message.content
      | (if type == "string" then . else ([.[]? | .text? // empty] | join("")) end)
      | test("^\\s*(<command-message>[^<]*</command-message>\\s*)?<command-name>/?frame-check</command-name>")
    ' >/dev/null 2>&1 || continue
  [ "$ln" -gt "$last" ] && last="$ln"
done <<EOF
$(grep -n '<command-name>' "$transcript" 2>/dev/null)
EOF

# 差し戻しを出した地点も起点として扱う。
# reason は「監査が不要と判断するなら理由を明示して終える」という出口を案内しているが、
# その行為自体は transcript 上の痕跡にならない。記録しないと、棄却しても次のターン末で
# 同じ条件が再成立し、frame-check を実際に走らせるまで毎ターン差し戻しが続く
# (stop_hook_active が抑止するのは直後の再停止1回だけ)。
# 記録しておけば、棄却された場合も次の要求はさらに threshold 回ぶん先になる。
marker_dir="${TMPDIR:-/tmp}/claude-frame-check"
marker="$marker_dir/$(printf '%s' "$transcript" | shasum | awk '{print $1}')"
if [ -f "$marker" ]; then
  demanded=$(cat "$marker" 2>/dev/null)
  case "${demanded:-}" in
    ''|*[!0-9]*) demanded=0 ;;
  esac
  [ "$demanded" -gt "$last" ] && last="$demanded"
fi

# その行以降のツール呼び出し数。
# 現行の harness はサブエージェントの行を projects/<sid>/subagents/ の別ファイルへ分けるため
# isSidechain の除外は実質 no-op だが、同一 transcript に混ざる形式へ戻ったときの保険として残す
# (混ざると監査対象でない呼び出しで閾値に達してしまう)
calls=$(tail -n +$((last + 1)) "$transcript" \
  | grep -v '"isSidechain":true' \
  | grep -o '"type":"tool_use"' \
  | wc -l \
  | tr -d ' ')

[ "$calls" -lt "$threshold" ] && exit 0

# 次の要求はここからさらに threshold 回ぶん先にする(上のコメント参照)
mkdir -p "$marker_dir" 2>/dev/null \
  && wc -l < "$transcript" | tr -d ' ' > "$marker" 2>/dev/null

jq -n --arg c "$calls" --arg t "$threshold" \
  '{decision:"block", reason:("前回の点検からツール実行が "+$c+" 回に達しました(閾値 "+$t+")。終了前に frame-check スキルを実行し、いま進めている方針がユーザーの目的と合っているかを監査してください。\n指摘は 実行 / タスク化 / 理由付きで棄却 / AskUserQuestion のいずれかで処理してから終了してください(記録するだけは不可)。\n監査が不要と判断する場合は、その理由を最終報告に明示してください。")}'
exit 0
