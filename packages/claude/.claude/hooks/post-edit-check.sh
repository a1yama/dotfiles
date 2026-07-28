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

      if command -v golangci-lint >/dev/null 2>&1; then
        gomodroot=$(dirname "$gomod")
        cfg=""
        for c in .golangci.yml .golangci.yaml .golangci.toml .golangci.json; do
          [ -f "$gomodroot/$c" ] && { cfg="$gomodroot/$c"; break; }
        done
        # リポジトリ固有設定が無ければ複雑度だけを見る共有設定にフォールバックする
        [ -z "$cfg" ] && cfg="$HOME/.claude/lint/golangci-complexity.yml"
        # 初回はビルドキャッシュ生成で長引くため打ち切る(SIGALRM 終了 = 142)
        # 件数上限は無効化する。先に打ち切られると、後段の絞り込みで編集ファイルの指摘が
        # 残らないことがある(出力量は trunc で抑える)
        out=$(cd "$dir" && perl -e 'alarm shift; exec @ARGV' 30 \
          golangci-lint run -c "$cfg" --path-mode abs \
          --max-issues-per-linter 0 --max-same-issues 0 . 2>&1)
        rc=$?
        # golangci-lint はパッケージ単位で走るため、編集したファイル以外の既存債務は捨てる。
        # 指摘行が1つも無い出力(設定エラー等)はそのまま見せる
        if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qE '^/.+\.go:[0-9]+:[0-9]+:'; then
          absfile="$(cd "$dir" && pwd -P)/$(basename "$file")"
          out=$(printf '%s' "$out" | grep -F "$absfile:")
        fi
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 142 ] && [ -n "$out" ]; then
          add_error "golangci-lint (複雑度の上限超過。関数を分割するか、分割しない理由を報告に明示してください):
$(printf '%s' "$out" | trunc)"
        fi
      fi
    fi
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    case "$file" in
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
    esac

    # 複雑度の共有チェック。リポジトリ側の ESLint 設定・node_modules の有無に関わらず、
    # ~/.claude/lint の専用環境で常に実行する(Go 側の共有 golangci 設定と対になる)
    sharedbin="$HOME/.claude/lint/node_modules/.bin/eslint"
    sharedcfg="$HOME/.claude/lint/eslint-complexity.mjs"
    if [ -x "$sharedbin" ] && [ -f "$sharedcfg" ]; then
      # 対象ファイルが cwd 配下にないと ESLint が「base path 外」として無視するため dir へ移る。
      # --no-inline-config: 共有環境に無いプラグイン向けの eslint-disable コメントが
      # 「Definition for rule was not found」の誤検知になるのを防ぐ
      out=$(cd "$dir" && perl -e 'alarm shift; exec @ARGV' 20 \
        "$sharedbin" --no-config-lookup --config "$sharedcfg" \
        --no-inline-config --max-warnings 0 "$file" 2>&1)
      rc=$?
      if [ "$rc" -ne 0 ] && [ "$rc" -ne 142 ] && [ -n "$out" ]; then
        add_error "eslint (複雑度: 共有設定。関数を分割するか、分割しない理由を報告に明示してください):
$(printf '%s' "$out" | trunc)"
      fi
    fi

    # 最寄りの ESLint 設定と、その上方の node_modules/.bin/eslint が揃うときだけ実行。
    # 設定はリポジトリ側のものを使う(複雑度以外の repo 固有ルール担当)
    d="$dir" esdir=""
    while [ "$d" != "/" ] && [ "$d" != "$HOME" ]; do
      for c in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml; do
        [ -f "$d/$c" ] && { esdir="$d"; break 2; }
      done
      d=$(dirname "$d")
    done
    if [ -n "$esdir" ]; then
      d="$esdir" esbin=""
      while [ "$d" != "/" ]; do
        [ -x "$d/node_modules/.bin/eslint" ] && { esbin="$d/node_modules/.bin/eslint"; break; }
        d=$(dirname "$d")
      done
      if [ -n "$esbin" ]; then
        # 複雑度ルールは warn から導入する運用のため、warn でも非ゼロ終了させて拾う
        out=$(cd "$esdir" && perl -e 'alarm shift; exec @ARGV' 30 \
          "$esbin" --max-warnings 0 "$file" 2>&1)
        rc=$?
        # 142 = SIGALRM(タイムアウト)。打ち切りを検出扱いしない
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 142 ] && [ -n "$out" ]; then
          add_error "eslint:
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
