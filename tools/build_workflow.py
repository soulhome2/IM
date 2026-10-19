#!/usr/bin/env python3
"""Сборка prototype/workflow.js, openapi.js, fixture.js и strings.js из Specification/State_machine/,
примеров машины сценариев для её тестов (tests/scenario-examples.js) из Specification/Scenario_machine/examples/,
таблицы переходов для человека Specification/State_machine/TRANSITIONS.md и перечня настроек
администратора Specification/State_machine/SETTINGS.md.

Прототип открывают как файл (file://), а оттуда браузер не даёт прочитать JSON.
Поэтому машина, контракт API и эталонный набор данных подключаются обычными скриптами:
window.IM_WORKFLOW, window.IM_OPENAPI, window.IM_FIXTURE и каталог строк window.IM_STRINGS
(§14.9: strings/<язык>.json → { язык: { ключ: строка } }). Машину исполняет встроенный
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixture  # noqa: E402
import settings_doc  # noqa: E402
import transitions_doc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MACHINE = os.path.join(ROOT, "Specification", "State_machine")
TARGETS = [
    ("workflow.v4.json", "workflow.js", "IM_WORKFLOW", 2),
    ("openapi.json", "openapi.js", "IM_OPENAPI", None),
    ("fixtures/demo.json", "fixture.js", "IM_FIXTURE", None),
]


def build(source, var, indent):
    if source == "fixtures/demo.json":
        # Эталонный набор — с файлами сценариев fixtures/scenarios/ (DATA-09)
        data = fixture.load()
        source = "fixtures/demo.json и fixtures/scenarios/*.json"
    else:
        with open(os.path.join(MACHINE, source), encoding="utf-8") as f:
            data = json.load(f)
    header = (
        f"// Собрано из Specification/State_machine/{source} скриптом tools/build_workflow.py.\n"
        "// Руками не править: правится исходник, затем сборка.\n"
    )
    body = json.dumps(data, ensure_ascii=False, indent=indent, separators=None if indent else (",", ":"))
    return f"{header}window.{var} = {body};\n"


def build_strings():
    """Каталог строк (§14.9): все strings/<язык>.json в один объект { язык: { ключ: строка } }."""
    folder = os.path.join(MACHINE, "strings")
    catalog = {}
    for name in sorted(os.listdir(folder)):
        if name.endswith(".json"):
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                catalog[name[:-5]] = {k: v for k, v in json.load(f).items() if not k.startswith("$")}
    header = (
        "// Собрано из Specification/State_machine/strings/*.json скриптом tools/build_workflow.py.\n"
        "// Руками не править: правится исходник, затем сборка.\n"
    )
    return f"{header}window.IM_STRINGS = {json.dumps(catalog, ensure_ascii=False, indent=2)};\n"


def build_scenario_examples():
    """Примеры машины сценариев (Specification/Scenario_machine/examples/**) — тестам исполнителя
    сценариев: { путь от examples/: сценарий }."""
    folder = os.path.join(ROOT, "Specification", "Scenario_machine", "examples")
    examples = {}
    for base, dirs, files in os.walk(folder):
        dirs.sort()
        for name in sorted(files):
            if name.endswith(".json"):
                with open(os.path.join(base, name), encoding="utf-8") as f:
                    examples[os.path.relpath(os.path.join(base, name), folder).replace(os.sep, "/")] = json.load(f)
    header = (
        "// Собрано из Specification/Scenario_machine/examples/ скриптом tools/build_workflow.py.\n"
        "// Руками не править: правится исходник, затем сборка.\n"
    )
    return f"{header}window.IM_SCENARIO_EXAMPLES = {json.dumps(dict(sorted(examples.items())), ensure_ascii=False)};\n"


def outputs():
    """(путь от корня, текст, из чего собран) — всё, что собирает этот скрипт."""
    for source, target, var, indent in TARGETS:
        yield f"prototype/{target}", build(source, var, indent), source
    yield "prototype/strings.js", build_strings(), "strings/*.json"
    yield "tests/scenario-examples.js", build_scenario_examples(), "Scenario_machine/examples/"
    with open(os.path.join(MACHINE, "workflow.v4.json"), encoding="utf-8") as f:
        w = json.load(f)
    yield "Specification/State_machine/TRANSITIONS.md", transitions_doc.render(w), "workflow.v4.json"
    yield "Specification/State_machine/SETTINGS.md", settings_doc.render(w), "workflow.v4.json"


def main():
    check = "--check" in sys.argv
    code = 0
    for target, text, source in outputs():
        path = os.path.join(ROOT, target)
        if check:
            try:
                with open(path, encoding="utf-8") as f:
                    current = f.read()
            except OSError:
                current = None
            if current != text:
                print(f"{target} отстал от {source}: запустите python3 tools/build_workflow.py")
                code = 1
            else:
                print(f"{target} совпадает с {source}")
            continue
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"Собран {target}")
    return code


if __name__ == "__main__":
    sys.exit(main())
