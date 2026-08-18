#!/bin/bash
# PreToolUse(Bash) フック: ファイル操作を Bash で行おうとしたら専用ツールへ差し戻す。
#
# 2026-06-28 から additionalContext による警告のみで運用したが、直近7日でも
# grep 始まり 286 回 / ls・find 始まり 64 回と行動が変わらなかったため deny に格上げした。
# 誤検知の害を抑えるため、判定は「コマンド先頭トークン」に限る
# (例: `git log | grep` は git 始まりなので対象外)。
#
# 専用ツールで代替できない正当なケースは3通りで通す:
#   1. 代替不能なフラグ(tail -f / ls -l / find の時刻・サイズ述語)は自動で許可
#   2. 代替ツールがそのセッションに存在しない場合は自動で許可 (2026-08-10 追加)
#   3. それ以外は `# tool-exception: 理由` をコマンドに付けて明示する
#      (理由を書けないなら例外ではない、というルールをそのまま仕組みにしたもの)
#
# 2 の背景: Grep/Glob が無効なセッションが実在し、harness は「grep を Bash で使え」、
# このフックは「Grep ツールを使え」と言う出口のないループになっていた。差し戻しても
# 解決しない以上、deny はノイズにしかならず、常態化した tool-exception が
# 1 の抑止力ごと壊す。判定は harness だけが書く tool_result のエラー文言を根拠にし、
# そのエラーが「当のツールを呼んだ結果」であることまで tool_use_id で突き合わせる
# (Bash の出力に同じ文言を出しただけでは免除が成立しないようにするため)。
# 代替ツールがある通常セッションではこの分岐に入らないので、deny の強度は変わらない。
#
# 最終手段の手動オプトアウトとして CLAUDE_BASH_NUDGE_OFF=1 で全体を無効化できる。
set -u

[ "${CLAUDE_BASH_NUDGE_OFF:-}" = "1" ] && exit 0

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# 理由付きの例外は無条件で通す
case "$cmd" in
  *"# tool-exception:"*) exit 0 ;;
esac

# 先頭のコメント行・空行を読み飛ばし、最初の実コマンドの第1トークンを取る
line=$(printf '%s\n' "$cmd" \
  | grep -vE '^[[:space:]]*(#|$)' \
  | head -n1 \
  | sed -E 's/^[[:space:]]+//')
first=$(printf '%s' "$line" | awk '{print $1}')
[ -z "$first" ] && exit 0

# フラグ判定に使う範囲を「最初のコマンドの引数列」に限る。
# コマンド文字列全体に部分一致させると、パイプや && の後段の引数で免除が成立してしまう
# (例: `ls src && sort -S 1M f.txt` が ls の -S 免除に、`echo x && cmd 2>&1` が echo の
#  リダイレクト判定に引っかかる)。
# 区切り文字は引用符の外にあるものだけを見る。単純に最初の | ; & で切ると
# `echo 'a;b' > f` が `echo 'a` になってリダイレクト判定を迂回できてしまう。
seg=$(printf '%s' "$line" | awk '{
  q = ""; out = ""
  for (i = 1; i <= length($0); i++) {
    c = substr($0, i, 1)
    if (q == "") {
      if (c == "\"" || c == "\047") { q = c }
      else if (c == "|" || c == ";" || c == "&") { break }
    } else if (c == q) { q = "" }
    out = out c
  }
  print out
}')

alt=""
case "$first" in
  cat|head)  alt="Read" ;;
  tail)
    # -f/-F の追従は Read で代替できない
    case "$seg" in *" -f"*|*" -F"*) exit 0 ;; esac
    alt="Read"
    ;;
  grep|rg)   alt="Grep" ;;
  ls)
    # 権限・シンボリックリンク先・更新時刻順・サイズ順は Glob では取れない。
    # 短オプションは結合されるので(-la / -al / -alt)、トークン単位で対象文字を探す。
    # --color のような長いオプションに含まれる l を拾わないよう -- は除外する。
    # set -f はパス名展開の抑止。非クォート展開のままだと `ls *.md` の * がフック実行時の
    # cwd に対して展開され、判定対象がコマンド行と別物になる
    set -f
    # shellcheck disable=SC2086 # 引数列を単語に割るための意図的な非クォート
    for w in $seg; do
      case "$w" in
        --*) ;;
        -*[ltS]*) set +f; exit 0 ;;
      esac
    done
    set +f
    alt="Glob"
    ;;
  find)
    # 時刻・サイズ・実行系の述語は Glob では表現できない
    case "$seg" in
      *" -exec"*|*" -delete"*|*" -mtime"*|*" -mmin"*|*" -newer"*|*" -size"*) exit 0 ;;
    esac
    alt="Glob"
    ;;
  sed|awk)   alt="Edit" ;;
  echo)
    # 追記・上書きリダイレクトのときだけ Write を促す
    case "$seg" in
      *">>"*|*"> "*|*">"*) alt="Write" ;;
    esac
    ;;
esac

[ -z "$alt" ] && exit 0

# $1 のツールが「この実行コンテキストには存在しない」と harness が返した痕跡があるか。
# 走査は deny 手前でしか走らず、見つかったらマーカーに残して以降は transcript を読み直さない
# (ツールの有無は同一 transcript の間は変わらない)。
#
# マーカーのキーは session_id ではなく transcript_path。session_id は親セッションと
# サブエージェントで共有される一方、利用可能なツールはコンテキストごとに異なるため、
# session_id をキーにすると Grep/Glob を持たないサブエージェントが1体走っただけで
# 親セッションの deny まで無効化される。サブエージェントは
# projects/<sid>/subagents/agent-*.jsonl の別ファイルなので transcript なら区別できる。
# ハッシュ化しているので harness 由来の値がそのままパスに入ることもない。
tool_unavailable() {
  tu_tool="$1"
  tu_transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -n "$tu_transcript" ] && [ -f "$tu_transcript" ] || return 1

  tu_dir="${TMPDIR:-/tmp}/claude-bash-tool-nudge"
  tu_marker="$tu_dir/$(printf '%s' "$tu_transcript" | shasum | awk '{print $1}').${tu_tool}"
  [ -f "$tu_marker" ] && return 0

  # 判定は tool_use_id での突き合わせで行う。
  # 「同じ行にエラー文言と is_error:true がある」だけでは、並列呼び出しで別レコードの
  # is_error を拾う誤検知と、Bash の出力に同じ文言を出すだけの偽装の両方が通ってしまう。
  # 該当 tool_result と対になる tool_use の name が当のツールであることまで確認する。
  #
  # 走査は末尾数千行に限る。通常セッションではマーカーが作られないため毎回走ることになり、
  # 数十 MB の transcript を全走査すると同期実行の PreToolUse がその分待たされる。
  # 証跡が窓外へ流れると免除は成立しないが、ツール不在に気づいた直後に Bash へ切り替わるため
  # 実運用では窓に収まる。
  tail -n "${CLAUDE_BASH_NUDGE_SCAN_LINES:-2000}" "$tu_transcript" 2>/dev/null \
    | jq -s -e --arg tool "$tu_tool" '
        [.[] | .message.content? | select(type == "array") | .[]] as $items
        | [$items[]
           | select(.type == "tool_result" and .is_error == true)
           | select((.content | tostring)
                    | startswith("<tool_use_error>Error: No such tool available: " + $tool + "."))
           | .tool_use_id] as $failed
        | [$items[] | select(.type == "tool_use" and .name == $tool) | .id] as $called
        | any($failed[]; . as $id | $called | index($id) != null)
      ' >/dev/null 2>&1 || return 1

  mkdir -p "$tu_dir" 2>/dev/null && : > "$tu_marker" 2>/dev/null
  return 0
}

# 差し戻しても代替手段が無いセッションでは黙って通す
tool_unavailable "$alt" && exit 0

jq -n --arg t "$first" --arg a "$alt" \
  '{hookSpecificOutput:{
      hookEventName:"PreToolUse",
      permissionDecision:"deny",
      permissionDecisionReason:("ツール選択ルール(CLAUDE.md): `"+$t+"` は専用ツール "+$a+" を使ってください。Bash は最後の手段です。専用ツールで代替できない場合のみ、コマンドに `# tool-exception: <理由>` を添えて再実行してください(理由を書けないなら例外ではありません)。なお "+$a+" がこのセッションに存在しない場合は、一度 "+$a+" を呼んで `No such tool available` エラーを出せば、以降この種の Bash コマンドは自動で許可されます。")
   }}'
exit 0
