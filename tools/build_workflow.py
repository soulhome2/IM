#!/usr/bin/env python3
"""Сборка prototype/workflow.js, openapi.js, fixture.js и strings.js из Specification/Workflow_machine/,
примеров машины сценариев для её тестов (tests/scenario-examples.js) из Specification/Scenario_machine/examples/,
таблицы переходов для человека Specification/Workflow_machine/TRANSITIONS.md и перечня настроек
администратора Specification/Workflow_machine/SETTINGS.md.

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
import openapi30  # noqa: E402
import settings_doc  # noqa: E402
import transitions_doc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MACHINE = os.path.join(ROOT, "Specification", "Workflow_machine")
TARGETS = [
    ("workflow_schema.v1.json", "workflow.js", "IM_WORKFLOW", 2),
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
    return render(data, source, var, indent)


def render(data, source, var, indent):
    """Текст собранного файла — и для порч машины (tools/machine_mutations.py): workflow.js из испорченной машины."""
    header = (
        f"// Собрано из Specification/Workflow_machine/{source} скриптом tools/build_workflow.py.\n"
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
        "// Собрано из Specification/Workflow_machine/strings/*.json скриптом tools/build_workflow.py.\n"
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


def build_openapi30():
    """Копия контракта в OpenAPI 3.0 для генератора сервера (JSON, отступ 2, LF)."""
    with open(os.path.join(MACHINE, "openapi.json"), encoding="utf-8", newline="") as f:
        spec = openapi30.convert(json.load(f))
    left = openapi30.leftovers(spec)
    if left:
        # Без этой остановки копия молча ушла бы генератору сервера с тем, чего 3.0 не знает
        raise SystemExit("Specification/Workflow_machine/openapi.v30.json не собрана: в копии остались конструкции "
                         "OpenAPI 3.1, которых перевод (tools/openapi30.py) не знает:\n  " + "\n  ".join(left))
    note = "Собрано из openapi.json скриптом tools/build_workflow.py (OpenAPI 3.0 для генератора сервера), руками не править."
    spec["info"]["description"] = (spec["info"].get("description", "") + "\n\n" + note).strip()
    return json.dumps(spec, ensure_ascii=False, indent=2) + "\n"


def outputs():
    """(путь от корня, текст, из чего собран) — всё, что собирает этот скрипт."""
    for source, target, var, indent in TARGETS:
        yield f"prototype/{target}", build(source, var, indent), source
    yield "prototype/strings.js", build_strings(), "strings/*.json"
    yield "tests/scenario-examples.js", build_scenario_examples(), "Scenario_machine/examples/"
    with open(os.path.join(MACHINE, "workflow_schema.v1.json"), encoding="utf-8") as f:
        w = json.load(f)
    yield "Specification/Workflow_machine/TRANSITIONS.md", transitions_doc.render(w), "workflow_schema.v1.json"
    yield "Specification/Workflow_machine/openapi.v30.json", build_openapi30(), "openapi.json"
    yield "Specification/Workflow_machine/SETTINGS.md", settings_doc.render(w), "workflow_schema.v1.json"


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
