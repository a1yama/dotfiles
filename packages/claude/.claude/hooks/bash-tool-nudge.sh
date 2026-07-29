#!/bin/bash
# PreToolUse(Bash) フック: ファイル操作を Bash で行おうとしたら専用ツールへ差し戻す。
#
# 2026-06-28 から additionalContext による警告のみで運用したが、直近7日でも
# grep 始まり 286 回 / ls・find 始まり 64 回と行動が変わらなかったため deny に格上げした。
# 誤検知の害を抑えるため、判定は「コマンド先頭トークン」に限る
# (例: `git log | grep` は git 始まりなので対象外)。
#
# 専用ツールで代替できない正当なケースは2通りで通す:
#   1. 代替不能なフラグ(tail -f / ls -l / find の時刻・サイズ述語)は自動で許可
#   2. それ以外は `# tool-exception: 理由` をコマンドに付けて明示する
#      (理由を書けないなら例外ではない、というルールをそのまま仕組みにしたもの)
set -u

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# 理由付きの例外は無条件で通す
case "$cmd" in
  *"# tool-exception:"*) exit 0 ;;
esac

# 先頭のコメント行・空行を読み飛ばし、最初の実コマンドの第1トークンを取る
first=$(printf '%s\n' "$cmd" \
  | grep -vE '^[[:space:]]*(#|$)' \
  | head -n1 \
  | sed -E 's/^[[:space:]]+//' \
  | awk '{print $1}')
[ -z "$first" ] && exit 0

alt=""
case "$first" in
  cat|head)  alt="Read" ;;
  tail)
    # -f/-F の追従は Read で代替できない
    case "$cmd" in *" -f"*|*" -F"*) exit 0 ;; esac
    alt="Read"
    ;;
  grep|rg)   alt="Grep" ;;
  ls)
    # パーミッション・シンボリックリンク先は Glob では取れない
    case "$cmd" in *" -l"*) exit 0 ;; esac
    alt="Glob"
    ;;
  find)
    # 時刻・サイズ・実行系の述語は Glob では表現できない
    case "$cmd" in
      *" -exec"*|*" -delete"*|*" -mtime"*|*" -mmin"*|*" -newer"*|*" -size"*) exit 0 ;;
    esac
    alt="Glob"
    ;;
  sed|awk)   alt="Edit" ;;
  echo)
    # 追記・上書きリダイレクトのときだけ Write を促す
    case "$cmd" in
      *">>"*|*"> "*|*">"*) alt="Write" ;;
    esac
    ;;
esac

[ -z "$alt" ] && exit 0

jq -n --arg t "$first" --arg a "$alt" \
  '{hookSpecificOutput:{
      hookEventName:"PreToolUse",
      permissionDecision:"deny",
      permissionDecisionReason:("ツール選択ルール(CLAUDE.md): `"+$t+"` は専用ツール "+$a+" を使ってください。Bash は最後の手段です。専用ツールで代替できない場合のみ、コマンドに `# tool-exception: <理由>` を添えて再実行してください(理由を書けないなら例外ではありません)。")
   }}'
exit 0
