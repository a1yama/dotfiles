#!/bin/bash
# dotfiles-structure スキルの構造図が、実在する stow パッケージを全部挙げているかのテスト。
# `bash tests/dotfiles-structure-doc.test.sh` で実行する。
# 図は手で書いているので、パッケージを足したときに取り残される(3つ欠けたまま数か月たっていた)。
set -u
PKG_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SKILL="$PKG_ROOT/claude/.claude/skills/dotfiles-structure/SKILL.md"
pass=0; fail=0
ok() { if [ "$2" = "1" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; fi; }
eq() { if [ "$1" = "$2" ]; then echo 1; else echo 0; fi; }

# $1 の直下にあるディレクトリのうち、$2 の構造図に「── 名前/」の形で出てこないものを空白区切りで返す。
# 名前の前後まで見るのは、lazygit の行で git が挙がっていることにしないため
missing_packages() {
  mp_out=""
  for mp_dir in "$1"/*/; do
    [ -d "$mp_dir" ] || continue
    mp_name=$(basename "$mp_dir")
    grep -qF -- "── ${mp_name}/" "$2" 2>/dev/null || mp_out="${mp_out:+$mp_out }$mp_name"
  done
  printf '%s' "$mp_out"
}

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/packages/git" "$ROOT/packages/lazygit" "$ROOT/packages/zsh" "$ROOT/empty"
: > "$ROOT/packages/not-a-package.txt"
printf '│   ├── git/      # a\n│   ├── lazygit/  # b\n│   └── zsh/      # c\n' > "$ROOT/all.md"
printf '│   ├── lazygit/  # b\n│   └── zsh/      # c\n' > "$ROOT/no-git.md"
printf 'packages/git/ と lazygit と zsh/ の説明だけで、図が無い\n' > "$ROOT/prose.md"
: > "$ROOT/blank.md"

ok "全部挙がっていれば空" "$(eq "$(missing_packages "$ROOT/packages" "$ROOT/all.md")" "")"
ok "別の名前に含まれるだけの名前は欠けとして返す" "$(eq "$(missing_packages "$ROOT/packages" "$ROOT/no-git.md")" "git")"
ok "図の形でない言及は数えない" "$(eq "$(missing_packages "$ROOT/packages" "$ROOT/prose.md")" "git lazygit zsh")"
ok "空の文書では全部が欠け" "$(eq "$(missing_packages "$ROOT/packages" "$ROOT/blank.md")" "git lazygit zsh")"
ok "文書が無ければ全部が欠け" "$(eq "$(missing_packages "$ROOT/packages" "$ROOT/none.md")" "git lazygit zsh")"
ok "パッケージが無ければ空" "$(eq "$(missing_packages "$ROOT/empty" "$ROOT/all.md")" "")"

ok "スキルの文書がある" "$([ -s "$SKILL" ] && echo 1 || echo 0)"
real=$(missing_packages "$PKG_ROOT" "$SKILL")
ok "構造図に無いパッケージ: ${real:-なし}" "$(eq "$real" "")"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = "0" ]
