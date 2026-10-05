#!/usr/bin/env python3
"""Мутации кода: насколько тесты ловят ошибки в исполнителе, сервере и интерфейсе.

В копии репозитория по одному портится место в коде (engine.js, server.js, app.js) —
так, как мог бы ошибиться разработчик: строгое сравнение вместо нестрогого, забытая
проверка, таймер без остатка. Затем запускаются тесты API (tests/api.html), а для
интерфейса — самопроверка прототипа. Каждая порча должна уронить тесты (KILLED).
Если тесты прошли (SURVIVED) — в них дыра: такую ошибку никто бы не заметил.

Отличие от tools/check_mutations.py: там меняется машина состояний и проверяется,
что прототип ведёт себя по-новому (правила только в машине). Здесь меняется код
и проверяется, что тесты замечают поломку.

Запуск из корня репозитория:
  python3 tools/check_code_mutations.py            — все мутации, около двух минут
  python3 tools/check_code_mutations.py hold-limit — только названные
Код выхода 1, если хоть одна мутация выжила.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (имя, файл, что заменить, на что, чем проверять: api — тесты API, ui — самопроверка)
MUTATIONS = [
    ("active-limit", "engine.js", "if (u.size + extra < W.limits.maxActive) return null;", "if (u.size + extra <= W.limits.maxActive) return null;", "api"),
    ("hold-limit", "engine.js", "units(\"on_hold\", ev).size < W.limits.maxOnHold ?", "units(\"on_hold\", ev).size <= W.limits.maxOnHold ?", "api"),
    ("group-is-one-unit", "engine.js", ".map((e) => e.groupId || e.id)", ".map((e) => e.id)", "api"),
    ("self-without-groups", "engine.js", "(id === ME || (isGroup(id) && ctx.memberOf(id, ME)))", "(id === ME)", "api"),
    ("addressee-owner-only", "engine.js", "const addressee = (ev) => ev.owner || ev.assignmentGroup || null;", "const addressee = (ev) => ev.owner || null;", "api"),
    ("pause-loses-remaining", "engine.js", "if (ev[f.due]) ev[f.left] = Math.max(0, ev[f.due] - now());", "if (ev[f.due]) ev[f.left] = null;", "api"),
    ("resume-restarts", "engine.js", "const left = ev[f.left] != null ? ev[f.left] : timerSec(ev, id) * 1000;", "const left = timerSec(ev, id) * 1000;", "api"),
    ("deadline-fires-repeatedly", "engine.js", "return ev.firedTimers[id] !== due;", "return true;", "api"),
    ("if-person-any", "engine.js", "return v && isGroup(v) === (mod[2] === \"ifGroup\") ? v : null;", "return v || null;", "api"),
    ("form-not-validated", "engine.js", "if (required && (v == null || String(v).trim() === \"\")) {", "if (false) {", "api"),
    ("close-result-any-owner", "engine.js", "if (item.ownerOnlyInStates.includes(ev.state) && !isMine(ev)) return;", "", "api"),
    ("close-result-any-surface", "engine.js", "if (surface && item.surfaces && !item.surfaces.includes(surface)) return;", "", "api"),
    ("reopen-window-ignored", "engine.js", "Math.round((now() - (ev.closedAt || 0)) / 60000) <= W.limits.reopenWindowMin", "true", "api"),
    ("breach-no-flag", "engine.js", "        ev.slaBreached = true;\n", "", "api"),
    ("pending-target-as-owner", "engine.js", "if (ev.state === \"pending_acceptance\" && isTarget(ev)) return \"target\";", "", "api"),
    ("scope-always-own", "engine.js", "const key = `${prefix}:${own ? \"own\" : \"any\"}`;", "const key = `${prefix}:own`;", "api"),
    ("break-ignored", "engine.js", "agentReady: () => (ctx.agentState() === \"not_ready\" ? [\"На перерыве доступен только просмотр\"] : null),", "agentReady: () => null,", "api"),
    ("scenario-always-editable", "engine.js", "const canEditScenario = (ev) => Boolean(ev) && !firstFail(ev, W.scenarioEdit.guards);", "const canEditScenario = (ev) => Boolean(ev);", "api"),
    ("filter-ignores-ownership", "engine.js", "if (f.ownership && f.ownership !== ownership(ev)) return false;", "", "api"),
    ("badge-ignores-addressee", "engine.js", "if (r.when && r.when.addressee && r.when.addressee !== (isGroup(addressee(ev)) ? \"group\" : \"person\")) return false;", "", "api"),
    ("level-not-incremented", "engine.js", "if (field === \"escalation_level\") ev.escalationLevel += 1;", "if (field === \"escalation_level\") ev.escalationLevel += 0;", "api"),
    ("version-conflict-ignored", "server.js", "if (body && body.expectedState && body.expectedState !== ev.state) {", "if (false) {", "api"),
    ("version-not-bumped", "server.js", "const touch = (list) => list.forEach((e) => (e.version += 1));", "const touch = () => {};", "api"),
    ("same-type-any-type", "server.js", "list = anchor ? pool.filter((e) => groupable(e) && e.typeId === anchor.typeId) : [];", "list = anchor ? pool.filter((e) => groupable(e)) : [];", "api"),
    ("device-type-filter-ignored", "server.js", "if (q.deviceTypeId && q.deviceTypeId !== \"all\") {", "if (false) {", "api"),
    ("focus-page-missing", "server.js", "const focusPage = idx === -1 ? null : Math.floor(idx / size) + 1;", "const focusPage = null;", "api"),
    ("answers-by-anyone", "server.js", "if (!engine.canEditScenario(ev)) return problem(403, \"PERMISSION_DENIED\", [\"Карточка открыта на просмотр\"]);\n          const stale", "const stale", "api"),
    ("if-match-ignored", "server.js", "const stale = versionProblem(ev, headers);\n          if (stale) return stale;\n          if (body", "if (body", "api"),
    ("answers-if-match-ignored", "server.js", "const stale = versionProblem(ev, headers);\n          if (stale) return stale;\n          Object.assign", "Object.assign", "api"),
    ("if-match-optional", "server.js", "if (!sent) return problem(428,", "if (!sent) return null;\n      if (false) return problem(428,", "api"),
    ("etag-missing", "server.js", "body: card(ev), headers: { ETag: etag(ev) } }", "body: card(ev) }", "api"),
    ("targets-include-self", "server.js", "let list = targets().filter((o) => !engine.isSelf(o.id));", "let list = targets();", "api"),
    ("limit-code-generic", "server.js", "withinActiveLimit: \"LIMIT_EXCEEDED\",", "withinActiveLimit: \"GUARD_FAILED\",", "api"),
    ("group-size-zero", "server.js", "groupSize: ev.groupId ? groupMates(ev).length : 0,", "groupSize: 0,", "api"),
    ("hold-timer-hidden", "server.js", "holdTimer: holdTimerState(ev),", "holdTimer: null,", "api"),
    ("colleague-acts-as-operator", "server.js", "          Object.assign({}, engineCtx, {\n            me: id,", "          Object.assign({}, engineCtx, {\n            me: ME,", "api"),
    ("operator-never-idle", "server.js", "{ me: ME, idleSec: () => (lastHeartbeat == null ? 0 : (now() - lastHeartbeat) / 1000) }", "{ me: ME, idleSec: () => 0 }", "api"),
    ("heartbeat-not-counted", "server.js", "          lastHeartbeat = now();\n", "", "api"),
    ("colleague-never-idle", "server.js", "idleSec: () => (colleagueIdleSince[id] == null ? 0 : (now() - colleagueIdleSince[id]) / 1000),", "idleSec: () => 0,", "api"),
    ("preferences-not-from-fixture", "server.js", "preferences: JSON.parse(JSON.stringify(fixture.operatorPreferences || {})),", "preferences: {},", "api"),
    ("media-no-positions", "server.js", ".map((id) => ({ deviceGuid: id, x: deviceSpec(id).position.x, y: deviceSpec(id).position.y, isSource: id === src })),", ".map((id) => ({ deviceGuid: id, x: 0, y: 0, isSource: id === src })),", "api"),
    ("media-plan-by-site-only", "server.js", "const placed = ids.map((id) => deviceSpec(id).position).find(Boolean);", "const placed = null;", "api"),
    ("ui-map-ignores-markers", "app.js", "const markers = ordered.map((m) => deviceMarker(m, { source: m.deviceGuid === source, active: m.deviceGuid === state.activeCam })).join(\"\");", "const markers = \"\";", "ui"),
    ("number-is-guid", "server.js", "        number: ev.number,", "        number: ev.id,", "api"),
    ("event-type-guid-is-id", "server.js", "if (q.eventTypeGuid && q.eventTypeGuid !== \"all\" && e.typeGuid !== q.eventTypeGuid) return false;", "if (q.eventTypeGuid && q.eventTypeGuid !== \"all\" && e.typeId !== q.eventTypeGuid) return false;", "api"),
    ("setting-is-ignored", "engine.js", "settingIs: (ev, [key, expected]) => (setting(key) === expected ? null : [\"Другое значение настройки\"]),", "settingIs: () => null,", "api"),
    ("owner-group-ignored", "engine.js", "ownerHasDutyGroup: (ev, [expected]) => (Boolean(ev.owner && ctx.dutyGroupOf(ev.owner)) === expected ? null : [\"Дежурная группа владельца не подходит\"]),", "ownerHasDutyGroup: () => null,", "api"),
    ("offline-without-scheduler", "server.js", "            session.agentState = \"offline\";\n            session.reasonId = null;\n            const fired = runScheduler();", "            session.agentState = \"offline\";\n            session.reasonId = null;\n            const fired = [];", "api"),
    ("visibility-ignored", "server.js", "    let list = events.filter(canSee);", "    let list = events;", "api"),
    ("card-ignores-access", "server.js", "      return ev && canSee(ev) ? ev : null;", "      return ev;", "api"),
    ("stream-leaks-hidden", "server.js", "      if (ev && !canSee(ev)) return;\n", "", "api"),
    ("tree-ignores-access", "server.js", ".filter((c) => c.isDevice && myDevices.has(c.id))", ".filter((c) => c.isDevice)", "api"),
    ("counters-ignore-access", "server.js", "events.filter((e) => canSee(e) && engine.inQueueFilter(e, f.id)).length", "events.filter((e) => engine.inQueueFilter(e, f.id)).length", "api"),
    ("stream-id-repeats", "server.js", "id: String(++seq),", "id: String(seq),", "api"),
    ("ui-required-from-ignored", "app.js", "if (!field.requiredFrom) return Boolean(field.required);", "return Boolean(field.required);", "ui"),
    ("ui-hotkeys-under-modal", "app.js", "if (modalOpen && !hotkey.worksInModal) return;", "", "ui"),
    ("ui-disabled-not-explained", "app.js", "if (btn.getAttribute(\"aria-disabled\") !== \"true\") return false;\n    toast(btn.title || t(\"Действие недоступно\"));", "if (btn.getAttribute(\"aria-disabled\") !== \"true\") return false;", "ui"),
    ("ui-placeholder-ignored", "app.js", "const fallback = field.placeholder ? (enabled.length === 1 ? enabled[0].id : \"\") : enabled[0] && enabled[0].id;", "const fallback = enabled[0] && enabled[0].id;", "ui"),
    ("ui-no-if-match", "app.js", "const ifMatch = (ev) => ({ \"If-Match\": `\"${ev.version}\"` });", "const ifMatch = () => ({});", "ui"),
    ("ui-selection-not-checked", "app.js", "return sel && sel.enabled ? a : { ...a, disabled: true, hint: why };", "return a;", "ui"),
]


def chrome(url, profile, budget):
    out = subprocess.run(
        [
            "google-chrome",
            "--headless=new",
            "--disable-gpu",
            "--no-sandbox",
            "--no-first-run",
            f"--user-data-dir={profile}",
            f"--virtual-time-budget={budget}",
            "--dump-dom",
            url,
        ],
        capture_output=True,
        text=True,
        timeout=240,
    )
    return out.stdout


def run_tests(site, kind, profile):
    shutil.rmtree(profile, ignore_errors=True)
    if kind == "api":
        page = chrome(f"file://{site}/tests/api.html", profile, 120000)
        passed = 'data-apitest="pass"' in page
        log = re.search(r'<pre id="apitest-log">(.*?)</pre>', page, re.S)
    else:
        page = chrome(f"file://{site}/prototype/index.html?selftest", profile, 30000)
        passed = 'data-selftest="pass"' in page
        log = re.search(r'<pre id="selftest-log"[^>]*>(.*?)</pre>', page, re.S)
    fails = [line for line in (log.group(1).splitlines() if log else []) if line.startswith("FAIL")]
    return passed, fails, bool(log)


def main():
    wanted = [a for a in sys.argv[1:] if not a.startswith("-")]
    work = tempfile.mkdtemp(prefix="im-code-mut-")
    profile = os.path.join(work, "profile")
    site = os.path.join(work, "site")
    survived = 0
    try:
        for name, file, old, new, kind in MUTATIONS:
            if wanted and name not in wanted:
                continue
            shutil.rmtree(site, ignore_errors=True)
            for sub in ("prototype", "tests", "theme"):
                shutil.copytree(os.path.join(ROOT, sub), os.path.join(site, sub))
            path = os.path.join(site, "prototype", file)
            with open(path, encoding="utf-8") as f:
                code = f.read()
            if code.count(old) != 1:
                print(f"STALE {name}: в {file} не найдено место порчи — обновите мутацию")
                survived += 1
                continue
            with open(path, "w", encoding="utf-8") as f:
                f.write(code.replace(old, new))
            passed, fails, ran = run_tests(site, kind, profile)
            if not ran:
                print(f"KILLED {name} [{kind}] — тесты не запустились (ошибка JS)")
            elif passed:
                survived += 1
                print(f"SURVIVED {name} [{kind}] — тесты прошли с испорченным {file}")
            else:
                print(f"KILLED {name} [{kind}] — {fails[0][:110] if fails else 'тесты упали'}")
        # Контроль: без порчи тесты проходят
        if not wanted:
            shutil.rmtree(site, ignore_errors=True)
            for sub in ("prototype", "tests", "theme"):
                shutil.copytree(os.path.join(ROOT, sub), os.path.join(site, sub))
            for kind in ("api", "ui"):
                passed, fails, _ = run_tests(site, kind, profile)
                if not passed:
                    survived += 1
                    print(f"BASE [{kind}] — без порчи тесты не проходят: {fails[:2]}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print(f"Выживших мутаций кода: {survived}")
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
