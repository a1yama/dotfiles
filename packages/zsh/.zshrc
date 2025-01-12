eval "$(starship init zsh)"

export PATH="/opt/homebrew/opt/php@8.1/bin:$PATH"
export PATH="/opt/homebrew/opt/php@8.1/sbin:$PATH"
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$PATH
export AWS_PROFILE=tricera

if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  autoload -Uz compinit && compinit
fi
