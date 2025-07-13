gh issue view $ARGUMENTS でGitHubのIssueの内容を確認し、タスクの遂行を行なってください。
タスクは以下の手順で進めてください。

1. Issueに記載されている内容を理解する
2. mainにチェックアウトし、pullを行い、最新のリモートの状態を取得する
3. Issueの内容を元に、適切な命名でブランチを作成、チェックアウトする
4. Issueの内容を実現するために必要なタスクをTDD（テスト駆動開発）に基づいて遂行する
6. テストとLintを実行し、すべてのテストが通ることを確認する
7. コミットを適切な粒度で作成する
8. 以下のルールに従ってPRを作成する
    - PRのdescriptionのテンプレートは @.github/PULL_REQUEST_TEMPLATE.md を参照し、それに従うこと
    - PRのdescriptionのテンプレート内でコメントアウトされている箇所は必ず削除すること
    - PRのdescriptionには`Closes #$ARGUMENTS`と記載すること
