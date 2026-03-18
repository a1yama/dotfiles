# CLAUDE.md

## Conversation Guidelines

- 常に日本語で会話する
- タスクが完了したらsayコマンドで通知する
- 指示が曖昧だったり疑問があった場合にはそのまま作業に入らず質問をしてください。
  - 間違った認識のまま対応することを防ぐためです。
- 必要に応じてチームで対応してください。

## Coding Policy

### コメントのルール

- コードを読めば分かる内容のコメントは追加しない
- コメントは「何をしているか」ではなく「なぜそうしているか」を説明する
- 自明なコードにコメントを付けない（リーダブルコードの原則）

悪い例:
```go
// ユーザーを取得する
user := getUser(id)

// エラーチェック
if err != nil {
    return err
}
```

良い例:
```go
// キャッシュを先に確認し、DBアクセスを減らす
user := getUser(id)
```

### ツール選択ルール

以下の操作には専用ツールを使用してください。Bash は**最後の手段**です。

| 操作 | 使うべきツール | 使ってはいけないコマンド |
|---|---|---|
| ファイル検索 | Glob | ls, find |
| コンテンツ検索 | Grep | grep, rg |
| ファイル読み込み | Read | cat, head, tail |
| ファイル編集 | Edit | sed, awk |
| ファイル作成・書き込み | Write | echo >, cat <<EOF |

専用ツールを使うことで、変更内容がユーザーに明示的に表示され、レビューが容易になります。

### 連続 Bash 使用の自己チェック

Bash ツールを**3回以上連続**で使用する場合、以下を自己チェックする：

1. **専用ツールで代替可能か？**
   - ファイル検索 → Glob
   - コンテンツ検索 → Grep
   - ファイル読み込み → Read
   - ファイル編集 → Edit

2. **複数のBashコマンドを1回にまとめられるか？**
   ```bash
   # ❌ 悪い例（3回の Bash 呼び出し）
   Bash: ls -la
   Bash: grep "pattern" file.txt
   Bash: cat result.txt

   # ✅ 良い例（専用ツール使用）
   Glob: "*"
   Grep: "pattern" in "file.txt"
   Read: "result.txt"
   ```

3. **一連の操作をスキル化すべきか？**
   - 同じBash操作パターンが繰り返されている場合はスキル化を検討

## Git Commit Guidelines

- コミットメッセージは1行のみで簡潔に記述する
- 「🤖 Generated with Claude Code」の署名は追加しない
- 「Co-Authored-By: Claude」は追加しない
- コミットメッセージの形式: `git commit -m "簡潔なメッセージ"`
- 勝手にコミットしないこと

## Pull Request Guidelines

- PRの本文に「🤖 Generated with Claude Code」の署名は追加しない
- PRタイトルは70文字以内で簡潔に記述する

例:
```bash
git commit -m "fix: 認証情報を含むGitHub URLのパース処理を修正"
```

### コミットメッセージの書き方

- **1行のみ**で簡潔に記述する
- **変更内容の要約**ではなく、**変更の目的**を記述する
- Prefix（`feat:`, `fix:`, `refactor:` 等）を活用する
- 50文字以内を目安とする

良い例:
```bash
git commit -m "fix: 返済APIのUTCタイムゾーン問題を修正"
git commit -m "feat: セブン銀行APIに30秒タイムアウトを追加"
```

悪い例:
```bash
# ❌ 長すぎる
git commit -m "コードレビューを実施しました。以下の問題を指摘します。 レビュー結果 [重要度: high] internal/adapter/..."

# ❌ 変更内容の羅列
git commit -m "ファイルAを変更、ファイルBを追加、ファイルCを削除"
```

## Development Philosophy

- 独立したサブタスクが複数ある場合は、`claude-tmux spawn` で並列エージェントの活用を検討する

## claude-tmux

tmux内でClaude Codeエージェントを並列実行するためのCLIツール（オーケストレーション対応）。

### サブコマンド

| コマンド | 説明 |
|---|---|
| `claude-tmux spawn "タスク説明" [--name NAME] [--dir DIR] [--no-review]` | 新しいtmuxペインでインタラクティブエージェントを起動 |
| `claude-tmux issues 42 43 44` | 複数のGitHub Issueを並列エージェントで処理 |
| `claude-tmux status` | 実行中のエージェント一覧とペイン生存確認 |
| `claude-tmux questions` | 質問待ちのエージェント一覧を表示 |
| `claude-tmux answer <name> <回答>` | 質問に回答（answerファイル作成 + ペインに通知）|
| `claude-tmux logs <name>` | 特定エージェントのログを表示（未実装） |
| `claude-tmux kill [name\|all]` | エージェントペイン停止とディレクトリ削除 |
| `claude-tmux clean` | 完了/死亡したエージェントのディレクトリをクリーンアップ |

### スキル

- `/spawn-agents タスクの説明` — タスクをサブタスクに分解し、`claude-tmux spawn` で並列エージェントを起動する

### tmux キーバインド

- `C-q a` — カレントディレクトリで新しいClaude Codeインタラクティブウィンドウを起動

### 仕様

- エージェントディレクトリ: `/tmp/claude-agents/<name>/`
  - `pane-id` - tmuxペインID
  - `prompt` - 元のプロンプト
  - `question` - 質問内容（存在する場合）
  - `answer` - 回答（存在する場合）
  - `status` - running/completed/error
- ペイン分割: 左右分割（`-h`）、複数なら上下にも分割（`-v`）
- 実行モード: インタラクティブモード（ヘッドレスではない）
- tmuxセッション外での実行時はエラー

### オーケストレーション（監督機能）

エージェントが質問したい場合、監督エージェントが自動的に判断して回答します：

1. **エージェント**: Write ツールで `/tmp/claude-agents/<name>/question` に質問を書き込む
2. **監督**: `/supervise` スキルを実行（または `claude-tmux supervise`）
3. **監督**: 各質問を分析して、**ユーザーに確認せず**最善の判断で回答を決定
4. **監督**: `claude-tmux answer <name> "回答内容"` で回答を自動提供
5. **エージェント**: Read ツールで `/tmp/claude-agents/<name>/answer` から回答を読み取り、タスクを続行

#### 監督の判断基準

- 技術選択: 一般的でメンテナンス性の高い選択を優先
- セキュリティ: 安全性を最優先
- シンプルさ: 過度に複雑な実装を避ける
- 一貫性: プロジェクト全体の方針と一致

### 自動コードレビュー

- タスク完了後、エージェント自身が git diff を確認してコードレビューを実施
- `--no-review` オプションでレビューをスキップ可能
- セキュリティ、バグ、パフォーマンス等の観点でチェック

### クリーンアップ

- `claude-tmux clean` - 完了/死亡したエージェントのディレクトリを自動削除
- 意図しないファイル変更のリスクがあるため、実行後に `git diff` で変更内容を確認すること
