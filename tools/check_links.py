#!/usr/bin/env python3
"""Проверка ссылок: каждая относительная ссылка в Markdown ведёт на существующий файл,
каждая ссылка «§N» и «§N.M» — на существующий раздел правил (DOC-43).

Запуск из корня репозитория: python3 tools/check_links.py
Внешние ссылки (http, https, mailto) и якоря внутри файла не проверяются.
Ссылки «§» не проверяются на Vision (перед ними слово «Vision»), в описании и стилях прототипа —
там это разделы дизайн-кита, в собранных файлах, архиве правил и прошлых ревью.
Копии исходника машины сценариев (спецификация, схема, примеры) не проверяются вовсе: «§» там — разделы
спецификации DSL, а ссылки ведут на документы исходного репозитория (Specification/Scenario_machine/ORIGIN.md).
Код выхода 1, если есть нерабочие ссылки.
"""
import os
import re
import sys
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
CODE = re.compile(r"```.*?```", re.S)
RULES = os.path.join(ROOT, "Specification", "State_rules", "States rules IM.md")
SECTION = re.compile(r"§\s?(\d+(?:\.\d+)*)")
HEADING = re.compile(r"^##+ (\d+(?:\.\d+)?)\.? ", re.M)
# Где «§» — не правила: архив и прошлые ревью, разделы дизайн-кита, собранные копии машины
SKIP_DIRS = {"archive", "reviews", "node_modules"}
SKIP_FILES = {
    os.path.join("prototype", "README.md"),
    os.path.join("prototype", "workflow.js"),
    os.path.join("prototype", "openapi.js"),
    os.path.join("prototype", "fixture.js"),
    os.path.join("prototype", "strings.js"),
}
# Машина сценариев: спецификация, схема и примеры — копии исходника байт в байт (ORIGIN.md), не правятся.
# «§» в них — разделы спецификации DSL, ссылки ведут на документы исходного репозитория, не перенесённые в IM
SCENARIO_MACHINE = os.path.join("Specification", "Scenario_machine")
SCENARIO_OWN = {"README.md", "CHANGELOG.md", "ORIGIN.md"}


def source_copy(rel):
    return rel.startswith(SCENARIO_MACHINE + os.sep) and os.path.basename(rel) not in SCENARIO_OWN


def markdown_files():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            if name.endswith(".md"):
                yield os.path.join(base, name)


def section_refs():
    """Ссылки «§N» и «§N.M», которых нет среди заголовков правил."""
    with open(RULES, encoding="utf-8") as f:
        valid = set(HEADING.findall(f.read()))
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS]
        for name in sorted(files):
            path = os.path.join(base, name)
            rel = os.path.relpath(path, ROOT)
            if not name.endswith((".md", ".json", ".js", ".py", ".html")) or rel in SKIP_FILES or source_copy(rel):
                continue
            with open(path, encoding="utf-8") as f:
                text = f.read()
            for match in SECTION.finditer(text):
                if match.group(1) in valid or "Vision" in text[max(0, match.start() - 30):match.start()]:
                    continue
                line = text.count("\n", 0, match.start()) + 1
                yield f"{rel}:{line}: §{match.group(1)} — такого раздела в правилах нет"


def main():
    broken = []
    for path in sorted(markdown_files()):
        if source_copy(os.path.relpath(path, ROOT)):
            continue
        with open(path, encoding="utf-8") as f:
            text = CODE.sub("", f.read())
        for match in LINK.finditer(text):
            target = match.group(1)
            if re.match(r"^[a-z]+:", target) or target.startswith("#"):
                continue
            file_part = unquote(target.split("#")[0].split("?")[0])
            if not os.path.exists(os.path.join(os.path.dirname(path), file_part)):
                line = text.count("\n", 0, match.start()) + 1
                broken.append(f"{os.path.relpath(path, ROOT)}:{line}: {target}")
    broken += section_refs()
    for item in broken:
        print(item)
    print(f"Нерабочих ссылок: {len(broken)}")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
