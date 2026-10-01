#!/usr/bin/env python3
"""Проверка ссылок в Markdown: каждая относительная ссылка ведёт на существующий файл.

Запуск из корня репозитория: python3 tools/check_links.py
Внешние ссылки (http, https, mailto) и якоря внутри файла не проверяются.
Код выхода 1, если есть нерабочие ссылки.
"""
import os
import re
import sys
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
CODE = re.compile(r"```.*?```", re.S)


def markdown_files():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            if name.endswith(".md"):
                yield os.path.join(base, name)


def main():
    broken = []
    for path in sorted(markdown_files()):
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
    for item in broken:
        print(item)
    print(f"Нерабочих ссылок: {len(broken)}")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
