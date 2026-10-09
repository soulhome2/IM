/* Сценарии формальной проверки машины состояний (скилл im-fsm): то, что нельзя проверить чтением
   машины, — как автоматические переходы ведут себя во времени. Названия начинаются с «im-fsm:»,
   по ним скилл находит результаты. Тесты идут против встроенного сервера и против бэкенда: другая
   настройка схемы — изменениями на прогон в POST /test/reset (PROC-13).

   Наборы ниже перечислены по машине: если в ней появится переход без смены состояния или новый
   вход в «В работе», для которого здесь нет сценария, — тест «покрытие» упадёт. */
(() => {
  const { test, makeEnv, assert, enc } = IMTest;
  const ME = "me";
  const W = window.IM_WORKFLOW;

  const changed = (base, copy) =>
    copy ? Object.fromEntries(Object.keys(copy).filter((k) => JSON.stringify(copy[k]) !== JSON.stringify(base[k])).map((k) => [k, copy[k]])) : undefined;
  const standWith = ({ workflow, fixture }) => makeEnv({ workflowPatch: changed(W, workflow), fixturePatch: changed(window.IM_FIXTURE, fixture) });
  // Своя копия машины с изменённой эскалацией
  const withEscalation = (patch) => Object.assign({}, W, { escalation: Object.assign({}, W.escalation, patch) });
  const levelsTo = (refs) => W.escalation.levels.map((l, i) => (refs[i] ? Object.assign({}, l, { targetRef: refs[i] }) : l));
  const newFire = (env) => env.find((e) => e.state === "new" && e.eventType.id === "fire" && e.priority === "critical");
  const firedFor = (fired, guid) => fired.filter((f) => f.incidentGuid === guid).map((f) => f.transitionId);
  // До дедлайна норматива из карточки — плюс секунда
  const untilDue = (env, card) => Math.ceil((Date.parse(card.timer.dueAt) - env.now) / 1000) + 1;

  /* ===== Прыжок часов против шагов (§14.3, RULE-41, RULE-48) ===== */

  // Пары из карты пересечений (check_machine.py --fsm), где оба события наступают по времени или одно
  // открывает дорогу другому. Пары с действием человека (вышел, сменили роли) по времени не совпадают:
  // сервер обрабатывает их в момент действия, при любом шаге планировщика одинаково
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
  ];
  ORDER.forEach((c) => {
    test(`im-fsm: прыжок часов и шаги — один итог: ${c.name}`, async () => {
      async function run(stepSec) {
        const env = await standWith({ workflow: c.workflow });
        const guid = await c.setup(env);
        const fired = [];
        // Без признака активности: молчание оператора идёт, как во время простоя
        for (let left = c.windowSec; left > 0; left -= stepSec) {
          fired.push(...firedFor((await env.call("POST", "/test/clock", { advanceSec: Math.min(stepSec, left) })).body.fired, guid));
        }
        const card = await env.card(guid);
        return { fired, end: [card.state, card.owner && card.owner.id, card.assignmentGroup && card.assignmentGroup.id, card.escalationLevel, card.breaches.map((b) => b.kind)] };
      }
      // Шаг короче любого порога (молчание — 5 минут), но не мельче нужного: итог тот же, вызовов меньше
      const steps = await run(120);
      const jump = await run(c.windowSec);
      assert.eq(steps.fired.slice(0, c.first.length), c.first, "порядок при шагах");
      assert.eq(jump.fired, steps.fired, "прыжок часов — те же переходы в том же порядке");
      assert.eq(jump.end, steps.end, "и тот же итог");
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
      const [first, second] = (await env.call("GET", `/operator/incidents/${enc(inc.guid)}/scenario`)).body.steps.map((s) => s.id);
      assert.status(await env.answer(inc.guid, { [first]: true }), 200, null, "ответ на шаг 1");
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

  /* ===== Покрытие: наборы сценариев перечисляют всё, что есть в машине ===== */

  test("im-fsm: покрытие — у каждого перехода без смены состояния и каждого входа в «В работе» есть сценарий", async () => {
    const noChange = W.transitions.filter((t) => t.trigger !== "manual" && t.to === null).map((t) => t.id).sort();
    assert.eq(Object.keys(ONCE).sort(), noChange, "переходы без смены состояния — в наборе ONCE");
    const intoWork = W.transitions.filter((t) => t.trigger === "manual" && t.to === "in_progress" && t.id !== "reopen").map((t) => t.id).sort();
    assert.eq(Object.keys(REENTRY).sort(), intoWork, "входы в «В работе» (кроме переоткрытия) — в наборе REENTRY");
  });
})();
