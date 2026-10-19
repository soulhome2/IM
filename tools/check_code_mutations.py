#!/usr/bin/env python3
"""Мутации кода: насколько тесты ловят ошибки в исполнителе, сервере и интерфейсе.

В копии репозитория по одному портится место в коде (engine.js, server.js, scenario.js, app.js) —
так, как мог бы ошибиться разработчик: строгое сравнение вместо нестрогого, забытая
проверка, таймер без остатка. Затем запускаются тесты API (tests/api.html), а для
интерфейса — самопроверка прототипа, для исполнителя сценариев — его тесты (tests/scenario.html).
Каждая порча должна уронить тесты (KILLED).
Если тесты прошли (SURVIVED) — в них дыра: такую ошибку никто бы не заметил.

Отличие от tools/check_mutations.py: там меняется машина состояний и проверяется,
что прототип ведёт себя по-новому (правила только в машине). Здесь меняется код
и проверяется, что тесты замечают поломку.

Быстро (PROC-17): чтобы поймать порчу, хватает одного упавшего теста. Поэтому тесты идут до
первого падения (failfast). Мутации идут одновременно в несколько потоков — у каждого своя копия
прототипа и свой Chrome (tools/parallel.py). Вердикт тот же: выжившая мутация всегда проходит
полный набор тестов.

Запуск из корня репозитория:
  python3 tools/check_code_mutations.py            — все мутации; на 8 ядрах — несколько минут
  python3 tools/check_code_mutations.py hold-limit — только названные
  python3 tools/check_code_mutations.py --full     — без failfast: полные прогоны
  --jobs=N — потоков (по умолчанию три четверти ядер), --shard=K/M — K-я из M частей (так делит CI)
Код выхода 1, если хоть одна мутация выжила.
"""
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parallel  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (имя, файл, что заменить, на что, чем проверять: api — тесты API, ui — самопроверка, scenario — тесты исполнителя сценариев)
MUTATIONS = [
    ("active-limit", "engine.js", "if (u.size < W.limits.maxActive) return null;", "if (u.size <= W.limits.maxActive) return null;", "api"),
    ("hold-limit", "engine.js", "units(\"on_hold\", ev).size < W.limits.maxOnHold ?", "units(\"on_hold\", ev).size <= W.limits.maxOnHold ?", "api"),
    ("self-without-groups", "engine.js", "(id === ME || (isGroup(id) && ctx.memberOf(id, ME)))", "(id === ME)", "api"),
    ("addressee-owner-only", "engine.js", "const addressee = (ev) => ev.owner || ev.assignmentGroup || null;", "const addressee = (ev) => ev.owner || null;", "api"),
    ("pause-loses-remaining", "engine.js", "if (ev[f.due]) ev[f.left] = Math.max(0, ev[f.due] - now());", "if (ev[f.due]) ev[f.left] = null;", "api"),
    ("resume-restarts", "engine.js", "const left = ev[f.left] != null ? ev[f.left] : timerSec(ev, id) * 1000;", "const left = timerSec(ev, id) * 1000;", "api"),
    ("deadline-fires-repeatedly", "engine.js", "return ev.firedTimers[id] !== due;", "return true;", "api"),
    ("if-person-any", "engine.js", "return v && isGroup(v) === (mod[2] === \"ifGroup\") ? v : null;", "return v || null;", "api"),
    ("form-not-validated", "engine.js", "if (required && (v == null || String(v).trim() === \"\")) {", "if (false) {", "api"),
    ("close-result-any-owner", "engine.js", "if (item.ownerOnlyInStates.includes(ev.state) && !isMine(ev)) return;", "", "api"),
    ("close-result-any-surface", "engine.js", "if (surface && item.surfaces && !item.surfaces.includes(surface)) return;", "", "api"),
    ("reopen-window-ignored", "engine.js", "now() - (ev.closedAt || 0) <= W.limits.reopenWindowMin * 60000", "true", "api"),
    ("breach-no-flag", "engine.js", "breachOwnerOfLinked(ev) : addressee(ev) });\n        ev.slaBreached = true;\n", "breachOwnerOfLinked(ev) : addressee(ev) });\n", "api"),
    ("pending-target-as-owner", "engine.js", "if (ev.state === \"pending_acceptance\" && isTarget(ev)) return \"target\";", "", "api"),
    ("scope-always-own", "engine.js", "const key = `${prefix}:${own ? \"own\" : \"any\"}`;", "const key = `${prefix}:own`;", "api"),
    ("break-ignored", "engine.js", "return st && st.readOnly ? [st.readOnlyReasonKey] : null;", "return null;", "api"),
    ("scenario-always-editable", "engine.js", "const canEditScenario = (ev) => Boolean(ev) && !firstFail(ev, W.scenarioEdit.guards);", "const canEditScenario = (ev) => Boolean(ev);", "api"),
    ("filter-ignores-ownership", "engine.js", "if (f.ownership && f.ownership !== ownership(ev)) return false;", "", "api"),
    ("badge-ignores-addressee", "engine.js", "if (r.when && r.when.addressee && r.when.addressee !== (isGroup(addressee(ev)) ? \"group\" : \"person\")) return false;", "", "api"),
    ("count-not-incremented", "engine.js", "ev[key] = (ev[key] || 0) + 1;", "ev[key] = ev[key] || 0;", "api"),
    ("version-conflict-ignored", "server.js", "if (body && body.expectedState && body.expectedState !== ev.state) {", "if (false) {", "api"),
    ("version-not-bumped", "server.js", "const touch = (list) => list.forEach((e) => (e.version += 1));", "const touch = () => {};", "api"),
    ("device-type-filter-ignored", "server.js", "if (q.deviceTypeId && q.deviceTypeId !== \"all\") {", "if (false) {", "api"),
    ("focus-page-missing", "server.js", "      const focusPage = idx === -1 ? null : Math.floor(idx / size) + 1;\n      const found", "      const focusPage = null;\n      const found", "api"),
    ("answers-by-anyone", "server.js", "if (!engine.canEditScenario(ev)) return problem(403, \"PERMISSION_DENIED\", [\"workflow.error.read_only\"]);\n          const stale", "const stale", "api"),
    ("if-match-ignored", "server.js", "const stale = versionProblem(ev, headers);\n          if (stale) return stale;\n          if (body", "if (body", "api"),
    # Машина сценариев и стык (§14.5, ARCH-06): исполнитель scenario.js и его вызовы в сервере
    ("answer-off-path-accepted", "scenario.js", 'if (i < 0) return { ok: false, error: "not_on_path" };\n', "", "api"),
    ("answer-editable-ignored", "scenario.js", 'if (!isCurrent && step.revisitable === false) return { ok: false, error: "not_editable" };\n', "", "api"),
    ("branch-answers-kept", "scenario.js", "dropped.forEach((id) => delete r.state[id]);", "", "api"),
    ("closing-without-finish", "scenario.js", 'setId === "closing" && Boolean(result.completedAt)', 'setId === "closing"', "api"),
    ("progress-from-start", "scenario.js", "const rest = remaining(script, result.currentStepId);", "const rest = remaining(script, script.initialStepId);", "api"),
    ("share-no-settle", "scenario.js", "while (!r.completedAt && moved.includes(r.currentStepId)", "while (false && moved.includes(r.currentStepId)", "api"),
    ("required-skip-allowed", "scenario.js", 'if (o.skip && !canSkip(step)) return { ok: false, error: "required" };\n', "", "api"),
    ("macro-ignores-run-macro", "server.js", '      if (!actorEngine.availability("run_macro", ev).ok) return;\n', "", "api"),
    ("new-incident-oldest-version", "server.js", ".sort((a, b) => b.version - a.version)[0]", ".sort((a, b) => a.version - b.version)[0]", "api"),
    ("cursor-off-path", "server.js", "if (!body || !pathOf(ev).includes(body.stepId))", "if (!body)", "api"),
    ("finish-no-close-form", "app.js", '    if (!wasDone && runDone(after) && canDo("close", after)) trigger("close", after, "card");\n', "", "ui"),
    ("ahead-with-current", "scenario.js", "for (let x = id; x !== from; x = prev.get(x)) out.unshift(x);", "for (let x = id; x !== null; x = prev.get(x)) out.unshift(x);", "api"),
    ("ahead-not-shown", "app.js", "  const aheadOf = (ev) => (scenarioOf(ev) ? scenarioOf(ev).ahead || [] : []);", "  const aheadOf = () => [];", "ui"),
    ("datetime-iso-on-path", "app.js", '    if (step.type === "Datetime") return fmtWhen(entry.value);\n', "", "ui"),
    # Формат редактора продукта (Scenario_machine/CHANGELOG): финальный шаг, условие своего шага, операторы, Select, умолчания
    ("finish-step-reads-transitions", "scenario.js", "    if (step.finish) return null;\n", "", "scenario"),
    ("condition-context-lost", "scenario.js", 'if (step.type === "RadioButton") return { value: value == null ? null : value };', 'if (step.type === "RadioButton") return {};', "scenario"),
    ("in-standard", "scenario.js", 'logic.add_operation("in", (needle, haystack) => {', 'logic.add_operation("in_off", (needle, haystack) => {', "scenario"),
    ("eq-standard", "scenario.js", 'logic.add_operation("==", (a, b) => {', 'logic.add_operation("==_off", (a, b) => {', "scenario"),
    ("empty-condition-fires", "scenario.js", 'if (!condition || typeof condition !== "object" || !Object.keys(condition).length) return false;', 'if (!condition || typeof condition !== "object") return false;', "scenario"),
    ("rules-on-any-type", "scenario.js", "const rules = WITH_RULES.includes(step.type) ? step.transitions.rules || [] : [];\n    const context", "const rules = step.transitions.rules || [];\n    const context", "scenario"),
    ("select-required-ignored", "scenario.js", 'return v.required && v.lists.some((l) => !(value[l.id] || []).length) ? "required" : null;', "return null;", "scenario"),
    ("macro-effect-ignored", "server.js", 'res.effects.filter((e) => e.type === "macro")', 'res.effects.filter((e) => e.type === "callMacro")', "api"),
    ("ui-default-ignored", "app.js", "    return defaultOf(step);\n", "    return null;\n", "ui"),
    ("draft-kept-on-leave", "app.js", "    state.drafts.delete(draftKey(ev, path[cursorOf(ev)]));\n", "", "ui"),
    ("required-steps-code-lost", "server.js", 'const code = REASON_CODE[check.why && check.why[0]] || GUARD_CODE[check.guard] || "GUARD_FAILED";', 'const code = GUARD_CODE[check.guard] || "GUARD_FAILED";', "api"),
    ("view-not-advanced", "server.js", "ev.viewStepId = path[Math.min(path.lastIndexOf(body.stepId) + 1, path.length - 1)];", "ev.viewStepId = body.stepId;", "api"),
    ("answers-if-match-ignored", "server.js", "const stale = versionProblem(ev, headers);\n          if (stale) return stale;\n          const res = answerStep", "const res = answerStep", "api"),
    ("if-match-optional", "server.js", "if (!sent) return problem(428,", "if (!sent) return null;\n      if (false) return problem(428,", "api"),
    ("etag-missing", "server.js", "{ status: 200, body: card(ev), headers: { ETag: etag(ev) } }", "{ status: 200, body: card(ev) }", "api"),
    ("targets-include-self", "server.js", "let list = targets().filter((o) => !engine.isSelf(o.id));", "let list = targets();", "api"),
    ("limit-code-generic", "server.js", "withinActiveLimit: \"LIMIT_EXCEEDED\",", "withinActiveLimit: \"GUARD_FAILED\",", "api"),
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
    ("event-type-guid-is-id", "server.js", "!String(q.eventTypeGuid).split(\",\").includes(e.typeGuid)", "!String(q.eventTypeGuid).split(\",\").includes(e.typeId)", "api"),
    ("setting-is-ignored", "engine.js", "settingIs: (ev, [key, expected]) => (setting(key) === expected ? null : [\"workflow.guard.setting_other\"]),", "settingIs: () => null,", "api"),
    ("owner-group-ignored", "engine.js", "ownerHasDutyGroup: (ev, [expected]) => (Boolean(ev.owner && ctx.dutyGroupOf(ev.owner)) === expected ? null : [\"workflow.guard.owner_duty_group\"]),", "ownerHasDutyGroup: () => null,", "api"),
    ("offline-without-scheduler", "server.js", "            session.agentState = \"offline\";\n            session.reasonId = null;\n            const fired = runScheduler();", "            session.agentState = \"offline\";\n            session.reasonId = null;\n            const fired = [];", "api"),
    ("visibility-ignored", "server.js", "let list = events.filter((e) => canSee(e) && shown.has(STATES[e.state].category));", "let list = events.filter((e) => shown.has(STATES[e.state].category));", "api"),
    # Объединение (§11): основной, срок, закрытие привязанных; вкладка — фильтр; панель выборки
    ("merge-primary-order", "server.js", "const order = (a, b) => b.priority - a.priority || a.occurredAt - b.occurredAt || byNumber(a, b);", "const order = (a, b) => a.priority - b.priority || a.occurredAt - b.occurredAt || byNumber(a, b);", "api"),
    ("merge-linked-stay-open", "server.js", "if (isDone(ev) && events.some((e) => e.linkedTo === ev.id && e.state === \"linked\")) runScheduler();", "", "api"),
    ("ui-linked-chip-hidden", "app.js", "if (!e.linkedCount) return \"\";", "return \"\";", "ui"),
    ("ui-selection-bar-hidden", "app.js", "bar.hidden = !n;", "bar.hidden = true;", "ui"),
    ("card-ignores-access", "server.js", "      return ev && canSee(ev) ? ev : null;", "      return ev;", "api"),
    ("stream-leaks-hidden", "server.js", "      if (ev && !canSee(ev)) return;\n", "", "api"),
    ("tree-ignores-access", "server.js", ".filter((c) => c.isDevice && myDevices.has(c.id))", ".filter((c) => c.isDevice)", "api"),
    ("counters-ignore-access", "server.js", "const list = visible({});", "const list = events;", "api"),
    ("target-access-ignored", "engine.js", "return !target || ctx.hasAccess(target, ev) ? null : [\"workflow.guard.target_no_access\"];", "return null;", "api"),
    ("group-access-all-members", "server.js", "if (group) return membersOf(group).some((m) => hasAccess(m, ev));", "if (group) return membersOf(group).every((m) => hasAccess(m, ev));", "api"),
    ("level-cannot-accept-ignored", "engine.js", "return !ctx.canAccept || ctx.canAccept(target, ev, ev.owner);", "return true;", "api"),
    # Уровень, где принять может только тот, у кого инцидент уже есть, пропускается (RULE-93)
    ("level-current-addressee-ignored", "engine.js", "if (target === addressee(ev)) return false;", "", "api"),
    ("level-group-owner-counted", "engine.js", "ctx.canAccept(target, ev, ev.owner)", "ctx.canAccept(target, ev)", "api"),
    ("group-accept-except-ignored", "server.js", "membersOf(group).some((m) => m !== except && canAccept(m, ev))", "membersOf(group).some((m) => canAccept(m, ev))", "api"),
    ("alert-ignores-access", "server.js", ".filter((id) => present({ id }) && hasAccess(id, ev));", ".filter((id) => present({ id }));", "api"),
    ("alert-ignores-presence", "server.js", ".filter((id) => present({ id }) && hasAccess(id, ev));", ".filter((id) => hasAccess(id, ev));", "api"),
    ("alert-no-recipient-silent", "engine.js", "if (!sent) ctx.log(inc, s.actor, W.alerts.noRecipientLog, {}, now());", "", "api"),
    ("tick-array-order", "engine.js", "if (!next || c.moment < next.moment) next = c;", "if (!next) next = c;", "api"),
    ("tick-effects-at-now", "engine.js", "          at = runAt;\n          let facts = null;", "          at = null;\n          let facts = null;", "api"),
    ("admin-read-without-right", "server.js", "        \"/operator/admin/duty-groups\",\n        () => {\n          if (!can(\"incident:schema:admin\")) return problem(403, \"PERMISSION_DENIED\", [\"workflow.error.no_schema_admin\"]);", "        \"/operator/admin/duty-groups\",\n        () => {", "api"),
    ("tick-without-after", "engine.js", "const moment = momentOf(ev, tr, last);", "const moment = momentOf(ev, tr, null);", "api"),
    ("alert-toast-silent", "app.js", 'toast(t("Алерт: {id} — {what}", { id, what: tr ? lbl(tr) : tid }));', "", "ui"),
    ("access-lost-toast-silent", "app.js", 'toast(t("{id} вам больше не доступен: изменились группы доступа", { id: msg.payload.number }));', "", "ui"),
    ("admin-values-raw", "app.js", "    if (values && typeof v === \"string\" && values[v]) return te(values[v]);\n", "", "ui"),
    ("colleagues-not-ticked", "server.js", "const others = OPERATORS.filter((op) => op.id !== ME).flatMap((op) => colleagueTick(op.id));", "const others = [];", "api"),
    ("colleague-always-ready", "server.js", "agentState: () => agentStateOf(id),", "agentState: () => \"ready\",", "api"),
    ("reset-ignores-workflow-patch", "server.js", "useWorkflow(body.workflowPatch ? mergePatch(BASE_W, body.workflowPatch) : BASE_W);", "useWorkflow(BASE_W);", "api"),
    ("reset-ignores-fixture-patch", "server.js", "load(body.fixturePatch ? mergePatch(FIXTURE, body.fixturePatch) : FIXTURE);", "load(FIXTURE);", "api"),
    ("help-links-ignore-site", "server.js", "q.site == null || l.site == null || l.site === q.site", "true", "api"),
    ("help-menu-without-site", "app.js", 'ev && ev.site ? { site: ev.site } : {}', "{}", "ui"),
    ("cameras-not-from-links", "server.js", "cameras: camerasOf(inc.devices[0]),", "cameras: CAMERA_LINKS[0].cameras.slice(),", "api"),
    ("camera-links-first-only", "server.js", "CAMERA_LINKS.filter((l) => l.devices.includes(source)).flatMap", "CAMERA_LINKS.filter((l) => l.devices.includes(source)).slice(0, 1).flatMap", "api"),
    ("camera-links-duplicates", "server.js", "[...new Set(CAMERA_LINKS.filter((l) => l.devices.includes(source)).flatMap((l) => l.cameras))]", "CAMERA_LINKS.filter((l) => l.devices.includes(source)).flatMap((l) => l.cameras)", "api"),
    ("camera-links-reverse", "server.js", "new Set(CAMERA_LINKS.filter(", "new Set(CAMERA_LINKS.slice().reverse().filter(", "api"),
    ("camera-links-ignore-source", "server.js", "CAMERA_LINKS.filter((l) => l.devices.includes(source))", "CAMERA_LINKS.filter((l) => l.devices.length)", "api"),
    ("camera-links-created-empty", "server.js", "cameras: camerasOf(devices[0]),", "cameras: [],", "api"),
    ("ui-camera-links-no-name", "app.js", "<tr><td>${asData(l.name)}</td><td>${names(l.devices)}</td>", "<tr><td>—</td><td>${names(l.devices)}</td>", "ui"),
    ("expired-resolution-refires", "engine.js", "if (left === 0 && fired) {", "if (false) {", "api"),
    ("cannot-accept-ignored", "engine.js", "return Boolean(ctx.canAccept && ctx.canAccept(who, ev)) === expected ? null : [\"workflow.guard.addressee_can_accept\"];", "return [\"workflow.guard.addressee_can_accept\"];", "api"),
    ("lost-access-ignored", "engine.js", "return Boolean(ctx.hasAccess && ctx.hasAccess(who, ev)) === expected ? null : [\"workflow.guard.addressee_access\"];", "return [\"workflow.guard.addressee_access\"];", "api"),
    ("group-roles-ignored", "server.js", "const byRole = OPERATORS.filter((o) => rolesOf(o.id).some((r) => (group.roles || []).includes(r))).map((o) => o.id);", "const byRole = [];", "api"),
    ("duty-group-last", "server.js", "dutyGroupOf: (userId) => (GROUPS.find((g) => membersOf(g).includes(userId)) || {}).id || null,", "dutyGroupOf: (userId) => ([...GROUPS].reverse().find((g) => membersOf(g).includes(userId)) || {}).id || null,", "api"),
    ("group-shift-ignored", "server.js", "(op.group ? membersOf(op).some((m) => present({ id: m })) :", "(op.group ? true :", "api"),
    ("agent-state-ignored", "server.js", ": ![\"not_ready\", \"offline\"].includes(agentStateOf(op.id)));", ": true);", "api"),
    ("ui-bulk-failures-hidden", "app.js", "toast(res.failed.length ? `${okText} ", "toast(false ? `${okText} ", "ui"),
    ("ui-bulk-transfer-copy", "app.js", 'title: t("Передать {n, plural, one {# инцидент} few {# инцидента} other {# инцидентов}}", { n }),', 'title: t("Передать"),', "ui"),
    ("external-effects-dropped", "server.js", "journalEntries: journal, externalEffects, canceledTimerTrigger", "journalEntries: journal, externalEffects: [], canceledTimerTrigger", "api"),
    ("reopen-window-rounded", "engine.js", "now() - (ev.closedAt || 0) <= W.limits.reopenWindowMin * 60000", "Math.round((now() - (ev.closedAt || 0)) / 60000) <= W.limits.reopenWindowMin", "api"),
    ("queue-not-sorted", "server.js", "}).sort((a, b) => ORDERS[sortOf(q)](a, b) || byNumber(a, b));", "});", "api"),
    ("queue-sort-always-open", "server.js", "return s.operatorMayChange && s.options.includes(asked) ? asked : s.default;", "return s.options.includes(asked) ? asked : s.default;", "api"),
    ("queue-filters-ignored", "server.js", 'if (q.priority != null && q.priority !== "" && e.priority !== Number(q.priority)) return false;', "", "api"),
    ("strings-no-fallback", "server.js", "const strings = Object.assign({}, STRINGS.ru || {}, STRINGS[locale] || {});", "const strings = STRINGS[locale] || {};", "api"),
    ("ui-catalog-ignored", "app.js", "if (catalog[ru] != null) return icu(catalog[ru], vars || {});", "", "ui"),
    ("create-norm-from-occurred", "engine.js", 'const applied = applyEffects(tr, ev, {}, tr.actor || "dispatcher");\n      return applied.ok', 'at = ev.occurredAt;\n      const applied = applyEffects(tr, ev, {}, tr.actor || "dispatcher");\n      at = null;\n      return applied.ok', "api"),
    ("ui-notice-ignored", "app.js", 'if (notice && (notice.audience === "observers" ||', 'if (false && (notice.audience === "observers" ||', "ui"),
    ("transition-facts-missing", "server.js", "state: { from: f.from.state || null, to: ev.state },", "state: { from: null, to: ev.state },", "api"),
    ("grace-ignored", "engine.js", "(agentOnly || c.moment + GRACE_MS > ctx.now())", "agentOnly", "api"),
    # Системный переход в окне после дедлайна (RULE-67): переход по таймеру — первым
    # При прыжке часов переход по таймеру — не позже готового системного (BUG-38)
    ("timer-after-system-in-jump", "engine.js", "Math.max(next.moment + GRACE_MS, last || 0), sysAt)", "Math.max(next.moment + GRACE_MS, last || 0), ctx.now())", "api"),
    ("system-waits-for-grace", "engine.js", 'c.tr.trigger === "timer" && !system && (agentOnly', 'c.tr.trigger === "timer" && (agentOnly', "api"),
    ("override-ignored", "engine.js", "      const canceled = windowBefore(ev, id);", "      const canceled = null;", "api"),
    # Объединение проверяет окно так же, как одиночный переход (BUG-62)
    ("merge-window-ignored", "engine.js", "const canceled = others.map((ev) => windowBefore(ev, check.tr.id));", "const canceled = others.map(() => null);", "api"),
    ("merge-primary-window-ignored", "engine.js", "const primaryCanceled = check.take ? windowBefore(primary, check.take.id) : null;", "const primaryCanceled = null;", "api"),
    # Ручной переход, после которого таймер продолжается, окно не отменяет (RULE-83)
    ("window-cancels-continuing", "engine.js", "        if ((timers[g.args[0]].continuesOn || []).includes(manualId)) return;\n", "", "api"),
    # Группа и устройство — по устройству-источнику, а не по всем устройствам события (RULE-85)
    ("group-by-all-devices", "server.js", "const touches = (ev, ids) => ids.includes(eventSource(ev));", "const touches = (ev, ids) => (ev.deviceIds || []).some((id) => ids.includes(id));", "api"),
    # В дереве — все устройства группы, а не только с тревогой (RULE-86)
    # У группы одно число — открытые инциденты, плашки «подгрупп / устройств» нет (BUG-64)
    ("tree-badge-back", "app.js", '              ${isDevice ? "" : filterButtons(item.guid)}', '              ${isDevice ? "" : `<span class="tree-badge">${(item.children || []).length}</span>` + filterButtons(item.guid)}', "ui"),
    # Узел без открытых инцидентов приглушён (RULE-92)
    ("tree-quiet-ignored", "app.js", 'const quiet = counters.open ? "" : "quiet";', 'const quiet = "";', "ui"),
    ("tree-quiet-unstyled", "styles.css", ".tree-node.quiet > .node-content > .material-symbols-outlined:not(.toggle-icon) { color: var(--tree-quiet, var(--muted)); }", ".tree-node.quiet > .node-content > .material-symbols-outlined:not(.toggle-icon) { }", "ui"),
    # Длинные названия в дереве — на две строки, текущее найденное — целиком (BUG-65)
    ("tree-names-one-line", "styles.css", "  display: -webkit-box;\n  -webkit-box-orient: vertical;\n  -webkit-line-clamp: 2;\n", "  white-space: nowrap;\n  text-overflow: ellipsis;\n", "ui"),
    ("tree-current-clamped", "styles.css", ".tree-node.hit-current > .node-content .node-text { display: block; -webkit-line-clamp: none; line-clamp: none; }", ".tree-node.hit-current > .node-content .node-text { display: block; }", "ui"),
    ("tree-open-devices-only", "app.js", "const devices = parent ? groupDevices(parent) : [];", "const devices = parent ? groupDevices(parent).filter((d) => d.counters && d.counters.open > 0) : [];", "ui"),
    # Esc в карточке — «К очереди», если не открыто меню, форма или окно (RULE-87)
    # Esc — по одному слою: развёрнутые видео или карта, панель групп поверх узкого экрана (RULE-91)
    ("esc-ignores-full", "app.js", "    if (state.full) {\n", "    if (false) {\n", "ui"),
    ("esc-ignores-drawer", "app.js", "if (state.groupsOn && narrowQuery.matches) return closeDrawer();", "", "ui"),
    ("esc-keeps-card", "app.js", "    if (state.mode !== \"work\") return;\n", "    return;\n", "ui"),
    # Поиск и клавиатура в дереве групп (RULE-88)
    ("tree-no-mark", "app.js", "if (at < 0) return escapeHtml(text);", "return escapeHtml(text);", "ui"),
    ("tree-down-stays", "app.js", "const moves = { ArrowDown: items[at + 1],", "const moves = { ArrowDown: node,", "ui"),
    ("tree-focus-lost", "app.js", "    if (current && hadFocus) current.focus();\n", "", "ui"),
    ("tree-right-ignored", "app.js", "      state.openGroups.add(id);\n      return renderGroups();", "      return;", "ui"),
    ("tree-search-esc-kept", "app.js", "      } else if (e.key === \"Escape\" && e.target.value) {", "      } else if (false) {", "ui"),
    ("tree-hit-stays", "app.js", "state.treeHit = (state.treeHit + dir + n) % n;", "state.treeHit = (state.treeHit + n) % n;", "ui"),
    # Выбор узла раскрывает путь к нему: после очистки поиска выбранное видно (BUG-63)
    ("tree-chosen-hidden", "app.js", "for (let up = node.parentElement.closest(\".tree-node\"); up; up = up.parentElement.closest(\".tree-node\")) state.openGroups.add(up.dataset.id);", "", "ui"),
    # Группа, найденная по названию, — свёрнута; раскрытая — внутри всё (BUG-67)
    ("tree-found-group-empty", "app.js", "const reveal = Boolean(all || (q && !forceOpen && open));", "const reveal = false;", "ui"),
    ("tree-found-group-forced", "app.js", "const forceOpen = Boolean(q && !all && hasKids && foundInside(item, q));", "const forceOpen = Boolean(q && !all && hasKids && nodeMatchesQuery(item, q, isDevice));", "ui"),
    ("tree-left-search-stuck", "app.js", 'if (open && !node.classList.contains("search-open")) {', "if (open && !state.groupQuery.trim()) {", "ui"),
    # Home и End в дереве — первый и последний видимый узел (§13, PROC-27)
    ("tree-home-end-ignored", "app.js", ", Home: items[0], End: items[items.length - 1] };", " };", "ui"),
    ("tree-hit-enter-ignored", "app.js", "      } else if (e.key === \"Enter\") {\n        e.preventDefault();\n        stepTreeHit(e.shiftKey ? -1 : 1);", "      } else if (false) {", "ui"),
    # «Далее» всегда на месте: на последнем шаге и на вкладке привязанных — серая (RULE-89)
    ("next-on-last-step", "app.js", "    return i < path.length - 1;\n  }", "    return true;\n  }", "ui"),
    ("next-on-linked-tab", "app.js", 'const canNext = tab === "scenario" && canGoNext(ev, i, editable);', "const canNext = canGoNext(ev, i, editable);", "ui"),
    ("back-after-next", "styles.css", ".scenario-actions-end { grid-area: next; display: flex; flex-wrap: nowrap;", ".scenario-actions-end { grid-area: next; display: flex; flex-direction: row-reverse; flex-wrap: nowrap;", "ui"),
    ("counters-always", "server.js", 'body: treeView(TREE, q.withCounters === "true")', "body: treeView(TREE, true)", "api"),
    ("journal-not-paged", "server.js", "body: { items: all.slice((n - 1) * size, n * size), total: all.length } }", "body: { items: all, total: all.length } }", "api"),
    ("group-settled-per-member", "server.js", "            if (r.status === 200) {\n              done.push(ev);", "            if (r.status === 200) {\n              settleGroups();\n              done.push(ev);", "api"),
    ("access-lost-not-sent", "server.js", "if (wasMine.has(id) && !canSee(ev)) {", "if (false) {", "api"),
    ("target-can-accept-ignored", "engine.js", "return !target || ctx.canAccept(target, ev) ? null : [\"workflow.guard.target_cannot_accept\"];", "return null;", "api"),
    ("accept-right-ignored", "server.js", "return permsOf(id).includes(\"incident:accept\") && hasAccess(id, ev);", "return hasAccess(id, ev);", "api"),
    ("stream-id-repeats", "server.js", "const message = Object.assign({ id: String(++seq) }, body);", "const message = Object.assign({ id: String(seq) }, body);", "api"),
    ("ui-required-from-ignored", "app.js", "if (!field.requiredFrom) return Boolean(field.required);", "return Boolean(field.required);", "ui"),
    ("ui-esc-keeps-modal", "app.js", "if (e.key !== \"Escape\") return;", "return;", "ui"),
    ("selection-reason-generic", "server.js", "if (!ok && !reason && failed && failed[1].why && (mode.allowed || list.length < 2)) {", "if (false) {", "api"),
    ("selection-reason-irrelevant-first", "server.js", "const failed = avail.find(([, a]) => !a.ok && !a.hidden) || avail.find(([, a]) => !a.ok);", "const failed = avail.find(([, a]) => !a.ok);", "api"),
    ("selection-visible-always", "server.js", "const visible = mode.mode === \"merge\" || avail.some(([, a]) => !a.hidden);", "const visible = true;", "api"),
    ("ui-combo-typing-ignored", "app.js", "if (state.tbOpen === input.dataset.tbToggle) return comboNarrow(input);", "if (state.tbOpen === input.dataset.tbToggle) return;", "ui"),
    ("ui-combo-enter-ignored", "app.js", "    } else if (e.key === \"Enter\" && first) {\n      e.preventDefault();\n      first.click();", "    } else if (e.key === \"Enter\" && first) {\n      e.preventDefault();", "ui"),
    ("ui-filter-combo-typing-ignored", "app.js", "if (filt.open === input.dataset.msToggle) return comboNarrow(input);", "if (filt.open === input.dataset.msToggle) return;", "ui"),
    ("ui-filter-dialog-stale-language", "app.js", "      filt.focusSearch = false;\n      renderFilter();\n    }\n    syncLocale", "      filt.focusSearch = false;\n    }\n    syncLocale", "ui"),
    ("ui-take-as-one-stays-in-queue", "app.js", "    navigate(merge.ui.navigate);\n", "", "ui"),
    ("detach-all-partial", "server.js", "          if (blocked) return runTransition(detach.id, blocked, {}, \"card\");\n", "", "api"),
    ("ui-detach-all-hidden", "app.js", "      first && total > 1\n", "      false\n", "ui"),
    ("linked-page-ignored", "server.js", "items: all.slice((n - 1) * size, n * size).map((e) => summary(e, \"card\")), total: all.length, page: n, pageSize: size", "items: all.slice(0, size).map((e) => summary(e, \"card\")), total: all.length, page: n, pageSize: size", "api"),
    ("ui-linked-page-ignored", "app.js", "        state.linkedPage = Number(lnkPage.dataset.lnkPage);\n", "", "ui"),
    ("ui-linked-all-on-one-page", "app.js", "      total > LINKED_PAGE\n", "      false\n", "ui"),
    ("merged-in-uncapped", "server.js", "others.slice(0, MERGED_IN_SHOWN).map((o) => o.number)", "others.map((o) => o.number)", "api"),
    ("filter-same-scenario-ignored", "server.js", "        const inScenario = byScenario.get(scenarioGuid);\n", "        const inScenario = all;\n", "api"),
    ("filter-scenario-choice-ignored", "server.js", "        const asked = scenarios.find((x) => x.id === body.scenarioGuid);\n", "        const asked = null;\n", "api"),
    ("ui-filter-same-not-sent", "app.js", "        sameScenario: filt.same,\n", "", "ui"),
    ("ui-filter-scenario-not-sent", "app.js", "        Object.assign(filt, { scenario: box.value, open: null, q: {}, focusSearch: false });", "        Object.assign(filt, { open: null, q: {}, focusSearch: false });", "ui"),
    ("merge-reason-wrong-incident", "server.js", "            if (!check.ok && check.why) {\n", "            if (false) {\n", "api"),
    ("filter-same-includes-foreign", "server.js", "        matched = takeable(inScenario);\n", "        matched = inScenario;\n", "api"),
    ("ui-zero-option-selectable", "app.js", "${none ? input.replace(\" />\", \" disabled />\") : input}", "${input}", "ui"),
    ("filter-zero-scenario-kept", "server.js", "scenarioGuid = asked && (asked.count > 0 || !best.count) ? asked.id : best.id;", "scenarioGuid = asked ? asked.id : best.id;", "api"),
    ("filter-options-ignore-scenario", "server.js", "        base = takeable(pool.filter((e) => scenarioKey(e) === scenarioGuid));\n", "", "api"),
    ("filter-options-not-viable", "server.js", "        base === pool ? opts : opts.filter(", "        true ? opts : opts.filter(", "api"),
    ("ui-work-tab-ignored", "app.js", "        state.workTab = tabBtn.dataset.workTab;\n", "", "ui"),
    ("ui-work-tabs-hidden", "app.js", "    if (!ev.linkedCount) return \"\";\n    const b = (id, label) =>", "    return \"\";\n    const b = (id, label) =>", "ui"),
    ("ui-actions-jump-on-tab", "app.js", 'id="stepBack" ${tab !== "scenario" || i === 0 ? "disabled" : ""}', 'id="stepBack" ${tab !== "scenario" ? "hidden" : i === 0 ? "disabled" : ""}', "ui"),
    ("search-ignores-linked", "server.js", "if (!hit(e, needle) && !linkedHits(e, needle).length) return false;", "if (!hit(e, needle)) return false;", "api"),
    ("linked-focus-page-ignored", "server.js", "const idx = q.focusGuid ? all.findIndex((e) => e.id === q.focusGuid) : -1;", "const idx = -1;", "api"),
    ("ui-search-opens-scenario", "app.js", "workTab: foundLinked(ev.guid).length ? \"linked\" : \"scenario\"", "workTab: \"scenario\"", "ui"),
    ("ui-search-found-page-ignored", "app.js", "    if (page && page.focusPage && page.focusPage !== state.linkedPage) {", "    if (false) {", "ui"),
    ("copy-answers-overwrites", "scenario.js", "if (!entry || entry.skipped || r.state[id] || !src", "if (!entry || entry.skipped || !src", "api"),
    ("copy-answers-no-log", "engine.js", "          if (n && template) ctx.log(p, s.actor, template, { number: ev.number, n }, at);\n", "", "api"),
    ("relink-closed-too", "engine.js", "const children = ctx.events().filter((e) => e.linkedTo === ev.id && !isDone(e));", "const children = ctx.events().filter((e) => e.linkedTo === ev.id);", "api"),
    ("relink-no-log", "engine.js", "            if (template) ctx.log(e, s.actor, template, { primaryNumber: p.number }, at);\n", "", "api"),
    ("transfer-restarts-reaction", "engine.js", "if (mode === \"ifStopped\" && dueOf(ev, id)) return;", "if (mode === \"ifStopped\" && false) return;", "api"),
    ("level0-last-norm", "engine.js", "const found = level > 0 ? levels.find((l) => l.level === level) || levels[levels.length - 1] : null;", "const found = levels.find((l) => l.level === level) || levels[levels.length - 1];", "api"),
    ("detach-before-accept", "engine.js", "return p && (ownership(p) === \"owner\" || unowned(p)) ? null", "return p && (isMine(p) || unowned(p)) ? null", "api"),
    ("linked-breach-owner-self", "engine.js", "owner: who === \"primaryOwner\" ? breachOwnerOfLinked(ev) : addressee(ev)", "owner: addressee(ev)", "api"),
    ("merge-starts-fresh-resolution", "engine.js", "        if (mode === \"ifStarted\" && !dueOf(ev, id) && ev[FIELDS[id].left] == null) return;\n", "", "api"),
    ("linked-due-missing", "server.js", "        linkedDueAt: linkedDue(ev),", "        linkedDueAt: null,", "api"),
    ("ui-linked-row-no-timer", "app.js", "${timerChip(m, \"event-sla lnk-sla\") || \"<span></span>\"}", "<span></span>", "ui"),
    ("ui-linked-due-chip-hidden", "app.js", "    if (!e.linkedDueAt) return \"\";\n    const due = Date.parse(e.linkedDueAt);", "    return \"\";\n    const due = Date.parse(e.linkedDueAt);", "ui"),
    ("ui-select-by-filter-menu-dead", "app.js", "      openFilter(state.groupId || \"all\");\n", "", "ui"),
    ("ui-absence-hidden", "app.js", 'o.available === false && o.availabilityLabel ? t(o.availabilityLabel) : ""', '""', "ui"),
    ("ui-target-typing-keeps-pick", "app.js", '      input.parentElement.querySelector("[data-field]").value = "";\n', "", "ui"),
    ("ui-target-open-after-blur", "app.js", "        if (open && !open.contains(document.activeElement)) closeTargetCombo(open.dataset.targetCombo);\n", "", "ui"),
    ("ui-target-options-tabbable", "app.js", 'role="option" tabindex="-1" data-target-pick=', 'role="option" data-target-pick=', "ui"),
    ("ui-target-unnamed", "app.js", '    input.setAttribute("aria-label", `${lbl(field)}, ${picked ? t(picked.label) : hint}`);\n', "", "ui"),
    ("ui-target-selected-accent", "styles.css", '.target-opt[aria-selected="true"] { background: var(--accent-dim); color: var(--text); font-weight: 600; }', '.target-opt[aria-selected="true"] { background: var(--accent-dim); color: var(--accent); font-weight: 600; }', "ui"),
    ("ui-target-notes-faint", "styles.css", ".target-opt em { color: var(--muted); }", ".target-opt em { color: var(--faint); }", "ui"),
    ("ui-target-enter-ignored", "app.js", "      pickTarget(name, opts[0].dataset.targetPick);\n", "", "ui"),
    ("ui-target-down-closed", "app.js", "      if (!state.dialog.combo.open) return openTargetCombo(name);\n", "      if (!state.dialog.combo.open) return;\n", "ui"),
    ("ui-target-menu-in-flow", "styles.css", ".target-combo .mselect-menu { position: absolute;", ".target-combo .mselect-menu { position: static;", "ui"),
    ("ui-target-sections-swapped", "app.js", 'section("На месте", all.filter((o) => o.available !== false), `${field.name}-here`) +\n      section("Нет на месте", all.filter((o) => o.available === false), `${field.name}-away`)', 'section("Нет на месте", all.filter((o) => o.available === false), `${field.name}-away`) +\n      section("На месте", all.filter((o) => o.available !== false), `${field.name}-here`)', "ui"),
    ("ui-target-prefix-search", "app.js", "const targetHit = (o, q) => comboHit(`${t(o.label)} ${t(o.role || \"\")}`, q);", "const targetHit = (o, q) => !q || t(o.label).toLowerCase().startsWith(q.toLowerCase());", "ui"),
    ("ui-target-esc-closes-form", "app.js", "    if (e.key === \"Escape\" && state.dialog.combo.open) {\n      e.stopPropagation();", "    if (e.key === \"Escape\" && state.dialog.combo.open) {", "ui"),
    ("reopen-keeps-link", "engine.js", "        const p = ev.linkedTo && byId(ev.linkedTo);\n        ev.linkedTo = null;\n", "        const p = ev.linkedTo && byId(ev.linkedTo);\n        if (!s.form || !s.form.comment) ev.linkedTo = null;\n", "api"),
    ("reopen-unlink-no-log", "engine.js", "        if (primary) s.after.push(() => ctx.log(p, s.actor, primary, { number: ev.number }, at));\n", "", "api"),
    ("linked-access-ignored", "engine.js", "        return Boolean(ctx.hasAccess && ctx.hasAccess(who, ev)) === expected ? null : [\"workflow.guard.primary_addressee_access\"];", "        return expected ? null : [\"workflow.guard.primary_addressee_access\"];", "api"),
    ("absence-no-reason", "server.js", 'render("workflow.label.absent.break", { reason: reason ? [reason.labelKey] : "" })', 'render("workflow.label.absent.break", { reason: "" })', "api"),
    ("last-transfer-target-forgotten", "server.js", "      if (targetField && formValues && formValues[targetField.name]) session.lastTransferTargetId = formValues[targetField.name];\n", "", "api"),
    ("ui-selection-bar-only-enabled", "app.js", "a.kind === \"transition\" && a.bulkAllowed && a.visible)", "a.kind === \"transition\" && a.bulkAllowed && a.enabled)", "ui"),
    ("ui-disabled-not-explained", "app.js", "if (btn.getAttribute(\"aria-disabled\") !== \"true\") return false;\n    toast(btn.title || t(\"Действие недоступно\"));", "if (btn.getAttribute(\"aria-disabled\") !== \"true\") return false;", "ui"),
    ("ui-placeholder-ignored", "app.js", "const fallback = hasLbl(field, \"placeholder\") ? (enabled.length === 1 ? enabled[0].id : \"\") : enabled[0] && enabled[0].id;", "const fallback = enabled[0] && enabled[0].id;", "ui"),
    ("ui-no-if-match", "app.js", "const ifMatch = (ev) => ({ \"If-Match\": `\"${ev.version}\"` });", "const ifMatch = () => ({});", "ui"),
    ("ui-row-acts-on-selection", "app.js", 'trigger(act.dataset.do, store.page.items.find((x) => x.guid === act.dataset.ev), "queue");', 'trigger(act.dataset.do, store.page.items.find((x) => x.guid === act.dataset.ev), "queue", [...state.checked]);', "ui"),
    # Порядок очереди и новая схема (§7, §14.10, BUG-34)
    # Телефон: типы и порядок — под «Фильтры» с числом выбранных (BUG-50)
    ("ui-more-filters-no-count", "app.js", '$("eventsMoreN").hidden = !n;', '$("eventsMoreN").hidden = true;', "ui"),
    ("ui-more-filters-no-toggle", "app.js", '$("eventsToolbar").classList.toggle("more-open", state.moreFilters);', "", "ui"),
    ("ui-sort-ignores-permission", "app.js", "select.hidden = !s.operatorMayChange;", "select.hidden = false;", "ui"),
    ("ui-sort-not-saved", "app.js", 'await api.patch("/operator/session/preferences", { queueSort: e.target.value });', "", "ui"),
    ("ui-sort-no-requery", "app.js", 'await api.patch("/operator/session/preferences", { queueSort: e.target.value });\n      requery(true);', 'await api.patch("/operator/session/preferences", { queueSort: e.target.value });', "ui"),
    ("ui-selection-survives-context", "app.js", "    if (!keepSelection) {\n      state.checked.clear();", "    if (false) {\n      state.checked.clear();", "ui"),
    ("ui-filter-select-keeps-view", "app.js", "    Object.assign(state, { groupId: filt.node ? filt.node.guid : \"all\", deviceTypes: [], eventTypes: [], search: \"\", page: 1 });\n", "", "ui"),
    ("ui-schema-not-reloaded", "app.js", 'if (msg.type === "workflow.schema_published") {', "if (false) {", "ui"),
    ("schema-published-silent", "server.js", 'if (W !== before) emit("workflow.schema_published"', 'if (false) emit("workflow.schema_published"', "api"),
    # Цвет полоски очереди — из настройки приоритета, не свой в коде (§1, §4, BUG-39)
    ("ui-priority-color-ignored", "app.js", 'data-color="${escapeHtml(PRIORITIES[e.priority].color)}"', 'data-color="red"', "ui"),
    # Приоритеты — настраиваемый справочник (§2.5, RULE-68)
    ("priority-coercion-off", "server.js", "priority: priorityLevel(spec.priority),", "priority: spec.priority,", "api"),
    ("top-priority-fixed", "server.js", "const topPriority = () => (PRIORITIES.length ? PRIORITIES[0].value : null);", "const topPriority = () => 100;", "api"),
    ("ui-priorities-not-reloaded", "app.js", 'if (msg.type === "reference.priorities_changed") {', "if (false) {", "ui"),
    # Лимиты без ограничения (§10.2, §11, RULE-69) и проверка лимита выборки на сервере (BUG-40)
    ("active-limit-null-blocks", "engine.js", "        if (W.limits.maxActive == null) return null;\n", "", "api"),
    ("bulk-limit-unchecked", "server.js", "if (W.limits.maxBulk != null && guids.length > W.limits.maxBulk) return problem(", "if (false) return problem(", "api"),
    ("selection-truncated-on-null", "server.js", "const max = W.limits.maxBulk;\n      let list = [];", "const max = W.limits.maxBulk ?? 0;\n      let list = [];", "api"),
    ("ui-status-always-of-n", "app.js", 'LIMITS.maxActive == null ? t("В очереди: {n} · у меня: {a}, отложено: {h}", queueVars) : t(', "t(", "ui"),
    ("ui-null-key-ignored", "app.js", 'if (v == null) return nullKey ? te(nullKey) : "—";', 'if (v == null) return "—";', "ui"),
    # Плашка сценария в очереди — название, не счёт шагов (§14.5)
    ("ui-scenario-chip-count", "app.js", '<span class="event-prog">${escapeHtml(scenarioTitle(e))}</span>', '<span class="event-prog">${prog.filled}/${prog.total}</span>', "ui"),
    ("ui-scenario-chip-only-answered", "app.js", "${prog.total ? `<span class=\"event-prog\">", "${prog.filled ? `<span class=\"event-prog\">", "ui"),
    ("ui-scenario-untitled-empty", "app.js", 't(ev.scenarioTitle || "Без названия")', 't(ev.scenarioTitle || "")', "ui"),
    ("ui-priority-no-label", "app.js", 'role="img" aria-label="${te("Приоритет: {label}", {\n        label: inLang(PRIORITIES[e.priority].name),\n      })}"', "", "ui"),
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


def run_tests(site, kind, profile, failfast=False):
    shutil.rmtree(profile, ignore_errors=True)
    if kind == "api":
        page = chrome(f"file://{site}/tests/api.html" + ("?failfast" if failfast else ""), profile, 120000)
        passed = 'data-apitest="pass"' in page
        log = re.search(r'<pre id="apitest-log">(.*?)</pre>', page, re.S)
    elif kind == "scenario":
        page = chrome(f"file://{site}/tests/scenario.html", profile, 60000)
        passed = 'data-scenariotest="pass"' in page
        log = re.search(r'<pre id="scenariotest-log">(.*?)</pre>', page, re.S)
    else:
        page = chrome(f"file://{site}/prototype/index.html?selftest" + ("&failfast" if failfast else ""), profile, 60000)
        passed = 'data-selftest="pass"' in page
        log = re.search(r'<pre id="selftest-log"[^>]*>(.*?)</pre>', page, re.S)
    fails = [line for line in (log.group(1).splitlines() if log else []) if line.startswith("FAIL")]
    return passed, fails, bool(log)


def check(site, profile, mutation, full):
    """Одна мутация в своей копии прототипа: строка вердикта и выжила ли."""
    name, file, old, new, kind = mutation
    path = os.path.join(site, "prototype", file)
    with open(path, encoding="utf-8") as f:
        code = f.read()
    if code.count(old) != 1:
        return f"STALE {name}: в {file} не найдено место порчи — обновите мутацию", True
    with open(path, "w", encoding="utf-8") as f:
        f.write(code.replace(old, new))
    try:
        # До первого падения: не упало ничего — значит, пройден весь набор
        passed, fails, ran = run_tests(site, kind, profile, failfast=not full)
    finally:
        with open(path, "w", encoding="utf-8") as f:
            f.write(code)
    if not ran:
        return f"KILLED {name} [{kind}] — тесты не запустились (ошибка JS)", False
    if passed:
        return f"SURVIVED {name} [{kind}] — тесты прошли с испорченным {file}", True
    return f"KILLED {name} [{kind}] — {fails[0][:110] if fails else 'тесты упали'}", False


def main():
    wanted, jobs, shard, shards = parallel.options()
    full = "--full" in sys.argv
    todo = parallel.part([m for m in MUTATIONS if not wanted or m[0] in wanted], shard, shards)
    work = tempfile.mkdtemp(prefix="im-code-mut-")
    tasks = queue.Queue()
    for m in todo:
        tasks.put(m)
    lock = threading.Lock()
    survived = []

    def worker(n):
        # Своя копия прототипа и тестов: портится и восстанавливается по одному файлу
        site = os.path.join(work, f"site{n}")
        for sub in ("prototype", "tests", "theme"):
            shutil.copytree(os.path.join(ROOT, sub), os.path.join(site, sub))
        profile = os.path.join(work, f"profile{n}")
        while True:
            try:
                m = tasks.get_nowait()
            except queue.Empty:
                return
            line, bad = check(site, profile, m, full)
            with lock:
                print(line, flush=True)
                if bad:
                    survived.append(m[0])

    try:
        threads = [threading.Thread(target=worker, args=(n,)) for n in range(min(jobs, len(todo)) or 1)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        # Контроль: без порчи тесты проходят — полный прогон; при делении на части — в первой
        if not wanted and shard == 1:
            site, profile = os.path.join(work, "site0"), os.path.join(work, "profile-base")
            if not os.path.exists(site):
                for sub in ("prototype", "tests", "theme"):
                    shutil.copytree(os.path.join(ROOT, sub), os.path.join(site, sub))
            for kind in ("api", "ui", "scenario"):
                passed, fails, _ = run_tests(site, kind, profile)
                if not passed:
                    survived.append(f"BASE {kind}")
                    print(f"BASE [{kind}] — без порчи тесты не проходят: {fails[:2]}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    part = f" (часть {shard} из {shards}: {len(todo)} мутаций)" if shards > 1 else ""
    print(f"Выживших мутаций кода: {len(survived)}{part}")
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
