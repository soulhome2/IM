/* Встроенный сервер прототипа. Отвечает на запросы ровно по контракту
   Specification/State_machine/openapi.json и хранит всё, что в продукте хранит бэкенд:
   инциденты, журнал, ответы сценария, сессию оператора. Переходы выполняет исполнитель
   машины (engine.js), автоматические — планировщик раз в секунду (§6.2). Интерфейс (app.js)
   разговаривает с ним только через api.js, теми же запросами, что с настоящим бэкендом.
   Работает в той же вкладке: страница открывается и с диска (file://), и с сайта.
   Данные — эталонный набор Specification/State_machine/fixtures/demo.json (prototype/fixture.js):
   его же загружает бэкенд на тестовом стенде. Демо: один оператор, права — весь каталог,
   эмуляция коллег (§17).

   Параметры create(): workflow — машина; fixture — эталонный набор; colleagues — настройки
   эмуляции коллег (colleagues.js) или false; now — часы; autoTick: false — планировщик не
   запускается сам; permissions — права оператора списком ключей (по умолчанию — весь каталог,
   кроме настройки схемы); testSupport: true — служебные операции тестового стенда
   /test/reset и /test/clock (README машины, «Тестовый стенд»). */
(() => {
  function create(opts) {
    const W = opts.workflow;
    const FIXTURE = opts.fixture;
    const ME = FIXTURE.operator;
    const iso = (ms) => (ms == null ? null : new Date(ms).toISOString());

    // Часы. Тестовый стенд их останавливает и сдвигает (/test/clock), иначе идут вместе с настоящими
    const realNow = opts.now || (() => Date.now());
    const clock = { frozenAt: null, offset: 0 };
    const now = () => (clock.frozenAt != null ? clock.frozenAt : realNow() + clock.offset);
    // Имена заголовков в HTTP не зависят от регистра: внутри — строчными
    const lowerKeys = (headers) => Object.fromEntries(Object.entries(headers || {}).map(([k, v]) => [k.toLowerCase(), String(v)]));

    /* ===== Данные: загружаются из эталонного набора (load) ===== */

    let OPERATORS = [];
    let GROUPS = [];
    let ACTORS = [];
    let DEVICE_TYPES = {};
    let DEVICE_CATALOG = {};
    let PLANS = [];
    let TREE = [];
    let SCENARIOS = {};
    // Группы доступа (§5): какие устройства доступны ролям. Роли оператора стенда — из набора
    // или из /test/reset (operatorRoles); видимые ему устройства считаются один раз при загрузке
    let ACCESS_GROUPS = [];
    // Роли и их права — как их отдаёт основная система (§5): по ним известны права всех людей
    let ROLE_RIGHTS = {};
    let rolesOverride = null;
    let myDevices = new Set();
    // Идентификаторы, которые сервер создаёт сам, — UUID (контракт): первая цифра — вид
    // (7 — запись журнала, 8 — группа обработки, 9 — запуск макроса), дальше — номер
    const uuid = (kind, n, tail) => `${kind}${String(n).padStart(7, "0")}-0000-4000-8000-${tail || "000000000000"}`;
    const serial = { group: 0, macro: 0 };
    let events = [];
    let SIM = { enabled: false };
    let session = null;
    // Эмулированные коллеги: исполнитель каждого и с какого момента его сессия не отвечает
    const colleagueEngines = {};
    const colleagueIdleSince = {};
    const PAGE_SIZE = 8;

    /* ===== Люди и права ===== */

    const findActor = (id) => ACTORS.find((a) => a.id === id) || null;
    const rawName = (id) => {
      const actor = findActor(id);
      return actor ? actor.name : "Не назначен";
    };
    const actorKind = (actor) =>
      actor.group ? "duty_group" : actor.id === "dispatcher" ? "dispatcher" : actor.system ? "system" : "operator";
    function actorRef(id, fallbackName) {
      if (!id) return fallbackName ? { id: null, kind: "system", name: fallbackName, role: "система" } : null;
      const actor = findActor(id);
      if (!actor) return { id, kind: "operator", name: id, role: "" };
      return { id: actor.id, kind: actorKind(actor), name: actor.name, role: actor.role };
    }

    // Права демо-оператора: весь каталог машины, кроме настройки схемы. В продукте права
    // приходят из внешней системы (§5), здесь — один набор на всех (§17)
    const ALL_PERMISSIONS = W.permissions.map((p) => p.key).filter((key) => key !== "incident:schema:admin");
    let PERMISSIONS = opts.permissions || ALL_PERMISSIONS;
    const can = (key) => PERMISSIONS.includes(key);

    /* ===== Устройства и группы ===== */

    const deviceSpec = (id) => DEVICE_CATALOG[id] || { name: id, type: "camera" };
    function deviceRef(id) {
      const spec = deviceSpec(id);
      const type = DEVICE_TYPES[spec.type] ? spec.type : "camera";
      return { guid: id, name: spec.name, typeId: type, typeLabel: DEVICE_TYPES[type].label };
    }
    function findNode(nodes, id) {
      for (const node of nodes) {
        if (node.id === id) return node;
        const found = node.children ? findNode(node.children, id) : null;
        if (found) return found;
      }
      return null;
    }
    function collectDeviceIds(node) {
      if (!node) return [];
      if (node.isDevice) return [node.id];
      return [...new Set((node.children || []).flatMap(collectDeviceIds))];
    }
    const eventSource = (ev) => (ev.deviceIds && ev.deviceIds[0]) || (ev.cameras && ev.cameras[0]) || null;

    // Устройства, доступные ролям, — по группам доступа (§5): группы устройств с вложенными и
    // отдельные устройства. Инцидент виден, если доступно его устройство-источник
    function accessibleDevices(roles) {
      const out = new Set();
      ACCESS_GROUPS.filter((a) => a.roles.some((r) => roles.includes(r))).forEach((a) => {
        (a.sourceGroups || []).forEach((gid) => {
          const node = findNode(TREE, gid);
          if (node) collectDeviceIds(node).forEach((id) => out.add(id));
        });
        (a.devices || []).forEach((id) => out.add(id));
      });
      return out;
    }
    const canSee = (ev) => myDevices.has(eventSource(ev));
    // Состав дежурной группы (§8.1): все, у кого есть одна из её ролей, плюс отдельные люди.
    // Считается на лету — роли меняются; порядок групп — порядок в наборе
    const rolesOf = (id) => (id === ME && rolesOverride ? rolesOverride : (OPERATORS.find((o) => o.id === id) || {}).roles || []);
    const membersOf = (group) => {
      const byRole = OPERATORS.filter((o) => rolesOf(o.id).some((r) => (group.roles || []).includes(r))).map((o) => o.id);
      return [...new Set(byRole.concat(group.members || []))];
    };
    // Доступ адресата к объекту инцидента (§8.1): человеку — по его ролям, группе — хотя бы
    // одному участнику
    function hasAccess(id, ev) {
      const group = GROUPS.find((g) => g.id === id);
      if (group) return membersOf(group).some((m) => hasAccess(m, ev));
      if (id === ME) return canSee(ev);
      const person = OPERATORS.find((o) => o.id === id);
      return Boolean(person) && accessibleDevices(person.roles || []).has(eventSource(ev));
    }
    // Права человека: у оператора стенда — его набор, у остальных — объединение прав его ролей
    const permsOf = (id) => (id === ME ? PERMISSIONS : [...new Set(rolesOf(id).flatMap((r) => ROLE_RIGHTS[r] || []))]);
    // Может ли адресат принять (§8.1): право «Принимать» и доступ к объекту; группа — если хотя бы
    // один участник может
    function canAccept(id, ev) {
      const group = GROUPS.find((g) => g.id === id);
      if (group) return membersOf(group).some((m) => canAccept(m, ev));
      return permsOf(id).includes("incident:accept") && hasAccess(id, ev);
    }
    // Группа устройства-источника: самая глубокая, где оно стоит (первое вхождение по дереву)
    function sourceGroupOf(ev) {
      const src = eventSource(ev);
      const walk = (nodes) => {
        for (const node of nodes) {
          if (node.isDevice) continue;
          const deeper = walk(node.children || []);
          if (deeper) return deeper;
          if ((node.children || []).some((c) => c.isDevice && c.id === src)) return { guid: node.id, name: node.name };
        }
        return null;
      };
      return walk(TREE);
    }
    const touches = (ev, ids) => (ev.deviceIds || []).some((id) => ids.includes(id));

    /* ===== Сценарий (до подключения машины сценариев, §14.5, §17) ===== */

    const scenarioOf = (ev) => SCENARIOS[ev.typeId];
    const scenarioSteps = (ev) => scenarioOf(ev).steps;
    const stepShort = (step) => (step.type === "checkbox" ? "Подтверждение" : step.label);
    function stepAnswerText(ev, step) {
      if (step.type === "checkbox") return ev.answers[step.id] ? "Да" : "";
      if (step.type === "macros") return ev.launched.length ? `${ev.launched.length} макрос` : "";
      return ev.answers[step.id] || "";
    }
    function isStepValid(ev, step) {
      if (!step.required) return true;
      if (step.type === "checkbox") return ev.answers[step.id] === true;
      if (step.type === "macros") return true;
      return Boolean(ev.answers[step.id]);
    }
    const scenarioDone = (ev) => scenarioSteps(ev).every((s) => isStepValid(ev, s));
    function firstOpenStep(ev) {
      const steps = scenarioSteps(ev);
      const blocked = steps.findIndex((s) => s.required && !isStepValid(ev, s));
      if (blocked !== -1) return blocked;
      const empty = steps.findIndex((s) => !stepAnswerText(ev, s));
      return empty === -1 ? steps.length - 1 : empty;
    }
    const canOpenStep = (ev, index) =>
      index >= 0 && index < scenarioSteps(ev).length && scenarioSteps(ev).slice(0, index).every((s) => isStepValid(ev, s));
    function cursorOf(ev) {
      if (typeof ev.stepIndex !== "number" || !canOpenStep(ev, ev.stepIndex)) ev.stepIndex = firstOpenStep(ev);
      return ev.stepIndex;
    }
    function stepProgress(ev) {
      const steps = scenarioSteps(ev);
      return { filled: steps.filter((s) => Boolean(stepAnswerText(ev, s))).length, total: steps.length };
    }

    /* ===== Журнал ===== */

    function log(ev, whoId, template, vars) {
      ev.log.push({ at: now(), whoId, k: template, v: vars || null });
    }

    // Всё, что исполнитель знает о данных сервера. «Я» (me) у каждого исполнителя своё: у оператора
    // стенда — он сам, у эмулированных коллег — коллега (их действия идут через те же переходы)
    const engineCtx = {
      workflow: W,
      me: ME,
      now,
      events: () => events,
      can,
      isGroup: (id) => GROUPS.some((g) => g.id === id),
      // Дежурная группа человека (§8.1): первая, в которую он входит
      dutyGroupOf: (userId) => (GROUPS.find((g) => membersOf(g).includes(userId)) || {}).id || null,
      memberOf: (groupId, userId) => {
        const group = GROUPS.find((g) => g.id === groupId);
        return Boolean(group && membersOf(group).includes(userId));
      },
      inGroup: (ev, groupId) => touches(ev, collectDeviceIds(findNode(TREE, groupId))),
      agentState: () => session.agentState,
      stepsFilled: (ev, setId) => setId === "none" || scenarioDone(ev),
      progress: (ev) => stepProgress(ev),
      stepNumber: (ev) => cursorOf(ev) + 1,
      setCursor: (ev) => {
        ev.stepIndex = firstOpenStep(ev);
      },
      actorName: (id) => rawName(id),
      log,
      transferTargets: () => targets(),
      hasAccess: (id, ev) => hasAccess(id, ev),
      canAccept: (id, ev) => canAccept(id, ev),
      defaultTransferTarget: () => session.preferences.defaultTransferTargetId,
      // У членов группы ответы общие (grouping.shared): один объект ответов на всех
      shareAnswers: (ev, first) => {
        ev.answers = first.answers;
      },
      detachAnswers: (ev) => {
        ev.answers = JSON.parse(JSON.stringify(ev.answers));
      },
      onEvict: (ev, who, transitionId) => {
        if (who === ME) emit("incident.card_evicted", ev, null, { transitionId });
      },
    };
    // Молчание оператора стенда (§12.3) — с последнего признака активности (heartbeat)
    let lastHeartbeat = null;
    const engine = IMEngine.create(
      Object.assign({}, engineCtx, { me: ME, idleSec: () => (lastHeartbeat == null ? 0 : (now() - lastHeartbeat) / 1000) })
    );

    // Эталонный набор → модель сервера. Набор — снимок на момент capturedAt: при загрузке все
    // времена сдвигаются на «сейчас − capturedAt», и набор выглядит свежим в любой день
    function load(fixture) {
      // Сброс — вход оператора: молчание считается с этого момента
      lastHeartbeat = now();
      serial.group = 0;
      serial.macro = 0;
      const data = JSON.parse(JSON.stringify(fixture));
      const delta = now() - Date.parse(data.capturedAt);
      const abs = (time) => (time == null ? null : Date.parse(time) + delta);
      OPERATORS = data.people.operators;
      GROUPS = data.people.dutyGroups.map((g) => Object.assign({ group: true }, g));
      ACTORS = OPERATORS.concat(GROUPS, data.people.system.map((a) => Object.assign({ system: true }, a)));
      DEVICE_TYPES = Object.fromEntries(data.deviceTypes.map((t) => [t.id, { label: t.label }]));
      DEVICE_CATALOG = Object.fromEntries(
        data.devices.map((d) => [d.id, { name: d.name, type: d.type, position: d.position || null, thumbnailUrl: d.thumbnailUrl || null }])
      );
      PLANS = data.plans || [];
      ACCESS_GROUPS = data.accessGroups || [];
      ROLE_RIGHTS = Object.fromEntries((data.roles || []).map((r) => [r.name, r.permissions]));
      const tree = (groups) =>
        groups.map((g) =>
          Object.assign({ id: g.id, name: g.name }, g.description ? { description: g.description } : {}, {
            children: tree(g.groups || []).concat((g.devices || []).map((id) => ({ id, isDevice: true }))),
          })
        );
      TREE = tree(data.sourceGroups);
      const me = data.people.operators.find((o) => o.id === ME) || {};
      myDevices = accessibleDevices(rolesOverride || me.roles || []);
      SCENARIOS = data.scenarios;
      events = data.incidents.map((inc) => ({
        id: inc.guid,
        number: inc.number,
        typeId: inc.eventType.id,
        typeGuid: inc.eventType.guid,
        type: inc.eventType.name,
        priority: inc.priority,
        site: inc.site,
        siteType: inc.siteType,
        location: inc.location,
        occurredAt: abs(inc.occurredAt),
        deviceIds: inc.devices,
        cameras: inc.cameras,
        media: inc.media,
        state: inc.state,
        owner: inc.owner,
        assignmentGroup: inc.assignmentGroup,
        escalationLevel: inc.escalationLevel,
        holdReason: inc.holdReason,
        closeResult: inc.closeResult,
        massCause: inc.closeCause,
        closeComment: inc.result,
        closedBy: inc.closedBy,
        closedAt: abs(inc.closedAt),
        reactionDueAt: null,
        resolutionDueAt: null,
        resolutionLeftMs: null,
        holdSince: null,
        holdDueAt: null,
        timers: inc.timers,
        slaBreached: inc.slaBreached,
        breaches: (inc.breaches || []).map((b) => ({ kind: b.kind, at: abs(b.at), owner: b.owner || null })),
        groupId: null,
        answers: inc.scenario.answers,
        launched: inc.scenario.launchedMacros,
        log: inc.journal.map((j) => ({ at: abs(j.at), whoId: j.actor, who: j.actorName, k: j.template, v: j.vars })),
        // Шаг, на котором остановился владелец; нет — первый незаполненный
        stepIndex: inc.scenario.cursorStepId ? SCENARIOS[inc.eventType.id].steps.findIndex((s) => s.id === inc.scenario.cursorStepId) : undefined,
        version: 1,
      }));
      // Таймеры: в наборе — с какого момента идут, длительность — норматив машины (§4).
      // Запуск в прошлом сдвигает дедлайн: «удержание началось 4 минуты назад»
      const shift = (ev, due, since, startedAt) => {
        const ms = abs(startedAt) - now();
        if (ev[due] != null) ev[due] += ms;
        if (since && ev[since] != null) ev[since] += ms;
      };
      events.forEach((ev) => {
        const t = ev.timers || {};
        delete ev.timers;
        if (t.reaction) {
          engine.startTimer(ev, "reaction", ev.escalationLevel > 0 ? "byEscalationLevel" : undefined);
          shift(ev, "reactionDueAt", null, t.reaction.startedAt);
        }
        if (t.resolution && t.resolution.leftSec != null) ev.resolutionLeftMs = t.resolution.leftSec * 1000;
        else if (t.resolution) {
          engine.resumeTimer(ev, "resolution");
          shift(ev, "resolutionDueAt", null, t.resolution.startedAt);
        }
        if (t.hold) {
          engine.startTimer(ev, "hold");
          shift(ev, "holdDueAt", "holdSince", t.hold.startedAt);
        }
      });
      session = {
        agentState: "ready",
        reasonId: null,
        openIncidentGuid: null,
        preferences: JSON.parse(JSON.stringify(fixture.operatorPreferences || {})),
      };
      SIM = opts.colleagues ? JSON.parse(JSON.stringify(opts.colleagues.SIM)) : { enabled: false };
      Object.keys(colleagueIdleSince).forEach((id) => delete colleagueIdleSince[id]);
    }

    load(FIXTURE);

    /* ===== Ответы API: представление для смотрящего оператора ===== */

    // Подстановка [шаблон, переменные] → русский текст. Клиент получает и шаблон, и переменные,
    // чтобы перевести их на язык интерфейса
    function render(template, vars) {
      const value = (v) => (Array.isArray(v) ? render(v[0], v[1]) : v);
      return String(template || "").replace(/\{(\w+)\}/g, (m, key) => (vars && key in vars ? String(value(vars[key])) : m));
    }
    const say = (why) => (why ? { text: render(why[0], why[1]), key: why[0], vars: why[1] || {} } : null);

    const STATES = Object.fromEntries(W.states.map((s) => [s.id, s]));
    const isDone = (ev) => STATES[ev.state].category === "done";

    function timerState(ev) {
      if (isDone(ev)) return null;
      const base = { serverTime: iso(now()) };
      if (ev.reactionDueAt) {
        return Object.assign(base, { id: "reaction", label: "Реакция", dueAt: iso(ev.reactionDueAt), remainingMs: ev.reactionDueAt - now(), running: true });
      }
      if (ev.resolutionDueAt) {
        return Object.assign(base, { id: "resolution", label: "Закрытие", dueAt: iso(ev.resolutionDueAt), remainingMs: ev.resolutionDueAt - now(), running: true });
      }
      if (ev.resolutionLeftMs != null) {
        return Object.assign(base, { id: "resolution", label: "Закрытие", dueAt: null, remainingMs: ev.resolutionLeftMs, running: false });
      }
      return null;
    }
    function holdTimerState(ev) {
      if (ev.state !== "on_hold" || !ev.holdDueAt) return null;
      return { id: "hold", label: "Удержание", dueAt: iso(ev.holdDueAt), remainingMs: ev.holdDueAt - now(), running: true, serverTime: iso(now()) };
    }

    const groupMates = (ev) => (ev.groupId ? events.filter((e) => e.groupId === ev.groupId) : [ev]);

    // Варианты полей формы перехода для этого инцидента и значения по умолчанию (form машины)
    function formView(tr, ev, surface) {
      if (!tr || !tr.form) return {};
      const f = engine.form(tr.form, ev, { surface, noteVars: { groupSize: groupMates(ev).length } });
      const fieldOptions = {};
      f.fields.forEach((field) => {
        if (!field.options) return;
        fieldOptions[field.name] = {
          options: field.options.map((o) => {
            const reason = o.why ? say([o.why]) : null;
            return Object.assign(
              { id: o.id, label: o.label, disabled: Boolean(o.disabled), reason: reason ? reason.text : null },
              o.role != null ? { role: o.role, available: o.available !== false, availabilityLabel: o.availabilityLabel || null } : {}
            );
          }),
          defaultValue: field.defaultValue || null,
        };
      });
      const note = say(f.note);
      return { fieldOptions, formNote: note ? { text: note.text, key: note.key, vars: note.vars } : null };
    }

    function actionsFor(ev, surface) {
      return engine.actions(ev, surface).map((a) => {
        const tr = engine.transition(a.id);
        const why = !a.enabled && Array.isArray(a.hint) ? say(a.hint) : null;
        return Object.assign(
          {
            id: a.id,
            kind: a.kind,
            label: a.label,
            style: a.style,
            visible: true,
            enabled: a.enabled,
            reason: why ? why.text : null,
            reasonKey: why ? why.key : null,
            reasonVars: why ? why.vars : null,
            formId: a.formId || null,
            hotkey: a.hotkey || null,
            navigate: a.navigate || null,
            bulkAllowed: Boolean(tr && tr.bulk && tr.bulk.allowed),
          },
          a.enabled ? formView(tr, ev, surface) : {}
        );
      });
    }

    function badgeView(ev) {
      const b = engine.badge(ev);
      return { label: render(b.label[0], b.label[1]), style: b.style, template: b.label[0], vars: b.label[1] || {} };
    }

    function summary(ev, surface) {
      const src = eventSource(ev);
      return {
        guid: ev.id,
        number: ev.number,
        occurredAt: iso(ev.occurredAt),
        eventType: { guid: ev.typeGuid, id: ev.typeId, name: ev.type },
        priority: ev.priority,
        sourceGroup: sourceGroupOf(ev),
        sourceDeviceTypeId: src ? deviceRef(src).typeId : null,
        site: ev.site || null,
        siteType: ev.siteType || null,
        location: ev.location || null,
        state: ev.state,
        stateCategory: STATES[ev.state].category,
        ownership: engine.ownership(ev),
        owner: actorRef(ev.owner),
        assignmentGroup: actorRef(ev.assignmentGroup),
        badge: badgeView(ev),
        escalationLevel: ev.escalationLevel,
        holdReasonId: ev.holdReason,
        closeResultId: ev.closeResult,
        closeCauseId: ev.massCause,
        closeResultLabel: ev.closeResult ? engine.closeResultLabel(ev) : null,
        closedAt: iso(ev.closedAt),
        timer: timerState(ev),
        holdTimer: holdTimerState(ev),
        slaBreached: Boolean(ev.slaBreached),
        breaches: (ev.breaches || []).map((b) => ({ kind: b.kind, at: iso(b.at), owner: actorRef(b.owner) })),
        groupGuid: ev.groupId || null,
        groupSize: ev.groupId ? groupMates(ev).length : 0,
        scenarioProgress: stepProgress(ev),
        mediaKinds: ev.media === "video" ? ["video"] : ev.media === "map" ? ["map"] : ["video", "map"],
        schemaVersion: 4,
        version: String(ev.version),
        actions: actionsFor(ev, surface || "queue"),
      };
    }

    const STEP_TYPE = { checkbox: "Checkbox", radio: "RadioButton", combo: "Select", edit: "Comment", macros: "Macros" };
    function scenarioView(ev) {
      const sc = scenarioOf(ev);
      const steps = sc.steps;
      return {
        scenarioGuid: sc.guid,
        scenarioVersion: 1,
        title: sc.title,
        steps: steps.map((s) => ({
          id: s.id,
          type: STEP_TYPE[s.type],
          title: s.label,
          description: "",
          requiredFor: s.required ? ["closing"] : [],
          view: { short: stepShort(s), options: s.options || null, placeholder: s.placeholder || null, buttons: s.buttons || null },
        })),
        answers: JSON.parse(JSON.stringify(ev.answers)),
        launchedMacros: ev.launched.slice(),
        cursorStepId: steps[cursorOf(ev)].id,
        progress: stepProgress(ev),
        requiredStepsFilled: { closing: scenarioDone(ev) },
      };
    }

    function journalView(ev) {
      return ev.log.map((entry, i) => ({
        guid: uuid(7, i, ev.id.slice(-12)),
        at: iso(entry.at),
        actor: actorRef(entry.whoId, entry.who),
        kind: entry.kind || (entry.whoId === "dispatcher" || entry.whoId === "system" || (!entry.whoId && entry.who) ? "system" : "transition"),
        templateKey: entry.k,
        vars: entry.v || {},
        text: render(entry.k, entry.v),
      }));
    }

    function groupView(ev) {
      if (!ev.groupId) return null;
      const mates = groupMates(ev);
      const block = say(engine.excludeBlock(ev));
      return {
        guid: ev.groupId,
        createdAt: iso(ev.groupCreatedAt || now()),
        owner: actorRef(ev.owner),
        eventType: { guid: ev.typeGuid, id: ev.typeId, name: ev.type },
        members: mates.map((m) => summary(m, "card")),
        sharedAnswers: JSON.parse(JSON.stringify(ev.answers)),
        exclude: {
          enabled: engine.canExcludeFromGroup(ev),
          reason: block ? block.text : null,
          reasonKey: block ? block.key : null,
          reasonVars: block ? block.vars : null,
        },
      };
    }

    function card(ev) {
      const src = eventSource(ev);
      const deviceIds = [...new Set([...(ev.deviceIds || []), ...(ev.cameras || [])])];
      return Object.assign(summary(ev, "card"), {
        description: null,
        readOnly: !engine.canEditScenario(ev),
        source: src ? deviceRef(src) : null,
        devices: deviceIds.filter((id) => myDevices.has(id)).map(deviceRef),
        scenario: scenarioView(ev),
        journal: journalView(ev),
        media: mediaView(ev),
        group: groupView(ev),
        result: ev.closeComment || null,
      });
    }

    // План инцидента: тот, где стоит источник или первое устройство события с положением,
    // иначе план площадки
    function planOf(ev) {
      const ids = [eventSource(ev), ...(ev.deviceIds || []), ...(ev.cameras || [])].filter(Boolean);
      const placed = ids.map((id) => deviceSpec(id).position).find(Boolean);
      return PLANS.find((p) => (placed ? p.id === placed.plan : p.site === ev.site)) || null;
    }

    function mediaView(ev) {
      const src = eventSource(ev);
      const plan = planOf(ev);
      const ids = [...new Set([...(ev.deviceIds || []), ...(ev.cameras || [])])].filter((id) => myDevices.has(id));
      return {
        cameras: (ev.cameras || []).filter((id) => myDevices.has(id)).map((id) => ({
          guid: id,
          name: deviceSpec(id).name,
          isSource: id === src,
          archiveUrl: null,
          liveUrl: null,
          archiveStartAt: iso(ev.occurredAt),
          thumbnailUrl: deviceSpec(id).thumbnailUrl,
        })),
        // Значки на плане — устройства и камеры инцидента, у которых есть положение на этом плане
        map: plan && {
          planGuid: plan.id,
          planName: plan.name,
          imageUrl: plan.imageUrl,
          markers: ids
            .filter((id) => (deviceSpec(id).position || {}).plan === plan.id)
            .map((id) => ({ deviceGuid: id, x: deviceSpec(id).position.x, y: deviceSpec(id).position.y, isSource: id === src })),
        },
      };
    }

    function usage() {
      const active = engine.units("in_progress");
      const held = engine.units("on_hold");
      const blocking = events.find((e) => e.state === "in_progress" && e.owner === ME);
      return { activeCount: active.size, onHoldCount: held.size, blockingIncidentGuid: blocking ? blocking.id : null };
    }

    function shiftView() {
      const at = (h) => {
        const d = new Date(now());
        d.setHours(h, 0, 0, 0);
        return iso(d.getTime());
      };
      return { from: at(8), to: at(20) };
    }

    function sessionView() {
      const me = findActor(ME);
      return {
        operator: {
          guid: ME,
          name: me.name,
          role: me.role,
          dutyGroupGuids: GROUPS.filter((g) => membersOf(g).includes(ME)).map((g) => g.id),
        },
        shift: shiftView(),
        agentState: session.agentState === "not_ready" || session.agentState === "offline" ? session.agentState : usage().activeCount ? "busy" : "ready",
        agentStateReasonId: session.reasonId,
        permissions: PERMISSIONS.slice(),
        limits: Object.fromEntries(Object.entries(W.limits).filter(([key]) => !key.startsWith("$"))),
        usage: usage(),
        preferences: JSON.parse(JSON.stringify(session.preferences)),
        workflowSchemaVersion: 4,
        permissionIssues: [],
      };
    }

    // Состояние человека (§12.1): у оператора стенда — из сессии, у остальных — из набора.
    // На смене — «На смене» или «Занят»; дежурная группа — если на смене хотя бы один участник (§8.1)
    const agentStateOf = (id) => (id === ME ? session.agentState : (OPERATORS.find((o) => o.id === id) || {}).agentState || "offline");
    const onShift = (op) => (op.group ? membersOf(op).some((m) => onShift({ id: m })) : !["not_ready", "offline"].includes(agentStateOf(op.id)));
    const stateLabel = (id) => (W.session.states.find((st) => st.id === agentStateOf(id)) || {}).label || null;

    // Адресаты передачи. Себя и своих групп в списке нет (§8.1, §10.1)
    function targets() {
      return OPERATORS.concat(GROUPS).map((op) => ({
        id: op.id,
        kind: op.group ? "duty_group" : "operator",
        name: op.name,
        label: op.name,
        role: op.group ? "группа" : op.role,
        available: onShift(op),
        availabilityLabel: onShift(op) ? null : op.group ? "никого нет на смене" : stateLabel(op.id),
        memberIds: op.group ? membersOf(op) : [],
      }));
    }

    /* ===== Очередь: фильтр, группа, типы, поиск, страница ===== */

    function visible(q) {
      let list = events.filter(canSee);
      if (q.sourceGroupGuid && q.sourceGroupGuid !== "all") {
        const node = findNode(TREE, q.sourceGroupGuid);
        const ids = node ? collectDeviceIds(node) : [q.sourceGroupGuid];
        list = list.filter((e) => touches(e, ids));
      }
      return list.filter((e) => {
        if (q.filter && !engine.inQueueFilter(e, q.filter)) return false;
        if (q.eventTypeGuid && q.eventTypeGuid !== "all" && e.typeGuid !== q.eventTypeGuid) return false;
        if (q.deviceTypeId && q.deviceTypeId !== "all") {
          const src = eventSource(e);
          if (!src || deviceSpec(src).type !== q.deviceTypeId) return false;
        }
        if (q.search) {
          const needle = String(q.search).toLowerCase();
          if (!`${e.number} ${e.type} ${e.site} ${e.location}`.toLowerCase().includes(needle)) return false;
        }
        return true;
      });
    }

    function page(q) {
      const list = visible(q);
      const size = Math.max(1, Number(q.pageSize) || PAGE_SIZE);
      const pages = Math.max(1, Math.ceil(list.length / size));
      const n = Math.min(Math.max(1, Number(q.page) || 1), pages);
      // На какой странице выбранный инцидент — если он виден при этих фильтрах (null — не виден)
      const idx = q.focusGuid ? list.findIndex((e) => e.id === q.focusGuid) : -1;
      const focusPage = idx === -1 ? null : Math.floor(idx / size) + 1;
      return { items: list.slice((n - 1) * size, n * size).map((e) => summary(e, "queue")), total: list.length, page: n, pageSize: size, focusPage };
    }

    function counters() {
      const out = {};
      W.queueFilters.forEach((f) => (out[f.id] = events.filter((e) => canSee(e) && engine.inQueueFilter(e, f.id)).length));
      return out;
    }

    // Дерево групп — только группы, где есть доступные оператору устройства, и только они (§5)
    function treeView(nodes) {
      return nodes
        .filter((n) => !n.isDevice && collectDeviceIds(n).some((id) => myDevices.has(id)))
        .map((n) => {
          const ids = collectDeviceIds(n);
          const open = events.filter((e) => canSee(e) && !isDone(e) && touches(e, ids));
          const devices = (n.children || [])
            .filter((c) => c.isDevice && myDevices.has(c.id))
            .map((c) => {
              const evs = events.filter((e) => canSee(e) && !isDone(e) && touches(e, [c.id]));
              return Object.assign(deviceRef(c.id), { counters: { open: evs.length, critical: evs.filter((e) => e.priority === "critical").length } });
            });
          return {
            guid: n.id,
            name: n.name,
            description: n.description || null,
            children: treeView(n.children || []),
            devices,
            counters: { open: open.length, critical: open.filter((e) => e.priority === "critical").length },
          };
        });
    }

    function eventTypes() {
      const seen = new Map();
      events.forEach((e) => {
        if (!seen.has(e.typeId)) seen.set(e.typeId, { guid: e.typeGuid, id: e.typeId, name: e.type, defaultReactionSec: engine.norm({ typeId: e.typeId, priority: "medium" }, "reaction") });
      });
      return [...seen.values()];
    }

    /* ===== Поток серверных событий (§9: поток вместо опроса) ===== */

    const listeners = new Set();
    let seq = 0;
    function emit(type, ev, actorId, payload) {
      // Об инциденте вне групп доступа оператор не узнаёт и из потока (§5)
      if (ev && !canSee(ev)) return;
      const message = {
        id: String(++seq),
        type,
        at: iso(now()),
        incidentGuid: ev ? ev.id : null,
        actor: actorRef(actorId),
        incident: ev ? summary(ev, "queue") : null,
        payload: payload || {},
      };
      record("GET", "/operator/stream", 200, message, "stream");
      listeners.forEach((fn) => setTimeout(() => fn(JSON.parse(JSON.stringify(message))), 0));
    }
    function subscribe(fn) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    }

    /* ===== Ошибки по контракту (Problem) ===== */

    function problem(status, code, why, extra) {
      const s = say(why) || { text: code, key: code, vars: {} };
      return { status, body: Object.assign({ code, message: s.text, messageKey: s.key, messageVars: s.vars }, extra || {}) };
    }

    // Невыполненное условие → код ошибки по контракту: не из этого состояния — 409,
    // нет права или не выполнено условие — 403 с машинным кодом и именем условия
    const GUARD_CODE = {
      hasPermission: "PERMISSION_DENIED",
      hasScopedPermission: "PERMISSION_DENIED",
      withinActiveLimit: "LIMIT_EXCEEDED",
      withinHoldLimit: "LIMIT_EXCEEDED",
      agentReady: "AGENT_NOT_READY",
      targetIsNotSelf: "TRANSFER_TO_SELF_FORBIDDEN",
      targetHasAccess: "TARGET_NO_ACCESS",
      targetCanAccept: "TARGET_CANNOT_ACCEPT",
      requiredStepsFilled: "REQUIRED_STEPS_NOT_FILLED",
      withinReopenWindow: "REOPEN_WINDOW_EXPIRED",
    };
    function guardProblem(check) {
      if (check.notFrom) return problem(409, "TRANSITION_NOT_ALLOWED_FROM_STATE", check.why);
      return problem(403, GUARD_CODE[check.guard] || "GUARD_FAILED", check.why, check.guard ? { guard: check.guard } : {});
    }

    /* ===== Маршруты API ===== */

    // Инцидент по идентификатору: byId — для самого сервера, find — для запросов оператора,
    // ему инцидент вне групп доступа не виден никак (§5)
    const byId = (guid) => events.find((e) => e.id === guid) || null;
    const find = (guid) => {
      const ev = byId(guid);
      return ev && canSee(ev) ? ev : null;
    };
    const touch = (list) => list.forEach((e) => (e.version += 1));

    // Версия записи для оптимистичной блокировки (§14.1): ETag — поле version в кавычках.
    // Запрос, меняющий инцидент, несёт её в If-Match: нет заголовка — 428, версия старая — 412
    const etag = (ev) => `"${ev.version}"`;
    function versionProblem(ev, headers) {
      const sent = headers["if-match"];
      if (!sent) return problem(428, "PRECONDITION_REQUIRED", ["Нет версии записи: запрос без If-Match"]);
      const versions = sent.split(",").map((v) => v.trim().replace(/^W\//, ""));
      if (versions.includes("*") || versions.includes(etag(ev))) return null;
      return problem(412, "VERSION_CONFLICT", ["Инцидент уже изменён: {state}", { state: STATES[ev.state].label }], { current: card(ev) });
    }

    function runTransition(id, ev, formValues, surface) {
      const tr = engine.transition(id);
      if (!tr) return problem(404, "NOT_FOUND", ["Неизвестное действие"]);
      const check = engine.availability(id, ev, { form: formValues, surface });
      if (!check.ok) return guardProblem(check);
      const before = ev.log.length;
      const r = engine.run(id, ev, formValues, { surface });
      if (!r.ok) return problem(422, "FORM_FIELD_REQUIRED", r.why);
      touch([ev]);
      emit(id === "transfer" ? "incident.owner_changed" : "incident.state_changed", ev, ME, { transitionId: id });
      const journal = journalView(ev).slice(before);
      return { status: 200, body: { incident: card(ev), navigate: r.navigate || null, journalEntries: journal, externalEffects: [], canceledTimerTrigger: null } };
    }

    function selectionActions(list) {
      const manual = W.transitions.filter((t) => t.trigger === "manual");
      return manual.map((tr) => {
        const mode = tr.bulk || { allowed: false };
        const each = list.every((e) => engine.availability(tr.id, e).ok);
        const sameTypeNew =
          list.length &&
          list.every((e) => W.grouping.createFrom.states.includes(e.state)) &&
          (!W.grouping.createFrom.sameEventType || list.every((e) => e.typeId === list[0].typeId));
        let ok = false;
        if (list.length < 2) ok = each;
        else if (mode.allowed && mode.mode === "same_type_new") ok = sameTypeNew && each;
        else if (mode.allowed && (mode.mode === "each_allowed" || mode.mode === "group_or_each_allowed")) ok = each;
        const why = ok ? null : say(["Для этой выборки действие недоступно"]);
        return {
          id: tr.id,
          kind: "transition",
          label: tr.label,
          style: tr.ui.style || "outline",
          visible: true,
          enabled: ok,
          reason: why ? why.text : null,
          reasonKey: why ? why.key : null,
          reasonVars: why ? why.vars : null,
          formId: tr.form || null,
          hotkey: tr.ui.hotkey || null,
          navigate: tr.ui.navigate || null,
          bulkAllowed: Boolean(mode.allowed),
          createsGroup: Boolean(mode.createsGroup),
        };
      });
    }

    function selection(body) {
      const q = { filter: body.filter, search: body.search, sourceGroupGuid: body.sourceGroupGuid, eventTypeGuid: body.eventTypeGuid, deviceTypeId: body.deviceTypeId };
      const max = W.limits.maxBulk;
      let list = [];
      if (body.mode === "explicit") {
        list = (body.incidentGuids || []).map(find).filter(Boolean);
      } else if (body.mode === "all_in_filter") {
        list = visible(q).filter((e) => !isDone(e));
      } else if (body.mode === "same_type_new") {
        const pool = visible(q);
        const groupable = (e) => W.grouping.createFrom.states.includes(e.state);
        const anchor = find(body.anchorIncidentGuid) || pool.find(groupable);
        list = anchor ? pool.filter((e) => groupable(e) && e.typeId === anchor.typeId) : [];
      }
      const truncated = body.mode !== "explicit" && list.length > max;
      if (body.mode !== "explicit") list = list.slice(0, max);
      return { incidentGuids: list.map((e) => e.id), truncated, actions: selectionActions(list) };
    }

    const ROUTES = [
      ["GET", "/operator/workflow/active", () => ({ status: 200, body: W, headers: { ETag: `"${W.schema.id}@${W.schema.version}"` } })],
      ["GET", "/operator/session", () => ({ status: 200, body: sessionView() })],
      [
        "PUT",
        "/operator/session/agent-state",
        (p, q, body) => {
          if (body.agentState === "not_ready") {
            const notReady = W.session.states.find((s) => s.id === "not_ready");
            if (notReady.permission && !can(notReady.permission)) return problem(403, "PERMISSION_DENIED", ["Нет права уходить на перерыв"]);
            session.agentState = "not_ready";
            session.reasonId = body.reasonId || null;
            // Системное откладывание своих инцидентов в работе выполняет машина (system_hold_break)
            const fired = runScheduler();
            emit("session.agent_state_changed", null, ME, { agentState: "not_ready" });
            return { status: 200, body: { session: sessionView(), affectedIncidents: fired.map((f) => find(f.id)).filter(Boolean).map((ev) => summary(ev, "queue")) } };
          }
          if (body.agentState === "offline") {
            // Конец смены: адресованные лично и не принятые уходят дежурной группе или в очередь (§8.1)
            session.agentState = "offline";
            session.reasonId = null;
            const fired = runScheduler();
            emit("session.agent_state_changed", null, ME, { agentState: "offline" });
            return { status: 200, body: { session: sessionView(), affectedIncidents: fired.map((f) => find(f.id)).filter(Boolean).map((ev) => summary(ev, "queue")) } };
          }
          session.agentState = "ready";
          session.reasonId = null;
          emit("session.agent_state_changed", null, ME, { agentState: "ready" });
          return { status: 200, body: { session: sessionView(), affectedIncidents: [] } };
        },
      ],
      [
        "POST",
        "/operator/session/heartbeat",
        (p, q, body) => {
          session.openIncidentGuid = body.openIncidentGuid || null;
          lastHeartbeat = now();
          return { status: 204, body: null };
        },
      ],
      [
        "PATCH",
        "/operator/session/preferences",
        (p, q, body) => {
          Object.assign(session.preferences, body || {});
          return { status: 200, body: sessionView().preferences };
        },
      ],
      ["GET", "/operator/incidents", (p, q) => ({ status: 200, body: page(q) })],
      ["GET", "/operator/incidents/counters", () => ({ status: 200, body: counters() })],
      ["POST", "/operator/incidents/selection", (p, q, body) => ({ status: 200, body: selection(body || {}) })],
      [
        "POST",
        "/operator/incidents/transitions/{transitionId}/bulk",
        (p, q, body) => {
          const guids = body.incidentGuids || [];
          const list = guids.map(find).filter(Boolean);
          if (!list.length) return problem(422, "BULK_SELECTION_INVALID", ["Выборка пуста"]);
          const succeeded = [];
          // Нет такого или он вне доступа — для оператора одно и то же: NOT_FOUND
          const failed = guids.filter((g) => !find(g)).map((g) => ({ incidentGuid: g, problem: problem(404, "NOT_FOUND", ["Инцидент не найден"]).body }));
          let navigate = null;
          list.forEach((ev) => {
            const r = runTransition(p.transitionId, ev, body.formValues || {}, body.surface);
            if (r.status === 200) {
              succeeded.push(summary(ev, "queue"));
              navigate = r.body.navigate || navigate;
            } else failed.push({ incidentGuid: ev.id, problem: r.body });
          });
          return { status: 200, body: { succeeded, failed, navigate } };
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}",
        (p) => {
          const ev = find(p.incidentGuid);
          return ev ? { status: 200, body: card(ev), headers: { ETag: etag(ev) } } : problem(404, "NOT_FOUND", ["Инцидент не найден"]);
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}/actions",
        (p, q) => {
          const ev = find(p.incidentGuid);
          return ev ? { status: 200, body: actionsFor(ev, q.surface || "card") } : problem(404, "NOT_FOUND", ["Инцидент не найден"]);
        },
      ],
      [
        "POST",
        "/operator/incidents/{incidentGuid}/transitions/{transitionId}",
        (p, q, body, headers) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["Инцидент не найден"]);
          const stale = versionProblem(ev, headers);
          if (stale) return stale;
          if (body && body.expectedState && body.expectedState !== ev.state) {
            return problem(412, "VERSION_CONFLICT", ["Инцидент уже изменён: {state}", { state: STATES[ev.state].label }], { current: card(ev) });
          }
          const res = runTransition(p.transitionId, ev, (body && body.formValues) || {}, body && body.surface);
          if (res.status === 200) res.headers = { ETag: etag(ev) };
          return res;
        },
      ],
      [
        "POST",
        "/operator/incident-groups",
        (p, q, body) => {
          const list = (body.incidentGuids || []).map(find).filter(Boolean);
          const groupId = uuid(8, ++serial.group);
          const r = engine.createGroup(list, groupId);
          if (!r.ok) return r.guard ? guardProblem(r) : problem(422, "BULK_SELECTION_INVALID", r.why);
          list.forEach((ev) => {
            ev.groupCreatedAt = now();
            log(ev, ME, "Групповая обработка вместе с {ids}", {
              ids: list
                .filter((x) => x.id !== ev.id)
                .map((x) => x.number)
                .join(", "),
            });
          });
          touch(list);
          list.forEach((ev) => emit("incident.group_changed", ev, ME, { groupGuid: groupId }));
          return { status: 201, body: groupView(list[0]) };
        },
      ],
      [
        "DELETE",
        "/operator/incident-groups/{groupGuid}/members/{incidentGuid}",
        (p) => {
          const ev = find(p.incidentGuid);
          if (!ev || ev.groupId !== p.groupGuid) return problem(404, "NOT_FOUND", ["Инцидент не в группе"]);
          const r = engine.excludeFromGroup(ev);
          if (!r.ok) return r.guard ? guardProblem(r) : problem(422, "BULK_SELECTION_INVALID", r.why);
          touch([ev]);
          emit("incident.group_changed", ev, ME, { groupGuid: null });
          return { status: 200, body: card(ev) };
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}/scenario",
        (p) => {
          const ev = find(p.incidentGuid);
          return ev ? { status: 200, body: scenarioView(ev) } : problem(404, "NOT_FOUND", ["Инцидент не найден"]);
        },
      ],
      [
        "PATCH",
        "/operator/incidents/{incidentGuid}/scenario/answers",
        (p, q, body, headers) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["Инцидент не найден"]);
          // Ответы пишет только тот, кому машина разрешает править сценарий (scenarioEdit, §10.4)
          if (!engine.canEditScenario(ev)) return problem(403, "PERMISSION_DENIED", ["Карточка открыта на просмотр"]);
          const stale = versionProblem(ev, headers);
          if (stale) return stale;
          Object.assign(ev.answers, (body && body.answers) || {});
          if (!canOpenStep(ev, cursorOf(ev))) ev.stepIndex = firstOpenStep(ev);
          touch([ev]);
          return { status: 200, body: scenarioView(ev), headers: { ETag: etag(ev) } };
        },
      ],
      [
        "PUT",
        "/operator/incidents/{incidentGuid}/scenario/cursor",
        (p, q, body) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["Инцидент не найден"]);
          if (!engine.canEditScenario(ev)) return problem(403, "PERMISSION_DENIED", ["Карточка открыта на просмотр"]);
          const steps = scenarioSteps(ev);
          let index = cursorOf(ev);
          if (body && body.stepId) index = steps.findIndex((s) => s.id === body.stepId);
          else if (body && body.move === "next") index += 1;
          else if (body && body.move === "prev") index -= 1;
          else if (body && body.move === "first_open") index = firstOpenStep(ev);
          if (!canOpenStep(ev, index)) return problem(409, "REQUIRED_STEPS_NOT_FILLED", ["Сначала заполните предыдущие шаги"]);
          ev.stepIndex = index;
          return { status: 200, body: scenarioView(ev) };
        },
      ],
      [
        "POST",
        "/operator/incidents/{incidentGuid}/macros/{macroId}",
        (p) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["Инцидент не найден"]);
          const check = engine.availability("run_macro", ev);
          if (!check.ok) return guardProblem(check);
          if (!ev.launched.includes(p.macroId)) ev.launched.push(p.macroId);
          log(ev, ME, "Запущен макрос «{name}»", { name: p.macroId });
          touch([ev]);
          return { status: 202, body: { executionGuid: uuid(9, ++serial.macro), macroId: p.macroId, status: "delivered", queuedAt: iso(now()) } };
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}/journal",
        (p) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["Инцидент не найден"]);
          const items = journalView(ev);
          return { status: 200, body: { items, total: items.length } };
        },
      ],
      [
        "POST",
        "/operator/incidents/{incidentGuid}/journal",
        (p, q, body) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["Инцидент не найден"]);
          const text = String((body && body.text) || "").trim();
          if (!text) return problem(422, "FORM_FIELD_REQUIRED", ["Пустой комментарий"]);
          // Заметка оператора: состояние не меняется, текст не переводится — шаблон «{text}»
          ev.log.push({ at: now(), whoId: ME, k: "{text}", v: { text }, kind: "note" });
          touch([ev]);
          emit("journal.appended", ev, ME, {});
          const items = journalView(ev);
          return { status: 201, body: items[items.length - 1] };
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}/media",
        (p) => {
          const ev = find(p.incidentGuid);
          return ev ? { status: 200, body: mediaView(ev) } : problem(404, "NOT_FOUND", ["Инцидент не найден"]);
        },
      ],
      [
        "GET",
        "/operator/transfer-targets",
        (p, q) => {
          const ev = q.incidentGuid ? find(q.incidentGuid) : null;
          let list = targets().filter((o) => !engine.isSelf(o.id));
          if (ev) list = list.filter((o) => o.id !== engine.addressee(ev) && hasAccess(o.id, ev) && canAccept(o.id, ev));
          return { status: 200, body: list.map(({ label, ...rest }) => rest) };
        },
      ],
      [
        "GET",
        "/operator/reference/reasons/{catalogId}",
        (p) => {
          const catalog = W.reasonCatalogs[p.catalogId];
          return catalog ? { status: 200, body: catalog.items } : problem(404, "NOT_FOUND", ["Справочник не найден"]);
        },
      ],
      ["GET", "/operator/reference/event-types", () => ({ status: 200, body: eventTypes() })],
      [
        "GET",
        "/operator/reference/device-types",
        () => ({ status: 200, body: Object.entries(DEVICE_TYPES).map(([id, d]) => ({ id, label: d.label })) }),
      ],
      ["GET", "/operator/reference/source-groups", () => ({ status: 200, body: treeView(TREE) })],
      ["GET", "/operator/reference/priorities", () => ({ status: 200, body: ["critical", "high", "medium", "low"].map((id) => ({ id })) })],
    ].concat(opts.testSupport ? TEST_ROUTES() : []);

    /* ===== Тестовый стенд: только с testSupport, в боевой системе этих операций нет ===== */

    function TEST_ROUTES() {
      return [
        [
          "POST",
          "/test/reset",
          (p, q, body) => {
            if (body.fixture && body.fixture !== "demo") return problem(404, "NOT_FOUND", ["Нет эталонного набора {name}", { name: body.fixture }]);
            // Часы останавливаются: время в тестах идёт только по /test/clock
            clock.frozenAt = body.freezeClock === false ? null : realNow() + clock.offset;
            PERMISSIONS = body.operatorPermissions || opts.permissions || ALL_PERMISSIONS;
            rolesOverride = body.operatorRoles || null;
            load(FIXTURE);
            return { status: 200, body: { fixture: "demo", now: iso(now()), frozen: clock.frozenAt != null } };
          },
        ],
        [
          "PUT",
          "/test/operators/{operatorId}/roles",
          (p, q, body) => {
            // Роли изменились (в продукте — роли или группы доступа): сервер сразу проверяет, у кого
            // из владельцев и адресатов пропал доступ (addressee_lost_access, §5)
            const person = OPERATORS.find((o) => o.id === p.operatorId);
            if (!person) return problem(404, "NOT_FOUND", ["Нет оператора {id}", { id: p.operatorId }]);
            person.roles = (body && body.roles) || [];
            if (person.id === ME) {
              rolesOverride = person.roles;
              myDevices = accessibleDevices(person.roles);
            }
            const fired = runScheduler();
            return { status: 200, body: { operatorId: person.id, roles: person.roles, fired: fired.map((f) => ({ incidentGuid: f.id, transitionId: f.transition })) } };
          },
        ],
        [
          "POST",
          "/test/clock",
          (p, q, body) => {
            const sec = Number(body.advanceSec) || 0;
            if (sec < 0) return problem(422, "FORM_FIELD_REQUIRED", ["Время назад не идёт"]);
            if (clock.frozenAt != null) clock.frozenAt += sec * 1000;
            else clock.offset += sec * 1000;
            const fired = runScheduler();
            return { status: 200, body: { now: iso(now()), fired: fired.map((f) => ({ incidentGuid: f.id, transitionId: f.transition })) } };
          },
        ],
      ];
    }

    const compiled = ROUTES.map(([method, template, fn]) => {
      const names = [];
      const re = new RegExp(`^${template.replace(/\{(\w+)\}/g, (m, name) => (names.push(name), "([^/]+)"))}$`);
      return { method, template, re, names, fn };
    });

    // Образцы ответов — для самопроверки: она сверяет их со схемами openapi.json.
    // По каждому маршруту, коду и типу события — первые несколько, чтобы покрыть все виды ответов
    const recorded = [];
    const samples = new Map();
    function record(method, template, status, body, kind, headers) {
      const key = `${method} ${template} ${status} ${body && body.type ? body.type : ""}`;
      const n = samples.get(key) || 0;
      if (n >= 12) return;
      samples.set(key, n + 1);
      recorded.push({ method, template, status, body: JSON.parse(JSON.stringify(body)), kind: kind || "http", headers: lowerKeys(headers) });
    }

    function handle(method, url, body, headers) {
      const [path, query = ""] = String(url).split("?");
      const q = {};
      new URLSearchParams(query).forEach((v, k) => (q[k] = v));
      // Сначала маршрут без параметров: /incidents/counters не должен попасть в /incidents/{guid}
      const route =
        compiled.find((r) => r.method === method && !r.names.length && r.re.test(path)) ||
        compiled.find((r) => r.method === method && r.re.test(path));
      if (!route) return { status: 404, body: { code: "NOT_FOUND", message: `Нет маршрута ${method} ${path}` } };
      const m = path.match(route.re);
      const params = {};
      route.names.forEach((name, i) => (params[name] = decodeURIComponent(m[i + 1])));
      const res = route.fn(params, q, body || {}, lowerKeys(headers));
      record(method, route.template, res.status, res.body, "http", res.headers);
      return res;
    }

    /* ===== Планировщик и эмуляция коллег ===== */

    // Автоматические переходы машины по дедлайнам (§6.2): в продукте их выполняет сервер
    function runScheduler() {
      const fired = engine.tick();
      fired.forEach(({ id, transition }) => {
        const ev = byId(id);
        touch([ev]);
        const tr = engine.transition(transition);
        emit(transition === "auto_escalate" ? "incident.auto_escalated" : "incident.state_changed", ev, tr.actor || "dispatcher", {
          transitionId: transition,
          addressee: actorRef(engine.addressee(ev)),
        });
      });
      return fired;
    }

    /* ===== Эмуляция коллег (§17): через те же переходы машины, от имени коллеги ===== */

    // У каждого коллеги свой исполнитель: «я» — коллега, права — весь каталог, на смене. Признак
    // активности — свой: потерявший связь коллега перестаёт отвечать, и системные переходы
    // машины (system_hold_idle, затем system_release_idle) срабатывают по её же условиям
    function colleague(id) {
      if (!colleagueEngines[id]) {
        colleagueEngines[id] = IMEngine.create(
          Object.assign({}, engineCtx, {
            me: id,
            can: (key) => permsOf(id).includes(key),
            agentState: () => "ready",
            idleSec: () => (colleagueIdleSince[id] == null ? 0 : (now() - colleagueIdleSince[id]) / 1000),
          })
        );
      }
      return colleagueEngines[id];
    }
    const isColleague = (id) => Boolean(id) && id !== ME && OPERATORS.some((op) => op.id === id);
    const foreignActive = () => events.filter((e) => e.state === "in_progress" && isColleague(e.owner) && !e.groupId);

    // Коллега берёт одно из новых событий первой страницы очереди — не то, что открыто у оператора
    function simTakeEvent() {
      const pool = visible({ filter: "open" })
        .slice(0, PAGE_SIZE)
        .filter((e) => e.state === "new" && e.id !== session.openIncidentGuid);
      // В верхней части очереди всегда оставляем новое событие, чтобы оператору было что взять
      if (pool.length < 2) return;
      const ev = pool[pool.length - 1];
      // Берёт первый по очереди коллега, кому машина разрешает: свой лимит активных, права, на смене
      for (let i = 0; i < SIM.colleagues.length; i++) {
        const who = SIM.colleagues[(SIM.taken + i) % SIM.colleagues.length];
        if (colleagueIdleSince[who] != null) continue;
        const r = colleague(who).run("claim", ev, {}, { surface: "queue" });
        if (!r.ok) continue;
        SIM.taken += 1;
        touch([ev]);
        emit("incident.state_changed", ev, who, { transitionId: "claim" });
        return;
      }
    }

    // Коллега проходит шаг своего сценария — если машина разрешает ему править (scenarioEdit)
    function simAdvanceEvent() {
      const pool = foreignActive().filter((e) => !scenarioDone(e) && colleague(e.owner).canEditScenario(e));
      if (!pool.length) return;
      const ev = pool[Math.floor(Math.random() * pool.length)];
      const steps = scenarioSteps(ev);
      const idx = steps.findIndex((s) => !stepAnswerText(ev, s));
      if (idx === -1) return;
      const step = steps[idx];
      let done = "";
      if (step.type === "checkbox") {
        ev.answers[step.id] = true;
        done = "подтверждено";
      } else if (step.type === "macros") {
        if (!colleague(ev.owner).availability("run_macro", ev).ok) return;
        ev.launched.push(step.buttons[0]);
        done = ["запущен макрос «{name}»", { name: step.buttons[0] }];
      } else if (step.options) {
        ev.answers[step.id] = step.options[Math.floor(Math.random() * step.options.length)];
        done = ev.answers[step.id];
      } else {
        const notes = opts.colleagues.SIM_NOTES;
        ev.answers[step.id] = notes[Math.floor(Math.random() * notes.length)];
        done = ev.answers[step.id];
      }
      ev.stepIndex = Math.min(idx + 1, steps.length - 1);
      log(ev, ev.owner, "Шаг {i}/{n} · {name}: {done}", { i: idx + 1, n: steps.length, name: stepShort(step), done });
      touch([ev]);
      emit("journal.appended", ev, ev.owner, {});
      // Сценарий заполнен — коллега закрывает инцидент результатом полной обработки (тем, что
      // требует обязательных шагов, §2.2) и освобождается для следующего
      if (scenarioDone(ev)) {
        const who = ev.owner;
        const full = W.reasonCatalogs.close_result.items.find((i) => i.requiredStepSet && i.requiredStepSet !== "none");
        const r = colleague(who).run("close", ev, { resultId: full && full.id }, { surface: "card" });
        if (r.ok) {
          touch([ev]);
          emit("incident.state_changed", ev, who, { transitionId: "close" });
        }
      }
    }

    // Коллега передаёт свой инцидент оператору — переход «Передать» с его правами и проверками
    function simHandoff() {
      for (const ev of foreignActive()) {
        const from = ev.owner;
        const r = colleague(from).run("transfer", ev, { targetId: ME, comment: "Нужен оператор с доступом к архиву площадки" }, { surface: "card" });
        if (!r.ok) continue;
        touch([ev]);
        emit("incident.owner_changed", ev, from, { transitionId: "transfer", addressee: actorRef(ME) });
        return;
      }
    }

    // Коллега теряет связь (§12.3): его сессия больше не отвечает. Дальше — системные переходы
    // машины по признаку активности: сразу «отложен, нет связи», через idle_release — в очередь
    function simDrop() {
      const ev = foreignActive().pop();
      if (!ev) return;
      colleagueIdleSince[ev.owner] = now() - W.session.idleHoldSec * 1000;
      colleagueTick(ev.owner);
    }

    // Системные переходы оператора-коллеги (scope: incidents_owned_by_agent) — по его состоянию
    function colleagueTick(id) {
      const before = Object.fromEntries(events.map((e) => [e.id, e.owner]));
      colleague(id)
        .tick({ agentOnly: true })
        .forEach(({ id: guid, transition }) => {
          const ev = byId(guid);
          touch([ev]);
          emit("incident.state_changed", ev, "system", { transitionId: transition, previousOwner: actorRef(before[guid]) });
        });
    }

    function simulateColleagues() {
      if (!SIM.enabled) return;
      SIM.takeTick += 1;
      if (SIM.taken < SIM.maxTaken && SIM.takeTick >= (SIM.taken ? SIM.takeEverySec : SIM.firstTakeSec)) {
        SIM.takeTick = 0;
        simTakeEvent();
      }
      SIM.stepTick += 1;
      if (SIM.stepTick >= SIM.stepEverySec) {
        SIM.stepTick = 0;
        simAdvanceEvent();
      }
      SIM.handoffTick += 1;
      if (!SIM.handoffDone && SIM.handoffTick >= SIM.handoffSec) {
        SIM.handoffDone = true;
        simHandoff();
      }
      SIM.dropTick += 1;
      if (!SIM.dropDone && SIM.dropTick >= SIM.dropSec) {
        SIM.dropDone = true;
        simDrop();
      }
    }

    // Секунда работы встроенного сервера: автоматические переходы, затем коллеги
    function second() {
      const fired = runScheduler();
      Object.keys(colleagueIdleSince).forEach(colleagueTick);
      if (!fired.length) simulateColleagues();
    }

    if (opts.autoTick !== false) setInterval(second, 1000);

    return {
      handle,
      subscribe,
      recorded,
      tick: runScheduler,
      // Для тестов эмуляции коллег: секунда работы при остановленных часах стенда
      simulateSecond() {
        if (clock.frozenAt != null) clock.frozenAt += 1000;
        second();
      },
      routes: ROUTES.map(([method, template]) => `${method} ${template}`),
    };
  }

  window.IMServer = { create };
})();
