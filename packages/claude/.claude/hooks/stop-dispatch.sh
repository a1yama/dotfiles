#!/bin/bash
# Stop フック: quality-gate → claude-notify を直列に実行するディスパッチャー。
# Stop フックは並列実行されるため、個別登録だと gate に差し戻された未完了の時点で
# 「完了」通知が飛んでしまう。gate が block したときは通知を出さない。
set -u

input=$(cat)

gate_out=$(printf '%s' "$input" | "$HOME/dotfiles/packages/claude/.claude/hooks/stop-quality-gate.sh")
if [ -n "$gate_out" ]; then
  printf '%s' "$gate_out"
  exit 0
fi

printf '%s' "$input" | "$HOME/.local/bin/claude-notify"
