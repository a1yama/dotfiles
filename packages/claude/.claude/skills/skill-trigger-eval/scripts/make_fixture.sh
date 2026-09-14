#!/usr/bin/env bash
# evals/ のクエリが参照するファイルを実在させるための fixture を作る。
# 存在しないパスを書くと Claude が探索に走り、スキルの良し悪しと無関係な MISS が出る。
#
#   ./make_fixture.sh /tmp/skill-eval-fixture
#   python3 probe.py --eval-set ../evals/review.json --cwd /tmp/skill-eval-fixture/repo

set -euo pipefail
ROOT="${1:?使い方: $0 <fixture を作るディレクトリ>}"

rm -rf "$ROOT"
mkdir -p "$ROOT/repo/internal/auth" "$ROOT/repo/internal/payment"
mkdir -p "$ROOT/docs" "$ROOT/zenn/articles"

# --- review.json / parallel.json / recon.json 用の Go リポジトリ ---
cd "$ROOT/repo"
git init -q
git config user.email eval@example.com
git config user.name eval

cat > go.mod <<'EOF'
module example.com/svc

go 1.23

require github.com/go-chi/chi/v5 v5.0.10
EOF

cat > internal/auth/token.go <<'EOF'
package auth

import "time"

type Token struct {
	Value     string
	ExpiresAt time.Time
}

func (t Token) Valid(now time.Time) bool {
	return now.Before(t.ExpiresAt)
}
EOF

cat > internal/payment/charge.go <<'EOF'
package payment

import "errors"

var ErrInsufficient = errors.New("insufficient balance")

func Charge(balance, amount int) (int, error) {
	if amount > balance {
		return balance, ErrInsufficient
	}
	return balance - amount, nil
}
EOF

git add -A
git commit -qm "initial"

# レビュー対象になる未コミット差分。これが無いと code-review 系のクエリが空振りする
cat > internal/payment/charge.go <<'EOF'
package payment

import "errors"

var ErrInsufficient = errors.New("insufficient balance")

func Charge(balance, amount int) (int, error) {
	if amount < 0 {
		return balance, nil
	}
	if amount > balance {
		return balance, ErrInsufficient
	}
	return balance - amount, nil
}

func Refund(balance, amount int) int {
	return balance + amount
}
EOF

# --- writing.json 用の冗長な原稿 ---
cat > "$ROOT/docs/minutes-0903.md" <<'EOF'
# アーキテクチャ会議 議事録 (2026-09-03)

本日の会議におきましては、まず最初に、現行の決済基盤におけるスケーラビリティの
課題について、各チームからの報告が行われたということが挙げられます。

その結果として、現時点においては、以下のような論点が存在しているということが
明らかになったと言えるのではないかと思われます。

- データベースの接続数が上限に近づきつつあるという点について
- バッチ処理の実行時間が想定よりも長くなっているという点について
- 監視のアラートが過剰に発報しているという点について

これらの点を踏まえまして、次回の会議までに、それぞれの担当者において、
より詳細な調査を実施していただくということで合意がなされました。
EOF

cat > "$ROOT/docs/design-proposal-v3.md" <<'EOF'
# 決済基盤リアーキテクチャ提案 v3

## はじめに
本提案書におきましては、現行の決済基盤が抱えている諸課題に対して、
どのようなアプローチをとるべきかということについて、検討を行った結果を
まとめさせていただいております。

## 背景
ご存知のとおり、現行システムは2019年に構築されたものでありまして、
それ以来、大きなアーキテクチャ上の変更は行われてきておりません。
EOF

cat > "$ROOT/zenn/articles/claude-hooks.md" <<'EOF'
---
title: "Claude Code のフック機構を使い倒す"
---

Claude Code にはフックという仕組みが存在しています。これは、Claude が
何らかのツールを実行しようとしたタイミングや、セッションが開始された
タイミングなどにおいて、任意のシェルスクリプトを実行することができる
という機能であると言うことができます。

この記事におきましては、私が実際に運用しているフックについて、
その設定方法と、なぜそれが必要であったのかという背景について、
できるだけ詳しく説明していきたいと思っております。
EOF

echo "fixture を作成しました: $ROOT"
echo "  Go リポジトリ (review/parallel/recon 用): $ROOT/repo"
echo "  原稿 (writing 用):                        $ROOT"
