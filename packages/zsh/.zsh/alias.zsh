# tmux
alias t="tmux"
alias ta="tmux attach"
alias tat="tmux attach -t"
alias tl="tmux list-sessions"
alias tn="tmux new -s"
alias tk="tmux kill-session -t"

alias g="git"
alias cat="bat"
alias ll="ls -l"
alias vim="nvim"
alias gaa="git aa"
alias gst="git st"
alias gss="git ss"
alias gfe="git fe"
alias commit="git cm"
alias emptycommit="git ecm"
alias pullc="git plc"
alias pushc="git psc"
alias addfzf="git adf"
alias restorefzf="git rsf"
alias mergefzf="git mgf"
alias checkout="git cho"
alias checkoutb="git cob"

switch() {
  local branch
  branch=$(git branch --all --format='%(refname:short)' | grep -v 'HEAD' | fzf --height=15 --reverse)
  
  if [ -n "$branch" ]; then
    # リモートブランチであればローカルに追跡ブランチを作成
    if [[ "$branch" == remotes/* ]]; then
      local local_branch="${branch#remotes/origin/}"
      echo "Switching to remote branch $local_branch"
      git switch --track "$branch"
    else
      echo "Switching to local branch $branch"
      git switch "$branch"
    fi
  fi
}
