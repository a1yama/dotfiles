#!/bin/bash
# Stop フック: ソースコード変更がある場合の品質ゲート。
# テストはランナーを検出できたリポジトリで実際に実行し、失敗なら失敗ログ付きで停止を差し戻す
# (グリーンになるまで終われないループ)。同じ作業ツリー状態での成功はキャッシュして再実行しない。
# code-review はスキル実行の痕跡がなければ差し戻す。
# CLAUDE.md「テストなしで動きますと言わない」と code-review の起動導線を機構化する。
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

# テスト: ランナーを検出できたリポジトリでは実際に実行し、結果で判定する(痕跡ではなく実測)
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
  cache_dir="${QG_CACHE_DIR:-$HOME/.cache/claude-quality-gate}"
  timeout_s="${QG_TEST_TIMEOUT:-120}"
  # 作業ツリーの状態ハッシュ。同じ状態でテスト成功済みなら再実行せず、停止のたびの待ち時間を防ぐ
  state=$({ git diff HEAD 2>/dev/null
            git ls-files --others --exclude-standard -z 2>/dev/null | xargs -0 shasum 2>/dev/null
          } | shasum | awk '{print $1}')
  cache_file="$cache_dir/$(printf '%s' "$root" | shasum | awk '{print $1}')"
  if [ ! -f "$cache_file" ] || [ "$(cat "$cache_file")" != "$state" ]; then
    # macOS に timeout(1) がないため perl の alarm でタイムアウトを実装(SIGALRM 終了 = 142)
    test_out=$(cd "$root" && perl -e 'alarm shift; exec @ARGV' "$timeout_s" sh -c "$suggest" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      mkdir -p "$cache_dir"
      printf '%s' "$state" > "$cache_file"
    elif [ "$rc" -eq 142 ]; then
      # タイムアウト時は実測を諦め、従来どおり痕跡ベースで判定する
      if ! has_evidence '(go test|npm (run )?test|yarn test|pnpm test|pytest|vitest|jest|cargo test|phpunit|make test|bundle exec rspec|rspec )'; then
        issues="- テスト(\`$suggest\`)が ${timeout_s}s でタイムアウトしました。手動で実行して結果を報告するか、実行しない理由を明示してください。"
      fi
    else
      issues="- テスト失敗(\`$suggest\`)。修正してください:
$(printf '%s' "$test_out" | head -c 4000 | head -n 40)"
    fi
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
