#!/usr/bin/env python3
"""lint.py のテスト。

    python3 scripts/test_lint.py

voice プロファイルは「検出を黙らせる」方向の変更なので、黙らせすぎていないこと
（voice なしでは出る警告が出ること）を対で確認する。
"""
import sys, unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lint


def ids(res):
    return {w["id"] for w in res["warnings"]}


# 文長が揃っていて段落も1文ずつ。voice なしなら burstiness と段落変動係数が鳴る。
UNIFORM = "\n\n".join([
    "この処理は現在の実装では同期的に動いています。",
    "同期的に動くため呼び出し側は完了まで待たされます。",
    "待たされる時間は平均すると約200ミリ秒ほどでした。",
    "この値は本番環境のログを集計して算出しています。",
    "非同期化すれば呼び出し側の待ち時間はなくなります。",
    "ただし順序保証が失われるため別の対処が必要です。",
])


class TestUntouchable(unittest.TestCase):
    def test_code_block_excluded(self):
        body = lint.strip_untouchable("本文です。\n```\nコード内の文です。\n```\n続きです。")
        self.assertNotIn("コード内", body)
        self.assertIn("続き", body)

    def test_frontmatter_and_table_excluded(self):
        body = lint.strip_untouchable("---\nname: x\n---\n| a | b |\n|---|---|\n本文です。")
        self.assertNotIn("name", body)
        self.assertNotIn("| a |", body)
        self.assertIn("本文です", body)

    def test_url_and_inline_code_excluded(self):
        body = lint.strip_untouchable("詳細は https://example.com/a を見る。`foo_bar` を使う。")
        self.assertNotIn("example.com", body)
        self.assertNotIn("foo_bar", body)


class TestShortInput(unittest.TestCase):
    def test_too_short_returns_note(self):
        res = lint.check("短い。")
        self.assertEqual(res["warnings"], [])
        self.assertIn("note", res)

    def test_empty_input(self):
        res = lint.check("")
        self.assertEqual(res["warnings"], [])
        self.assertIn("note", res)


class TestUnpunctuated(unittest.TestCase):
    def test_ratio_counts_lines_without_period(self):
        body = "\n".join(["句点のない行をここに書いている"] * 6)
        self.assertEqual(lint.unpunctuated_ratio(body), 1.0)

    def test_ratio_zero_when_all_punctuated(self):
        body = "\n".join(["句点のある行をここに書いている。"] * 6)
        self.assertEqual(lint.unpunctuated_ratio(body), 0.0)

    def test_too_few_lines_returns_zero(self):
        self.assertEqual(lint.unpunctuated_ratio("句点のない行をここに書く"), 0.0)

    def test_headings_ignored(self):
        body = "\n".join(["# 見出しをここに書いている"] * 6 + ["本文をここに書いている。"] * 6)
        self.assertEqual(lint.unpunctuated_ratio(body), 0.0)

    def test_closing_brackets_are_not_sentence_marks(self):
        # 句点を打たない議事録（田中「〜します」の並び）を「閉じている」と誤判定すると、
        # 文分割が壊れたまま素通りして文書全体が未解析になる。終端は句点類だけで見る。
        body = "\n".join(["田中「来週までに出しておきます」", "佐藤「レビューは二人で見ましょう」"] * 3)
        self.assertEqual(lint.unpunctuated_ratio(body), 1.0)
        res = lint.check(body, business=False)
        self.assertIn("unpunctuated_lines", ids(res))
        self.assertEqual(res["stats"]["文数"], 6)
        self.assertNotIn("note", res)

    def test_density_uses_same_lines_as_ratio(self):
        # 句点なしの本文 + 句点ありの箇条書き。分母がずれていると密度だけが高く出て、
        # AND で組んだガードが意図と逆に外れる（文数が 11 → 5 に化けて警告0件だった）。
        text = "\n".join([
            "今日はリリース作業をしていた",
            "手順書がなかったので手探りで進めた",
            "次からは手順書を先に書く",
            "ドキュメントは大事なので来週まとめたい",
            "来週までにまとめておきたい",
            "レビューもお願いする予定",
        ]) + "\n\n" + "\n".join([
            "- 認証基盤のリファクタを完了した。",
            "- 決済APIのレイテンシを調査した。",
            "- 監視アラートの閾値を見直した。",
            "- デプロイ手順書を更新した。",
            "- 障害報告のテンプレを作った。",
        ])
        body = lint.strip_untouchable(text)
        self.assertEqual(lint.sentence_mark_density(body), 0.0)  # 箇条書きの句点は数えない
        res = lint.check(text, business=False)
        self.assertIn("unpunctuated_lines", ids(res))
        self.assertEqual(res["stats"]["文数"], 11)

    def test_nakaguro_bullets_recognized(self):
        # 「・」は日本語文書で一般的。記号を変えただけで挙動が反転してはいけない。
        for marker in ["・", "- ", "＊ " if False else "* "]:
            body = "\n".join([f"{marker}認証基盤のリファクタを完了した",
                              f"{marker}決済APIのレイテンシを調査した",
                              f"{marker}監視アラートの閾値を見直した",
                              f"{marker}デプロイ手順書を更新した",
                              f"{marker}障害報告のテンプレを作った",
                              f"{marker}オンコール当番表を整理した"])
            self.assertEqual(lint.unpunctuated_ratio(body), 0.0, marker)

    def test_fullwidth_space_bullets_recognized(self):
        body = "\n".join(["-　認証基盤のリファクタを完了した", "-　決済APIのレイテンシを調査した"] * 3)
        self.assertEqual(lint.unpunctuated_ratio(body), 0.0)

    def test_bullets_excluded_from_ratio(self):
        # 週報・リリースノートの箇条書きは句点を打たないのが普通。数えると誤判定になる。
        body = "\n".join([
            "- 認証基盤のリファクタを完了した",
            "- 決済APIのレイテンシを調査した",
            "* 監視アラートの閾値を見直した",
            "1. デプロイ手順書を更新した",
            "2) 障害報告のテンプレを作った",
        ])
        self.assertEqual(lint.unpunctuated_ratio(body), 0.0)

    def test_bullet_list_report_keeps_rhythm_warnings(self):
        text = "# 週次報告\n\n" + "\n".join([
            "- 認証基盤のリファクタを完了した",
            "- 決済APIのレイテンシを調査した",
            "- 監視アラートの閾値を見直した",
            "- デプロイ手順書を更新した",
            "- 障害報告のテンプレを作った",
        ])
        self.assertNotIn("unpunctuated_lines", ids(lint.check(text)))

    def test_hard_wrapped_prose_is_not_mistaken_for_one_line_per_sentence(self):
        # 折り返した普通の文書。行末だけ見ると1行1文と区別できないが、句点は普通に打たれている。
        # 誤検出すると文数・平均文長・体言止め率が全部化け、リズム検出が無言で止まる。
        sents = [
            "この処理は現在の実装では同期的に動いていて、呼び出し側は完了まで待たされる形になっています。",
            "待たされる時間は平均すると約200ミリ秒ほどで、本番環境のログを集計して算出した値になります。",
            "非同期化すれば待ち時間はなくなりますが、順序保証が失われるため別の対処が必要になります。",
        ]
        wrapped = "\n".join(s[i:i + 22] for s in sents for i in range(0, len(s), 22))
        self.assertGreater(lint.unpunctuated_ratio(wrapped), 0.5)   # 行末だけでは判別できない
        self.assertGreater(lint.sentence_mark_density(wrapped), 1.0)  # が、句点は打たれている
        res = lint.check(wrapped, business=False)
        self.assertNotIn("unpunctuated_lines", ids(res))
        self.assertEqual(res["stats"]["文数"], len(sents))

    def test_narrow_hard_wrap_also_survives(self):
        # 折り返し幅を狭めると句点なし行の割合は 0.9 を超える。
        # 「閾値を上げる」対処ではここを救えない。効いているのは密度のほう。
        sents = [
            "この処理は現在の実装では完全に同期的な形で動作していて、呼び出し側は処理が完了するまで待たされ続ける形になってしまっています。",
            "待たされる時間は平均すると約200ミリ秒ほどになっていて、これは本番環境のアクセスログを日次で集計して算出した実測値になります。",
            "非同期化すれば呼び出し側の待ち時間そのものはなくなりますが、順序の保証が失われてしまうため別の対処をあわせて考える必要があります。",
        ]
        wrapped = "\n".join(s[i:i + 12] for s in sents for i in range(0, len(s), 12))
        self.assertEqual(lint.unpunctuated_ratio(wrapped), 1.0)  # 行末だけでは救いようがない
        self.assertNotIn("unpunctuated_lines", ids(lint.check(wrapped, business=False)))
        self.assertEqual(lint.check(wrapped, business=False)["stats"]["文数"], len(sents))

    def test_bullet_with_multiple_spaces(self):
        # 記号のあとの空白が複数でも箇条書きとして扱う。
        # なお BULLET の `[ \t]+` を `[ \t]` に縮めても body_sentences() が strip() するため
        # 公開APIからは差が観測できない。ここで固定できるのは「除外されること」まで。
        body = "\n".join(["-   認証基盤のリファクタを完了した", "1.  決済APIの調査をした"] * 3)
        self.assertEqual(lint.unpunctuated_ratio(body), 0.0)
        self.assertEqual(lint.body_sentences("-   項目をここに書きます。"), ["項目をここに書きます。"])

    def test_density_separates_the_two_styles(self):
        one_per_line = "\n".join(["今日はリリース作業をしていた", "手順書がなかったので手探りで進めた"] * 3)
        self.assertLess(lint.sentence_mark_density(one_per_line), 0.5)

    def test_one_line_per_sentence_suppresses_rhythm_warnings(self):
        # 2024年以降の a1yama の書き方。文分割が壊れるので burstiness を根拠にしない。
        text = "\n".join([
            "今日はリリース作業をしていた",
            "手順書がなかったので手探りで進めた",
            "次からは手順書を先に書く",
            "ドキュメントは大事なので来週まとめたい",
            "来週までにまとめておきたい",
            "レビューもお願いする予定",
        ])
        res = lint.check(text, business=False)
        self.assertIn("unpunctuated_lines", ids(res))
        self.assertNotIn("low_burstiness", ids(res))
        self.assertNotIn("low_sentence_variance", ids(res))
        # ここから下が再発防止の本体。
        # 上の3つは「再分割しない」実装でも通る（早期returnに落ちて警告が出ないため）。
        # 行数まで文数が復元されていることを positive に assert しないと、修正を消しても緑になる。
        self.assertNotIn("note", res)
        self.assertEqual(res["stats"]["文数"], 6)
        # 段落ベースの検出も止める。1行1文だと body 全体が1段落になり、
        # 先頭が「また」なら必ず「1/1段落が接続詞で始まる（100%）」になる。
        self.assertNotIn("connective_openers", ids(res))

    def test_connective_suppressed_when_metrics_shaky(self):
        # 接続詞で始まる段落を2つ作って conn_min を越えさせ、ゲートだけを踏ませる
        text = ("また手順書を先に用意する\n次からは前日までに書いておく\n\n"
                "さらに監視のアラートも設定する\nロールバック手順も書いておく\n"
                "結果は翌日の朝会で共有する\nレビューは二人で見る体制にする")
        got = ids(lint.check(text))
        self.assertIn("unpunctuated_lines", got)
        self.assertNotIn("connective_openers", got)
        # 同じ段落構成で句点だけを足すと shaky でなくなり、ちゃんと鳴る＝ゲートが効いている証拠
        punctuated = ("また手順書を先に用意する。\n次からは前日までに書いておく。\n\n"
                      "さらに監視のアラートも設定する。\nロールバック手順も書いておく。\n"
                      "結果は翌日の朝会で共有する。\nレビューは二人で見る体制にする。")
        self.assertIn("connective_openers", ids(lint.check(punctuated)))

    def test_unpunctuated_still_detects_terms(self):
        # 再分割しないと全文が1文に潰れ、語句の検出まで道連れで死ぬ
        text = "\n".join([
            "これにより対応することが可能になります",
            "つまり運用における改善が期待されます",
            "このように実施を通じて効果があると考えられます",
            "さらに関係者との調整も適切に実施していく所存です",
            "また十分な検証を行う必要があると考えます",
            "以上のように重要な取り組みであると認識しております",
        ])
        got = ids(lint.check(text))
        self.assertIn("unpunctuated_lines", got)
        self.assertIn("translationese", got)
        self.assertIn("hedge", got)


class TestVoiceProfile(unittest.TestCase):
    def test_unknown_voice_raises(self):
        with self.assertRaises(KeyError):
            lint.check(UNIFORM, voice="存在しない書き手")

    def test_apply_voice_without_profile_is_identity(self):
        terms = ["していく", "これにより"]
        self.assertEqual(lint.apply_voice(terms, None), terms)

    def test_burstiness_fires_without_voice(self):
        res = lint.check(UNIFORM, business=False)
        self.assertIn("low_burstiness", ids(res))

    def test_burstiness_suppressed_with_voice(self):
        res = lint.check(UNIFORM, business=False, voice="a1yama")
        self.assertNotIn("low_burstiness", ids(res))
        self.assertNotIn("low_sentence_variance", ids(res))

    def test_burstiness_stat_still_reported(self):
        # 黙らせるのは警告だけ。数値は残す（人間が判断できるように）
        res = lint.check(UNIFORM, business=False, voice="a1yama")
        self.assertIn("burstiness", res["stats"])

    def test_keep_words_not_flagged(self):
        text = "この対応はかなり様々な形で進めていく方針です。しっかりと基本的に対応を行う。単に速度の話ではない。"
        self.assertIn("empty_modifier", ids(lint.check(text)))
        self.assertNotIn("empty_modifier", ids(lint.check(text, voice="a1yama")))
        self.assertNotIn("ai_syntax", ids(lint.check(text, voice="a1yama")))

    def test_unused_words_still_flagged(self):
        # 本人が一度も使っていない語は voice でも残す
        text = ("これにより対応することが可能です。つまり運用における改善が期待されます。"
                "このように実施を通じて効果があると考えられます。")
        got = ids(lint.check(text, voice="a1yama"))
        self.assertIn("translationese", got)
        self.assertIn("hedge", got)

    def test_bold_threshold_is_zero(self):
        text = "**強調**した文をここに書きます。次の文もここに書きます。三つ目の文もここに書きます。"
        self.assertIn("bold_over_voice", ids(lint.check(text, voice="a1yama")))
        self.assertNotIn("bold_over_voice", ids(lint.check(text)))

    def test_no_bold_passes(self):
        text = "強調のない文をここに書きます。次の文もここに書きます。三つ目の文もここに書きます。"
        self.assertNotIn("bold_over_voice", ids(lint.check(text, voice="a1yama")))

    def test_keep_entries_exist_in_detectors(self):
        # 完全一致で除去するので、検出器リストに無い語は黙って no-op になる。
        # 実際に "ちゃんと" が dead entry のまま、SKILL.md だけが「抑制される」と書いていた。
        terms = lint.detector_terms()
        for name, profile in lint.VOICE_PROFILES.items():
            for word in profile.get("keep", []):
                self.assertIn(word, terms, f"{name} の keep「{word}」がどの検出器にも無い")

    def test_bold_ignores_untouchable_regions(self):
        # コードブロック内の ** で警告が出ると、手順0の「触らない領域」を直せと言うことになる
        text = ("本文をここに書きます。次の文もここに書きます。三つ目もここに書きます。\n"
                "```\n**触らない強調**\n```\n")
        self.assertNotIn("bold_over_voice", ids(lint.check(text, voice="a1yama")))

    def test_bold_colon_ignores_code_block(self):
        text = ("本文をここに書きます。次の文もここに書きます。三つ目もここに書きます。\n"
                "```\n- **項目A**: 説明\n- **項目B**: 説明\n- **項目C**: 説明\n```\n")
        self.assertNotIn("bold_colon_bullets", ids(lint.check(text)))

    def test_connective_needs_two_hits(self):
        # 段落が少ない文書で接続詞1回では鳴らない（比率だけだと必ず鳴ってしまう）
        text = "リリースは水曜です。\n\nまた、手順書を用意します。\n\nレビューは二人で見ます。"
        self.assertNotIn("connective_openers", ids(lint.check(text, voice="a1yama")))

    def test_connective_min_applies_to_default_profile_too(self):
        # プロファイルを持たない一般の書き手が主な利用者。既定でも1件では鳴らさない。
        text = "リリースは来週の水曜に実施します。\n\nまた、手順書は前日までに用意します。デプロイ担当も決めます。"
        res = lint.check(text)
        self.assertEqual(res["stats"]["接続詞で始まる段落の比率"], 0.5)  # 比率は閾値超え
        self.assertNotIn("connective_openers", ids(res))                  # それでも鳴らさない

    def test_keep_does_not_cover_unused_variant(self):
        # 「を進めていく」は「していく」と語尾が同じだが実測0回なので keep しない。
        # keep の根拠は本人が実際に使うことで、語形の整合ではない。
        self.assertNotIn("を進めていく", lint.VOICE_PROFILES["a1yama"]["keep"])
        text = "対応を進めていく方針です。次の文をここに書きます。三つ目もここに書きます。"
        self.assertIn("nominal_predicate", ids(lint.check(text, voice="a1yama")))

    def test_connective_threshold_tighter(self):
        # 接続詞2/8段落 = 25%。既定(30%)では鳴らず、a1yama(10%)では鳴る帯
        text = "\n\n".join([
            "リリースは来週の水曜に実施する予定です。",
            "また、手順書は前日までに用意します。",
            "レビューは二人で見る体制にします。",
            "監視のアラートも合わせて設定します。",
            "そのため、当日の担当を決めておきます。",
            "ロールバック手順も書いておきます。",
            "検証環境で一度通してから本番に入ります。",
            "結果は翌日の朝会で共有します。",
        ])
        self.assertNotIn("connective_openers", ids(lint.check(text)))
        self.assertIn("connective_openers", ids(lint.check(text, voice="a1yama")))


class TestDetectors(unittest.TestCase):
    def test_negation_contrast_needs_three_hits(self):
        one = "速度ではなく安定性の話です。次の文をここに書きます。三つ目の文もここに書きます。"
        self.assertNotIn("negation_contrast_repeat", ids(lint.check(one)))
        many = "速度ではなく安定性です。規模ではなく頻度です。数ではなく質です。量ではなく型です。"
        self.assertIn("negation_contrast_repeat", ids(lint.check(many)))

    def test_bold_colon_bullets(self):
        text = ("- **項目A**: 説明をここに書きます。\n- **項目B**: 説明をここに書きます。\n"
                "- **項目C**: 説明をここに書きます。\n本文をここに書きます。")
        self.assertIn("bold_colon_bullets", ids(lint.check(text)))

    def test_em_dash_and_emoji(self):
        text = "これは説明です — そして続きます。次の文をここに書きます。三つ目もここに書きます。🎉"
        got = ids(lint.check(text))
        self.assertIn("em_dash", got)
        self.assertIn("emoji", got)

    def test_em_dash_and_emoji_ignore_code_blocks(self):
        # bold と同じ理由。コードやログの中の記号を「直せ」と言ってはいけない。
        text = ('本文をここに書きます。次の文もここに書きます。三つ目もここに書きます。\n'
                '```\necho "done 🎉"  # 出力 — 完了\n```\n')
        got = ids(lint.check(text))
        self.assertNotIn("em_dash", got)
        self.assertNotIn("emoji", got)


class TestThresholds(unittest.TestCase):
    def test_prose_threshold_is_stricter_than_business(self):
        # 業務文書(-0.35)では許容、読み物(-0.24)では警告になる帯があること
        # burstiness が -0.30 付近に来るよう調整した文書（-0.35 と -0.24 の間）
        mid = "\n\n".join([
            "この処理は同期的に動いています。",
            "呼び出し側は完了まで待たされます。",
            "待ち時間は平均で約200ミリ秒でした。",
            "この値は本番環境のログを集計して算出したもので、時間帯による差はほとんどありませんでした。",
            "非同期化すれば待ち時間はなくなります。",
            "ただし順序保証が失われます。",
        ])
        self.assertIn("low_burstiness", ids(lint.check(mid, business=False)))
        self.assertNotIn("low_burstiness", ids(lint.check(mid, business=True)))


class TestShakyAndVoiceCombined(unittest.TestCase):
    def test_voice_suppression_and_shaky_suppression_stack(self):
        # 両方の抑制が重なっても、本人が使わない語と太字は残る
        text = "\n".join([
            "これにより対応することが可能になります",
            "つまり運用における改善が期待されます",
            "**強調**もここに入れておきます",
            "かなり様々な形で進めていく方針です",
            "しっかりと基本的に対応を行います",
            "単に速度だけの話ではありません",
        ])
        got = ids(lint.check(text, voice="a1yama"))
        self.assertIn("unpunctuated_lines", got)
        self.assertNotIn("low_burstiness", got)
        self.assertIn("bold_over_voice", got)
        self.assertIn("translationese", got)   # これにより／することが可能は実測0件
        self.assertIn("ai_syntax", got)        # つまり も実測0件。単に だけが keep で外れる
        self.assertNotIn("empty_modifier", got)  # かなり／様々な／しっかりと／基本的に は常用語


class TestCli(unittest.TestCase):
    def _run(self, *args):
        import subprocess
        return subprocess.run([sys.executable, str(Path(lint.__file__)), *args],
                              capture_output=True, text=True)

    def setUp(self):
        import tempfile
        self.tmp = tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8")
        self.tmp.write(UNIFORM)
        self.tmp.close()
        self.path = self.tmp.name

    def tearDown(self):
        Path(self.path).unlink(missing_ok=True)

    def test_runs_and_prints_sections(self):
        r = self._run(self.path)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("## 指標", r.stdout)
        self.assertIn("## 検出", r.stdout)

    def test_json_is_parseable(self):
        import json as _json
        r = self._run(self.path, "--json")
        self.assertEqual(r.returncode, 0, r.stderr)
        data = _json.loads(r.stdout)
        self.assertIn("stats", data)
        self.assertIn("warnings", data)

    def test_voice_appears_in_header(self):
        r = self._run(self.path, "--voice", "a1yama")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("voice: a1yama", r.stdout)

    def test_unknown_voice_rejected_by_argparse(self):
        r = self._run(self.path, "--voice", "存在しない書き手")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("--voice", r.stderr)

    def test_note_is_printed(self):
        # 短い文書で「なぜ指標が出ないか」が画面に出ること（--json でしか読めない状態だった）
        p = Path(self.path)
        p.write_text("短い。", encoding="utf-8")
        r = self._run(str(p))
        self.assertIn("本文が短すぎて指標を出せません", r.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
