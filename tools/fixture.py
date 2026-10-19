"""Эталонный набор тестового стенда целиком: Specification/Workflow_machine/fixtures/demo.json и сценарии
fixtures/scenarios/<сценарий>.v<версия>.json — по файлу на версию сценария, в формате машины сценариев (DATA-09).

Набор для POST /test/reset и патчей стенда — один объект: строки сценариев (scenarios.rows — как на сервере:
guid, version, name, script) собираются из файлов, guid, version и name — из scenario.id, version и name. Так набор
читают сборка (build_workflow.py), проверки (check_machine.py, check_scenarios.py, check_guide.py) и бэкенд.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "Specification", "Workflow_machine", "fixtures")
SCENARIOS = os.path.join(FIXTURES, "scenarios")


def scenario_files():
    """(имя файла, сценарий) — по имени файла."""
    for name in sorted(os.listdir(SCENARIOS)):
        if name.endswith(".json"):
            with open(os.path.join(SCENARIOS, name), encoding="utf-8") as f:
                yield name, json.load(f)


def row(script):
    meta = script["scenario"]
    return {"guid": meta["id"], "version": meta["version"], "name": meta["name"], "script": script}


def load():
    with open(os.path.join(FIXTURES, "demo.json"), encoding="utf-8") as f:
        fx = json.load(f)
    fx["scenarios"]["rows"] = [row(script) for _, script in scenario_files()]
    return fx
