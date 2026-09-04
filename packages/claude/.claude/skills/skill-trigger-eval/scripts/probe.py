#!/usr/bin/env python3
"""スキルが実際に発火するかを、本物のスキル群を走らせて測る。

skill-creator の scripts/run_eval.py を使わない理由:

1. あちらは description だけ入れた偽のスラッシュコマンドを評価する。本物のスキルは
   ~/.claude/skills から同時にロードされたままなので、本物が勝つと not-triggered と数える。
   どのスキルが横取りしたかも記録されない。
2. あちらは assistant イベントに tool_use が無いと即 False を返す。thinking を出すモデルでは
   thinking ブロックの assistant が tool_use より先に届くため、ほぼ全件が not-triggered になる。

ここでは偽コマンドを作らず、発火した「スキル名」と、そこに至る tool 列を記録する。
判定を「最初の tool_use」に限らないのは、Bash でファイルを読んでから Skill を呼ぶ経路
(`Bash → Skill`)を取りこぼさないため。
"""

import argparse
import json
import os
import select
import subprocess
import sys
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def tool_uses_in_event(event: dict) -> list[tuple[str, str | None]]:
    """1イベントに含まれる tool_use を (ツール名, スキル名 or None) の列で返す。

    副作用を持たない純粋関数。プロセスを起動せずに全分岐をテストできる。
    assistant 以外のイベントと、tool_use を含まない assistant は空リストを返す
    (ここで打ち切らないことが thinking 対応の要点)。
    """
    if event.get("type") != "assistant":
        return []
    out: list[tuple[str, str | None]] = []
    for item in event.get("message", {}).get("content", []):
        if item.get("type") != "tool_use":
            continue
        name = item.get("name", "")
        skill = item.get("input", {}).get("skill", "?") if name == "Skill" else None
        out.append((name, skill))
    return out


def scan_stream(lines, max_tools: int) -> dict:
    """stream-json の行を順に食わせ、tool 列と最初に発火したスキル名を返す。

    Skill が出るか max_tools 本に達した時点で打ち切る。
    """
    tools: list[str] = []
    skill: str | None = None
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        for name, got_skill in tool_uses_in_event(event):
            tools.append(name)
            if got_skill is not None and skill is None:
                skill = got_skill
        if skill is not None or len(tools) >= max_tools:
            break
    return {"tools": tools, "skill": skill}


def run_query(query: str, cwd: str, timeout: int, max_tools: int, model: str | None) -> dict:
    cmd = ["claude", "-p", query, "--output-format", "stream-json", "--verbose"]
    if model:
        cmd.extend(["--model", model])
    # CLAUDECODE を外さないと Claude Code セッション内から claude -p を起動できない
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}

    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=cwd, env=env
    )
    tools: list[str] = []
    skill: str | None = None
    buffer = ""
    start = time.time()
    try:
        while time.time() - start < timeout:
            if proc.poll() is not None:
                rest = proc.stdout.read()
                if rest:
                    buffer += rest.decode("utf-8", errors="replace")
                break
            ready, _, _ = select.select([proc.stdout], [], [], 1.0)
            if not ready:
                continue
            chunk = os.read(proc.stdout.fileno(), 8192)
            if not chunk:
                break
            buffer += chunk.decode("utf-8", errors="replace")
            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                got = scan_stream([line], max_tools=1)
                tools.extend(got["tools"])
                if got["skill"] and skill is None:
                    skill = got["skill"]
                if skill is not None or len(tools) >= max_tools:
                    return {"tools": tools, "skill": skill}
        rest = scan_stream(buffer.split("\n"), max_tools)
        tools.extend(rest["tools"])
        return {"tools": tools, "skill": skill or rest["skill"]}
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()


def summarize(items: list[dict], results: dict[int, list[dict]]) -> tuple[int, list[str]]:
    """測定結果を人が読む行に整形する。多数決で HIT/MISS を決める。"""
    passed = 0
    out: list[str] = []
    for i, item in enumerate(items):
        runs = results[i]
        expected = item.get("expected")
        fired = Counter(r["skill"] for r in runs)
        hits = sum(1 for r in runs if r["skill"] == expected)
        ok = hits > len(runs) / 2
        passed += ok
        out.append(f"{'HIT ' if ok else 'MISS'} 期待={expected}  発火={dict(fired)}")
        # 期待と違うスキルが取った回だけ tool 列を出す(犯人の特定に効く)
        for r in runs:
            if r["skill"] != expected:
                out.append(f"     列: {' → '.join(r['tools']) or '(なし)'}")
        out.append(f"     {item['query'][:62]}")
    return passed, out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--eval-set", required=True, help="[{query, expected}] の JSON")
    ap.add_argument("--cwd", required=True, help="claude -p を走らせる作業ディレクトリ")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--timeout", type=int, default=200)
    ap.add_argument("--max-tools", type=int, default=4)
    ap.add_argument("--model", default=None)
    args = ap.parse_args()

    items = json.loads(Path(args.eval_set).read_text())
    jobs = [(i, it) for i, it in enumerate(items) for _ in range(args.runs)]
    results: dict[int, list[dict]] = {i: [] for i in range(len(items))}

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {
            ex.submit(run_query, it["query"], args.cwd, args.timeout, args.max_tools, args.model): i
            for i, it in jobs
        }
        done = 0
        for f in as_completed(futs):
            try:
                results[futs[f]].append(f.result())
            except Exception as e:  # noqa: BLE001
                results[futs[f]].append({"tools": [], "skill": f"<error:{type(e).__name__}>"})
            done += 1
            print(f"  {done}/{len(jobs)}", file=sys.stderr, flush=True)

    passed, lines = summarize(items, results)
    print("\n".join(lines))
    print(f"\n=== {passed}/{len(items)} 期待どおり ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
