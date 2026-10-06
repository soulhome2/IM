"""Настройки администратора словами: Specification/State_machine/SETTINGS.md (RULE-44).

Собирается из раздела adminSettings машины workflow.v4.json вместе с текущими значениями.
Вызывается из tools/build_workflow.py; руками SETTINGS.md не правится.
"""


def at(w, path):
    cur = w
    for seg in path.split("."):
        if isinstance(cur, list):
            cur = next((x for x in cur if isinstance(x, dict) and x.get("id") == seg), None)
        elif isinstance(cur, dict):
            cur = cur.get(seg)
        else:
            return None
    return cur


LABELS = {}


def word(key):
    """Машинное значение — подписью из adminSettings.valueLabels (BUG-26)."""
    return LABELS.get(key, key)


def duration(sec):
    if sec is None:
        return "—"
    if sec % 3600 == 0 and sec >= 3600:
        return f"{sec // 3600}\u00a0ч"
    if sec % 60 == 0 and sec >= 60:
        return f"{sec // 60}\u00a0мин"
    return f"{sec}\u00a0с"


def value(v, key="", seconds=False):
    """Значение настройки для человека: длительности — в минутах и часах, списки — по подписям."""
    sec = seconds or key.endswith("Sec")
    if v is None:
        return "—"
    if isinstance(v, bool):
        return "да" if v else "нет"
    if isinstance(v, (int, float)):
        if key.endswith("Min"):
            return duration(int(v) * 60)
        if key.endswith("Minutes"):
            return duration(int(v) * 60)
        return duration(int(v)) if sec else str(v)
    if isinstance(v, str):
        return f"`{v}`" if ":" in v and " " not in v else v
    if isinstance(v, dict):
        return "; ".join(f"{word(k)}: {value(x, k, sec)}" for k, x in v.items() if not k.startswith("$")) or "нет"
    if isinstance(v, list):
        if not v:
            return "нет"
        return "; ".join(element(x, sec) for x in v)
    return str(v)


def element(x, sec):
    if not isinstance(x, dict):
        return value(x, seconds=sec)
    if "key" in x and "label" in x:
        return f"`{x['key']}` — {x['label']}"
    if "level" in x:
        return f"уровень {x['level']}: `{x.get('targetRef')}`, реакция {duration(x.get('reactionSec'))}"
    head = x.get("label") or x.get("id") or ""
    extra = [value(v, k, sec) for k, v in x.items() if k.endswith(("Sec", "Minutes")) and v is not None]
    if "sec" in x:
        cond = ", ".join(f"{word(k)} = {word(str(v))}" for k, v in x.items() if k != "sec")
        return f"{cond}: {duration(x['sec'])}"
    return head + (f" ({', '.join(extra)})" if extra else "")


def render(w):
    a = w["adminSettings"]
    LABELS.clear()
    LABELS.update({k: v for k, v in a.get("valueLabels", {}).items() if not k.startswith("$")})
    out = [
        "# Настройки администратора",
        "",
        "Собрано из раздела `adminSettings` машины [workflow.v4.json](workflow.v4.json) скриптом `tools/build_workflow.py` — руками не править. "
        "Что меняет администратор с правом `incident:schema:admin`, по вкладкам будущей админки, и какое значение сейчас (RULE-44). "
        "Переходы, состояния, формы и бейджи — модель, а не настройки: их здесь нет. "
        "Тот же перечень показывает прототип: меню пользователя → «Настройки администратора». "
        "`check_machine.py` проверяет, что каждая настройка схемы есть здесь или в списке «Не настройки» в конце.",
        "",
    ]
    for tab in a["tabs"]:
        out += [f"## {tab['label']}", "", f"Правила: {tab['rules']}.", ""]
        if "items" in tab:
            out += ["| Настройка | Что задаёт | Сейчас | В машине |", "|---|---|---|---|"]
            for item in tab["items"]:
                key = item["path"].split(".")[-1]
                seconds = item["path"].startswith("timers.")
                current = at(w, item["path"])
                values = item.get("values", {})
                shown = values[current] if isinstance(current, str) and current in values else value(current, key, seconds)
                out.append(f"| {item['label']} | {item['what']} | {shown} | `{item['path']}` |")
        else:
            src = f"читается запросом `{tab['source']}`" if tab.get("source") else "запроса в контракте пока нет"
            out += [f"{tab['what']}. Данные МИ, не схема: {src}."]
        out.append("")
    out += ["## Не настройки", "", "Ключи разделов-настроек машины, которые администратор не меняет, и почему.", "", "| В машине | Почему не настройка |", "|---|---|"]
    out += [f"| `{n['path']}` | {n['why']} |" for n in a["notSettings"]]
    return "\n".join(out) + "\n"
