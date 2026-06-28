#!/bin/bash
# PreToolUse(Bash) フック: ファイル操作を Bash で行おうとした場合に専用ツールを促す。
# ブロックはせず additionalContext でモデルに注意を返す(warn)。誤検知の害を最小化するため、
# 「コマンド先頭トークンが対象」のときだけ警告する(例: `git log | grep` は git 始まりなので対象外)。
set -u

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# 先頭の空白を除去して第1トークンを取得
first=$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]+//' | awk '{print $1}')

alt=""
case "$first" in
  cat|head|tail) alt="Read" ;;
  grep|rg)       alt="Grep" ;;
  find|ls)       alt="Glob" ;;
  sed|awk)       alt="Edit" ;;
  echo)
    # 追記・上書きリダイレクトのときだけ Write を促す
    case "$cmd" in
      *">>"*|*"> "*|*">"*) alt="Write" ;;
    esac
    ;;
esac

[ -z "$alt" ] && exit 0

jq -n --arg t "$first" --arg a "$alt" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("ツール選択ルール: `"+$t+"` はファイル操作なら専用ツール "+$a+" で代替してください(CLAUDE.md)。Bash は最後の手段。コマンド出力に対するパイプ等で正当に必要な場合のみ続行。")}}'
exit 0
