#!/usr/bin/env python3
"""Сборка prototype/workflow.js из машины состояний Specification/State_machine/workflow.v4.json.

Прототип открывают как файл (file://), а оттуда браузер не даёт прочитать JSON.
Поэтому машина подключается обычным скриптом: window.IM_WORKFLOW = { ... }.
Руками workflow.js не правится — только машина и затем эта сборка.

Запуск из корня репозитория:
  python3 tools/build_workflow.py          — собрать
  python3 tools/build_workflow.py --check  — проверить, что workflow.js не отстал от машины (для CI)
Код выхода 1, если при --check файл отличается.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "Specification", "State_machine", "workflow.v4.json")
TARGET = os.path.join(ROOT, "prototype", "workflow.js")

HEADER = (
    "// Собрано из Specification/State_machine/workflow.v4.json скриптом tools/build_workflow.py.\n"
    "// Руками не править: правится машина, затем сборка.\n"
)


def build():
    with open(SOURCE, encoding="utf-8") as f:
        workflow = json.load(f)
    body = json.dumps(workflow, ensure_ascii=False, indent=2)
    return f"{HEADER}window.IM_WORKFLOW = {body};\n"


def main():
    text = build()
    if "--check" in sys.argv:
        try:
            with open(TARGET, encoding="utf-8") as f:
                current = f.read()
        except OSError:
            current = None
        if current != text:
            print("prototype/workflow.js отстал от машины: запустите python3 tools/build_workflow.py")
            return 1
        print("prototype/workflow.js совпадает с машиной")
        return 0
    with open(TARGET, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("Собран prototype/workflow.js")
    return 0


if __name__ == "__main__":
    sys.exit(main())
