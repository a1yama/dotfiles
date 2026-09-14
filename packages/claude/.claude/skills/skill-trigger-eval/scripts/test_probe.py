#!/usr/bin/env python3
"""probe.py の純粋関数のテスト。プロセスを起動しないので単体で走る。

    python3 scripts/test_probe.py
"""

import json
import sys

from probe import scan_stream, summarize, tool_uses_in_event


def assistant(*content):
    return {"type": "assistant", "message": {"content": list(content)}}


def tool_use(name, **inp):
    return {"type": "tool_use", "name": name, "input": inp}


FAILS = []


def check(label, got, want):
    if got != want:
        FAILS.append(f"FAIL  {label}\n      want={want!r}\n      got ={got!r}")
        print(f"FAIL  {label}  want={want!r} got={got!r}")
    else:
        print(f"pass  {label}")


# --- tool_uses_in_event: 正常系 ---
check("Skill 発火", tool_uses_in_event(assistant(tool_use("Skill", skill="code-review"))),
      [("Skill", "code-review")])
check("Skill 以外", tool_uses_in_event(assistant(tool_use("Bash", command="ls"))),
      [("Bash", None)])
check("1メッセージに複数 tool", tool_uses_in_event(assistant(tool_use("Bash"), tool_use("Skill", skill="x"))),
      [("Bash", None), ("Skill", "x")])

# --- tool_uses_in_event: 空・境界 ---
check("assistant 以外は空", tool_uses_in_event({"type": "result", "subtype": "success"}), [])
check("thinking のみの assistant は空(打ち切らない)",
      tool_uses_in_event(assistant({"type": "thinking", "thinking": "..."})), [])
check("text のみの assistant は空", tool_uses_in_event(assistant({"type": "text", "text": "hi"})), [])
check("content が空", tool_uses_in_event(assistant()), [])
check("message キーが無い", tool_uses_in_event({"type": "assistant"}), [])
check("空 dict", tool_uses_in_event({}), [])
check("Skill だが input が空", tool_uses_in_event(assistant({"type": "tool_use", "name": "Skill"})),
      [("Skill", "?")])
check("name キーが無い tool_use", tool_uses_in_event(assistant({"type": "tool_use", "input": {}})),
      [("", None)])

# --- scan_stream: 再発防止 ---
# thinking の assistant が tool_use より先に来ても打ち切らない(run_eval.py はここで壊れる)
check("再発防止: thinking が先でも Skill を拾う",
      scan_stream([
          json.dumps(assistant({"type": "thinking", "thinking": "..."})),
          json.dumps(assistant(tool_use("Skill", skill="frame-check"))),
      ], max_tools=4),
      {"tools": ["Skill"], "skill": "frame-check"})

# Bash を挟んでから Skill を呼ぶ経路(「最初の tool_use」判定だと取りこぼす)
check("再発防止: Bash → Skill を拾う",
      scan_stream([
          json.dumps(assistant(tool_use("Bash", command="git diff"))),
          json.dumps(assistant(tool_use("Skill", skill="code-review"))),
      ], max_tools=4),
      {"tools": ["Bash", "Skill"], "skill": "code-review"})

check("max_tools で打ち切る",
      scan_stream([json.dumps(assistant(tool_use("Bash"))) for _ in range(9)], max_tools=3),
      {"tools": ["Bash", "Bash", "Bash"], "skill": None})

check("最後まで Skill 無し",
      scan_stream([json.dumps(assistant(tool_use("Grep")))], max_tools=4),
      {"tools": ["Grep"], "skill": None})

check("空ストリーム", scan_stream([], max_tools=4), {"tools": [], "skill": None})
check("空行だけ", scan_stream(["", "   "], max_tools=4), {"tools": [], "skill": None})
check("不正入力: JSON でない行は飛ばす",
      scan_stream(["これはJSONではない", json.dumps(assistant(tool_use("Skill", skill="a")))], max_tools=4),
      {"tools": ["Skill"], "skill": "a"})
check("最初に発火したスキルだけ採る",
      scan_stream([json.dumps(assistant(tool_use("Skill", skill="first"), tool_use("Skill", skill="second")))],
                  max_tools=4),
      {"tools": ["Skill", "Skill"], "skill": "first"})

# --- summarize: 多数決 ---
items = [
    {"query": "q1", "expected": "a"},
    {"query": "q2", "expected": "a"},
    {"query": "q3", "expected": None},
]
res = {
    0: [{"tools": ["Skill"], "skill": "a"}] * 3,                       # 3/3 → HIT
    1: [{"tools": ["Skill"], "skill": "a"}, {"tools": [], "skill": None},
        {"tools": [], "skill": None}],                                 # 1/3 → MISS
    2: [{"tools": ["Bash"], "skill": None}] * 3,                       # 期待どおり非発火 → HIT
}
passed, _ = summarize(items, res)
check("多数決: 3/3 と 0 件発火が HIT、1/3 が MISS", passed, 2)

res_tie = {0: [{"tools": [], "skill": "a"}, {"tools": [], "skill": None}]}
passed_tie, _ = summarize([{"query": "q", "expected": "a"}], res_tie)
check("境界: 2回中1回(同数)は HIT にしない", passed_tie, 0)

print(f"\n{'FAILED' if FAILS else 'すべて pass'} ({len(FAILS)} 件失敗)")
sys.exit(1 if FAILS else 0)
