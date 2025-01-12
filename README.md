# dotfiles

## Installation
run install
```
curl -o - https://raw.githubusercontent.com/a1yama/dotfiles/refs/heads/master/install | sh
```

## zsh
zshはそれぞれの環境で違うものがあると思うので、それぞれを設定するようにした
installでtouchしているので`packages/zsh/.zsh/local.zsh`に必要な設定を記載していく
exportは特に独自のものを入れると思うのでzshrcには記載していない
aliasも各環境で必要なものが出てくると思うので、固有のものはlocal.zshに記載する