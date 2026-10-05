# Fix corrupted FPATH if inherited from parent process
unset FPATH
fpath=()

precmd() {
  print -Pn "\e]0;%~\a"
}
# Workbrew 管理下の PC では wrapper 経由でないと brew が拒否される
if [[ -x /opt/workbrew/bin/brew ]]; then
  eval "$(/opt/workbrew/bin/brew shellenv)"
else
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Load zsh completion system first
# Ensure system function paths are included
fpath=(/usr/share/zsh/site-functions /usr/share/zsh/${ZSH_VERSION}/functions $fpath)

if type brew &>/dev/null; then
  fpath=($(brew --prefix)/share/zsh-completions $fpath)
fi

autoload -Uz compinit compaudit add-zsh-hook is-at-least
# Homebrew is managed by Workbrew, so /opt/homebrew is owned by the `workbrew`
# user and compaudit flags it. Trust it unless it is group/world-writable;
# anything else insecure still gets the interactive prompt.
() {
  setopt local_options extended_glob
  local -a insecure=(${(f)"$(compaudit 2>/dev/null)"})
  local -a writable=(${^${(M)insecure:#/opt/homebrew/*}}(N^f:go-w:))
  if (( ${#${insecure:#/opt/homebrew/*}} + ${#writable} )); then
    compinit
  else
    compinit -u
  fi
}

# Initialize rbenv
if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init - zsh)"
fi

# Initialize starship and plugins after compinit
eval "$(starship init zsh)"

eval "$(zoxide init zsh)"

if type brew &>/dev/null; then
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Editor settings
export EDITOR=nvim

# zsh は EDITOR/VISUAL に "vi" が含まれると main キーマップを viins にする。
# "nvim" も部分一致するため、指定しないと ^A/^E が self-insert になる。
# 以降の bindkey は main(=emacs) に入るので、fzf.zsh を読む前に固定する。
bindkey -e

ZSH_DIR="${HOME}/.zsh"

if [ -d $ZSH_DIR ] && [ -r $ZSH_DIR ] && [ -x $ZSH_DIR ]; then
    for file in ${ZSH_DIR}/**/*.zsh; do
        [ -r $file ] && source $file
    done
fi
