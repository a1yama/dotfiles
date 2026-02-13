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

## claude-tmux

tmux × Claude Code の並列エージェント実行を自動化するCLIツール。
`stow -d packages -t ~ -R claude` で `~/.local/bin/claude-tmux` にリンクされる。

### サブコマンド

```bash
# ヘッドレスエージェントを起動
claude-tmux spawn "READMEを日本語に翻訳して" --name translate-readme

# 名前・作業ディレクトリを指定して起動
claude-tmux spawn "テストを追加" --name add-tests --dir ~/projects/myapp

# 複数のGitHub Issueを並列処理
claude-tmux issues 42 43 44

# 実行中のエージェント一覧
claude-tmux status

# ログをリアルタイム表示
claude-tmux logs translate-readme

# エージェントを停止
claude-tmux kill translate-readme
claude-tmux kill all
```

### Claude Code スキル

```
/spawn-agents 機能AのリファクタリングとBのテスト追加を並列で実行
```

タスクをサブタスクに分解し、それぞれ `claude-tmux spawn` で並列エージェントを起動する。

### tmux キーバインド

| キー | 動作 |
|---|---|
| `C-q a` | カレントディレクトリで新しいClaude Codeウィンドウを起動 |
