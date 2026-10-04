#!/usr/bin/env python3
"""Сборка prototype/workflow.js, openapi.js и fixture.js из Specification/State_machine/.

Прототип открывают как файл (file://), а оттуда браузер не даёт прочитать JSON.
Поэтому машина, контракт API и эталонный набор данных подключаются обычными скриптами:
window.IM_WORKFLOW, window.IM_OPENAPI и window.IM_FIXTURE. Машину исполняет встроенный
сервер прототипа на эталонных данных, по контракту самопроверка и тесты сверяют его ответы.
Руками эти файлы не правятся — только исходники и затем эта сборка.

Запуск из корня репозитория:
  python3 tools/build_workflow.py          — собрать
  python3 tools/build_workflow.py --check  — проверить, что собранные файлы не отстали (для CI)
Код выхода 1, если при --check файл отличается.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MACHINE = os.path.join(ROOT, "Specification", "State_machine")
TARGETS = [
    ("workflow.v4.json", "workflow.js", "IM_WORKFLOW", 2),
    ("openapi.json", "openapi.js", "IM_OPENAPI", None),
    ("fixtures/demo.json", "fixture.js", "IM_FIXTURE", None),
]


def build(source, var, indent):
    with open(os.path.join(MACHINE, source), encoding="utf-8") as f:
        data = json.load(f)
    header = (
        f"// Собрано из Specification/State_machine/{source} скриптом tools/build_workflow.py.\n"
        "// Руками не править: правится исходник, затем сборка.\n"
    )
    body = json.dumps(data, ensure_ascii=False, indent=indent, separators=None if indent else (",", ":"))
    return f"{header}window.{var} = {body};\n"


def main():
    check = "--check" in sys.argv
    code = 0
    for source, target, var, indent in TARGETS:
        text = build(source, var, indent)
        path = os.path.join(ROOT, "prototype", target)
        if check:
            try:
                with open(path, encoding="utf-8") as f:
                    current = f.read()
            except OSError:
                current = None
            if current != text:
                print(f"prototype/{target} отстал от {source}: запустите python3 tools/build_workflow.py")
                code = 1
            else:
                print(f"prototype/{target} совпадает с {source}")
            continue
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"Собран prototype/{target}")
    return code


if __name__ == "__main__":
    sys.exit(main())
