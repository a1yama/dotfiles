#!/bin/bash
# エージェントが「人間の入力待ちで止まっているか」を tmux ペインに記録する。
#
# harness が ~/.claude/sessions/<PID>.json に持つ status は busy / idle の2値しかなく、
# AskUserQuestion の回答待ちや許可待ちで停止していても busy のままになる(実測で確認)。
# 「働いている」と「人を待っている」を区別するため、blocked だけをここで補う。
# busy / idle はレジストリ側が持っているので二重には書かない。
#
# Usage: agent-status.sh block|unblock
#
# tmux 外・tmux 未導入・ペイン特定不可のときは何もせず正常終了する。
# デスクトップアプリ経由のセッションはこれに該当し、レジストリ側も status:null になる。
set -u

OPT_NAME="${CLAUDE_AGENT_STATUS_OPT:-@claude_blocked}"
SESSIONS_DIR="${CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}"

# フックは stdin に JSON を受け取る。読み捨てないと呼び出し側が EPIPE で落ちうる。
drain_stdin() {
  [ -t 0 ] || cat >/dev/null 2>&1 || true
}

# 自分のペインを特定する。
# 1) tmux ペイン内で起動されていれば TMUX_PANE が継承されている
# 2) 無ければレジストリの tmux フィールド("main:@5.%7")の末尾から拾う
#    (claude-notify の resolve_tmux_label と同じ形式)
resolve_pane() {
  if [ -n "${TMUX_PANE:-}" ]; then
    printf '%s' "$TMUX_PANE"
    return 0
  fi

  local registry="${SESSIONS_DIR}/${CLAUDE_PID:-}.json"
  [ -n "${CLAUDE_PID:-}" ] || return 0
  [ -f "$registry" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local ref
  ref=$(jq -r '.tmux // empty' "$registry" 2>/dev/null || true)
  [ -n "$ref" ] || return 0
  printf '%s' "${ref##*.}"
}

main() {
  local action="${1:-}"
  drain_stdin

  case "$action" in
    block | unblock) ;;
    *) exit 0 ;;
  esac

  command -v tmux >/dev/null 2>&1 || exit 0

  local pane
  pane=$(resolve_pane)
  [ -n "$pane" ] || exit 0

  # 値には epoch 秒を入れる。いつから待たせているかを読み側で出せるようにするため。
  # ペインが死んでいる場合は set が失敗するが、生存判定は読み側が行うので握り潰す。
  if [ "$action" = "block" ]; then
    tmux set-option -p -t "$pane" "$OPT_NAME" "$(date +%s)" 2>/dev/null || true
  else
    tmux set-option -p -u -t "$pane" "$OPT_NAME" 2>/dev/null || true
  fi
}

main "$@"
exit 0
