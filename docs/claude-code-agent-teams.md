# Claude Code Agent Teams 導入メモ

## 概要

複数のClaude Codeセッションをチームとして統合し、複雑なタスクを協調作業で進める実験的機能。

## 現在の状況

- **利用可否**: システムメッセージでは「not available on this plan」と表示されているが、実際には環境変数で有効化可能
- **ステータス**: 実験的機能（デフォルト無効）
- **プラン制限**: 公式ドキュメントでは明記されていない

## Agent Teams vs Subagents

| 特性 | Subagents (Task tool) | Agent Teams |
|------|----------------------|-------------|
| **コンテキスト** | 独立したコンテキスト | 独立したコンテキスト |
| **通信方法** | メインへの報告のみ | メンバー間で直接通信 |
| **タスク管理** | メインが全て管理 | 共有タスクリストで自己調整 |
| **適用場面** | 短期的なフォーカスタスク | 複雑な協調・議論が必要 |
| **トークンコスト** | 低（結果のみ要約） | 高（各メンバーが独立インスタンス） |

## 有効化方法

### 方法1: settings.json で設定

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

設定ファイルの場所:
- プロジェクト: `./.claude/settings.json`
- グローバル: `~/.claude/settings.json`

### 方法2: 環境変数で設定

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
claude
```

## 主な機能

### 基本的な使用方法

```
I'm designing a CLI tool. Create an agent team to explore this from
different angles: one teammate on UX, one on technical architecture,
one playing devil's advocate.
```

### 表示モード

- **in-process** (デフォルト): 同じターミナル内で実行
- **split panes**: tmux/iTerm2でペイン分割（視覚的に分かりやすい）

### タスク管理

- チームリーダーがタスクを割り当て
- メンバーが自動的にタスクをクレーム
- 共有タスクリストで進捗管理

### チーム規模の推奨

- **開始時**: 3-5人のメンバー
- **タスク数**: 1メンバーあたり5-6タスクが最適
- **スケーリング**: 実際に並列化のメリットがある場合のみ増やす

## 最適なユースケース

1. **並列コードレビュー**: セキュリティ、パフォーマンス、テストカバレッジを分担
2. **競合仮説の検証**: 複数の仮説を並列で調査
3. **新機能の並列開発**: 独立したモジュールの同時実装
4. **多角的な設計検討**: UX、アーキテクチャ、懸念事項を別々に検討

## 現在の制限事項

- セッション再開時に in-process teammates は復元されない
- タスク完了のマーク付けが遅れることがある
- シャットダウンが遅い可能性
- 1セッションにつき1チームのみ管理可能
- Teammates は独自のチームを作成できない（リーダーのみ）
- Split panes 機能は tmux または iTerm2 が必須

## トークンコスト

各メンバーが独立したClaudeインスタンスとして動作するため、トークンコストは線形に増加する。
単一セッションよりもかなり多くのトークンを使用することに注意。

## claude-tmux との統合案

### 現在の claude-tmux の課題

- ヘッドレスモード (`-p`) で実行されるため、対話的な質問ができない
- エージェントが質問すると処理が停止してしまう

### Agent Teams を使った改善案

```bash
# claude-tmux team サブコマンドの追加
claude-tmux team spawn "タスク説明" [--members N]

# 実装イメージ:
# 1. チームリーダーをインタラクティブモードで起動（split pane）
# 2. ワーカーメンバーをヘッドレスモードで起動
# 3. リーダーがメンバーの質問に答えながら進行
# 4. 人間は最終成果物の確認のみ
```

### 実装タスク（TODO）

- [ ] Agent Teams の有効化テスト
  - 環境変数設定で実際に有効になるか確認
  - プランの制限を確認（Pro/Team/Enterprise）
- [ ] `claude-tmux team` サブコマンドの設計
  - チームリーダーとメンバーの役割分担
  - split panes での表示方法
  - タスクの自動割り当てロジック
- [ ] テスト運用
  - 小規模なタスクで動作確認
  - トークンコストの測定
  - 実用性の評価

## 参考リンク

- [Agent Teams - Claude Code Docs](https://code.claude.com/docs/en/agent-teams.md)
- [Claude Code Agent Teams: The Complete Guide 2026](https://claudefa.st/blog/guide/agents/agent-teams)
- [Orchestrate teams of Claude Code sessions](https://code.claude.com/docs/en/agent-teams)

---

**作成日**: 2026-03-02
**更新日**: 2026-03-02
