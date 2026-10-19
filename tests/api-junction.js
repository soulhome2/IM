/* Тесты API стыка машины инцидента и машины сценариев (§14.5, Specification/Scenario_machine/, ARCH-06):
   каждая строка §14.5 и каждая строка таблицы «переход инцидента → прохождение сценария» из плана
   reviews/2026-10-19/plan.md. Как и остальные тесты API — только запросы контракта, поэтому их проходит
   и бэкенд. Сценарии — эталонного набора: пожар (версии 1 и 2) и проникновение. */
(() => {
  const { test, makeEnv, actionOf, assert, enc } = IMTest;
  const ME = "me";
  const FX = window.IM_FIXTURE;
  const FIRE = FX.scenarios.byEventType.fire;
  const LATEST_FIRE = Math.max(...FX.scenarios.rows.filter((r) => r.guid === FIRE).map((r) => r.version));
  const all = window.IM_WORKFLOW.permissions.map((p) => p.key).filter((k) => k !== "incident:schema:admin");

  const scenarioOf = async (env, guid) => env.ok("GET", `/operator/incidents/${enc(guid)}/scenario`);
  const answer = (env, guid, stepId, value) => env.answer(guid, { stepId, value });
  const answerOk = async (env, guid, stepId, value) => {
    const res = await answer(env, guid, stepId, value);
    assert.status(res, 200, null, `ответ на «${stepId}»`);
    return res.body;
  };
  const values = (sc) => Object.fromEntries(Object.entries(sc.result.state).map(([id, e]) => [id, e.skipped ? "skip" : e.value]));
  const newOf = async (env, type) => (await env.all("open")).filter((e) => e.state === "new" && e.eventType.id === type);
  // Новый инцидент от источника — появляется сейчас, на последней версии сценария своего типа события
  async function created(env, type) {
    const sample = (await env.all("all")).find((e) => e.eventType.id === type);
    const source = (await env.card(sample.guid)).source.guid;
    const res = await env.call("POST", "/test/incidents", { eventTypeId: type, deviceIds: [source], location: "тест" });
    assert.status(res, 201, null, "инцидент появился");
    return res.body;
  }
  // Своя копия набора: у пожара версии 1 шаг меняется на прогон стенда (PROC-13)
  function fireV1With(change) {
    const rows = JSON.parse(JSON.stringify(FX.scenarios.rows));
    const script = rows.find((r) => r.guid === FIRE && r.version === 1).script;
    change(script, (id) => script.steps.find((s) => s.id === id));
    return { scenarios: { rows } };
  }

  /* ===== Создание прохождения, версии (§14.5, ARCH-06 в4) ===== */

  test("Прохождение создаётся при появлении инцидента — на последней версии сценария; открытые доигрывают на своей (§14.5, ARCH-06 в4)", async () => {
    const env = await makeEnv();
    const card = await created(env, "fire");
    const sc = card.scenario;
    assert.eq([sc.scenarioGuid, sc.scenarioVersion, sc.script.scenario.version], [FIRE, LATEST_FIRE, LATEST_FIRE], "версия — последняя");
    assert.eq([sc.path, sc.result.state, sc.result.completedAt], [[sc.script.scenario.initialStep], {}, null], "прохождение с начала");
    const old = (await newOf(env, "fire")).find((e) => e.guid !== card.guid);
    assert.eq((await scenarioOf(env, old.guid)).scenarioVersion, 1, "инцидент из набора — на версии 1");
    // Версия 2 — с шагом «Эвакуация» после типа сработки; версия 1 — без него
    for (const [guid, next] of [[card.guid, "evacuation"], [old.guid, "note"]]) {
      assert.status(await env.act(guid, "claim", {}, "queue"), 200, null, "взять");
      await answerOk(env, guid, "visual", ["confirmed"]);
      await answerOk(env, guid, "verdict", "dispatch");
      const after = await answerOk(env, guid, "kind", { kind: ["smoke"] });
      assert.eq(after.result.currentStepId, next, `после типа сработки — ${next}`);
      if (guid === card.guid) await env.act(guid, "release", { comment: "тест" });
    }
  });

  /* ===== Набор «закрытие», прогресс, курсор (§14.5) ===== */

  test("«Обработан» — когда прохождение дошло до finish, а не когда отвечены обязательные шаги; тогда он и по умолчанию (§2.2, §14.5, в5)", async () => {
    const env = await makeEnv();
    const [inc] = await newOf(env, "fire");
    await env.act(inc.guid, "claim", {}, "queue");
    await answerOk(env, inc.guid, "visual", ["confirmed"]);
    let sc = await answerOk(env, inc.guid, "verdict", "dispatch");
    assert.eq(sc.requiredStepsFilled, { closing: false, none: true }, "обязательные отвечены, до finish не дошли");
    let field = actionOf(await env.card(inc.guid), "close").fieldOptions.resultId;
    assert.ok(field.options.find((o) => o.id === "processed").disabled && field.defaultValue === null, "«Обработан» недоступен");
    // Код — «не выполнен набор», а не общий отказ условия: по нему клиент подсказывает пройти сценарий (BUG-68)
    const refused = await env.act(inc.guid, "close", { resultId: "processed" });
    assert.status(refused, 403, "REQUIRED_STEPS_NOT_FILLED", "закрыть «Обработан»");
    assert.eq(refused.body.guard, "closeResultAllowed", "условие");
    await env.answer(inc.guid, { stepId: "kind", skip: true });
    sc = (await env.answer(inc.guid, { stepId: "note", skip: true })).body;
    assert.eq([sc.result.currentStepId, Boolean(sc.result.completedAt), sc.requiredStepsFilled.closing], [null, true, true], "пройден до finish");
    field = actionOf(await env.card(inc.guid), "close").fieldOptions.resultId;
    assert.eq(field.defaultValue, "processed", "«Обработан» по умолчанию");
  });

  test("Прогресс «N из M»: M — пройденное плюс кратчайший остаток до finish, при ветвлении меняется; в строке очереди — то же (§14.5, в6)", async () => {
    const env = await makeEnv();
    const [inc] = await newOf(env, "intrusion");
    await env.act(inc.guid, "claim", {}, "queue");
    // INC-1839 — «Проникновение» v2. Кратчайший путь: подтверждение, «Персонал / ложная», описание, «Доложил»
    const first = await scenarioOf(env, inc.guid);
    assert.eq(first.scenarioVersion, 2, "версия сценария");
    assert.eq([first.progress, first.ahead], [{ filled: 0, total: 4, step: 1 }, ["verdict", "note", "report"]], "в начале: шаги впереди — кратчайший путь (RULE-95)");
    assert.eq((await answerOk(env, inc.guid, "visual", ["confirmed"])).progress, { filled: 1, total: 4, step: 2 }, "после подтверждения");
    // «Реальное проникновение» ведёт через «Сообщил охране» и зону — путь длиннее
    const real = await answerOk(env, inc.guid, "verdict", "real");
    assert.eq([real.progress, real.ahead], [{ filled: 2, total: 6, step: 3 }, ["zone", "note", "report"]], "после ветвления: впереди — другой путь");
    const row = (await env.all("mine")).find((e) => e.guid === inc.guid);
    assert.eq([row.scenarioProgress.filled, row.scenarioProgress.total], [2, 6], "строка очереди");
  });

  test("Курсор: «Взять» и «Переоткрыть» ставят его на текущий шаг прохождения; ответы после закрытия и переоткрытия сохранены (§14.5, в10)", async () => {
    const env = await makeEnv();
    const [inc] = await newOf(env, "fire");
    const claimed = await env.act(inc.guid, "claim", {}, "queue");
    assert.status(claimed, 200, null, "взять");
    assert.eq((await scenarioOf(env, inc.guid)).cursorStepId, "visual", "после «Взять»");
    await answerOk(env, inc.guid, "visual", ["confirmed"]);
    assert.status(await env.call("PUT", `/operator/incidents/${enc(inc.guid)}/scenario/cursor`, { stepId: "visual" }), 200, null, "курсор назад");
    assert.status(await env.act(inc.guid, "close", { resultId: "false_alarm", comment: "тест" }), 200, null, "закрыть");
    const closed = await env.card(inc.guid);
    assert.ok(closed.readOnly, "закрытый — на просмотр");
    assert.status(await answer(env, inc.guid, "verdict", "real"), 403, "PERMISSION_DENIED", "ответ в закрытом");
    assert.status(await env.act(inc.guid, "reopen", { comment: "тест" }), 200, null, "переоткрыть");
    const sc = await scenarioOf(env, inc.guid);
    assert.eq([sc.cursorStepId, values(sc)], ["verdict", { visual: ["confirmed"] }], "курсор — текущий шаг, ответы сохранены");
  });

  /* ===== Ответ на шаг: путь, переответ, ошибки (профиль МИ, в7) ===== */

  test("Ответ не на шаг пути — 409 STEP_NOT_ON_PATH; неверное значение — 422 INVALID_ANSWER с причиной; обязательный не пропустить", async () => {
    const env = await makeEnv();
    const [inc] = await newOf(env, "fire");
    await env.act(inc.guid, "claim", {}, "queue");
    assert.status(await answer(env, inc.guid, "note", "рано"), 409, "STEP_NOT_ON_PATH", "шаг впереди");
    assert.status(await answer(env, inc.guid, "no_such_step", "x"), 409, "STEP_NOT_ON_PATH", "шага нет");
    await answerOk(env, inc.guid, "visual", ["confirmed"]);
    const bad = await answer(env, inc.guid, "verdict", "nope");
    assert.status(bad, 422, "INVALID_ANSWER", "вариант не из списка");
    assert.eq(bad.body.details && bad.body.details.reason, "option", "причина");
    const skip = await env.answer(inc.guid, { stepId: "verdict", skip: true });
    assert.status(skip, 422, "INVALID_ANSWER", "пропуск обязательного");
    assert.eq(skip.body.details && skip.body.details.reason, "required", "причина пропуска");
    assert.eq((await scenarioOf(env, inc.guid)).result.currentStepId, "verdict", "прохождение не сдвинулось");
  });

  test("Пройденный шаг: переответ меняет ветку — выпавшие шаги без ответа, в history остаются; шаг с revisitable: false — 409 (в7)", async () => {
    const env = await makeEnv({ fixturePatch: fireV1With((sc, step) => (step("visual").revisitable = false)) });
    const [intr] = await newOf(env, "intrusion");
    await env.act(intr.guid, "claim", {}, "queue");
    await answerOk(env, intr.guid, "visual", ["confirmed"]);
    await answerOk(env, intr.guid, "verdict", "real");
    await answerOk(env, intr.guid, "notify", null);
    await answerOk(env, intr.guid, "zone", { zone: ["warehouse"] });
    const sc = await answerOk(env, intr.guid, "verdict", "staff");
    assert.eq([sc.path, sc.result.currentStepId], [["visual", "verdict", "note"], "note"], "путь по новой ветке");
    assert.ok(!sc.result.state.zone && !sc.result.state.notify, "ответы выпавших шагов убраны");
    assert.ok(sc.result.history.some((h) => h.stepId === "zone" && h.action === "answer"), "в history он остался");
    const [fire] = await newOf(env, "fire");
    await env.act(fire.guid, "claim", {}, "queue");
    await answerOk(env, fire.guid, "visual", ["confirmed"]);
    assert.status(await answer(env, fire.guid, "visual", ["confirmed"]), 409, "STEP_NOT_EDITABLE", "переответ на revisitable: false");
  });

  test("Макрос исхода — один, по условиям run_macro; инцидент ответ не меняет (§14.5, в8)", async () => {
    const env = await makeEnv();
    const [inc] = await newOf(env, "fire");
    await env.act(inc.guid, "claim", {}, "queue");
    await answerOk(env, inc.guid, "visual", ["confirmed"]);
    const sc = await answerOk(env, inc.guid, "verdict", "real");
    const card = await env.card(inc.guid);
    assert.eq([card.state, card.owner.id, card.escalationLevel], ["in_progress", ME, 0], "инцидент тот же: в работе у меня, без эскалации");
    assert.eq(sc.result.history.filter((h) => h.action === "macro").map((h) => h.name), ["Оповещение и эвакуационные выходы"], "макрос — в прохождении");
    assert.eq(card.journal.filter((j) => j.templateKey === "workflow.journal.macro.launched").map((j) => j.vars.name), ["Оповещение и эвакуационные выходы"], "один макрос в журнале");
    // Без права запускать макросы ответ принят, а макрос — нет: ответы на переходы и права не влияют
    const noRun = await makeEnv({ permissions: all.filter((k) => k !== "incident:run_action") });
    const [other] = await newOf(noRun, "fire");
    await noRun.act(other.guid, "claim", {}, "queue");
    await answerOk(noRun, other.guid, "visual", ["confirmed"]);
    const res = await answerOk(noRun, other.guid, "verdict", "real");
    assert.ok(res.result.history.some((h) => h.action === "macro"), "намерение — в прохождении");
    assert.ok(!(await noRun.card(other.guid)).journal.some((j) => j.templateKey === "workflow.journal.macro.launched"), "макрос не запущен");
  });

  /* ===== Переходы инцидента и прохождение (таблица плана) ===== */

  test("Отложить, вернуть в очередь, передать: ответы и путь те же, отвечать нельзя; «Возобновить» и «Взять» — снова можно (§14.5)", async () => {
    const env = await makeEnv();
    const [inc] = await newOf(env, "fire");
    await env.act(inc.guid, "claim", {}, "queue");
    await answerOk(env, inc.guid, "visual", ["confirmed"]);
    const before = values(await answerOk(env, inc.guid, "verdict", "real"));
    assert.status(await env.act(inc.guid, "hold", { reasonId: "third_party", comment: "ждём" }), 200, null, "отложить");
    assert.status(await answer(env, inc.guid, "kind", { kind: ["smoke"] }), 403, "PERMISSION_DENIED", "ответ в отложенном");
    assert.eq(values(await scenarioOf(env, inc.guid)), before, "отложен — ответы те же");
    await env.act(inc.guid, "resume", {});
    assert.eq((await scenarioOf(env, inc.guid)).cursorStepId, "kind", "возобновлён — курсор на текущем шаге");
    await env.act(inc.guid, "release", { comment: "тест" });
    assert.eq(values(await scenarioOf(env, inc.guid)), before, "в очереди — ответы те же");
    await env.act(inc.guid, "claim", {}, "queue");
    await answerOk(env, inc.guid, "kind", { kind: ["smoke"] });
    assert.status(await env.act(inc.guid, "transfer", { targetId: "sidorov", comment: "тест" }), 200, null, "передать");
    assert.eq(values(await scenarioOf(env, inc.guid)).kind, { kind: ["smoke"] }, "передан — ответы те же");
    assert.ok((await env.card(inc.guid)).readOnly, "у меня — на просмотр");
  });

  test("Объединение разных версий одного сценария: переносится совместимое, шаг другой версии — нет; прохождение основного идёт дальше (§11.3, в11)", async () => {
    const env = await makeEnv();
    const v2 = await created(env, "fire");
    const [v1] = await newOf(env, "fire");
    assert.status(await env.act(v2.guid, "claim", {}, "queue"), 200, null, "взять v2");
    for (const [id, value] of [["visual", ["confirmed"]], ["verdict", "dispatch"], ["kind", { kind: ["smoke"] }], ["evacuation", "yes"]]) await answerOk(env, v2.guid, id, value);
    assert.status(await env.act(v2.guid, "release", { comment: "тест" }), 200, null, "v2 — в очередь");
    assert.status(await env.act(v1.guid, "claim", {}, "queue"), 200, null, "взять v1");
    await answerOk(env, v1.guid, "visual", ["confirmed"]);
    const before = values(await scenarioOf(env, v2.guid));
    const res = await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [v1.guid, v2.guid], primaryGuid: v1.guid });
    const primary = await scenarioOf(env, res.incident.guid);
    assert.eq(primary.scenarioVersion, 1, "основной — на своей версии");
    assert.eq(values(primary), { visual: ["confirmed"], verdict: "dispatch", kind: { kind: ["smoke"] } }, "перенесены классификация и тип; эвакуации в версии 1 нет");
    assert.eq(primary.result.currentStepId, "note", "прохождение основного — до первого неотвеченного");
    const entry = (await env.card(v1.guid)).journal.filter((e) => e.templateKey === "workflow.journal.answers_moved").pop();
    assert.ok(entry && entry.vars.n === 2, `в журнале основного перенесено 2: ${entry && entry.text}`);
    const linked = await env.card(v2.guid);
    assert.eq([linked.state, values(linked.scenario)], ["linked", before], "у привязанного ответы — история");
    assert.status(await answer(env, v2.guid, "note", "x"), 403, "PERMISSION_DENIED", "привязанный — на просмотр");
    // «Отсоединить»: прохождение отсоединённого — как было
    assert.status(await env.call("DELETE", `/operator/incidents/${enc(v1.guid)}/linked/${enc(v2.guid)}`), 200, null, "отсоединить");
    const detached = await env.card(v2.guid);
    assert.eq([detached.state, values(detached.scenario), detached.scenario.scenarioVersion], ["new", before, 2], "отсоединён: новый, ответы и версия те же");
  });

  test("Закрытие основного закрывает привязанные — их прохождение заморожено как было (close_linked, §11.4)", async () => {
    const env = await makeEnv();
    const [a, b] = await newOf(env, "fire");
    await env.act(a.guid, "claim", {}, "queue");
    await answerOk(env, a.guid, "visual", ["confirmed"]);
    await env.act(a.guid, "release", { comment: "тест" });
    const before = values(await scenarioOf(env, a.guid));
    await env.act(b.guid, "claim", {}, "queue");
    await env.ok("POST", "/operator/incidents/merge", { incidentGuids: [a.guid, b.guid], primaryGuid: b.guid });
    assert.status(await env.act(b.guid, "close", { resultId: "false_alarm", comment: "тест" }), 200, null, "закрыть основной");
    const linked = await env.card(a.guid);
    assert.eq([linked.state, values(linked.scenario), linked.readOnly], ["closed", before, true], "привязанный закрыт, прохождение то же, на просмотр");
  });
})();
