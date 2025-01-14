precmd() {
  print -Pn "\e]0;%~\a"
}
eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(starship init zsh)"

if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  autoload -Uz compinit && compinit
fi

ZSH_DIR="${HOME}/.zsh"

if [ -d $ZSH_DIR ] && [ -r $ZSH_DIR ] && [ -x $ZSH_DIR ]; then
    for file in ${ZSH_DIR}/**/*.zsh; do
        [ -r $file ] && source $file
    done
fi
