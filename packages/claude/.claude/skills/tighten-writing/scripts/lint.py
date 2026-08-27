#!/usr/bin/env python3
"""AI臭・冗長さの機械判定。読むのは人間、直すかどうか決めるのも人間（またはスキル）。

    python3 scripts/lint.py doc.md
    python3 scripts/lint.py doc.md --json

検出は「疑い」であって違反ではない。閾値を割ったからといって機械的に直すと、
かえって不自然になる。数値は「どこを見るべきか」を教えるだけのもの。

リズム指標（burstiness / 段落構造の均質性）と「〜ではなく」の出現率という着想は
zenn.dev/coji/articles/natural-japanese-ai-smell-lint に依拠している。
ただし対象が業務文書なので閾値は緩め、判定は警告に留める。
"""
import argparse, json, re, statistics, sys, unicodedata
from pathlib import Path

# ---------- 触らない領域を落とす ----------

def strip_untouchable(text):
    """コードブロック・frontmatter・表・URL・インラインコードを除外した本文を返す。

    これらは添削対象外（値を書き換えると事故になる）なので、指標の計算からも外す。
    """
    lines = text.split("\n")
    out, in_code, in_fm = [], False, False
    if lines and lines[0].strip() == "---":
        in_fm = True
        lines = lines[1:]
    for ln in lines:
        s = ln.strip()
        if in_fm:
            if s == "---":
                in_fm = False
            continue
        if s.startswith("```") or s.startswith("~~~"):
            in_code = not in_code
            continue
        if in_code:
            continue
        if s.startswith("|") or re.match(r"^\|?[\s:\-|]+\|[\s:\-|]*$", s):
            continue  # 表
        ln = re.sub(r"`[^`]*`", "", ln)
        ln = re.sub(r"https?://\S+", "", ln)
        out.append(ln)
    return "\n".join(out)


def body_sentences(body):
    """見出し・箇条書き記号を落とし、文に分割する。"""
    txt = re.sub(r"^\s{0,3}#{1,6}\s+.*$", "", body, flags=re.M)     # 見出し
    txt = re.sub(r"^\s*[-*+]\s+", "", txt, flags=re.M)              # 箇条書き記号
    txt = re.sub(r"^\s*\d+[.)]\s+", "", txt, flags=re.M)
    txt = re.sub(r"\*\*(.+?)\*\*", r"\1", txt)
    parts = re.split(r"(?<=[。！？!?])\s*", txt)
    return [p.strip() for p in parts if len(re.sub(r"\s", "", p)) >= 4]


def paragraphs(body):
    txt = re.sub(r"^\s{0,3}#{1,6}\s+.*$", "", body, flags=re.M)
    blocks = [b for b in re.split(r"\n\s*\n", txt) if len(re.sub(r"\s", "", b)) >= 20]
    res = []
    for b in blocks:
        n = len(re.findall(r"[。！？!?]", b))
        if n >= 1:
            res.append(n)
    return res


def clen(s):
    return len(re.sub(r"\s", "", s))

# ---------- 検出器 ----------

HEDGES = ["と考えられます", "と考えております", "と思われます", "と認識して", "可能性も否定できません",
          "と言えるでしょう", "ではないでしょうか", "が期待されます", "があると考え", "ないわけではない"]
NOMINAL = ["を実施する", "を実施し", "を行う", "を行い", "を図る", "を進めていく", "の実施", "を開始する"]
TRANSLATIONESE = ["することが可能", "する必要性", "という事実", "に関して", "における", "を通じて",
                  "これにより", "のような形で", "という形で", "という点において", "していく"]
EMPTY_MOD = ["非常に", "極めて", "かなり", "大幅に", "しっかりと", "きちんと", "適切に", "確実に",
             "可能な限り", "基本的に", "一定の", "様々な", "多様な", "幅広い", "柔軟に", "スムーズに",
             "円滑に", "効率的に", "継続的に"]
AI_SYNTAX = ["単に", "重要なのは", "こそが", "いかがでしょうか", "ぜひご活用", "つまり",
             "このように", "と言っても過言ではありません"]
BOTHSIDES = ["という意見もあれば", "一方でこうした", "賛否両論", "とも言えますし", "見方もあります"]
CONNECTIVES = ["また", "さらに", "加えて", "そのため", "したがって", "よって", "一方で", "他方",
               "このように", "つまり", "すなわち", "なお"]


def count_terms(sentences, terms):
    hits = {}
    for s in sentences:
        for t in terms:
            if t in s:
                hits.setdefault(t, []).append(s[:60])
    return hits


def taigen_dome_ratio(sentences):
    """体言止めの近似検出。文末が用言で終わっていないものを数える。"""
    verbish = re.compile(r"(です|ます|ました|ません|でした|である|だった|た|る|い|う|く|ぬ|よ|ね|か)[。！？!?]?$")
    n = 0
    for s in sentences:
        core = s.rstrip("。！？!?」』）)")
        if not core:
            continue
        if not verbish.search(core):
            n += 1
    return n / len(sentences) if sentences else 0.0


def check(text, business=True):
    body = strip_untouchable(text)
    sents = body_sentences(body)
    warn = []
    stats = {}
    if len(sents) < 3:
        return {"stats": {}, "warnings": [], "note": "本文が短すぎて指標を出せません"}

    lens = [clen(s) for s in sents]
    mean, sd = statistics.mean(lens), (statistics.stdev(lens) if len(lens) > 1 else 0.0)
    burst = (sd - mean) / (sd + mean) if (sd + mean) else 0.0
    stats["文数"] = len(sents)
    stats["平均文長"] = round(mean, 1)
    stats["文長の標準偏差"] = round(sd, 1)
    stats["burstiness"] = round(burst, 3)
    # 読み物向けの基準は -0.24。業務文書は構造化されていて揃いやすいので -0.35 を目安にする。
    thr = -0.35 if business else -0.24
    if burst < thr:
        warn.append({
            "id": "low_burstiness", "level": "警告",
            "detail": f"burstiness={burst:.3f} が目安({thr})を下回る。文の長短のメリハリが乏しい"
                      f"（平均{mean:.0f}字 / 標準偏差{sd:.0f}字）",
            "hint": "短い断定文を混ぜる。長い文を分けるだけだと全部が同じ長さになって悪化する",
        })

    pcs = paragraphs(body)
    if len(pcs) >= 3:
        pm, psd = statistics.mean(pcs), statistics.stdev(pcs)
        cv = psd / pm if pm else 0.0
        stats["段落数"] = len(pcs)
        stats["段落あたり文数"] = round(pm, 2)
        stats["段落文数の変動係数"] = round(cv, 3)
        if cv <= 0.194:
            warn.append({
                "id": "low_sentence_variance", "level": "警告",
                "detail": f"段落の文数が揃いすぎている（変動係数 {cv:.3f} ≤ 0.194、平均{pm:.1f}文）",
                "hint": "1文だけの段落や、逆に長い段落を作る。全段落を同じ文数に整えるのは逆効果",
            })

    td = taigen_dome_ratio(sents)
    stats["体言止め率(近似)"] = round(td, 3)
    if td == 0.0 and len(sents) >= 12:
        warn.append({"id": "no_taigen_dome", "level": "情報",
                     "detail": "体言止めが1つもない。全文が同じ終わり方で機械的に読める",
                     "hint": "見出しや箇条書きで体言止めを使うだけでも変わる。無理に本文に入れる必要はない"})

    denaku = sum(s.count("ではなく") + s.count("だけでなく") for s in sents)
    rate = denaku / len(sents)
    stats["否定対比構文の出現率"] = round(rate, 3)
    if rate > 0.05 and denaku >= 3:  # 短い文書で1回だけ出た場合は誤検知になる
        warn.append({"id": "negation_contrast_repeat", "level": "警告",
                     "detail": f"「〜ではなく／だけでなく」が {denaku}回 / {len(sents)}文（{rate:.1%}）。"
                               f"人間の中央値は約1.5%、AIの平均は約8.3%と報告されている",
                     "hint": "言いたい側だけ書けば足りることが多い"})

    bold_colon = re.findall(r"^\s*[-*+]\s*\*\*[^*]+\*\*\s*[:：]", text, flags=re.M)
    stats["太字コロン箇条書き"] = len(bold_colon)
    if len(bold_colon) >= 3:
        warn.append({"id": "bold_colon_bullets", "level": "警告",
                     "detail": f"「**項目**: 説明」形式の箇条書きが{len(bold_colon)}件。AI生成文書の指紋になりやすい",
                     "hint": "表にする、または太字を外して普通の箇条書きにする"})

    bold_all = re.findall(r"\*\*[^*]+\*\*", text)
    stats["太字の総数"] = len(bold_all)
    if len(bold_all) > max(6, len(sents) * 0.25):
        warn.append({"id": "bold_overuse", "level": "情報",
                     "detail": f"太字が{len(bold_all)}箇所。多すぎると強調が効かなくなる",
                     "hint": "本当に読み手が拾うべき1〜3箇所に絞る"})

    for label, terms, level in [
        ("hedge", HEDGES, "警告"), ("nominal_predicate", NOMINAL, "警告"),
        ("translationese", TRANSLATIONESE, "情報"), ("empty_modifier", EMPTY_MOD, "警告"),
        ("ai_syntax", AI_SYNTAX, "情報"), ("both_sides", BOTHSIDES, "警告"),
    ]:
        hits = count_terms(sents, terms)
        total = sum(len(v) for v in hits.values())
        stats[label] = total
        if total:
            top = sorted(hits.items(), key=lambda kv: -len(kv[1]))[:6]
            warn.append({"id": label, "level": level,
                         "detail": f"{total}件: " + "、".join(f"「{k}」×{len(v)}" for k, v in top),
                         "hint": {"hedge": "断定するか、「未確認」と書いて根拠を示す",
                                  "nominal_predicate": "動詞に戻す（対応を実施する→対応する）",
                                  "translationese": "和文の言い方に直す（〜することが可能→〜できる）",
                                  "empty_modifier": "削るか数字にする",
                                  "ai_syntax": "文ごと組み替える。頻度が低ければ問題ない",
                                  "both_sides": "立場を1つに寄せる"}[label]})

    para_starts = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]
    conn = sum(1 for p in para_starts if any(p.lstrip("-*+ ").startswith(c) for c in CONNECTIVES))
    if para_starts:
        r = conn / len(para_starts)
        stats["接続詞で始まる段落の比率"] = round(r, 3)
        if r > 0.3:
            warn.append({"id": "connective_openers", "level": "警告",
                         "detail": f"{conn}/{len(para_starts)}段落が接続詞で始まる（{r:.0%}）",
                         "hint": "半分以上は削れる。論理関係が本当に必要な箇所だけ残す"})

    emoji = [c for c in text if unicodedata.category(c) == "So"]
    if emoji:
        stats["絵文字"] = len(emoji)
        warn.append({"id": "emoji", "level": "情報",
                     "detail": f"絵文字が{len(emoji)}個。業務文書では浮くことが多い", "hint": "削る"})
    if "—" in text or "–" in text:
        warn.append({"id": "em_dash", "level": "情報",
                     "detail": "emダッシュ（—/–）が含まれる。日本語では読点や括弧が自然",
                     "hint": "「、」や（）に置き換える"})

    return {"stats": stats, "warnings": warn}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--prose", action="store_true", help="ブログ・読み物として厳しめの閾値を使う")
    a = ap.parse_args()
    text = Path(a.file).read_text(encoding="utf-8")
    res = check(text, business=not a.prose)
    if a.json:
        print(json.dumps(res, ensure_ascii=False, indent=2)); return
    print(f"# {a.file}\n")
    print("## 指標")
    for k, v in res["stats"].items():
        print(f"  {k}: {v}")
    print(f"\n## 検出 ({len(res['warnings'])}件)")
    if not res["warnings"]:
        print("  なし")
    for w in res["warnings"]:
        print(f"\n[{w['level']}] {w['id']}")
        print(f"    {w['detail']}")
        print(f"    → {w['hint']}")
    print("\n※ 検出は「疑い」です。理由があれば残してください。機械的に全部直すと不自然になります。")


if __name__ == "__main__":
    main()
