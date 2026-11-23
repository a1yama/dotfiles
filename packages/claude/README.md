# claude パッケージ

Claude Code の設定・スキル・CLIツールを管理するパッケージ。

## セットアップ

```bash
stow -d packages -t ~ -R claude
```

## claude-tmux

tmux × Claude Code の並列エージェント実行を自動化するCLIツール。
`~/.local/bin/claude-tmux` にリンクされる。

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

## claude-loop

リポジトリごとの改善ループを、専用マシンで無人の定時実行にする。
`~/.local/bin/claude-loop` にリンクされる。

```bash
claude-loop list                  # 設定されているループと直近の結果
claude-loop run <name> --dry-run  # 準備(専用 worktree・リンク・SETUP)までを確かめる
claude-loop run <name>            # 1回実行する
claude-loop install               # このマシン向けのループを launchd に登録する
claude-loop uninstall             # 登録を外す
```

- 設定は `~/.config/claude-loop/<name>.conf`(このパッケージの `.config/claude-loop/`)。項目は `claude-loop` 冒頭のコメントを参照
- `HOST` が `hostname -s` と一致するマシンでしか登録も実行もしない。dotfiles を入れた全マシンで動くことはない
- 対話用の clone では作業しない。`~/.local/state/claude-loop/worktrees/<name>` の専用 worktree を毎回 `origin/main` に合わせてから始める
- 前回の変更が worktree に残っていたら実行せず止まる(捨てない)。中身を確かめてから手で片付ける
- 結果は `~/.local/state/claude-loop/<name>.last.json`、ログは `~/.local/state/claude-loop/logs/<name>/`
- ループの手順そのもの(何を判定し、何を提案するか)は各リポジトリの手順書に置く。ここに書くのは「いつ・どこで・何を起動するか」だけ
- 新しいマシンで使うとき: `stow -d packages -t ~ -R claude` のあと `claude-loop install`。設定を変えたときも `claude-loop install` をやり直す
- launchd の登録先は画面にログインしているユーザーの領域(`gui/<uid>`)。専用マシンは自動ログインにしておく。ログインしていない間は起動しない
- launchd から起動したシェルは `.zshrc` を読まない。失敗の通知を受けるには `~/.config/claude-loop/env` に `CLAUDE_SLACK_WEBHOOK_URL=` か `CLAUDE_DISCORD_WEBHOOK_URL=` を書く(秘密の値なので dotfiles には入れない)
- PR は merge コミットでマージする手順にする。squash してブランチを消すと、worktree に残ったコミットがどこからも参照されなくなり、次の回が「未 push のコミット」で止まる
- 対話ログインは期限で切れる。無人で動かし続けるには `claude setup-token` の出力を同じファイルに `CLAUDE_CODE_OAUTH_TOKEN=` で書き、`chmod 600` する(これも dotfiles には入れない)
  - トークンは `claude` の起動時にだけ渡し、`SETUP` には渡さない。ただし `claude` が実行するコマンド(テストや npm スクリプト)に引き継がれるかは確認していない
- 導入の直後は `claude-loop run <name> --dry-run` で準備が通ることを確かめる。`env -i HOME=$HOME /bin/zsh -lc 'claude-loop run <name> --dry-run'` なら launchd に近い環境で確かめられる

## スキル

| スキル | 種類 | 説明 |
|---|---|---|
| `/spawn-agents` | ユーザー実行 | タスクをサブタスクに分解し、並列エージェントを起動 |
| `/code-review` | ユーザー実行 / 自動 | 実装完了後にサブエージェントでコードレビュー |
| `dotfiles-structure` | 自動参照 | リポジトリ構造・stowの使い方をClaudeが自動参照 |

## tmux キーバインド

| キー | 動作 |
|---|---|
| `C-q a` | カレントディレクトリで新しいClaude Codeウィンドウを起動 |
