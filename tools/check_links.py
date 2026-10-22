#!/usr/bin/env python3
"""Проверка ссылок: каждая относительная ссылка в Markdown ведёт на существующий файл,
каждая ссылка «§N» и «§N.M» — на существующий раздел правил (DOC-43).

Запуск из корня репозитория: python3 tools/check_links.py
Внешние ссылки (http, https, mailto) и якоря внутри файла не проверяются.
Ссылки «§» не проверяются на Vision (перед ними слово «Vision»), в описании и стилях прототипа —
там это разделы дизайн-кита, в собранных файлах, архиве правил и прошлых ревью.
Примеры машины сценариев — копии исходника — не проверяются вовсе: ссылки в них ведут на документы
исходного репозитория (Specification/Scenario_machine/ORIGIN.md). Спецификация и схема — свои, проверяются.
Скиллы Claude Code (.claude/) и CLAUDE.md проверяются как документы; кроме ссылок — пути в `…` (файл есть
в репозитории) и заголовок каждого .claude/skills/<имя>/SKILL.md: name совпадает с папкой, description не пуст,
кавычки закрыты, «: » — только в значении в кавычках (иначе YAML не разбирается).
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
# Машина сценариев: примеры — копии исходника (ORIGIN.md), ссылки в них ведут на документы исходного репозитория.
# Спецификация и схема приведены к формату редактора продукта (CHANGELOG) — проверяются как свои
SCENARIO_MACHINE = os.path.join("Specification", "Scenario_machine")
SCENARIO_OWN = {"README.md", "CHANGELOG.md", "ORIGIN.md", "scenario_spec.v1.md", "scenario_schema.v1.json"}


def walk_dirs(base, dirs):
    """Каталоги на «.» пропускаются, кроме .claude в корне — скиллы и настройки Claude Code."""
    dirs[:] = [d for d in dirs if not d.startswith(".") or (base == ROOT and d == ".claude")]


def source_copy(rel):
    return rel.startswith(SCENARIO_MACHINE + os.sep) and os.path.basename(rel) not in SCENARIO_OWN


def markdown_files():
    for base, dirs, files in os.walk(ROOT):
        walk_dirs(base, dirs)
        for name in files:
            if name.endswith(".md"):
                yield os.path.join(base, name)


def section_refs():
    """Ссылки «§N» и «§N.M», которых нет среди заголовков правил."""
    with open(RULES, encoding="utf-8") as f:
        valid = set(HEADING.findall(f.read()))
    for base, dirs, files in os.walk(ROOT):
        walk_dirs(base, dirs)
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
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


# Путь в `…`: есть «/» и расширение, без шаблонов и подстановок
CODE_PATH = re.compile(r"`([\w.-]+(?:/[\w.-]+)+\.\w+)`")


def skill_problems():
    """Пути в `…` в CLAUDE.md и скиллах — существуют; заголовок SKILL.md — name по папке, description."""
    files = set()
    for base, dirs, names in os.walk(ROOT):
        walk_dirs(base, dirs)
        files.update(os.path.relpath(os.path.join(base, n), ROOT).replace(os.sep, "/") for n in names)
    docs = ["CLAUDE.md"] + sorted(f for f in files if f.startswith(".claude/skills/") and f.endswith(".md"))
    for rel in docs:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            text = f.read()
        here = os.path.dirname(rel)
        for match in CODE_PATH.finditer(text):
            path = match.group(1)
            near = os.path.normpath(os.path.join(here, path)).replace(os.sep, "/")
            # Путь может быть от корня, от файла или хвостом пути (`State_rules/CHANGELOG.md`)
            if path in files or near in files or any(f.endswith("/" + path) for f in files):
                continue
            line = text.count("\n", 0, match.start()) + 1
            yield f"{rel}:{line}: {path} — такого файла нет"
        if os.path.basename(rel) != "SKILL.md":
            continue
        head = re.match(r"---\n(.*?)\n---\n", text, re.S)
        fields = dict(re.findall(r"^(\w+): *(.*)$", head.group(1), re.M)) if head else {}
        for key, value in list(fields.items()):
            line = text.count("\n", 0, text.find(f"\n{key}:")) + 2
            quoted = value[:1] in ('"', "'")
            if quoted and (len(value) < 2 or value[-1] != value[0]):
                yield f"{rel}:{line}: {key} — кавычка не закрыта"
            elif not quoted and (": " in value or " #" in value):
                yield f"{rel}:{line}: {key} — «: » или « #» без кавычек ломает YAML: взять значение в кавычки"
            fields[key] = value[1:-1] if quoted and len(value) > 1 and value[-1] == value[0] else value
        folder = os.path.basename(here)
        if fields.get("name") != folder:
            yield f"{rel}:2: name «{fields.get('name')}» не совпадает с папкой «{folder}»"
        if not fields.get("description"):
            yield f"{rel}:3: нет description"


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
    broken += skill_problems()
    for item in broken:
        print(item)
    print(f"Нерабочих ссылок: {len(broken)}")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
