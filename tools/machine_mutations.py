"""Общий список порч выражений машины (PROC-75): tools/mutations/machine.json.

Одна запись — одна порча машины состояний: что найти в Specification/Workflow_machine/workflow_schema.v1.json и на что
заменить; место — ровно одно. Её применяют двое: модель Quint (tools/check_quint_mutations.mjs) собирается из
испорченной машины, тесты API (tools/check_code_mutations.py) идут на prototype/workflow.js, собранной из неё же
той же функцией, что tools/build_workflow.py.
"""
import json
import os

import build_workflow

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILE = os.path.join(ROOT, "tools", "mutations", "machine.json")
MACHINE = os.path.join(ROOT, "Specification", "Workflow_machine", "workflow_schema.v1.json")


def load():
    """Записи списка: name, what (что ломает), find, replace; model — почему модель порчу не проверяет
    (вне модели, мир модели, эквивалентна, кандидат в инвариант): скрипт модели такую пропускает."""
    with open(FILE, encoding="utf-8") as f:
        return json.load(f)


def workflow_js(find, replace):
    """(сколько мест порчи в машине, prototype/workflow.js из испорченной машины — если место одно)."""
    with open(MACHINE, encoding="utf-8") as f:
        text = f.read()
    n = text.count(find)
    if n != 1:
        return n, None
    data = json.loads(text.replace(find, replace))
    return 1, build_workflow.render(data, "workflow_schema.v1.json", "IM_WORKFLOW", 2)
