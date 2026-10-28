#!/usr/bin/env python3
"""Перевод контракта openapi.json (OpenAPI 3.1) в OpenAPI 3.0.3.

Генератор сервера МИ (oapi-codegen на kin-openapi 0.117) 3.1 не понимает, поэтому для него
собирается копия: Specification/Workflow_machine/openapi.v30.json. Исходник остаётся в 3.1.

Что переводится (только внутри объектов Schema):
  type: [X, "null"]                       -> type: X, nullable: true
  anyOf/oneOf с {"type": "null"}          -> вариант без null (или остальные варианты) + nullable: true
  examples: [..]                          -> example: первое значение
  const, if / then / else                 -> убираются (проверку делает машина и сервер, не схема)
  $ref рядом с другими полями             -> allOf: [{$ref}] плюс остальные поля
"""
import copy

SCHEMA_MAP = ("properties",)                  # значения — схемы
SCHEMA_ONE = ("items", "additionalProperties", "not")
SCHEMA_LIST = ("allOf", "anyOf", "oneOf")
DROPPED = ("const", "if", "then", "else")


def _is_null(v):
    return isinstance(v, dict) and v == {"type": "null"}


def _schema(s, path, found):
    """Переводит схему на месте. found — список путей конструкций 3.1, найденных до перевода."""
    if not isinstance(s, dict):
        return s
    for key in DROPPED:
        if key in s:
            found.append(f"{path}/{key}")
            del s[key]
    t = s.get("type")
    if isinstance(t, list):
        found.append(f"{path}/type")
        rest = [x for x in t if x != "null"]
        if len(rest) != len(t):
            s["nullable"] = True
        if len(rest) == 1:
            s["type"] = rest[0]
        else:
            del s["type"]
            s["anyOf"] = [{"type": x} for x in rest]
    if isinstance(s.get("examples"), list):
        found.append(f"{path}/examples")
        ex = s.pop("examples")
        if ex:
            s["example"] = ex[0]
    for key in ("anyOf", "oneOf"):
        v = s.get(key)
        if isinstance(v, list) and any(_is_null(x) for x in v):
            found.append(f"{path}/{key}")
            rest = [x for x in v if not _is_null(x)]
            s["nullable"] = True
            if len(rest) == 1:
                del s[key]
                variant = rest[0]
                if "$ref" in variant and len(variant) == 1:
                    s["allOf"] = s.get("allOf", []) + [variant]
                else:
                    for k, val in variant.items():
                        s.setdefault(k, val)
            else:
                s[key] = rest
    if "$ref" in s and len(s) > 1:
        found.append(f"{path}/$ref")
        ref = s.pop("$ref")
        s["allOf"] = [{"$ref": ref}] + s.get("allOf", [])
    # вложенные схемы
    for key in SCHEMA_MAP:
        if isinstance(s.get(key), dict):
            for name, sub in s[key].items():
                _schema(sub, f"{path}/{key}/{name}", found)
    for key in SCHEMA_ONE:
        if isinstance(s.get(key), dict):
            _schema(s[key], f"{path}/{key}", found)
    for key in SCHEMA_LIST:
        if isinstance(s.get(key), list):
            for i, sub in enumerate(s[key]):
                _schema(sub, f"{path}/{key}/{i}", found)
    return s


def _walk(node, path, found, in_components_schemas=False):
    """Обход всего документа: схемы лежат под components.schemas и под ключом schema."""
    if isinstance(node, dict):
        for key, val in node.items():
            sub = f"{path}/{key}"
            if key == "schema" and isinstance(val, dict):
                _schema(val, sub, found)
            elif key == "schemas" and path.endswith("/components") and isinstance(val, dict):
                for name, sch in val.items():
                    _schema(sch, f"{sub}/{name}", found)
            else:
                _walk(val, sub, found)
    elif isinstance(node, list):
        for i, val in enumerate(node):
            _walk(val, f"{path}/{i}", found)


def convert(spec):
    """Новая копия контракта в OpenAPI 3.0.3; исходник не меняется."""
    out = copy.deepcopy(spec)
    _walk(out, "", [])
    out["openapi"] = "3.0.3"
    return out


def leftovers(spec):
    """Пути конструкций, которых нет в 3.0 (у готовой копии список пуст)."""
    found = []
    _walk(copy.deepcopy(spec), "", found)
    return found
