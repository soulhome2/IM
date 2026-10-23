#!/usr/bin/env python3
"""Мутации кода: насколько тесты ловят ошибки в исполнителе, сервере и интерфейсе.

В копии репозитория по одному портится место в коде (engine.js, server.js, scenario.js, app.js) —
так, как мог бы ошибиться разработчик: строгое сравнение вместо нестрогого, забытая
проверка, таймер без остатка. Смысл условий и эффектов — выражения машины (CEL.md, ARCH-07): их порча —
в собранной машине prototype/workflow.js, так, как мог бы ошибиться тот, кто правит машину. Затем запускаются тесты API (tests/api.html), а для
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

Ещё быстрее (PROC-41): у мутаций тестами API первым идёт тест, поймавший её в прошлый раз
(tools/mutations/api-killers.json, tests/api.html?first=…) — тесты API независимы, каждый со сброса стенда;
не упал — дальше весь набор по порядку. Подсказки обновляются после каждого прогона; устаревшая подсказка
стоит только времени. Контроль без порчи идёт в общей очереди, вместе с мутациями.

Запуск из корня репозитория:
  python3 tools/check_code_mutations.py            — все мутации; на 8 ядрах — несколько минут
  python3 tools/check_code_mutations.py hold-limit — только названные
  python3 tools/check_code_mutations.py --full     — без failfast: полные прогоны
  --jobs=N — потоков (по умолчанию три четверти ядер), --shard=K/M — K-я из M частей (так делит CI)
Код выхода 1, если хоть одна мутация выжила.
"""
import html
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from urllib.parse import quote

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parallel  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Мутация тестами API → тест, который поймал её в прошлый раз (PROC-41)
KILLERS = os.path.join(ROOT, "tools", "mutations", "api-killers.json")

# (имя, файл, что заменить, на что, чем проверять: api — тесты API, ui — самопроверка, scenario — тесты исполнителя сценариев)
MUTATIONS = [
    ("active-limit", "workflow.js", "countMine(me, 'in_progress', incident.id) < limits.maxActive\"", "countMine(me, 'in_progress', incident.id) <= limits.maxActive\"", "api"),
    ("hold-limit", "workflow.js", "countMine(me, 'on_hold', incident.id) < limits.maxOnHold", "countMine(me, 'on_hold', incident.id) <= limits.maxOnHold", "api"),
    ("self-without-groups", "workflow.js", "id != '' && (id == who || (isGroup(id) && who in members(id)))", "id != '' && id == who", "api"),
    ("addressee-owner-only", "workflow.js", "x.owner != '' ? x.owner : x.assignmentGroup", "x.owner", "api"),
    ("pause-loses-remaining", "workflow.js", "\"value\": \"incident.timers[timerId].due - now > 0 ? incident.timers[timerId].due - now : 0\"", "\"value\": \"0\"", "api"),
    ("resume-restarts", "workflow.js", "\"value\": \"incident.timers[timerId].paused ? incident.timers[timerId].left : timerSec(incident, timerId, '') * 1000\"", "\"value\": \"timerSec(incident, timerId, '') * 1000\"", "api"),
    ("deadline-fires-repeatedly", "workflow.js", "t.due != 0 && t.due <= now && t.fired != t.due", "t.due != 0 && t.due <= now", "api"),
    ("if-person-any", "workflow.js", "id != '' && !isGroup(id) ? id : ''", "id", "api"),
    ("form-not-validated", "engine.js", "if (rule.required && empty) {", "if (false) {", "api"),
    # Значение поля-списка — по правилам формы машины (ARCH-09)
    ("form-list-value-unchecked", "engine.js", "if (!offered) return {", "if (false) return {", "api"),
    ("form-list-hidden-accepted", "engine.js", "          rule.visible &&\n", "", "api"),
    ("form-comment-required-ignored", "workflow.js", "\"requiredExpr\": \"closeResults.exists(i, i.id == form.resultId && i.commentRequired)\"", "\"requiredExpr\": \"false\"", "api"),
    ("form-cause-always-visible", "workflow.js", "\"visibleExpr\": \"form.resultId == 'mass'\"", "\"visibleExpr\": \"true\"", "api"),
    ("form-transfer-offers-no-access", "workflow.js", " && canAccept(t, x, '') && !(isOperator(t)", " && !(isOperator(t)", "api"),
    ("form-transfer-offers-owner", "workflow.js", " && t != addressee(x)", "", "api"),
    # Вышедшему из своей дежурной группы — не предлагать (RULE-107)
    ("form-transfer-offers-own-group-away", "workflow.js", " && !(isOperator(t) && agentState(t) == 'offline' && isSelf(who, dutyGroupOf(t)))", "", "api"),
    ("form-hold-offers-system", "workflow.js", "r.setBy != 'system'", "true", "api"),
    ("form-close-no-default", "workflow.js", "\"defaultExpr\": \"stepsFilled(incident, 'closing') ? 'processed' : ''\"", "\"defaultExpr\": \"''\"", "api"),
    ("form-close-steps-ignored", "workflow.js", "\"enabledExpr\": \"closeResults.exists(i, i.id == option && stepsOk(i, incident))\"", "\"enabledExpr\": \"true\"", "api"),
    ("form-note-ignores-ownership", "workflow.js", "\"expr\": \"ownership(me, incident) == 'other'\",\n          \"textKey\": \"workflow.form.transfer.note.1\"", "\"expr\": \"false\",\n          \"textKey\": \"workflow.form.transfer.note.1\"", "api"),
    ("close-result-any-owner", "workflow.js", " && !(x.state in i.ownerOnlyInStates && x.owner != who)", "", "api"),
    ("close-result-any-surface", "workflow.js", "(surface == '' || size(i.surfaces) == 0 || surface in i.surfaces)", "true", "api"),
    ("reopen-window-ignored", "workflow.js", "\"expr\": \"now - incident.closedAt <= limits.reopenWindowMin * 60000\"", "\"expr\": \"true\"", "api"),
    ("breach-no-flag", "workflow.js", "\"set\": \"incident.slaBreached\",\n            \"value\": \"true\"", "\"set\": \"incident.slaBreached\",\n            \"value\": \"incident.slaBreached\"", "api"),
    ("pending-target-as-owner", "workflow.js", "x.state == 'pending_acceptance' && isTarget(who, x) ? 'target' : ", "", "api"),
    ("scope-always-own", "workflow.js", "\"expr\": \"can(me, scopeOwn(me, incident, scopeRule) ? ownKey : anyKey)\"", "\"expr\": \"can(me, ownKey)\"", "api"),
    ("break-ignored", "workflow.js", "\"expr\": \"!session.states.exists(s, s.id == agentState(me) && s.readOnly)\"", "\"expr\": \"true\"", "api"),
    # «Занят» — производное: по выражению машины, смены — от хранимого (RULE-99)
    ("busy-never", "workflow.js", "\"expr\": \"countMine(me, 'in_progress', '') > 0\"", "\"expr\": \"false\"", "api"),
    ("agent-move-from-shown", "server.js", "const from = session.agentState;", "const from = sessionView().agentState;", "api"),
    # Автоэскалация — только тому, кто может принять сейчас: вышедшему — если в его группе кто-то на месте (RULE-100)
    ("escalate-to-signed-out", "workflow.js", "&& canAcceptNow(l.target, x, x.owner))", "&& canAccept(l.target, x, x.owner))", "api"),
    ("signed-out-group-ignored", "workflow.js", "canAcceptPerson(who, x) && (signedIn(who) || cel.bind(", "canAcceptPerson(who, x) && (signedIn(who) && cel.bind(", "api"),
    ("scenario-always-editable", "engine.js", "const canEditScenario = (ev) => Boolean(ev) && !firstFail(ev, W.scenarioEdit.guards);", "const canEditScenario = (ev) => Boolean(ev);", "api"),
    ("filter-ignores-ownership", "workflow.js", "\"incident.state in ['in_progress', 'on_hold'] && ownership(me, incident) == 'owner'\"", "\"incident.state in ['in_progress', 'on_hold']\"", "api"),
    ("badge-ignores-addressee", "workflow.js", "\"incident.state == 'pending_acceptance' && ownership(me, incident) == 'target' && isGroup(addressee(incident))\"", "\"incident.state == 'pending_acceptance' && ownership(me, incident) == 'target'\"", "api"),
    ("count-not-incremented", "workflow.js", "\"value\": \"incident.${field} + 1\"", "\"value\": \"incident.${field}\"", "api"),
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
    ("share-off", "scenario.js", "while (!r.completedAt && r.currentStepId && !settled.includes(r.currentStepId)) {", "while (false) {", "api"),
    ("required-skip-allowed", "scenario.js", 'if (o.skip && !canSkip(step)) return { ok: false, error: "required" };\n', "", "api"),
    ("macro-ignores-run-macro", "server.js", '      if (!actorEngine.availability("run_macro", ev).ok) return;\n', "", "api"),
    ("new-incident-oldest-version", "server.js", ".sort((a, b) => b.version - a.version)[0]", ".sort((a, b) => a.version - b.version)[0]", "api"),
    ("cursor-off-path", "server.js", "if (!body || !pathOf(ev).includes(body.stepId))", "if (!body)", "api"),
    # Набор сдвинут на час вперёд — события «из будущего»: время сравнивается с датой, не только время суток (PROC-46)
    ("fixture-times-future", "server.js", "const delta = now() - Date.parse(data.capturedAt);", "const delta = now() - Date.parse(data.capturedAt) + 3600000;", "ui"),
    ("finish-no-summary", "app.js", "  const atSummary = (ev) => runDone(ev) && !state.summaryOff.has(ev.guid) && cursorOf(ev) === pathOf(ev).length - 1;", "  const atSummary = () => false;", "ui"),
    ("close-form-offers-processed", "app.js", "const options = opts.options.filter((o) => !fullyProcessed(o.id));", "const options = opts.options;", "ui"),
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
    ("datetime-without-zone", "scenario.js", "(Z|[+-]\\d{2}:\\d{2})$/;", "(Z|[+-]\\d{2}:\\d{2})?$/;", "scenario"),
    ("datetime-not-utc", "scenario.js", '    if (step.type === "Datetime") return new Date(raw).toISOString().replace(/\\.\\d+Z$/, "Z");\n', "", "scenario"),
    ("select-required-ignored", "scenario.js", 'return v.required && v.lists.some((l) => !(value[l.id] || []).length) ? "required" : null;', "return null;", "scenario"),
    ("macro-effect-ignored", "server.js", 'res.effects.filter((e) => e.type === "macro")', 'res.effects.filter((e) => e.type === "callMacro")', "api"),
    ("ui-default-ignored", "app.js", "    return defaultOf(step);\n", "    return null;\n", "ui"),
    # PROC-33: «Далее» у обязательного Select — когда отмечено в каждом списке; вложение Image одно
    ("ui-select-partial", "app.js", 'if (step.type === "Select") return Boolean(value) && step.view.lists.every((l) => (value[l.id] || []).length > 0);', 'if (step.type === "Select") return Boolean(value) && step.view.lists.some((l) => (value[l.id] || []).length > 0);', "ui"),
    ("ui-image-keeps-first", "app.js", "setDraft(ev, file.dataset.file, atts[0].id, atts);", "const d0 = draftOf(ev, file.dataset.file);\n        setDraft(ev, file.dataset.file, (d0 && d0.value) || atts[0].id, atts.concat((d0 && d0.attachments) || []));", "ui"),
    ("draft-kept-on-leave", "app.js", "    state.drafts.delete(draftKey(ev, path[cursorOf(ev)]));\n", "", "ui"),
    ("required-steps-code-lost", "server.js", "const code = (g.errorCodes || {})[check.why && check.why[0]] || g.errorCode || \"GUARD_FAILED\";", "const code = g.errorCode || \"GUARD_FAILED\";", "api"),
    ("view-not-advanced", "server.js", "ev.viewStepId = path[Math.min(path.lastIndexOf(body.stepId) + 1, path.length - 1)];", "ev.viewStepId = body.stepId;", "api"),
    ("answers-if-match-ignored", "server.js", "const stale = versionProblem(ev, headers);\n          if (stale) return stale;\n          const res = answerStep", "const res = answerStep", "api"),
    ("if-match-optional", "server.js", "if (!sent) return problem(428,", "if (!sent) return null;\n      if (false) return problem(428,", "api"),
    ("etag-missing", "server.js", "{ status: 200, body: card(ev), headers: { ETag: etag(ev) } }", "{ status: 200, body: card(ev) }", "api"),
    ("targets-include-self", "server.js", "const list = field ? field.options : targets().filter((o) => !engine.isSelf(o.id));", "const list = field ? field.options : targets();", "api"),
    ("targets-ignore-form", "server.js", "const list = field ? field.options : targets().filter((o) => !engine.isSelf(o.id));", "const list = targets().filter((o) => !engine.isSelf(o.id));", "api"),
    ("limit-code-generic", "workflow.js", "\"fn\": \"withinActiveLimit\",\n        \"errorCode\": \"LIMIT_EXCEEDED\",", "\"fn\": \"withinActiveLimit\",\n        \"errorCode\": \"GUARD_FAILED\",", "api"),
    ("hold-timer-hidden", "server.js", "holdTimer: holdTimerState(ev),", "holdTimer: null,", "api"),
    ("colleague-acts-as-operator", "server.js", "          Object.assign({}, engineCtx, {\n            me: id,", "          Object.assign({}, engineCtx, {\n            me: ME,", "api"),
    ("operator-never-idle", "server.js", "{ me: ME, idleSec: () => (lastHeartbeat == null ? 0 : (now() - lastHeartbeat) / 1000) }", "{ me: ME, idleSec: () => 0 }", "api"),
    ("colleague-never-idle", "server.js", "idleSec: () => (colleagueIdleSince[id] == null ? 0 : (now() - colleagueIdleSince[id]) / 1000),", "idleSec: () => 0,", "api"),
    ("preferences-not-from-fixture", "server.js", "preferences: JSON.parse(JSON.stringify(fixture.operatorPreferences || {})),", "preferences: {},", "api"),
    ("media-no-positions", "server.js", ".map((id) => ({ deviceGuid: id, x: deviceSpec(id).position.x, y: deviceSpec(id).position.y, isSource: id === src })),", ".map((id) => ({ deviceGuid: id, x: 0, y: 0, isSource: id === src })),", "api"),
    ("media-plan-by-site-only", "server.js", "const placed = ids.map((id) => deviceSpec(id).position).find(Boolean);", "const placed = null;", "api"),
    ("ui-map-ignores-markers", "app.js", "const markers = ordered.map((m) => deviceMarker(m, { source: m.deviceGuid === source, active: m.deviceGuid === state.activeCam })).join(\"\");", "const markers = \"\";", "ui"),
    ("number-is-guid", "server.js", "        number: ev.number,", "        number: ev.id,", "api"),
    ("event-type-guid-is-id", "server.js", "!String(q.eventTypeGuid).split(\",\").includes(e.typeGuid)", "!String(q.eventTypeGuid).split(\",\").includes(e.typeId)", "api"),
    ("setting-is-ignored", "workflow.js", "\"expr\": \"settingKey == value\"", "\"expr\": \"true\"", "api"),
    ("owner-group-ignored", "workflow.js", "\"expr\": \"(incident.owner != '' && dutyGroupOf(incident.owner) != '') == expected\"", "\"expr\": \"true\"", "api"),
    ("offline-without-scheduler", "server.js", "            session.agentState = \"offline\";\n            session.reasonId = null;\n            const fired = runSchedulerForOwnChange();", "            session.agentState = \"offline\";\n            session.reasonId = null;\n            const fired = [];", "api"),
    # Карточку увели (BUG-105): событие — только при открытой карточке и не за свой перерыв или выход
    ("evict-any-card", "server.js", "&& session.openIncidentGuid === ev.id) emit(", ") emit(", "api"),
    ("evict-own-change", "server.js", "if (who === ME && !ownAgentStateChange && ", "if (who === ME && ", "api"),
    ("visibility-ignored", "server.js", "let list = events.filter((e) => canSee(e) && filters.set(e, engine.queueFilters(e)).get(e).length);", "let list = events.filter((e) => filters.set(e, engine.queueFilters(e)).get(e).length);", "api"),
    ("lists-show-linked", "server.js", "let list = events.filter((e) => canSee(e) && filters.set(e, engine.queueFilters(e)).get(e).length);", "let list = events.filter((e) => canSee(e) && filters.set(e, engine.queueFilters(e)).get(e));", "api"),
    # Объединение (§11): основной, срок, закрытие привязанных; вкладка — фильтр; панель выборки
    ("merge-primary-first", "server.js", "const pickPrimary = (list) => engine.mergePrimary([...list].sort(byNumber));", "const pickPrimary = (list) => list[0] || null;", "api"),
    ("merge-primary-click-order", "server.js", "engine.mergePrimary([...list].sort(byNumber))", "engine.mergePrimary(list)", "api"),
    ("merge-primary-occurred-lost", "engine.js", "priority: ev.priority, occurredAt: ev.occurredAt, state: ev.state", "priority: ev.priority, state: ev.state", "api"),
    ("ui-linked-chip-hidden", "app.js", "if (!e.linkedCount) return \"\";", "return \"\";", "ui"),
    ("ui-selection-bar-hidden", "app.js", "bar.hidden = !n;", "bar.hidden = true;", "ui"),
    ("card-ignores-access", "server.js", "      return ev && canSee(ev) ? ev : null;", "      return ev;", "api"),
    ("stream-leaks-hidden", "server.js", "      if (ev && !canSee(ev)) return;\n", "", "api"),
    ("tree-ignores-access", "server.js", ".filter((c) => c.isDevice && myDevices.has(c.id))", ".filter((c) => c.isDevice)", "api"),
    ("counters-ignore-access", "server.js", "const list = visible({});", "const list = events;", "api"),
    ("target-access-ignored", "workflow.js", "\"expr\": \"form.targetId == '' || hasAccess(form.targetId, incident)\"", "\"expr\": \"true\"", "api"),
    ("group-access-all-members", "workflow.js", "members(who).exists(m, access(m, x))", "members(who).all(m, access(m, x))", "api"),
    ("level-cannot-accept-ignored", "workflow.js", "l.target != addressee(x) && canAcceptNow(l.target, x, x.owner)", "l.target != addressee(x)", "api"),
    # Уровень, где принять может только тот, у кого инцидент уже есть, пропускается (RULE-93)
    ("level-current-addressee-ignored", "workflow.js", "l.target != addressee(x) && canAcceptNow(", "canAcceptNow(", "api"),
    ("level-group-owner-counted", "workflow.js", "canAcceptNow(l.target, x, x.owner)", "canAcceptNow(l.target, x, '')", "api"),
    ("group-accept-except-ignored", "workflow.js", "m != except && signedIn(m) && canAcceptPerson(m, x)", "signedIn(m) && canAcceptPerson(m, x)", "api"),
    ("tick-array-order", "engine.js", "if (!next || c.moment < next.moment) next = c;", "if (!next) next = c;", "api"),
    ("tick-effects-at-now", "engine.js", "        at = runAt;\n        let facts = null;", "        at = null;\n        let facts = null;", "api"),
    ("admin-read-without-right", "server.js", "        \"/operator/admin/duty-groups\",\n        () => {\n          if (!can(\"incident:schema:admin\")) return problem(403, \"PERMISSION_DENIED\", [\"workflow.error.no_schema_admin\"]);", "        \"/operator/admin/duty-groups\",\n        () => {", "api"),
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
    ("expired-resolution-refires", "workflow.js", "\"value\": \"left == 0 && incident.timers[timerId].fired != 0 ? incident.timers[timerId].fired : now + left\"", "\"value\": \"now + left\"", "api"),
    ("cannot-accept-ignored", "workflow.js", "\"expr\": \"addressee(incident) != '' && canAccept(addressee(incident), incident, '') == expected\"", "\"expr\": \"false\"", "api"),
    ("lost-access-ignored", "workflow.js", "\"expr\": \"addressee(incident) != '' && hasAccess(addressee(incident), incident) == expected\"", "\"expr\": \"false\"", "api"),
    ("group-roles-ignored", "server.js", "const byRole = OPERATORS.filter((o) => rolesOf(o.id).some((r) => (group.roles || []).includes(r))).map((o) => o.id);", "const byRole = [];", "api"),
    ("duty-group-last", "workflow.js", "size(gs) > 0 ? gs[0] : ''", "size(gs) > 0 ? gs[size(gs) - 1] : ''", "api"),
    ("group-shift-ignored", "server.js", "(op.group ? membersOf(op).some((m) => present({ id: m })) :", "(op.group ? true :", "api"),
    ("agent-state-ignored", "server.js", ": engine.onDuty(op.id));", ": true);", "api"),
    ("ui-bulk-failures-hidden", "app.js", "toast(res.failed.length ? `${okText} ", "toast(false ? `${okText} ", "ui"),
    ("ui-bulk-transfer-copy", "app.js", "title: t(form.bulkTitleKey, { n })", "title: t(form.titleKey)", "ui"),
    ("external-effects-dropped", "server.js", "journalEntries: journalView(ev).slice(before), externalEffects, canceledTimerTrigger", "journalEntries: journalView(ev).slice(before), externalEffects: [], canceledTimerTrigger", "api"),
    ("queue-not-sorted", "server.js", "      return list.sort((a, b) => cmp(a, b) || byNumber(a, b));", "      return list;", "api"),
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
    ("timer-after-system-in-jump", "engine.js", "Math.max(next.moment + GRACE_MS, s.last.get(ev.id) || 0), sysAt)", "Math.max(next.moment + GRACE_MS, s.last.get(ev.id) || 0), ctx.now())", "api"),
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
    # «Далее» всегда на месте: с последнего шага пройденного сценария — на «Итог», на вкладке привязанных — серая (RULE-89)
    ("next-not-to-summary", "app.js", "    return i < path.length - 1 || (runDone(ev) && !atSummary(ev));\n  }", "    return i < path.length - 1;\n  }", "ui"),
    ("next-on-linked-tab", "app.js", 'const canNext = tab === "scenario" && !summary && canGoNext(ev, i, editable);', "const canNext = !summary && canGoNext(ev, i, editable);", "ui"),
    ("back-after-next", "styles.css", ".scenario-actions-end {\n  grid-area: next;\n  justify-self: end;\n  display: flex;\n", ".scenario-actions-end {\n  grid-area: next;\n  justify-self: end;\n  display: flex;\n  flex-direction: row-reverse;\n", "ui"),
    ("sort-newest-as-oldest", "workflow.js", "\"-incident.priority\",\n        \"-incident.occurredAt\"", "\"-incident.priority\",\n        \"incident.occurredAt\"", "api"),
    ("sort-reaction-ignores-running", "workflow.js", "\"timerRuns(incident, 'reaction') ? 0 : 1\"", "\"0\"", "api"),
    ("sort-ignores-keys", "server.js", "for (let i = 0; i < ka.length; i++) if (ka[i] !== kb[i]) return ka[i] - kb[i];", "", "api"),
    ("agent-move-any", "server.js", "if (!move || !target) return problem(409,", "if (!target) return problem(409,", "api"),
    ("agent-reason-optional", "server.js", "if (target.requiresReason && !W.session.breakReasons.some((r) => r.id === body.reasonId))", "if (false)", "api"),
    ("agent-break-from-offline", "workflow.js", "\"noteKey\": \"workflow.session.transition.break.note\",\n        \"from\": [\n          \"ready\"\n        ]", "\"noteKey\": \"workflow.session.transition.break.note\",\n        \"from\": [\n          \"ready\",\n          \"offline\"\n        ]", "api"),
    ("run-all-skips-check", "engine.js", "        if (!a.ok) return { ok: false, why: a.why, guard: a.guard, notFrom: a.notFrom, ev };", "", "api"),
    ("card-note-ignores-actions", "server.js", "base.actions.filter((a) => a.enabled).map((a) => a.id)", "base.actions.map((a) => a.id)", "api"),
    ("card-note-not-sent", "server.js", "        note: noteView(ev, base.actions.filter((a) => a.enabled).map((a) => a.id)),\n", "", "api"),
    ("ui-card-note-hidden", "app.js", "    const n = ev && ev.note;\n    if (!n) return \"\";", "    return \"\";", "ui"),
    ("stream-addressed-to-me-lost", "server.js", "addressedToMe: engine.isSelf(engine.addressee(ev)),", "addressedToMe: false,", "api"),
    ("summary-addressee-lost", "server.js", "группа (§8.1)\n        addressee: actorRef(engine.addressee(ev)),", "группа (§8.1)\n        addressee: null,", "api"),
    ("linked-count-ignores-access", "server.js", "linkedCount: events.filter((e) => e.linkedTo === ev.id && canSee(e)).length,", "linkedCount: events.filter((e) => e.linkedTo === ev.id).length,", "api"),
    ("schema-version-literal", "server.js", "        schemaVersion: W.schema.version,", "        schemaVersion: 3,", "api"),
    ("ui-bulk-done-generic", "app.js", "const done = tr && tr.ui && tr.ui.bulkDoneKey;", "const done = null;", "ui"),
    ("ui-session-note-lost", "app.js", "return m && m.noteKey ? t(m.noteKey, vars || {}) : \"\";", "return \"\";", "ui"),
    ("ui-detached-state-lost", "app.js", "return tr && STATES[tr.to] ? lbl(STATES[tr.to]) : \"\";", "return \"\";", "ui"),
    ("notify-self", "workflow.js", "\"if\": \"whom != '' && whom != actor\"", "\"if\": \"whom != ''\"", "api"),
    ("recipients-ignore-duty", "workflow.js", ".filter(m, onDuty(m) && access(m, x))", ".filter(m, access(m, x))", "api"),
    ("recipients-ignore-access", "workflow.js", ".filter(m, onDuty(m) && access(m, x))", ".filter(m, onDuty(m))", "api"),
    ("alert-no-recipient-silent", "workflow.js", "\"emptyLog\": \"alert ? alerts.noRecipientLog : ''\"", "\"emptyLog\": \"''\"", "api"),
    ("alert-by-recipient", "workflow.js", "\"alert\": \"alert\",", "\"alert\": \"whom == alerts.target\",", "api"),
    ("alert-not-delivered", "server.js", 'if (alert && recipients.includes(ME)) emit("incident.alert"', 'if (false) emit("incident.alert"', "api"),
    ("tree-counts-linked", "server.js", 'const isOpen = (e) => engine.inQueueFilter(e, "open");', "const isOpen = (e) => !isDone(e);", "api"),
    ("selection-single-stub", "app.js", "(state.checked.size === 1 ? await api.get(`/operator/incidents/${enc(first)}`) : { guid: first })", "{ guid: first }", "ui"),
    ("window-mark-kept-on-failure", "engine.js", "if (canceled) ev.firedTimers = canceled.firedBefore;", "", "api"),
    ("merge-two-transactions", "engine.js", "const applied = applySteps(steps, ME);", "const applied = applySteps(steps.slice(0, 1), ME); if (applied.ok && steps[1]) { const r2 = applySteps(steps.slice(1), ME); if (!r2.ok) return r2; applied.steps.push(r2.steps[0]); }", "api"),
    ("agent-state-same-applied", "server.js", "if (to === from) return { status: 200, body: { session: sessionView(), affectedIncidents: [] } };", "", "api"),
    ("bulk-form-from-card", "app.js", "const ev = Object.assign({}, row, { actions: act ? [act] : [] });", "const ev = row.actions ? row : await api.get(`/operator/incidents/${enc(first)}`);", "ui"),
    ("selection-form-first-only", "server.js", "          .filter((o) => others.every((x) => x.options.some((y) => y.id === o.id)))\n", "", "api"),
    ("blocking-ignores-units", "server.js", "const blocking = events.find((e) => active.has(e.id));", "const blocking = null;", "api"),
    ("counters-always", "server.js", 'body: treeView(TREE, q.withCounters === "true")', "body: treeView(TREE, true)", "api"),
    ("journal-not-paged", "server.js", "body: { items: all.slice((n - 1) * size, n * size), total: all.length } }", "body: { items: all, total: all.length } }", "api"),
    ("group-settled-per-member", "server.js", "            if (r.status === 200) {\n              done.push(ev);", "            if (r.status === 200) {\n              settleGroups();\n              done.push(ev);", "api"),
    ("access-lost-not-sent", "server.js", "if (wasMine.has(id) && !canSee(ev)) {", "if (false) {", "api"),
    ("target-can-accept-ignored", "workflow.js", "\"expr\": \"form.targetId == '' || canAccept(form.targetId, incident, '')\"", "\"expr\": \"true\"", "api"),
    ("accept-right-ignored", "workflow.js", "can(m, 'incident:accept') && access(m, x)", "access(m, x)", "api"),
    ("stream-id-repeats", "server.js", "const message = Object.assign({ id: String(++seq) }, body);", "const message = Object.assign({ id: String(seq) }, body);", "api"),
    ("ui-field-rules-ignore-choice", "app.js", "return r.dependsOn ? r.byValue[values[r.dependsOn] || \"\"] || r.byValue[\"\"] : r;", "return r;", "ui"),
    ("ui-esc-keeps-modal", "app.js", "if (e.key !== \"Escape\") return;", "return;", "ui"),
    ("selection-reason-generic", "server.js", "if (!ok && !reason && failed && failed[1].why && (mode.allowed || list.length < 2)) {", "if (false) {", "api"),
    ("selection-reason-irrelevant-first", "server.js", "const failed = avail.find(([, a]) => !a.ok && !a.hidden) || avail.find(([, a]) => !a.ok);", "const failed = avail.find(([, a]) => !a.ok);", "api"),
    ("selection-visible-always", "server.js", "const visible = mode.mode === \"merge\" ? avail.some(([, a]) => !a.notFrom) : avail.some(([, a]) => !a.hidden);", "const visible = true;", "api"),
    ("selection-merge-visible-always", "server.js", "mode.mode === \"merge\" ? avail.some(([, a]) => !a.notFrom) :", "mode.mode === \"merge\" ? true :", "api"),
    ("ui-combo-typing-ignored", "app.js", "if (state.tbOpen === input.dataset.tbToggle) return comboNarrow(input);", "if (state.tbOpen === input.dataset.tbToggle) return;", "ui"),
    ("ui-combo-enter-ignored", "app.js", "    } else if (e.key === \"Enter\" && first) {\n      e.preventDefault();\n      first.click();", "    } else if (e.key === \"Enter\" && first) {\n      e.preventDefault();", "ui"),
    ("ui-filter-combo-typing-ignored", "app.js", "if (filt.open === input.dataset.msToggle) return comboNarrow(input);", "if (filt.open === input.dataset.msToggle) return;", "ui"),
    ("ui-filter-dialog-stale-language", "app.js", "      filt.focusSearch = false;\n      renderFilter();\n    }\n    syncLocale", "      filt.focusSearch = false;\n    }\n    syncLocale", "ui"),
    ("ui-take-as-one-stays-in-queue", "app.js", "    navigate(merge.ui.navigate);\n", "", "ui"),
    ("detach-all-partial", "server.js", "          const r = engine.runAll(detach.id, linked, {}, { surface: \"card\" });\n          if (!r.ok)", "          const r = engine.runAll(detach.id, linked.slice(0, 1), {}, { surface: \"card\" });\n          if (!r.ok)", "api"),
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
    ("ui-actions-jump-on-tab", "app.js", 'id="stepBack" ${offAttr(!(tab !== "scenario" || (i === 0 && !summary)), backWhy(tab))}', 'id="stepBack" ${tab !== "scenario" ? "hidden" : offAttr(!(i === 0 && !summary), backWhy(tab))}', "ui"),
    # «Взял — вернул» эскалацию не откладывает (RULE-104)
    ("release-restarts-reaction", "workflow.js", '"reaction",\n            "continue"', '"reaction"', "api"),
    ("stop-forgets-left", "workflow.js", '"value": "keep ? incident.timers[timerId].due - now : 0"', '"value": "0"', "api"),
    # «Переоткрыть» снимает закрытие целиком (RULE-103)
    ("reopen-keeps-closed-at", "workflow.js", '"closedAt",\n            "0"', '"closedAt",\n            "closedAt"', "api"),
    # Файл тестов с ошибкой в первой строке не загрузился — прогон красный, а не без его тестов (PROC-53)
    ("test-file-load-error", "../tests/api-junction.js", "/* Тесты API стыка машины инцидента", "}\n/* Тесты API стыка машины инцидента", "api"),
    # Системные ветки (PROC-49): молчание возвращает в очередь и отложенное перерывом; адресат вышел без дежурной
    # группы — реакция продолжается с того же срока
    ("idle-release-skips-break", "workflow.js", '[\n              "break",\n              "no_link"\n            ]', '[\n              "no_link"\n            ]', "api"),
    ("signed-out-queue-restarts-reaction", "workflow.js", '"fn": "appendLog",\n          "args": [\n            "workflow.journal.addressee_signed_out_to_queue"\n          ]', '"fn": "startTimer",\n          "args": [\n            "reaction"\n          ]\n        },\n        {\n          "kind": "transactional",\n          "fn": "appendLog",\n          "args": [\n            "workflow.journal.addressee_signed_out_to_queue"\n          ]', "api"),
    # «Переоткрыть» — норматив закрытия заново: полный или из настройки, причина сбоя снимается (PROC-48)
    ("reopen-resolution-continues", "workflow.js", '"fn": "restartTimer",\n          "args": [\n            "resolution",\n            "limits.reopenResolutionSec"\n          ]', '"fn": "startTimer",\n          "args": [\n            "resolution"\n          ]', "api"),
    ("reopen-setting-ignored", "workflow.js", '"resolution",\n            "limits.reopenResolutionSec"', '"resolution",\n            "0"', "api"),
    ("reopen-keeps-cause", "workflow.js", '"closeCauseId",\n            "\'\'"', '"closeCauseId",\n            "closeCauseId"', "api"),
    # «Передать», когда передать некому (BUG-85)
    ("transfer-nobody-allowed", "workflow.js", "\"expr\": \"transferTargets().exists(", "\"expr\": \"true || transferTargets().exists(", "api"),
    # Ключ повтора и версии отмеченных (BUG-84)
    ("idempotency-off", "server.js", "if (idem && answered.has(idem)) {", "if (false) {", "api"),
    ("bulk-versions-unchecked", "server.js", "if (changedSince(ev, body.expectedVersions)) return failed.push(", "if (false) return failed.push(", "api"),
    ("merge-versions-unchecked", "server.js", "const stale = list.find((e) => changedSince(e, expected));", "const stale = null;", "api"),
    ("ui-bulk-no-versions", "app.js", "surface, expectedVersions: expectedVersions(guids), idempotencyKey", "surface, idempotencyKey", "ui"),
    # Догон в общем порядке по времени (ARCH-13)
    ("tick-per-incident-since-now", "engine.js", "s.since.has(key) ? s.since.get(key) : s.lastRun != null ? s.lastRun : ctx.now()", "ctx.now()", "api"),
    # Уточнения норматива — только по признакам overridesBy (ARCH-11)
    ("overrides-by-ignored", "workflow.js", "overrideAllowed(t, o) && overrideMatches(x, o)", "overrideMatches(x, o)", "api"),
    # Отсчёт — по времени сервера (BUG-103)
    ("ui-clock-ignores-server", "app.js", "const serverNow = () => Date.now() + skewMs;", "const serverNow = () => Date.now();", "ui"),
    # Одно слово — одно число: нижнее меню — как у «Очередь» (BUG-100)
    ("ui-nav-count-all-open", "app.js", '$("navQueueCount").textContent = String(store.page.total || 0);', '$("navQueueCount").textContent = String(store.counters.open || 0);', "ui"),
    # Пустой поиск в дереве — по узлам на экране (BUG-92)
    ("ui-tree-empty-by-class", "app.js", 'filter((n) => n.dataset.id !== "all" && onScreen(n));', 'filter((n) => n.dataset.id !== "all" && !n.classList.contains("hidden"));', "ui"),
    # «Далее» и «Назад» недоступны — с причиной по нажатию (BUG-91)
    ("ui-step-nav-silent", "app.js", 'if (explainIfOff(e.target.closest("#stepNext"))) return;', "", "ui"),
    ("ui-step-nav-no-reason", "app.js", 'const offAttr = (on, why) => (on ? "" : `aria-disabled="true" title="${escapeHtml(why)}"`);', 'const offAttr = (on, why) => (on ? "" : "disabled");', "ui"),
    ("search-ignores-linked", "server.js", "if (!hit(e, needle) && !linkedHits(e, needle).length) return false;", "if (!hit(e, needle)) return false;", "api"),
    ("linked-focus-page-ignored", "server.js", "const idx = q.focusGuid ? all.findIndex((e) => e.id === q.focusGuid) : -1;", "const idx = -1;", "api"),
    ("ui-search-opens-scenario", "app.js", "workTab: foundLinked(ev.guid).length ? \"linked\" : \"scenario\"", "workTab: \"scenario\"", "ui"),
    ("ui-search-found-page-ignored", "app.js", "    if (page && page.focusPage && page.focusPage !== state.linkedPage) {", "    if (false) {", "ui"),
    # Текущий шаг основного отвечен только в сценарии с петлёй — такого в эталонном наборе нет, ловит тест исполнителя
    ("copy-answers-overwrites", "scenario.js", "if (!entry || entry.skipped || r.state[id] || !src", "if (!entry || entry.skipped || !src", "scenario"),
    ("copy-answers-no-log", "engine.js", "            if (n && a.logKey) ctx.log(p, cur.actor, a.logKey, { number: target.number, n }, now());\n", "", "api"),
    ("relink-closed-too", "workflow.js", "\"in\": \"linkedOf(incident.id).filter(e, !isDone(e))\"", "\"in\": \"incidents.filter(e, e.linkedTo == incident.id)\"", "api"),
    ("relink-no-log", "workflow.js", "\"incident\": \"c\",\n                      \"key\": \"logKey\"", "\"incident\": \"c\",\n                      \"key\": \"''\"", "api"),
    ("transfer-restarts-reaction", "workflow.js", "ifStopped && incident.timers[timerId].due != 0", "false", "api"),
    ("level0-last-norm", "workflow.js", "x.escalationLevel > 0 && size(escalation.levels) > 0 ?", "size(escalation.levels) > 0 ?", "api"),
    ("detach-before-accept", "workflow.js", "(ownership(me, ps[0]) == 'owner' || unowned(ps[0]))", "(ps[0].owner == me || unowned(ps[0]))", "api"),
    # Срок группы — самый ранний; нарушения основного — и привязанным (RULE-97)
    ("tighten-ignored", "workflow.js", "size(ps) > 0 && leftOf(incident, timerId, now) >= 0 && !spent(incident, timerId, now) && !spent(ps[0], timerId, now)", "false", "api"),
    ("tighten-spent-counted", "workflow.js", " && !spent(incident, timerId, now) && !spent(ps[0], timerId, now)", " && !spent(ps[0], timerId, now)", "api"),
    ("tighten-new-primary-skipped", "workflow.js", "\"set\": \"p.timers[timerId].left\",\n                            \"value\": \"left\"", "\"set\": \"p.timers[timerId].left\",\n                            \"value\": \"t.left\"", "api"),
    ("detach-keeps-own-deadline", "workflow.js", "\"value\": \"leftOf(ps[0], timerId, now)\"", "\"value\": \"incident.timers[timerId].left\"", "api"),
    ("detach-spent-lost", "workflow.js", "\"if\": \"leftOf(ps[0], timerId, now) == 0\"", "\"if\": \"false\"", "api"),
    ("detach-window-not-spent", "workflow.js", "\"if\": \"leftOf(ps[0], timerId, now) == 0\"", "\"if\": \"spent(ps[0], timerId, now)\"", "api"),
    ("action-not-activity", "server.js", "      if (acting) lastHeartbeat = now();\n", "", "api"),
    ("breach-not-shared", "workflow.js", "\"in\": \"groupMembersAt(incident, deadline)\"", "\"in\": \"[]\"", "api"),
    ("window-breach-not-shared", "engine.js", "canceled.tr.effects.filter((x) => x.fn === \"recordBreach\")", "[]", "api"),
    # Нарушение группы — тем, кто был в группе в момент срока (BUG-73)
    ("share-ignores-join-time", "workflow.js", "(e.linkedTo == p.id && !isDone(e) && e.linkedAt <= at)", "(e.linkedTo == p.id && !isDone(e))", "api"),
    ("share-skips-left", "workflow.js", " || (e.leftGroup.primaryId == p.id && e.leftGroup.linkedAt <= at && e.leftGroup.at >= at)", "", "api"),
    ("link-time-not-set", "workflow.js", "\"set\": \"incident.linkedAt\",\n            \"value\": \"now\"", "\"set\": \"incident.linkedAt\",\n            \"value\": \"0\"", "api"),
    ("left-group-not-recorded", "workflow.js", "\"value\": \"{'primaryId': incident.linkedTo, 'linkedAt': incident.linkedAt, 'at': now}\"", "\"value\": \"incident.leftGroup\"", "api"),
    ("relink-forgets-group", "workflow.js", "\"value\": \"{'primaryId': c.linkedTo, 'linkedAt': c.linkedAt, 'at': now}\"", "\"value\": \"c.leftGroup\"", "api"),
    # Журнал срока группы (RULE-98)
    ("group-breach-no-log", "workflow.js", "\"key\": \"groupLogKey\"", "\"key\": \"''\"", "api"),
    ("deadline-no-log", "workflow.js", "\"key\": \"logKey\",\n                          \"vars\": \"{'number': incident.number}\",\n                          \"once\"", "\"key\": \"''\",\n                          \"vars\": \"{'number': incident.number}\",\n                          \"once\"", "api"),
    ("deadline-log-always", "workflow.js", "\"if\": \"left < was\"", "\"if\": \"true\"", "api"),
    ("deadline-log-twice", "workflow.js", "\"once\": \"true\"", "\"once\": \"false\"", "api"),
    ("linked-timer-shown", "server.js", "      if (isDone(ev) || ev.state === \"linked\") return null;", "      if (isDone(ev)) return null;", "api"),
    ("linked-version-not-bumped", "server.js", "      onBreachShared: (ev) => touch([ev]),", "      onBreachShared: () => {},", "api"),
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
    ("reopen-unlink-no-log", "workflow.js", "\"key\": \"primaryLogKey\"", "\"key\": \"''\"", "api"),
    ("linked-access-ignored", "workflow.js", "who != '' && hasAccess(who, incident) == expected", "who != '' && true == expected", "api"),
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
    ("active-limit-null-blocks", "workflow.js", "\"expr\": \"limits.maxActive == 0 || countMine(", "\"expr\": \"countMine(", "api"),
    ("bulk-limit-unchecked", "server.js", "if (W.limits.maxBulk != null && guids.length > W.limits.maxBulk) return problem(", "if (false) return problem(", "api"),
    # Лимит выборки и у «Взять в работу» на выборке (BUG-83)
    ("merge-limit-unchecked", "server.js", "if (tooLarge(list)) return problem(", "if (false) return problem(", "api"),
    ("selection-merge-limit-ignored", "server.js", "else if (tooLarge(list)) reason", "else if (false) reason", "api"),
    ("selection-truncated-on-null", "server.js", "const max = W.limits.maxBulk;\n      let list = [];", "const max = W.limits.maxBulk ?? 0;\n      let list = [];", "api"),
    ("ui-status-always-of-n", "app.js", 'LIMITS.maxActive == null ? t("Открытых: {n} · у меня: {a}, отложено: {h}", queueVars) : t(', "t(", "ui"),
    ("ui-null-key-ignored", "app.js", 'if (v == null) return nullKey ? te(nullKey) : "—";', 'if (v == null) return "—";', "ui"),
    # Плашка сценария в очереди — название, не счёт шагов (§14.5)
    ("ui-scenario-chip-count", "app.js", '<span class="event-prog">${escapeHtml(scenarioTitle(e))}</span>', '<span class="event-prog">${prog.filled}/${prog.total}</span>', "ui"),
    ("ui-scenario-chip-only-answered", "app.js", "${prog.total ? `<span class=\"event-prog\">", "${prog.filled ? `<span class=\"event-prog\">", "ui"),
    ("ui-scenario-untitled-empty", "app.js", 't(ev.scenarioTitle || "Без названия")', 't(ev.scenarioTitle || "")', "ui"),
    # Автоматические переходы и запрос оператора (§14.3, ARCH-10): догон перед запросом (BUG-82), системные — сразу после
    ("catchup-before-request-off", "server.js", "if (acting) runScheduler();", "if (false) runScheduler();", "api"),
    ("settle-after-request-off", "server.js", "if (acting && res.status < 300 && runScheduler().length && res.again)", "if (false && res.again)", "api"),
    # Карточку увели — уведомление с причиной (BUG-86)
    ("ui-evict-silent", "app.js", '} else if (msg.type === "incident.card_evicted" && !mine && state.selectedId === msg.incidentGuid) {', "} else if (false) {", "ui"),
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


def run_tests(site, kind, profile, failfast=False, first=None):
    """(прошли ли, строки FAIL, запустились ли, имя первого упавшего теста API или None)"""
    shutil.rmtree(profile, ignore_errors=True)
    first_failed = None
    if kind == "api":
        query = "&".join((["failfast"] if failfast else []) + ([f"first={quote(first)}"] if first else []))
        page = chrome(f"file://{site}/tests/api.html" + (f"?{query}" if query else ""), profile, 120000)
        passed = 'data-apitest="pass"' in page
        log = re.search(r'<pre id="apitest-log">(.*?)</pre>', page, re.S)
        m = re.search(r'data-apitest-first-failed="([^"]*)"', page)
        first_failed = html.unescape(m.group(1)) if m and m.group(1) else None
    elif kind == "scenario":
        page = chrome(f"file://{site}/tests/scenario.html", profile, 60000)
        passed = 'data-scenariotest="pass"' in page
        log = re.search(r'<pre id="scenariotest-log">(.*?)</pre>', page, re.S)
    else:
        # Бюджет — как у самопроверки в CI, с запасом втрое (PROC-31)
        page = chrome(f"file://{site}/prototype/index.html?selftest" + ("&failfast" if failfast else ""), profile, 180000)
        passed = 'data-selftest="pass"' in page
        log = re.search(r'<pre id="selftest-log"[^>]*>(.*?)</pre>', page, re.S)
    fails = [line for line in (log.group(1).splitlines() if log else []) if line.startswith("FAIL")]
    return passed, fails, bool(log), first_failed


def check(site, profile, mutation, full, killers):
    """Одна мутация в своей копии прототипа: строка вердикта, выжила ли и поймавший тест API."""
    name, file, old, new, kind = mutation
    path = os.path.join(site, "prototype", file)
    with open(path, encoding="utf-8") as f:
        code = f.read()
    if code.count(old) != 1:
        return f"STALE {name}: в {file} не найдено место порчи — обновите мутацию", True, None
    with open(path, "w", encoding="utf-8") as f:
        f.write(code.replace(old, new))
    try:
        # До первого падения: не упало ничего — значит, пройден весь набор. Первым — поймавший в прошлый раз
        hint = None if full else killers.get(name)
        passed, fails, ran, killer = run_tests(site, kind, profile, failfast=not full, first=hint)
    finally:
        with open(path, "w", encoding="utf-8") as f:
            f.write(code)
    if not ran:
        return f"KILLED {name} [{kind}] — тесты не запустились (ошибка JS)", False, None
    if passed:
        return f"SURVIVED {name} [{kind}] — тесты прошли с испорченным {file}", True, None
    return f"KILLED {name} [{kind}] — {fails[0][:110] if fails else 'тесты упали'}", False, killer


def main():
    wanted, jobs, shard, shards = parallel.options()
    full = "--full" in sys.argv
    todo = parallel.part([m for m in MUTATIONS if not wanted or m[0] in wanted], shard, shards)
    try:
        with open(KILLERS, encoding="utf-8") as f:
            killers = json.load(f)
    except FileNotFoundError:
        killers = {}
    found = {}
    work = tempfile.mkdtemp(prefix="im-code-mut-")
    tasks = queue.Queue()
    # Контроль: без порчи тесты проходят — полный прогон; при делении на части — в первой. Первым в очереди,
    # самый долгий (самопроверка) — раньше всех: идёт вместе с мутациями, а не после них
    if not wanted and shard == 1:
        for kind in ("ui", "api", "scenario"):
            tasks.put(("BASE", kind))
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
            if m[0] == "BASE":
                passed, fails, _, _ = run_tests(site, m[1], profile)
                if not passed:
                    with lock:
                        survived.append(f"BASE {m[1]}")
                        print(f"BASE [{m[1]}] — без порчи тесты не проходят: {fails[:2]}", flush=True)
                continue
            line, bad, killer = check(site, profile, m, full, killers)
            with lock:
                print(line, flush=True)
                if bad:
                    survived.append(m[0])
                if killer:
                    found[m[0]] = killer

    try:
        threads = [threading.Thread(target=worker, args=(n,)) for n in range(min(jobs, tasks.qsize()) or 1)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
    finally:
        shutil.rmtree(work, ignore_errors=True)
    # Подсказки — на следующий прогон: поймавшие сейчас; полный список — без мутаций, которых больше нет
    known = {m[0] for m in MUTATIONS if m[4] == "api"}
    updated = {k: v for k, v in dict(killers, **found).items() if k in known}
    if updated != killers:
        with open(KILLERS, "w", encoding="utf-8") as f:
            json.dump(updated, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write("\n")
    part = f" (часть {shard} из {shards}: {len(todo)} мутаций)" if shards > 1 else ""
    print(f"Выживших мутаций кода: {len(survived)}{part}")
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
