# tmux パッケージ

tmux の設定を管理するパッケージ。

## セットアップ

```bash
stow -d packages -t ~ -R tmux
```

### プラグインのインストール

初回のみ、tmux 内で `prefix + I` を実行して TPM プラグインをインストールする。

## キーバインド

prefix は `C-q` に設定。

### ペイン操作

| キー | 動作 |
|---|---|
| `s` | 下に分割 |
| `v` | 右に分割 |
| `h/j/k/l` | ペイン移動（Vim スタイル） |
| `H/J/K/L` | ペインリサイズ |
| `R` | ペイン名変更 |
| `x` | ペインを閉じる |
| `z` | ペイン最大化 |

### ウィンドウ操作

| キー | 動作 |
|---|---|
| `c` | 新規ウィンドウ |
| `n/p` | 次/前のウィンドウ |
| `w` | ウィンドウ一覧（fzf） |
| `r` | ウィンドウ名変更 |
| `&` | ウィンドウ削除 |

### セッション操作

| キー | 動作 |
|---|---|
| `/` | セッション切替（fzf） |
| `e` | 新規セッション |
| `$` | セッション名変更 |
| `d` | デタッチ |

### その他

| キー | 動作 |
|---|---|
| `a` | Claude Code 起動 |
| `f` | tmux-fzf 起動 |
| `?` | キーバインドヘルプ |

## セッション復元

tmux-resurrect と tmux-continuum により、PC 再起動後もセッションを復元できる。

### 仕組み

- **自動保存**: continuum が 15 分ごとにセッション状態を自動保存
- **自動復元**: PC 再起動後、`tmux` を起動するだけで前回のレイアウトが復元される
- 保存先: `~/.tmux/resurrect/`

### 復元される内容

- ウィンドウ・ペインのレイアウト
- 各ペインのカレントディレクトリ
- セッション名・ウィンドウ名

### 復元されない内容

- 実行中のプロセス（claude、vim 等）は手動で再起動が必要
  - Claude Code は `C-q a` で起動後、`claude -c` で前回の会話を継続可能

### 手動操作

| キー | 動作 |
|---|---|
| `prefix + Ctrl-s` | 手動でセッションを保存 |
| `prefix + Ctrl-r` | 手動でセッションを復元 |

レイアウトを大きく変更した直後など、すぐに保存したい場合は `prefix + Ctrl-s` を使う。

## プラグイン一覧

| プラグイン | 説明 |
|---|---|
| [tpm](https://github.com/tmux-plugins/tpm) | プラグインマネージャ |
| [tmux-fzf](https://github.com/sainnhe/tmux-fzf) | fzf によるセッション・ウィンドウ検索 |
| [tmux-cpu](https://github.com/tmux-plugins/tmux-cpu) | CPU・メモリ使用率の表示 |
| [tmux-net-speed](https://github.com/tmux-plugins/tmux-net-speed) | ネットワーク速度の表示 |
| [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) | セッションの保存・復元 |
| [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) | セッションの自動保存・自動復元 |
