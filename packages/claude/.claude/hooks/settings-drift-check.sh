#!/bin/bash
# SessionStart フック: settings.json は意図的に stow リンクしていない(CLI が直接書き換えるため)。
# repo 側と ~/.claude 側の二重管理になっており、片方だけ編集される事故を検知して警告する。
# model キーは /model で CLI が書き込む機械ローカル値のため比較対象から除外する。
set -u

repo_file="${DRIFT_REPO_FILE:-$HOME/dotfiles/packages/claude/.claude/settings.json}"
home_file="${DRIFT_HOME_FILE:-$HOME/.claude/settings.json}"

[ -f "$repo_file" ] || exit 0
[ -f "$home_file" ] || exit 0

# キー順・整形差で誤検知しないよう正規化して比較する
norm() { jq -S 'del(.model)' "$1" 2>/dev/null || cat "$1"; }

if diff_out=$(diff <(norm "$repo_file") <(norm "$home_file")); then
  exit 0
fi

diff_out=$(printf '%s' "$diff_out" | head -c 3000 | head -n 60)

jq -n --arg d "$diff_out" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:("警告: settings.json が repo(dotfiles) と ~/.claude で乖離しています。規約では両方を同時に編集します。ユーザーに乖離を報告し、どちらを正とするか確認して同期してください。\n差分(< repo / > home):\n"+$d)}}'
exit 0
