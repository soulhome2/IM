#!/usr/bin/env python3
"""Проверка словарей перевода прототипа: нет лишних ключей и словари языков совпадают.

Запуск из корня репозитория: python3 tools/check_i18n.py
Ключ — русская строка. Он используется, если встречается целиком как строка: в коде прототипа и машине
состояний (prototype/workflow.js) — всё содержимое литерала в кавычках "…", '…' или `…`; в разметке —
весь текст элемента или значение атрибута. Подстрока другой строки или комментарий не считаются (PROC-32).
Непереведённые строки ловит самопроверка прототипа.
С --fix удаляет лишние ключи из словарей.
Код выхода 1, если нашлись лишние ключи или ключи, которые есть только в одном языке.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROTO = os.path.join(ROOT, "prototype")
DICTS = ["i18n-ui.js", "i18n-data.js", "i18n-html.js"]
SOURCES = ["app.js", "engine.js", "server.js", "fixture.js", "colleagues.js", "api.js", "workflow.js", "strings.js", "index.html", "selftest.js"]
ENTRY = r'^    "((?:[^"\\]|\\.)*)":\s*(?:\n\s*)?"(?:[^"\\]|\\.)*",\n'


def section(text, lang):
    start = text.index(f"\n  {lang}: {{")
    end = text.index("\n  },", start)
    return start, end


def used_in(key, sources):
    """Встречается ли ключ целиком как строка: в кавычках "…", '…', `…`; в разметке — весь текст элемента
    или значение атрибута. Подстрока другой строки или комментарий не считаются (PROC-32)."""
    k = re.escape(key)
    whole = re.compile(rf'"{k}"|\'{k}\'|`{k}`|>\s*{k}\s*<|="{k}"')
    return any(whole.search(text) for text in sources)


def keys_of(text, lang):
    start, end = section(text, lang)
    return re.findall(ENTRY, text[start:end + 1], re.M)


def main():
    fix = "--fix" in sys.argv
    sources = []
    for name in SOURCES:
        with open(os.path.join(PROTO, name), encoding="utf-8") as f:
            sources.append(f.read())
    problems = 0
    for name in DICTS:
        path = os.path.join(PROTO, name)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        # Языки словаря — все разделы; каждый сверяется с английским
        langs = re.findall(r"^  ([a-z]{2}): \{$", text, re.M)
        sets = {lang: set(keys_of(text, lang)) for lang in langs}
        for lang in langs:
            for key in sorted(sets["en"] ^ sets[lang]):
                print(f"{name}: «{key}» есть только в {'en' if key in sets['en'] else lang}")
                problems += 1
        unused = sorted(k for k in set().union(*sets.values()) if not used_in(k.replace('\\"', '"'), sources) and not used_in(k, sources))
        for key in unused:
            print(f"{name}: лишний ключ «{key}»")
        problems += 0 if fix else len(unused)
        if fix and unused:
            for key in unused:
                text = re.sub(r'^    "' + re.escape(key) + r'":\s*(?:\n\s*)?"(?:[^"\\]|\\.)*",\n', "", text, flags=re.M)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            print(f"{name}: удалено {len(unused)}")
    print(f"Проблем в словарях: {problems}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
