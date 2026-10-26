#!/usr/bin/env python3
"""Генератор порч машины (PROC-76): tools/mutations/generated.json — в формате общего списка tools/mutations/machine.json.
Список в репозиторий не кладётся (.gitignore): по машине он всегда один и тот же — собирается перед прогоном.

Ручной список пишут те же люди, что и проверки, и слепые пятна у них общие; генератор портит каждое место машины
однотипно:
  - у перехода убрано одно условие (guards) или один эффект (effects);
  - переход ведёт в другое состояние (to) — в каждое из остальных;
  - в выражении CEL ("expr") заменён один оператор: == и !=, && и ||, < и <=, > и >=, убрано !.
Место — текст машины, ровно одно (контекст вверх до единственности), машина после порчи — правильный JSON.
Порча, совпавшая с ручной из machine.json, не повторяется.

Пометка model (скрипт модели такую пропускает, тесты API — нет) — по машине, а не по списку имён:
  - эффект, который в модели ничего не меняет: только действия мира (журнал, уведомления, карточка на экране) —
    tools/gen_quint.mjs их пропускает;
  - выражение интерфейса: бейджи, пояснения на карточке, подсказки форм, фильтры и группы очереди;
  - эквивалентная — EQUIVALENT ниже, после разбора выживших.

Запуск из корня репозитория: python3 tools/gen_mutations.py
Прогон: node tools/check_quint_mutations.mjs --generated, python3 tools/check_code_mutations.py --generated;
целиком — вручную на GitHub, .github/workflows/mutations-generated.yml.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import machine_mutations  # noqa: E402

ROOT = machine_mutations.ROOT
OUT = os.path.join(ROOT, "tools", "mutations", "generated.json")

# Разделы машины, которые модель не читает: выражения в них — интерфейс
UI_SECTIONS = {"badges", "cardNotes", "queueFilters", "queueGrouping", "display", "navActions"}
UI_PATHS = [re.compile(r"^forms\.[^.]+\.notes\.")]
# Эквивалентные порчи: имя → почему поведение не меняется. Пополняется по разбору выживших
EQUIVALENT = {}

FLIPS = [
    ("le", r"<=", "<"),
    ("lt", r"(?<![<=!-])<(?!=)", "<="),
    ("ge", r">=", ">"),
    ("gt", r"(?<![>=-])>(?!=)", ">="),
    ("eq", r"==", "!="),
    ("ne", r"!=", "=="),
    ("and", r"&&", "||"),
    ("or", r"\|\|", "&&"),
    ("not", r"!(?!=)", ""),
]


class Text:
    """Машина как текст: значения JSON по смещениям — порча меняет текст, а не пересобирает файл"""

    def __init__(self, src):
        self.src = src

    def end(self, i):
        """Конец значения JSON, начинающегося в src[i]"""
        s = self.src
        if s[i] == '"':
            j = i + 1
            while s[j] != '"':
                j += 2 if s[j] == "\\" else 1
            return j + 1
        if s[i] in "[{":
            close = "]" if s[i] == "[" else "}"
            j = i + 1
            while True:
                while s[j] in " \r\n\t,:":
                    j += 1
                if s[j] == close:
                    return j + 1
                j = self.end(j)
        return re.compile(r"[^,\]}\s]+").match(s, i).end()

    def items(self, i):
        """Элементы массива src[i] == '[': [(начало, конец)]"""
        s, out, j = self.src, [], i + 1
        while True:
            while s[j] in " \r\n\t,":
                j += 1
            if s[j] == "]":
                return out
            e = self.end(j)
            out.append((j, e))
            j = e

    def fields(self, i):
        """Поля объекта src[i] == '{': {ключ: начало значения}"""
        s, out, j = self.src, {}, i + 1
        while True:
            while s[j] in " \r\n\t,":
                j += 1
            if s[j] == "}":
                return out
            ke = self.end(j)
            v = ke
            while s[v] in " :\r\n\t":
                v += 1
            out[json.loads(s[j:ke])] = v
            j = self.end(v)

    def strings(self, i, path, key):
        """Все строки с ключом key внутри значения src[i]: (путь, начало, конец). Элемент массива в пути — по id или fn"""
        s = self.src
        if s[i] == "{":
            f = self.fields(i)
            for k, v in f.items():
                if k == key and s[v] == '"':
                    yield path, v, self.end(v)
                else:
                    yield from self.strings(v, path + [k], key)
        elif s[i] == "[":
            for n, (a, _) in enumerate(self.items(i)):
                name = str(n)
                if s[a] == "{":
                    f = self.fields(a)
                    for k in ("id", "fn"):
                        if k in f and s[f[k]] == '"':
                            name = json.loads(s[f[k] : self.end(f[k])])
                            break
                yield from self.strings(a, path + [name], key)

    def edit(self, a, b, new):
        """(find, replace): src[a:b] → new; целые строки и контекст вверх, пока место не единственное"""
        s = self.src
        ls, le = s.rfind("\n", 0, a) + 1, s.find("\n", b) + 1
        while s.count(s[ls:le]) != 1:
            ls = s.rfind("\n", 0, ls - 1) + 1
        return s[ls:le], s[ls:a] + new + s[b:le]

    def drop(self, arr, k):
        """(find, replace): из массива src[arr] убран k-й элемент — вместе с запятой"""
        els = self.items(arr)
        if len(els) == 1:
            return self.edit(arr + 1, els[0][1], "")
        if k < len(els) - 1:
            return self.edit(els[k][0], els[k + 1][0], "")
        return self.edit(els[k - 1][1], els[k][1], "")


def changes_model(fn, effects, seen=()):
    """Меняет ли эффект что-то в модели: не только действия мира (кроме переноса ответов, его модель исполняет)"""

    def ops(lst):
        for op in lst or []:
            if "set" in op or "append" in op or op.get("world") == "shareAnswers":
                return True
            if "call" in op and op["call"] not in seen and changes_model(op["call"], effects, seen + (fn,)):
                return True
            if ops(op.get("then")) or ops(op.get("else")) or ops(op.get("do")):
                return True
        return False

    return ops(effects[fn].get("do"))


def label(it):
    """Имя элемента условия или эффекта: функция и первый аргумент-строка"""
    a = (it.get("args") or [None])[0]
    return it["fn"] + (f"-{a.replace(':', '-')}" if isinstance(a, str) and re.fullmatch(r"[\w.:]+", a) else "")


def generate(src):
    t, data = Text(src), json.loads(src)
    effects = {e["fn"]: e for e in data["registries"]["effects"]}
    top = t.fields(0)
    out = []

    def add(name, what, fr, model=None):
        n, k = name, 2
        while any(m["name"] == n for m in out):
            n, k = f"{name}-{k}", k + 1
        m = {"name": n, "what": what, "find": fr[0], "replace": fr[1]}
        if EQUIVALENT.get(n):
            m["model"] = "эквивалентна: " + EQUIVALENT[n]
        elif model:
            m["model"] = model
        out.append(m)

    states = [s["id"] for s in data["states"]]
    for (ta, _), tr in zip(t.items(top["transitions"]), data["transitions"]):
        f, tid = t.fields(ta), tr["id"]
        for kind, word in (("guards", "условие"), ("effects", "эффект")):
            if kind not in f or src[f[kind]] != "[":
                continue
            for k, it in enumerate(tr[kind]):
                model = None
                if kind == "effects" and not changes_model(it["fn"], effects):
                    model = "вне модели: эффект в модели ничего не меняет — только мир (журнал, уведомления, карточка на экране) или пустой"
                add(f"gen-{tid}-no-{kind[:-1]}-{label(it)}", f"«{tid}» без {'условия' if kind == 'guards' else 'эффекта'} {it['fn']}{' ' + json.dumps(it.get('args'), ensure_ascii=False) if it.get('args') else ''}", t.drop(f[kind], k), model)
        if tr["to"] and tr["from"]:
            for st in states:
                if st != tr["to"]:
                    add(f"gen-{tid}-to-{st}", f"«{tid}» ведёт в {st}, а не в {tr['to']}", t.edit(f["to"], t.end(f["to"]), json.dumps(st)))

    for path, a, b in t.strings(0, [], "expr"):
        p = ".".join(path)
        ui = path[0] in UI_SECTIONS or any(r.match(p + ".") for r in UI_PATHS)
        s = src[a:b]
        for op, pat, rep in FLIPS:
            for n, m in enumerate(re.finditer(pat, s)):
                add(f"gen-cel-{p}-{op}{n + 1}", f"CEL {p}: {m.group(0)} → {rep or 'убрано'} ({n + 1}-е)", t.edit(a + m.start(), a + m.end(), rep), "вне модели: интерфейс (бейджи, пояснения, подсказки форм, очередь)" if ui else None)

    # Совпала с ручной — не повторять
    hand = {src.replace(m["find"], m["replace"], 1) for m in machine_mutations.load() if src.count(m["find"]) == 1}
    out = [m for m in out if src.replace(m["find"], m["replace"], 1) not in hand]
    for m in out:
        bad = src.count(m["find"]) != 1 or src.replace(m["find"], m["replace"], 1) == src
        try:
            json.loads(src.replace(m["find"], m["replace"], 1))
        except ValueError:
            bad = True
        if bad:
            raise SystemExit(f"Порча {m['name']}: место не одно, пустая замена или машина после порчи — не JSON")
    return out


def main():
    with open(machine_mutations.MACHINE, encoding="utf-8") as f:
        muts = generate(f.read())
    text = json.dumps(muts, ensure_ascii=False, indent=1) + "\n"
    skip = sum(1 for m in muts if m.get("model"))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"Собран tools/mutations/generated.json: {len(muts)} порч, модель пропускает {skip}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
