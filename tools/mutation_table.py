#!/usr/bin/env python3
"""Таблица «порча машины → кто ловит» (PROC-75): tools/mutations/MACHINE.md.

Порчи — общий список tools/mutations/machine.json. Кто поймал — из последних прогонов: модель Quint —
tools/mutations/quint-catchers.json (пишет tools/check_quint_mutations.mjs), тесты API — tools/mutations/api-killers.json
(пишет tools/check_code_mutations.py). Порча, которую ловят тесты API, но не модель, — кандидат в инвариант;
которую не ловит никто — дыра.

Запуск из корня репозитория: python3 tools/mutation_table.py [--check] — --check: таблица не отстала от прогонов.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import machine_mutations  # noqa: E402

ROOT = machine_mutations.ROOT
DIR = os.path.join(ROOT, "tools", "mutations")
OUT = os.path.join(DIR, "MACHINE.md")


def read(name):
    try:
        with open(os.path.join(DIR, name), encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def cell(results, name):
    if name not in results:
        return "не прогонялась"
    return results[name] or "**не поймана**"


def main():
    quint, api = read("quint-catchers.json"), read("api-killers.json")
    rows, counts = [], {"обе": 0, "только модель": 0, "только тесты API": 0, "никто": 0, "модель не проверяет (пометка)": 0, "не прогонялась": 0}
    for m in machine_mutations.load():
        q, a = quint.get(m["name"]), api.get(m["name"])
        if m.get("model"):
            counts["модель не проверяет (пометка)"] += 1
        elif m["name"] not in quint or m["name"] not in api:
            counts["не прогонялась"] += 1
        else:
            counts["обе" if q and a else "только модель" if q else "только тесты API" if a else "никто"] += 1
        what = m["what"].replace("|", "\\|")
        model = f"_{m['model']}_" if m.get("model") else cell(quint, m["name"])
        rows.append(f"| `{m['name']}` | {what} | {model} | {cell(api, m['name'])} |")
    text = "\n".join([
        "# Порчи машины — кто ловит",
        "",
        "Собрано `python3 tools/mutation_table.py` из общего списка порч машины [`machine.json`](machine.json) и последних",
        "прогонов: модель Quint — `node tools/check_quint_mutations.mjs` ([`quint-catchers.json`](quint-catchers.json)),",
        "тесты API — `python3 tools/check_code_mutations.py` ([`api-killers.json`](api-killers.json)). Руками не править.",
        "",
        "Ловят тесты API, но не модель, — кандидат в инвариант модели; не ловит никто — дыра (PROC-75). Пометка `model` в",
        "списке — почему модель порчу не проверяет (вне модели, мир модели, эквивалентна, кандидат в инвариант); такие",
        "порчи скрипт модели пропускает.",
        "",
        "Итого: " + ", ".join(f"{k} — {v}" for k, v in counts.items()) + ".",
        "",
        "| Порча | Что ломает | Модель Quint | Тесты API |",
        "|---|---|---|---|",
        *rows,
        "",
    ])
    if "--check" in sys.argv:
        same = os.path.exists(OUT) and open(OUT, encoding="utf-8").read() == text
        print("tools/mutations/MACHINE.md совпадает с прогонами" if same else "tools/mutations/MACHINE.md устарела: python3 tools/mutation_table.py")
        return 0 if same else 1
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"Собрана tools/mutations/MACHINE.md: {', '.join(f'{k} — {v}' for k, v in counts.items())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
