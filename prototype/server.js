/* Встроенный сервер прототипа. Отвечает на запросы ровно по контракту
   Specification/Workflow_machine/openapi.json и хранит всё, что в продукте хранит бэкенд:
   инциденты, журнал, прохождение сценариев, сессию оператора. Переходы выполняет исполнитель
   машины (engine.js), автоматические — планировщик раз в секунду (§6.2), сценарии — исполнитель
   машины сценариев (scenario.js) через стык §14.5. Интерфейс (app.js)
   разговаривает с ним только через api.js, теми же запросами, что с настоящим бэкендом.
   Работает в той же вкладке: страница открывается и с диска (file://), и с сайта.
   Данные — эталонный набор Specification/Workflow_machine/fixtures/demo.json со сценариями fixtures/scenarios/
   (prototype/fixture.js):
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
    let SCENARIO_ROWS = {};
    let SCENARIO_BY_TYPE = {};
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
    // Доступ человека к объекту инцидента — по группам доступа его ролей (§5). Факт мира для выражений
    // машины (cel.world.access); доступ группы и «может принять» — определения машины (hasAccess, canAccept)
    function hasAccess(id, ev) {
      if (id === ME) return canSee(ev);
      const person = OPERATORS.find((o) => o.id === id);
      return Boolean(person) && accessibleDevices(person.roles || []).has(eventSource(ev));
    }
    // Права человека: у оператора стенда — его набор, у остальных — объединение прав его ролей
    const permsOf = (id) => (id === ME ? PERMISSIONS : [...new Set(rolesOf(id).flatMap((r) => ROLE_RIGHTS[r] || []))]);
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

    /* ===== Сценарий: исполняет машина сценариев (prototype/scenario.js, §14.5) ===== */

    // Сценарий инцидента — версия, с которой он появился (§14.5): строка сценария как на сервере
    // (guid, version, name, script — формат машины сценариев), прохождение — ev.run (scenarioResult, спецификация, раздел 9)
    const rowKey = (guid, version) => `${guid}/${version}`;
    const rowOf = (ev) => SCENARIO_ROWS[rowKey(ev.scenarioGuid, ev.scenarioVersion)];
    const scriptOf = (ev) => rowOf(ev).script;
    // Новый инцидент получает последнюю версию сценария своего типа события
    function latestRow(typeId) {
      const guid = SCENARIO_BY_TYPE[typeId];
      return (
        Object.values(SCENARIO_ROWS)
          .filter((r) => r.guid === guid)
          .sort((a, b) => b.version - a.version)[0] || null
      );
    }
    const pathOf = (ev) => IMScenario.path(scriptOf(ev), ev.run);
    // Курсор показа — шаг пути; выпал из пути или ещё не ставился — текущий шаг прогона
    function viewStepOf(ev) {
      if (!pathOf(ev).includes(ev.viewStepId)) ev.viewStepId = IMScenario.cursor(scriptOf(ev), ev.run);
      return ev.viewStepId;
    }
    const progressOf = (ev) => IMScenario.progress(scriptOf(ev), ev.run);
    const stepsFilledOf = (ev, setId) => IMScenario.stepsFilled(scriptOf(ev), ev.run, setId);
    // Короткое имя шага — для журнала: название, иначе вопрос
    const stepName = (step) => step.title || step.view.label;
    // Ответ словами — для журнала: подписи вариантов (у Select — всех списков), текст, вложение; пропуск — тире
    function answerText(step, entry) {
      if (!entry || entry.skipped) return "—";
      const v = step.view;
      const label = (options, id) => (options.find((o) => o.id === id) || { label: id }).label;
      if (step.type === "Message") return v.label;
      if (step.type === "Image") return "1";
      if (step.type === "Select") return v.lists.flatMap((l) => (entry.value[l.id] || []).map((id) => label(l.options, id))).join(", ");
      if (step.type === "Checkbox") return entry.value.map((id) => label(v.options, id)).join(", ");
      if (step.type === "RadioButton") return label(v.options, entry.value);
      return String(entry.value == null ? "" : entry.value);
    }

    // Ответ на шаг — событие машины сценариев. Курсор показа — на шаг пути после отвеченного.
    // Макрос исхода запускается по условиям run_macro того, кто ответил (§14.5, профиль МИ)
    function answerStep(ev, actor, actorEngine, body) {
      const res = IMScenario.answer(scriptOf(ev), ev.run, body.stepId, body.value, {
        at: iso(now()),
        by: actor,
        skip: Boolean(body.skip),
        attachments: body.attachments || [],
      });
      if (!res.ok) return res;
      ev.run = res.result;
      const path = pathOf(ev);
      ev.viewStepId = path[Math.min(path.lastIndexOf(body.stepId) + 1, path.length - 1)];
      res.effects.filter((e) => e.type === "macro").forEach((e) => launchMacro(ev, actor, actorEngine, e.name));
      return res;
    }
    function launchMacro(ev, actor, actorEngine, name) {
      if (!actorEngine.availability("run_macro", ev).ok) return;
      log(ev, actor, "workflow.journal.macro.launched", { name });
      // Результат макроса — событием потока (§9, RULE-60); в прототипе исполнения нет — сразу «доставлен».
      // macroId события — имя макроса из сценария
      emit("macro.completed", ev, actor, { macroId: name, executionGuid: uuid(9, ++serial.macro), status: "delivered" });
    }
    // Ответ не принят — код ошибки по контракту
    function answerProblem(ev, body, error) {
      if (error === "not_on_path" || error === "unknown_step") return problem(409, "STEP_NOT_ON_PATH", ["workflow.error.scenario.not_on_path"]);
      if (error === "not_editable") return problem(409, "STEP_NOT_EDITABLE", ["workflow.error.scenario.not_editable"]);
      const step = scriptOf(ev).steps.find((x) => x.id === body.stepId);
      return problem(422, "INVALID_ANSWER", ["workflow.error.scenario.invalid_answer", { step: stepName(step) }], { details: { reason: error } });
    }

    /* ===== Журнал ===== */

    // when — момент, «в который» выполнен автоматический переход, если планировщик догонял (RULE-41)
    function log(ev, whoId, template, vars, when) {
      ev.log.push({ at: when != null ? when : now(), whoId, k: template, v: vars || null });
    }

    // Сценарий инцидента — ключ машины сценариев; нужен исполнителю уже при загрузке набора (таймеры)
    const scenarioKey = (ev) => ev.scenarioGuid;
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
      inGroup: (ev, groupId) => touches(ev, collectDeviceIds(findNode(TREE, groupId))),
      agentState: () => session.agentState,
      // Стык с машиной сценариев (§14.5): наборы шагов, прогресс, курсор, перенос ответов при объединении
      stepsFilled: (ev, setId) => stepsFilledOf(ev, setId),
      progress: (ev) => progressOf(ev),
      stepNumber: (ev) => pathOf(ev).lastIndexOf(viewStepOf(ev)) + 1,
      setCursor: (ev) => {
        ev.viewStepId = IMScenario.cursor(scriptOf(ev), ev.run);
      },
      // Сколько ответов привязанного перенесено в основной
      shareAnswers: (from, to, at) => {
        const res = IMScenario.share(scriptOf(from), from.run, scriptOf(to), to.run, { at: iso(at) });
        to.run = res.result;
        if (res.moved.length) to.viewStepId = IMScenario.cursor(scriptOf(to), to.run);
        return res.moved.length;
      },
      actorName: (id) => rawName(id),
      log,
      transferTargets: () => targets(),
      hasAccess: (id, ev) => hasAccess(id, ev),
      // Факты мира для выражений машины (cel.world, CEL.md): права и состояние любого человека, состав групп
      permsOf: (id) => permsOf(id),
      agentStateOf: (id) => agentStateOf(id),
      isOperator: (id) => OPERATORS.some((o) => o.id === id),
      membersOf: (groupId) => {
        const group = GROUPS.find((g) => g.id === groupId);
        return group ? membersOf(group) : [];
      },
      dutyGroups: () => GROUPS.map((g) => g.id),
      // Подставляется в форму «Передать»: кому этот оператор передавал в прошлый раз (§8.2)
      defaultTransferTarget: () => session.lastTransferTargetId,
      // Доставка уведомления (§9): получателей вычисляет машина (recipients). Алерт оператору стенда — событие
      // потока; остальные уведомления интерфейс выводит из событий о переходах
      deliver: (ev, recipients, { alert, transitionId }) => {
        if (alert && recipients.includes(ME)) emit("incident.alert", ev, "dispatcher", { transitionId });
      },
      // Нарушение основного записано тому, кто был в группе (recordBreach, §11.4, BUG-73) — ему новая версия
      onBreachShared: (ev) => touch([ev]),
      // Карточку увели (§9): в событии — кто выполнил переход и какой, по нему клиент называет причину (BUG-86).
      // Только если она открыта у оператора стенда и увёл не он сам своим перерывом или выходом (контракт, BUG-105)
      onEvict: (ev, who, transitionId, by) => {
        if (who === ME && !ownAgentStateChange && session.openIncidentGuid === ev.id) emit("incident.card_evicted", ev, by || null, { transitionId });
      },
    };
    // Перерыв или выход оператора стенда: переходы, которые он вызвал сам, увели карточку им же (BUG-105)
    let ownAgentStateChange = false;
    function runSchedulerForOwnChange() {
      ownAgentStateChange = true;
      try {
        return runScheduler();
      } finally {
        ownAgentStateChange = false;
      }
    }
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
      // Сброс — вход оператора и старт сервиса: молчание считается с этого момента — простой сервиса не молчание
      // операторов (§14.3, RULE-113)
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
      SCENARIO_ROWS = Object.fromEntries(data.scenarios.rows.map((r) => [rowKey(r.guid, r.version), r]));
      SCENARIO_BY_TYPE = data.scenarios.byEventType;
      // Прохождение — тоже снимок: его времена сдвигаются вместе с остальными
      const at = (time) => iso(abs(time));
      const runOf = (r) =>
        Object.assign({}, r, {
          state: Object.fromEntries(Object.entries(r.state).map(([id, e]) => [id, Object.assign({}, e, { answeredAt: at(e.answeredAt) })])),
          history: r.history.map((h) => Object.assign({}, h, { ts: at(h.ts) })),
          completedAt: at(r.completedAt),
        }, r.attachments ? { attachments: r.attachments.map((a) => Object.assign({}, a, { capturedAt: at(a.capturedAt) })) } : {});
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
        reactionLeftMs: null,
        resolutionDueAt: null,
        resolutionLeftMs: null,
        holdSince: null,
        holdDueAt: null,
        timers: inc.timers,
        slaBreached: inc.slaBreached,
        breaches: (inc.breaches || []).map((b) => ({ kind: b.kind, at: abs(b.at), owner: b.owner || null })),
        linkedTo: inc.linkedGuid || null,
        scenarioGuid: inc.scenarioGuid,
        scenarioVersion: inc.scenarioVersion,
        run: runOf(inc.scenarioResult),
        // Курсор показа — до первого setCursor на текущем шаге прогона
        viewStepId: null,
        log: inc.journal.map((j) => ({ at: abs(j.at), whoId: j.actor, who: j.actorName, k: j.template, v: j.vars })),
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
    // Закрыт ли — определение isDone машины
    const isDone = (ev) => engine.isDone(ev);

    // Подпись таймера — из машины, на языке оператора (§14.9)
    const timerLabel = (id) => render((W.timers.find((t) => t.id === id) || {}).labelKey || id);
    // У привязанного своего срока нет: у группы один — срок основного (§11.4)
    function timerState(ev) {
      if (isDone(ev) || ev.state === "linked") return null;
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

    // Варианты полей формы перехода для этого инцидента и значения по умолчанию, видно ли поле и обязательно ли
    // (form машины): интерфейс правил форм не вычисляет — смотрит в fieldRules
    function formView(tr, ev, surface) {
      if (!tr || !tr.form) return {};
      const f = engine.form(tr.form, ev, { surface });
      const fieldOptions = {};
      const fieldRules = {};
      f.fields.forEach((field) => {
        fieldRules[field.name] = field.rules;
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
      return { fieldOptions, fieldRules, formNote: note ? { text: note.text, key: note.key, vars: note.vars } : null };
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
        // Адресат — определение addressee машины: владелец, а пока группа не приняла — группа (§8.1)
        addressee: actorRef(engine.addressee(ev)),
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
        // Сколько привязанных — те же, что в GET …/linked: только видимые оператору (§5, ARCH-08 в15)
        linkedCount: events.filter((e) => e.linkedTo === ev.id && canSee(e)).length,
        scenarioProgress: progressOf(ev),
        scenarioTitle: rowOf(ev).name == null ? null : rowOf(ev).name,
        mediaKinds: ev.media === "video" ? ["video"] : ev.media === "map" ? ["map"] : ["video", "map"],
        schemaVersion: W.schema.version,
        version: String(ev.version),
        actions: actionsFor(ev, surface || "queue"),
      };
    }

    // Сценарий карточки: версия инцидента, прохождение и то, что МИ из него считает (профиль МИ)
    function scenarioView(ev) {
      const row = rowOf(ev);
      return {
        scenarioGuid: row.guid,
        scenarioVersion: row.version,
        name: row.name == null ? null : row.name,
        script: JSON.parse(JSON.stringify(row.script)),
        result: JSON.parse(JSON.stringify(ev.run)),
        path: pathOf(ev),
        // Шаги впереди по кратчайшему пути — карточка показывает их серым (RULE-95)
        ahead: IMScenario.ahead(row.script, ev.run),
        cursorStepId: viewStepOf(ev),
        progress: progressOf(ev),
        requiredStepsFilled: Object.fromEntries(
          Object.keys(W.stepSets)
            .filter((k) => !k.startsWith("$"))
            .map((k) => [k, stepsFilledOf(ev, k)])
        ),
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
    // Название сценария по guid — последней версии; нет названия — null
    const scenarioName = (guid) => {
      const row = Object.values(SCENARIO_ROWS).find((r) => r.guid === guid);
      return row && row.name != null ? row.name : null;
    };

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
      const pool = sortBy(visible({ filter: qf }).filter(under), sortOf({}));
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
      const scenarioLabel = (k) => scenarioName(k);
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
          versions: versionsOf(max == null ? matched : matched.slice(0, max)),
          truncated: max != null && matched.length > max,
          scenarioGuid,
          excluded,
          options: { conditions: options, scenarios },
        },
      };
    }

    // Пояснение в карточке — правила cardNotes машины, текстом на языке оператора (§6.3, ARCH-08 в8)
    function noteView(ev, enabledIds) {
      const n = engine.cardNote(ev, enabledIds);
      const s = n ? say(n.note) : null;
      return s ? { text: s.text, key: s.key, vars: s.vars, style: n.style } : null;
    }
    function card(ev) {
      const src = eventSource(ev);
      const deviceIds = [...new Set([...(ev.deviceIds || []), ...(ev.cameras || [])])];
      const base = summary(ev, "card");
      return Object.assign(base, {
        description: null,
        readOnly: !engine.canEditScenario(ev),
        // Доступные действия карточки уже посчитаны в summary — условия машины второй раз не вычисляются
        note: noteView(ev, base.actions.filter((a) => a.enabled).map((a) => a.id)),
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
      const blocking = events.find((e) => active.has(e.id));
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
        // Хранимое состояние, а вместо него производное — по выражению машины: «Занят», если есть свои в работе (derived, §12, RULE-99)
        agentState: engine.shownAgentState(session.agentState),
        agentStateReasonId: session.reasonId,
        permissions: PERMISSIONS.slice(),
        limits: Object.fromEntries(Object.entries(W.limits).filter(([key]) => !key.startsWith("$"))),
        usage: usage(),
        preferences: JSON.parse(JSON.stringify(session.preferences)),
        lastTransferTargetId: session.lastTransferTargetId || null,
        workflowSchemaVersion: W.schema.version,
        permissionIssues: [],
      };
    }

    // Состояние человека (§12.1): у оператора стенда — из сессии, у остальных — из набора.
    // На месте — «Готов» или «Занят»; дежурная группа — если на месте хотя бы один участник (§8.1)
    const agentStateOf = (id) => (id === ME ? session.agentState : (OPERATORS.find((o) => o.id === id) || {}).agentState || "offline");
    const present = (op) => (op.group ? membersOf(op).some((m) => present({ id: m })) : engine.onDuty(op.id));
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
    const byNumber = (a, b) => a.number.localeCompare(b.number, undefined, { numeric: true });
    // Ключи порядка — выражения машины (queueSort.keys): меньше — выше, следующий — при равенстве
    function sortBy(list, orderId) {
      const keys = new Map(list.map((e) => [e, engine.sortKeys(e, orderId)]));
      const cmp = (a, b) => {
        const [ka, kb] = [keys.get(a), keys.get(b)];
        for (let i = 0; i < ka.length; i++) if (ka[i] !== kb[i]) return ka[i] - kb[i];
        return 0;
      };
      return list.sort((a, b) => cmp(a, b) || byNumber(a, b));
    }

    // Поиск — по номеру, типу, площадке и месту. Привязанные инциденты в списках не видны, но ищутся:
    // их находит строка основного, в ней — кто из привязанных подошёл (matchedLinked)
    const hit = (e, needle) => `${e.number} ${e.type} ${e.site} ${e.location}`.toLowerCase().includes(needle);
    const linkedHits = (e, needle) => events.filter((x) => x.linkedTo === e.id && canSee(x) && hit(x, needle));
    function visible(q) {
      // В списках — инциденты, которые проходят хоть один фильтр очереди машины: привязанные инциденты
      // объединённого живут в карточке основного (§11)
      const filters = new Map();
      let list = events.filter((e) => canSee(e) && filters.set(e, engine.queueFilters(e)).get(e).length);
      if (q.sourceGroupGuid && q.sourceGroupGuid !== "all") {
        const node = findNode(TREE, q.sourceGroupGuid);
        const ids = node ? collectDeviceIds(node) : [q.sourceGroupGuid];
        list = list.filter((e) => touches(e, ids));
      }
      return sortBy(list.filter((e) => {
        if (q.filter && W.queueFilters.some((f) => f.id === q.filter) && !filters.get(e).includes(q.filter)) return false;
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
      }), sortOf(q));
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
      const passed = list.map((e) => engine.queueFilters(e));
      W.queueFilters.forEach((f) => (out[f.id] = passed.filter((ids) => ids.includes(f.id)).length));
      return out;
    }

    // Дерево групп — только группы, где есть доступные оператору устройства, и только они (§5)
    // Счётчики открытых инцидентов — только по запросу (withCounters=true, BUG-37). Открытые — те же, что в
    // фильтре очереди open машины: привязанные в нём не видны (BUG-77)
    // Фильтр машины — один раз на инцидент за запрос: узлы и устройства считают по готовому списку
    const isOpen = (e) => engine.inQueueFilter(e, "open");
    function treeView(nodes, withCounters, visibleOpen) {
      const all = withCounters ? visibleOpen || events.filter((e) => canSee(e) && isOpen(e)) : [];
      return nodes
        .filter((n) => !n.isDevice && collectDeviceIds(n).some((id) => myDevices.has(id)))
        .map((n) => {
          const ids = collectDeviceIds(n);
          const open = all.filter((e) => touches(e, ids));
          const devices = (n.children || [])
            .filter((c) => c.isDevice && myDevices.has(c.id))
            .map((c) => {
              const evs = open.filter((e) => touches(e, [c.id]));
              return withCounters ? Object.assign(deviceRef(c.id), { counters: { open: evs.length, topPriority: evs.filter((e) => e.priority === topPriority()).length } }) : deviceRef(c.id);
            });
          return {
            guid: n.id,
            name: n.name,
            description: n.description || null,
            children: treeView(n.children || [], withCounters, all),
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
    // История потока — последние события: по Last-Event-ID сервер досылает пропущенное; такого id уже нет —
    // первым сообщением stream.reset, клиент перечитывает всё (контракт, BUG-102)
    const STREAM_DEPTH = 500;
    const history = [];
    function send(body) {
      const message = Object.assign({ id: String(++seq) }, body);
      record("GET", "/operator/stream", 200, message, "stream");
      history.push(message);
      if (history.length > STREAM_DEPTH) history.shift();
      listeners.forEach((fn) => setTimeout(() => fn(JSON.parse(JSON.stringify(message))), 0));
    }
    function subscribe(fn, lastEventId) {
      if (lastEventId != null && lastEventId !== "") {
        const i = history.findIndex((m) => m.id === String(lastEventId));
        const missed =
          i >= 0
            ? history.slice(i + 1)
            : [{ id: String(seq), type: "stream.reset", at: iso(now()), incidentGuid: null, actor: null, incident: null, payload: {} }];
        if (i < 0) record("GET", "/operator/stream", 200, missed[0], "stream");
        missed.forEach((m) => setTimeout(() => fn(JSON.parse(JSON.stringify(m))), 0));
      }
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
    // Код ошибки по невыполненному условию — errorCode условия в реестре машины; у причины, у которой свой код,
    // где бы её ни дало условие, — errorCodes по ключу причины (BUG-68, ARCH-08 в9)
    const guardOf = (fn) => W.registries.guards.find((g) => g.fn === fn) || {};
    function guardProblem(check) {
      if (check.notFrom) return problem(409, "TRANSITION_NOT_ALLOWED_FROM_STATE", check.why);
      const g = guardOf(check.guard);
      const code = (g.errorCodes || {})[check.why && check.why[0]] || g.errorCode || "GUARD_FAILED";
      return problem(403, code, check.why, check.guard ? { guard: check.guard } : {});
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
    // Версии отобранных — их клиент пришлёт в expectedVersions (BUG-84)
    const versionsOf = (list) => Object.fromEntries(list.map((e) => [e.id, String(e.version)]));

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
        // Адресовано смотрящему — ему или его дежурной группе (isSelf машины): поток у каждого оператора свой
        addressedToMe: engine.isSelf(engine.addressee(ev)),
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
      if (!r.ok) return problem(422, r.code || "FORM_FIELD_REQUIRED", r.why);
      touch([ev]);
      emitTransition(ev, id, ME, r.facts);
      // Последний адресат оператора — из поля адресата формы перехода, если оно есть (§8.2)
      const targetField = ((W.forms.find((f) => f.id === tr.form) || {}).fields || []).find((f) => f.source === "transferTargets");
      if (targetField && formValues && formValues[targetField.name]) session.lastTransferTargetId = formValues[targetField.name];
      const externalEffects = (r.external || []).map((x) => ({ fn: x.fn, target: x.target, status: "queued" }));
      // Ответ — заново после системных переходов, которые выполнит handle (ARCH-10): журнал — и их записи
      const view = () => ({ incident: card(ev), navigate: r.navigate || null, journalEntries: journalView(ev).slice(before), externalEffects, canceledTimerTrigger: r.canceled || null });
      return { status: 200, body: view(), view };
    }

    // Отмеченный изменился после отметки (expectedVersions, §14.1, BUG-84): версия строки очереди не та, что прислал
    // клиент. Нет guid в словаре — не сверяется
    const changedSince = (ev, expected) => Boolean(expected) && expected[ev.id] != null && String(expected[ev.id]) !== String(ev.version);
    const conflict = (ev, extra) => problem(412, "VERSION_CONFLICT", ["workflow.error.version_conflict", { state: [STATES[ev.state].labelKey] }], extra);

    // Основной при объединении (§11) — mergePrimary машины. Ни одного подходящего — null. Выборка — по возрастанию
    // номера, а не в порядке отметки: у совсем равных основной — меньший номер, как в модели Quint
    const pickPrimary = (list) => engine.mergePrimary([...list].sort(byNumber));
    // Основной — всегда по §11.3 (mergePrimary машины): выбрать его клиент не может (RULE-101)
    function mergeIncidents(guids, expected) {
      const list = guids.map(find).filter(Boolean);
      if (list.length !== guids.length) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
      // Объединение — всё или ничего: хоть один изменился после отметки — не выполняется (BUG-84)
      const stale = list.find((e) => changedSince(e, expected));
      if (stale) return conflict(stale, { current: card(stale) });
      if (!list.length) return problem(422, "BULK_SELECTION_INVALID", ["workflow.error.merge.too_few"]);
      // Лимит выборки — как у массовых действий (§11, BUG-83); null — без ограничения
      if (tooLarge(list)) return problem(422, "BULK_SELECTION_INVALID", ["workflow.error.selection_too_large", { n: W.limits.maxBulk }]);
      // Одно — просто «Взять»; от двух — не меньше bulk.minItems перехода объединения машины
      const min = (W.transitions.find((t) => t.bulk && t.bulk.mode === "merge") || { bulk: {} }).bulk.minItems;
      if (list.length > 1 && list.length < min) return problem(422, "BULK_SELECTION_INVALID", ["workflow.error.selection_too_small", { n: min }]);
      const primary = pickPrimary(list);
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
      const reply = () => ({ status: 200, body: { incident: card(primary) } });
      return Object.assign(reply(), { again: reply });
    }

    // Больше лимита выборки (§11, RULE-69): null — без ограничения
    const tooLarge = (list) => W.limits.maxBulk != null && list.length > W.limits.maxBulk;
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
        // «Взять в работу» относится к отмеченному в состоянии, откуда объединяют, — и к своему отложенному, у
        // которого основного нет (RULE-78): на панели — с причиной. Два закрытых — не показана (§11.1, BUG-90)
        const visible = mode.mode === "merge" ? avail.some(([, a]) => !a.notFrom) : avail.some(([, a]) => !a.hidden);
        let ok = false;
        let reason = null;
        if (mode.mode === "merge") {
          // «Взять в работу» как одно: основной можно взять, остальные — объединить. Один ли сценарий — условие
          // перехода объединения машины (sameScenarioAsPrimary), его причина — с номером того, кто мешает (ARCH-08 в13)
          const primary = list.length ? pickPrimary(list) : null;
          if (list.length > 1 && list.length < mode.minItems) reason = ["workflow.error.selection_too_small", { n: mode.minItems }];
          else if (tooLarge(list)) reason = ["workflow.error.selection_too_large", { n: W.limits.maxBulk }];
          else if (primary) {
            // Одно отмеченное — просто «Взять»; несколько — как одно. Делать нечего — недоступно.
            // Не проходит — причина того, кто мешает, с его номером
            const check = engine.mergeCheck(primary, list.filter((e) => e !== primary));
            ok = check.ok && (list.length > 1 || Boolean(check.take));
            if (!check.ok && check.why) {
              reason = list.length < 2 || !check.ev ? check.why : ["workflow.error.selection.item", { number: check.ev.number, reason: render(check.why[0], check.why[1]) }];
            }
          } else if (list.length) reason = ["workflow.guard.merge_primary"];
        } else if (list.length < 2) ok = each;
        // Меньше bulk.minItems машины — на выборке недоступно
        else if (mode.allowed && list.length < mode.minItems) reason = ["workflow.error.selection_too_small", { n: mode.minItems }];
        else if (mode.allowed && tooLarge(list)) reason = ["workflow.error.selection_too_large", { n: W.limits.maxBulk }];
        else if (mode.allowed && mode.mode === "each_allowed") ok = each;
        // Причина — одного такого отмеченного: одно отмеченное — как в карточке, несколько — с его номером
        if (!ok && !reason && failed && failed[1].why && (mode.allowed || list.length < 2)) {
          reason = list.length < 2 ? failed[1].why : ["workflow.error.selection.item", { number: failed[0].number, reason: render(failed[1].why[0], failed[1].why[1]) }];
        }
        const why = ok ? null : say(reason || ["workflow.error.selection_unavailable"]);
        return Object.assign(
          {
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
          },
          ok && tr.form && mode.mode === "each_allowed" ? sharedForm(tr, list) : {}
        );
      });
    }

    // Форма действия на выборке — одна на всех (§11, ARCH-08 в14): варианты полей — те, что есть у каждого
    // отмеченного (выборка — из очереди); недоступный хоть у одного — недоступен; по умолчанию — общее значение
    function sharedForm(tr, list) {
      const [first, ...rest] = list.map((e) => formView(tr, e, "queue"));
      const fieldOptions = {};
      Object.entries(first.fieldOptions).forEach(([name, f]) => {
        const others = rest.map((v) => v.fieldOptions[name] || { options: [] });
        const options = f.options
          .filter((o) => others.every((x) => x.options.some((y) => y.id === o.id)))
          .map((o) => {
            const off = [o].concat(others.map((x) => x.options.find((y) => y.id === o.id))).find((y) => y.disabled);
            return off ? Object.assign({}, o, { disabled: true, reason: off.reason }) : o;
          });
        const d = f.defaultValue;
        fieldOptions[name] = { options, defaultValue: d && others.every((x) => x.defaultValue === d) && options.some((o) => o.id === d && !o.disabled) ? d : null };
      });
      return { fieldOptions, fieldRules: first.fieldRules, formNote: first.formNote };
    }

    function selection(body) {
      const q = { filter: body.filter, search: body.search, sourceGroupGuid: body.sourceGroupGuid, eventTypeGuid: body.eventTypeGuid, deviceTypeId: body.deviceTypeId };
      const max = W.limits.maxBulk;
      let list = [];
      // explicit — с отмеченными (minItems: 1 по контракту, BUG-98)
      if (body.mode === "explicit" && !(body.incidentGuids || []).length) return problem(422, "BULK_SELECTION_INVALID", ["workflow.error.selection_empty"]);
      if (body.mode === "explicit") {
        list = (body.incidentGuids || []).map(find).filter(Boolean);
      } else if (body.mode === "all_in_filter") {
        list = visible(q).filter((e) => !isDone(e));
      }
      // null — без ограничения (§11, RULE-69)
      const truncated = body.mode !== "explicit" && max != null && list.length > max;
      if (truncated) list = list.slice(0, max);
      // Ничего не подошло — и действий нет (BUG-98)
      return { status: 200, body: { incidentGuids: list.map((e) => e.id), versions: versionsOf(list), truncated, actions: list.length ? selectionActions(list) : [] } };
    }

    const ROUTES = [
      ["GET", "/operator/workflow/active", () => ({ status: 200, body: W, headers: { ETag: `"${W.schema.id}@${W.schema.version}${W === BASE_W ? "" : "+test"}"` } })],
      ["GET", "/operator/session", () => ({ status: 200, body: sessionView() })],
      [
        "PUT",
        "/operator/session/agent-state",
        (p, q, body) => {
          // Смена — переходом состояния оператора машины (session.transitions, §12, ARCH-08 в4): откуда и куда;
          // право и причина — у состояния, куда переходит
          const from = session.agentState;
          const to = body.agentState;
          const target = W.session.states.find((s) => s.id === to);
          // То же состояние — ни причины, ни планировщика, ни события: сменить причину перерыва, не вернувшись, нельзя (§12.2)
          if (to === from) return { status: 200, body: { session: sessionView(), affectedIncidents: [] } };
          const move = W.session.transitions.find((t) => t.from.includes(from) && t.to === to);
          const label = (id) => [(W.session.states.find((s) => s.id === id) || {}).labelKey || id];
          if (!move || !target) return problem(409, "TRANSITION_NOT_ALLOWED_FROM_STATE", ["workflow.error.agent_state_not_allowed", { from: label(from), to: label(to) }]);
          if (target.permission && !can(target.permission)) return problem(403, "PERMISSION_DENIED", ["workflow.error.break_no_permission"]);
          if (target.requiresReason && !W.session.breakReasons.some((r) => r.id === body.reasonId)) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.reason_required"]);
          if (to === "not_ready") {
            session.agentState = "not_ready";
            session.reasonId = body.reasonId || session.reasonId || null;
            // Системное откладывание своих инцидентов в работе выполняет машина (system_hold_break)
            const fired = runSchedulerForOwnChange();
            emit("session.agent_state_changed", null, ME, { agentState: "not_ready" });
            return { status: 200, body: { session: sessionView(), affectedIncidents: fired.map((f) => find(f.id)).filter(Boolean).map((ev) => summary(ev, "queue")) } };
          }
          if (body.agentState === "offline") {
            // Выход из МИ: свои в работе и отложенные — в очередь (owner_signed_out), адресованные лично
            // и не принятые — дежурной группе или в очередь (§8.1, §12.1); их выполняет машина
            session.agentState = "offline";
            session.reasonId = null;
            const fired = runSchedulerForOwnChange();
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
          // Признак активности — как у любого не-GET запроса оператора (handle, §12.3)
          session.openIncidentGuid = body.openIncidentGuid || null;
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
      ["POST", "/operator/incidents/selection", (p, q, body) => selection(body || {})],
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
          // Одно отмеченное — как одиночное действие; от двух — не меньше bulk.minItems машины
          if (bulkTr && guids.length > 1 && guids.length < bulkTr.bulk.minItems) return problem(422, "BULK_SELECTION_INVALID", ["workflow.error.selection_too_small", { n: bulkTr.bulk.minItems }]);
          // Нет такого или он вне доступа — для оператора одно и то же: NOT_FOUND
          const failed = guids.filter((g) => !find(g)).map((g) => ({ incidentGuid: g, problem: problem(404, "NOT_FOUND", ["workflow.error.not_found"]).body }));
          let navigate = null;
          const done = [];
          list.forEach((ev) => {
            // Изменился после отметки — не трогается: устаревшая выборка не перебивает сделанное после неё (BUG-84)
            if (changedSince(ev, body.expectedVersions)) return failed.push({ incidentGuid: ev.id, problem: conflict(ev).body });
            const r = runTransition(p.transitionId, ev, body.formValues || {}, body.surface);
            if (r.status === 200) {
              done.push(ev);
              navigate = r.body.navigate || navigate;
            } else failed.push({ incidentGuid: ev.id, problem: r.body });
          });
          const reply = () => ({ status: 200, body: { succeeded: done.map((ev) => summary(ev, "queue")), failed, navigate } });
          return Object.assign(reply(), { again: reply });
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
          if (res.status !== 200) return res;
          const reply = () => ({ status: 200, body: res.view(), headers: { ETag: etag(ev) } });
          return Object.assign(reply(), { again: reply });
        },
      ],
      ["POST", "/operator/incidents/merge", (p, q, body) => mergeIncidents((body && body.incidentGuids) || [], body && body.expectedVersions)],
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
          if (r.status !== 200) return r;
          const reply = () => ({ status: 200, body: card(primary) });
          return Object.assign(reply(), { again: reply });
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
          // «Отсоединить все» — тот же переход ко всем привязанным разом, атомарно: всё или ничего (ARCH-08 в6)
          const detach = W.transitions.find((t) => t.trigger === "manual" && t.from.includes("linked"));
          const linked = events.filter((e) => e.linkedTo === primary.id && e.state === "linked" && canSee(e));
          const r = engine.runAll(detach.id, linked, {}, { surface: "card" });
          if (!r.ok) return r.guard || r.notFrom ? guardProblem(r) : problem(422, r.code || "FORM_FIELD_REQUIRED", r.why);
          touch(linked);
          linked.forEach((ev, i) => emitTransition(ev, detach.id, ME, r.facts[i]));
          const reply = () => ({ status: 200, body: card(primary) });
          return Object.assign(reply(), { again: reply });
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
        "POST",
        "/operator/incidents/{incidentGuid}/scenario/answer",
        (p, q, body, headers) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          // Отвечает только тот, кому машина разрешает править сценарий (scenarioEdit, §10.4)
          if (!engine.canEditScenario(ev)) return problem(403, "PERMISSION_DENIED", ["workflow.error.read_only"]);
          const stale = versionProblem(ev, headers);
          if (stale) return stale;
          const res = answerStep(ev, ME, engine, body || {});
          if (!res.ok) return answerProblem(ev, body || {}, res.error);
          touch([ev]);
          // Ответы сценария изменились — тем, кто видит инцидент (§9, RULE-60)
          emit("incident.updated", ev, ME, { stepIds: [body.stepId] });
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
          // Показать можно только шаг пути: дальше текущего не пройти, не ответив на него
          if (!body || !pathOf(ev).includes(body.stepId)) return problem(409, "STEP_NOT_ON_PATH", ["workflow.error.scenario.not_on_path"]);
          ev.viewStepId = body.stepId;
          return { status: 200, body: scenarioView(ev) };
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
          // Для инцидента — варианты поля адресата формы машины (optionExpr); без инцидента — все, кроме себя
          const form = W.forms.find((f) => f.fields.some((x) => x.source === "transferTargets"));
          const field = ev && form ? engine.form(form.id, ev).fields.find((x) => x.source === "transferTargets") : null;
          const list = field ? field.options : targets().filter((o) => !engine.isSelf(o.id));
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
      // Сценарий — последняя версия сценария типа события: на ней инцидент и доигрывает (§14.5)
      const row = latestRow(spec.eventTypeId);
      if (!type || !row || !devices.length || badPriority) return null;
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
        reactionLeftMs: null,
        resolutionDueAt: null,
        resolutionLeftMs: null,
        holdSince: null,
        holdDueAt: null,
        slaBreached: false,
        breaches: [],
        linkedTo: null,
        scenarioGuid: row.guid,
        scenarioVersion: row.version,
        run: IMScenario.start(row.script, iso(now())),
        viewStepId: null,
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
            // advanceSec — целое, не меньше 0, обязательно (контракт, BUG-99)
            const sec = body.advanceSec;
            if (!Number.isInteger(sec)) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.test.clock_seconds"]);
            if (sec < 0) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.test.clock_backwards"]);
            if (clock.frozenAt != null) clock.frozenAt += sec * 1000;
            else clock.offset += sec * 1000;
            // serviceRestart — сервис лежал всё время сдвига: при старте молчание считается заново (§14.3, RULE-113, RULE-119)
            if (body.serviceRestart === true) lastHeartbeat = now();
            // runScheduler: false — такт планировщика ещё не наступил: что сделает запрос оператора (§14.3, BUG-82)
            const fired = body.runScheduler === false ? [] : runScheduler();
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

    // Ключ повтора (idempotencyKey, BUG-84): ответ на запрос с ключом помнится 10 минут, повтор получает его же
    // и ничего не выполняет снова — двойное нажатие и ретрай сети не применяют действие дважды
    const IDEMPOTENCY_MS = 10 * 60 * 1000;
    const answered = new Map();

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
      const acting = method !== "GET" && path.startsWith("/operator/");
      const idem = acting && body && body.idempotencyKey ? `${method} ${path} ${body.idempotencyKey}` : null;
      answered.forEach((a, k) => now() - a.at >= IDEMPOTENCY_MS && answered.delete(k));
      if (idem && answered.has(idem)) {
        const { res } = answered.get(idem);
        record(method, route.template, res.status, res.body, "http", res.headers);
        return JSON.parse(JSON.stringify(res));
      }
      // Перед запросом оператора — всё, что уже наступило по времени (§14.3, ARCH-10): иначе действие между
      // тактами планировщика стёрло бы нарушение (BUG-82). Окно после дедлайна по-прежнему ждёт человека
      if (acting) runScheduler();
      // Действие оператора — признак активности (§12.3, BUG-76): кто действует, тот не молчит
      if (acting) lastHeartbeat = now();
      let res = route.fn(params, q, body || {}, lowerKeys(headers));
      // После — системные переходы, которые запрос сделал возможными (передали вышедшему — сразу его группе), в
      // том же запросе: их события уходят в поток, ответ показывает инциденты уже после них (ARCH-10)
      if (acting && res.status < 300 && runScheduler().length && res.again) res = res.again();
      record(method, route.template, res.status, res.body, "http", res.headers);
      const out = { status: res.status, body: res.body, headers: res.headers };
      if (idem) answered.set(idem, { at: now(), res: JSON.parse(JSON.stringify(out)) });
      return out;
    }

    /* ===== Планировщик и эмуляция коллег ===== */

    // Автоматические переходы машины по дедлайнам (§6.2): в продукте их выполняет сервер
    function runScheduler() {
      // Чьи инциденты были мои — владельцем или адресатом, лично или группой (ownership машины): если после
      // переходов такой инцидент мне не виден, сервер сообщает об этом (§5)
      const wasMine = new Set(events.filter((e) => !isDone(e) && engine.ownership(e) !== "other").map((e) => e.id));
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

    // Ответ коллеги на шаг: вариант — случайный (в каждом списке Select — один), отметки — сколько нужно,
    // текст — из заметок эмуляции; вложение (необязательное) коллега пропускает
    function colleagueAnswer(step) {
      const v = step.view;
      const any = (list) => list[Math.floor(Math.random() * list.length)];
      const ids = (options) => options.map((o) => o.id);
      if (step.type === "RadioButton") return { stepId: step.id, value: any(ids(v.options)) };
      if (step.type === "Select") return { stepId: step.id, value: Object.fromEntries(v.lists.map((l) => [l.id, [any(ids(l.options))]])) };
      if (step.type === "Checkbox") return { stepId: step.id, value: ids(v.options).slice(0, Math.max(1, v.minSelected)) };
      if (step.type === "Comment") return { stepId: step.id, value: v.readonly ? "" : any(opts.colleagues.SIM_NOTES) };
      if (step.type === "Datetime") return { stepId: step.id, value: new Date(now()).toISOString().slice(0, 19) + "Z" };
      if (step.type === "Image") return { stepId: step.id, skip: true };
      return { stepId: step.id, value: null };
    }

    // Коллега отвечает на текущий шаг своего сценария — если машина разрешает ему править (scenarioEdit)
    function simAdvanceEvent() {
      const pool = foreignActive().filter((e) => !e.run.completedAt && colleague(e.owner).canEditScenario(e));
      if (!pool.length) return;
      const ev = pool[Math.floor(Math.random() * pool.length)];
      const who = ev.owner;
      const step = scriptOf(ev).steps.find((x) => x.id === ev.run.currentStepId);
      const answer = colleagueAnswer(step);
      if (!answer || !answerStep(ev, who, colleague(who), answer).ok) return;
      const prog = progressOf(ev);
      const i = pathOf(ev).lastIndexOf(step.id) + 1;
      log(ev, who, "workflow.journal.scenario.step", { i, n: prog.total == null ? i : prog.total, name: stepName(step), done: answerText(step, ev.run.state[step.id]) });
      touch([ev]);
      emit("journal.appended", ev, who, {});
      // Сценарий пройден — коллега закрывает инцидент результатом полной обработки (тем, что
      // требует набора обязательных шагов, §2.2) и освобождается для следующего
      const full = W.reasonCatalogs.close_result.items.find((x) => x.requiredStepSet && x.requiredStepSet !== "none");
      if (full && stepsFilledOf(ev, full.requiredStepSet)) {
        const r = colleague(who).run("close", ev, { resultId: full.id }, { surface: "card" });
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
