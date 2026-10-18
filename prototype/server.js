/* Встроенный сервер прототипа. Отвечает на запросы ровно по контракту
   Specification/State_machine/openapi.json и хранит всё, что в продукте хранит бэкенд:
   инциденты, журнал, ответы сценария, сессию оператора. Переходы выполняет исполнитель
   машины (engine.js), автоматические — планировщик раз в секунду (§6.2). Интерфейс (app.js)
   разговаривает с ним только через api.js, теми же запросами, что с настоящим бэкендом.
   Работает в той же вкладке: страница открывается и с диска (file://), и с сайта.
   Данные — эталонный набор Specification/State_machine/fixtures/demo.json (prototype/fixture.js):
   его же загружает бэкенд на тестовом стенде. Демо: один оператор, права — весь каталог,
   эмуляция коллег (§17).

   Параметры create(): workflow — машина; fixture — эталонный набор; strings — каталог строк по
   языкам (§14.9, prototype/strings.js); colleagues — настройки
   эмуляции коллег (colleagues.js) или false; now — часы; autoTick: false — планировщик не
   запускается сам; permissions — права оператора списком ключей (по умолчанию — весь каталог,
   кроме настройки схемы); testSupport: true — служебные операции тестового стенда
   /test/reset и /test/clock (README машины, «Тестовый стенд»). */
(() => {
  // Изменения на один прогон стенда — JSON Merge Patch (RFC 7396): объекты сливаются, null удаляет
  // поле, массивы и значения заменяются целиком. Исходник не меняется (PROC-13)
  function mergePatch(target, patch) {
    if (!patch || typeof patch !== "object" || Array.isArray(patch)) return JSON.parse(JSON.stringify(patch));
    const out = target && typeof target === "object" && !Array.isArray(target) ? JSON.parse(JSON.stringify(target)) : {};
    Object.entries(patch).forEach(([key, value]) => {
      if (value === null) delete out[key];
      else out[key] = mergePatch(out[key], value);
    });
    return out;
  }

  function create(opts) {
    // Схема: исходная — из opts; тестовый стенд может подменить её на прогон (/test/reset, workflowPatch)
    const BASE_W = opts.workflow;
    let W = BASE_W;
    const FIXTURE = opts.fixture;
    const STRINGS = opts.strings || {};
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
    // Справочник приоритетов (§2.5, RULE-68): уровни по убыванию числа — справочник МИ, общий для
    // всех схем. Код не знает уровни ни по имени, ни по числу
    let PRIORITIES = [];
    // Шкала приоритета из контракта (Priority: целое 0–100) — границы, а не уровни справочника
    const SCALE = { min: 0, max: 100 };
    const topPriority = () => (PRIORITIES.length ? PRIORITIES[0].value : null);
    // Число от источника → уровень справочника: есть — как есть; нет — ближайший не выше; ниже самого
    // низкого или без числа — самый низкий. Инцидент не кажется срочнее, чем по настройке
    function priorityLevel(n) {
      const lowest = PRIORITIES[PRIORITIES.length - 1];
      if (typeof n !== "number") return lowest.value;
      const level = PRIORITIES.find((p) => p.value <= n);
      return (level || lowest).value;
    }
    // Справочные ссылки меню справки (§7): общие и ссылки площадки — справочник администратора
    let HELP_LINKS = [];
    // Связи камер (§19.1, RULE-70): многие-ко-многим — название, устройства, камеры по порядку показа
    let CAMERA_LINKS = [];
    // Камеры источника: из всех связей, где он есть, — связи по порядку списка, камеры по порядку
    // связи, без повторов; первая — главная
    const camerasOf = (source) => [...new Set(CAMERA_LINKS.filter((l) => l.devices.includes(source)).flatMap((l) => l.cameras))];
    // Роли и их права — как их отдаёт основная система (§5): по ним известны права всех людей
    let ROLE_RIGHTS = {};
    let rolesOverride = null;
    let myDevices = new Set();
    // Идентификаторы, которые сервер создаёт сам, — UUID (контракт): первая цифра — вид
    // (7 — запись журнала, 8 — группа обработки, 9 — запуск макроса), дальше — номер
    const uuid = (kind, n, tail) => `${kind}${String(n).padStart(7, "0")}-0000-4000-8000-${tail || "000000000000"}`;
    const serial = { macro: 0, incident: 0 };
    let events = [];
    let SIM = { enabled: false };
    let session = null;
    // Эмулированные коллеги: исполнитель каждого и с какого момента его сессия не отвечает
    const colleagueEngines = {};
    const colleagueIdleSince = {};
    const PAGE_SIZE = 8;
    const MERGED_IN_SHOWN = 5;

    /* ===== Люди и права ===== */

    const findActor = (id) => ACTORS.find((a) => a.id === id) || null;
    const rawName = (id) => {
      const actor = findActor(id);
      // Нет человека — подпись-ключ (§14.9): переводится там, где показывается
      return actor ? actor.name : ["workflow.label.unassigned"];
    };
    const actorKind = (actor) =>
      actor.group ? "duty_group" : actor.id === "dispatcher" ? "dispatcher" : actor.system ? "system" : "operator";
    function actorRef(id, fallbackName) {
      if (!id) return fallbackName ? { id: null, kind: "system", name: fallbackName, role: render("workflow.label.role.system") } : null;
      const actor = findActor(id);
      if (!actor) return { id, kind: "operator", name: id, role: "" };
      return { id: actor.id, kind: actorKind(actor), name: actor.name, role: actor.role };
    }

    // Права демо-оператора: весь каталог машины, с настройкой схемы — чтобы был виден экран
    // настроек администратора (§20). В продукте права приходят из внешней системы (§5)
    let ALL_PERMISSIONS = W.permissions.map((p) => p.key);
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
    // один участник может. except — участник, который не в счёт: у него инцидент уже есть (RULE-93)
    function canAccept(id, ev, except) {
      const group = GROUPS.find((g) => g.id === id);
      if (group) return membersOf(group).some((m) => m !== except && canAccept(m, ev));
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
    // Инцидент относится к группе и устройству по устройству-источнику (§19.1, RULE-85): камеры рядом
    // и другие устройства события тревогой не считаются — ни в счётчиках дерева, ни в фильтре группы
    const touches = (ev, ids) => ids.includes(eventSource(ev));

    /* ===== Сценарий (до подключения машины сценариев, §14.5, §17) ===== */

    const scenarioOf = (ev) => SCENARIOS[ev.typeId];
    const scenarioSteps = (ev) => scenarioOf(ev).steps;
    // Короткое имя шага: у подтверждения — подпись-ключ (§14.9), у остальных — название из сценария
    const stepShort = (step) => (step.type === "checkbox" ? ["workflow.scenario.confirmation"] : step.label);
    // Заполнен ли шаг: подтверждён, запущен макрос или есть ответ
    function stepAnswerText(ev, step) {
      if (step.type === "checkbox") return Boolean(ev.answers[step.id]);
      if (step.type === "macros") return ev.launched.length > 0;
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

    // when — момент, «в который» выполнен автоматический переход, если планировщик догонял (RULE-41)
    function log(ev, whoId, template, vars, when) {
      ev.log.push({ at: when != null ? when : now(), whoId, k: template, v: vars || null });
    }

    // Всё, что исполнитель знает о данных сервера. «Я» (me) у каждого исполнителя своё: у оператора
    // стенда — он сам, у эмулированных коллег — коллега (их действия идут через те же переходы)
    const engineCtx = {
      workflow: W,
      me: ME,
      now,
      events: () => events,
      // Сценарий инцидента — условию «один сценарий с основным» у «Взять в работу» на выборке
      scenarioKey: (ev) => scenarioKey(ev),
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
      canAccept: (id, ev, except) => canAccept(id, ev, except),
      // Подставляется в форму «Передать»: кому этот оператор передавал в прошлый раз (§8.2)
      defaultTransferTarget: () => session.lastTransferTargetId,
      // Получатели алерта (§9, RULE-43): человек или участники группы — на месте и с доступом к
      // объекту. Оператору стенда — событие потока; сколько получателей, столько и вернуть
      notifyAlert: (ev, targetId, transitionId) => {
        const group = GROUPS.find((g) => g.id === targetId);
        const who = (group ? membersOf(group) : [targetId]).filter((id) => present({ id }) && hasAccess(id, ev));
        if (who.includes(ME)) emit("incident.alert", ev, "dispatcher", { transitionId });
        return who.length;
      },
      onEvict: (ev, who, transitionId) => {
        if (who === ME) emit("incident.card_evicted", ev, null, { transitionId });
      },
    };
    // Молчание оператора стенда (§12.3) — с последнего признака активности (heartbeat)
    let lastHeartbeat = null;
    const makeEngine = () =>
      IMEngine.create(Object.assign({}, engineCtx, { me: ME, idleSec: () => (lastHeartbeat == null ? 0 : (now() - lastHeartbeat) / 1000) }));
    let engine = makeEngine();
    // Другая схема на прогон стенда: всё, что из неё считается, — заново (PROC-13)
    function useWorkflow(w) {
      W = w;
      ALL_PERMISSIONS = W.permissions.map((p) => p.key);
      STATES = Object.fromEntries(W.states.map((s) => [s.id, s]));
      engineCtx.workflow = W;
      engine = makeEngine();
      Object.keys(colleagueEngines).forEach((id) => delete colleagueEngines[id]);
    }

    // Эталонный набор → модель сервера. Набор — снимок на момент capturedAt: при загрузке все
    // времена сдвигаются на «сейчас − capturedAt», и набор выглядит свежим в любой день
    function load(fixture) {
      // Сброс — вход оператора: молчание считается с этого момента
      lastHeartbeat = now();
      serial.incident = 0;
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
      PRIORITIES = (data.priorities || []).slice().sort((a, b) => b.value - a.value);
      HELP_LINKS = data.helpLinks || [];
      CAMERA_LINKS = data.cameraLinks || [];
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
        cameras: camerasOf(inc.devices[0]),
        media: inc.media,
        state: inc.state,
        owner: inc.owner,
        assignmentGroup: inc.assignmentGroup,
        escalationLevel: inc.escalationLevel,
        transferCount: inc.transferCount || 0,
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
        linkedTo: inc.linkedGuid || null,
        answers: inc.scenario.answers,
        launched: inc.scenario.launchedMacros,
        log: inc.journal.map((j) => ({ at: abs(j.at), whoId: j.actor, who: j.actorName, k: j.template, v: j.vars })),
        // Шаг, на котором остановился владелец; нет — первый незаполненный
        stepIndex: inc.scenario.cursorStepId ? SCENARIOS[inc.eventType.id].steps.findIndex((s) => s.id === inc.scenario.cursorStepId) : undefined,
        version: 1,
        // Набор — снимок: время появления в МИ неизвестно, берётся время события
        createdAt: abs(inc.occurredAt),
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
        lastTransferTargetId: null,
      };
      SIM = opts.colleagues ? JSON.parse(JSON.stringify(opts.colleagues.SIM)) : { enabled: false };
      Object.keys(colleagueIdleSince).forEach((id) => delete colleagueIdleSince[id]);
    }

    load(FIXTURE);

    /* ===== Ответы API: представление для смотрящего оператора ===== */

    // Строка ICU MessageFormat (§14.9): {name} — подстановка, {n, plural, one {…} few {…} other {…}} —
    // форма после числа, # — само число. Неизвестная подстановка остаётся как есть
    function icu(text, vars, locale, number) {
      let out = "";
      for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (c === "#" && number != null) out += String(number);
        else if (c !== "{") out += c;
        else {
          let depth = 0;
          let j = i;
          for (; j < text.length; j++) if (text[j] === "{") depth++; else if (text[j] === "}" && --depth === 0) break;
          const m = text.slice(i + 1, j).match(/^\s*(\w+)\s*(?:,\s*plural\s*,([\s\S]*))?$/);
          const v = m && vars ? vars[m[1]] : undefined;
          if (!m || v === undefined) out += text.slice(i, j + 1);
          else if (!m[2]) out += String(v);
          else {
            const forms = {};
            m[2].replace(/([=\w]+)\s*\{((?:[^{}]|\{[^{}]*\})*)\}/g, (all, k, form) => (forms[k] = form));
            const form = forms[`=${v}`] || forms[new Intl.PluralRules(locale).select(Number(v))] || forms.other || "";
            out += icu(form, vars, locale, v);
          }
          i = j;
        }
      }
      return out;
    }
    // Ключ каталога (§14.9) → строка на языке оператора, иначе русская; не ключ — сам текст.
    // Подстановка [ключ, подстановки] переводится так же. Клиент получает и ключ, и подстановки
    function render(template, vars) {
      const locale = (session && session.preferences.locale) || "ru";
      const text = (STRINGS[locale] || {})[template] || (STRINGS.ru || {})[template] || String(template || "");
      const values = Object.fromEntries(Object.entries(vars || {}).map(([k, v]) => [k, Array.isArray(v) ? render(v[0], v[1]) : v]));
      return icu(text, values, locale);
    }
    const say = (why) => (why ? { text: render(why[0], why[1]), key: why[0], vars: why[1] || {} } : null);

    let STATES = Object.fromEntries(W.states.map((s) => [s.id, s]));
    const isDone = (ev) => STATES[ev.state].category === "done";

    // Подпись таймера — из машины, на языке оператора (§14.9)
    const timerLabel = (id) => render((W.timers.find((t) => t.id === id) || {}).labelKey || id);
    function linkedDue(ev) {
      const due = events.filter((e) => e.linkedTo === ev.id && !isDone(e) && e.resolutionDueAt).map((e) => e.resolutionDueAt);
      return due.length ? iso(Math.min(...due)) : null;
    }
    function timerState(ev) {
      if (isDone(ev)) return null;
      const base = { serverTime: iso(now()) };
      if (ev.reactionDueAt) {
        return Object.assign(base, { id: "reaction", label: timerLabel("reaction"), dueAt: iso(ev.reactionDueAt), remainingMs: ev.reactionDueAt - now(), running: true });
      }
      if (ev.resolutionDueAt) {
        return Object.assign(base, { id: "resolution", label: timerLabel("resolution"), dueAt: iso(ev.resolutionDueAt), remainingMs: ev.resolutionDueAt - now(), running: true });
      }
      if (ev.resolutionLeftMs != null) {
        return Object.assign(base, { id: "resolution", label: timerLabel("resolution"), dueAt: null, remainingMs: ev.resolutionLeftMs, running: false });
      }
      return null;
    }
    function holdTimerState(ev) {
      if (ev.state !== "on_hold" || !ev.holdDueAt) return null;
      return { id: "hold", label: timerLabel("hold"), dueAt: iso(ev.holdDueAt), remainingMs: ev.holdDueAt - now(), running: true, serverTime: iso(now()) };
    }

    // Варианты полей формы перехода для этого инцидента и значения по умолчанию (form машины)
    function formView(tr, ev, surface) {
      if (!tr || !tr.form) return {};
      const f = engine.form(tr.form, ev, { surface });
      const fieldOptions = {};
      f.fields.forEach((field) => {
        if (!field.options) return;
        fieldOptions[field.name] = {
          options: field.options.map((o) => {
            const reason = o.why ? say([o.why]) : null;
            return Object.assign(
              { id: o.id, label: render(o.label), disabled: Boolean(o.disabled), reason: reason ? reason.text : null },
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
            label: render(a.label),
            style: a.style,
            visible: true,
            enabled: a.enabled,
            reason: why ? why.text : null,
            reasonKey: why ? why.key : null,
            reasonVars: why ? why.vars : null,
            formId: a.formId || null,
            navigate: a.navigate || null,
            icon: a.icon || null,
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
        createdAt: iso(ev.createdAt),
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
        transferCount: ev.transferCount || 0,
        holdReasonId: ev.holdReason,
        closeResultId: ev.closeResult,
        closeCauseId: ev.massCause,
        closeResultLabel: ev.closeResult ? render(engine.closeResultLabel(ev)) : null,
        closedAt: iso(ev.closedAt),
        timer: timerState(ev),
        holdTimer: holdTimerState(ev),
        slaBreached: Boolean(ev.slaBreached),
        breaches: (ev.breaches || []).map((b) => ({ kind: b.kind, at: iso(b.at), owner: actorRef(b.owner) })),
        linkedTo: ev.linkedTo || null,
        linkedCount: events.filter((e) => e.linkedTo === ev.id).length,
        // Самый ранний идущий срок закрытия среди привязанных (§11.4): истечёт — нарушение на владельца основного
        linkedDueAt: linkedDue(ev),
        scenarioProgress: stepProgress(ev),
        scenarioTitle: (scenarioOf(ev) && scenarioOf(ev).title) || null,
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
          view: { short: Array.isArray(stepShort(s)) ? render(stepShort(s)[0]) : stepShort(s), options: s.options || null, placeholder: s.placeholder || null, buttons: s.buttons || null },
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

    // Сценарий инцидента: «Взять в работу» на выборке — как одно, только с одним сценарием (§11)
    const scenarioKey = (ev) => (scenarioOf(ev) && scenarioOf(ev).guid) || ev.typeId;

    /* ===== «Выделить по фильтру» из дерева (§11) =====
       Узел дерева (или все события) и условия, соединённые «ИЛИ». В условии — «И»: тип устройства
       (один или любой), события из выбранных, устройства из выбранных; пустое — любые. Нет условий —
       все события узла. Подходящие отмечаются, дальше — панель выборки */
    const typeOfEvent = (e) => (eventSource(e) ? deviceSpec(eventSource(e)).type : null);
    const COND_KEYS = ["deviceTypeId", "eventTypeIds", "deviceGuids"];
    function badFilter(f) {
      if (f == null) return null;
      if (typeof f !== "object" || Object.keys(f).some((k) => k !== "any") || !Array.isArray(f.any || [])) return "any";
      for (const c of f.any || []) {
        const bad = Object.keys(c || {}).find((k) => !COND_KEYS.includes(k));
        if (bad) return bad;
        if (c.deviceTypeId != null && typeof c.deviceTypeId !== "string") return "deviceTypeId";
        if (["eventTypeIds", "deviceGuids"].some((k) => c[k] != null && !Array.isArray(c[k]))) return "eventTypeIds";
      }
      return null;
    }
    const normCond = (c) => ({
      deviceTypeId: (c && c.deviceTypeId) || null,
      eventTypeIds: [...new Set(((c && c.eventTypeIds) || []).map(String))].sort(),
      deviceGuids: [...new Set(((c && c.deviceGuids) || []).map(String))].sort(),
    });
    // Условия без повторов, по порядку; условие «всё любое» — то же, что нет условий
    function normFilter(f) {
      const seen = new Set();
      const any = ((f && f.any) || []).map(normCond).filter((c) => {
        const key = JSON.stringify(c);
        return !seen.has(key) && seen.add(key);
      });
      return { any: any.some((c) => !c.deviceTypeId && !c.eventTypeIds.length && !c.deviceGuids.length) ? [] : any };
    }
    // skip — какое поле условия не учитывать: для вариантов этого поля в окне
    const fitsCond = (c, e, skip) =>
      (skip === "deviceTypeId" || !c.deviceTypeId || typeOfEvent(e) === c.deviceTypeId) &&
      (skip === "eventTypeIds" || !c.eventTypeIds.length || c.eventTypeIds.includes(e.typeId)) &&
      (skip === "deviceGuids" || !c.deviceGuids.length || c.deviceGuids.includes(eventSource(e)));
    const fitsFilter = (f, e) => !f.any.length || f.any.some((c) => fitsCond(c, e));
    // Под узлом — устройство-источник в группе дерева или во вложенных; без узла — все события
    function underNode(nodeId) {
      if (!nodeId) return () => true;
      const node = findNode(TREE, nodeId);
      const ids = new Set(node ? collectDeviceIds(node) : []);
      return (e) => ids.has(eventSource(e));
    }
    const typeName = (id) => (events.find((e) => e.typeId === id) || { type: id }).type;
    const deviceTypeLabel = (id) => (DEVICE_TYPES[id] || { label: id }).label;
    // Окно фильтра: варианты для каждого условия по каскаду — тип устройства, события этого типа,
    // устройства этого типа с выбранными событиями — с числами; сколько подходит под все условия и
    // какие (для «Выделить» — не больше maxBulk; null — все). Со всех страниц очереди
    function filterView(body) {
      const nodeId = body.sourceGroupGuid || null;
      if (nodeId && !findNode(TREE, nodeId)) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
      const bad = badFilter(body.filter);
      if (bad) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.filter.bad", { name: bad }]);
      // Варианты — и для пустых условий, которые оператор только добавил: их нормализация не убирает
      const conds = ((body.filter && body.filter.any) || []).map(normCond);
      const f = normFilter(body.filter);
      const under = underNode(nodeId);
      // Фильтр очереди (queueFilters машины), как над очередью; нет — открытые
      const qf = body.queueFilter || "open";
      if (!W.queueFilters.some((x) => x.id === qf)) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.filter.bad", { name: qf }]);
      const order = ORDERS[sortOf({})];
      const pool = visible({ filter: qf }).filter(under).sort((a, b) => order(a, b) || byNumber(a, b));
      const facet = (list, value, label, picked) => {
        const counts = new Map();
        list.forEach((e) => {
          const v = value(e);
          if (v != null) counts.set(v, (counts.get(v) || 0) + 1);
        });
        picked.forEach((v) => counts.has(v) || counts.set(v, 0));
        return [...counts].map(([id, count]) => ({ id, label: label(id), count })).sort((a, b) => String(a.label).localeCompare(String(b.label)));
      };
      const all = pool.filter((e) => fitsFilter(f, e));
      // «Одинаковый сценарий» (необязательно): события одного сценария, которые можно взять в работу как одно —
      // основной и те, кого к нему можно присоединить по условиям перехода объединения машины.
      // Чужие и ожидающие принятия не включаются: сколько — excluded. У сценария — сколько можно взять
      const scenarioLabel = (k) => (Object.values(SCENARIOS).find((x) => x && x.guid === k) || { title: typeName(k) }).title;
      const mergeTr = W.transitions.find((t) => t.bulk && t.bulk.mode === "merge");
      const takeable = (list) => {
        const p = pickPrimary(list);
        return p ? list.filter((e) => e === p || engine.availability(mergeTr.id, e, { form: { primaryId: p.id } }).ok) : [];
      };
      const byScenario = new Map();
      all.forEach((e) => byScenario.set(scenarioKey(e), (byScenario.get(scenarioKey(e)) || []).concat(e)));
      const scenarios = [...byScenario]
        .map(([id, list]) => ({ id, label: scenarioLabel(id), count: takeable(list).length }))
        .sort((a, b) => String(a.label).localeCompare(String(b.label)));
      let scenarioGuid = null;
      let matched = all;
      let excluded = 0;
      // Варианты условий: с галочкой — только из того, что можно взять в выбранном сценарии,
      // иначе выбор объекта обнулил бы выделение
      let base = pool;
      if (body.sameScenario && scenarios.length) {
        // Выбранный — если в нём есть что взять; иначе (не выбран, пропал, обнулился) — где взять можно больше всего
        const best = scenarios.reduce((a, b) => (b.count > a.count ? b : a));
        const asked = scenarios.find((x) => x.id === body.scenarioGuid);
        scenarioGuid = asked && (asked.count > 0 || !best.count) ? asked.id : best.id;
        const inScenario = byScenario.get(scenarioGuid);
        matched = takeable(inScenario);
        excluded = inScenario.length - matched.length;
        base = takeable(pool.filter((e) => scenarioKey(e) === scenarioGuid));
      }
      // С галочкой вариант остаётся, только если среди его событий есть кто может стать основным (новый или мой
      // в работе): иначе, выбрав его, взять было бы нечего. Выбранный раньше — остаётся, чтобы его можно было снять
      const viable = (opts, list, value, picked) =>
        base === pool ? opts : opts.filter((o) => picked.includes(o.id) || list.some((e) => value(e) === o.id && pickPrimary([e]) === e));
      const option = (list, value, label, picked) => viable(facet(list, value, label, picked), list, value, picked);
      const options = conds.map((c) => {
        const forEvents = base.filter((e) => fitsCond(Object.assign({}, c, { deviceGuids: [] }), e, "eventTypeIds"));
        const forDevices = base.filter((e) => fitsCond(c, e, "deviceGuids"));
        return {
          deviceTypes: option(base, typeOfEvent, deviceTypeLabel, c.deviceTypeId ? [c.deviceTypeId] : []),
          // События — по типу устройства; устройства — по типу и выбранным событиям
          eventTypes: option(forEvents, (e) => e.typeId, typeName, c.eventTypeIds),
          devices: option(forDevices, eventSource, (v) => deviceSpec(v).name, c.deviceGuids),
        };
      });
      const max = W.limits.maxBulk;
      return {
        status: 200,
        body: {
          count: matched.length,
          incidentGuids: (max == null ? matched : matched.slice(0, max)).map((e) => e.id),
          truncated: max != null && matched.length > max,
          scenarioGuid,
          excluded,
          options: { conditions: options, scenarios },
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
      // Камеры основного и открытых привязанных инцидентов, без повторов (§11)
      const own = ev.cameras || [];
      const extra = [...new Set(events.filter((e) => e.linkedTo === ev.id && e.state === "linked").flatMap((e) => e.cameras || []))].filter((id) => !own.includes(id));
      const cameras = own.concat(extra);
      return {
        cameras: cameras.filter((id) => myDevices.has(id)).map((id) => ({
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

    function sessionView() {
      const me = findActor(ME);
      return {
        operator: {
          guid: ME,
          name: me.name,
          role: me.role,
          dutyGroupGuids: GROUPS.filter((g) => membersOf(g).includes(ME)).map((g) => g.id),
        },
        agentState: session.agentState === "not_ready" || session.agentState === "offline" ? session.agentState : usage().activeCount ? "busy" : "ready",
        agentStateReasonId: session.reasonId,
        permissions: PERMISSIONS.slice(),
        limits: Object.fromEntries(Object.entries(W.limits).filter(([key]) => !key.startsWith("$"))),
        usage: usage(),
        preferences: JSON.parse(JSON.stringify(session.preferences)),
        lastTransferTargetId: session.lastTransferTargetId || null,
        workflowSchemaVersion: 4,
        permissionIssues: [],
      };
    }

    // Состояние человека (§12.1): у оператора стенда — из сессии, у остальных — из набора.
    // На месте — «Готов» или «Занят»; дежурная группа — если на месте хотя бы один участник (§8.1)
    const agentStateOf = (id) => (id === ME ? session.agentState : (OPERATORS.find((o) => o.id === id) || {}).agentState || "offline");
    const present = (op) => (op.group ? membersOf(op).some((m) => present({ id: m })) : !["not_ready", "offline"].includes(agentStateOf(op.id)));
    // Почему человека нет на месте (§8.1): перерыв — с причиной, вне МИ — «оффлайн»
    const reasonOf = (id) => (id === ME ? session.reasonId : (OPERATORS.find((o) => o.id === id) || {}).reasonId);
    const absenceLabel = (id) => {
      if (agentStateOf(id) === "offline") return render("workflow.label.absent.offline");
      const reason = W.session.breakReasons.find((r) => r.id === reasonOf(id));
      return render("workflow.label.absent.break", { reason: reason ? [reason.labelKey] : "" });
    };

    // Адресаты передачи. Себя и своих групп в списке нет (§8.1, §10.1)
    function targets() {
      return OPERATORS.concat(GROUPS).map((op) => ({
        id: op.id,
        kind: op.group ? "duty_group" : "operator",
        name: op.name,
        label: op.name,
        role: op.group ? render("workflow.label.role.group") : op.role,
        available: present(op),
        availabilityLabel: present(op) ? null : op.group ? render("workflow.label.nobody_present") : absenceLabel(op.id),
        memberIds: op.group ? membersOf(op) : [],
      }));
    }

    /* ===== Очередь: фильтр, группа, типы, поиск, страница ===== */

    // Порядок очереди (§7, RULE-62): из queueSort схемы; свой порядок оператор выбирает, только если
    // администратор разрешил. При равенстве — по номеру инцидента
    function sortOf(q) {
      const s = W.queueSort;
      const asked = q.sort || session.preferences.queueSort;
      return s.operatorMayChange && s.options.includes(asked) ? asked : s.default;
    }
    // Больше число — выше в очереди (§2.5, §7)
    const rank = (ev) => -ev.priority;
    const byNumber = (a, b) => a.number.localeCompare(b.number, undefined, { numeric: true });
    // Норматив реакции идёт: дедлайн есть и ещё не сработал (на потолке эскалации — уже сработал)
    const reactionRunning = (e) => Boolean(e.reactionDueAt) && !(e.firedTimers && e.firedTimers.reaction === e.reactionDueAt);
    const ORDERS = {
      priority_then_oldest: (a, b) => rank(a) - rank(b) || a.occurredAt - b.occurredAt,
      priority_then_newest: (a, b) => rank(a) - rank(b) || b.occurredAt - a.occurredAt,
      oldest_first: (a, b) => a.occurredAt - b.occurredAt,
      // Кто без идущего норматива реакции — после тех, у кого он идёт, по времени появления
      reaction_deadline: (a, b) =>
        Number(!reactionRunning(a)) - Number(!reactionRunning(b)) ||
        (reactionRunning(a) ? a.reactionDueAt - b.reactionDueAt : a.occurredAt - b.occurredAt),
    };

    // Поиск — по номеру, типу, площадке и месту. Привязанные инциденты в списках не видны, но ищутся:
    // их находит строка основного, в ней — кто из привязанных подошёл (matchedLinked)
    const hit = (e, needle) => `${e.number} ${e.type} ${e.site} ${e.location}`.toLowerCase().includes(needle);
    const linkedHits = (e, needle) => events.filter((x) => x.linkedTo === e.id && canSee(x) && hit(x, needle));
    const listed = () => new Set(W.queueFilters.flatMap((f) => (f.stateCategories || []).concat((f.states || []).map((st) => STATES[st].category))));
    function visible(q) {
      // В списках — только состояния, которые есть в фильтрах очереди машины: привязанные инциденты
      // объединённого живут в карточке основного (§11)
      const shown = listed();
      let list = events.filter((e) => canSee(e) && shown.has(STATES[e.state].category));
      if (q.sourceGroupGuid && q.sourceGroupGuid !== "all") {
        const node = findNode(TREE, q.sourceGroupGuid);
        const ids = node ? collectDeviceIds(node) : [q.sourceGroupGuid];
        list = list.filter((e) => touches(e, ids));
      }
      return list.filter((e) => {
        if (q.filter && !engine.inQueueFilter(e, q.filter)) return false;
        // Типы события и устройства — одно значение или несколько через запятую
        if (q.eventTypeGuid && q.eventTypeGuid !== "all" && !String(q.eventTypeGuid).split(",").includes(e.typeGuid)) return false;
        if (q.priority != null && q.priority !== "" && e.priority !== Number(q.priority)) return false;
        if (q.state && !String(q.state).split(",").includes(e.state)) return false;
        if (q.deviceTypeId && q.deviceTypeId !== "all") {
          const src = eventSource(e);
          if (!src || !String(q.deviceTypeId).split(",").includes(deviceSpec(src).type)) return false;
        }
        if (q.search) {
          const needle = String(q.search).toLowerCase();
          if (!hit(e, needle) && !linkedHits(e, needle).length) return false;
        }
        return true;
      }).sort((a, b) => ORDERS[sortOf(q)](a, b) || byNumber(a, b));
    }

    function page(q) {
      const list = visible(q);
      const size = Math.max(1, Number(q.pageSize) || PAGE_SIZE);
      const pages = Math.max(1, Math.ceil(list.length / size));
      const n = Math.min(Math.max(1, Number(q.page) || 1), pages);
      // На какой странице выбранный инцидент — если он виден при этих фильтрах (null — не виден)
      const idx = q.focusGuid ? list.findIndex((e) => e.id === q.focusGuid) : -1;
      const focusPage = idx === -1 ? null : Math.floor(idx / size) + 1;
      const found = (e) => (q.search ? linkedHits(e, String(q.search).toLowerCase()).map((x) => ({ guid: x.id, number: x.number })) : []);
      const item = (e) => Object.assign(summary(e, "queue"), found(e).length ? { matchedLinked: found(e) } : {});
      return { items: list.slice((n - 1) * size, n * size).map(item), total: list.length, page: n, pageSize: size, focusPage };
    }


    function counters(q) {
      const out = {};
      const list = visible({});
      W.queueFilters.forEach((f) => (out[f.id] = list.filter((e) => engine.inQueueFilter(e, f.id)).length));
      return out;
    }

    // Дерево групп — только группы, где есть доступные оператору устройства, и только они (§5)
    // Счётчики открытых инцидентов — только по запросу (withCounters=true, BUG-37)
    function treeView(nodes, withCounters) {
      return nodes
        .filter((n) => !n.isDevice && collectDeviceIds(n).some((id) => myDevices.has(id)))
        .map((n) => {
          const ids = collectDeviceIds(n);
          const open = events.filter((e) => canSee(e) && !isDone(e) && touches(e, ids));
          const devices = (n.children || [])
            .filter((c) => c.isDevice && myDevices.has(c.id))
            .map((c) => {
              const evs = events.filter((e) => canSee(e) && !isDone(e) && touches(e, [c.id]));
              return withCounters ? Object.assign(deviceRef(c.id), { counters: { open: evs.length, topPriority: evs.filter((e) => e.priority === topPriority()).length } }) : deviceRef(c.id);
            });
          return {
            guid: n.id,
            name: n.name,
            description: n.description || null,
            children: treeView(n.children || [], withCounters),
            devices,
            counters: withCounters
              ? { open: open.length, topPriority: open.filter((e) => e.priority === topPriority()).length }
              : null,
          };
        });
    }

    function eventTypes() {
      const seen = new Map();
      events.forEach((e) => {
        if (!seen.has(e.typeId)) seen.set(e.typeId, { guid: e.typeGuid, id: e.typeId, name: e.type, defaultReactionSec: engine.norm({ typeId: e.typeId }, "reaction") });
      });
      return [...seen.values()];
    }

    /* ===== Поток серверных событий (§9: поток вместо опроса) ===== */

    const listeners = new Set();
    let seq = 0;
    function emit(type, ev, actorId, payload) {
      // Об инциденте вне групп доступа оператор не узнаёт и из потока (§5)
      if (ev && !canSee(ev)) return;
      send({
        type,
        at: iso(now()),
        incidentGuid: ev ? ev.id : null,
        actor: actorRef(actorId),
        incident: ev ? summary(ev, "queue") : null,
        payload: payload || {},
      });
    }
    // Доступ к объекту пропал у того, кто инцидент вёл или кому он был адресован (§5): единственное
    // событие об инциденте вне групп доступа — только номер, данных инцидента оператор уже не видит
    function emitAccessLost(ev) {
      send({ type: "incident.access_lost", at: iso(now()), incidentGuid: ev.id, actor: null, incident: null, payload: { number: ev.number } });
    }
    function send(body) {
      const message = Object.assign({ id: String(++seq) }, body);
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
      if (!sent) return problem(428, "PRECONDITION_REQUIRED", ["workflow.error.precondition_required"]);
      const versions = sent.split(",").map((v) => v.trim().replace(/^W\//, ""));
      if (versions.includes("*") || versions.includes(etag(ev))) return null;
      return problem(412, "VERSION_CONFLICT", ["workflow.error.version_conflict", { state: [STATES[ev.state].labelKey] }], { current: card(ev) });
    }


    // Переход — одно событие потока (§9, RULE-60): какой, чем вызван и что было → стало. Что сказать
    // наблюдателям, клиент берёт из машины (ui.observerNotice), а не из имени перехода
    function emitTransition(ev, transitionId, actorId, facts) {
      const tr = engine.transition(transitionId);
      const f = facts || { from: {}, to: {} };
      emit("incident.transitioned", ev, actorId, {
        transitionId,
        trigger: tr ? tr.trigger : null,
        state: { from: f.from.state || null, to: ev.state },
        owner: { from: actorRef(f.from.owner), to: actorRef(ev.owner) },
        addressee: actorRef(engine.addressee(ev)),
        breach: f.breach || null,
      });
    }

    function runTransition(id, ev, formValues, surface) {
      const tr = engine.transition(id);
      if (!tr) return problem(404, "NOT_FOUND", ["workflow.error.unknown_action"]);
      const check = engine.availability(id, ev, { form: formValues, surface });
      if (!check.ok) return guardProblem(check);
      const before = ev.log.length;
      const r = engine.run(id, ev, formValues, { surface });
      if (!r.ok) return problem(422, "FORM_FIELD_REQUIRED", r.why);
      touch([ev]);
      emitTransition(ev, id, ME, r.facts);
      // Последний адресат оператора — из поля адресата формы перехода, если оно есть (§8.2)
      const targetField = ((W.forms.find((f) => f.id === tr.form) || {}).fields || []).find((f) => f.source === "transferTargets");
      if (targetField && formValues && formValues[targetField.name]) session.lastTransferTargetId = formValues[targetField.name];
      // Основной закрыт — привязанные закрываются сразу, системным переходом машины (§14.3)
      if (isDone(ev) && events.some((e) => e.linkedTo === ev.id && e.state === "linked")) runScheduler();
      const journal = journalView(ev).slice(before);
      const externalEffects = (r.external || []).map((x) => ({ fn: x.fn, target: x.target, status: "queued" }));
      return { status: 200, body: { incident: card(ev), navigate: r.navigate || null, journalEntries: journal, externalEffects, canceledTimerTrigger: r.canceled || null } };
    }

    // Основной при объединении (§11): мой в работе — к нему, иначе самый срочный новый,
    // у равных — самый ранний. Ни одного подходящего — null
    function pickPrimary(list) {
      const order = (a, b) => b.priority - a.priority || a.occurredAt - b.occurredAt || byNumber(a, b);
      const mine = list.filter((e) => e.state === "in_progress" && e.owner === ME).sort(order);
      const fresh = list.filter((e) => e.state === "new").sort(order);
      return mine[0] || fresh[0] || null;
    }
    function mergeIncidents(guids, primaryGuid) {
      const list = guids.map(find).filter(Boolean);
      if (list.length !== guids.length) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
      if (!list.length) return problem(422, "BULK_SELECTION_INVALID", ["workflow.error.merge.too_few"]);
      const primary = primaryGuid ? list.find((e) => e.id === primaryGuid) : pickPrimary(list);
      if (!primary) return problem(422, "BULK_SELECTION_INVALID", ["workflow.guard.merge_primary"]);
      const others = list.filter((e) => e !== primary);
      const r = engine.merge(primary, others);
      if (!r.ok) return r.guard ? guardProblem(r) : problem(422, "BULK_SELECTION_INVALID", r.why);
      // Привязанные объединяемых перешли к новому основному (relinkToPrimary машины) — им тоже новая версия
      touch(events.filter((e) => e.linkedTo === primary.id && !others.includes(e) && !isDone(e)));
      // Присоединённых может быть сколько угодно: в журнале — первые номера и «и ещё N»
      const shown = others.slice(0, MERGED_IN_SHOWN).map((o) => o.number).join(", ");
      if (others.length > MERGED_IN_SHOWN) log(primary, ME, "workflow.journal.merged_in_more", { ids: shown, more: others.length - MERGED_IN_SHOWN });
      else if (others.length) log(primary, ME, "workflow.journal.merged_in", { ids: shown });
      touch([primary].concat(others));
      others.forEach((o, i) => emitTransition(o, r.transitionId, ME, r.facts[i]));
      // Основной новый — взят в работу тем же действием (grouping.takeWith)
      if (r.taken) emitTransition(primary, r.taken.transitionId, ME, r.taken.facts);
      else emit("incident.updated", primary, ME, { stepIds: [] });
      return { status: 200, body: { incident: card(primary) } };
    }

    function selectionActions(list) {
      const manual = W.transitions.filter((t) => t.trigger === "manual");
      return manual.map((tr) => {
        const mode = tr.bulk || { allowed: false };
        // По каждому отмеченному: доступно ли, а если нет — почему. Ни к одному не относится
        // (скрыто у каждого, как в карточке) — на панели не показывается
        const avail = list.map((e) => [e, engine.availability(tr.id, e)]);
        const each = avail.every(([, a]) => a.ok);
        // Сначала тот, к кому действие относится, но не проходит (лимит, права), потом — не в том состоянии
        const failed = avail.find(([, a]) => !a.ok && !a.hidden) || avail.find(([, a]) => !a.ok);
        const visible = mode.mode === "merge" || avail.some(([, a]) => !a.hidden);
        let ok = false;
        let reason = null;
        if (mode.mode === "merge") {
          // «Взять в работу» как одно: один сценарий у всех, основной можно взять, остальные — объединить
          const scenarios = [...new Set(list.map(scenarioKey))];
          const primary = list.length ? pickPrimary(list) : null;
          if (scenarios.length > 1) {
            const titles = scenarios.map((k) => (Object.values(SCENARIOS).find((x) => x && x.guid === k) || { title: k }).title);
            reason = ["workflow.error.merge.scenarios", { titles: titles.join(", ") }];
          } else if (primary) {
            // Одно отмеченное — просто «Взять»; несколько — как одно. Делать нечего — недоступно.
            // Не проходит — причина того, кто мешает, с его номером
            const check = engine.mergeCheck(primary, list.filter((e) => e !== primary));
            ok = check.ok && (list.length > 1 || Boolean(check.take));
            if (!check.ok && check.why) {
              reason = list.length < 2 || !check.ev ? check.why : ["workflow.error.selection.item", { number: check.ev.number, reason: render(check.why[0], check.why[1]) }];
            }
          } else if (list.length) reason = ["workflow.guard.merge_primary"];
        } else if (list.length < 2) ok = each;
        else if (mode.allowed && mode.mode === "each_allowed") ok = each;
        // Причина — одного такого отмеченного: одно отмеченное — как в карточке, несколько — с его номером
        if (!ok && !reason && failed && failed[1].why && (mode.allowed || list.length < 2)) {
          reason = list.length < 2 ? failed[1].why : ["workflow.error.selection.item", { number: failed[0].number, reason: render(failed[1].why[0], failed[1].why[1]) }];
        }
        const why = ok ? null : say(reason || ["workflow.error.selection_unavailable"]);
        return {
          id: tr.id,
          kind: "transition",
          label: render(tr.labelKey),
          style: tr.ui.style || "outline",
          visible,
          enabled: ok,
          reason: why ? why.text : null,
          reasonKey: why ? why.key : null,
          reasonVars: why ? why.vars : null,
          formId: tr.form || null,
          navigate: tr.ui.navigate || null,
          bulkAllowed: Boolean(mode.allowed),
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
      }
      // null — без ограничения (§11, RULE-69)
      const truncated = body.mode !== "explicit" && max != null && list.length > max;
      if (truncated) list = list.slice(0, max);
      return { incidentGuids: list.map((e) => e.id), truncated, actions: selectionActions(list) };
    }

    const ROUTES = [
      ["GET", "/operator/workflow/active", () => ({ status: 200, body: W, headers: { ETag: `"${W.schema.id}@${W.schema.version}${W === BASE_W ? "" : "+test"}"` } })],
      ["GET", "/operator/session", () => ({ status: 200, body: sessionView() })],
      [
        "PUT",
        "/operator/session/agent-state",
        (p, q, body) => {
          if (body.agentState === "not_ready") {
            const notReady = W.session.states.find((s) => s.id === "not_ready");
            if (notReady.permission && !can(notReady.permission)) return problem(403, "PERMISSION_DENIED", ["workflow.error.break_no_permission"]);
            session.agentState = "not_ready";
            session.reasonId = body.reasonId || null;
            // Системное откладывание своих инцидентов в работе выполняет машина (system_hold_break)
            const fired = runScheduler();
            emit("session.agent_state_changed", null, ME, { agentState: "not_ready" });
            return { status: 200, body: { session: sessionView(), affectedIncidents: fired.map((f) => find(f.id)).filter(Boolean).map((ev) => summary(ev, "queue")) } };
          }
          if (body.agentState === "offline") {
            // Выход из МИ: свои в работе и отложенные — в очередь (owner_signed_out), адресованные лично
            // и не принятые — дежурной группе или в очередь (§8.1, §12.1); их выполняет машина
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
          // Лимит выборки проверяет сервер, а не только интерфейс (§11, BUG-40); null — без ограничения
          if (W.limits.maxBulk != null && guids.length > W.limits.maxBulk) return problem(422, "BULK_SELECTION_INVALID", ["workflow.error.selection_too_large", { n: W.limits.maxBulk }]);
          const list = guids.map(find).filter(Boolean);
          if (!list.length) return problem(422, "BULK_SELECTION_INVALID", ["workflow.error.selection_empty"]);
          // На выборке — только переходы с bulk.allowed машины (§11): «Взять» отмеченных — нет
          const bulkTr = engine.transition(p.transitionId);
          if (bulkTr && !(bulkTr.bulk && bulkTr.bulk.allowed)) return problem(422, "BULK_SELECTION_INVALID", ["workflow.error.selection_unavailable"]);
          const succeeded = [];
          // Нет такого или он вне доступа — для оператора одно и то же: NOT_FOUND
          const failed = guids.filter((g) => !find(g)).map((g) => ({ incidentGuid: g, problem: problem(404, "NOT_FOUND", ["workflow.error.not_found"]).body }));
          let navigate = null;
          const done = [];
          list.forEach((ev) => {
            const r = runTransition(p.transitionId, ev, body.formValues || {}, body.surface);
            if (r.status === 200) {
              done.push(ev);
              navigate = r.body.navigate || navigate;
            } else failed.push({ incidentGuid: ev.id, problem: r.body });
          });
          done.forEach((ev) => succeeded.push(summary(ev, "queue")));
          return { status: 200, body: { succeeded, failed, navigate } };
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}",
        (p) => {
          const ev = find(p.incidentGuid);
          return ev ? { status: 200, body: card(ev), headers: { ETag: etag(ev) } } : problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}/actions",
        (p, q) => {
          const ev = find(p.incidentGuid);
          return ev ? { status: 200, body: actionsFor(ev, q.surface || "card") } : problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
        },
      ],
      [
        "POST",
        "/operator/incidents/{incidentGuid}/transitions/{transitionId}",
        (p, q, body, headers) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          const stale = versionProblem(ev, headers);
          if (stale) return stale;
          if (body && body.expectedState && body.expectedState !== ev.state) {
            return problem(412, "VERSION_CONFLICT", ["workflow.error.version_conflict", { state: [STATES[ev.state].labelKey] }], { current: card(ev) });
          }
          const res = runTransition(p.transitionId, ev, (body && body.formValues) || {}, body && body.surface);
          if (res.status === 200) {
            res.body.incident = card(ev);
            res.headers = { ETag: etag(ev) };
          }
          return res;
        },
      ],
      ["POST", "/operator/incidents/merge", (p, q, body) => mergeIncidents((body && body.incidentGuids) || [], body && body.primaryGuid)],
      [
        "DELETE",
        "/operator/incidents/{incidentGuid}/linked/{linkedGuid}",
        (p) => {
          const primary = find(p.incidentGuid);
          const ev = find(p.linkedGuid);
          if (!primary || !ev || ev.linkedTo !== primary.id || ev.state !== "linked") return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          // «Отсоединить» — ручной переход машины из linked
          const detach = W.transitions.find((t) => t.trigger === "manual" && t.from.includes("linked"));
          const r = runTransition(detach.id, ev, {}, "card");
          return r.status === 200 ? { status: 200, body: card(primary) } : r;
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}/linked",
        (p, q) => {
          const primary = find(p.incidentGuid);
          if (!primary) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          // Привязанные инциденты объединённого (§11) — и закрытые вместе с ним, как история.
          // Их может быть сколько угодно (выборка без предела): постранично, как очередь
          const all = events.filter((e) => e.linkedTo === primary.id && canSee(e));
          const size = Math.min(200, Math.max(1, Number(q.pageSize) || PAGE_SIZE));
          const n = Math.max(1, Number(q.page) || 1);
          // На какой странице привязанный из focusGuid (найденное поиском очереди); null — его нет среди привязанных
          const idx = q.focusGuid ? all.findIndex((e) => e.id === q.focusGuid) : -1;
          const focusPage = idx === -1 ? null : Math.floor(idx / size) + 1;
          return { status: 200, body: { items: all.slice((n - 1) * size, n * size).map((e) => summary(e, "card")), total: all.length, page: n, pageSize: size, focusPage } };
        },
      ],
      [
        "DELETE",
        "/operator/incidents/{incidentGuid}/linked",
        (p) => {
          const primary = find(p.incidentGuid);
          if (!primary) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          // «Отсоединить все» — тот же переход ко всем привязанным разом: всё или ничего
          const detach = W.transitions.find((t) => t.trigger === "manual" && t.from.includes("linked"));
          const linked = events.filter((e) => e.linkedTo === primary.id && e.state === "linked" && canSee(e));
          const blocked = linked.find((ev) => !engine.availability(detach.id, ev).ok);
          if (blocked) return runTransition(detach.id, blocked, {}, "card");
          linked.forEach((ev) => runTransition(detach.id, ev, {}, "card"));
          return { status: 200, body: card(primary) };
        },
      ],
      ["POST", "/operator/incidents/filter", (p, q, body) => filterView(body || {})],
      [
        "GET",
        "/operator/incidents/{incidentGuid}/scenario",
        (p) => {
          const ev = find(p.incidentGuid);
          return ev ? { status: 200, body: scenarioView(ev) } : problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
        },
      ],
      [
        "PATCH",
        "/operator/incidents/{incidentGuid}/scenario/answers",
        (p, q, body, headers) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          // Ответы пишет только тот, кому машина разрешает править сценарий (scenarioEdit, §10.4)
          if (!engine.canEditScenario(ev)) return problem(403, "PERMISSION_DENIED", ["workflow.error.read_only"]);
          const stale = versionProblem(ev, headers);
          if (stale) return stale;
          Object.assign(ev.answers, (body && body.answers) || {});
          if (!canOpenStep(ev, cursorOf(ev))) ev.stepIndex = firstOpenStep(ev);
          touch([ev]);
          // Ответы сценария изменились — тем, кто видит инцидент (§9, RULE-60)
          emit("incident.updated", ev, ME, { stepIds: Object.keys((body && body.answers) || {}) });
          return { status: 200, body: scenarioView(ev), headers: { ETag: etag(ev) } };
        },
      ],
      [
        "PUT",
        "/operator/incidents/{incidentGuid}/scenario/cursor",
        (p, q, body) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          if (!engine.canEditScenario(ev)) return problem(403, "PERMISSION_DENIED", ["workflow.error.read_only"]);
          const steps = scenarioSteps(ev);
          let index = cursorOf(ev);
          if (body && body.stepId) index = steps.findIndex((s) => s.id === body.stepId);
          else if (body && body.move === "next") index += 1;
          else if (body && body.move === "prev") index -= 1;
          else if (body && body.move === "first_open") index = firstOpenStep(ev);
          if (!canOpenStep(ev, index)) return problem(409, "REQUIRED_STEPS_NOT_FILLED", ["workflow.error.previous_steps"]);
          ev.stepIndex = index;
          return { status: 200, body: scenarioView(ev) };
        },
      ],
      [
        "POST",
        "/operator/incidents/{incidentGuid}/macros/{macroId}",
        (p) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          const check = engine.availability("run_macro", ev);
          if (!check.ok) return guardProblem(check);
          if (!ev.launched.includes(p.macroId)) ev.launched.push(p.macroId);
          log(ev, ME, "workflow.journal.macro.launched", { name: p.macroId });
          touch([ev]);
          // Результат макроса — событием потока (§9, RULE-60); в прототипе исполнения нет — сразу «доставлен»
          const execution = { executionGuid: uuid(9, ++serial.macro), macroId: p.macroId, status: "delivered", queuedAt: iso(now()) };
          emit("macro.completed", ev, ME, { macroId: execution.macroId, executionGuid: execution.executionGuid, status: execution.status });
          return { status: 202, body: execution };
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}/journal",
        (p, q) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          // Постранично, как очередь (BUG-37); без pageSize — весь журнал одной страницей
          const all = journalView(ev);
          const size = Math.max(1, Number(q.pageSize) || all.length || 1);
          const n = Math.max(1, Number(q.page) || 1);
          return { status: 200, body: { items: all.slice((n - 1) * size, n * size), total: all.length } };
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}/media",
        (p) => {
          const ev = find(p.incidentGuid);
          return ev ? { status: 200, body: mediaView(ev) } : problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
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
      // Настройки администратора — данные МИ, которых нет в схеме (§20, RULE-44): только чтение
      [
        "GET",
        "/operator/admin/access-groups",
        () => {
          if (!can("incident:schema:admin")) return problem(403, "PERMISSION_DENIED", ["workflow.error.no_schema_admin"]);
          const named = (id, name) => ({ guid: id, name });
          return {
            status: 200,
            body: ACCESS_GROUPS.map((a) => ({
              id: a.id,
              name: a.name,
              roles: a.roles.slice(),
              sourceGroups: (a.sourceGroups || []).map((g) => named(g, (findNode(TREE, g) || {}).name || g)),
              devices: (a.devices || []).map((d) => named(d, deviceSpec(d).name)),
            })),
          };
        },
      ],
      [
        "GET",
        "/operator/admin/duty-groups",
        () => {
          if (!can("incident:schema:admin")) return problem(403, "PERMISSION_DENIED", ["workflow.error.no_schema_admin"]);
          return { status: 200, body: GROUPS.map((g) => ({ id: g.id, name: g.name, roles: (g.roles || []).slice(), members: (g.members || []).slice(), memberIds: membersOf(g) })) };
        },
      ],
      [
        "GET",
        "/operator/admin/camera-links",
        () => {
          if (!can("incident:schema:admin")) return problem(403, "PERMISSION_DENIED", ["workflow.error.no_schema_admin"]);
          const named = (id) => ({ guid: id, name: deviceSpec(id).name });
          return { status: 200, body: CAMERA_LINKS.map((l) => ({ guid: l.id, name: l.name, devices: l.devices.map(named), cameras: l.cameras.map(named) })) };
        },
      ],
      [
        "GET",
        "/operator/reference/reasons/{catalogId}",
        (p) => {
          const catalog = W.reasonCatalogs[p.catalogId];
          // Подпись позиции — на языке оператора, ключ — для клиента, который переводит сам (§14.9)
          return catalog ? { status: 200, body: catalog.items.map((i) => Object.assign({}, i, { label: render(i.labelKey) })) } : problem(404, "NOT_FOUND", ["workflow.error.catalog_not_found"]);
        },
      ],
      ["GET", "/operator/reference/event-types", () => ({ status: 200, body: eventTypes() })],
      [
        "GET",
        "/operator/reference/device-types",
        () => ({ status: 200, body: Object.entries(DEVICE_TYPES).map(([id, d]) => ({ id, label: d.label })) }),
      ],
      ["GET", "/operator/reference/source-groups", (p, q) => ({ status: 200, body: treeView(TREE, q.withCounters === "true") })],
      // Без площадки — все ссылки; с площадкой — общие и этой площадки (§7)
      [
        "GET",
        "/operator/reference/help-links",
        (p, q) => ({ status: 200, body: HELP_LINKS.filter((l) => q.site == null || l.site == null || l.site === q.site).map((l) => Object.assign({ icon: null }, l)) }),
      ],
      // Приоритеты — справочник машины в порядке важности (DOC-29)
      // Каталог строк (§14.9): язык — из запроса, иначе из настроек оператора; ключа нет на этом
      // языке или язык неизвестен — русская строка
      [
        "GET",
        "/operator/strings",
        (p, q) => {
          const locale = q.locale || session.preferences.locale || "ru";
          const strings = Object.assign({}, STRINGS.ru || {}, STRINGS[locale] || {});
          return { status: 200, body: { locale, strings } };
        },
      ],
      ["GET", "/operator/reference/priorities", () => ({ status: 200, body: JSON.parse(JSON.stringify(PRIORITIES)) })],
    ].concat(opts.testSupport ? TEST_ROUTES() : []);

    /* ===== Тестовый стенд: только с testSupport, в боевой системе этих операций нет ===== */

    // Появился инцидент (§6.2, RULE-61): запись из события источника, затем переход машины create —
    // он ставит владельца, уровень, норматив реакции и запись журнала. В продукте его вызывает
    // приход события от источника, на стенде — POST /test/incidents
    function createIncident(spec) {
      const type = eventTypes().find((t) => t.id === spec.eventTypeId);
      const devices = spec.deviceIds || [];
      const badPriority = spec.priority != null && !(Number.isInteger(spec.priority) && spec.priority >= SCALE.min && spec.priority <= SCALE.max);
      if (!type || !SCENARIOS[spec.eventTypeId] || !devices.length || badPriority) return null;
      const last = Math.max(0, ...events.map((e) => Number(String(e.number).replace(/\D/g, "")) || 0));
      const ev = {
        id: uuid(6, ++serial.incident),
        number: `INC-${last + 1}`,
        typeId: type.id,
        typeGuid: type.guid,
        type: type.name,
        priority: priorityLevel(spec.priority),
        site: spec.site || null,
        location: spec.location || null,
        occurredAt: spec.occurredAt ? Date.parse(spec.occurredAt) : now(),
        createdAt: now(),
        deviceIds: devices.slice(),
        cameras: camerasOf(devices[0]),
        state: null,
        owner: null,
        assignmentGroup: null,
        escalationLevel: 0,
        transferCount: 0,
        holdReason: null,
        closeResult: null,
        massCause: null,
        closeComment: null,
        closedBy: null,
        closedAt: null,
        reactionDueAt: null,
        resolutionDueAt: null,
        resolutionLeftMs: null,
        holdSince: null,
        holdDueAt: null,
        slaBreached: false,
        breaches: [],
        linkedTo: null,
        answers: {},
        launched: [],
        log: [],
        version: 1,
      };
      if (!engine.create(ev).ok) return null;
      events.unshift(ev);
      emit("incident.created", ev, "dispatcher", {});
      return ev;
    }

    function TEST_ROUTES() {
      return [
        [
          "POST",
          "/test/incidents",
          (p, q, body) => {
            const ev = createIncident(body || {});
            if (!ev) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.test.bad_incident"]);
            return { status: 201, body: card(ev), headers: { ETag: etag(ev) } };
          },
        ],
        [
          "POST",
          "/test/reset",
          (p, q, body) => {
            if (body.fixture && body.fixture !== "demo") return problem(404, "NOT_FOUND", ["workflow.error.test.no_fixture", { name: body.fixture }]);
            // Часы останавливаются: время в тестах идёт только по /test/clock
            clock.frozenAt = body.freezeClock === false ? null : realNow() + clock.offset;
            // Изменения схемы и набора — только на этот прогон: следующий reset без них вернёт исходные
            const before = W;
            const prioritiesBefore = JSON.stringify(PRIORITIES);
            useWorkflow(body.workflowPatch ? mergePatch(BASE_W, body.workflowPatch) : BASE_W);
            PERMISSIONS = body.operatorPermissions || opts.permissions || ALL_PERMISSIONS;
            rolesOverride = body.operatorRoles || null;
            load(body.fixturePatch ? mergePatch(FIXTURE, body.fixturePatch) : FIXTURE);
            // Схема сменилась — для клиентов это новая схема: пусть перечитают (BUG-34)
            if (W !== before) emit("workflow.schema_published", null, null, { schemaVersion: W.schema.version });
            // Справочник приоритетов сменился — так же (§2.5, RULE-68)
            if (JSON.stringify(PRIORITIES) !== prioritiesBefore) emit("reference.priorities_changed", null, null, {});
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
            if (!person) return problem(404, "NOT_FOUND", ["workflow.error.test.no_operator", { id: p.operatorId }]);
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
            if (sec < 0) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.test.clock_backwards"]);
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
      if (!route) return problem(404, "NOT_FOUND", ["workflow.error.no_route", { method, path }]);
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
      // Чьи инциденты были мои — владельцем или адресатом, лично или группой: если после переходов
      // такой инцидент мне не виден, сервер сообщает об этом (§5)
      const myGroups = GROUPS.filter((g) => membersOf(g).includes(ME)).map((g) => g.id);
      const wasMine = new Set(events.filter((e) => !isDone(e) && (e.owner === ME || myGroups.includes(e.assignmentGroup))).map((e) => e.id));
      const fired = engine.tick();
      // Системные переходы каждого человека — по его состоянию, как на бэкенде, а не только в эмуляции
      // коллег (RULE-47): переданное вышедшему сразу уходит его группе или в очередь
      const others = OPERATORS.filter((op) => op.id !== ME).flatMap((op) => colleagueTick(op.id));
      fired.forEach(({ id, transition, facts }) => {
        const ev = byId(id);
        touch([ev]);
        const tr = engine.transition(transition);
        if (wasMine.has(id) && !canSee(ev)) {
          wasMine.delete(id);
          emitAccessLost(ev);
        }
        emitTransition(ev, transition, tr.actor || "dispatcher", facts);
      });
      return fired.concat(others);
    }

    /* ===== Эмуляция коллег (§17): через те же переходы машины, от имени коллеги ===== */

    // У каждого коллеги свой исполнитель: «я» — коллега, права — по ролям, состояние — из набора
    // (RULE-47). Признак активности — свой: потерявший связь коллега перестаёт отвечать, и системные
    // переходы машины (system_hold_idle, затем system_release_idle) срабатывают по её же условиям
    function colleague(id) {
      if (!colleagueEngines[id]) {
        colleagueEngines[id] = IMEngine.create(
          Object.assign({}, engineCtx, {
            me: id,
            can: (key) => permsOf(id).includes(key),
            agentState: () => agentStateOf(id),
            idleSec: () => (colleagueIdleSince[id] == null ? 0 : (now() - colleagueIdleSince[id]) / 1000),
          })
        );
      }
      return colleagueEngines[id];
    }
    const isColleague = (id) => Boolean(id) && id !== ME && OPERATORS.some((op) => op.id === id);
    const foreignActive = () => events.filter((e) => e.state === "in_progress" && isColleague(e.owner));

    // Коллега берёт одно из новых событий первой страницы очереди — не то, что открыто у оператора
    function simTakeEvent() {
      const pool = visible({ filter: "open" })
        .slice(0, PAGE_SIZE)
        .filter((e) => e.state === "new" && e.id !== session.openIncidentGuid);
      // В верхней части очереди всегда оставляем новое событие, чтобы оператору было что взять
      if (pool.length < 2) return;
      const ev = pool[pool.length - 1];
      // Берёт первый по очереди коллега, кому машина разрешает: свой лимит активных, права, на месте
      for (let i = 0; i < SIM.colleagues.length; i++) {
        const who = SIM.colleagues[(SIM.taken + i) % SIM.colleagues.length];
        if (colleagueIdleSince[who] != null) continue;
        const r = colleague(who).run("claim", ev, {}, { surface: "queue" });
        if (!r.ok) continue;
        SIM.taken += 1;
        touch([ev]);
        emitTransition(ev, "claim", who, r.facts);
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
        done = ["workflow.journal.scenario.confirmed"];
      } else if (step.type === "macros") {
        if (!colleague(ev.owner).availability("run_macro", ev).ok) return;
        ev.launched.push(step.buttons[0]);
        done = ["workflow.journal.scenario.macro", { name: step.buttons[0] }];
      } else if (step.options) {
        ev.answers[step.id] = step.options[Math.floor(Math.random() * step.options.length)];
        done = ev.answers[step.id];
      } else {
        const notes = opts.colleagues.SIM_NOTES;
        ev.answers[step.id] = notes[Math.floor(Math.random() * notes.length)];
        done = ev.answers[step.id];
      }
      ev.stepIndex = Math.min(idx + 1, steps.length - 1);
      log(ev, ev.owner, "workflow.journal.scenario.step", { i: idx + 1, n: steps.length, name: stepShort(step), done });
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
          emitTransition(ev, "close", who, r.facts);
        }
      }
    }

    // Коллега передаёт свой инцидент оператору — переход «Передать» с его правами и проверками
    function simHandoff() {
      for (const ev of foreignActive()) {
        const from = ev.owner;
        // Комментарий пишет человек (эмулированный коллега) — данные, не текст системы
        const r = colleague(from).run("transfer", ev, { targetId: ME, comment: "Нужен оператор с доступом к архиву площадки" }, { surface: "card" }); // данные
        if (!r.ok) continue;
        touch([ev]);
        emitTransition(ev, "transfer", from, r.facts);
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
      const fired = colleague(id).tick({ agentOnly: true });
      fired.forEach(({ id: guid, transition, facts }) => {
        const ev = byId(guid);
        touch([ev]);
        emitTransition(ev, transition, "system", facts);
      });
      return fired;
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
