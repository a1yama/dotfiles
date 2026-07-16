#!/bin/bash
# PostToolUse(Edit|Write) フック: 編集直後のファイルに決定的チェック(fmt/vet/構文)を実行し、
# 検出したエラーを additionalContext でモデルに返して自己修正ループを閉じる。ブロックはしない。
# チェッカー未導入・対象外拡張子は黙ってスキップし、誤検知の害を最小化する。
set -u

file=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

errors=""
add_error() {
  errors="${errors:+$errors

}$1"
}

# コンテキストを圧迫しないよう出力を制限する
trunc() { head -c 4000 | head -n 40; }

dir=$(dirname "$file")

case "$file" in
  *.go)
    fmtout=$(gofmt -l "$file" 2>&1)
    if [ "$fmtout" = "$file" ]; then
      add_error "gofmt: 未整形です → gofmt -w '$file' を実行してください"
    elif [ -n "$fmtout" ]; then
      add_error "gofmt:
$(printf '%s' "$fmtout" | trunc)"
    fi
    # go vet はモジュール内でのみ実行(モジュール外だと常にエラーになるため)
    gomod=$(cd "$dir" && go env GOMOD 2>/dev/null)
    if [ -n "$gomod" ] && [ "$gomod" != "/dev/null" ]; then
      if ! out=$(cd "$dir" && go vet . 2>&1); then
        add_error "go vet:
$(printf '%s' "$out" | trunc)"
      fi
    fi
    ;;
  *.ts|*.tsx)
    # 最寄りの tsconfig.json とその上方の node_modules/.bin/tsc が揃うときだけ型チェック
    d="$dir" tsdir=""
    while [ "$d" != "/" ] && [ "$d" != "$HOME" ]; do
      [ -f "$d/tsconfig.json" ] && { tsdir="$d"; break; }
      d=$(dirname "$d")
    done
    if [ -n "$tsdir" ]; then
      d="$tsdir" tscbin=""
      while [ "$d" != "/" ]; do
        [ -x "$d/node_modules/.bin/tsc" ] && { tscbin="$d/node_modules/.bin/tsc"; break; }
        d=$(dirname "$d")
      done
      if [ -n "$tscbin" ]; then
        if ! out=$(cd "$tsdir" && "$tscbin" --noEmit 2>&1); then
          add_error "tsc --noEmit ($tsdir):
$(printf '%s' "$out" | trunc)"
        fi
      fi
    fi
    ;;
  *.sh|*.bash)
    if command -v shellcheck >/dev/null 2>&1; then
      if ! out=$(shellcheck -f gcc "$file" 2>&1); then
        add_error "shellcheck:
$(printf '%s' "$out" | trunc)"
      fi
    elif ! out=$(bash -n "$file" 2>&1); then
      add_error "bash -n (構文エラー):
$(printf '%s' "$out" | trunc)"
    fi
    ;;
  *.json)
    if ! out=$(jq empty "$file" 2>&1); then
      add_error "jq (JSON構文エラー):
$(printf '%s' "$out" | trunc)"
    fi
    ;;
esac

[ -z "$errors" ] && exit 0

jq -n --arg e "$errors" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("PostToolUse 自動チェックで問題を検出しました。該当箇所を修正してください:\n\n"+$e)}}'
exit 0
