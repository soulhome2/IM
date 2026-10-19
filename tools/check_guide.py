#!/usr/bin/env python3
"""Проверка руководства оператора: названия в нём — те же, что на экране.

Запуск из корня репозитория: python3 tools/check_guide.py
Название — текст в «» и жирный текст в Specification/Operator guide.md. Жирный текст с точкой
или двоеточием в конце — начало абзаца, а не название: не проверяется. Текст без букв («2/0») —
тоже. Название должно совпасть с текстом интерфейса целиком или с его шаблоном: «Отложен · причина»
подходит к «Отложен · {holdReasonLabel}». Тексты интерфейса — строки машины strings/ru.json,
эталонных данных, переводов i18n-ui.js, app.js и index.html.
Код выхода 1, если есть названия, которых на экране нет: кнопку переименовали, а руководство отстало.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixture  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUIDE = "Specification/Operator guide.md"
NAME = re.compile(r"«([^«»]+)»|\*\*([^*]+)\*\*")
QUOTED = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
TEXT_NODE = re.compile(r">([^<>]+)<")
SLOT = re.compile(r"(\{\w+\})")
LETTER = r"[A-Za-zА-Яа-яЁё]"
NUMBER = re.compile(r"\{(n|i|a|h|max|id|ids|count)\}$")


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def json_strings(value):
    if isinstance(value, dict):
        for v in value.values():
            yield from json_strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from json_strings(v)
    elif isinstance(value, str):
        yield value


def ui_texts():
    texts = set(json_strings(json.loads(read("Specification/Workflow_machine/strings/ru.json"))))
    texts |= set(json_strings(fixture.load()))
    for path in ("prototype/i18n-ui.js", "prototype/app.js", "prototype/index.html"):
        source = read(path)
        texts |= set(QUOTED.findall(source))
        if path.endswith(".html"):
            texts |= set(TEXT_NODE.findall(source))
    return {" ".join(t.split()) for t in texts if t.strip()}


def template(text):
    """Шаблон с подстановками {имя} — в выражение. Нужна хоть одна буква вне подстановок: «{number}: {reason}» подошёл бы к чему угодно.
    Число ({n}, {max}, {id}) подходит только к тексту с цифрой: иначе «Вернуть {n}» подошёл бы к «Вернуть в очеред»."""
    if "plural" in text or not SLOT.search(text) or not re.search(LETTER, SLOT.sub("", text)):
        return None
    out = ""
    for piece in SLOT.split(text):
        if not SLOT.fullmatch(piece):
            out += re.escape(piece)
        elif NUMBER.match(piece):
            out += r"\S*\d\S*"
        else:
            out += ".+"
    return re.compile("^" + out + "$")


def main():
    texts = ui_texts()
    templates = [p for p in map(template, texts) if p]
    guide = read(GUIDE)
    missing = []
    for match in NAME.finditer(guide):
        name = " ".join((match.group(1) or match.group(2)).split())
        if match.group(2) and name.endswith((".", ":")):
            continue
        if not re.search(LETTER, name):
            continue
        if name in texts or any(p.match(name) for p in templates):
            continue
        line = guide.count("\n", 0, match.start()) + 1
        missing.append(f"{GUIDE}:{line}: «{name}»")
    for item in missing:
        print(item)
    print(f"Названий не с экрана: {len(missing)}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
