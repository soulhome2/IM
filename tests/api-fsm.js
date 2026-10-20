/* Сценарии формальной проверки машины состояний (скилл im-fsm): то, что нельзя проверить чтением
   машины, — как автоматические переходы ведут себя во времени. Названия начинаются с «im-fsm:»,
   по ним скилл находит результаты. Тесты идут против встроенного сервера и против бэкенда: другая
   настройка схемы — изменениями на прогон в POST /test/reset (PROC-13).

   Наборы ниже перечислены по машине: если в ней появится переход без смены состояния, новый
   вход в «В работе» или ручной переход, после которого таймер продолжается, для которого здесь нет
   сценария, — тест «покрытие» упадёт. */
(() => {
  const { test, makeEnv, assert, enc } = IMTest;
  const ME = "me";
  const W = window.IM_WORKFLOW;
  // Окно после дедлайна (RULE-63): переход по таймеру — через graceSec после дедлайна
  const GRACE = ((W.invariants || {}).manualWinsOverTimer || {}).graceSec || 0;

  const changed = (base, copy) =>
    copy ? Object.fromEntries(Object.keys(copy).filter((k) => JSON.stringify(copy[k]) !== JSON.stringify(base[k])).map((k) => [k, copy[k]])) : undefined;
  const standWith = ({ workflow, fixture }) => makeEnv({ workflowPatch: changed(W, workflow), fixturePatch: changed(window.IM_FIXTURE, fixture) });
  // Своя копия машины с изменённой эскалацией
  const withEscalation = (patch) => Object.assign({}, W, { escalation: Object.assign({}, W.escalation, patch) });
  const levelsTo = (refs) => W.escalation.levels.map((l, i) => (refs[i] ? Object.assign({}, l, { targetRef: refs[i] }) : l));
  // Самый срочный уровень справочника приоритетов (§2.5): тесты не знают уровни по имени
  const TOP = Math.max(...window.IM_FIXTURE.priorities.map((p) => p.value));
  const newFire = (env) => env.find((e) => e.state === "new" && e.eventType.id === "fire" && e.priority === TOP);
  const firedFor = (fired, guid) => fired.filter((f) => f.incidentGuid === guid).map((f) => f.transitionId);
  // До дедлайна норматива из карточки — плюс секунда
  const untilDue = (env, card) => Math.ceil((Date.parse(card.timer.dueAt) - env.now) / 1000) + GRACE + 1;

  /* ===== Прыжок часов против шагов (§14.3, RULE-41, RULE-48) ===== */

  // Пары из карты пересечений (check_machine.py --fsm), где оба события наступают по времени или одно
  // открывает дорогу другому. Пары с действием человека (вышел, сменили роли) сервер обрабатывает в
  // момент действия; с таймером они совпадают в окне после дедлайна — набор WINDOW ниже
  const ORDER = [
    {
      name: "закрытие × молчание: первой наступает потеря связи, отложенный по закрытию не эскалируется",
      workflow: withEscalation({ onResolutionOverdue: "escalate" }),
      windowSec: 7200,
      async setup(env) {
        const inc = await newFire(env);
        assert.status(await env.act(inc.guid, "claim", {}, "queue"), 200, null, "взять");
        await env.heartbeat(inc.guid);
        return inc.guid;
      },
      first: ["system_hold_idle", "system_release_idle"],
    },
    {
      name: "реакция × адресат вышел: эскалация на меня, вышедшего, — и сразу моей группе",
      workflow: withEscalation({ levels: levelsTo([`user:${ME}`]) }),
      windowSec: 3600,
      async setup(env) {
        const inc = await env.find((e) => e.state === "new" && e.escalationLevel === 0);
        assert.status(await env.call("PUT", "/operator/session/agent-state", { agentState: "offline" }), 200, null, "выйти");
        return inc.guid;
      },
      first: ["auto_escalate", "addressee_signed_out_to_group"],
    },
    {
      name: "удержание × долгое молчание: «нет связи», потом в очередь раньше срока удержания",
      workflow: W,
      windowSec: 1600,
      async setup(env) {
        const inc = await newFire(env);
        assert.status(await env.act(inc.guid, "claim", {}, "queue"), 200, null, "взять");
        await env.heartbeat(inc.guid);
        return inc.guid;
      },
      first: ["system_hold_idle", "system_release_idle"],
    },
    {
      // Потеря связи через секунду после дедлайна — внутри окна: переход по таймеру первым, и оба — в
      // момент потери связи, при любом шаге (RULE-67, BUG-38). Шаг — секунда, иначе в окно не попасть
      name: "закрытие × молчание внутри окна: нарушение и «нет связи» в одну секунду",
      workflow: W,
      windowSec: W.session.idleHoldSec + 10,
      stepSec: 1,
      async setup(env) {
        const inc = await newFire(env);
        const claimed = await env.act(inc.guid, "claim", {}, "queue");
        assert.status(claimed, 200, null, "взять");
        await env.advance(Math.round((Date.parse(claimed.body.incident.timer.dueAt) - env.now) / 1000) - W.session.idleHoldSec + 1);
        await env.heartbeat(inc.guid);
        return inc.guid;
      },
      first: ["resolution_overdue", "system_hold_idle"],
    },
  ];
  ORDER.forEach((c) => {
    test(`im-fsm: прыжок часов и шаги — один итог: ${c.name}`, async () => {
      async function run(stepSec) {
        const env = await standWith({ workflow: c.workflow });
        const guid = await c.setup(env);
        const start = env.now;
        const fired = [];
        // Без признака активности: молчание оператора идёт, как во время простоя
        for (let left = c.windowSec; left > 0; left -= stepSec) {
          fired.push(...firedFor((await env.call("POST", "/test/clock", { advanceSec: Math.min(stepSec, left) })).body.fired, guid));
        }
        const card = await env.card(guid);
        // Время — в секундах от начала прогона: записи журнала, нарушения и идущие сроки (PROC-19)
        const sec = (iso) => (iso ? (Date.parse(iso) - start) / 1000 : null);
        const times = {
          journal: card.journal.map((j) => `${j.templateKey}@${sec(j.at)}`),
          breaches: card.breaches.map((b) => `${b.kind}@${sec(b.at)}`),
          timers: [card.timer && sec(card.timer.dueAt), card.holdTimer && sec(card.holdTimer.dueAt)],
        };
        return { fired, end: [card.state, card.owner && card.owner.id, card.assignmentGroup && card.assignmentGroup.id, card.escalationLevel, card.breaches.map((b) => b.kind)], times };
      }
      // Шаг короче любого порога (молчание — 5 минут), но не мельче нужного: итог тот же, вызовов меньше
      const steps = await run(c.stepSec || 120);
      const jump = await run(c.windowSec);
      assert.eq(steps.fired.slice(0, c.first.length), c.first, "порядок при шагах");
      assert.eq(jump.fired, steps.fired, "прыжок часов — те же переходы в том же порядке");
      assert.eq(jump.end, steps.end, "и тот же итог");
      assert.eq(jump.times, steps.times, "и то же время записей, нарушений и сроков");
    });
  });

  /* ===== Повторный вход: истёкший норматив закрытия не срабатывает снова (RULE-50) ===== */

  // Каждый вход в «В работе», кроме переоткрытия: оно запускает норматив заново (§4, правило 6)
  const REENTRY = {
    resume: {
      name: "«Отложить» → «Возобновить»",
      async run(env, guid) {
        assert.status(await env.act(guid, "hold", { reasonId: "third_party", comment: "ждём" }), 200, null, "отложить");
        assert.status(await env.act(guid, "resume"), 200, null, "возобновить");
      },
    },
    claim: {
      name: "«Вернуть в очередь» → «Взять»",
      async run(env, guid) {
        assert.status(await env.act(guid, "release", { comment: "не моё" }), 200, null, "вернуть");
        assert.status(await env.act(guid, "claim", {}, "queue"), 200, null, "взять снова");
      },
    },
    takeover: {
      name: "«Передать» Сидорову → «Перехватить»",
      async run(env, guid) {
        assert.status(await env.act(guid, "transfer", { targetId: "sidorov", comment: "тест" }), 200, null, "передать");
        assert.status(await env.act(guid, "takeover", { comment: "беру обратно" }, "card"), 200, null, "перехватить");
      },
    },
    accept: {
      name: "эскалация по закрытию моей группе → «Принять»",
      workflow: withEscalation({ onResolutionOverdue: "escalate", levels: levelsTo(["group:grp-leads"]) }),
      async run(env, guid) {
        assert.status(await env.act(guid, "accept", {}, "queue"), 200, null, "принять");
      },
    },
  };
  // Курсор сценария (§14.5, RULE-53): шаг 1 заполнен, курсор возвращён на него — после входа в работу
  // он на первом незаполненном
  const cursorOf = async (env, guid) => (await env.call("GET", `/operator/incidents/${enc(guid)}/scenario`)).body.cursorStepId;
  Object.entries(REENTRY).forEach(([id, c]) => {
    test(`im-fsm: повторный вход в работу не даёт нового срока, курсор — на первый незаполненный шаг: ${c.name}`, async () => {
      const env = await standWith({ workflow: c.workflow || W });
      const inc = await newFire(env);
      const claimed = await env.act(inc.guid, "claim", {}, "queue");
      const first = (await env.call("GET", `/operator/incidents/${enc(inc.guid)}/scenario`)).body.result.currentStepId;
      assert.status(await env.answerCurrent(inc.guid), 200, null, "ответ на шаг 1");
      const second = (await env.call("GET", `/operator/incidents/${enc(inc.guid)}/scenario`)).body.result.currentStepId;
      assert.status(await env.call("PUT", `/operator/incidents/${enc(inc.guid)}/scenario/cursor`, { stepId: first }), 200, null, "курсор на шаг 1");
      const expired = firedFor(await env.advance(untilDue(env, claimed.body.incident)), inc.guid);
      assert.ok(expired.some((t) => t.startsWith("resolution_")), `норматив закрытия истёк: ${expired}`);
      await c.run(env, inc.guid);
      const again = firedFor(await env.advance(5), inc.guid);
      assert.eq(again, [], `после «${id}» ничего не сработало`);
      assert.eq((await env.card(inc.guid)).breaches.filter((b) => b.kind === "resolution").length, 1, "нарушение закрытия одно");
      assert.eq(await cursorOf(env, inc.guid), second, `после «${id}» курсор на первом незаполненном шаге`);
    });
  });

  // Каждый вход в «Привязан» (§11.4): истёк срок группы, привязанный отсоединили и снова взяли в работу
  // одним с тем же основным — отработанный срок не возвращается, второго нарушения нет (PROC-20, RULE-97)
  const mergeTwo = async (env) => {
    const linked = await newFire(env);
    assert.status(await env.act(linked.guid, "claim", {}, "queue"), 200, null, "взять будущий привязанный");
    const primary = (await env.all("open")).find((e) => e.state === "new" && e.eventType.id === "fire");
    assert.status(await env.act(primary.guid, "claim", {}, "queue"), 200, null, "взять основной");
    assert.status(await env.call("POST", "/operator/incidents/merge", { incidentGuids: [primary.guid, linked.guid], primaryGuid: primary.guid }), 200, null, "взять в работу одним");
    return { linked: linked.guid, primary: primary.guid };
  };
  const REENTRY_LINKED = {
    merge: {
      name: "истёк срок группы → «Отсоединить» → снова «Взять в работу» одним",
      async run(env, { linked, primary }) {
        assert.status(await env.call("DELETE", `/operator/incidents/${enc(primary)}/linked/${enc(linked)}`), 200, null, "отсоединить");
        assert.status(await env.call("POST", "/operator/incidents/merge", { incidentGuids: [primary, linked], primaryGuid: primary }), 200, null, "снова одним");
      },
    },
  };
  Object.entries(REENTRY_LINKED).forEach(([id, c]) => {
    test(`im-fsm: повторный вход в «Привязан» не даёт нового нарушения: ${c.name}`, async () => {
      const env = await standWith({ workflow: W });
      const pair = await mergeTwo(env);
      const card = await env.card(pair.primary);
      const expired = firedFor(await env.advance(untilDue(env, card)), pair.primary);
      assert.eq(expired, ["resolution_overdue"], "срок группы истёк");
      assert.eq((await env.card(pair.linked)).breaches.filter((b) => b.kind === "resolution").length, 1, "нарушение срока группы — и у привязанного");
      await c.run(env, pair);
      assert.eq((await env.card(pair.linked)).state, "linked", `после «${id}» снова привязан`);
      const fired = await env.advance(60);
      assert.eq(firedFor(fired, pair.linked).concat(firedFor(fired, pair.primary)), [], `после «${id}» ничего не сработало`);
      assert.eq((await env.card(pair.linked)).breaches.filter((b) => b.kind === "resolution").length, 1, "нарушение закрытия одно");
    });
  });

  /* ===== Переходы без смены состояния: один раз на дедлайн ===== */

  const ONCE = {
    escalation_ceiling: { windowSec: 3600, workflow: withEscalation({ maxLevel: 0 }), async setup(env) { return (await env.find((e) => e.state === "new" && e.escalationLevel === 0)).guid; } },
    reaction_overdue: { windowSec: 3600, workflow: withEscalation({ enabled: false }), async setup(env) { return (await env.find((e) => e.state === "new" && e.escalationLevel === 0)).guid; } },
    resolution_overdue: { windowSec: 1500, workflow: W, async setup(env) { const inc = await newFire(env); await env.act(inc.guid, "claim", {}, "queue"); return inc.guid; } },
    resolution_ceiling: {
      windowSec: 1500,
      workflow: withEscalation({ onResolutionOverdue: "escalate", maxLevel: 0 }),
      async setup(env) { const inc = await newFire(env); await env.act(inc.guid, "claim", {}, "queue"); return inc.guid; },
    },
    hold_overdue: {
      windowSec: 3700,
      workflow: W,
      async setup(env) {
        const inc = await newFire(env);
        await env.act(inc.guid, "claim", {}, "queue");
        await env.act(inc.guid, "hold", { reasonId: "third_party", comment: "ждём" });
        return inc.guid;
      },
    },
  };
  Object.entries(ONCE).forEach(([id, c]) => {
    test(`im-fsm: без смены состояния — один раз на дедлайн: ${id}`, async () => {
      const env = await standWith({ workflow: c.workflow });
      const guid = await c.setup(env);
      // Оператор на месте: молчание не вмешивается. Окно — два срока таймера: реакция до 30 минут,
      // закрытие критического пожара — 10, удержание «Ожидание третьей стороны» — 30
      const fired = firedFor(await env.advance(c.windowSec), guid);
      assert.eq(fired.filter((t) => t === id).length, 1, `${id} — один раз: ${fired}`);
    });
  });

  /* ===== Системный переход в окне после дедлайна (§10.1, правило 5; RULE-67) ===== */

  // Окно ждёт только действия человека: если в окне готов системный переход, сначала выполняется
  // переход по таймеру, как без окна, — нарушение на момент дедлайна, потом системный.
  // По одному на каждый таймер и каждый вид системного перехода: выход, перерыв, права адресата
  const logKey = (id) => W.transitions.find((t) => t.id === id).effects.find((e) => e.fn === "appendLog").args[0];
  const signOut = async (env) => assert.status(await env.call("PUT", "/operator/session/agent-state", { agentState: "offline" }), 200, null, "выйти");
  const claimFire = async (env) => {
    const inc = await newFire(env);
    assert.status(await env.act(inc.guid, "claim", {}, "queue"), 200, null, "взять");
    await env.heartbeat(inc.guid);
    return inc.guid;
  };
  const WINDOW = [
    {
      name: "норматив закрытия × оператор вышел: нарушение и алерт, потом в очередь",
      workflow: W,
      setup: claimFire,
      system: signOut,
      order: ["resolution_overdue", "owner_signed_out"],
      end: "new",
      breach: "resolution",
    },
    {
      name: "норматив закрытия с эскалацией × перерыв: эскалация, инцидент не отложен",
      workflow: withEscalation({ onResolutionOverdue: "escalate", levels: levelsTo(["group:grp-leads"]) }),
      setup: claimFire,
      system: async (env) => assert.status(await env.call("PUT", "/operator/session/agent-state", { agentState: "not_ready" }), 200, null, "перерыв"),
      order: ["resolution_escalate"],
      end: "pending_acceptance",
      breach: "resolution",
    },
    {
      name: "срок удержания × оператор вышел: нарушение удержания, потом в очередь",
      workflow: W,
      async setup(env) {
        const guid = await claimFire(env);
        assert.status(await env.act(guid, "hold", { reasonId: "third_party", comment: "ждём" }), 200, null, "отложить");
        return guid;
      },
      system: signOut,
      order: ["hold_overdue", "owner_signed_out"],
      end: "new",
      breach: "hold",
    },
    {
      name: "норматив реакции, эскалировать некому × адресат не может принять: нарушение реакции, потом в очередь",
      workflow: withEscalation({ maxLevel: 0 }),
      async setup(env) {
        const inc = await newFire(env);
        assert.status(await env.act(inc.guid, "transfer", { targetId: "petrova", comment: "тест" }, "queue"), 200, null, "передать Петровой");
        return inc.guid;
      },
      system: async (env) => assert.status(await env.call("PUT", "/test/operators/petrova/roles", { roles: ["Наблюдатель"] }), 200, null, "Петрова не может принять"),
      order: ["escalation_ceiling", "addressee_cannot_accept"],
      end: "new",
      breach: "reaction",
    },
  ];
  WINDOW.forEach((c) => {
    test(`im-fsm: системный переход в окне после дедлайна — нарушение не теряется: ${c.name}`, async () => {
      const env = await standWith({ workflow: c.workflow });
      const guid = await c.setup(env);
      // Идущий таймер: у отложенного — срок удержания, норматив закрытия на паузе
      const before = await env.card(guid);
      const due = Date.parse((before.state === "on_hold" ? before.holdTimer : before.timer).dueAt);
      // Дедлайн прошёл, окно ещё идёт
      const early = firedFor(await env.advance(Math.ceil((due - env.now) / 1000) + 1), guid);
      assert.ok(GRACE > 1, "окно после дедлайна больше секунды");
      assert.eq(early, [], "в окне переход по таймеру ждёт");
      await c.system(env);
      const card = await env.card(guid);
      const keys = card.journal.map((j) => j.templateKey);
      const seen = c.order.map((id) => keys.indexOf(logKey(id)));
      assert.ok(seen.every((i) => i >= 0) && seen.every((i, n) => !n || seen[n - 1] < i), `в журнале по порядку: ${c.order.join(" → ")}`);
      assert.eq(card.state, c.end, "итоговое состояние");
      const breach = card.breaches.find((b) => b.kind === c.breach);
      assert.ok(breach, `нарушение ${c.breach} записано`);
      assert.eq(Date.parse(breach.at), due, "на момент дедлайна");
    });
  });

  /* ===== Ручное действие в окне, после которого таймер продолжается (§10.1, правило 5; RULE-83) ===== */

  // Ручные переходы из continuesOn таймера (check_machine.py --fsm): срабатывание в окне они не отменяют.
  // Действие за секунду до дедлайна и через секунду после — дальше срабатывает одно и то же
  const CONTINUING = {
    transfer: {
      name: "«Передать» нового Сидорову",
      workflow: W,
      async setup(env) {
        const inc = await env.find((e) => e.state === "new" && e.eventType.id === "fire" && e.priority === TOP && e.escalationLevel === 0);
        return inc.guid;
      },
      act: (env, guid) => env.act(guid, "transfer", { targetId: "sidorov", comment: "тест" }, "card"),
    },
    reject: {
      name: "«Отклонить» адресатом уровня 1",
      workflow: withEscalation({ levels: levelsTo([`user:${ME}`]) }),
      async setup(env) {
        const inc = await env.find((e) => e.state === "new" && e.eventType.id === "fire" && e.priority === TOP && e.escalationLevel === 0);
        assert.eq(firedFor(await env.advance(untilDue(env, inc)), inc.guid), ["auto_escalate"], "эскалация на меня");
        return inc.guid;
      },
      act: (env, guid) => env.act(guid, "reject", { comment: "тест" }, "card"),
    },
  };
  Object.entries(CONTINUING).forEach(([id, c]) => {
    test(`im-fsm: ручное действие в окне, после которого таймер продолжается, — дальше то же, что до дедлайна: ${c.name}`, async () => {
      async function run(offsetSec) {
        const env = await standWith({ workflow: c.workflow });
        const guid = await c.setup(env);
        const due = Date.parse((await env.card(guid)).timer.dueAt);
        assert.eq(firedFor(await env.advance(Math.round((due - env.now) / 1000) + offsetSec), guid), [], "до действия ничего не сработало");
        const res = await c.act(env, guid);
        assert.status(res, 200, null, `«${id}» ${offsetSec < 0 ? "до дедлайна" : "в окне"}`);
        assert.eq(res.body.canceledTimerTrigger, null, "срабатывание не отменено");
        const fired = firedFor(await env.advance(3600), guid);
        const card = await env.card(guid);
        return { fired, end: [card.state, card.owner && card.owner.id, card.assignmentGroup && card.assignmentGroup.id, card.escalationLevel, card.breaches.map((b) => b.kind)] };
      }
      const before = await run(-1);
      const inWindow = await run(1);
      assert.ok(before.fired.length > 0, `после действия до дедлайна автоматика работает: ${before.fired}`);
      assert.eq(inWindow, before, "в окне — те же срабатывания и тот же итог");
    });
  });

  /* ===== Покрытие: наборы сценариев перечисляют всё, что есть в машине ===== */

  test("im-fsm: покрытие — у каждого перехода без смены состояния, каждого входа в «В работе» и «Привязан», каждого таймера с нарушением и ручного перехода, после которого таймер продолжается, есть сценарий", async () => {
    const noChange = W.transitions.filter((t) => t.trigger !== "manual" && t.to === null).map((t) => t.id).sort();
    assert.eq(Object.keys(ONCE).sort(), noChange, "переходы без смены состояния — в наборе ONCE");
    const intoWork = W.transitions.filter((t) => t.trigger === "manual" && t.to === "in_progress" && t.id !== "reopen").map((t) => t.id).sort();
    assert.eq(Object.keys(REENTRY).sort(), intoWork, "входы в «В работе» (кроме переоткрытия) — в наборе REENTRY");
    const intoLinked = W.transitions.filter((t) => t.to === "linked").map((t) => t.id).sort();
    assert.eq(Object.keys(REENTRY_LINKED).sort(), intoLinked, "входы в «Привязан» — в наборе REENTRY_LINKED");
    // Таймеры, по которым переход пишет нарушение, — у каждого сценарий системного перехода в окне (RULE-67)
    const breachTimers = [...new Set(W.transitions.filter((t) => t.trigger === "timer" && t.effects.some((e) => e.fn === "recordBreach")).map((t) => t.guards.find((g) => g.fn === "timerExpired").args[0]))].sort();
    const inWindow = [...new Set(WINDOW.map((c) => c.breach))].sort();
    assert.eq(inWindow, breachTimers, "таймеры с нарушением — в наборе WINDOW");
    // Ручные переходы из continuesOn таймера, у которых в исходном состоянии есть переход по нему (RULE-83)
    const byTimer = (timer) => W.transitions.filter((t) => t.trigger === "timer" && t.guards.some((g) => g.fn === "timerExpired" && g.args[0] === timer));
    const continuing = [...new Set(W.timers.flatMap((tm) => (tm.continuesOn || [])
      .map((id) => W.transitions.find((t) => t.id === id))
      .filter((t) => t && t.trigger === "manual" && t.from.some((s) => byTimer(tm.id).some((x) => x.from.includes(s))))
      .map((t) => t.id)))].sort();
    assert.eq(Object.keys(CONTINUING).sort(), continuing, "ручные переходы, после которых таймер продолжается, — в наборе CONTINUING");
  });
})();
