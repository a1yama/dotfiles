以下のタスクを実行してください：

1. 今日の日付（YYYY-MM-DD形式）のObsidianデイリーノートを作成または更新
   - パス: ~/Documents/obsidian/Diary/YYYY/YYYY-MM-DD.md
   - デイリーノートが存在しない場合は新規作成（タイトル: # YYYY-MM-DD）

2. 既存のタスクセクションの処理
   - デイリーノート内に "## 📋 Tasks" で始まるセクションが既に存在する場合：
     - そのセクションから次の "##" または "---" またはファイル末尾までの内容を削除
   - 複数回実行しても重複しないようにする

3. GitHub のタスクを取得
   - 引数が "--all" の場合: 全リポジトリから自分に関連する Open Issue/PR を全て取得
     - Issue: gh search issues --author=@me --state=open --json repository,number,title,url --sort=created
     - PR: gh search prs --author=@me --state=open --json repository,number,title,url --sort=created
   - 引数が "--kyash" または引数なしの場合: Kyash organization 内で自分に関連する Open Issue/PR を全て取得
     - Issue: gh search issues --author=@me --state=open --owner=Kyash --json repository,number,title,url --sort=created
     - PR: gh search prs --author=@me --state=open --owner=Kyash --json repository,number,title,url --sort=created
   - マークダウンのチェックボックス形式で記載

4. Notion API MCP (mcp_notion) を使用して Notion の Tasks データベースからSlackタスクを取得
   - ステータスが "In Progress" または "Not Started" のタスクを取得
   - 優先度（Priority）の高い順にソート
   - 全件取得（page_sizeは大きめに設定）
   - 各タスクページのコンテンツブロックを取得
   - コンテンツの内容を要約してタスクのタイトルとして使用
   - Slack URLをコンテンツから抽出して表示

5. 全てのタスクをデイリーノートの末尾に追加（時刻付き）：
   - 文字エンコーディングはUTF-8で統一
   - 特殊文字や絵文字は正しく処理する
   - 以下のフォーマットで記載：
   ```markdown
   ## 📋 Tasks - HH:MM
   
   ### 🔵 Open Issues (Kyash/All)
   - [ ] [リポジトリ#番号] タイトル - [URL](URL)
   
   ### 🟢 Open Pull Requests (Kyash/All)  
   - [ ] [リポジトリ#番号] タイトル - [URL](URL)
   
   ### 💬 Slack Tasks
   - [ ] 要約されたタスクタイトル - [Slack](SlackURL)
   
   ---
   ```
   
   注意: 時刻（HH:MM）は実行時の時刻を使用し、複数回実行時は最新の情報で上書き更新

6. 完了後、Obsidian でデイリーノートを開く
   - `open "obsidian://open?vault=obsidian&file=Diary%2FYYYY%2FYYYY-MM-DD"`

引数: $ARGUMENTS