# Fix corrupted FPATH if inherited from parent process
unset FPATH
fpath=()

precmd() {
  print -Pn "\e]0;%~\a"
}
eval "$(/opt/homebrew/bin/brew shellenv)"

# Load zsh completion system first
# Ensure system function paths are included
fpath=(/usr/share/zsh/site-functions /usr/share/zsh/${ZSH_VERSION}/functions $fpath)

if type brew &>/dev/null; then
  fpath=($(brew --prefix)/share/zsh-completions $fpath)
fi

autoload -Uz compinit add-zsh-hook is-at-least
compinit

# Initialize starship and plugins after compinit
eval "$(starship init zsh)"

if type brew &>/dev/null; then
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Editor settings
export EDITOR=nvim

ZSH_DIR="${HOME}/.zsh"

if [ -d $ZSH_DIR ] && [ -r $ZSH_DIR ] && [ -x $ZSH_DIR ]; then
    for file in ${ZSH_DIR}/**/*.zsh; do
        [ -r $file ] && source $file
    done
fi
