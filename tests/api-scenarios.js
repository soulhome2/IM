/* Сценарные тесты API: «состояние, запрос → новое состояние, владелец, таймеры, журнал, коды
   ошибок». Это исполняемая спецификация операторской части: те же проверки должен проходить
   и бэкенд. Номера разделов — из Specification/State_rules/States rules IM.md. */
(() => {
  const { test, makeEnv, formFor, fullAnswers, actionOf, assert, enc } = IMTest;
  const ME = "me";
  const W = window.IM_WORKFLOW;
  // Окно после дедлайна (RULE-63): переход по таймеру — через graceSec после дедлайна
  const GRACE = ((W.invariants || {}).manualWinsOverTimer || {}).graceSec || 0;

  // Стенд со своей копией схемы или набора (PROC-13): отличающиеся разделы уходят в POST /test/reset
  // как JSON Merge Patch — так тест идёт и против встроенного сервера, и против бэкенда
  const changed = (base, copy) =>
    copy ? Object.fromEntries(Object.keys(copy).filter((k) => JSON.stringify(copy[k]) !== JSON.stringify(base[k])).map((k) => [k, copy[k]])) : undefined;
  const standWith = ({ workflow, fixture }) => makeEnv({ workflowPatch: changed(W, workflow), fixturePatch: changed(window.IM_FIXTURE, fixture) });
  const lastJournal = (card) => card.journal[card.journal.length - 1];
  // Запись журнала — ключ каталога (§14.9, RULE-66): для проверок по смыслу — её русская строка
  const jt = (entry) => window.IM_STRINGS.ru[entry.templateKey] || entry.templateKey;

  // Инцидента с таким идентификатором нет: формат верный, записи нет
  const UNKNOWN = "10000000-0000-4000-8000-000000000000";

  // Справочник приоритетов (§2.5) — данные набора: уровни по числу, первым — самый срочный. Тесты не
  // знают уровни по имени: берут их из справочника
  const LEVELS = window.IM_FIXTURE.priorities.map((p) => p.value).sort((a, b) => b - a);
  const TOP = LEVELS[0];
  // Новое событие пожара самого срочного уровня — их в демо два, однотипная пара для группы (§11)
  const newFire = (env) => env.find((e) => e.state === "new" && e.eventType.id === "fire" && e.priority === TOP);

  /* ===== Взять, лимит активных (§6.1, §10.2) ===== */

  test("Взять: в работе у меня, норматив реакции снят, норматив закрытия идёт, запись в журнале", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    assert.eq(inc.timer.id, "reaction", "до взятия идёт");
    assert.ok(inc.timer.running, "реакция идёт");
    const res = await env.act(inc.guid, "claim", {}, "queue", "new");
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.state, "in_progress", "состояние");
    assert.ok(Number(c.version) > Number(inc.version), `версия выросла: ${inc.version} → ${c.version}`);
    assert.eq(c.owner && c.owner.id, ME, "владелец");
    assert.eq(c.ownership, "owner", "отношение ко мне");
    assert.eq(c.timer.id, "resolution", "идёт норматив");
    assert.ok(c.timer.running, "норматив закрытия идёт");
    assert.eq(lastJournal(c).templateKey, "workflow.journal.claim", "журнал");
    assert.eq(res.body.navigate, "card", "переход в карточку");
    assert.eq((await env.session()).usage.activeCount, 1, "активных у меня");
  });

  test("Лимит активных 1: второе «Взять» недоступно и отклоняется сервером", async () => {
    const env = await makeEnv({ workflowPatch: { limits: { maxActive: 1 } } });
    const list = await env.all("open");
    const news = list.filter((e) => e.state === "new");
    assert.status(await env.act(news[0].guid, "claim", {}, "queue"), 200);
    // «Взять» — действие очереди (§7): смотрим строку очереди
    const second = (await env.all("open")).find((e) => e.guid === news[1].guid);
    const claim = actionOf(second, "claim");
    assert.ok(claim && !claim.enabled, "кнопка «Взять» у второго недоступна");
    assert.ok(/Лимит активных/.test(claim.reason), `причина: ${claim.reason}`);
    const second2 = await env.act(news[1].guid, "claim", {}, "queue");
    assert.status(second2, 403, "LIMIT_EXCEEDED", "второе взятие");
    assert.eq(second2.body.guard, "withinActiveLimit", "какое условие не выполнено");
  });

  test("Устаревшее состояние в запросе — конфликт версии 412 и актуальная карточка (§10.1, правило 1)", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    const conflict = await env.act(inc.guid, "claim", {}, "queue", "on_hold");
    assert.status(conflict, 412, "VERSION_CONFLICT");
    assert.eq(conflict.body.current && conflict.body.current.state, "new", "в ответе — актуальное состояние");
    assert.eq((await env.card(inc.guid)).state, "new", "состояние не изменилось");
  });

  test("Версия записи (§14.1): без If-Match — 428, со старой версией — 412 и актуальная карточка", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    const first = await env.etag(inc.guid);
    assert.eq(first, `"${inc.version}"`, "ETag карточки — версия из очереди в кавычках");
    assert.status(await env.act(inc.guid, "claim", {}, "queue", undefined, null), 428, "PRECONDITION_REQUIRED", "переход без If-Match");
    const claimed = await env.act(inc.guid, "claim", {}, "queue", undefined, first);
    assert.status(claimed, 200, null, "взять с версией свежего чтения");
    assert.eq(claimed.headers.etag, `"${claimed.body.incident.version}"`, "новая версия — в ETag ответа");
    assert.ok(claimed.headers.etag !== first, "переход меняет версию");
    const stale = await env.act(inc.guid, "release", { comment: "не моё" }, "card", undefined, first);
    assert.status(stale, 412, "VERSION_CONFLICT", "переход со старой версией");
    assert.eq(stale.body.current && stale.body.current.state, "in_progress", "в ответе — актуальная карточка");
    assert.eq((await env.card(inc.guid)).state, "in_progress", "состояние не изменилось");
    // Ответы сценария меняют версию: следующий запрос идёт с той, что пришла в их ETag
    assert.status(await env.answer(inc.guid, {}, null), 428, "PRECONDITION_REQUIRED", "ответы без If-Match");
    const card = await env.card(inc.guid);
    const saved = await env.answer(inc.guid, { [card.scenario.steps[0].id]: true }, claimed.headers.etag);
    assert.status(saved, 200, null, "ответы с версией после взятия");
    assert.ok(saved.headers.etag && saved.headers.etag !== claimed.headers.etag, "ответы меняют версию");
    assert.status(await env.act(inc.guid, "release", { comment: "не моё" }, "card", undefined, claimed.headers.etag), 412, "VERSION_CONFLICT", "версия до ответов");
    assert.status(await env.act(inc.guid, "release", { comment: "не моё" }, "card", undefined, saved.headers.etag), 200, null, "версия из ответа на ответы");
  });

  test("Переход не из этого состояния — 409 TRANSITION_NOT_ALLOWED_FROM_STATE", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    assert.status(await env.act(inc.guid, "resume", {}, "queue"), 409, "TRANSITION_NOT_ALLOWED_FROM_STATE");
  });

  /* ===== Отложить и возобновить (§6.1, §4) ===== */

  test("Отложить: причина обязательна, норматив закрытия на паузе, срок удержания идёт", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    await env.advance(30);
    assert.status(await env.act(inc.guid, "hold", { reasonId: "" }), 422, null, "без причины");
    const before = await env.card(inc.guid);
    const left = Date.parse(before.timer.dueAt) - env.now;
    const res = await env.act(inc.guid, "hold", { reasonId: "third_party", comment: "ждём" });
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.state, "on_hold", "состояние");
    assert.eq(c.holdReasonId, "third_party", "причина");
    assert.ok(!c.timer.running, "норматив закрытия приостановлен");
    assert.near(c.timer.remainingMs, left, 1000, "остаток норматива сохранён");
    assert.eq(c.holdTimer && c.holdTimer.id, "hold", "срок удержания");
    assert.near(Date.parse(c.holdTimer.dueAt) - env.now, 30 * 60000, 1000, "срок удержания по причине — 30 мин");
  });

  test("Возобновить: норматив закрытия продолжается с остатка, причина удержания снята", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    await env.act(inc.guid, "hold", { reasonId: "patrol", comment: "наряд" });
    const held = await env.card(inc.guid);
    await env.advance(600);
    const res = await env.act(inc.guid, "resume", {}, "queue");
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.state, "in_progress", "состояние");
    assert.eq(c.holdReasonId, null, "причина снята");
    assert.eq(c.holdTimer, null, "срок удержания снят");
    assert.near(Date.parse(c.timer.dueAt) - env.now, held.timer.remainingMs, 1000, "продолжение с остатка, а не заново");
  });

  test("Предельный срок удержания истёк — нарушение «hold», инцидент остаётся отложенным", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    await env.act(inc.guid, "hold", { reasonId: "third_party", comment: "ждём" });
    await env.advance(30 * 60 + GRACE + 1);
    const c = await env.card(inc.guid);
    assert.eq(c.state, "on_hold", "состояние");
    assert.ok(c.slaBreached, "отметка нарушения");
    assert.ok(c.breaches.some((b) => b.kind === "hold"), `нарушения: ${JSON.stringify(c.breaches.map((b) => b.kind))}`);
    await env.advance(60);
    assert.eq((await env.card(inc.guid)).breaches.filter((b) => b.kind === "hold").length, 1, "срабатывает один раз на дедлайн");
  });

  /* ===== Вернуть в очередь (§6.1, RULE-07) ===== */

  test("Вернуть в очередь: ничей, норматив закрытия не обнуляется при повторном взятии", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    await env.advance(120);
    const res = await env.act(inc.guid, "release", { comment: "не моё" });
    assert.status(res, 200);
    assert.eq(res.body.incident.state, "new", "состояние");
    assert.eq(res.body.incident.owner, null, "владелец");
    assert.eq(res.body.incident.timer.id, "reaction", "снова идёт реакция");
    const again = await env.act(inc.guid, "claim", {}, "queue");
    const left = Date.parse(again.body.incident.timer.dueAt) - env.now;
    const full = W.timers.find((x) => x.id === "resolution").byPriority[TOP] * 1000;
    assert.ok(left <= full - 119000, `норматив закрытия продолжен: осталось ${left} из ${full}`);
  });

  /* ===== Передать (§8, RULE-19, RULE-20) ===== */

  test("Передачи не расходуют цепочку автоэскалации и не продлевают реакцию: две передачи нового — не принят, уходит на уровень 1 (§8.3, RULE-76)", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    const due = inc.timer.dueAt;
    for (const [n, target] of [[1, "sidorov"], [2, "gusev"]]) {
      // Часть срока уже прошла: начни реакция заново — срок бы сдвинулся
      await env.advance(20);
      const res = await env.act(inc.guid, "transfer", { targetId: target, comment: `передача ${n}` }, "queue");
      assert.status(res, 200, null, `передача ${n}`);
      const c = res.body.incident;
      assert.eq([c.escalationLevel, c.transferCount], [0, n], `после передачи ${n}: уровень 0, передач ${n}`);
      assert.eq([c.timer.id, c.timer.dueAt], ["reaction", due], `после передачи ${n}: реакция продолжается с того же срока`);
    }
    await env.advance(Math.ceil((Date.parse(due) - env.now) / 1000) + GRACE + 1);
    const c = await env.card(inc.guid);
    const first = W.escalation.levels.find((l) => l.level === 1).targetRef.split(":")[1];
    assert.eq([c.state, c.owner && c.owner.id, c.escalationLevel, c.transferCount], ["pending_acceptance", first, 1, 2], "автоэскалация — на уровень 1, а не пропуском на 2 и не потолок");
  });

  test("Передать из «В работе»: реакция запускается по нормативу текущего уровня (RULE-76)", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    const res = await env.act(inc.guid, "transfer", { targetId: "sidorov", comment: "нужен допуск" });
    assert.status(res, 200);
    const timer = W.timers.find((t) => t.id === "reaction");
    const sec = (timer.overrides.find((o) => o.priority === inc.priority && Object.keys(o).length === 2) || {}).sec || timer.defaultSec;
    const left = Math.round((Date.parse(res.body.incident.timer.dueAt) - env.now) / 1000);
    assert.eq([res.body.incident.timer.id, left], ["reaction", sec], "реакция — полный норматив уровня 0");
  });

  test("Передать человеку: ожидает принятия, адресат в owner, уровень не меняется, передач +1, норматив закрытия на паузе (RULE-76)", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    const res = await env.act(inc.guid, "transfer", { targetId: "sidorov", comment: "нужен допуск" });
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.state, "pending_acceptance", "состояние");
    assert.eq(c.owner && c.owner.id, "sidorov", "owner — человек");
    assert.eq(c.assignmentGroup, null, "группы нет");
    assert.eq([c.escalationLevel, c.transferCount], [0, 1], "уровень не меняется, передач — одна");
    assert.eq(c.ownership, "other", "для меня — чужой");
    assert.eq(c.timer.id, "reaction", "идёт реакция адресата");
    assert.eq(res.body.navigate, "queue", "возврат к очереди");
  });

  test("Передать себе и своей дежурной группе нельзя: нет в вариантах и отказ сервера (§10.1)", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    const transfer = actionOf(await env.card(inc.guid), "transfer");
    const ids = transfer.fieldOptions.targetId.options.map((o) => o.id);
    assert.ok(!ids.includes(ME) && !ids.includes("grp-leads"), `варианты: ${ids.join(", ")}`);
    assert.status(await env.act(inc.guid, "transfer", { targetId: ME, comment: "x" }), 403, "TRANSFER_TO_SELF_FORBIDDEN", "себе");
    assert.status(await env.act(inc.guid, "transfer", { targetId: "grp-leads", comment: "x" }), 403, "TRANSFER_TO_SELF_FORBIDDEN", "своей группе");
  });

  test("Бейдж чужого инцидента в работе — ФИО владельца, ключом каталога: в очереди и в карточке (§2.4, BUG-51)", async () => {
    const env = await makeEnv();
    const guid = await env.guidOf("INC-1846");
    const owner = window.IM_FIXTURE.people.operators.find((o) => o.id === "petrova");
    const row = (await env.all("foreign")).find((e) => e.guid === guid);
    const card = await env.card(guid);
    assert.eq([card.state, card.owner && card.owner.id], ["in_progress", owner.id], "в работе у коллеги");
    for (const [where, inc] of [["очередь", row], ["карточка", card]]) {
      assert.eq(inc.badge.template, "workflow.badge.in_progress.other", `${where}: ключ бейджа`);
      assert.eq(inc.badge.label, owner.name, `${where}: текст бейджа`);
    }
  });

  test("«Перехватить» — не адресату: переданное моей группе принимают, а не перехватывают — ни в карточке, ни на панели выборки (§6.1, §7, BUG-55)", async () => {
    const env = await makeEnv();
    const guid = await env.guidOf("INC-1836");
    const card = await env.card(guid);
    assert.eq([card.state, card.ownership], ["pending_acceptance", "target"], "передано моей группе");
    const visible = (acts) => (acts || []).filter((a) => a.visible !== false).map((a) => a.id);
    assert.ok(visible(card.actions).includes("accept") && !visible(card.actions).includes("takeover"), `в карточке: ${visible(card.actions).join(", ")}`);
    const sel = await env.ok("POST", "/operator/incidents/selection", { mode: "explicit", incidentGuids: [guid] });
    assert.ok(!visible(sel.actions).includes("takeover"), `на панели выборки: ${visible(sel.actions).join(", ")}`);
    const res = await env.act(guid, "takeover", { comment: "тест" });
    assert.ok(res.status >= 400, `сервер перехват адресату отклоняет: ${res.status}`);
    assert.eq((await env.card(guid)).state, "pending_acceptance", "состояние не изменилось");
  });

  test("Адресат открывает карточку до «Принять»; «Принять» в строке первой (§6.3, §7, BUG-60)", async () => {
    const env = await makeEnv();
    const inbox = await env.all("inbox");
    for (const n of ["INC-1843", "INC-1836"]) {
      const guid = await env.guidOf(n);
      const row = inbox.find((e) => e.guid === guid);
      assert.eq(row.actions.map((a) => a.id).slice(0, 2), ["accept", "view"], `${n}: начало строки`);
      const card = await env.card(guid);
      const ids = card.actions.filter((a) => a.visible !== false).map((a) => a.id);
      assert.ok(["accept", "reject", "transfer"].every((a) => ids.includes(a)) && !ids.includes("takeover"), `${n}: в карточке ${ids.join(", ")}`);
    }
  });

  test("«Посмотреть» — значок у каждого инцидента очереди, без отдельного права; ничего не меняет (§6.3, §7, RULE-80, RULE-81)", async () => {
    assert.ok(!W.permissions.some((p) => p.key.startsWith("incident:read")), "в каталоге нет права на просмотр");
    // Только права для работы — «Посмотреть» от прав не зависит
    const env = await makeEnv({ permissions: ["incident:claim", "incident:accept"] });
    const all = await env.all("all");
    const states = new Set();
    for (const e of all) {
      const v = e.actions.find((a) => a.id === "view");
      assert.ok(v, `${e.number} (${e.state}/${e.ownership}): нет «Посмотреть»`);
      assert.eq([v.kind, v.style, v.icon, v.enabled], ["nav", "icon", "visibility", true], `${e.number}: «Посмотреть» — значок`);
      states.add(`${e.state}/${e.ownership}`);
    }
    for (const kind of ["new/other", "pending_acceptance/target", "on_hold/owner", "in_progress/other", "closed/owner"]) assert.ok(states.has(kind), `в наборе есть ${kind}`);
    // Свой в работе: основная — «Продолжить», значок тоже есть
    const fresh = all.find((e) => e.state === "new");
    await env.act(fresh.guid, "claim", {}, "queue");
    const mine = (await env.all("mine")).find((e) => e.guid === fresh.guid);
    assert.eq(mine.actions.slice(0, 2).map((a) => a.id), ["open_card", "view"], "свой в работе");
    // Карточка нового — на просмотр, с «Взять»; просмотр ничего не меняет
    const other = all.find((e) => e.state === "new" && e.guid !== fresh.guid);
    const card = await env.card(other.guid);
    assert.eq([card.state, card.readOnly, card.actions.some((a) => a.id === "claim" && a.enabled)], ["new", true, true], "карточка нового");
    assert.eq((await env.card(other.guid)).version, card.version, "просмотр не меняет инцидент");
  });

  test("Передача группе: owner пуст, адресат в assignment_group, бейдж «Вашей группе», «Принять» делает меня владельцем", async () => {
    const env = await makeEnv();
    const inc = await env.card(await env.guidOf("INC-1836"));
    assert.eq(inc.state, "pending_acceptance", "состояние");
    assert.eq(inc.owner, null, "owner пуст");
    assert.eq(inc.assignmentGroup && inc.assignmentGroup.id, "grp-leads", "группа");
    assert.eq(inc.ownership, "target", "адресован мне через группу");
    assert.ok(inc.badge.label.startsWith("Вашей группе"), `бейдж: ${inc.badge.label}`);
    const res = await env.act(inc.guid, "accept", {}, "queue");
    assert.status(res, 200);
    assert.eq(res.body.incident.owner.id, ME, "владелец");
    assert.eq(res.body.incident.assignmentGroup, null, "группа очищена");
  });

  test("Выход из МИ (§8.1, RULE-28): адресованный лично и не принятый уходит дежурной группе, норматив реакции продолжается", async () => {
    const env = await makeEnv();
    const personal = await env.card(await env.guidOf("INC-1843"));
    const forGroup = await env.card(await env.guidOf("INC-1836"));
    assert.eq([personal.state, personal.owner && personal.owner.id], ["pending_acceptance", ME], "INC-1843 адресован мне лично");
    const myGroup = (await env.session()).operator.dutyGroupGuids[0];
    const res = await env.call("PUT", "/operator/session/agent-state", { agentState: "offline" });
    assert.status(res, 200, null, "выйти");
    assert.eq(res.body.session.agentState, "offline", "состояние оператора");
    assert.ok(res.body.affectedIncidents.some((i) => i.guid === personal.guid), "INC-1843 среди изменённых");
    const after = await env.card(personal.guid);
    assert.eq([after.state, after.owner, after.assignmentGroup && after.assignmentGroup.id], ["pending_acceptance", null, myGroup], "передан моей дежурной группе");
    assert.eq(after.escalationLevel, personal.escalationLevel, "уровень эскалации не меняется");
    assert.eq(after.timer && after.timer.dueAt, personal.timer && personal.timer.dueAt, "норматив реакции продолжается, а не начинается заново");
    const group = await env.card(forGroup.guid);
    assert.eq([group.owner, group.assignmentGroup && group.assignmentGroup.id], [null, forGroup.assignmentGroup.id], "адресованный группе не меняется");
    assert.status(await env.call("PUT", "/operator/session/agent-state", { agentState: "ready" }), 200, null, "снова вошёл");
  });

  test("Выход из МИ (§12.1, RULE-37): свои в работе и отложенные сразу возвращаются в очередь; дальше — только просмотр", async () => {
    const env = await makeEnv();
    const taken = (await env.all("open")).find((e) => e.state === "new");
    assert.status(await env.act(taken.guid, "claim", {}, "queue"), 200, null, "взять");
    const mine = (await env.all("open")).filter((e) => ["in_progress", "on_hold"].includes(e.state) && e.owner && e.owner.id === ME);
    assert.ok(mine.some((e) => e.state === "in_progress") && mine.some((e) => e.state === "on_hold"), `у меня есть и в работе, и отложенные: ${mine.map((e) => e.number)}`);
    const res = await env.call("PUT", "/operator/session/agent-state", { agentState: "offline" });
    assert.status(res, 200, null, "выйти");
    for (const inc of mine) {
      assert.ok(res.body.affectedIncidents.some((i) => i.guid === inc.guid), `${inc.number}: среди изменённых`);
      const c = await env.card(inc.guid);
      assert.eq([c.state, c.owner, c.holdReasonId], ["new", null, null], `${inc.number}: новый, ничей, без причины`);
      assert.ok(c.journal.some((j) => /оператор вышел/.test(jt(j))), `${inc.number}: запись в журнале`);
    }
    assert.eq((await env.session()).usage.activeCount + (await env.session()).usage.onHoldCount, 0, "у меня ничего не осталось");
    // Вышедшему — только просмотр, как на перерыве (§10.4); войти — снова «Готов»
    assert.status(await env.act(taken.guid, "claim", {}, "queue"), 403, "AGENT_NOT_READY", "вышел — взять нельзя");
    assert.ok((await env.card(taken.guid)).guid === taken.guid, "просмотр доступен");
    assert.status(await env.call("PUT", "/operator/session/agent-state", { agentState: "ready" }), 200, null, "войти");
    assert.status(await env.act(taken.guid, "claim", {}, "queue"), 200, null, "после входа — снова можно");
  });

  test("Передача адресату, который уже вышел, — сразу его дежурной группе (§8.1, RULE-47)", async () => {
    const env = await makeEnv();
    const mall = (await env.all("open")).find((e) => e.state === "new" && e.site === "Торговый центр");
    // Кузнецов в наборе вышел, но передать ему можно: список это показывает, но не запрещает
    const target = (await env.ok("GET", `/operator/transfer-targets?incidentGuid=${enc(mall.guid)}`)).find((t) => t.id === "kuznetsov");
    assert.eq([target && target.available], [false], "Кузнецов в списке, не на месте");
    assert.status(await env.act(mall.guid, "transfer", { targetId: "kuznetsov", comment: "тест" }, "queue"), 200, null, "передать Кузнецову");
    const fired = await env.advance(1);
    assert.ok(fired.some((f) => f.incidentGuid === mall.guid && f.transitionId === "addressee_signed_out_to_group"), "сработало «адресат вышел»");
    const c = await env.card(mall.guid);
    assert.eq([c.state, c.owner, c.assignmentGroup && c.assignmentGroup.id], ["pending_acceptance", null, "grp-tc"], "у его группы «Охрана ТЦ»");
    assert.ok(c.journal.some((j) => /Адресат вышел, не приняв/.test(jt(j))), "запись в журнале");
  });

  test("Выход из МИ без дежурной группы: адресованный лично возвращается в общую очередь (§8.1)", async () => {
    // Свой набор данных: оператор стенда не состоит ни в одной группе
    const fixture = JSON.parse(JSON.stringify(window.IM_FIXTURE));
    fixture.people.dutyGroups.forEach((g) => (g.members = g.members.filter((m) => m !== ME)));
    const api = (await standWith({ fixture })).api;
    const guid = fixture.incidents.find((i) => i.number === "INC-1843").guid;
    const res = await api.raw("PUT", "/operator/session/agent-state", { agentState: "offline" });
    assert.status(res, 200, null, "выйти");
    const card = await api.get(`/operator/incidents/${enc(guid)}`);
    assert.eq([card.state, card.owner, card.assignmentGroup], ["new", null, null], "в общей очереди, ничей");
    assert.ok(card.journal.some((j) => /Адресат вышел/.test(jt(j))), "запись в журнале");
  });

  test("Закрытый из «Ожидает принятия» группой и переоткрытый — у человека, без группы (§8.1)", async () => {
    const env = await makeEnv();
    const inc = await env.card(await env.guidOf("INC-1836"));
    const close = actionOf((await env.all("inbox")).find((e) => e.guid === inc.guid), "close");
    const res = await env.act(inc.guid, "close", formFor(close, { resultId: "mass" }), "queue");
    assert.status(res, 200);
    assert.eq(res.body.incident.assignmentGroup, null, "после закрытия группы нет");
    const again = await env.act(inc.guid, "reopen", { comment: "вернули" });
    assert.status(again, 200);
    assert.eq(again.body.incident.owner.id, ME, "в работе у меня");
    assert.eq(again.body.incident.assignmentGroup, null, "и не у группы");
    const entry = again.body.incident.journal[again.body.incident.journal.length - 1];
    assert.ok(entry.vars.closeResultLabel, `в записи о переоткрытии — прежний результат: ${entry.text}`);
  });

  test("Отклонить: инцидент снова новый, ничей, уровень эскалации сохранён, реакция продолжается (RULE-82)", async () => {
    const env = await makeEnv();
    const inc = await env.card(await env.guidOf("INC-1843"));
    assert.eq(inc.badge.label, "Вам на принятие", "бейдж личной передачи");
    // Часть срока прошла: начни реакция заново — срок бы сдвинулся
    await env.advance(20);
    const res = await env.act(inc.guid, "reject", { comment: "не мой профиль" });
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.state, "new", "состояние");
    assert.eq(c.owner, null, "владелец");
    assert.eq(c.escalationLevel, inc.escalationLevel, "уровень сохранён");
    assert.eq([c.timer.id, c.timer.dueAt], ["reaction", inc.timer.dueAt], "реакция продолжается с того же срока");
  });

  test("Права own и any: без incident:transfer:any своё передать можно, чужое — нет (§5)", async () => {
    const all = W.permissions.map((p) => p.key).filter((k) => k !== "incident:schema:admin" && k !== "incident:transfer:any");
    const env = await makeEnv({ permissions: all });
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    assert.status(await env.act(inc.guid, "transfer", { targetId: "sidorov", comment: "своё" }), 200, null, "своё");
    const foreign = await env.find((e) => e.state === "in_progress" && e.ownership === "other");
    const transfer = actionOf(foreign, "transfer");
    assert.ok(!transfer || !transfer.enabled, "у чужого «Передать» недоступно");
    const res = await env.act(foreign.guid, "transfer", { targetId: "sidorov", comment: "чужое" }, "queue");
    assert.status(res, 403, "PERMISSION_DENIED", "чужое");
    assert.ok(/transfer:any/.test(res.body.message), `причина: ${res.body.message}`);
  });

  test("Адресаты передачи: без себя и своих групп; для инцидента — без текущего адресата", async () => {
    const env = await makeEnv();
    const all = await env.ok("GET", "/operator/transfer-targets");
    const ids = all.map((x) => x.id);
    assert.ok(!ids.includes(ME) && !ids.includes("grp-leads"), `список: ${ids.join(", ")}`);
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    await env.act(inc.guid, "transfer", { targetId: "petrova", comment: "x" });
    const forInc = await env.ok("GET", `/operator/transfer-targets?incidentGuid=${enc(inc.guid)}`);
    assert.ok(!forInc.some((x) => x.id === "petrova"), "текущий адресат исключён");
  });

  /* ===== Перехват (§6.1) ===== */

  test("Перехватить чужой: владелец — я, прогресс сценария сохранён; чужая карточка — только просмотр", async () => {
    const env = await makeEnv();
    const foreign = await env.find((e) => e.state === "in_progress" && e.ownership === "other");
    const before = await env.card(foreign.guid);
    assert.ok(before.readOnly, "чужая карточка — просмотр");
    const patch = await env.answer(foreign.guid, { x: 1 });
    assert.status(patch, 403, "PERMISSION_DENIED", "править чужой сценарий");
    const res = await env.act(foreign.guid, "takeover", { comment: "срочно" });
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.owner.id, ME, "владелец");
    assert.eq(c.scenarioProgress, before.scenarioProgress, "прогресс сохранён");
    assert.ok(!c.readOnly, "теперь можно править");
  });

  /* ===== Закрыть (§2.2, RULE-23) ===== */

  test("«Обработан» недоступен без обязательных шагов; с ними — выбран по умолчанию и закрывает", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    let card = await env.card(inc.guid);
    let results = actionOf(card, "close").fieldOptions.resultId;
    const processed = results.options.find((o) => o.id === "processed");
    assert.ok(processed.disabled && processed.reason, "«Обработан» недоступен и объяснено почему");
    assert.eq(results.defaultValue, null, "по умолчанию ничего не выбрано");
    assert.status(await env.act(inc.guid, "close", { resultId: "processed" }), 403, null, "закрыть «Обработан» без шагов");
    assert.status(await env.answer(inc.guid, fullAnswers(card)), 200, null, "ответы сценария");
    card = await env.card(inc.guid);
    results = actionOf(card, "close").fieldOptions.resultId;
    assert.eq(results.defaultValue, "processed", "по умолчанию «Обработан»");
    const res = await env.act(inc.guid, "close", { resultId: "processed" });
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.state, "closed", "состояние");
    assert.eq(c.closeResultId, "processed", "результат");
    assert.eq(c.timer, null, "нормативы не идут");
    assert.ok(c.closedAt, "время закрытия");
  });

  test("Результаты по поверхности: в очереди свой инцидент закрывают только «Массовым сбоем», в карточке — любым (§2.2, §7)", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    const row = (await env.all("mine")).find((e) => e.guid === inc.guid);
    assert.eq(actionOf(row, "close").fieldOptions.resultId.options.map((o) => o.id), ["mass"], "в очереди");
    const inCard = actionOf(await env.card(inc.guid), "close").fieldOptions.resultId.options.map((o) => o.id);
    assert.ok(inCard.includes("false_alarm") && inCard.includes("processed") && inCard.includes("mass"), `в карточке: ${inCard.join(", ")}`);
    assert.status(await env.act(inc.guid, "close", { resultId: "false_alarm", comment: "x" }, "queue"), 403, null, "«Ложная тревога» из очереди");
  });

  test("Чужой инцидент в работе «Массовым сбоем» не закрыть: только свой (ownerOnlyInStates, §2.2)", async () => {
    const env = await makeEnv();
    const foreign = await env.find((e) => e.state === "in_progress" && e.ownership === "other");
    const close = actionOf(foreign, "close");
    assert.ok(!close || !close.enabled, "«Закрыть» у чужого в работе недоступно");
    const cause = W.reasonCatalogs.mass_fault.items[0].id;
    assert.status(await env.act(foreign.guid, "close", { resultId: "mass", causeId: cause, comment: "x" }, "queue"), 403, null, "сервер отказывает");
  });

  test("«Ложная тревога» требует комментарий; комментарий сохраняется как result", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    assert.status(await env.act(inc.guid, "close", { resultId: "false_alarm", comment: "" }), 422, "FORM_FIELD_REQUIRED");
    const res = await env.act(inc.guid, "close", { resultId: "false_alarm", comment: "уборщик" });
    assert.status(res, 200);
    assert.eq(res.body.incident.closeResultId, "false_alarm", "результат");
    assert.eq(res.body.incident.result, "уборщик", "комментарий");
  });

  test("Из очереди закрывают только «Массовый сбой»: причина сбоя обязательна, подпись — причина", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    const close = actionOf(inc, "close");
    assert.eq(close.fieldOptions.resultId.options.map((o) => o.id), ["mass"], "результаты в очереди");
    assert.status(await env.act(inc.guid, "close", { resultId: "mass", comment: "свет" }, "queue"), 422, null, "без причины сбоя");
    const cause = close.fieldOptions.causeId.options[0];
    const res = await env.act(inc.guid, "close", { resultId: "mass", causeId: cause.id, comment: "свет" }, "queue");
    assert.status(res, 200);
    assert.eq(res.body.incident.closeCauseId, cause.id, "причина");
    assert.eq(res.body.incident.closeResultLabel, cause.label, "подпись — причина сбоя");
    assert.status(await env.act((await env.find((e) => e.state === "new")).guid, "close", { resultId: "false_alarm", comment: "x" }, "queue"), 403, null, "другой результат из очереди");
  });

  test("Права пути в работу (§5, RULE-36, RULE-38): «Принять» — по праву «Принимать», «Перехватить» и «Переоткрыть» — ещё и по праву взятия", async () => {
    const all = W.permissions.map((p) => p.key).filter((k) => k !== "incident:schema:admin");
    // Без права «Принимать»: принять нельзя, взять — можно
    let env = await makeEnv({ permissions: all.filter((k) => k !== "incident:accept") });
    const personal = await env.guidOf("INC-1843");
    const accept = await env.act(personal, "accept", {}, "queue");
    assert.status(accept, 403, "PERMISSION_DENIED", "принять без права «Принимать»");
    assert.ok(/incident:accept/.test(accept.body.message), `причина: ${accept.body.message}`);
    assert.status(await env.act((await newFire(env)).guid, "claim", {}, "queue"), 200, null, "взять — по праву взятия");
    // Без права взятия: перехватить и переоткрыть нельзя, даже с их собственными правами
    env = await makeEnv({ permissions: all.filter((k) => k !== "incident:claim") });
    const foreign = await env.find((e) => e.state === "in_progress" && e.ownership === "other");
    const card = await env.card(foreign.guid);
    assert.ok(!(card.actions || []).some((x) => x.id === "takeover" && x.visible !== false && x.enabled), "«Перехватить» без права взятия недоступно");
    assert.status(await env.act(foreign.guid, "takeover", { comment: "тест" }), 403, "PERMISSION_DENIED", "перехват без права взятия");
    const done = await env.find((e) => e.state === "closed");
    assert.status(await env.act(done.guid, "reopen", { comment: "тест" }), 403, "PERMISSION_DENIED", "переоткрытие без права взятия");
  });

  test("Передать можно только тому, кто может принять (§8.1, RULE-38); автоэскалация такого адресата пропускает (§8.3)", async () => {
    const env = await makeEnv();
    // У Петровой — только «Наблюдатель»: доступ ко всему есть, права «Принимать» нет
    assert.status(await env.call("PUT", "/test/operators/petrova/roles", { roles: ["Наблюдатель"] }), 200, null, "роли Петровой");
    const inc = await newFire(env);
    const targets = (await env.ok("GET", `/operator/transfer-targets?incidentGuid=${enc(inc.guid)}`)).map((t) => t.id);
    assert.ok(!targets.includes("petrova"), `Петровой нет среди адресатов: ${targets}`);
    const res = await env.act(inc.guid, "transfer", { targetId: "petrova", comment: "тест" }, "queue");
    assert.status(res, 403, "TARGET_CANNOT_ACCEPT", "передача тому, кто не может принять");
    assert.eq(res.body.guard, "targetCanAccept", "какое условие не выполнено");
    // Адресат первого уровня эскалации — Петрова: уровень пропускается, инцидент уходит на второй
    const first = W.escalation.levels[0].targetRef.split(":")[1];
    const second = W.escalation.levels[1].targetRef.split(":")[1];
    assert.eq(first, "petrova", "в машине первый уровень — Петрова");
    const left = Math.ceil((Date.parse(inc.timer.dueAt) - env.now) / 1000) + GRACE + 1;
    await env.advance(left);
    const c = await env.card(inc.guid);
    assert.eq([c.owner && c.owner.id, c.escalationLevel], [second, 2], "первый уровень пропущен — сразу второй");
  });

  test("Связи камер (§19.1, RULE-49, RULE-70): название, устройства и камеры по порядку, как в наборе; без права incident:schema:admin — 403", async () => {
    const env = await makeEnv();
    const links = await env.ok("GET", "/operator/admin/camera-links");
    assert.eq(
      links.map((l) => [l.guid, l.name, l.devices.map((d) => d.guid), l.cameras.map((c) => c.guid)]),
      window.IM_FIXTURE.cameraLinks.map((l) => [l.id, l.name, l.devices, l.cameras]),
      "связи, их порядок и порядок камер — из набора"
    );
    assert.ok(links.every((l) => l.devices.every((d) => d.name) && l.cameras.every((c) => c.name)), "с именами устройств и камер");
    const all = W.permissions.map((p) => p.key).filter((k) => k !== "incident:schema:admin");
    assert.status(await (await makeEnv({ permissions: all })).call("GET", "/operator/admin/camera-links"), 403, "PERMISSION_DENIED", "без права");
  });

  test("Связи камер многие-ко-многим (§19.1, RULE-70): камеры инцидента — из всех связей источника без повторов, по порядку связей; связи других устройств события не добавляют", async () => {
    const fx = window.IM_FIXTURE;
    // Камеры, доступные оператору стенда, — из ответов …/media эталонного набора
    const base = await makeEnv();
    const cams = [];
    for (const i of fx.incidents) {
      for (const c of (await base.ok("GET", `/operator/incidents/${enc(i.guid)}/media`)).cameras) if (!cams.includes(c.guid)) cams.push(c.guid);
      if (cams.length >= 4) break;
    }
    const [A, B, C, D] = cams;
    // Инцидент с источником и ещё одним устройством события
    const inc = fx.incidents.find((i) => i.devices.length > 1);
    const [S, O] = inc.devices;
    const other = fx.incidents.find((i) => i.devices[0] !== S && i.devices[0] !== O);
    const link = (n, devices, cameras) => ({ id: `b0000000-0000-4000-8000-0000000000a${n}`, name: `Связь ${n}`, devices, cameras });
    const X = link(1, [S], [A, B]);
    const Y = link(2, [S], [B, C]);
    const Z = link(3, [O], [D]);
    const camerasOf = async (env, guid) => (await env.ok("GET", `/operator/incidents/${enc(guid)}/media`)).cameras.map((c) => c.guid);

    const env = await makeEnv({ fixturePatch: { cameraLinks: [X, Y, Z] } });
    assert.eq(await camerasOf(env, inc.guid), [A, B, C], "две связи источника: общая камера — один раз, главная — первая камера первой связи; связь другого устройства события — не добавляет");
    assert.eq(await camerasOf(env, other.guid), [], "источник ни в одной связи — без камер");
    const res = await env.call("POST", "/test/incidents", { eventTypeId: inc.eventType.id, priority: TOP, deviceIds: [S, O], site: inc.site, location: "тест" });
    assert.status(res, 201, null, "появился");
    assert.eq(await camerasOf(env, res.body.guid), [A, B, C], "появившийся инцидент — камеры из связей источника");

    const swapped = await makeEnv({ fixturePatch: { cameraLinks: [Y, X, Z] } });
    assert.eq(await camerasOf(swapped, inc.guid), [B, C, A], "порядок связей в списке задаёт порядок камер и главную");
  });

  test("Справочные ссылки (§7, RULE-49): без площадки — все, с площадкой — общие и этой площадки", async () => {
    const env = await makeEnv();
    const fx = window.IM_FIXTURE.helpLinks;
    const all = await env.ok("GET", "/operator/reference/help-links");
    assert.eq(all.map((l) => l.id), fx.map((l) => l.id), "без площадки — весь справочник");
    const mall = await env.ok("GET", `/operator/reference/help-links?site=${enc("Торговый центр")}`);
    assert.eq(mall.map((l) => l.id), fx.filter((l) => !l.site || l.site === "Торговый центр").map((l) => l.id), "в ТЦ — общие и ссылки ТЦ");
    const office = await env.ok("GET", `/operator/reference/help-links?site=${enc("Главный офис")}`);
    assert.ok(office.length && office.every((l) => l.site == null), "на другой площадке — только общие");
  });

  test("Настройки администратора: группы доступа и дежурные группы (§20, RULE-44) — как в наборе; без права incident:schema:admin — 403", async () => {
    const env = await makeEnv();
    const fx = window.IM_FIXTURE;
    const access = await env.ok("GET", "/operator/admin/access-groups");
    assert.eq(access.map((a) => [a.name, a.roles]), fx.accessGroups.map((a) => [a.name, a.roles]), "группы доступа и их роли — из набора");
    const mall = access.find((a) => a.roles.includes("Оператор ТЦ"));
    assert.eq(mall.sourceGroups.map((g) => g.name), ["Торговый центр"], "группы устройств — с именами");
    const duty = await env.ok("GET", "/operator/admin/duty-groups");
    assert.eq(duty.map((g) => g.id), fx.people.dutyGroups.map((g) => g.id), "дежурные группы — в порядке набора");
    const leads = duty.find((g) => g.id === "grp-leads");
    assert.ok(leads.memberIds.includes(ME) && leads.memberIds.includes("petrova"), `состав: я — отдельно, Петрова — по роли: ${leads.memberIds}`);
    const all = W.permissions.map((p) => p.key).filter((k) => k !== "incident:schema:admin");
    const noAdmin = await makeEnv({ permissions: all });
    assert.status(await noAdmin.call("GET", "/operator/admin/access-groups"), 403, "PERMISSION_DENIED", "группы доступа без права");
    assert.status(await noAdmin.call("GET", "/operator/admin/duty-groups"), 403, "PERMISSION_DENIED", "дежурные группы без права");
  });

  test("Стенд: изменения схемы и набора на один прогон (PROC-13) — JSON Merge Patch в POST /test/reset", async () => {
    const env = await makeEnv({ workflowPatch: { escalation: { enabled: false } }, fixturePatch: { people: { dutyGroups: [] } } });
    const patched = await env.ok("GET", "/operator/workflow/active");
    assert.eq([patched.escalation.enabled, patched.escalation.maxLevel], [false, W.escalation.maxLevel], "в схеме изменено только указанное");
    assert.ok(!(await env.ok("GET", "/operator/transfer-targets")).some((t) => t.kind === "duty_group"), "дежурных групп в наборе нет");
    const plain = await makeEnv();
    assert.eq((await plain.ok("GET", "/operator/workflow/active")).escalation.enabled, W.escalation.enabled, "следующий сброс без изменений — исходная схема");
    assert.ok((await plain.ok("GET", "/operator/transfer-targets")).some((t) => t.kind === "duty_group"), "и исходный набор");
  });

  test("Автоэскалация выключена (§4, §9, RULE-40): истёкшая реакция — нарушение и алерт без передачи; потолка нет", async () => {
    for (const [why, levels] of [
      ["уровни настроены", null],
      ["уровней нет", []],
    ]) {
      const w = JSON.parse(JSON.stringify(W));
      w.escalation.enabled = false;
      if (levels) w.escalation.levels = levels;
      const api = (await standWith({ workflow: w })).api;
      const inc = (await api.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.state === "new");
      const got = [];
      const stop = api.subscribe((m) => got.push(m));
      const fired = [];
      // До конца реакции — по дедлайну карточки
      const card = await api.get(`/operator/incidents/${enc(inc.guid)}`);
      const now = Date.parse((await api.raw("POST", "/test/clock", { advanceSec: 0 })).body.now);
      for (let left = Math.ceil((Date.parse(card.timer.dueAt) - now) / 1000) + GRACE + 1; left > 0; left -= 240) {
        await api.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        fired.push(...(await api.raw("POST", "/test/clock", { advanceSec: Math.min(240, left) })).body.fired);
      }
      await new Promise((r) => setTimeout(r, 300));
      stop();
      const mine = fired.filter((f) => f.incidentGuid === inc.guid).map((f) => f.transitionId);
      assert.eq(mine, ["reaction_overdue"], `${why}: сработало только нарушение реакции`);
      const c = await api.get(`/operator/incidents/${enc(inc.guid)}`);
      assert.eq([c.state, c.escalationLevel, c.owner], ["new", 0, null], `${why}: никому не передан`);
      assert.eq(c.breaches.filter((b) => b.kind === "reaction").length, 1, `${why}: нарушение реакции записано`);
      assert.ok(c.journal.some((j) => /Норматив реакции нарушен/.test(jt(j))), `${why}: запись в журнале`);
      assert.ok(got.some((m) => m.type === "incident.alert" && m.incidentGuid === inc.guid && m.payload.transitionId === "reaction_overdue"), `${why}: алерт получателю — мне, я в группе старших операторов`);
    }
  });

  // Самый длинный норматив закрытия в машине: за это время он истечёт у любого инцидента
  const longestResolution = () => {
    const r = W.timers.find((x) => x.id === "resolution");
    return Math.max(r.defaultSec, ...Object.values(r.byPriority), ...r.overrides.map((o) => o.sec));
  };

  test("Алерт получателю алертов (§9, RULE-43): я в группе старших операторов, на месте и с доступом — приходит событие incident.alert", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    assert.status(await env.act(inc.guid, "claim", {}, "queue"), 200, null, "взять");
    const got = [];
    const stop = env.api.subscribe((m) => got.push(m));
    await new Promise((r) => setTimeout(r, 300));
    const fired = await env.advance(longestResolution() + GRACE + 1);
    await new Promise((r) => setTimeout(r, 300));
    stop();
    assert.ok(fired.some((f) => f.incidentGuid === inc.guid && f.transitionId === "resolution_overdue"), "норматив закрытия нарушен");
    const alert = got.find((m) => m.type === "incident.alert" && m.incidentGuid === inc.guid);
    assert.ok(alert, "в поток пришёл алерт");
    assert.eq(alert.payload.transitionId, "resolution_overdue", "алерт — о нарушении закрытия");
    const c = await env.card(inc.guid);
    assert.ok(!c.journal.some((j) => j.templateKey === W.alerts.noRecipientLog), "записи «алерт не отправлен» нет");
  });

  test("Алерт без получателя (§9, RULE-43): в группе старших операторов никого на месте с доступом — запись в журнале, события нет", async () => {
    for (const [why, patch] of [
      ["у Петровой нет доступа к объекту", (p) => (p.roles = ["Старший оператор"])],
      ["Петровой нет на месте", (p) => (p.agentState = "offline")],
    ]) {
      // Свой набор: в группе старших операторов только Петрова, меня нет
      const fixture = JSON.parse(JSON.stringify(window.IM_FIXTURE));
      fixture.people.dutyGroups.forEach((g) => (g.members = g.members.filter((m) => m !== ME)));
      patch(fixture.people.operators.find((o) => o.id === "petrova"));
      const api = (await standWith({ fixture })).api;
      const inc = (await api.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.state === "new");
      const claim = await api.raw("POST", `/operator/incidents/${enc(inc.guid)}/transitions/claim`, { expectedState: "new", surface: "queue" }, { "If-Match": `"${inc.version}"` });
      assert.status(claim, 200, null, `${why}: взять`);
      const got = [];
      const stop = api.subscribe((m) => got.push(m));
      for (let left = longestResolution() + GRACE + 1; left > 0; left -= 240) {
        await api.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        await api.raw("POST", "/test/clock", { advanceSec: Math.min(240, left) });
      }
      await new Promise((r) => setTimeout(r, 300));
      stop();
      const c = await api.get(`/operator/incidents/${enc(inc.guid)}`);
      assert.ok(c.journal.some((j) => /Норматив закрытия нарушен/.test(jt(j))), `${why}: нарушение записано`);
      assert.ok(c.journal.some((j) => j.templateKey === W.alerts.noRecipientLog), `${why}: в журнале «алерт не отправлен»`);
      assert.ok(!got.some((m) => m.type === "incident.alert"), `${why}: алерта в потоке нет`);
    }
  });

  test("Адресат больше не может принять (§8.1, RULE-39): отняли право «Принимать» — не принятый инцидент в очереди; в работе — не трогается", async () => {
    const env = await makeEnv();
    const inc = (await env.all("open")).find((e) => e.state === "new");
    assert.status(await env.act(inc.guid, "transfer", { targetId: "petrova", comment: "тест" }, "queue"), 200, null, "передать Петровой");
    const working = await env.guidOf("INC-1846");
    // «Наблюдатель» видит всё, но принимать не может
    const res = await env.call("PUT", "/test/operators/petrova/roles", { roles: ["Наблюдатель"] });
    assert.status(res, 200, null, "сменить роли Петровой");
    assert.ok(res.body.fired.some((f) => f.incidentGuid === inc.guid && f.transitionId === "addressee_cannot_accept"), "сработал возврат: адресат не может принять");
    const c = await env.card(inc.guid);
    assert.eq([c.state, c.owner, c.assignmentGroup], ["new", null, null], "снова новый, ничей");
    assert.ok(c.journal.some((j) => /не может принять/.test(jt(j))), "запись в журнале");
    const w = await env.card(working);
    assert.eq([w.state, w.owner && w.owner.id], ["in_progress", "petrova"], "INC-1846 у Петровой в работе — не трогается");
    // Группе старших операторов хватает меня: я в ней отдельным участником и могу принять
    const forGroup = await env.card(await env.guidOf("INC-1836"));
    assert.eq([forGroup.state, forGroup.assignmentGroup && forGroup.assignmentGroup.id], ["pending_acceptance", "grp-leads"], "INC-1836 остался группе");
  });

  test("Группа больше не может принять (§8.1, RULE-39): ни у одного участника нет и права, и доступа — инцидент в очереди", async () => {
    const all = W.permissions.map((p) => p.key).filter((k) => k !== "incident:schema:admin");
    // Я в группе старших операторов отдельным участником, но без права «Принимать»; Петрова — по роли «Старший оператор»
    const env = await makeEnv({ permissions: all.filter((k) => k !== "incident:accept") });
    const guid = await env.guidOf("INC-1836");
    const before = await env.ok("PUT", "/test/operators/petrova/roles", { roles: ["Оператор", "Старший оператор"] });
    assert.ok(!before.fired.some((f) => f.incidentGuid === guid), "пока Петрова в группе — группа может принять");
    const res = await env.call("PUT", "/test/operators/petrova/roles", { roles: ["Оператор"] });
    assert.ok(res.body.fired.some((f) => f.incidentGuid === guid && f.transitionId === "addressee_cannot_accept"), "в группе остался только я, без права «Принимать»");
    const c = await env.card(guid);
    assert.eq([c.state, c.owner, c.assignmentGroup], ["new", null, null], "снова новый, ничей, без группы");
  });

  test("Переоткрыть: в работе у меня, результат очищен, нарушения сохранены; после срока — нельзя", async () => {
    const env = await makeEnv();
    const done = await env.find((e) => e.state === "closed");
    const res = await env.act(done.guid, "reopen", { comment: "вернулись" });
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.state, "in_progress", "состояние");
    assert.eq(c.owner.id, ME, "владелец");
    assert.eq(c.closeResultId, null, "результат очищен");
    assert.eq(c.slaBreached, done.slaBreached, "отметка нарушения не сбрасывается");
    const other = (await env.all("done"))[0];
    await env.advance(W.limits.reopenWindowMin * 60 + 60);
    await env.act(c.guid, "close", { resultId: "false_alarm", comment: "x" });
    assert.status(await env.act(other.guid, "reopen", { comment: "x" }), 403, "REOPEN_WINDOW_EXPIRED", "после срока переоткрытия");
  });

  /* ===== Автоэскалация и нормативы (§4, §9) ===== */

  test("Автоэскалация по уровням и потолок: адресаты уровней, затем нарушение реакции без новой передачи", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    const reactionSec = W.timers.find((x) => x.id === "reaction").overrides.find((o) => o.priority === TOP).sec;
    await env.advance(reactionSec + GRACE + 1);
    let c = await env.card(inc.guid);
    const levels = W.escalation.levels;
    assert.eq(c.state, "pending_acceptance", "после реакции");
    assert.eq(c.escalationLevel, 1, "уровень");
    assert.eq(c.owner && c.owner.id, levels[0].targetRef.split(":")[1], "адресат уровня 1");
    await env.advance(levels[0].reactionSec + GRACE + 1);
    c = await env.card(inc.guid);
    assert.eq(c.escalationLevel, 2, "уровень 2");
    assert.eq(c.owner && c.owner.id, levels[1].targetRef.split(":")[1], "адресат уровня 2");
    await env.advance(levels[1].reactionSec + GRACE + 1);
    c = await env.card(inc.guid);
    assert.eq(c.escalationLevel, W.escalation.maxLevel, "выше потолка не поднимается");
    assert.ok(c.breaches.some((b) => b.kind === "reaction"), "нарушение реакции записано");
    assert.ok(c.journal.some((j) => /Автоэскалация/.test(jt(j))), "автоэскалация в журнале");
  });

  test("Эскалация по нормативу закрытия (§9, RULE-27): при escalate — передача адресату уровня, на потолке — нарушение и алерт", async () => {
    // Своя копия машины с другой настройкой — так правило проверяется из машины, а не из кода
    async function overdue(patch) {
      const w = JSON.parse(JSON.stringify(W));
      w.escalation.onResolutionOverdue = "escalate";
      patch(w);
      const api = (await standWith({ workflow: w })).api;
      const fire = (await api.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find(
        (e) => e.state === "new" && e.eventType.id === "fire" && e.priority === TOP
      );
      const etag = (await api.raw("GET", `/operator/incidents/${enc(fire.guid)}`)).headers.etag;
      const claimed = await api.raw("POST", `/operator/incidents/${enc(fire.guid)}/transitions/claim`, { formValues: {}, surface: "queue" }, { "If-Match": etag });
      assert.status(claimed, 200, null, "взять");
      // Оператор на месте: часы шагами короче idleHoldSec, перед каждым — heartbeat. Ровно до
      // истечения норматива критического пожара: дальше по времени пошла бы уже реакция уровня (RULE-41)
      let left = w.timers.find((t) => t.id === "resolution").byPriority[TOP] + GRACE + 1;
      const fired = [];
      while (left > 0) {
        const step = Math.min(left, w.session.idleHoldSec - 1);
        await api.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        fired.push(...(await api.raw("POST", "/test/clock", { advanceSec: step })).body.fired.filter((f) => f.incidentGuid === fire.guid).map((f) => f.transitionId));
        left -= step;
      }
      return { fired, card: await api.get(`/operator/incidents/${enc(fire.guid)}`), w };
    }
    const up = await overdue(() => {});
    assert.eq(up.fired, ["resolution_escalate"], "сработала эскалация, а не алерт");
    const level1 = up.w.escalation.levels[0].targetRef.split(":")[1];
    assert.eq([up.card.state, up.card.owner && up.card.owner.id, up.card.escalationLevel], ["pending_acceptance", level1, 1], "передан адресату первого уровня");
    assert.eq(up.card.breaches.filter((b) => b.kind === "resolution").length, 1, "нарушение закрытия записано");
    const top = await overdue((w) => (w.escalation.maxLevel = 0));
    assert.eq(top.fired, ["resolution_ceiling"], "на потолке — алерт, без передачи");
    assert.eq([top.card.state, top.card.owner && top.card.owner.id], ["in_progress", ME], "остался в работе у меня");
    assert.eq(top.card.breaches.filter((b) => b.kind === "resolution").length, 1, "нарушение закрытия записано");
  });

  test("Автоэскалация пропускает уровни, у адресата которых нет доступа к объекту (§8.3); нет никого — никому не передаётся, нарушение и алерт", async () => {
    // Своя копия машины: адресаты уровней — из targets. Ждём ровно до истечения реакции инцидента
    async function escalate(targets, pick) {
      const w = JSON.parse(JSON.stringify(W));
      targets.forEach((ref, i) => (w.escalation.levels[i].targetRef = ref));
      const stand = await standWith({ workflow: w });
      const api = stand.api;
      const reset = { body: { now: new Date(stand.now).toISOString() } };
      const inc = (await api.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.state === "new" && e.escalationLevel === 0 && pick(e));
      let left = Math.ceil((Date.parse(inc.timer.dueAt) - Date.parse(reset.body.now)) / 1000) + GRACE + 1;
      const fired = [];
      while (left > 0) {
        const step = Math.min(left, w.session.idleHoldSec - 1);
        await api.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        fired.push(...(await api.raw("POST", "/test/clock", { advanceSec: step })).body.fired.filter((f) => f.incidentGuid === inc.guid).map((f) => f.transitionId));
        left -= step;
      }
      return { fired, card: await api.get(`/operator/incidents/${enc(inc.guid)}`) };
    }
    const inMall = (e) => e.site === "Торговый центр";
    const skip = await escalate(["user:kuznetsov", "user:noc"], (e) => !inMall(e));
    assert.eq([skip.fired, skip.card.owner && skip.card.owner.id, skip.card.escalationLevel], [["auto_escalate"], "noc", 2], "вне ТЦ: уровень 1 без доступа пропущен — сразу уровень 2");
    const keep = await escalate(["user:kuznetsov", "user:noc"], inMall);
    // Кузнецов в наборе вышел: эскалация на него — и сразу его группе «Охрана ТЦ» (RULE-47)
    assert.eq(keep.fired, ["auto_escalate", "addressee_signed_out_to_group"], "в ТЦ: уровень 1, Кузнецов — он вышел, сразу его группе");
    assert.eq([keep.card.owner, keep.card.assignmentGroup && keep.card.assignmentGroup.id, keep.card.escalationLevel], [null, "grp-tc", 1], "у «Охраны ТЦ», уровень 1");
    const none = await escalate(["user:kuznetsov", "user:kuznetsov"], (e) => !inMall(e));
    assert.eq(none.fired, ["escalation_ceiling"], "вне ТЦ и некому — сработал потолок эскалации: нарушение и алерт");
    assert.eq([none.card.state, none.card.owner, none.card.escalationLevel], ["new", null, 0], "никому не передан");
    assert.ok(none.card.breaches.some((b) => b.kind === "reaction"), "нарушение реакции записано");
  });

  test("Истёкший норматив закрытия срабатывает один раз: возврат в работу не даёт нового срока (§4, RULE-50)", async () => {
    // «Отложить → Возобновить» после истечения — без второго нарушения и алерта
    const env = await makeEnv();
    const inc = await newFire(env);
    const res = await env.act(inc.guid, "claim", {}, "queue");
    await env.advance(Math.ceil((Date.parse(res.body.incident.timer.dueAt) - env.now) / 1000) + GRACE + 1);
    assert.status(await env.act(inc.guid, "hold", { reasonId: "third_party", comment: "ждём" }), 200, null, "отложить");
    assert.status(await env.act(inc.guid, "resume"), 200, null, "возобновить");
    const again = await env.advance(5);
    assert.ok(!again.some((f) => f.incidentGuid === inc.guid), `после возобновления ничего не сработало: ${again.map((f) => f.transitionId)}`);
    assert.eq((await env.card(inc.guid)).breaches.filter((b) => b.kind === "resolution").length, 1, "нарушение закрытия одно");
    // Эскалация по закрытию на мою группу: принявший работает с инцидентом, его не уводят дальше
    const levels = W.escalation.levels.map((l, i) => (i === 0 ? Object.assign({}, l, { targetRef: "group:grp-leads" }) : l));
    const esc = await standWith({ workflow: Object.assign({}, W, { escalation: Object.assign({}, W.escalation, { onResolutionOverdue: "escalate", levels }) }) });
    const fire = await newFire(esc);
    const claimed = await esc.act(fire.guid, "claim", {}, "queue");
    const fired = await esc.advance(Math.ceil((Date.parse(claimed.body.incident.timer.dueAt) - esc.now) / 1000) + GRACE + 1);
    assert.ok(fired.some((f) => f.incidentGuid === fire.guid && f.transitionId === "resolution_escalate"), "эскалация по закрытию — моей группе");
    assert.status(await esc.act(fire.guid, "accept", {}, "queue"), 200, null, "принять");
    const after = await esc.advance(5);
    assert.ok(!after.some((f) => f.incidentGuid === fire.guid), `после «Принять» ничего не сработало: ${after.map((f) => f.transitionId)}`);
    const c = await esc.card(fire.guid);
    assert.eq([c.state, c.owner && c.owner.id, c.escalationLevel, c.breaches.filter((b) => b.kind === "resolution").length], ["in_progress", ME, 1, 1], "у меня в работе, уровень 1, нарушение одно");
  });

  test("Норматив закрытия истёк — нарушение «resolution» один раз, состояние не меняется", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    const res = await env.act(inc.guid, "claim", {}, "queue");
    const left = Date.parse(res.body.incident.timer.dueAt) - env.now;
    await env.advance(Math.ceil(left / 1000) + GRACE + 1);
    let c = await env.card(inc.guid);
    assert.eq(c.state, "in_progress", "состояние");
    assert.eq(c.breaches.filter((b) => b.kind === "resolution").length, 1, "одно нарушение");
    await env.advance(60);
    c = await env.card(inc.guid);
    assert.eq(c.breaches.filter((b) => b.kind === "resolution").length, 1, "повторно не срабатывает");
  });

  /* ===== Перерыв (§12) ===== */

  test("Оператор замолчал (§12.3): через idleHoldSec — «Отложен, нет связи», через idleReleaseSec — снова в очереди, ничей", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    assert.status(await env.act(inc.guid, "claim", {}, "queue"), 200, null, "взять");
    // Часы идут без heartbeat: оператор не на связи
    const silent = async (sec) => {
      const res = await env.call("POST", "/test/clock", { advanceSec: sec });
      assert.status(res, 200, null, "сдвиг часов");
      return res.body.fired.filter((f) => f.incidentGuid === inc.guid).map((f) => f.transitionId);
    };
    assert.eq(await silent(W.session.idleHoldSec - 10), [], "до idleHoldSec ничего не происходит");
    assert.eq(await silent(20), ["system_hold_idle"], "после idleHoldSec — системное «Отложить»");
    let c = await env.card(inc.guid);
    assert.eq([c.state, c.holdReasonId, c.owner && c.owner.id], ["on_hold", "no_link", ME], "отложен у оператора, причина «нет связи»");
    assert.eq(await silent(W.session.idleReleaseSec - W.session.idleHoldSec), ["system_release_idle"], "после idleReleaseSec — возврат в очередь");
    c = await env.card(inc.guid);
    assert.eq([c.state, c.owner], ["new", null], "снова новый, ничей");
  });

  test("Перерыв: инцидент в работе откладывается системой, действия недоступны; после возврата — доступны", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    const res = await env.ok("PUT", "/operator/session/agent-state", { agentState: "not_ready", reasonId: "lunch" });
    assert.eq(res.session.agentState, "not_ready", "состояние оператора");
    assert.eq(res.affectedIncidents.map((x) => x.guid), [inc.guid], "отложенные системой");
    const c = await env.card(inc.guid);
    assert.eq(c.state, "on_hold", "состояние");
    assert.eq(c.holdReasonId, "break", "причина «перерыв»");
    assert.ok(c.readOnly, "на перерыве — просмотр");
    const other = await env.find((e) => e.state === "new");
    assert.ok(!actionOf(other, "claim").enabled, "«Взять» на перерыве недоступно");
    await env.ok("PUT", "/operator/session/agent-state", { agentState: "ready" });
    assert.status(await env.act(inc.guid, "resume", {}, "queue"), 200, null, "возобновить после возврата");
  });

  test("Лимит отложенных — только для ручного «Отложить»: перерыв откладывает и сверх лимита (§10.2)", async () => {
    const env = await makeEnv();
    const max = W.limits.maxOnHold;
    let held = (await env.session()).usage.onHoldCount;
    while (held < max) {
      const inc = await env.find((e) => e.state === "new");
      await env.act(inc.guid, "claim", {}, "queue");
      await env.act(inc.guid, "hold", { reasonId: "no_data", comment: "x" });
      held = (await env.session()).usage.onHoldCount;
    }
    const inc = await env.find((e) => e.state === "new");
    await env.act(inc.guid, "claim", {}, "queue");
    assert.status(await env.act(inc.guid, "hold", { reasonId: "no_data", comment: "x" }), 403, "LIMIT_EXCEEDED", "ручное сверх лимита");
    await env.ok("PUT", "/operator/session/agent-state", { agentState: "not_ready", reasonId: "lunch" });
    assert.eq((await env.card(inc.guid)).state, "on_hold", "перерыв отложил сверх лимита");
  });

  test("Лимиты без ограничения (null или нет поля): взять больше одного, отложить больше пяти, выбрать и закрыть больше десяти (§10.2, §11, RULE-69)", async () => {
    const workflow = JSON.parse(JSON.stringify(W));
    Object.assign(workflow.limits, { maxActive: null, maxOnHold: null, maxBulk: null });
    const env = await standWith({ workflow });
    const news = (await env.all("open")).filter((e) => e.state === "new").slice(0, 3);
    for (const inc of news) assert.status(await env.act(inc.guid, "claim", {}, "queue"), 200, null, `взять ${inc.number}`);
    assert.ok((await env.session()).usage.activeCount >= 3, "в работе больше одного");
    // Отложить сверх прежних пяти: берём и откладываем, пока отложенных не станет на одно больше
    const target = (W.limits.maxOnHold || 5) + 1;
    for (let held = (await env.session()).usage.onHoldCount, guard = 0; held < target && guard < 10; guard++) {
      const inc = await env.find((e) => e.state === "new" || (e.state === "in_progress" && e.ownership === "mine"));
      if (inc.state === "new") assert.status(await env.act(inc.guid, "claim", {}, "queue"), 200, null, "взять");
      assert.status(await env.act(inc.guid, "hold", { reasonId: "no_data", comment: "x" }), 200, null, `отложить ${held + 1}-й`);
      held = (await env.session()).usage.onHoldCount;
    }
    assert.ok((await env.session()).usage.onHoldCount >= target, `отложено ${target} и больше`);
    const all = await env.ok("POST", "/operator/incidents/selection", { mode: "all_in_filter", filter: "open" });
    assert.ok(all.incidentGuids.length > (W.limits.maxBulk || 10) && !all.truncated, `«Выбрать все» — все ${all.incidentGuids.length}, без обрезки`);
    const cause = W.reasonCatalogs.mass_fault.items[0].id;
    const bulk = await env.call("POST", "/operator/incidents/transitions/close/bulk", { incidentGuids: all.incidentGuids, formValues: { resultId: "mass", causeId: cause, comment: "тест" }, surface: "queue" });
    assert.status(bulk, 200, null, "массовое действие на всю выборку");
    assert.eq(bulk.body.succeeded.length + bulk.body.failed.length, all.incidentGuids.length, "каждый инцидент выборки — в итоге");
  });

  test("Сервер проверяет лимит выборки: в массовом действии больше maxBulk — 422 целиком (§11, BUG-40)", async () => {
    // Предел задаёт администратор; в эталонной схеме его нет (null) — здесь он 10
    const max = 10;
    const env = await makeEnv({ workflowPatch: { limits: { maxBulk: max } } });
    const guids = (await env.all("open")).map((e) => e.guid);
    assert.ok(guids.length > max, "открытых больше лимита");
    const cause = W.reasonCatalogs.mass_fault.items[0].id;
    const body = (list) => ({ incidentGuids: list, formValues: { resultId: "mass", causeId: cause, comment: "тест" }, surface: "queue" });
    const over = await env.call("POST", "/operator/incidents/transitions/close/bulk", body(guids.slice(0, max + 1)));
    assert.status(over, 422, "BULK_SELECTION_INVALID", `${max + 1} — больше лимита`);
    assert.eq(over.body.messageKey, "workflow.error.selection_too_large", "причина — размер выборки");
    assert.status(await env.call("POST", "/operator/incidents/transitions/close/bulk", body(guids.slice(0, max))), 200, null, `${max} — в пределах лимита`);
  });

  /* ===== Выборка (§11) ===== */

  test("Внешние эффекты перехода — в ответе со статусом queued; себе и некому уведомления нет (§14.2, BUG-30)", async () => {
    const env = await makeEnv();
    const [a, b] = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire").slice(0, 2);
    const effects = (res) => res.body.externalEffects.map((x) => [x.fn, x.target, x.status]);
    const sent = await env.act(a.guid, "transfer", { targetId: "petrova", comment: "тест" }, "card");
    assert.status(sent, 200, null, "передать новый");
    assert.eq(effects(sent), [["notify", "petrova", "queued"]], "«Передать» новый: только новому адресату — прежнего владельца нет");
    const taken = await env.act(a.guid, "takeover", { comment: "беру" }, "card");
    assert.status(taken, 200, null, "перехватить у Петровой");
    assert.eq(effects(taken), [["notify", "petrova", "queued"]], "«Перехватить»: прежнему владельцу");
    const closed = await env.act(a.guid, "close", { resultId: "false_alarm", comment: "тест" }, "card");
    assert.status(closed, 200, null, "закрыть");
    assert.eq(effects(closed), [["externalCommand", "axxondata.export_incident", "queued"]], "«Закрыть»: выгрузка в AxxonData");
    assert.status(await env.act(b.guid, "claim", {}, "queue"), 200, null, "взять второй");
    const own = await env.act(b.guid, "transfer", { targetId: "petrova", comment: "тест" }, "card");
    assert.eq(effects(own), [["notify", "petrova", "queued"]], "«Передать» свой: себе уведомления нет");
  });

  test("Переоткрыть на границе срока: ровно срок — можно, на 20 секунд больше — нельзя (§6.1, BUG-31)", async () => {
    const env = await makeEnv();
    const [a, b] = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire").slice(0, 2);
    const form = { resultId: "false_alarm", comment: "тест" };
    for (const inc of [a, b]) {
      assert.status(await env.act(inc.guid, "claim", {}, "queue"), 200, null, `взять ${inc.number}`);
      assert.status(await env.act(inc.guid, "close", form, "card"), 200, null, `закрыть ${inc.number}`);
    }
    await env.advance(W.limits.reopenWindowMin * 60);
    assert.status(await env.act(a.guid, "reopen", { comment: "ровно срок" }, "card"), 200, null, "ровно срок — можно");
    assert.status(await env.act(a.guid, "close", form, "card"), 200, null, "закрыть снова — освободить лимит");
    await env.advance(20);
    assert.status(await env.act(b.guid, "reopen", { comment: "поздно" }, "card"), 403, "REOPEN_WINDOW_EXPIRED", "срок плюс 20 секунд — нельзя");
  });

  test("Каталог строк: язык из запроса или настроек оператора, неизвестный язык — русский (§14.9, RULE-66)", async () => {
    const env = await makeEnv();
    const S = window.IM_STRINGS;
    const en = await env.ok("GET", "/operator/strings?locale=en");
    assert.eq(en.locale, "en", "язык");
    assert.eq(Object.keys(en.strings).sort(), Object.keys(S.ru).sort(), "все ключи каталога");
    assert.eq(en.strings["workflow.state.new"], S.en["workflow.state.new"], "строка на английском");
    assert.status(await env.call("PATCH", "/operator/session/preferences", { locale: "en" }), 200, null, "язык оператора");
    const es = await env.ok("GET", "/operator/strings");
    assert.eq([es.locale, es.strings["workflow.transition.claim"]], ["en", S.en["workflow.transition.claim"]], "без locale — язык из настроек");
    const xx = await env.ok("GET", "/operator/strings?locale=xx");
    assert.eq(xx.strings, S.ru, "неизвестный язык — русские строки");
  });

  test("Появление инцидента: новый, ничей, уровень 0, норматив реакции от появления, запись журнала, событие потока (§6.2, RULE-61)", async () => {
    const env = await makeEnv();
    const got = [];
    const stop = env.api.subscribe((m) => got.push(m));
    await new Promise((r) => setTimeout(r, 300));
    const fire = (await env.all("open")).find((e) => e.eventType.id === "fire");
    const source = (await env.card(fire.guid)).source.guid;
    // Событие у источника — час назад: норматив реакции всё равно от появления в МИ
    const occurredAt = new Date(Date.parse(fire.occurredAt) - 3600 * 1000).toISOString();
    const res = await env.call("POST", "/test/incidents", { eventTypeId: "fire", priority: TOP, deviceIds: [source], site: fire.site, location: "тест", occurredAt });
    assert.status(res, 201, null, "появился");
    const c = res.body;
    assert.eq([c.state, c.owner, c.assignmentGroup, c.escalationLevel], ["new", null, null, 0], "новый, ничей, уровень 0");
    assert.ok(Date.parse(c.createdAt) > Date.parse(c.occurredAt), "время появления позже времени события");
    const norm = W.timers.find((t) => t.id === "reaction").overrides.find((o) => o.priority === TOP).sec;
    assert.ok(c.timer && c.timer.id === "reaction" && c.timer.running, "идёт норматив реакции");
    assert.eq(Date.parse(c.timer.dueAt) - Date.parse(c.createdAt), norm * 1000, "норматив реакции — от появления, а не от времени события");
    assert.eq(lastJournal(c).templateKey, "workflow.journal.create", "запись в журнале");
    assert.ok((await env.all("open")).some((e) => e.guid === c.guid), "в очереди");
    await new Promise((r) => setTimeout(r, 300));
    assert.ok(got.some((m) => m.type === "incident.created" && m.incidentGuid === c.guid), "событие потока incident.created");
    assert.status(await env.call("POST", "/test/incidents", { eventTypeId: "nope", priority: TOP, deviceIds: [source] }), 422, null, "неизвестный тип");
    stop();
  });

  /* ===== Приоритеты — настраиваемый справочник (§2.5, RULE-68) ===== */

  // Появился инцидент пожара с этим приоритетом от источника; ответ — его карточка
  async function fireWith(env, priority) {
    const fire = (await env.all("open")).find((e) => e.eventType.id === "fire");
    const source = (await env.card(fire.guid)).source.guid;
    return env.call("POST", "/test/incidents", Object.assign({ eventTypeId: "fire", deviceIds: [source], site: fire.site, location: "тест" }, priority === undefined ? {} : { priority }));
  }
  const reactionSec = (card) => (Date.parse(card.timer.dueAt) - Date.parse(card.createdAt)) / 1000;

  test("Приоритет от источника приводится к уровню справочника: есть — как есть, нет — ближайший не выше, ниже самого низкого или без числа — самый низкий (§2.5)", async () => {
    const env = await makeEnv();
    const lowest = LEVELS[LEVELS.length - 1];
    // Число между уровнями — ближайший не выше: инцидент не кажется срочнее, чем по настройке
    const between = LEVELS[1] + 1;
    for (const [sent, expected] of [[TOP, TOP], [between, LEVELS[1]], [lowest - 1, lowest], [undefined, lowest]]) {
      const res = await fireWith(env, sent);
      assert.status(res, 201, null, `приоритет ${sent}`);
      assert.eq(res.body.priority, expected, `${sent} → ${expected}`);
    }
    for (const bad of [101, -1, 50.5, "high"]) assert.status(await fireWith(env, bad), 422, null, `приоритет ${JSON.stringify(bad)} — не целое 0–100`);
  });

  test("Другой справочник приоритетов — без правки кода: порядок, фильтр, самый срочный, нормативы, событие reference.priorities_changed (§2.5, RULE-68)", async () => {
    // Пять уровней, ни одного прежнего числа; у двух — один цвет; свои нормативы — только у двух
    const levels = [
      { value: 95, name: { ru: "Угроза", en: "Threat" }, color: "red" },
      { value: 80, name: { ru: "Повышенный", en: "Elevated" }, color: "red" },
      { value: 60, name: { ru: "Обычный", en: "Regular" }, color: "amber" },
      { value: 40, name: { ru: "Пониженный", en: "Reduced" }, color: "blue" },
      { value: 10, name: { ru: "Информация", en: "Info" }, color: "grey" },
    ];
    const remap = Object.fromEntries(LEVELS.map((v, i) => [v, [95, 80, 60, 10][i]]));
    const fixture = JSON.parse(JSON.stringify(window.IM_FIXTURE));
    fixture.priorities = levels;
    fixture.incidents.forEach((inc) => (inc.priority = remap[inc.priority]));
    const workflow = JSON.parse(JSON.stringify(W));
    const reaction = workflow.timers.find((t) => t.id === "reaction");
    reaction.overrides = [{ priority: 95, sec: 120 }, { priority: 60, sec: 600 }];
    workflow.timers.find((t) => t.id === "resolution").byPriority = { 95: 600, 60: 1500 };

    const base = await makeEnv();
    const got = [];
    const stop = base.api.subscribe((m) => got.push(m));
    await new Promise((r) => setTimeout(r, 300));
    const env = await standWith({ workflow, fixture });
    await new Promise((r) => setTimeout(r, 300));
    stop();
    assert.ok(got.some((m) => m.type === "reference.priorities_changed"), "событие reference.priorities_changed");

    const ref = await env.ok("GET", "/operator/reference/priorities");
    assert.eq(ref.map((p) => p.value), [95, 80, 60, 40, 10], "справочник — новый, по убыванию числа");
    const all = await queueOf(env);
    assert.ok(all.every((i, n) => !n || all[n - 1].priority >= i.priority), "очередь — по числу, большее выше");
    const elevated = await queueOf(env, "&priority=80");
    assert.ok(elevated.length && elevated.length === all.filter((i) => i.priority === 80).length, "фильтр по новому уровню");

    // Самый срочный — наибольшее число нового справочника, а не прежний «критический»
    const tree = await env.ok("GET", "/operator/reference/source-groups?withCounters=true");
    const nodes = [];
    const walk = (list) => list.forEach((n) => (nodes.push(n), n.devices.forEach((d) => d.counters && nodes.push(d)), walk(n.children || [])));
    walk(tree);
    assert.ok(nodes.some((n) => n.counters.topPriority > 0), "в дереве есть инциденты самого срочного уровня 95");
    assert.ok(nodes.every((n) => n.counters.topPriority <= n.counters.open), "срочных не больше открытых");

    // Нормативы: у уровня со своей строкой — она, без строки — по умолчанию (§4, правило 2)
    assert.eq(reactionSec((await fireWith(env, 95)).body), 120, "95 — своя строка норматива");
    const plain = (await fireWith(env, 85)).body;
    assert.eq([plain.priority, reactionSec(plain)], [80, reaction.defaultSec], "85 → 80, без своей строки — норматив по умолчанию");
  });

  test("Поток событий: ручной переход, нарушение, ответы сценария, макрос — каждый своим событием (§9, RULE-60)", async () => {
    const escalation = Object.assign({}, W.escalation, { enabled: false });
    const env = await makeEnv({ workflowPatch: { escalation } });
    const got = [];
    const stop = env.api.subscribe((m) => got.push(m));
    await new Promise((r) => setTimeout(r, 300));
    const [a, b] = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire");
    assert.status(await env.act(a.guid, "claim", {}, "queue"), 200, null, "взять");
    assert.status(await env.answer(a.guid, { visual: true }), 200, null, "ответ сценария");
    const macro = (await env.call("GET", `/operator/incidents/${enc(a.guid)}/scenario`)).body.steps.find((s) => s.type === "Macros");
    if (macro) assert.status(await env.call("POST", `/operator/incidents/${enc(a.guid)}/macros/${enc(macro.view.buttons[0])}`), 202, null, "макрос");
    await env.advance(W.timers.find((x) => x.id === "reaction").overrides.find((o) => o.priority === b.priority).sec + GRACE + 1);
    await new Promise((r) => setTimeout(r, 300));
    stop();
    const of = (type, guid, tid) => got.find((m) => m.type === type && m.incidentGuid === guid && (!tid || m.payload.transitionId === tid));
    const claim = of("incident.transitioned", a.guid, "claim");
    assert.ok(claim, `«Взять»: ${got.map((m) => m.type).join(", ")}`);
    assert.eq([claim.payload.trigger, claim.payload.state.from, claim.payload.state.to, claim.payload.owner.from, claim.payload.owner.to.id, claim.payload.breach], ["manual", "new", "in_progress", null, ME, null], "«Взять»: было → стало");
    const overdue = of("incident.transitioned", b.guid, "reaction_overdue");
    assert.ok(overdue && overdue.payload.breach === "reaction" && overdue.payload.state.from === overdue.payload.state.to, "нарушение реакции: breach, состояние не меняется");
    assert.ok(of("incident.updated", a.guid) && of("incident.updated", a.guid).payload.stepIds.includes("visual"), "ответы сценария — incident.updated");
    if (macro) assert.ok(of("macro.completed", a.guid), "макрос — macro.completed");
    const old = got.filter((m) => ["incident.state_changed", "incident.owner_changed", "incident.auto_escalated", "incident.sla_breached"].includes(m.type));
    assert.eq(old.map((m) => m.type), [], "старых типов событий нет");
  });

  test("Окно после дедлайна: «Взять» в окне выигрывает у таймера, после окна — нет (§10.1, правило 5; RULE-63)", async () => {
    assert.ok(GRACE > 0, "окно задано в машине");
    const norm = (inc) => W.timers.find((x) => x.id === "reaction").overrides.find((o) => o.priority === inc.priority).sec;
    // Автоэскалация включена: отменённая эскалация — запись в журнале, без нарушения (эскалация его и не пишет)
    let env = await makeEnv();
    let inc = await newFire(env);
    let due = Date.parse(inc.timer.dueAt);
    await env.advance(norm(inc) + 1);
    let res = await env.act(inc.guid, "claim", {}, "queue");
    assert.status(res, 200, null, "«Взять» через секунду после дедлайна");
    let c = res.body.incident;
    assert.eq([res.body.canceledTimerTrigger, c.state, c.escalationLevel, c.breaches.length], ["auto_escalate", "in_progress", 0, 0], "эскалация отменена, нарушения нет");
    assert.ok(c.journal.some((j) => j.templateKey === "workflow.journal.timer_overridden"), "отмена — в журнале");
    // Автоэскалация выключена: отменённое «Норматив реакции нарушен» — нарушение на момент дедлайна
    env = await makeEnv({ workflowPatch: { escalation: Object.assign({}, W.escalation, { enabled: false }) } });
    inc = await newFire(env);
    due = Date.parse(inc.timer.dueAt);
    await env.advance(norm(inc) + 1);
    res = await env.act(inc.guid, "claim", {}, "queue");
    assert.status(res, 200, null, "«Взять» в окне при выключенной эскалации");
    c = res.body.incident;
    assert.eq(res.body.canceledTimerTrigger, "reaction_overdue", "отменено «норматив реакции нарушен»");
    assert.ok(c.breaches.length === 1 && c.breaches[0].kind === "reaction" && Date.parse(c.breaches[0].at) === due, `нарушение реакции на момент дедлайна: ${JSON.stringify(c.breaches)}`);
    // После окна таймер уже сработал: инцидент ушёл по эскалации, «Взять» не из этого состояния
    env = await makeEnv();
    inc = await newFire(env);
    await env.advance(norm(inc) + GRACE + 1);
    assert.eq((await env.card(inc.guid)).state, "pending_acceptance", "после окна — автоэскалация");
    assert.status(await env.act(inc.guid, "claim", {}, "queue"), 409, "TRANSITION_NOT_ALLOWED_FROM_STATE", "«Взять» после окна");
  });

  test("Окно после дедлайна: «Передать» и «Отклонить» таймер не отменяют — реакция продолжается, автоэскалация по окончании окна (RULE-83)", async () => {
    assert.ok(GRACE > 0, "окно задано в машине");
    const toDue = (env, inc) => Math.round((Date.parse(inc.timer.dueAt) - env.now) / 1000);
    const levelZero = (env) => env.find((e) => e.state === "new" && e.eventType.id === "fire" && e.priority === TOP && e.escalationLevel === 0);
    const [first, second] = W.escalation.levels;
    const idOf = (level) => level.targetRef.split(":")[1];
    // «Передать» Сидорову через секунду после дедлайна: эскалация не отменена — по окончании окна уровню 1
    let env = await makeEnv();
    let inc = await levelZero(env);
    await env.advance(toDue(env, inc) + 1);
    let res = await env.act(inc.guid, "transfer", { targetId: "sidorov", comment: "тест" }, "card");
    assert.status(res, 200, null, "«Передать» в окне");
    assert.eq(res.body.canceledTimerTrigger, null, "срабатывание не отменено");
    await env.advance(GRACE);
    let c = await env.card(inc.guid);
    assert.eq([c.state, c.owner && c.owner.id, c.escalationLevel], ["pending_acceptance", idOf(first), 1], "по окончании окна — автоэскалация уровню 1");
    // «Отклонить» адресатом уровня 1 через секунду после его дедлайна: по окончании окна — уровню 2
    env = await standWith({ workflow: Object.assign({}, W, { escalation: Object.assign({}, W.escalation, { levels: [Object.assign({}, first, { targetRef: `user:${ME}` }), second] }) }) });
    inc = await levelZero(env);
    await env.advance(toDue(env, inc) + GRACE + 1);
    c = await env.card(inc.guid);
    assert.eq([c.state, c.owner && c.owner.id, c.escalationLevel], ["pending_acceptance", ME, 1], "автоэскалация на меня");
    await env.advance(toDue(env, c) + 1);
    res = await env.act(inc.guid, "reject", { comment: "тест" }, "card");
    assert.status(res, 200, null, "«Отклонить» в окне");
    assert.eq(res.body.canceledTimerTrigger, null, "срабатывание не отменено");
    await env.advance(GRACE);
    c = await env.card(inc.guid);
    assert.eq([c.state, c.owner && c.owner.id, c.escalationLevel], ["pending_acceptance", idOf(second), 2], "по окончании окна — автоэскалация уровню 2");
  });

  test("После потолка и нарушения реакции: «Передать» запускает её по нормативу уровня, «Отклонить» — нет (RULE-84)", async () => {
    const toDue = (env, inc) => Math.round((Date.parse(inc.timer.dueAt) - env.now) / 1000);
    const firedFor = (fired, guid) => fired.filter((f) => f.incidentGuid === guid).map((f) => f.transitionId);
    const reactions = (card) => card.breaches.filter((b) => b.kind === "reaction").length;
    // Эскалация выключена: нарушение реакции остановило её; «Передать» — у адресата новый срок, истёк — второе нарушение
    let env = await standWith({ workflow: Object.assign({}, W, { escalation: Object.assign({}, W.escalation, { enabled: false }) }) });
    let inc = await newFire(env);
    assert.eq(firedFor(await env.advance(toDue(env, inc) + GRACE + 1), inc.guid), ["reaction_overdue"], "нарушение реакции");
    let res = await env.act(inc.guid, "transfer", { targetId: "sidorov", comment: "тест" }, "card");
    assert.status(res, 200, null, "передать после нарушения");
    let c = res.body.incident;
    assert.ok(c.timer && Date.parse(c.timer.dueAt) > env.now, `у адресата новый срок реакции: ${JSON.stringify(c.timer)}`);
    assert.eq(firedFor(await env.advance(toDue(env, c) + GRACE + 1), inc.guid), ["reaction_overdue"], "срок адресата истёк — снова нарушение");
    assert.eq(reactions(await env.card(inc.guid)), 2, "два нарушения реакции");
    // Потолок: единственный уровень — я; не принял — потолок остановил реакцию; «Отклонить» — новый без срока
    const [first] = W.escalation.levels;
    env = await standWith({ workflow: Object.assign({}, W, { escalation: Object.assign({}, W.escalation, { levels: [Object.assign({}, first, { targetRef: `user:${ME}` })], maxLevel: 1 }) }) });
    inc = await env.find((e) => e.state === "new" && e.eventType.id === "fire" && e.priority === TOP && e.escalationLevel === 0);
    assert.eq(firedFor(await env.advance(toDue(env, inc) + GRACE + 1), inc.guid), ["auto_escalate"], "эскалация на меня");
    c = await env.card(inc.guid);
    assert.eq(firedFor(await env.advance(toDue(env, c) + GRACE + 1), inc.guid), ["escalation_ceiling"], "потолок");
    res = await env.act(inc.guid, "reject", { comment: "тест" }, "card");
    assert.status(res, 200, null, "отклонить после потолка");
    c = res.body.incident;
    assert.eq([c.state, Boolean(c.timer && c.timer.dueAt)], ["new", false], "новый в очереди без срока реакции");
    assert.eq(firedFor(await env.advance(3600), inc.guid), [], "за час ничего не сработало");
    assert.eq(reactions(await env.card(inc.guid)), 1, "нарушение реакции одно — от потолка");
  });

  test("Окно после дедлайна: «Взять в работу одним» в окне — нарушение не теряется ни у привязанного, ни у основного (BUG-62)", async () => {
    assert.ok(GRACE > 0, "окно задано в машине");
    const noEscalation = { workflow: Object.assign({}, W, { escalation: Object.assign({}, W.escalation, { enabled: false }) }) };
    const merge = (env, primary, other) => env.call("POST", "/operator/incidents/merge", { incidentGuids: [primary, other], primaryGuid: primary });
    const overriddenAt = (card, kind, due) => {
      assert.eq(card.breaches.map((b) => [b.kind, Date.parse(b.at)]), [[kind, due]], `${card.number}: нарушение ${kind} на момент дедлайна`);
      assert.ok(card.journal.some((j) => j.templateKey === "workflow.journal.timer_overridden"), `${card.number}: отмена — в журнале`);
    };
    // Норматив реакции истёк секунду назад: инцидент привязывается к другому новому — и он же как основной
    for (const asPrimary of [false, true]) {
      const env = await standWith(noEscalation);
      const [late, other] = (await env.all("open"))
        .filter((e) => e.state === "new" && e.eventType.id === "fire")
        .sort((x, y) => Date.parse(x.timer.dueAt) - Date.parse(y.timer.dueAt));
      const due = Date.parse(late.timer.dueAt);
      await env.advance(Math.round((due - env.now) / 1000) + 1);
      const res = asPrimary ? await merge(env, late.guid, other.guid) : await merge(env, other.guid, late.guid);
      assert.status(res, 200, null, asPrimary ? "объединить, основной — с истёкшей реакцией" : "объединить, привязанный — с истёкшей реакцией");
      const c = await env.card(late.guid);
      assert.eq(c.state, asPrimary ? "in_progress" : "linked", "состояние после объединения");
      overriddenAt(c, "reaction", due);
    }
    // Срок удержания истёк секунду назад: свой отложенный привязывается к своему в работе
    const env = await makeEnv();
    const [held, primary] = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire");
    assert.status(await env.act(held.guid, "claim", {}, "queue"), 200, null, "взять будущий привязанный");
    assert.status(await env.act(primary.guid, "claim", {}, "queue"), 200, null, "взять основной");
    const onHold = await env.act(held.guid, "hold", { reasonId: "third_party", comment: "ждём" });
    assert.status(onHold, 200, null, "отложить");
    const due = Date.parse(onHold.body.incident.holdTimer.dueAt);
    await env.advance(Math.round((due - env.now) / 1000) + 1);
    assert.status(await merge(env, primary.guid, held.guid), 200, null, "объединить с отложенным");
    overriddenAt(await env.card(held.guid), "hold", due);
  });

  test("Параметры контракта работают: счётчики дерева групп — только по запросу, журнал постранично (BUG-37)", async () => {
    const env = await makeEnv();
    const plain = await env.ok("GET", "/operator/reference/source-groups");
    const counted = await env.ok("GET", "/operator/reference/source-groups?withCounters=true");
    assert.ok(plain.length && plain.every((n) => n.counters == null), "без withCounters счётчиков нет");
    assert.ok(counted.every((n) => n.counters && typeof n.counters.open === "number"), "с withCounters — счётчики");
    const inc = (await env.all("all")).find((e) => e.state === "closed");
    const all = await env.ok("GET", `/operator/incidents/${enc(inc.guid)}/journal`);
    assert.ok(all.total >= 2 && all.items.length === all.total, `без pageSize — весь журнал: ${all.items.length} из ${all.total}`);
    const second = await env.ok("GET", `/operator/incidents/${enc(inc.guid)}/journal?page=2&pageSize=1`);
    assert.eq([second.items.length, second.total, second.items[0].guid], [1, all.total, all.items[1].guid], "вторая страница по одной записи");
  });

  /* ===== Порядок очереди (§7, RULE-62) ===== */

  const queueOf = async (env, query) => (await env.ok("GET", `/operator/incidents?filter=all&pageSize=1000${query || ""}`)).items;
  // Больше число — выше (§2.5, §7)
  const rankOf = (inc) => -inc.priority;
  const num = (inc) => Number(inc.number.replace(/\D/g, ""));
  const at = (inc) => Date.parse(inc.occurredAt);
  const running = (inc) => Boolean(inc.timer && inc.timer.id === "reaction" && inc.timer.running);
  const ORDER = {
    priority_then_oldest: (a, b) => rankOf(a) - rankOf(b) || at(a) - at(b),
    priority_then_newest: (a, b) => rankOf(a) - rankOf(b) || at(b) - at(a),
    oldest_first: (a, b) => at(a) - at(b),
    reaction_deadline: (a, b) =>
      Number(!running(a)) - Number(!running(b)) || (running(a) ? Date.parse(a.timer.dueAt) - Date.parse(b.timer.dueAt) : at(a) - at(b)),
  };
  const sortedBy = (list, id) => list.slice().sort((a, b) => ORDER[id](a, b) || num(a) - num(b)).map((i) => i.number);

  test("Порядок очереди по умолчанию — приоритет, внутри старые выше; свой порядок оператору без разрешения не дан (§7, RULE-62)", async () => {
    const env = await makeEnv();
    const list = await queueOf(env);
    assert.eq(list.map((i) => i.number), sortedBy(list, "priority_then_oldest"), "по умолчанию");
    assert.eq((await queueOf(env, "&sort=oldest_first")).map((i) => i.number), sortedBy(list, "priority_then_oldest"), "sort без разрешения не учитывается");
    assert.status(await env.call("PATCH", "/operator/session/preferences", { queueSort: "oldest_first" }), 200, null, "выбор оператора");
    assert.eq((await queueOf(env)).map((i) => i.number), sortedBy(list, "priority_then_oldest"), "выбор оператора без разрешения не учитывается");
  });

  test("Порядок очереди: каждый из четырёх, если оператору разрешено выбирать; выбор из настроек — без параметра (§7, RULE-62)", async () => {
    const queueSort = Object.assign({}, W.queueSort, { operatorMayChange: true });
    const env = await makeEnv({ workflowPatch: { queueSort } });
    const list = await queueOf(env);
    for (const id of W.queueSort.options) {
      assert.eq((await queueOf(env, `&sort=${id}`)).map((i) => i.number), sortedBy(list, id), id);
    }
    assert.ok(list.some(running) && list.some((i) => !running(i)), "в наборе есть и с идущим нормативом реакции, и без");
    assert.status(await env.call("PATCH", "/operator/session/preferences", { queueSort: "oldest_first" }), 200, null, "выбор оператора");
    assert.eq((await queueOf(env)).map((i) => i.number), sortedBy(list, "oldest_first"), "без параметра — выбор оператора");
  });

  test("Фильтры очереди по приоритету и состоянию (RULE-62)", async () => {
    const env = await makeEnv();
    const all = await queueOf(env);
    const high = await queueOf(env, `&priority=${LEVELS[1]}`);
    assert.ok(high.length && high.every((i) => i.priority === LEVELS[1]) && high.length === all.filter((i) => i.priority === LEVELS[1]).length, "только второй по срочности");
    const states = await queueOf(env, "&state=new,on_hold");
    assert.ok(states.length && states.every((i) => ["new", "on_hold"].includes(i.state)) && states.length === all.filter((i) => ["new", "on_hold"].includes(i.state)).length, "только новые и отложенные");
  });

  /* ===== Объединение: основной и привязанные инциденты (§11) ===== */

  test("«Выделить по фильтру» с «Одинаковый сценарий»: только то, что можно взять как одно; по умолчанию — где таких больше; чужие не включены; «Взять в работу» доступна (§11)", async () => {
    const env = await makeEnv();
    const body = { sourceGroupGuid: null, filter: { any: [] }, queueFilter: "open" };
    const plain = await env.ok("POST", "/operator/incidents/filter", body);
    const sc = plain.options.scenarios;
    assert.ok(sc.length > 1, "среди открытых — несколько сценариев");
    assert.eq([plain.scenarioGuid, plain.excluded], [null, 0], "без галочки — без отбора по сценарию");
    const top = sc.reduce((a, b) => (b.count > a.count ? b : a));
    const same = await env.ok("POST", "/operator/incidents/filter", Object.assign({}, body, { sameScenario: true }));
    assert.eq([same.scenarioGuid, same.count], [top.id, top.count], "по умолчанию — сценарий, где больше всего можно взять");
    let total = 0;
    let left = 0;
    for (const x of sc.filter((y) => y.count > 0)) {
      const r = await env.ok("POST", "/operator/incidents/filter", Object.assign({}, body, { sameScenario: true, scenarioGuid: x.id }));
      assert.eq([r.scenarioGuid, r.count], [x.id, x.count], `выбранный сценарий «${x.label}»`);
      total += r.count + r.excluded;
      left += r.excluded;
      const sel = await env.ok("POST", "/operator/incidents/selection", { mode: "explicit", incidentGuids: r.incidentGuids });
      const merge = sel.actions.find((a) => a.id === "merge");
      assert.ok(merge.enabled, `«${x.label}»: «Взять в работу» недоступна — ${merge.reason}`);
      const cards = await Promise.all(r.incidentGuids.map((g) => env.card(g)));
      assert.ok(cards.every((c) => c.state === "new" || (c.owner && c.owner.id === ME)), `«${x.label}»: включены чужие`);
    }
    assert.ok(total <= plain.count, "подходят + не включены — не больше всех подходящих");
    assert.ok(left > 0, "в демо-данных есть чужие среди сценариев — их не включили");
    // Без галочки чужой среди отмеченных: причина на «Взять в работу» — его номер, а не основного
    const mixed = await env.ok("POST", "/operator/incidents/selection", { mode: "explicit", incidentGuids: await Promise.all(["INC-1830", "INC-1840"].map((n) => env.guidOf(n))) });
    const blocked = mixed.actions.find((a) => a.id === "merge");
    assert.ok(!blocked.enabled && /^INC-1840: /.test(blocked.reason), `причина: ${blocked.reason}`);
    // Сценарий, где взять нечего, не остаётся выбранным — «Выделить 0» не бывает
    const empty = sc.find((x) => x.count === 0);
    assert.ok(empty, "в демо-данных есть сценарий, где взять нечего");
    const fallback = await env.ok("POST", "/operator/incidents/filter", Object.assign({}, body, { sameScenario: true, scenarioGuid: empty.id }));
    assert.eq([fallback.scenarioGuid, fallback.count], [top.id, top.count], "сценарий без того, что можно взять, — заменён");
    // С галочкой варианты условий — только из того, что можно взять в сценарии: любой выбор что-то оставляет
    for (const x of sc.filter((y) => y.count > 0)) {
      const withBlank = Object.assign({}, body, { filter: { any: [{ deviceTypeId: null, eventTypeIds: [], deviceGuids: [] }] }, sameScenario: true, scenarioGuid: x.id });
      const r = await env.ok("POST", "/operator/incidents/filter", withBlank);
      for (const d of r.options.conditions[0].deviceTypes) {
        const one = await env.ok("POST", "/operator/incidents/filter", Object.assign({}, withBlank, { filter: { any: [{ deviceTypeId: d.id, eventTypeIds: [], deviceGuids: [] }] } }));
        assert.ok(one.count > 0 && one.scenarioGuid === x.id, `«${x.label}», тип «${d.label}»: подходит ${one.count}, сценарий ${one.scenarioGuid}`);
      }
      for (const ev of r.options.conditions[0].eventTypes) {
        const one = await env.ok("POST", "/operator/incidents/filter", Object.assign({}, withBlank, { filter: { any: [{ deviceTypeId: null, eventTypeIds: [ev.id], deviceGuids: [] }] } }));
        assert.ok(one.count > 0 && one.scenarioGuid === x.id, `«${x.label}», события «${ev.label}»: подходит ${one.count}`);
      }
      for (const dev of r.options.conditions[0].devices) {
        const one = await env.ok("POST", "/operator/incidents/filter", Object.assign({}, withBlank, { filter: { any: [{ deviceTypeId: null, eventTypeIds: [], deviceGuids: [dev.id] }] } }));
        assert.ok(one.count > 0 && one.scenarioGuid === x.id, `«${x.label}», устройство «${dev.label}»: подходит ${one.count}`);
      }
    }
    const gone = await env.ok("POST", "/operator/incidents/filter", Object.assign({}, body, { sameScenario: true, scenarioGuid: "нет-такого" }));
    assert.eq(gone.scenarioGuid, top.id, "сценария нет среди подходящих — где больше всего можно взять");
  });

  test("«Выделить по фильтру»: условия через «ИЛИ» — подходит под любое; в условии — каскад: события и устройства только выбранного типа (§11)", async () => {
    const env = await makeEnv();
    const filter = async (any) => env.ok("POST", "/operator/incidents/filter", { sourceGroupGuid: null, filter: { any } });
    const all = await filter([{}]);
    const types = all.options.conditions[0].deviceTypes.filter((o) => o.count);
    assert.ok(types.length >= 2, "событий хотя бы двух типов устройств");
    const [a, b] = types;
    const one = await filter([{ deviceTypeId: a.id }]);
    assert.eq(one.count, a.count, "условие по типу — столько, сколько у варианта");
    const both = await filter([{ deviceTypeId: a.id }, { deviceTypeId: b.id }]);
    assert.eq(both.count, a.count + b.count, "«ИЛИ» — сумма двух типов");
    const cascade = one.options.conditions[0];
    assert.ok(cascade.eventTypes.length && cascade.eventTypes.every((o) => o.count > 0), "события — только того типа, с числами");
    assert.ok(cascade.devices.length && cascade.devices.every((o) => o.count > 0), "устройства — только того типа");
    const narrow = await filter([{ deviceTypeId: a.id, eventTypeIds: [cascade.eventTypes[0].id] }]);
    assert.eq(narrow.count, cascade.eventTypes[0].count, "тип и событие — «И»");
    assert.status(await env.call("POST", "/operator/incidents/filter", { sourceGroupGuid: "nope" }), 404, null, "узла нет");
    assert.status(await env.call("POST", "/operator/incidents/filter", { filter: { color: ["red"] } }), 422, null, "неизвестный признак фильтра");
    // Фильтр очереди: выделяется то, что видно в очереди при этом фильтре
    const done = await env.ok("POST", "/operator/incidents/filter", { filter: { any: [{}] }, queueFilter: "done" });
    const closed = (await env.all("done")).map((e) => e.guid);
    assert.ok(done.count === closed.length && done.incidentGuids.every((g) => closed.includes(g)), "фильтр «Закрытые» — только закрытые");
  });

  test("Панель выборки: недоступное кому-то из отмеченных — с причиной и номером; не относящееся ни к одному — не показано", async () => {
    const env = await makeEnv({ workflowPatch: { limits: { maxActive: 1 } } });
    const news = (await env.all("open")).filter((e) => e.state === "new");
    // Передал свой инцидент Сидорову, взял другой: лимит 1 занят — перехват передачи недоступен
    assert.status(await env.act(news[0].guid, "claim", {}, "queue"), 200);
    assert.status(await env.act(news[0].guid, "transfer", { targetId: "sidorov", comment: "нужен допуск" }), 200, null, "передать Сидорову");
    assert.status(await env.act(news[1].guid, "claim", {}, "queue"), 200);
    const one = await env.ok("POST", "/operator/incidents/selection", { mode: "explicit", incidentGuids: [news[0].guid] });
    const card = actionOf(await env.card(news[0].guid), "takeover");
    const solo = one.actions.find((a) => a.id === "takeover");
    assert.ok(solo.visible && !solo.enabled && solo.reason === card.reason && /Лимит активных/.test(solo.reason), `одно отмеченное — причина как в карточке: ${solo.reason}`);
    // Новый отмечен первым, но причина — того, к кому перехват относится: лимит, а не «не то состояние»
    const two = await env.ok("POST", "/operator/incidents/selection", { mode: "explicit", incidentGuids: [news[2].guid, news[0].guid] });
    const take = two.actions.find((a) => a.id === "takeover");
    assert.ok(take.visible && !take.enabled, "«Перехватить» видна, но недоступна");
    assert.eq(take.reason, `${news[0].number}: ${card.reason}`, "причина — с номером инцидента");
    assert.ok(!two.actions.find((a) => a.id === "accept").visible, "«Принять» ни к одному не относится — не показана");
    assert.ok(two.actions.find((a) => a.id === "close").enabled, "«Закрыть» доступна обоим");
  });

  test("Взять в работу как одно: основной — самый срочный новый, взят мной; привязанные пропали из списков; лимит — одна единица; сценарии разные — нельзя", async () => {
    const env = await makeEnv();
    // Пожары разной срочности: основной — самый срочный, а не первый попавшийся
    const order = (a, b) => b.priority - a.priority || Date.parse(a.occurredAt) - Date.parse(b.occurredAt);
    const all = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire").sort(order);
    const fires = [all[all.length - 1], all[0], all[1]];
    assert.ok(fires[0].priority < fires[1].priority, "есть пожары разной срочности");
    const expected = fires.slice().sort(order)[0];
    const other = (await env.all("open")).find((e) => e.state === "new" && e.eventType.id !== "fire");
    const mixed = await env.ok("POST", "/operator/incidents/selection", { mode: "explicit", incidentGuids: [fires[0].guid, other.guid] });
    const take = mixed.actions.find((a) => a.id === "merge");
    assert.ok(!take.enabled && /Сценарии разные/.test(take.reason), `разные сценарии: ${take.reason}`);
    assert.status(await env.call("POST", "/operator/incidents/merge", { incidentGuids: [fires[0].guid, other.guid] }), 403, null, "разные сценарии — отказ");
    const sel = await env.ok("POST", "/operator/incidents/selection", { mode: "explicit", incidentGuids: fires.map((e) => e.guid) });
    assert.ok(sel.actions.find((a) => a.id === "merge").enabled, "«Взять в работу» на выборке одного сценария");
    const res = await env.call("POST", "/operator/incidents/merge", { incidentGuids: fires.map((e) => e.guid) });
    assert.status(res, 200, null, "взять как одно");
    const primary = res.body.incident;
    assert.eq([primary.guid, primary.state, primary.owner.id, primary.linkedCount], [expected.guid, "in_progress", ME, 2], "основной — самый срочный, у меня в работе, привязанных двое");
    assert.eq(primary.priority, expected.priority, "приоритет основного — свой, объединение его не меняет");
    const others = fires.filter((e) => e.guid !== primary.guid).map((e) => e.guid);
    for (const filter of ["open", "all", "done", "mine", "foreign", "inbox"]) {
      assert.ok((await env.all(filter)).every((e) => !others.includes(e.guid)), `привязанные не в фильтре ${filter}`);
    }
    const linked = await env.card(others[0]);
    assert.eq([linked.state, linked.linkedTo, linked.owner], ["linked", primary.guid, null], "привязанный — «Привязан», ссылка на основной");
    assert.eq((await env.session()).usage.activeCount, 1, "в лимите — одна единица");
  });

  test("Взять в работу как одно: лимит занят — ничего не меняется; к моему в работе — новые присоединяются, приоритет и срок основного — свои", async () => {
    const env = await makeEnv({ workflowPatch: { limits: { maxActive: 1 } } });
    const news = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire");
    // В работу — самый несрочный пожар: присоединяемые срочнее его
    const [b, c] = news;
    const a = news[news.length - 1];
    assert.ok(a.priority < b.priority, "есть пожары разной срочности");
    assert.status(await env.act(a.guid, "claim", {}, "queue"), 200, null, "взять один");
    assert.status(await env.call("POST", "/operator/incidents/merge", { incidentGuids: [b.guid, c.guid] }), 403, "LIMIT_EXCEEDED", "лимит занят — взять новые как одно нельзя");
    const after = await Promise.all([b, c].map((e) => env.card(e.guid)));
    assert.ok(after.every((x) => x.state === "new" && !x.linkedTo), "ничего не изменилось");
    const mine = await env.card(a.guid);
    // Присоединяем новый более срочный: срок его реакции раньше срока закрытия моего — основной всё равно свой
    const urgent = b;
    assert.ok(urgent.priority > mine.priority, "присоединяемый срочнее моего");
    assert.ok(Date.parse(urgent.timer.dueAt) < Date.parse(mine.timer.dueAt), "срок реакции нового раньше срока закрытия моего");
    const res = await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [a.guid, urgent.guid] });
    assert.eq([res.incident.guid, res.incident.linkedCount], [a.guid, 1], "новый присоединён к моему в работе");
    assert.eq([res.incident.timer.id, res.incident.timer.dueAt, res.incident.priority], [mine.timer.id, mine.timer.dueAt, mine.priority], "норматив, срок и приоритет основного — свои");
  });

  test("Привязанные: закрыли основной — закрыты его результатом; переоткрыли — остались закрытыми; «Отсоединить» — снова новое; передача — только с доступом к объектам привязанных (§5)", async () => {
    const people = JSON.parse(JSON.stringify(window.IM_FIXTURE.people));
    people.operators.find((o) => o.id === "kuznetsov").agentState = "ready";
    const env = await makeEnv({ fixturePatch: { people } });
    const [mall, office, third] = await Promise.all(["INC-1847", "INC-1838", "INC-1828"].map((n) => env.guidOf(n)));
    assert.status(await env.call("POST", "/operator/incidents/merge", { incidentGuids: [] }), 422, "BULK_SELECTION_INVALID", "ничего не отмечено");
    assert.status(await env.call("POST", "/operator/incidents/merge", { incidentGuids: [mall, office, third], primaryGuid: mall }), 200, null, "взять как одно с основным в ТЦ");
    const detached = await env.call("DELETE", `/operator/incidents/${enc(mall)}/linked/${enc(third)}`);
    assert.status(detached, 200, null, "отсоединить");
    const back = await env.card(third);
    assert.eq([back.state, back.linkedTo], ["new", null], "отсоединённый — новый, без связи");
    assert.ok((await env.all("open")).some((e) => e.guid === third), "снова в очереди");
    const denied = await env.act(mall, "transfer", { targetId: "kuznetsov", comment: "тест" }, "card");
    assert.status(denied, 403, null, "у Кузнецова нет доступа к объекту привязанного");
    assert.eq(denied.body.messageKey, "workflow.guard.target_no_access_linked", `причина: ${denied.body.message}`);
    assert.status(await env.act(mall, "close", { resultId: "false_alarm", comment: "тест" }, "card"), 200, null, "закрыть основной");
    const closed = await env.card(office);
    assert.eq([closed.state, closed.closeResultId, closed.linkedTo], ["closed", "false_alarm", mall], "привязанный закрыт результатом основного, связь — история");
    assert.eq(closed.journal[closed.journal.length - 1].templateKey, "workflow.journal.close_linked", "в журнале — закрыто вместе с основным");
    assert.status(await env.act(mall, "reopen", { comment: "ещё" }, "card"), 200, null, "переоткрыть основной");
    assert.eq((await env.card(office)).state, "closed", "привязанный остался закрытым");
  });

  test("Два основных со привязанными — «Взять в работу» как одно: все привязанные у нового основного, цепочек нет, у перешедших — запись в журнале (§11)", async () => {
    const env = await makeEnv();
    const [a, b, c, d] = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire");
    assert.ok(d, "в демо-данных четыре новых пожара");
    await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [a.guid, b.guid], primaryGuid: a.guid });
    await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [c.guid, d.guid], primaryGuid: c.guid });
    await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [a.guid, c.guid], primaryGuid: a.guid });
    const cards = await Promise.all([b, c, d].map((e) => env.card(e.guid)));
    assert.ok(cards.every((x) => x.state === "linked" && x.linkedTo === a.guid), "B, C и D привязаны к A напрямую");
    const moved = cards[2].journal[cards[2].journal.length - 1];
    assert.eq([moved.templateKey, moved.vars.primaryNumber], ["workflow.journal.merge", a.number], "у D — запись о новом основном");
    const page = await env.ok("GET", `/operator/incidents/${enc(a.guid)}/linked`);
    assert.eq(page.items.map((x) => x.guid).sort(), [b.guid, c.guid, d.guid].sort(), "у A трое привязанных");
    assert.eq((await env.card(c.guid)).linkedCount, 0, "у C привязанных не осталось");
    // Закрытые вместе с прежним основным остаются при нём как история: E + F, закрыть, переоткрыть E, к A
    const fx = window.IM_FIXTURE;
    const base = fx.incidents.find((i) => i.number === "INC-1847");
    const [e, f] = [0, 1].map((k) => Object.assign(JSON.parse(JSON.stringify(base)), { guid: `10000000-0000-4000-8000-0000000098${k}0`, number: `INC-98${k}0` }));
    const env2 = await makeEnv({ fixturePatch: { incidents: fx.incidents.concat([e, f]) } });
    const lead = (await env2.all("open")).find((x) => x.number === "INC-1838");
    await env2.ok("POST", "/operator/incidents/merge", { incidentGuids: [e.guid, f.guid], primaryGuid: e.guid });
    assert.status(await env2.act(e.guid, "close", { resultId: "false_alarm", comment: "тест" }, "card"), 200, null, "закрыть E");
    assert.status(await env2.act(e.guid, "reopen", { comment: "ещё" }, "card"), 200, null, "переоткрыть E");
    await env2.ok("POST", "/operator/incidents/merge", { incidentGuids: [lead.guid, e.guid], primaryGuid: lead.guid });
    const closed = await env2.card(f.guid);
    assert.eq([closed.state, closed.linkedTo], ["closed", e.guid], "закрытый F остался при E как история");
  });

  test("Норматив закрытия привязанного идёт дальше: истёк — нарушение на владельца основного и алерт; у нового привязанного норматива нет; закрыли основной раньше — нарушения нет (§11.4)", async () => {
    const env = await makeEnv();
    const fires = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire");
    const urgent = fires[0];
    const calm = fires[fires.length - 1];
    const fresh = fires[1];
    assert.ok(urgent.priority > calm.priority, "есть пожары разной срочности");
    for (const e of [urgent, calm]) assert.status(await env.act(e.guid, "claim", {}, "queue"), 200, null, `взять ${e.number}`);
    await env.advance(30);
    const before = await env.card(urgent.guid);
    const res = await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [calm.guid, urgent.guid, fresh.guid], primaryGuid: calm.guid });
    const linked = await env.card(urgent.guid);
    assert.eq([linked.state, linked.timer.id, linked.timer.running, linked.timer.dueAt], ["linked", "resolution", true, before.timer.dueAt], "у привязанного срок закрытия идёт, тот же");
    assert.eq((await env.card(fresh.guid)).timer, null, "у нового привязанного норматива нет");
    assert.eq(res.incident.linkedDueAt, before.timer.dueAt, "у основного — срок привязанного");
    await env.advance(Math.ceil((Date.parse(before.timer.dueAt) - env.now) / 1000) + 5);
    const late = await env.card(urgent.guid);
    assert.eq([late.state, late.breaches.length, late.breaches[0].kind, late.breaches[0].owner && late.breaches[0].owner.id], ["linked", 1, "resolution", ME], "нарушение закрытия — на владельца основного");
    assert.eq(late.journal[late.journal.length - 1].templateKey, "workflow.journal.linked_resolution_overdue", "запись в журнале привязанного");
    const primary = await env.card(calm.guid);
    assert.eq([primary.breaches.length, primary.timer.dueAt], [0, res.incident.timer.dueAt], "у основного нарушений нет, срок свой");
    // Закрыли основной раньше срока привязанного — нарушения нет
    const env2 = await makeEnv();
    for (const e of [urgent, calm]) await env2.act(e.guid, "claim", {}, "queue");
    await env2.ok("POST", "/operator/incidents/merge", { incidentGuids: [calm.guid, urgent.guid], primaryGuid: calm.guid });
    assert.status(await env2.act(calm.guid, "close", { resultId: "false_alarm", comment: "тест" }, "card"), 200, null, "закрыть основной");
    await env2.advance(900);
    const closed = await env2.card(urgent.guid);
    assert.eq([closed.state, closed.breaches.length], ["closed", 0], "закрыт вместе с основным, нарушения нет");
  });

  test("Переоткрыли событие, закрытое вместе с основным, — оно само по себе: связи нет, у основного его нет, запись в журнале обоих (§11.4, BUG-42)", async () => {
    const env = await makeEnv();
    const [a, b, c] = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire");
    for (const e of [a, b]) assert.status(await env.act(e.guid, "claim", {}, "queue"), 200, null, `взять ${e.number}`);
    await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [a.guid, b.guid], primaryGuid: a.guid });
    assert.status(await env.act(a.guid, "close", { resultId: "false_alarm", comment: "тест" }, "card"), 200, null, "закрыть основной");
    assert.eq((await env.card(b.guid)).linkedTo, a.guid, "закрытый вместе с основным — при нём как история");
    assert.status(await env.act(b.guid, "reopen", { comment: "тест" }, "queue"), 200, null, "переоткрыть привязанный");
    const reopened = await env.card(b.guid);
    assert.eq([reopened.state, reopened.linkedTo], ["in_progress", null], "в работе, связи нет");
    assert.eq(reopened.journal[reopened.journal.length - 1].templateKey, "workflow.journal.reopen_unlinked", "запись в журнале события");
    const primary = await env.card(a.guid);
    const note = primary.journal.filter((j) => j.templateKey === "workflow.journal.linked_reopened").pop();
    assert.ok(note && note.vars.number === b.number, "запись в журнале основного");
    assert.eq((await env.ok("GET", `/operator/incidents/${enc(a.guid)}/linked`)).items.map((x) => x.guid), [], "у основного его нет");
    // Основной переоткрыли и объединили с другим — переоткрытый не трогается
    assert.status(await env.act(a.guid, "reopen", { comment: "тест" }, "queue"), 200, null, "переоткрыть основной");
    assert.status(await env.act(c.guid, "claim", {}, "queue"), 200, null, "взять третий");
    await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [c.guid, a.guid], primaryGuid: c.guid });
    const after = await env.card(b.guid);
    assert.eq([after.state, after.linkedTo], ["in_progress", null], "переоткрытый остался сам по себе");
    // Обычное переоткрытие — без записей о связи
    const plain = (await env.card(c.guid)).journal.some((j) => /reopen_unlinked|linked_reopened/.test(j.templateKey));
    assert.ok(!plain, "у непривязанного записей о связи нет");
  });

  test("У адресата основного нет доступа к привязанному — после эскалации или смены ролей привязанный отсоединяется и уходит в очередь (§11.4, §5, RULE-71)", async () => {
    const W = window.IM_WORKFLOW;
    const levels = W.escalation.levels.map((l, i) => (i === 0 ? Object.assign({}, l, { targetRef: "user:kuznetsov" }) : l));
    const env = await makeEnv({ workflowPatch: { escalation: Object.assign({}, W.escalation, { onResolutionOverdue: "escalate", levels }) } });
    const fires = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire");
    const mall = fires.find((e) => e.site === "Торговый центр");
    const office = fires.find((e) => e.site !== "Торговый центр");
    assert.ok(mall && office, "пожары в ТЦ и вне его");
    assert.status(await env.act(mall.guid, "claim", {}, "queue"), 200, null, "взять пожар ТЦ");
    await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [mall.guid, office.guid], primaryGuid: mall.guid });
    const due = (await env.card(mall.guid)).timer.dueAt;
    // Вручную Кузнецову (только ТЦ) нельзя: нет доступа к привязанному
    const manual = await env.act(mall.guid, "transfer", { targetId: "kuznetsov", comment: "тест" }, "card");
    assert.status(manual, 403, "GUARD_FAILED", "ручная передача без доступа к привязанному");
    // Норматив закрытия истёк — эскалация Кузнецову, он оффлайн — «Охране ТЦ»: доступа к офису нет ни у кого
    await env.advance(Math.ceil((Date.parse(due) - env.now) / 1000) + 10);
    const primary = await env.card(mall.guid);
    assert.eq([primary.state, primary.assignmentGroup && primary.assignmentGroup.id], ["pending_acceptance", "grp-tc"], "основной — «Охране ТЦ»");
    const freed = await env.card(office.guid);
    assert.eq([freed.state, freed.linkedTo, freed.owner], ["new", null, null], "привязанный — снова новый, ничей, без связи");
    assert.eq(freed.timer && freed.timer.id, "reaction", "реакция — заново");
    assert.ok(freed.journal.some((j) => j.templateKey === "workflow.journal.linked_lost_access"), "запись в журнале привязанного");
    const note = primary.journal.filter((j) => j.templateKey === "workflow.journal.linked_lost_access_primary").pop();
    assert.ok(note && note.vars.number === office.number, "запись в журнале основного");
    assert.eq(primary.linkedCount, 0, "у основного привязанных нет");

    // Смена ролей: у владельца основного больше нет доступа к объекту привязанного
    const env2 = await makeEnv();
    assert.status(await env2.act(mall.guid, "claim", {}, "queue"), 200, null, "взять пожар ТЦ");
    await env2.ok("POST", "/operator/incidents/merge", { incidentGuids: [mall.guid, office.guid], primaryGuid: mall.guid });
    const roles = await env2.call("PUT", "/test/operators/me/roles", { roles: ["Оператор", "Оператор ТЦ"] });
    assert.ok(!roles.body.fired.some((f) => f.transitionId === "linked_lost_access"), "доступ остался — привязанный на месте");
    const res = await env2.call("PUT", "/test/operators/me/roles", { roles: ["Оператор ТЦ"] });
    assert.ok(res.body.fired.some((f) => f.incidentGuid === office.guid && f.transitionId === "linked_lost_access"), "без доступа к офису — отсоединён");
    const kept = await env2.card(mall.guid);
    assert.eq([kept.state, kept.owner && kept.owner.id, kept.linkedCount], ["in_progress", ME, 0], "основной у меня, привязанных нет");
  });

  test("Ответы сценария привязанного — в незаполненные шаги основного; заполненное в основном не перезаписывается; запись в журнале (§11)", async () => {
    const env = await makeEnv();
    const [a, b] = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire");
    assert.status(await env.act(a.guid, "claim", {}, "queue"), 200, null, "взять A");
    assert.status(await env.answer(a.guid, { visual: true, note: "из A" }), 200, null, "ответы A");
    assert.status(await env.act(b.guid, "claim", {}, "queue"), 200, null, "взять B");
    assert.status(await env.answer(b.guid, { note: "из B" }), 200, null, "ответы B");
    const res = await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [a.guid, b.guid], primaryGuid: b.guid });
    const primary = await env.card(res.incident.guid);
    assert.eq([primary.scenario.answers.visual, primary.scenario.answers.note], [true, "из B"], "флажок из A перенесён, своё поле B осталось");
    const entry = primary.journal.filter((e) => e.templateKey === "workflow.journal.answers_moved").pop();
    assert.ok(entry && entry.vars.number === a.number && entry.vars.n === 1, `запись в журнале основного: ${entry && entry.text}`);
    assert.eq((await env.card(a.guid)).scenario.answers.note, "из A", "у привязанного ответы остались как история");
  });

  test("Поиск находит привязанный инцидент — строкой основного с «найдено в привязанных»; страница найденного среди привязанных (§11)", async () => {
    const fx = window.IM_FIXTURE;
    const base = fx.incidents.find((i) => i.number === "INC-1847");
    const extra = Array.from({ length: 12 }, (_, k) =>
      Object.assign(JSON.parse(JSON.stringify(base)), { guid: `10000000-0000-4000-8000-0000000099${String(k).padStart(2, "0")}`, number: `INC-99${String(k).padStart(2, "0")}` })
    );
    const env = await makeEnv({ fixturePatch: { incidents: fx.incidents.concat(extra) } });
    await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [base.guid].concat(extra.map((e) => e.guid)), primaryGuid: base.guid });
    const last = extra[extra.length - 1];
    const res = await env.ok("GET", `/operator/incidents?filter=open&search=${encodeURIComponent(last.number)}`);
    assert.eq(res.items.map((e) => e.guid), [base.guid], "найден основной, привязанного строкой нет");
    assert.eq(res.items[0].matchedLinked, [{ guid: last.guid, number: last.number }], "в строке — какой привязанный подошёл");
    const plain = await env.ok("GET", `/operator/incidents?filter=open&search=${encodeURIComponent(base.number)}`);
    assert.ok(plain.items.length === 1 && !plain.items[0].matchedLinked, "поиск по самому основному — без «найдено в привязанных»");
    const p1 = await env.ok("GET", `/operator/incidents/${enc(base.guid)}/linked?pageSize=5&focusGuid=${enc(last.guid)}`);
    assert.eq(p1.focusPage, 3, "найденное — на третьей странице по 5");
    const none = await env.ok("GET", `/operator/incidents/${enc(base.guid)}/linked?pageSize=5&focusGuid=${enc(base.guid)}`);
    assert.eq(none.focusPage, null, "не привязанный — без страницы");
  });

  test("Журнал основного: присоединено много — первые пять номеров и «и ещё N»; мало — все номера (§11)", async () => {
    const fx = window.IM_FIXTURE;
    const base = fx.incidents.find((i) => i.number === "INC-1847");
    const extra = Array.from({ length: 6 }, (_, k) =>
      Object.assign(JSON.parse(JSON.stringify(base)), { guid: `10000000-0000-4000-8000-0000000099${String(k).padStart(2, "0")}`, number: `INC-99${String(k).padStart(2, "0")}` })
    );
    const env = await makeEnv({ fixturePatch: { incidents: fx.incidents.concat(extra) } });
    const many = await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [base.guid].concat(extra.map((e) => e.guid)), primaryGuid: base.guid });
    const entry = (c) => c.journal.filter((e) => /merged_in/.test(e.templateKey)).pop();
    const big = entry(await env.card(many.incident.guid));
    assert.eq([big.templateKey, big.vars.ids.split(", ").length, big.vars.more], ["workflow.journal.merged_in_more", 5, 1], "пять номеров и ещё один");
    assert.ok(/и ещё 1$/.test(big.text), `текст: ${big.text}`);
    const env2 = await makeEnv();
    const fires = (await env2.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire").slice(0, 3);
    const few = await env2.ok("POST", "/operator/incidents/merge", { incidentGuids: fires.map((e) => e.guid) });
    const small = entry(await env2.card(few.incident.guid));
    assert.eq([small.templateKey, small.vars.ids.split(", ").length], ["workflow.journal.merged_in", 2], "оба номера");
  });

  test("«Отсоединить все»: все привязанные — снова новые, у основного привязанных нет; нельзя — не меняется ничего (§11)", async () => {
    const env = await makeEnv();
    const fires = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire").slice(0, 3);
    const res = await env.ok("POST", "/operator/incidents/merge", { incidentGuids: fires.map((e) => e.guid) });
    const lead = res.incident.guid;
    const others = fires.map((e) => e.guid).filter((g) => g !== lead);
    // Привязанные — постранично: по одному на странице, вместе — все
    const p1 = await env.ok("GET", `/operator/incidents/${enc(lead)}/linked?page=1&pageSize=1`);
    const p2 = await env.ok("GET", `/operator/incidents/${enc(lead)}/linked?page=2&pageSize=1`);
    assert.eq([p1.total, p1.items.length, p2.items.length, p2.page], [2, 1, 1, 2], "две страницы по одному");
    assert.eq([p1.items[0].guid, p2.items[0].guid].sort(), others.slice().sort(), "на страницах — все привязанные");
    assert.status(await env.call("GET", `/operator/incidents/${enc("00000000-0000-4000-8000-000000000000")}/linked`), 404, "NOT_FOUND", "нет такого основного");
    // На перерыве отсоединять нельзя: отказ — и ни одно не отсоединено
    await env.ok("PUT", "/operator/session/agent-state", { agentState: "not_ready", reasonId: "lunch" });
    assert.status(await env.call("DELETE", `/operator/incidents/${enc(lead)}/linked`), 403, null, "на перерыве");
    assert.eq((await Promise.all(others.map((g) => env.card(g)))).map((c) => c.state), others.map(() => "linked"), "ничего не отсоединено");
    await env.ok("PUT", "/operator/session/agent-state", { agentState: "ready" });
    const all = await env.call("DELETE", `/operator/incidents/${enc(lead)}/linked`);
    assert.status(all, 200, null, "отсоединить все");
    assert.eq(all.body.guid, lead, "ответ — основной");
    assert.eq((await env.ok("GET", `/operator/incidents/${enc(lead)}/linked`)).items.filter((x) => x.state === "linked").length, 0, "привязанных не осталось");
    const back = await Promise.all(others.map((g) => env.card(g)));
    assert.ok(back.every((c) => c.state === "new" && !c.linkedTo), "все — новые, без связи");
    const open = (await env.all("open")).map((e) => e.guid);
    assert.ok(others.every((g) => open.includes(g)), "все снова в очереди");
    assert.status(await env.call("DELETE", `/operator/incidents/${enc(lead)}/linked`), 200, null, "привязанных нет — без изменений");
    assert.status(await env.call("DELETE", `/operator/incidents/${enc("00000000-0000-4000-8000-000000000000")}/linked`), 404, "NOT_FOUND", "нет такого");
  });

  test("Основной «Ожидает принятия»: отсоединять — только после «Принять», и человеку, и группе (§11.4, RULE-78)", async () => {
    // Основной адресован мне автоэскалацией: первая ступень — я сам или моя группа
    for (const [who, targetRef, ownership] of [["лично", `user:${ME}`, "target"], ["группе", "group:grp-leads", "target"]]) {
      const env = await makeEnv({ workflowPatch: { escalation: { levels: [{ level: 1, targetRef, reactionSec: 600 }], maxLevel: 1 } } });
      const fires = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire").slice(0, 2);
      const res = await env.ok("POST", "/operator/incidents/merge", { incidentGuids: fires.map((e) => e.guid) });
      const lead = res.incident.guid;
      const other = fires.map((e) => e.guid).find((g) => g !== lead);
      assert.status(await env.act(lead, "release", { comment: "тест" }, "card"), 200, null, `${who}: основной — в очередь`);
      await env.advance(W.timers.find((t) => t.id === "reaction").defaultSec + 60);
      const pending = await env.card(lead);
      assert.eq([pending.state, pending.ownership], ["pending_acceptance", ownership], `${who}: основной ждёт моего принятия`);
      assert.eq((await env.card(other)).state, "linked", `${who}: привязанный на месте`);
      const before = await env.call("DELETE", `/operator/incidents/${enc(lead)}/linked/${enc(other)}`);
      assert.ok(before.status >= 400, `${who}: до «Принять» отсоединить нельзя — ${before.status}`);
      assert.eq((await env.card(other)).state, "linked", `${who}: не отсоединён`);
      assert.status(await env.act(lead, "accept", {}, "card"), 200, null, `${who}: «Принять»`);
      assert.status(await env.call("DELETE", `/operator/incidents/${enc(lead)}/linked/${enc(other)}`), 200, null, `${who}: после «Принять» — можно`);
      assert.eq((await env.card(other)).state, "new", `${who}: отсоединённый — снова новый`);
    }
  });

  test("Выборка: «Взять» выборкой недоступно — как одно только «Взять в работу»; режима «однотипные» нет (§11)", async () => {
    const env = await makeEnv();
    const all = await env.all();
    const fires = all.filter((e) => e.state === "new" && e.eventType.id === "fire").slice(0, 2);
    const sel = await env.ok("POST", "/operator/incidents/selection", { mode: "explicit", incidentGuids: fires.map((e) => e.guid) });
    const claim = sel.actions.find((a) => a.id === "claim");
    assert.ok(!claim.enabled && !claim.bulkAllowed, "«Взять» на двух однотипных новых");
    assert.status(await env.call("POST", "/operator/incidents/transitions/claim/bulk", { incidentGuids: fires.map((e) => e.guid), formValues: {}, surface: "queue" }), 422, "BULK_SELECTION_INVALID", "«Взять» выборкой — отказ сервера");
    assert.ok(fires.length === 2 && (await env.all("open")).filter((e) => fires.some((f) => f.guid === e.guid)).every((e) => e.state === "new"), "никто не взят");
    const capped = await makeEnv({ workflowPatch: { limits: { maxBulk: 10 } } });
    const allIn = await capped.ok("POST", "/operator/incidents/selection", { mode: "all_in_filter", filter: "open" });
    assert.ok(allIn.incidentGuids.length <= 10, "не больше лимита выборки");
    assert.eq(allIn.truncated, (await capped.all("open")).length > 10, "признак усечения");
  });

  test("Массовое действие: передача выборки — каждому, кому доступно; результат по каждому", async () => {
    const env = await makeEnv();
    const news = (await env.all("open")).filter((e) => e.state === "new").slice(0, 3);
    const res = await env.call("POST", "/operator/incidents/transitions/transfer/bulk", {
      incidentGuids: news.map((e) => e.guid),
      formValues: { targetId: "sidorov", comment: "выборкой" },
      surface: "queue",
    });
    assert.status(res, 200);
    assert.eq(res.body.succeeded.length, 3, "передано");
    assert.ok(res.body.succeeded.every((e) => e.state === "pending_acceptance" && e.owner.id === "sidorov"), "все у адресата");
  });

  /* ===== Сценарий (§10.4, §14.5) ===== */

  test("Сценарий: курсор не перепрыгивает незаполненный обязательный шаг; ответы двигают прогресс; макрос в журнале", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    const card = await env.card(inc.guid);
    const steps = card.scenario.steps;
    const locked = steps.findIndex((s, i) => i > 0 && steps.slice(0, i).some((p) => p.requiredFor.includes("closing")));
    const jump = await env.call("PUT", `/operator/incidents/${enc(inc.guid)}/scenario/cursor`, { stepId: steps[locked].id });
    assert.status(jump, 409, "REQUIRED_STEPS_NOT_FILLED", "переход через незаполненный шаг");
    const saved = await env.answer(inc.guid, { [steps[0].id]: true });
    assert.status(saved, 200, null, "ответ на шаг");
    const after = saved.body;
    assert.eq(after.progress.filled, card.scenario.progress.filled + 1, "прогресс");
    const macroStep = steps.find((s) => s.type === "Macros");
    const name = macroStep.view.buttons[0];
    const run = await env.call("POST", `/operator/incidents/${enc(inc.guid)}/macros/${enc(name)}`, { stepId: macroStep.id });
    assert.status(run, 202);
    const c = await env.card(inc.guid);
    assert.ok(c.scenario.launchedMacros.includes(name), "макрос отмечен запущенным");
    assert.ok(c.journal.some((j) => j.templateKey === "workflow.journal.macro.launched" && j.vars.name === name), "макрос в журнале");
  });

  /* ===== Очередь: фильтры, счётчики, страницы (§7, §19) ===== */

  test("Счётчики фильтров совпадают с очередью; страницы и focusPage", async () => {
    const env = await makeEnv();
    const counters = await env.ok("GET", "/operator/incidents/counters");
    for (const f of W.queueFilters) {
      const page = await env.ok("GET", `/operator/incidents?filter=${f.id}&pageSize=1000`);
      assert.eq(page.total, counters[f.id], `фильтр «${f.id}»`);
    }
    const inbox = (await env.all("inbox")).map((e) => e.number).sort();
    assert.eq(inbox, ["INC-1836", "INC-1843"], "мне на принятие");
    // Переданный коллеге — не «мне на принятие», а чужой (отношение к смотрящему, §7)
    const inc = await newFire(env);
    await env.act(inc.guid, "transfer", { targetId: "sidorov", comment: "x" }, "queue");
    assert.ok(!(await env.all("inbox")).some((e) => e.guid === inc.guid), "переданный коллеге не во «Мне на принятие»");
    assert.ok((await env.all("foreign")).some((e) => e.guid === inc.guid), "он в «Чужих»");
    const open = await env.all("open");
    const last = open[open.length - 1];
    const page1 = await env.ok("GET", `/operator/incidents?filter=open&page=1&pageSize=5&focusGuid=${enc(last.guid)}`);
    assert.eq(page1.page, 1, "страница не перелистывается сама");
    assert.eq(page1.focusPage, Math.ceil(open.length / 5), "страница выбранного");
    const hidden = await env.ok("GET", `/operator/incidents?filter=done&focusGuid=${enc(last.guid)}`);
    assert.eq(hidden.focusPage, null, "невидимый при фильтре — null");
  });

  test("Фильтры группы, типа события, типа устройства и поиск сужают очередь", async () => {
    const env = await makeEnv();
    const tree = await env.ok("GET", "/operator/reference/source-groups?withCounters=true");
    const all = await env.all();
    const byGroup = await env.ok("GET", `/operator/incidents?filter=all&sourceGroupGuid=${enc(tree[0].guid)}&pageSize=1000`);
    assert.ok(byGroup.total > 0 && byGroup.total < all.length, `группа «${tree[0].name}»: ${byGroup.total} из ${all.length}`);
    // Фильтр по типу события — по guid из справочника; машинный id (fire) — для нормативов и сценария
    const fireType = (await env.ok("GET", "/operator/reference/event-types")).find((t) => t.id === "fire");
    const fire = await env.ok("GET", `/operator/incidents?filter=all&eventTypeGuid=${enc(fireType.guid)}&pageSize=1000`);
    assert.eq(fire.total, all.filter((e) => e.eventType.id === "fire").length, "тип события: все пожарные и только они");
    const dev = await env.ok("GET", "/operator/incidents?filter=all&deviceTypeId=fire-detector&pageSize=1000");
    assert.ok(dev.items.every((e) => e.sourceDeviceTypeId === "fire-detector"), "тип устройства-источника");
    const search = await env.ok("GET", "/operator/incidents?filter=all&search=INC-1847");
    assert.eq(search.items.map((e) => e.number), ["INC-1847"], "поиск по номеру");
    const open = tree[0].counters.open;
    assert.eq(open, (await env.ok("GET", `/operator/incidents?filter=open&sourceGroupGuid=${enc(tree[0].guid)}&pageSize=1000`)).total, "счётчик группы в дереве");
  });

  /* ===== Справочники, схема, сессия, карточка по частям ===== */

  test("Схема workflow и справочники — те, что в машине; приоритеты — из справочника набора (§2.5)", async () => {
    const env = await makeEnv();
    const wf = await env.ok("GET", "/operator/workflow/active");
    assert.eq(wf.transitions.map((t) => t.id), W.transitions.map((t) => t.id), "переходы схемы");
    const hold = await env.ok("GET", "/operator/reference/reasons/hold");
    assert.eq(hold.map((r) => r.id), W.reasonCatalogs.hold.items.map((r) => r.id), "причины удержания");
    assert.status(await env.call("GET", "/operator/reference/reasons/nothing"), 404, "NOT_FOUND", "неизвестный справочник");
    const types = await env.ok("GET", "/operator/reference/event-types");
    assert.ok(types.some((x) => x.id === "fire") && types.every((x) => x.defaultReactionSec > 0), "типы событий с нормативом реакции");
    const devices = await env.ok("GET", "/operator/reference/device-types");
    assert.ok(devices.some((x) => x.id === "camera") && devices.every((x) => x.label), "типы устройств");
    const priorities = await env.ok("GET", "/operator/reference/priorities");
    assert.eq(priorities.map((x) => x.value), LEVELS, "приоритеты — по убыванию числа");
    assert.ok(priorities.every((x) => x.name.ru && x.color), "у каждого — название и цвет");
  });

  test("Форма «Передать» подставляет адресата прошлой передачи этого оператора; настройки нет; автоэскалация не запоминается (§8.2)", async () => {
    const env = await makeEnv();
    const preset = window.IM_FIXTURE.operatorPreferences;
    const initial = await env.session();
    Object.entries(preset).forEach(([key, value]) => assert.eq(initial.preferences[key], value, `после сброса ${key} — из эталонного набора`));
    assert.eq(initial.lastTransferTargetId, null, "после сброса — никого");
    const [a, b] = (await env.all("open")).filter((e) => e.state === "new" && e.site !== "Торговый центр");
    assert.eq(actionOf(a, "transfer").fieldOptions.targetId.defaultValue || null, null, "передач ещё не было — поле пустое");
    assert.status(await env.act(a.guid, "transfer", { targetId: "noc", comment: "тест" }, "queue"), 200, null, "передать Дежурному ЦОД");
    assert.eq((await env.session()).lastTransferTargetId, "noc", "сервер запомнил");
    const again = (await env.all("open")).find((e) => e.guid === b.guid);
    assert.eq(actionOf(again, "transfer").fieldOptions.targetId.defaultValue, "noc", "в следующей форме — он же");
    // Адресату, которому этот инцидент передать нельзя (нет доступа), не подставляется
    const mall = (await env.all("open")).find((e) => e.state === "new" && e.site === "Торговый центр");
    assert.status(await env.act(mall.guid, "transfer", { targetId: "kuznetsov", comment: "тест" }, "queue"), 200, null, "передать Кузнецову событие ТЦ");
    assert.eq((await env.session()).lastTransferTargetId, "kuznetsov", "последний — Кузнецов");
    const office = (await env.all("open")).find((e) => e.guid === b.guid);
    assert.eq(actionOf(office, "transfer").fieldOptions.targetId.defaultValue || null, null, "Кузнецову вне ТЦ нельзя — не подставлен");
    assert.status(await env.heartbeat(a.guid), 204, null, "признак активности");
  });

  test("Действия карточки и очереди различаются по поверхности; сценарий, журнал и камеры — те же, что в карточке", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    const card = await env.card(inc.guid);
    const inCard = (await env.ok("GET", `/operator/incidents/${enc(inc.guid)}/actions?surface=card`)).map((a) => a.id);
    const inQueue = (await env.ok("GET", `/operator/incidents/${enc(inc.guid)}/actions?surface=queue`)).map((a) => a.id);
    assert.ok(inCard.includes("hold") && !inQueue.includes("hold"), `«Отложить» только в карточке: ${inCard} / ${inQueue}`);
    assert.eq(await env.ok("GET", `/operator/incidents/${enc(inc.guid)}/scenario`), card.scenario, "сценарий");
    const journal = await env.ok("GET", `/operator/incidents/${enc(inc.guid)}/journal`);
    assert.eq(journal.items.length, card.journal.length, "журнал");
    assert.eq(journal.total, journal.items.length, "всего записей");
    assert.eq(await env.ok("GET", `/operator/incidents/${enc(inc.guid)}/media`), card.media, "камеры и карта");
  });

  test("Камеры и план (GET …/media): картинки камер, план, значки с положением — из эталонного набора", async () => {
    const env = await makeEnv();
    const fx = window.IM_FIXTURE;
    const dev = Object.fromEntries(fx.devices.map((d) => [d.guid || d.id, d]));
    let markers = 0;
    // Камеры инцидента — из всех связей его источника без повторов (§19.1, RULE-70), первая — главная
    const camerasOf = (inc) => [...new Set(fx.cameraLinks.filter((l) => l.devices.includes(inc.devices[0])).flatMap((l) => l.cameras))];
    for (const inc of fx.incidents) {
      const media = await env.ok("GET", `/operator/incidents/${enc(inc.guid)}/media`);
      const ids = [...new Set([...inc.devices, ...camerasOf(inc)])];
      const source = inc.devices[0];
      assert.eq(
        media.cameras.map((c) => [c.guid, c.thumbnailUrl, c.isSource]),
        camerasOf(inc).map((id) => [id, dev[id].thumbnailUrl || null, id === source]),
        `${inc.number}: камеры из связей источника`
      );
      // План — там, где источник или первое устройство с положением, иначе план площадки
      const placed = [source, ...ids].map((id) => dev[id] && dev[id].position).find(Boolean);
      const plan = fx.plans.find((p) => (placed ? p.id === placed.plan : p.site === inc.site)) || null;
      if (!plan) {
        assert.eq(media.map, null, `${inc.number}: плана нет`);
        continue;
      }
      assert.eq([media.map.planGuid, media.map.planName, media.map.imageUrl], [plan.guid || plan.id, plan.name, plan.imageUrl], `${inc.number}: план`);
      const expected = ids
        .filter((id) => dev[id].position && dev[id].position.plan === plan.id)
        .map((id) => [id, dev[id].position.x, dev[id].position.y, id === source]);
      const got = media.map.markers.map((m) => [m.deviceGuid, m.x, m.y, m.isSource]);
      assert.eq(got.slice().sort(), expected.slice().sort(), `${inc.number}: значки на плане`);
      markers += got.length;
    }
    return `инцидентов ${fx.incidents.length}, значков ${markers}`;
  });

  test("Группы доступа (§5): с ролью «Оператор ТЦ» видно только «Торговый центр» — в очереди, счётчиках, выборке, дереве, потоке; чужое — 404", async () => {
    const fx = window.IM_FIXTURE;
    const role = "Оператор ТЦ";
    // Доступные роли устройства — по группам доступа набора, с вложенными группами
    const byId = {};
    const index = (groups) => groups.forEach((g) => ((byId[g.id] = g), index(g.groups || [])));
    index(fx.sourceGroups);
    const devicesOf = (g) => (g.devices || []).concat(...(g.groups || []).map(devicesOf));
    const allowed = new Set(
      fx.accessGroups.filter((a) => a.roles.includes(role)).flatMap((a) => a.sourceGroups.flatMap((id) => devicesOf(byId[id])).concat(a.devices))
    );
    const sourceOf = (i) => i.devices[0];
    const seen = fx.incidents.filter((i) => allowed.has(sourceOf(i)));
    const hidden = fx.incidents.filter((i) => !allowed.has(sourceOf(i)));
    assert.ok(seen.length && hidden.length, "в наборе есть и доступные роли инциденты, и недоступные");

    const env = await makeEnv({ roles: [role] });
    const got = [];
    const stop = env.api.subscribe((m) => got.push(m));
    assert.eq((await env.all("all")).map((e) => e.guid).sort(), seen.map((i) => i.guid).sort(), "в очереди — только доступные");
    assert.eq((await env.ok("GET", "/operator/incidents/counters")).all, seen.length, "счётчик «Все»");
    const other = hidden[0];
    assert.status(await env.call("GET", `/operator/incidents/${enc(other.guid)}`), 404, "NOT_FOUND", "карточка недоступного");
    assert.status(await env.call("GET", `/operator/incidents/${enc(other.guid)}/actions`), 404, "NOT_FOUND", "действия недоступного");
    assert.status(await env.act(other.guid, "claim", {}, "queue"), 404, "NOT_FOUND", "переход над недоступным");
    const all = await env.ok("POST", "/operator/incidents/selection", { mode: "all_in_filter", filter: "all" });
    assert.ok(all.incidentGuids.every((g) => seen.some((i) => i.guid === g)), "«Выбрать все» — только доступные");
    const bulk = await env.call("POST", "/operator/incidents/transitions/transfer/bulk", {
      incidentGuids: [seen.find((i) => i.state === "new").guid, other.guid],
      formValues: { targetId: "petrova", comment: "тест" },
      surface: "queue",
    });
    assert.ok(bulk.body.failed.some((f) => f.incidentGuid === other.guid && f.problem.code === "NOT_FOUND"), "массовое действие: недоступный — NOT_FOUND");
    const tree = await env.ok("GET", "/operator/reference/source-groups");
    const treeDevices = [];
    const walk = (nodes) => nodes.forEach((n) => (treeDevices.push(...n.devices.map((d) => d.guid)), walk(n.children)));
    walk(tree);
    assert.ok(tree.length > 0 && treeDevices.every((d) => allowed.has(d)), `дерево групп — только доступные устройства: ${tree.map((n) => n.name)}`);
    // Время идёт: недоступные новые эскалируются, но в поток о них ничего не приходит
    await env.advance(W.timers.find((x) => x.id === "reaction").overrides.find((o) => o.priority === TOP).sec + GRACE + 1);
    await new Promise((r) => setTimeout(r, 300));
    stop();
    assert.ok(got.length > 0, "события о доступных пришли");
    // Кроме потери доступа к моим: в наборе есть инциденты вне ТЦ, адресованные мне (BUG-24)
    assert.ok(got.every((m) => !m.incidentGuid || seen.some((i) => i.guid === m.incidentGuid) || (m.type === "incident.access_lost" && !m.incident)), "о недоступных событий нет");
  });

  test("Дежурная группа с доступом ко всем объектам — в адресатах передачи у любого инцидента; своей группы там нет (§8.1)", async () => {
    const env = await makeEnv();
    const office = (await env.all("open")).find((e) => e.state === "new" && e.site !== "Торговый центр");
    const options = actionOf(office, "transfer").fieldOptions.targetId.options;
    const group = options.find((o) => o.id === "grp-response");
    assert.ok(group && !group.disabled, `«Группа реагирования» в форме передачи ${office.number}: ${options.map((o) => o.id)}`);
    const listed = (await env.ok("GET", `/operator/transfer-targets?incidentGuid=${enc(office.guid)}`)).find((t) => t.id === "grp-response");
    assert.ok(listed && listed.kind === "duty_group" && listed.available, "в адресатах — дежурная группа, на месте есть кто принять");
    assert.ok(!options.some((o) => o.id === "grp-leads"), "своей группы «Старшие операторы» нет");
    assert.status(await env.act(office.guid, "transfer", { targetId: "grp-response", comment: "группе" }, "queue"), 200, null, "передать группе");
    const card = await env.card(office.guid);
    assert.eq([card.state, card.owner, card.assignmentGroup && card.assignmentGroup.id], ["pending_acceptance", null, "grp-response"], "ждёт принятия группой, владельца нет");
  });

  test("Передача только адресату с доступом (§8.1): Кузнецов и «Охрана ТЦ» видят только «Торговый центр»", async () => {
    const env = await makeEnv();
    const news = (await env.all("open")).filter((e) => e.state === "new");
    const mall = news.filter((e) => e.site === "Торговый центр");
    const elsewhere = news.filter((e) => e.site !== "Торговый центр");
    assert.ok(mall.length >= 1 && elsewhere.length >= 1, "есть новые и в ТЦ, и вне его");
    const targetsOf = async (inc) => (await env.ok("GET", `/operator/transfer-targets?incidentGuid=${enc(inc.guid)}`)).map((t) => t.id);
    const outside = await targetsOf(elsewhere[0]);
    assert.ok(!outside.includes("kuznetsov") && !outside.includes("grp-tc"), `вне ТЦ нет Кузнецова и «Охраны ТЦ»: ${outside}`);
    const inside = await targetsOf(mall[0]);
    assert.ok(inside.includes("kuznetsov") && inside.includes("grp-tc"), `в ТЦ они есть: ${inside}`);
    const options = actionOf(elsewhere[0], "transfer").fieldOptions.targetId.options.map((o) => o.id);
    assert.ok(!options.includes("kuznetsov") && !options.includes("grp-tc"), "и в форме передачи их нет");
    for (const target of ["kuznetsov", "grp-tc"]) {
      const res = await env.act(elsewhere[0].guid, "transfer", { targetId: target, comment: "тест" }, "queue");
      assert.status(res, 403, "TARGET_NO_ACCESS", `передача вне ТЦ: ${target}`);
      assert.eq(res.body.guard, "targetHasAccess", "какое условие не выполнено");
    }
    // Массовая передача: где у адресата нет доступа — в failed, остальное передаётся
    const bulk = await env.ok("POST", "/operator/incidents/transitions/transfer/bulk", {
      incidentGuids: [elsewhere[1] ? elsewhere[1].guid : elsewhere[0].guid, mall[0].guid],
      formValues: { targetId: "kuznetsov", comment: "тест" },
      surface: "queue",
    });
    assert.ok(bulk.succeeded.some((i) => i.guid === mall[0].guid), "инцидент ТЦ передан");
    assert.ok(bulk.failed.length === 1 && bulk.failed[0].problem.code === "TARGET_NO_ACCESS", `вне ТЦ — отказ: ${JSON.stringify(bulk.failed.map((f) => f.problem.code))}`);
  });

  test("Передача группе: достаточно доступа хотя бы у одного участника (§8.1)", async () => {
    // Своя копия набора: в «Охране ТЦ» ещё Гусев, у которого доступ ко всему
    const fixture = JSON.parse(JSON.stringify(window.IM_FIXTURE));
    fixture.people.dutyGroups.find((g) => g.id === "grp-tc").members.push("gusev");
    const api = (await standWith({ fixture })).api;
    const inc = (await api.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.state === "new" && e.site !== "Торговый центр");
    const targets = (await api.get("/operator/transfer-targets", { incidentGuid: inc.guid })).map((t) => t.id);
    assert.ok(targets.includes("grp-tc") && !targets.includes("kuznetsov"), `группа есть, Кузнецова нет: ${targets}`);
    const etag = (await api.raw("GET", `/operator/incidents/${enc(inc.guid)}`)).headers.etag;
    const res = await api.raw("POST", `/operator/incidents/${enc(inc.guid)}/transitions/transfer`, { formValues: { targetId: "grp-tc", comment: "тест" }, surface: "queue" }, { "If-Match": etag });
    assert.status(res, 200, null, "передача группе со смешанным доступом");
  });

  test("Потеря доступа (§5): у владельца или адресата нет доступа к объекту — инцидент в очереди; группе хватает одного участника", async () => {
    const env = await makeEnv();
    const open = await env.all("open");
    const hers = open.filter((e) => e.owner && e.owner.id === "petrova");
    assert.ok(hers.some((e) => e.site !== "Торговый центр"), "у Петровой есть инциденты вне ТЦ");
    // Инцидент ТЦ — Петровой: после смены роли он должен остаться у неё
    const mall = open.find((e) => e.state === "new" && e.site === "Торговый центр");
    assert.status(await env.act(mall.guid, "transfer", { targetId: "petrova", comment: "тест" }, "queue"), 200, null, "передать Петровой инцидент ТЦ");
    const res = await env.call("PUT", "/test/operators/petrova/roles", { roles: ["Оператор ТЦ"] });
    assert.status(res, 200, null, "сменить роли Петровой");
    for (const inc of hers.filter((e) => e.site !== "Торговый центр")) {
      assert.ok(res.body.fired.some((f) => f.incidentGuid === inc.guid && f.transitionId === "addressee_lost_access"), `${inc.number}: сработала потеря доступа`);
      const c = await env.card(inc.guid);
      assert.eq([c.state, c.owner, c.holdReasonId], ["new", null, null], `${inc.number}: снова новый, ничей`);
      assert.ok(c.journal.some((j) => /нет доступа к объекту/.test(jt(j))), `${inc.number}: запись в журнале`);
    }
    const kept = await env.card(mall.guid);
    assert.eq([kept.state, kept.owner && kept.owner.id], ["pending_acceptance", "petrova"], "инцидент ТЦ остался у Петровой");
    // Группе старших операторов хватает доступа у меня; без него — в очередь
    const forGroup = (await env.all("all")).find((e) => e.assignmentGroup && e.assignmentGroup.id === "grp-leads" && e.site !== "Торговый центр");
    assert.ok(!res.body.fired.some((f) => f.incidentGuid === forGroup.guid), "группе хватает доступа у одного участника");
    // Мой инцидент вне ТЦ: после смены моей роли он мне не виден — приходит только номер (BUG-24)
    const taken = (await env.all("open")).find((e) => e.state === "new" && e.site !== "Торговый центр");
    assert.status(await env.act(taken.guid, "claim", {}, "queue"), 200, null, "взять инцидент вне ТЦ");
    const notMine = (await env.all("open")).filter((e) => e.site !== "Торговый центр" && !(e.owner && e.owner.id === "me") && !(e.assignmentGroup && e.assignmentGroup.id === "grp-leads"));
    const got = [];
    const stop = env.api.subscribe((m) => got.push(m));
    // По сети поток подключается не сразу
    await new Promise((r) => setTimeout(r, 300));
    const mine = await env.call("PUT", "/test/operators/me/roles", { roles: ["Оператор ТЦ"] });
    assert.ok(mine.body.fired.some((f) => f.incidentGuid === forGroup.guid && f.transitionId === "addressee_lost_access"), "в группе доступа нет ни у кого — в очередь");
    for (let i = 0; i < 30 && got.filter((m) => m.type === "incident.access_lost").length < 2; i++) await new Promise((r) => setTimeout(r, 100));
    await new Promise((r) => setTimeout(r, 300));
    stop();
    for (const inc of [taken, forGroup]) {
      const about = got.filter((m) => m.incidentGuid === inc.guid);
      assert.eq(about.map((m) => m.type), ["incident.access_lost"], `${inc.number}: о нём — одно событие`);
      assert.eq([about[0].incident, about[0].payload], [null, { number: inc.number }], `${inc.number}: только номер`);
    }
    assert.ok(notMine.length && !got.some((m) => notMine.some((e) => e.guid === m.incidentGuid)), "о чужих и ничьих, ставших недоступными, — ничего");
  });

  test("Дежурная группа — по ролям и отдельным людям (§8.1); человек в нескольких группах — при выходе первая по порядку", async () => {
    const env = await makeEnv();
    assert.eq((await env.session()).operator.dutyGroupGuids, ["grp-leads"], "я в группе старших операторов — как отдельный участник");
    const elsewhere = (await env.all("open")).find((e) => e.state === "new" && e.site !== "Торговый центр");
    const target = async (id) => (await env.ok("GET", `/operator/transfer-targets?incidentGuid=${enc(elsewhere.guid)}`)).find((t) => t.id === id);
    assert.ok(!(await target("grp-tc")), "вне ТЦ «Охраны ТЦ» нет: у её участников нет доступа");
    // Группа на месте, если на месте хотя бы один участник: в «Охране ТЦ» пока только Кузнецов, он «Вышел»
    const mall = (await env.all("open")).find((e) => e.state === "new" && e.site === "Торговый центр");
    const tcBefore = (await env.ok("GET", `/operator/transfer-targets?incidentGuid=${enc(mall.guid)}`)).find((t) => t.id === "grp-tc");
    assert.eq([tcBefore.name, tcBefore.available], ["Охрана ТЦ", false], "у группы название; на месте никого");
    // Гусеву — роль «Оператор ТЦ»: он входит в «Охрану ТЦ» по роли, и у группы появляется доступ
    assert.status(await env.call("PUT", "/test/operators/gusev/roles", { roles: ["Оператор", "Оператор ТЦ"] }), 200, null, "роли Гусева");
    const tc = await target("grp-tc");
    assert.ok(tc && tc.memberIds.includes("gusev") && tc.memberIds.includes("kuznetsov"), `состав по роли: ${tc && tc.memberIds}`);
    assert.eq(tc.available, true, "Гусев на месте — и группа на месте");
    // Мне — тоже «Оператор ТЦ»: я в двух группах, первая по порядку — группа старших операторов
    assert.status(await env.call("PUT", "/test/operators/me/roles", { roles: ["Оператор", "Оператор ТЦ"] }), 200, null, "мои роли");
    assert.eq((await env.session()).operator.dutyGroupGuids, ["grp-leads", "grp-tc"], "я в двух группах, по порядку");
    const personal = await env.guidOf("INC-1843");
    assert.status(await env.call("PUT", "/operator/session/agent-state", { agentState: "offline" }), 200, null, "выйти");
    const after = await env.card(personal);
    assert.eq(after.assignmentGroup && after.assignmentGroup.id, "grp-leads", "INC-1843 ушёл в первую по порядку группу");
  });

  test("Адресат не на месте — почему: «перерыв: Обед», вне МИ — «оффлайн», у группы — «никого нет на месте» (§8.1)", async () => {
    const env = await makeEnv();
    const open = await env.all("open");
    const labels = async (inc) =>
      Object.fromEntries((await env.ok("GET", `/operator/transfer-targets?incidentGuid=${enc(inc.guid)}`)).map((t) => [t.id, [t.available, t.availabilityLabel]]));
    const office = await labels(open.find((e) => e.state === "new" && e.site !== "Торговый центр"));
    assert.eq(office.orlova, [false, "перерыв: Обед"], "Орлова на обеде");
    assert.eq(office.sidorov, [true, null], "Сидоров на месте — без подписи");
    const mall = await labels(open.find((e) => e.state === "new" && e.site === "Торговый центр"));
    assert.eq(mall.kuznetsov, [false, "оффлайн"], "Кузнецов вне МИ");
    assert.eq(mall["grp-tc"], [false, "никого нет на месте"], "в «Охране ТЦ» никого");
  });

  test("Порядок дежурных групп задаёт администратор: при обратном порядке — в «Охрану ТЦ» (§8.1)", async () => {
    const fixture = JSON.parse(JSON.stringify(window.IM_FIXTURE));
    fixture.people.dutyGroups.reverse();
    fixture.people.operators.find((o) => o.id === ME).roles.push("Оператор ТЦ");
    const api = (await standWith({ fixture })).api;
    const guid = fixture.incidents.find((i) => i.number === "INC-1843").guid;
    await api.raw("PUT", "/operator/session/agent-state", { agentState: "offline" });
    const card = await api.get(`/operator/incidents/${enc(guid)}`);
    assert.eq(card.assignmentGroup && card.assignmentGroup.id, "grp-tc", "первая по порядку — теперь «Охрана ТЦ»");
  });

  /* ===== Эмуляция коллег во встроенном сервере (§17) ===== */

  test("Коллеги действуют через переходы машины: взять, передать мне, потеря связи и возврат в очередь (§12.3)", async () => {
    if (IMTest.external) return "пропущено: эмуляция коллег есть только во встроенном сервере";
    // Лимит активных 1: проверяем, что у каждого коллеги он свой
    const server = IMServer.create({
      workflow: Object.assign({}, W, { limits: Object.assign({}, W.limits, { maxActive: 1 }) }),
      fixture: window.IM_FIXTURE,
      colleagues: window.IM_COLLEAGUES,
      autoTick: false,
      testSupport: true,
    });
    const api = IMApi.create({ server });
    await api.raw("POST", "/test/reset", { fixture: "demo" });
    const sim = window.IM_COLLEAGUES.SIM;
    const before = new Map((await api.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.map((e) => [e.guid, e]));
    for (let i = 0; i <= sim.dropSec; i++) server.simulateSecond();
    const cards = await Promise.all([...before.keys()].map((id) => api.get(`/operator/incidents/${enc(id)}`)));
    const colleagues = new Set(sim.colleagues);
    const entry = (c, template) => c.journal.find((j) => j.templateKey === template);

    // Взятые коллегами: были новыми, теперь в работе у коллеги, в журнале — переход «Взять» от его имени
    const taken = cards.filter((c) => before.get(c.guid).state === "new" && entry(c, "workflow.journal.claim"));
    assert.ok(taken.length > 0, "коллеги ничего не взяли");
    taken.forEach((c) => assert.ok(colleagues.has(entry(c, "workflow.journal.claim").actor.id), `${c.guid}: взял не коллега`));
    // Лимит активных — у каждого коллеги свой (§10.2)
    const active = {};
    cards.filter((c) => c.state === "in_progress" && c.owner && colleagues.has(c.owner.id)).forEach((c) => {
      active[c.owner.id] = (active[c.owner.id] || 0) + 1;
    });
    Object.entries(active).forEach(([who, n]) => assert.ok(n <= 1, `у ${who} в работе ${n} > 1`));

    // Передача мне: переход «Передать» от имени коллеги — ожидает моего принятия
    const handed = cards.filter((c) => c.state === "pending_acceptance" && c.ownership === "target" && before.get(c.guid).state === "in_progress");
    assert.eq(handed.length, 1, "передано мне коллегой");
    const transfer = handed[0].journal[handed[0].journal.length - 1];
    assert.ok(transfer.templateKey === "workflow.journal.transfer" && colleagues.has(transfer.actor.id), `запись о передаче: ${transfer.templateKey}`);

    // Потеря связи: системный переход машины откладывает инциденты именно этого коллеги
    const dropped = cards.filter((c) => c.state === "on_hold" && c.holdReasonId === "no_link");
    assert.ok(dropped.length > 0, "никто не отложен из-за потери связи");
    const lost = new Set(dropped.map((c) => before.get(c.guid).owner && before.get(c.guid).owner.id).filter(Boolean));
    assert.eq(lost.size, 1, "связь потерял один коллега");
    cards
      .filter((c) => c.state === "in_progress" && c.owner && !lost.has(c.owner.id))
      .forEach((c) => assert.ok(c.holdReasonId !== "no_link", "у остальных инциденты в работе"));

    // Через idle_release молчания — снова в очереди, ничьи (system_release_idle)
    await api.raw("POST", "/test/clock", { advanceSec: W.session.idleReleaseSec });
    server.simulateSecond();
    for (const c of dropped) {
      const now = await api.get(`/operator/incidents/${enc(c.guid)}`);
      assert.eq([now.state, now.owner], ["new", null], `${c.guid} после долгого молчания`);
    }
    return `взято ${taken.length}, передано мне 1, отложено без связи ${dropped.length}`;
  });

  /* ===== Ошибки и поток событий ===== */

  test("Неизвестный инцидент и маршрут — 404 с кодом NOT_FOUND", async () => {
    const env = await makeEnv();
    assert.status(await env.call("GET", `/operator/incidents/${UNKNOWN}`), 404, "NOT_FOUND");
    assert.status(await env.act(UNKNOWN, "claim"), 404, "NOT_FOUND");
    assert.status(await env.call("GET", "/operator/nothing"), 404, "NOT_FOUND");
  });

  test("Поток событий: workflow.schema_published — стенд сменил схему, клиент её перечитывает (§14.10, BUG-34)", async () => {
    const env = await makeEnv();
    const got = [];
    const stop = env.api.subscribe((m) => got.push(m));
    // По сети поток подключается не сразу
    await new Promise((r) => setTimeout(r, 300));
    const published = async () => {
      await new Promise((r) => setTimeout(r, 300));
      return got.splice(0).filter((m) => m.type === "workflow.schema_published");
    };
    await makeEnv({ workflowPatch: { queueSort: { operatorMayChange: true } } });
    const first = await published();
    assert.eq(first.length, 1, "схему подменили — одно событие");
    assert.eq([first[0].incidentGuid, first[0].payload.schemaVersion], [null, W.schema.version], "не об инциденте, версия схемы");
    assert.eq((await env.api.get("/operator/workflow/active")).queueSort.operatorMayChange, true, "схема — уже новая");
    await makeEnv();
    assert.eq((await published()).length, 1, "вернули исходную — снова событие");
    await makeEnv();
    assert.eq((await published()).length, 0, "схема та же — события нет");
    stop();
  });

  test("Поток событий: автоэскалация — incident.transitioned по таймеру, было → стало и адресат; id: сообщения — его id (§9, RULE-60)", async () => {
    const env = await makeEnv();
    const got = [];
    const stop = env.api.subscribe((m, meta) => got.push({ m, meta }));
    const inc = await newFire(env);
    await env.advance(W.timers.find((x) => x.id === "reaction").overrides.find((o) => o.priority === TOP).sec + GRACE + 1);
    await new Promise((r) => setTimeout(r, 300));
    stop();
    const found = got.find(({ m }) => m.type === "incident.transitioned" && m.incidentGuid === inc.guid && m.payload.transitionId === "auto_escalate");
    assert.ok(found, `событие пришло: ${got.map(({ m }) => m.type).join(", ")}`);
    const p = found.m.payload;
    assert.eq([p.trigger, p.state.from, p.state.to], ["timer", "new", "pending_acceptance"], "по таймеру: новое → ожидает принятия");
    assert.eq(p.addressee.id, W.escalation.levels[0].targetRef.split(":")[1], "адресат в событии");
    // Сообщение SSE: id: совпадает с id в data — по нему переподключение с Last-Event-ID
    got.forEach(({ m, meta }) => assert.eq(meta && meta.lastEventId, m.id, `id: сообщения ${m.type}`));
    assert.eq(new Set(got.map(({ m }) => m.id)).size, got.length, "id сообщений не повторяются");
  });
})();
