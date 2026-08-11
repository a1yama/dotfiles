#!/bin/bash
# Stop フック: frame-check(方向の監査)と quality-gate(コードの質)を実行するディスパッチャー。
# Stop フックは並列実行されるため、個別登録だと gate に差し戻された未完了の時点で
# 「完了」通知が飛んでしまう。いずれかが block したときは通知を出さない。
#
# 両ゲートは「どちらかが block したら残りを飛ばす」ではなく必ず両方走らせ、
# 差し戻し理由を連結して1つの block にする。片方で打ち切ると、block からの継続後の
# 再停止は stop_hook_active=true になり後段のゲートも自前のループ防止で即 exit するため、
# そのターンで一度も走らないまま通知まで抜けてしまう
# (frame-check が発火する長いターンほどテストと code-review が要る、という逆転が起きる)。
#
# CLAUDE_HOOKS_DIR / CLAUDE_NOTIFY_BIN はテストからの差し替え用。
set -u

input=$(cat)

hooks="${CLAUDE_HOOKS_DIR:-$HOME/dotfiles/packages/claude/.claude/hooks}"
notify="${CLAUDE_NOTIFY_BIN:-$HOME/.local/bin/claude-notify}"

frame_out=$(printf '%s' "$input" | "$hooks/stop-frame-check.sh")
gate_out=$(printf '%s' "$input" | "$hooks/stop-quality-gate.sh")

if [ -n "$frame_out" ] || [ -n "$gate_out" ]; then
  # 各ゲートの出力を個別に検証して reason を集める。まとめて jq に流すと、片方が壊れた出力を
  # 返しただけで全体が失敗し、もう片方の正当な差し戻し(テスト失敗など)まで捨ててしまう
  reasons=""
  for out in "$frame_out" "$gate_out"; do
    [ -n "$out" ] || continue
    reason=$(printf '%s' "$out" \
      | jq -r 'if type == "object" then (.reason // empty) else empty end' 2>/dev/null)
    [ -n "$reason" ] || continue
    reasons="${reasons:+$reasons

}$reason"
  done

  if [ -n "$reasons" ]; then
    jq -n --arg r "$reasons" '{decision:"block", reason:$r}'
    exit 0
  fi

  # 有効な JSON が1つも無い場合でも差し戻しは落とさない(素通しより安全)。
  # ただし出力をそのまま連結すると有効な JSON にならず harness に無視され、
  # 差し戻しも通知も消える。整形した block にして必ず伝える
  jq -n --arg o "$frame_out$gate_out" \
    '{decision:"block", reason:("Stop フックのゲートが不正な出力を返しました。フックを確認してください:\n"+($o[0:500]))}'
  exit 0
fi

# 通知の終了ステータスをそのまま返さない。Stop フックの exit 2 は
# 「stderr を理由にした差し戻し」と解釈されるため、通知が落ちただけで
# ユーザーには理由不明の差し戻しに見えてしまう
printf '%s' "$input" | "$notify"
exit 0
