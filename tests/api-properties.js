/* Случайные прогоны с инвариантами. Сотни случайных шагов — действие из тех, что сервер
   показывает в очереди или карточке, сдвиг времени, перерыв, ответы сценария, группа — и
   после каждого шага проверка, что модель цела. Плюс главное свойство API: действие, которое
   сервер показал доступным, выполняется, а недоступное — отклоняется.
   Прогон воспроизводим: зерно (seed) задаёт всю последовательность. Свои зёрна —
   tests/api.html?seeds=1,2,3&steps=200. */
(() => {
  const { test, makeEnv, formFor, fullAnswers, assert, enc } = IMTest;
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
  function invariants(list, session) {
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
      // Закрытые хранят признак группы как историю (RULE-59): группа из одного — только среди открытых
      if (inc.groupGuid && inc.groupSize < 2 && inc.state !== "closed") say(inc, "группа из одного (RULE-52)");
      if (inc.groupGuid && !inc.owner && !inc.assignmentGroup) say(inc, "ничейный в группе (RULE-52)");
      if (!inc.groupGuid && inc.groupSize) say(inc, "не в группе, а размер группы задан");
    });
    // Группа следует за владельцем (RULE-52): у членов один владелец и один адресат
    const groups = new Map();
    list.filter((inc) => inc.groupGuid && inc.state !== "closed").forEach((inc) => groups.set(inc.groupGuid, (groups.get(inc.groupGuid) || []).concat(inc)));
    groups.forEach((members, g) => {
      const keys = new Set(members.map((m) => `${m.owner ? m.owner.id : ""}|${m.assignmentGroup ? m.assignmentGroup.id : ""}`));
      if (keys.size > 1) bad.push(`группа ${g}: у членов разные владельцы или адресаты (RULE-52)`);
    });
    if (session.usage.activeCount > W.limits.maxActive) bad.push(`активных у меня ${session.usage.activeCount} > ${W.limits.maxActive}`);
    return bad;
  }

  async function walk(seed) {
    const r = rng(seed);
    const env = await makeEnv();
    const history = [];
    const versions = new Map();
    const journals = new Map();
    const roles = new Map(FX.people.operators.map((o) => [o.id, o.roles.slice()]));
    let checked = 0;
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
          const answers = r() < 0.5 ? fullAnswers(card) : { [card.scenario.steps[0].id]: true };
          const res = await env.answer(card.guid, answers);
          if (res.status !== 200 && !card.readOnly) fail(step, `ответы сценария отклонены: ${res.status} ${res.body && res.body.message}`);
          history.push(`ответы ${card.guid}`);
        }
      } else if (x < 0.29) {
        const news = (await env.all("open")).filter((e) => e.state === "new");
        const a = pick(r, news);
        const b = a && news.find((e) => e.guid !== a.guid && e.eventType.id === a.eventType.id);
        if (a && b) {
          const res = await env.call("POST", "/operator/incident-groups", { incidentGuids: [a.guid, b.guid] });
          history.push(`группа ${a.guid}+${b.guid}: ${res.status}`);
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
            const empty = (j.templateKey.match(/\{(\w+)\}/g) || []).map((m) => m.slice(1, -1)).filter((k) => k !== "comment" && (j.vars[k] == null || j.vars[k] === ""));
            if (empty.length) fail(step, `«${action.id}»: в записи «${j.templateKey}» пусто: ${empty.join(", ")}`);
          });
          journals.set(card.guid, card.journal.length);
        }
      }
      const [list, session] = await Promise.all([env.all(), env.session()]);
      const bad = invariants(list, session).concat(accessInvariants(list, session, roles));
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
      if (bad.length) fail(step, bad.slice(0, 3).join("; "));
      checked += 1;
    }
    const states = new Set((await env.all()).map((e) => e.state));
    return `${checked} шагов, состояния в конце: ${[...states].join(", ")}`;
  }

  SEEDS.forEach((seed) => {
    test(`Случайный прогон, зерно ${seed}: инварианты и «доступное выполняется, недоступное — нет»`, () => walk(seed));
  });

  test("Инварианты верны на начальных демо-данных", async () => {
    const env = await makeEnv();
    const bad = invariants(await env.all(), await env.session());
    assert.ok(!bad.length, bad.slice(0, 4).join("; "));
  });
})();
