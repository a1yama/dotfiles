#!/bin/bash
# 「指示された手段を検証せずに従う」を検出するためのシグナル判定。
# premise-check.sh(着手前の注入)と stop-premise-gate.sh(終了前の検査)の両方から source する。
#
# 片方だけパターンを直すと「注入したのにゲートが見ない」「ゲートだけ発火して案内が無い」が起きるため
# 判定はこのファイルにしか置かない。
#
# 精度を再現率より優先する。誤発火は毎ターン余計な節を書かせることになり、
# 数日で「またこれか」と読み飛ばされてゲート全体が死ぬ。取りこぼしは Stop 側の
# frame-check(長時間作業の監査)が別の閾値で拾う。

# 手戻り: 直前の成果物が間違っていた、と言われている
PREMISE_RE_REWORK='間違[っいえ]|誤り|誤って|おかしい|直して|直せ|修正して|修正し直|やり直|作り直|元に戻|戻して|動かない|動いてい?ない|効いてい?ない|できてい?ない|なってい?ない|反映されてい?ない|失敗して|バグって|壊れて|想定と違|違います|そうじゃない|ダメ|だめ'
PREMISE_RE_REWORK_EN='(^|[^a-zA-Z])(wrong|broken|revert|regressed)([^a-zA-Z]|$)|does(n.t| not) work|not working|fix (it|this|that)'

# 数値目標: 依頼に満たすべき数字・条件が入っている。
# 手戻り・手段指定より深い罠で、数値は目的の代理指標にすぎないのに目的そのものとして
# 最適化してしまう。指標を満たす最短経路はたいてい目的を壊す(アサーションを緩めてテストを通す、
# 型を any にしてビルドを通す、測定条件でだけ速くする、条件を後から絞り込んで数字を合わせる)。
# 数字が入っていること自体は機械的に分かるので、ここはフックで確実に引ける。
PREMISE_RE_TARGET='[0-9０-９]+[ 　]*[%％]|[0-9０-９]+[ 　]*[倍割]|最大化|最小化|最大限|極大化|できるだけ(多く|高く|大きく|少なく)|なるべく(多く|高く|少なく)|[0-9０-９]+[ 　]*(件|回|人|円|ms|秒|分|時間)[ 　]*(以上|以下|未満|超)'
PREMISE_RE_TARGET_EN='[0-9]+ *%|[0-9]+ *x( |$)|maximi[sz]e|minimi[sz]e|as (many|much|high|fast) as'

# 手段指定: 依頼に「どうやるか」が含まれている
PREMISE_RE_METHOD='を使って|使って(実装|作|書|直|やっ)|で実装|で書いて|で作って|でやって|に変えて|に置き換え|ではなく|の代わりに|する形で|方式で|アプローチで|やり方で|手順で'
PREMISE_RE_METHOD_EN='(^|[^a-zA-Z])(instead of|rather than|using)([^a-zA-Z]|$)'

# premise_signal <prompt>
#   手戻りなら "rework"、数値目標なら "target"、手段指定なら "method"、
#   どれでもなければ空文字を返す。
#   優先順位は rework > target > method。複数当たる依頼では、疑うべき対象が
#   深いものを選ぶ(前回の手段 > 目的関数 > 実装手段)。
premise_signal() {
  local text="$1"

  # スラッシュコマンドの起動そのものは依頼文ではない。
  # コマンド定義の文面がたまたま当たって毎回発火するのを防ぐ
  case "$text" in
    *'<command-name>'*) return 0 ;;
  esac

  if printf '%s' "$text" | grep -qiE "$PREMISE_RE_REWORK|$PREMISE_RE_REWORK_EN"; then
    printf 'rework'
    return 0
  fi
  if printf '%s' "$text" | grep -qiE "$PREMISE_RE_TARGET|$PREMISE_RE_TARGET_EN"; then
    printf 'target'
    return 0
  fi
  if printf '%s' "$text" | grep -qiE "$PREMISE_RE_METHOD|$PREMISE_RE_METHOD_EN"; then
    printf 'method'
    return 0
  fi
  return 0
}
