#!/bin/bash
# PreToolUse(AskUserQuestion) フック: 選択肢 UI がキー入力を受け付けなくなるのを防ぐ。
# ラベルが折り返す・preview が付くと矢印キー/Enter が効かなくなる事象があるため、
# additionalContext での警告ではなく deny で確実に弾いて短いラベルで出し直させる。
set -u

payload=$(cat)

# label の長さは表示幅で測る。全角(U+3000 以上)を 2 桁として数える。
violations=$(printf '%s' "$payload" | jq -r '
  def width: explode | map(if . >= 12288 then 2 else 1 end) | add // 0;
  [ .tool_input.questions[]? as $q
    | $q.options[]?
    | (.label // "") as $l
    | if (.preview // null) != null then "preview付き: \($l)"
      elif ($l | width) > 20 then "ラベル長すぎ(\($l | width)桁): \($l)"
      else empty end
  ] | join(" / ")
' 2>/dev/null)

[ -z "$violations" ] && exit 0

jq -n --arg v "$violations" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("AskUserQuestion 制約違反 → " + $v + " | label は表示幅20桁以内(全角10文字目安)、preview は使用禁止(CLAUDE.md)。補足は description に移し、見せたい差分は本文に書いてから出し直してください。")}}'
exit 0
