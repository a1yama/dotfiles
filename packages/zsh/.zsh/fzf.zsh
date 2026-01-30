# -------------------------
# fzf UI
# -------------------------
export FZF_DEFAULT_OPTS='--height=60% --reverse --border --cycle'

# preview: ファイルは中身、ディレクトリは一覧
__fzf_preview='
if [ -d {} ]; then
  ls -la {} | sed -n "1,200p"
else
  if command -v bat >/dev/null 2>&1; then
    bat --style=numbers --color=always --line-range :300 {}
  else
    sed -n "1,300p" {}
  fi
fi
'

# -------------------------
# 選択結果を開く/移動する共通処理
# -------------------------
__fzf_open_or_cd() {
  local target="$1"
  [[ -n "$target" ]] || return 0

  if [[ -d "$target" ]]; then
    cd -- "$target" || return 1
    zle reset-prompt
  else
    "${EDITOR:-vi}" "$target"
    zle redisplay
  fi
}

# -------------------------
# Ctrl+f: カレント配下（.）を検索（dir+file）
# fdがあればfd、無ければfind
# -------------------------
fzf-find-here() {
  local target
  if command -v fd >/dev/null 2>&1; then
    target=$(
      fd --hidden --follow --exclude .git . . 2>/dev/null \
      | sed 's|^\./||' \
      | fzf --prompt="Here> " --preview="$__fzf_preview"
    )
    [[ -n "$target" ]] || return 0
    __fzf_open_or_cd "./$target"
  else
    target=$(
      find . -mindepth 1 \( -type f -o -type d \) -not -path '*/.git/*' 2>/dev/null \
      | sed 's|^\./||' \
      | fzf --prompt="Here> " --preview="$__fzf_preview"
    )
    [[ -n "$target" ]] || return 0
    __fzf_open_or_cd "./$target"
  fi
}
zle -N fzf-find-here
bindkey '^f' fzf-find-here

# -------------------------
# Ctrl+g: HOME配下の全gitリポジトリを横断検索
# -------------------------
fzf-find-all-repos() {
  command -v git >/dev/null 2>&1 || return 0

  local home="${HOME:-$PWD}"
  local -a excludes=(Library .cache .Trash node_modules .npm .cargo .rustup Applications)
  local -a repo_cmd

  if command -v fd >/dev/null 2>&1; then
    repo_cmd=(fd --hidden --follow --type d --glob '.git')
    local ex
    for ex in "${excludes[@]}"; do
      repo_cmd+=(--exclude "$ex")
    done
    repo_cmd+=("$home")
  else
    repo_cmd=(find "$home")
    repo_cmd+=("(")
    local first=1 pattern exclude
    for exclude in "${excludes[@]}"; do
      if [[ "$exclude" == "node_modules" ]]; then
        pattern="*/$exclude"
      else
        pattern="$home/$exclude"
      fi
      if (( first )); then
        repo_cmd+=(-path "$pattern")
        first=0
      else
        repo_cmd+=(-o -path "$pattern")
      fi
    done
    repo_cmd+=(")")
    repo_cmd+=(-prune -o -type d -name .git -print)
  fi

  local delim=$'\t'
  local preview_cmd='
repo={2}
if [ -z "$repo" ]; then
  exit 0
fi
if command -v git >/dev/null 2>&1 && git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$repo" status -sb
  echo
fi
if [ -d "$repo" ]; then
  ls -la "$repo" | sed -n "1,200p"
fi
'

  local selection
  selection=$(
    "${repo_cmd[@]}" 2>/dev/null \
    | while IFS= read -r git_dir; do
        [[ -n "$git_dir" ]] || continue
        [[ "$git_dir" == *"/.git/modules/"* ]] && continue
        [[ -d "$git_dir" ]] || continue

        local repo="${git_dir%/.git*}"
        [[ -d "$repo" ]] || continue
        git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue

        local display="${repo/#$home/~}"
        printf '%s\t%s\n' "$display" "$repo"
      done \
    | fzf --prompt="AllRepos> " --with-nth=1 --delimiter="$delim" --preview="$preview_cmd"
  ) || return 0

  [[ -n "$selection" ]] || return 0
  [[ "$selection" == *$'\t'* ]] || return 0

  local target="${selection#*$'\t'}"
  [[ -n "$target" ]] || return 0
  __fzf_open_or_cd "$target"
}
zle -N fzf-find-all-repos
bindkey '^g' fzf-find-all-repos
