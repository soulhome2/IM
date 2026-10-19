/* Случайные прогоны с инвариантами. Сотни случайных шагов — действие из тех, что сервер
   показывает в очереди или карточке, сдвиг времени, перерыв, ответы сценария, группа — и
   после каждого шага проверка, что модель цела. Плюс главное свойство API: действие, которое
   сервер показал доступным, выполняется, а недоступное — отклоняется.
   Прогон воспроизводим: зерно (seed) задаёт всю последовательность. Свои зёрна —
   tests/api.html?seeds=1,2,3&steps=200. */
(() => {
  const { test, makeEnv, formFor, assert, enc } = IMTest;
  const W = window.IM_WORKFLOW;
  const params = new URLSearchParams(location.search);
  const SEEDS = (params.get("seeds") || "11,23,37,41").split(",").map(Number);
  const STEPS = Number(params.get("steps") || 140);

  // Детерминированный генератор (mulberry32)
  function rng(seed) {
    let a = seed >>> 0;
    return () => {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const pick = (r, list) => list[Math.floor(r() * list.length)];

  // Доступ по эталонному набору (§5, §8.1): устройства ролей — по группам доступа, участники
  // дежурной группы — люди с её ролями плюс названные. Роли тест ведёт сам: он же их и меняет
  const FX = window.IM_FIXTURE;
  const ME = FX.operator;
  const ROLE_SETS = [["Оператор"], ["Оператор ТЦ"], ["Оператор", "Старший оператор"]];
  const groupIndex = {};
  const indexGroups = (groups) => groups.forEach((g) => ((groupIndex[g.id] = g), indexGroups(g.groups || [])));
  indexGroups(FX.sourceGroups);
  const devicesOf = (g) => (g.devices || []).concat(...(g.groups || []).map(devicesOf));
  const devicesFor = (roles) =>
    new Set(FX.accessGroups.filter((a) => a.roles.some((x) => roles.includes(x))).flatMap((a) => a.sourceGroups.flatMap((id) => devicesOf(groupIndex[id])).concat(a.devices)));
  const sourceOf = Object.fromEntries(FX.incidents.map((i) => [i.guid, i.devices[0]]));
  function hasAccess(roles, id, guid) {
    const group = FX.people.dutyGroups.find((g) => g.id === id);
    if (!group) return devicesFor(roles.get(id) || []).has(sourceOf[guid]);
    const members = [...roles.keys()].filter((p) => (roles.get(p) || []).some((x) => (group.roles || []).includes(x))).concat(group.members || []);
    return members.some((m) => hasAccess(roles, m, guid));
  }

  // Доступ после любого шага: видно только доступное мне; у владельца и адресата открытого есть доступ;
  // выйдя из МИ, я не держу ни своих в работе и отложенных, ни адресованных лично мне
  function accessInvariants(list, session, roles) {
    const bad = [];
    const mine = devicesFor(roles.get(ME));
    list.forEach((inc) => {
      if (!mine.has(sourceOf[inc.guid])) bad.push(`${inc.guid}: виден мне, но его объект мне не доступен (§5)`);
      if (inc.state === "closed") return;
      const who = (inc.owner && inc.owner.id) || (inc.assignmentGroup && inc.assignmentGroup.id);
      if (who && !hasAccess(roles, who, inc.guid)) bad.push(`${inc.guid} (${inc.state}): у ${who} нет доступа к объекту (§5)`);
      if (session.agentState === "offline" && ["pending_acceptance", "in_progress", "on_hold"].includes(inc.state) && inc.owner && inc.owner.id === ME) {
        bad.push(`${inc.guid}: я вышел, а он мой — ${inc.state} (§8.1, §12.1)`);
      }
    });
    return bad;
  }

  // Инварианты модели по ответам API — то, что должно быть верно после любого шага
  function invariants(list, session, maxActive) {
    const bad = [];
    const say = (inc, msg) => bad.push(`${inc.guid} (${inc.state}): ${msg}`);
    list.forEach((inc) => {
      if (inc.owner && inc.owner.kind === "duty_group") say(inc, "владелец — группа (RULE-19)");
      if (inc.state === "new" && (inc.owner || inc.assignmentGroup)) say(inc, "у нового есть владелец или группа");
      if (inc.state === "pending_acceptance" && Boolean(inc.owner) === Boolean(inc.assignmentGroup)) say(inc, "адресат должен быть ровно один: человек или группа");
      if ((inc.state === "in_progress" || inc.state === "on_hold") && (!inc.owner || inc.assignmentGroup)) say(inc, "в работе — без владельца-человека или с группой");
      if ((inc.state === "on_hold") !== Boolean(inc.holdReasonId)) say(inc, "причина удержания не совпадает с состоянием");
      if ((inc.state === "closed") !== Boolean(inc.closeResultId)) say(inc, "результат закрытия не совпадает с состоянием");
      const t = inc.timer;
      if (inc.state === "new" || inc.state === "pending_acceptance") {
        // Реакция не идёт только на потолке эскалации: нарушение записано, выше передавать некому (§9)
        const ceiling = inc.escalationLevel >= W.escalation.maxLevel && inc.breaches.some((b) => b.kind === "reaction");
        if ((!t || t.id !== "reaction" || !t.running) && !ceiling) say(inc, `ждёт реакции, а таймер ${JSON.stringify(t && [t.id, t.running])}`);
      }
      if (inc.state === "in_progress" && (!t || t.id !== "resolution" || !t.running)) say(inc, "в работе — норматив закрытия должен идти");
      if (inc.state === "on_hold" && (!t || t.id !== "resolution" || t.running)) say(inc, "отложен — норматив закрытия должен стоять");
      if (inc.state === "closed" && (t || inc.holdTimer)) say(inc, "закрыт — таймеры должны стоять");
      if (inc.holdTimer && inc.state !== "on_hold") say(inc, "срок удержания вне «Отложен»");
      if (inc.slaBreached !== inc.breaches.length > 0) say(inc, "sla_breached не совпадает с записями нарушений");
      if (inc.ownership === "target" && inc.state !== "pending_acceptance") say(inc, "«адресован мне» вне ожидания принятия");
      if (inc.owner && inc.owner.id === session.operator.guid && inc.state !== "pending_acceptance" && inc.state !== "closed" && inc.ownership !== "owner") {
        say(inc, `мой, а отношение «${inc.ownership}»`);
      }
      // Объединение (§11): привязанные в списках не показываются; связь у открытого — только у привязанного
      if (inc.state === "linked") say(inc, "привязанный инцидент в списке");
      if (inc.linkedTo && inc.state !== "closed") say(inc, "открытый со ссылкой на основной");
      // Прогресс сценария в строке очереди (§14.5): отвечено не больше, чем шагов до конца
      const prog = inc.scenarioProgress;
      if (prog && prog.total != null && prog.filled > prog.total) say(inc, `прогресс сценария ${prog.filled} из ${prog.total}`);
    });
    if (maxActive != null && session.usage.activeCount > maxActive) bad.push(`активных у меня ${session.usage.activeCount} > ${maxActive}`);
    return bad;
  }

  // Инварианты прохождения сценария (§14.5, профиль машины сценариев) — по карточке инцидента (PROC-30)
  function scenarioInvariants(card) {
    const bad = [];
    const say = (msg) => bad.push(`${card.guid} (${card.state}): сценарий — ${msg}`);
    const sc = card.scenario;
    const done = Boolean(sc.result.completedAt);
    const last = sc.path[sc.path.length - 1];
    if (sc.requiredStepsFilled.closing !== done) say(`набор «закрытие» ${sc.requiredStepsFilled.closing}, а прохождение ${done ? "завершено" : "не завершено"}`);
    if (done && sc.result.currentStepId !== null) say("у завершённого есть текущий шаг");
    if (!done && sc.result.currentStepId !== last) say(`текущий шаг ${sc.result.currentStepId} — не конец пути ${last}`);
    if (!sc.path.includes(sc.cursorStepId)) say(`курсор показа ${sc.cursorStepId} не на пути`);
    if (sc.progress.total != null && sc.progress.filled > sc.progress.total) say(`прогресс ${sc.progress.filled} из ${sc.progress.total}`);
    if (sc.progress.step !== sc.path.length) say(`номер шага ${sc.progress.step}, а шагов на пути ${sc.path.length}`);
    if ((card.state === "closed" || card.state === "linked") && !card.readOnly) say("закрытый или привязанный можно править");
    return bad;
  }

  // Прохождение по карточке; инцидент, которого оператору не видно (роли сменились, §5), — не проверяется
  async function scenarioOf(env, guid) {
    const res = await env.call("GET", `/operator/incidents/${enc(guid)}`);
    return res.status === 200 ? scenarioInvariants(res.body) : [];
  }

  async function walk(seed) {
    const r = rng(seed);
    // Лимит активных: в машине — без ограничения; каждое второе зерно — с лимитом 1, чтобы проверялся и он
    const maxActive = SEEDS.indexOf(seed) % 2 ? W.limits.maxActive : 1;
    const env = await makeEnv(maxActive === W.limits.maxActive ? undefined : { workflowPatch: { limits: { maxActive } } });
    const history = [];
    const versions = new Map();
    const journals = new Map();
    const roles = new Map(FX.people.operators.map((o) => [o.id, o.roles.slice()]));
    let checked = 0;
    // Инциденты, которых коснулся шаг, — их прохождение проверяется по карточке
    let touched = new Set();
    const fail = (step, msg) => {
      throw new Error(`зерно ${seed}, шаг ${step}: ${msg}. Последние шаги: ${history.slice(-6).join(" → ")}`);
    };
    for (let step = 1; step <= STEPS; step++) {
      const x = r();
      if (x < 0.04) {
        const who = pick(r, FX.people.operators).id;
        const set = pick(r, ROLE_SETS);
        const res = await env.call("PUT", `/test/operators/${enc(who)}/roles`, { roles: set });
        if (res.status !== 200) fail(step, `роли ${who} не сменились: ${res.status}`);
        roles.set(who, set.slice());
        history.push(`роли ${who}: ${set.join("+")}${res.body.fired.length ? ` (${res.body.fired.map((f) => f.transitionId).join(",")})` : ""}`);
      } else if (x < 0.14) {
        const sec = 1 + Math.floor(r() * 900);
        const fired = await env.advance(sec);
        history.push(`+${sec} с${fired.length ? ` (${fired.map((f) => f.transitionId).join(",")})` : ""}`);
      } else if (x < 0.19) {
        const session = await env.session();
        const now = session.agentState === "busy" ? "ready" : session.agentState;
        const to = pick(r, ["ready", "not_ready", "offline"].filter((st) => st !== now));
        await env.ok("PUT", "/operator/session/agent-state", { agentState: to, reasonId: to === "not_ready" ? "lunch" : null });
        history.push(`состояние: ${to}`);
      } else if (x < 0.25) {
        const mine = (await env.all("mine")).filter((e) => e.state === "in_progress");
        if (mine.length) {
          const card = await env.card(pick(r, mine).guid);
          // Пройти сценарий до конца или ответить на текущий шаг — случайным вариантом
          const variant = Math.floor(r() * 3);
          const res = card.scenario.result.completedAt
            ? { status: 200 }
            : r() < 0.5
              ? await env.passScenario(card.guid, variant)
              : await env.answerCurrent(card.guid, variant);
          if (res.status !== undefined && res.status !== 200 && !card.readOnly) fail(step, `ответы сценария отклонены: ${res.status} ${res.body && res.body.message}`);
          history.push(`ответы ${card.guid}`);
          touched.add(card.guid);
        }
      } else if (x < 0.29) {
        // «Объединить» (§11): два-три случайных открытых — отказ или основной со привязанными
        const open = await env.all("open");
        const picked = [...new Set([pick(r, open), pick(r, open), pick(r, open)].filter(Boolean))];
        if (picked.length >= 2) {
          const res = await env.call("POST", "/operator/incidents/merge", { incidentGuids: picked.map((e) => e.guid) });
          if (![200, 403, 422].includes(res.status)) fail(step, `объединение: ${res.status}`);
          history.push(`объединить ${picked.map((e) => e.guid).join("+")}: ${res.status}`);
          picked.forEach((e) => touched.add(e.guid));
        }
      } else {
        const all = await env.all();
        const inc = pick(r, all);
        const surface = r() < 0.5 ? "queue" : "card";
        const view = surface === "card" ? await env.card(inc.guid) : inc;
        const actions = view.actions.filter((a) => a.kind === "transition");
        if (!actions.length) continue;
        const action = pick(r, actions);
        const res = await env.act(inc.guid, action.id, formFor(action), surface, inc.state);
        history.push(`${action.id} ${inc.guid} [${surface}${action.enabled ? "" : ", недоступно"}] → ${res.status}`);
        touched.add(inc.guid);
        // Главное свойство API: доступное выполняется, недоступное отклоняется
        if (action.enabled && res.status !== 200) {
          fail(step, `«${action.id}» показано доступным, а сервер ответил ${res.status} ${res.body && res.body.message}`);
        }
        if (!action.enabled && res.status === 200) fail(step, `«${action.id}» показано недоступным (${action.reason}), а сервер его выполнил`);
        if (res.status === 200) {
          const card = res.body.incident;
          const before = journals.get(card.guid) || 0;
          if (card.journal.length <= before) fail(step, `переход «${action.id}» не записан в журнал ${card.guid}`);
          // В новой записи журнала нет пустых подстановок, кроме комментария (RULE-54)
          card.journal.slice(before).forEach((j) => {
            // Подстановки — по русской строке каталога (§14.9): в самом ключе их нет
            const empty = ((window.IM_STRINGS.ru[j.templateKey] || j.templateKey).match(/\{(\w+)\}/g) || []).map((m) => m.slice(1, -1)).filter((k) => k !== "comment" && (j.vars[k] == null || j.vars[k] === ""));
            if (empty.length) fail(step, `«${action.id}»: в записи «${j.templateKey}» пусто: ${empty.join(", ")}`);
          });
          journals.set(card.guid, card.journal.length);
        }
      }
      const [list, session] = await Promise.all([env.all(), env.session()]);
      const bad = invariants(list, session, maxActive).concat(accessInvariants(list, session, roles));
      list.forEach((inc) => {
        const v = Number(inc.version);
        if (v < (versions.get(inc.guid) || 0)) bad.push(`${inc.guid}: версия уменьшилась`);
        versions.set(inc.guid, v);
      });
      if (step % 20 === 0) {
        const counters = await env.ok("GET", "/operator/incidents/counters");
        for (const f of W.queueFilters) {
          const total = (await env.ok("GET", `/operator/incidents?filter=${f.id}&pageSize=1000`)).total;
          if (total !== counters[f.id]) bad.push(`счётчик «${f.id}» ${counters[f.id]}, а в очереди ${total}`);
        }
      }
      for (const guid of touched) bad.push(...(await scenarioOf(env, guid)));
      touched = new Set();
      if (bad.length) fail(step, bad.slice(0, 3).join("; "));
      checked += 1;
    }
    // В конце — прохождение у всех инцидентов набора, в том числе привязанных и закрытых
    const end = [];
    for (const inc of FX.incidents) end.push(...(await scenarioOf(env, inc.guid)));
    if (end.length) fail(STEPS, end.slice(0, 3).join("; "));
    const states = new Set((await env.all()).map((e) => e.state));
    return `${checked} шагов, состояния в конце: ${[...states].join(", ")}`;
  }

  SEEDS.forEach((seed) => {
    test(`Случайный прогон, зерно ${seed}: инварианты и «доступное выполняется, недоступное — нет»`, () => walk(seed));
  });

  test("Инварианты верны на начальных демо-данных", async () => {
    const env = await makeEnv();
    const bad = invariants(await env.all(), await env.session(), W.limits.maxActive);
    for (const inc of FX.incidents) bad.push(...(await scenarioOf(env, inc.guid)));
    assert.ok(!bad.length, bad.slice(0, 4).join("; "));
  });
})();
