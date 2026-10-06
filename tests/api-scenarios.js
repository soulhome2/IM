/* Сценарные тесты API: «состояние, запрос → новое состояние, владелец, таймеры, журнал, коды
   ошибок». Это исполняемая спецификация операторской части: те же проверки должен проходить
   и бэкенд. Номера разделов — из Specification/State_rules/States rules IM.md. */
(() => {
  const { test, makeEnv, formFor, fullAnswers, actionOf, assert, enc } = IMTest;
  const ME = "me";
  const W = window.IM_WORKFLOW;

  // Стенд со своей копией схемы или набора (PROC-13): отличающиеся разделы уходят в POST /test/reset
  // как JSON Merge Patch — так тест идёт и против встроенного сервера, и против бэкенда
  const changed = (base, copy) =>
    copy ? Object.fromEntries(Object.keys(copy).filter((k) => JSON.stringify(copy[k]) !== JSON.stringify(base[k])).map((k) => [k, copy[k]])) : undefined;
  const standWith = ({ workflow, fixture }) => makeEnv({ workflowPatch: changed(W, workflow), fixturePatch: changed(window.IM_FIXTURE, fixture) });
  const lastJournal = (card) => card.journal[card.journal.length - 1];

  // Инцидента с таким идентификатором нет: формат верный, записи нет
  const UNKNOWN = "10000000-0000-4000-8000-000000000000";

  // Новое критическое событие пожара — их в демо два, однотипная пара для группы (§11)
  const newFire = (env) => env.find((e) => e.state === "new" && e.eventType.id === "fire" && e.priority === "critical");

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
    assert.eq(lastJournal(c).templateKey, "Взято в работу", "журнал");
    assert.eq(res.body.navigate, "card", "переход в карточку");
    assert.eq((await env.session()).usage.activeCount, 1, "активных у меня");
  });

  test("Лимит активных 1: второе «Взять» недоступно и отклоняется сервером", async () => {
    const env = await makeEnv();
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
    await env.advance(30 * 60 + 1);
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
    const full = W.timers.find((x) => x.id === "resolution").byPriority.critical * 1000;
    assert.ok(left <= full - 119000, `норматив закрытия продолжен: осталось ${left} из ${full}`);
  });

  /* ===== Передать (§8, RULE-19, RULE-20) ===== */

  test("Передать человеку: ожидает принятия, адресат в owner, уровень +1, норматив закрытия на паузе", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    await env.act(inc.guid, "claim", {}, "queue");
    const res = await env.act(inc.guid, "transfer", { targetId: "sidorov", comment: "нужен допуск" });
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.state, "pending_acceptance", "состояние");
    assert.eq(c.owner && c.owner.id, "sidorov", "owner — человек");
    assert.eq(c.assignmentGroup, null, "группы нет");
    assert.eq(c.escalationLevel, 1, "уровень");
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
      assert.eq([c.state, c.owner, c.holdReasonId, c.groupGuid], ["new", null, null, null], `${inc.number}: новый, ничей, без причины и группы`);
      assert.ok(c.journal.some((j) => /оператор вышел/.test(j.templateKey)), `${inc.number}: запись в журнале`);
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
    assert.ok(c.journal.some((j) => /Адресат вышел, не приняв/.test(j.templateKey)), "запись в журнале");
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
    assert.ok(card.journal.some((j) => /Адресат вышел/.test(j.templateKey)), "запись в журнале");
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
  });

  test("Отклонить: инцидент снова новый, ничей, уровень эскалации сохранён", async () => {
    const env = await makeEnv();
    const inc = await env.card(await env.guidOf("INC-1843"));
    assert.eq(inc.badge.label, "Вам на принятие", "бейдж личной передачи");
    const res = await env.act(inc.guid, "reject", { comment: "не мой профиль" });
    assert.status(res, 200);
    const c = res.body.incident;
    assert.eq(c.state, "new", "состояние");
    assert.eq(c.owner, null, "владелец");
    assert.eq(c.escalationLevel, inc.escalationLevel, "уровень сохранён");
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
    const left = Math.ceil((Date.parse(inc.timer.dueAt) - env.now) / 1000) + 1;
    await env.advance(left);
    const c = await env.card(inc.guid);
    assert.eq([c.owner && c.owner.id, c.escalationLevel], [second, 2], "первый уровень пропущен — сразу второй");
  });

  test("Связи камер (§19.1, RULE-49): устройство → камеры по порядку, как в наборе; без права incident:schema:admin — 403", async () => {
    const env = await makeEnv();
    const links = await env.ok("GET", "/operator/admin/camera-links");
    assert.eq(links.map((l) => [l.device.guid, l.cameras.map((c) => c.guid)]), window.IM_FIXTURE.cameraLinks.map((l) => [l.device, l.cameras]), "связи и порядок камер — из набора");
    assert.ok(links.every((l) => l.device.name && l.cameras.every((c) => c.name)), "с именами устройств и камер");
    const all = W.permissions.map((p) => p.key).filter((k) => k !== "incident:schema:admin");
    assert.status(await (await makeEnv({ permissions: all })).call("GET", "/operator/admin/camera-links"), 403, "PERMISSION_DENIED", "без права");
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

  test("Порядок автоматических переходов — по времени наступления (RULE-41): прыжок часов и прогон мелкими шагами дают одно и то же", async () => {
    // Взял инцидент, связь пропала; эскалация по закрытию включена. Первой наступает потеря связи
    // (5 минут), а не норматив закрытия — инцидент отложен, и закрытие уже не эскалируется
    async function run(stepSec) {
      const w = JSON.parse(JSON.stringify(W));
      w.escalation.onResolutionOverdue = "escalate";
      const api = (await standWith({ workflow: w })).api;
      const inc = (await api.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.state === "new" && e.eventType.id === "fire" && e.priority === "critical");
      const etag = (await api.raw("GET", `/operator/incidents/${enc(inc.guid)}`)).headers.etag;
      assert.status(await api.raw("POST", `/operator/incidents/${enc(inc.guid)}/transitions/claim`, { formValues: {}, surface: "queue" }, { "If-Match": etag }), 200, null, "взять");
      await api.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: inc.guid });
      const fired = [];
      for (let left = 7200; left > 0; left -= stepSec) {
        fired.push(...(await api.raw("POST", "/test/clock", { advanceSec: Math.min(stepSec, left) })).body.fired.filter((f) => f.incidentGuid === inc.guid).map((f) => f.transitionId));
      }
      const c = await api.get(`/operator/incidents/${enc(inc.guid)}`);
      return { fired, end: [c.state, c.owner && c.owner.id, c.escalationLevel, c.breaches.map((b) => b.kind)] };
    }
    const steps = await run(37);
    const jump = await run(7200);
    assert.eq(steps.fired.slice(0, 2), ["system_hold_idle", "system_release_idle"], "сначала потеря связи, потом возврат в очередь");
    assert.ok(!steps.fired.includes("resolution_escalate"), "отложенный по потере связи по закрытию не эскалируется");
    assert.eq(jump.fired, steps.fired, "прыжок часов — те же переходы в том же порядке");
    assert.eq(jump.end, steps.end, "и тот же итог");
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

  test("Догон: переход без таймера — сразу после того, который сделал его возможным (RULE-48)", async () => {
    // Я вышел; первый уровень эскалации — на меня. Эскалация на меня делает возможным «адресат
    // вышел» — он должен сработать сразу, раньше следующего уровня, при любом шаге часов
    async function run(stepSec) {
      const w = JSON.parse(JSON.stringify(W));
      w.escalation.levels[0].targetRef = `user:${ME}`;
      const api = (await standWith({ workflow: w })).api;
      const inc = (await api.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.state === "new" && e.escalationLevel === 0);
      assert.status(await api.raw("PUT", "/operator/session/agent-state", { agentState: "offline" }), 200, null, "выйти");
      const fired = [];
      for (let left = 3600; left > 0; left -= stepSec) {
        fired.push(...(await api.raw("POST", "/test/clock", { advanceSec: Math.min(stepSec, left) })).body.fired.filter((f) => f.incidentGuid === inc.guid).map((f) => f.transitionId));
      }
      const c = await api.get(`/operator/incidents/${enc(inc.guid)}`);
      return { fired, end: [c.state, c.owner && c.owner.id, c.assignmentGroup && c.assignmentGroup.id, c.escalationLevel] };
    }
    const steps = await run(37);
    const jump = await run(3600);
    assert.eq(steps.fired.slice(0, 2), ["auto_escalate", "addressee_signed_out_to_group"], "эскалация на меня — и сразу моей группе");
    assert.eq(jump.fired, steps.fired, "прыжок часов — те же переходы в том же порядке");
    assert.eq(jump.end, steps.end, "и тот же итог");
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
      for (let left = Math.ceil((Date.parse(card.timer.dueAt) - now) / 1000) + 1; left > 0; left -= 240) {
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
      assert.ok(c.journal.some((j) => /Норматив реакции нарушен/.test(j.templateKey)), `${why}: запись в журнале`);
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
    const fired = await env.advance(longestResolution() + 1);
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
      for (let left = longestResolution() + 1; left > 0; left -= 240) {
        await api.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        await api.raw("POST", "/test/clock", { advanceSec: Math.min(240, left) });
      }
      await new Promise((r) => setTimeout(r, 300));
      stop();
      const c = await api.get(`/operator/incidents/${enc(inc.guid)}`);
      assert.ok(c.journal.some((j) => /Норматив закрытия нарушен/.test(j.templateKey)), `${why}: нарушение записано`);
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
    assert.ok(c.journal.some((j) => /не может принять/.test(j.templateKey)), "запись в журнале");
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
    const reactionSec = W.timers.find((x) => x.id === "reaction").overrides.find((o) => o.priority === "critical").sec;
    await env.advance(reactionSec + 1);
    let c = await env.card(inc.guid);
    const levels = W.escalation.levels;
    assert.eq(c.state, "pending_acceptance", "после реакции");
    assert.eq(c.escalationLevel, 1, "уровень");
    assert.eq(c.owner && c.owner.id, levels[0].targetRef.split(":")[1], "адресат уровня 1");
    await env.advance(levels[0].reactionSec + 1);
    c = await env.card(inc.guid);
    assert.eq(c.escalationLevel, 2, "уровень 2");
    assert.eq(c.owner && c.owner.id, levels[1].targetRef.split(":")[1], "адресат уровня 2");
    await env.advance(levels[1].reactionSec + 1);
    c = await env.card(inc.guid);
    assert.eq(c.escalationLevel, W.escalation.maxLevel, "выше потолка не поднимается");
    assert.ok(c.breaches.some((b) => b.kind === "reaction"), "нарушение реакции записано");
    assert.ok(c.journal.some((j) => /Автоэскалация/.test(j.templateKey)), "автоэскалация в журнале");
  });

  test("Эскалация по нормативу закрытия (§9, RULE-27): при escalate — передача адресату уровня, на потолке — нарушение и алерт", async () => {
    // Своя копия машины с другой настройкой — так правило проверяется из машины, а не из кода
    async function overdue(patch) {
      const w = JSON.parse(JSON.stringify(W));
      w.escalation.onResolutionOverdue = "escalate";
      patch(w);
      const api = (await standWith({ workflow: w })).api;
      const fire = (await api.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find(
        (e) => e.state === "new" && e.eventType.id === "fire" && e.priority === "critical"
      );
      const etag = (await api.raw("GET", `/operator/incidents/${enc(fire.guid)}`)).headers.etag;
      const claimed = await api.raw("POST", `/operator/incidents/${enc(fire.guid)}/transitions/claim`, { formValues: {}, surface: "queue" }, { "If-Match": etag });
      assert.status(claimed, 200, null, "взять");
      // Оператор на месте: часы шагами короче idleHoldSec, перед каждым — heartbeat. Ровно до
      // истечения норматива критического пожара: дальше по времени пошла бы уже реакция уровня (RULE-41)
      let left = w.timers.find((t) => t.id === "resolution").byPriority.critical + 1;
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
      let left = Math.ceil((Date.parse(inc.timer.dueAt) - Date.parse(reset.body.now)) / 1000) + 1;
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
    await env.advance(Math.ceil((Date.parse(res.body.incident.timer.dueAt) - env.now) / 1000) + 1);
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
    const fired = await esc.advance(Math.ceil((Date.parse(claimed.body.incident.timer.dueAt) - esc.now) / 1000) + 1);
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
    await env.advance(Math.ceil(left / 1000) + 1);
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

  /* ===== Группа сценария и выборка (§11) ===== */

  test("«Обработать как одно»: оба в работе одной группой, в лимите — одна единица, ответы общие", async () => {
    const env = await makeEnv();
    const fires = (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === "fire").slice(0, 2);
    const res = await env.call("POST", "/operator/incident-groups", { incidentGuids: fires.map((e) => e.guid) });
    assert.status(res, 201);
    const group = res.body;
    assert.eq(group.members.length, 2, "в группе");
    assert.ok(group.members.every((m) => m.state === "in_progress" && m.groupGuid === group.guid), "оба в работе одной группой");
    assert.ok(group.members.every((m) => m.groupSize === 2), "размер группы у каждого — 2");
    assert.eq((await env.session()).usage.activeCount, 1, "одна единица в лимите");
    assert.status(await env.answer(fires[0].guid, { visual: true }), 200, null, "ответ в группе");
    assert.eq((await env.card(fires[1].guid)).scenario.answers.visual, true, "ответ виден у второго");
    const c = await env.card(fires[0].guid);
    assert.ok(!c.group.exclude.enabled && /Лимит активных/.test(c.group.exclude.reason), "исключить нельзя — лимит");
    assert.status(await env.call("DELETE", `/operator/incident-groups/${enc(group.guid)}/members/${enc(fires[0].guid)}`), 403, "LIMIT_EXCEEDED");
  });

  test("Группа из разных типов событий не создаётся", async () => {
    const env = await makeEnv();
    const news = (await env.all("open")).filter((e) => e.state === "new");
    const mixed = [news.find((e) => e.eventType.id === "fire"), news.find((e) => e.eventType.id !== "fire")];
    assert.status(await env.call("POST", "/operator/incident-groups", { incidentGuids: mixed.map((e) => e.guid) }), 422, "BULK_SELECTION_INVALID");
    assert.ok((await env.all("open")).filter((e) => mixed.some((m) => m.guid === e.guid)).every((e) => e.state === "new"), "никто не взят");
  });

  test("Выборка: однотипные — только новые того же типа; смешанная — «Взять» выборкой недоступно", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    const same = await env.ok("POST", "/operator/incidents/selection", { mode: "same_type_new", anchorIncidentGuid: inc.guid, filter: "open" });
    const all = await env.all();
    assert.ok(same.incidentGuids.length >= 2, "нашлись однотипные");
    assert.ok(same.incidentGuids.every((id) => all.find((e) => e.guid === id).eventType.id === "fire"), "все — пожарные");
    assert.ok(same.incidentGuids.every((id) => all.find((e) => e.guid === id).state === "new"), "все — новые");
    const mixed = all.filter((e) => e.state === "new").filter((e, i, list) => list.findIndex((x) => x.eventType.id === e.eventType.id) === i).slice(0, 2);
    const sel = await env.ok("POST", "/operator/incidents/selection", { mode: "explicit", incidentGuids: mixed.map((e) => e.guid) });
    assert.ok(!sel.actions.find((a) => a.id === "claim").enabled, "«Взять» на смешанной выборке");
    const allIn = await env.ok("POST", "/operator/incidents/selection", { mode: "all_in_filter", filter: "open" });
    assert.ok(allIn.incidentGuids.length <= W.limits.maxBulk, "не больше лимита выборки");
    assert.eq(allIn.truncated, (await env.all("open")).length > W.limits.maxBulk, "признак усечения");
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
    assert.ok(c.journal.some((j) => j.templateKey === "Запущен макрос «{name}»" && j.vars.name === name), "макрос в журнале");
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
    const tree = await env.ok("GET", "/operator/reference/source-groups");
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

  test("Схема workflow, справочники и приоритеты — те, что в машине", async () => {
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
    assert.eq(priorities.map((x) => x.id), ["critical", "high", "medium", "low"], "приоритеты");
  });

  test("Настройки оператора: предвыбор адресата меняет значение по умолчанию в форме передачи (§8.2)", async () => {
    const env = await makeEnv();
    const preset = window.IM_FIXTURE.operatorPreferences;
    const initial = (await env.session()).preferences;
    Object.entries(preset).forEach(([key, value]) => assert.eq(initial[key], value, `после сброса ${key} — из эталонного набора`));
    await env.ok("PATCH", "/operator/session/preferences", { defaultTransferTargetId: "noc" });
    assert.eq((await env.session()).preferences.defaultTransferTargetId, "noc", "сохранено в сессии");
    const inc = await newFire(env);
    assert.eq(actionOf(inc, "transfer").fieldOptions.targetId.defaultValue, "noc", "по умолчанию в форме");
    assert.status(await env.heartbeat(inc.guid), 204, null, "признак активности");
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
    // Камеры инцидента — из связи его источника (§19.1, RULE-49), первая — главная
    const camerasOf = (inc) => (fx.cameraLinks.find((l) => l.device === inc.devices[0]) || { cameras: [] }).cameras;
    for (const inc of fx.incidents) {
      const media = await env.ok("GET", `/operator/incidents/${enc(inc.guid)}/media`);
      const ids = [...new Set([...inc.devices, ...camerasOf(inc)])];
      const source = inc.devices[0];
      assert.eq(
        media.cameras.map((c) => [c.guid, c.thumbnailUrl, c.isSource]),
        camerasOf(inc).map((id) => [id, dev[id].thumbnailUrl || null, id === source]),
        `${inc.number}: камеры из связи источника`
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
    await env.advance(W.timers.find((x) => x.id === "reaction").overrides.find((o) => o.priority === "critical").sec + 1);
    await new Promise((r) => setTimeout(r, 300));
    stop();
    assert.ok(got.length > 0, "события о доступных пришли");
    // Кроме потери доступа к моим: в наборе есть инциденты вне ТЦ, адресованные мне (BUG-24)
    assert.ok(got.every((m) => !m.incidentGuid || seen.some((i) => i.guid === m.incidentGuid) || (m.type === "incident.access_lost" && !m.incident)), "о недоступных событий нет");
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
      assert.ok(c.journal.some((j) => /нет доступа к объекту/.test(j.templateKey)), `${inc.number}: запись в журнале`);
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

  test("Комментарий оператора в журнале: состояние не меняется, пустой не принимается", async () => {
    const env = await makeEnv();
    const inc = await newFire(env);
    assert.status(await env.call("POST", `/operator/incidents/${enc(inc.guid)}/journal`, { text: "  " }), 422, "FORM_FIELD_REQUIRED");
    const res = await env.call("POST", `/operator/incidents/${enc(inc.guid)}/journal`, { text: "Позвонил на пост" });
    assert.status(res, 201);
    assert.eq([res.body.kind, res.body.text, res.body.actor.id], ["note", "Позвонил на пост", ME], "запись");
    const c = await env.card(inc.guid);
    assert.eq(c.state, "new", "состояние не изменилось");
    assert.eq(lastJournal(c).text, "Позвонил на пост", "в журнале карточки");
  });

  /* ===== Эмуляция коллег во встроенном сервере (§17) ===== */

  test("Коллеги действуют через переходы машины: взять, передать мне, потеря связи и возврат в очередь (§12.3)", async () => {
    if (IMTest.external) return "пропущено: эмуляция коллег есть только во встроенном сервере";
    const server = IMServer.create({
      workflow: W,
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
    const taken = cards.filter((c) => before.get(c.guid).state === "new" && entry(c, "Взято в работу"));
    assert.ok(taken.length > 0, "коллеги ничего не взяли");
    taken.forEach((c) => assert.ok(colleagues.has(entry(c, "Взято в работу").actor.id), `${c.guid}: взял не коллега`));
    // Лимит активных — у каждого коллеги свой (§10.2)
    const active = {};
    cards.filter((c) => c.state === "in_progress" && c.owner && colleagues.has(c.owner.id)).forEach((c) => {
      active[c.owner.id] = (active[c.owner.id] || 0) + 1;
    });
    Object.entries(active).forEach(([who, n]) => assert.ok(n <= W.limits.maxActive, `у ${who} в работе ${n} > ${W.limits.maxActive}`));

    // Передача мне: переход «Передать» от имени коллеги — ожидает моего принятия
    const handed = cards.filter((c) => c.state === "pending_acceptance" && c.ownership === "target" && before.get(c.guid).state === "in_progress");
    assert.eq(handed.length, 1, "передано мне коллегой");
    const transfer = handed[0].journal[handed[0].journal.length - 1];
    assert.ok(/^Передано →/.test(transfer.templateKey) && colleagues.has(transfer.actor.id), `запись о передаче: ${transfer.templateKey}`);

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

  test("Поток событий: автоэскалация приходит событием incident.auto_escalated с адресатом; id: сообщения — его id", async () => {
    const env = await makeEnv();
    const got = [];
    const stop = env.api.subscribe((m, meta) => got.push({ m, meta }));
    const inc = await newFire(env);
    await env.advance(W.timers.find((x) => x.id === "reaction").overrides.find((o) => o.priority === "critical").sec + 1);
    await new Promise((r) => setTimeout(r, 300));
    stop();
    const found = got.find(({ m }) => m.type === "incident.auto_escalated" && m.incidentGuid === inc.guid);
    assert.ok(found, `событие пришло: ${got.map(({ m }) => m.type).join(", ")}`);
    assert.eq(found.m.payload.addressee.id, W.escalation.levels[0].targetRef.split(":")[1], "адресат в событии");
    // Сообщение SSE: id: совпадает с id в data — по нему переподключение с Last-Event-ID
    got.forEach(({ m, meta }) => assert.eq(meta && meta.lastEventId, m.id, `id: сообщения ${m.type}`));
    assert.eq(new Set(got.map(({ m }) => m.id)).size, got.length, "id сообщений не повторяются");
  });
})();
