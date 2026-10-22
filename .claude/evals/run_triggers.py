#!/usr/bin/env python3
"""Срабатывание скиллов IM: каждый запрос из triggers.md — свежая сессия claude -p, какой скилл вызван первым.

Запуск из корня репозитория: python3 .claude/evals/run_triggers.py [номер …] [--jobs=N]
Сессия — в режиме plan, без Bash, Edit и Write; гасится на первом вызове скилла, после трёх других
инструментов или через 90 с. Печатает таблицу и precision / recall по im-review, im-fsm, im-fix.
Код выхода 1, если есть несовпадения.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
SKILLS = ("im-review", "im-fsm", "im-fix")
ROW = re.compile(r"^\| (\d+) \| (.+?) \| (\S+) \| ([+−±]) *\|")
TIMEOUT = 90


def claude_bin():
    found = os.environ.get("CLAUDE_BIN") or shutil.which("claude")
    if not found:
        found = next(iter(sorted(glob.glob(os.path.expanduser(
            "~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude")), reverse=True)), None)
    if not found:
        sys.exit("Не найден claude: добавьте в PATH или задайте CLAUDE_BIN")
    return found


def cases():
    with open(os.path.join(HERE, "triggers.md"), encoding="utf-8") as f:
        return [(int(m[1]), m[2], m[3], m[4]) for m in map(ROW.match, f) if m]


def first_skill(binary, prompt):
    """(первый вызванный скилл или «нет», входные токены первого ответа, секунды)."""
    # Без MCP: прогон проверяет скиллы, внешние системы ему не нужны. «--» — запрос не станет флагом
    cmd = [binary, "-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "plan",
           "--disallowedTools", "Bash Edit Write NotebookEdit", "--no-session-persistence", "--strict-mcp-config",
           "--", prompt]
    start = time.time()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    timer = threading.Timer(TIMEOUT, proc.kill)
    timer.start()
    got, tokens, others = "нет", None, 0
    try:
        for line in proc.stdout:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if event.get("type") == "result":
                break
            if event.get("type") != "assistant":
                continue
            usage = event["message"].get("usage") or {}
            if tokens is None and usage:
                tokens = sum(usage.get(k, 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
            uses = [c for c in event["message"]["content"] if c.get("type") == "tool_use"]
            skill = next((c["input"].get("skill") for c in uses if c["name"] == "Skill"), None)
            if skill:
                got = skill
                break
            others += len(uses)
            if others >= 3:
                break
    finally:
        timer.cancel()
        proc.kill()
        proc.wait()
    return got, tokens, round(time.time() - start)


def main():
    wanted = {int(a) for a in sys.argv[1:] if a.isdigit()}
    jobs = next((int(a.split("=", 1)[1]) for a in sys.argv[1:] if a.startswith("--jobs=")), 4)
    todo = [c for c in cases() if not wanted or c[0] in wanted]
    binary = claude_bin()
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(lambda c: (c, first_skill(binary, c[1])), todo))
    print("| № | Запрос | Ожидается | Тип | Вызван первым | Итог | Токенов на входе | с |")
    print("|---|---|---|---|---|---|---|---|")
    bad = 0
    for (n, prompt, expected, kind), (got, tokens, secs) in results:
        ok = got == expected if expected in SKILLS else got not in SKILLS
        bad += not ok
        print(f"| {n} | {prompt} | {expected} | {kind} | {got} | {'✅' if ok else '❌'} | {tokens or '—'} | {secs} |")
    print()
    for skill in SKILLS:
        tp = sum(1 for c, r in results if c[2] == skill and r[0] == skill)
        fp = sum(1 for c, r in results if c[2] != skill and r[0] == skill)
        fn = sum(1 for c, r in results if c[2] == skill and r[0] != skill)
        precision = f"{tp / (tp + fp):.0%}" if tp + fp else "—"
        recall = f"{tp / (tp + fn):.0%}" if tp + fn else "—"
        print(f"{skill}: precision {precision} ({tp} из {tp + fp}), recall {recall} ({tp} из {tp + fn})")
    print(f"Несовпадений: {bad} из {len(results)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
