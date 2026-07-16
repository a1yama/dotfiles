#!/bin/bash
# Stop フック: ソースコード変更があるのに「テスト実行」「code-review スキル実行」の痕跡がない場合、
# 一度だけ停止を差し戻して対応(または未実施理由の明示)を促す。
# CLAUDE.md「テストなしで動きますと言わない」と code-review の起動導線を機構化する品質ゲート。
set -u

input=$(cat)

# block からの継続後の再停止は素通しする(無限ループ防止)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
if [ -n "$cwd" ]; then
  cd "$cwd" 2>/dev/null || exit 0
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# テスト・レビュー対象になり得るソースコードの変更だけを見る(設定・ドキュメント類は対象外)
changed=$( { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } \
  | grep -E '\.(go|ts|tsx|js|jsx|py|rs|php|rb)$' )
[ -z "$changed" ] && exit 0

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

has_evidence() {
  [ -n "$transcript" ] && [ -f "$transcript" ] && grep -qE "$1" "$transcript"
}

issues=""

# テスト: ランナーを検出できたリポジトリでのみ要求する(ノイズ防止)
if ! has_evidence '(go test|npm (run )?test|yarn test|pnpm test|pytest|vitest|jest|cargo test|phpunit|make test|bundle exec rspec|rspec )'; then
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  suggest=""
  if [ -f "$root/go.mod" ]; then
    suggest="go test ./..."
  elif [ -f "$root/package.json" ] && jq -e '.scripts.test // empty' "$root/package.json" >/dev/null 2>&1; then
    suggest="npm test"
  elif [ -f "$root/pytest.ini" ] || { [ -f "$root/pyproject.toml" ] && grep -q '\[tool\.pytest' "$root/pyproject.toml"; }; then
    suggest="pytest"
  elif [ -f "$root/Cargo.toml" ]; then
    suggest="cargo test"
  elif [ -f "$root/Makefile" ] && grep -qE '^test:' "$root/Makefile"; then
    suggest="make test"
  fi
  if [ -n "$suggest" ]; then
    issues="- テスト実行の痕跡がありません。\`$suggest\` などで実行して結果を報告するか、実行しない理由を明示してください。"
  fi
fi

# レビュー: Skill ツールでの code-review 呼び出し痕跡を探す(スキル一覧の記載とは形式が異なるため誤検知しない)
if ! has_evidence '"skill" *: *"[^"]*code-review"'; then
  issues="${issues:+$issues
}- code-review スキルが未実行です。実行して指摘に対応するか、不要な理由を明示してください。"
fi

[ -z "$issues" ] && exit 0

jq -n --arg i "$issues" \
  '{decision:"block", reason:("ソースコードが変更されていますが、終了前の品質ゲートで以下が未完了です(CLAUDE.md ハルシネーション防止):\n"+$i)}'
exit 0
