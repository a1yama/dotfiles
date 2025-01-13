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

## vim 
vimは開発でガッツリ使うことはなく、簡単なスクリプトを書くときや、Goの簡単な検証をするときなどに使う程度  
nvimまでいらないけどどうせなら…という好奇心から設定してみた  
設定ファイルは以下をそのまま使っている  
それをstowのディレクトリ構造に落とし込んでいる  
https://gitlab.com/utzuro/dots/-/tree/main/config/vim?ref_type=heads

tmuxは使わないので、そのあたりのプラグインだけ削除してあとの設定はそのままにしている  
正直まだ使い方が分からないところがあるが同僚氏なので、分からないところは聞いていこうと思う
