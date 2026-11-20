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
    // Правила-фильтры (§14.5, ARCH-15): как incident_rules сервера МИ — из эталонного набора, редактора нет (§17).
    // createdAt — мс: последний шаг ранжирования
    let RULES = [];
    // Окна плановых работ (§14.12, ТЗ-21): данные МИ организации, как правила; времена — мс. В отбор и в карточку
    // идут уже развёрнутые интервалы (maintenanceIntervals), смысл «в окне» — определение машины windowCovers
    let MAINT = [];
    // События (§14.5): guid от источника → номер тревоги и инциденты по порядку создания. Повтор события с тем же
    // guid ничего не создаёт. Набор отдельного списка не хранит — события собираются из eventGuid инцидентов
    let EVENTS = new Map();
    // Приём события (§14.5): уведомления переходов появления и итог адресации до записи события (commitEvent)
    let intakeDeliveries = null;
    const pendingIntake = new Map();
    // Когда принято каждое событие (мс) — для «приёма в минуту» раздела «Состояние системы» (§20)
    let intakeLog = [];
    // Группы доступа (§5): какие устройства доступны ролям. Роли оператора стенда — из набора
    // или из /test/reset (operatorRoles); видимые ему устройства считаются один раз при загрузке
    let ACCESS_GROUPS = [];
    // Справочник приоритетов (§2.5, RULE-68): уровни по убыванию числа — справочник МИ, общий для
    // всех схем. Код не знает уровни ни по имени, ни по числу
    let PRIORITIES = [];
    // Шкала приоритета из контракта (Priority: целое 0–100) — границы, а не уровни справочника
    const SCALE = { min: 0, max: 100 };
    // Название уровня справочника на языке оператора (§2.5): текст отказа «Приоритет уже изменён» (RULE-143)
    const priorityName = (value) => {
      const p = PRIORITIES.find((x) => x.value === value);
      return (p && p.name && (p.name[(session && session.preferences.locale) || "ru"] || p.name.ru)) || String(value);
    };
    const topPriority = () => (PRIORITIES.length ? PRIORITIES[0].value : null);
    // Число → уровень справочника (подмена приоритета на стенде, §2.5): есть — как есть; нет — ближайший не выше;
    // ниже самого низкого или без числа — самый низкий. Инцидент не кажется срочнее, чем по настройке
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
    // (6 — инцидент, 7 — запись журнала, 8 — группа обработки, 9 — запуск макроса, e — событие без guid), дальше — номер
    const uuid = (kind, n, tail) => `${kind}${String(n).padStart(7, "0")}-0000-4000-8000-${tail || "000000000000"}`;
    const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
    const isGuid = (g) => typeof g === "string" && UUID.test(g.toLowerCase());
    const serial = { macro: 0, incident: 0, event: 0, window: 0 };
    let events = [];
    let SIM = { enabled: false };
    let session = null;
    // Эмулированные коллеги: исполнитель каждого и с какого момента его сессия не отвечает
    const colleagueEngines = {};
    const colleagueIdleSince = {};
    // Идущие перерывы людей (§12.2): начало, причина и срок на начало перерыва, ушло ли оповещение «перерыв затянулся»
    let breaks = {};
    // Подсчёты блока «За период» (§23.3): запрос человека → время подсчёта и ответ; тот же запрос в течение минуты не считается заново
    let statsCache = new Map();
    const PAGE_SIZE = 8;
    const MERGED_IN_SHOWN = 5;

    /* ===== Аудит (§12.4): журнал действий в памяти, только дополняется ===== */

    // Журнал настроек прототипа пуст: редактора настроек в прототипе нет (§17)
    let auditActions = [];
    const settingsAudit = [];
    const DAY_MS = 86400000;
    const EXPORT_MAX_DAYS = 92;
    const EXPORT_MAX_ROWS = 1000000;
    // Вид записи по переходу машины: передача, перенаправление, объединение, эскалация; прочие переходы
    // системы и диспетчера — auto, человека — transition
    const AUDIT_KIND_OF = Object.assign(
      {},
      ...[
        [["transfer", "takeover", "release"], "handover"],
        [["reject", "addressee_signed_out_to_group", "addressee_signed_out_to_queue", "addressee_lost_access", "addressee_cannot_accept"], "redirect"],
        [["merge", "detach", "close_linked"], "merge"],
        [["auto_escalate", "resolution_escalate", "escalation_ceiling", "resolution_ceiling"], "escalation"],
      ].map(([ids, kind]) => Object.fromEntries(ids.map((id) => [id, kind])))
    );
    function audit(actorId, kind, fields) {
      const ref = actorRef(actorId);
      const person = ref && (ref.kind === "operator" || ref.kind === "duty_group");
      const entry = Object.assign(
        {
          id: String(auditActions.length + 1).padStart(8, "0"),
          at: iso(now()),
          personId: person ? ref.id : null,
          personName: ref ? String(ref.name) : render("workflow.label.role.system"),
          actorKind: person ? "person" : "system",
          kind,
        },
        fields
      );
      Object.keys(entry).forEach((k) => entry[k] === undefined && delete entry[k]);
      auditActions.push(entry);
      return entry;
    }
    function auditTransition(ev, transitionId, actorId, facts) {
      const f = facts || { from: {}, to: {} };
      const ref = actorRef(actorId);
      const byPerson = ref && ref.kind === "operator";
      const kind = AUDIT_KIND_OF[transitionId] || (byPerson ? "transition" : "auto");
      const target = actorRef(engine.addressee(ev));
      const related = ev.linkedTo || (f.from && f.from.linkedTo);
      audit(actorId, kind, {
        incidentGuid: ev.id,
        incidentNumber: ev.number,
        transition: transitionId,
        fromState: f.from.state || undefined,
        toState: ev.state,
        reasonId: ev.holdReason || undefined,
        targetPersonId: kind === "handover" || kind === "redirect" ? (target && target.kind === "operator" ? target.id : undefined) : undefined,
        targetGroupId: kind === "handover" || kind === "redirect" ? (target && target.kind === "duty_group" ? target.id : undefined) : undefined,
        relatedIncidentGuid: kind === "merge" && related && related !== ev.id ? related : undefined,
        relatedIncidentNumber: kind === "merge" && related && related !== ev.id ? (byId(related) || {}).number : undefined,
      });
    }
    // Ответ сценария: шаг и выбранный вариант; пропуск — skipped; свободный текст — только признак и длина (§12.4)
    function auditAnswer(ev, actorId, step, body) {
      const value = body.value;
      const answer = { skipped: Boolean(body.skip), hasText: false, textLength: 0 };
      // Вариант — только у шагов выбора; у любого другого шага строка — признак и длина, без самого значения
      const type = step && step.type;
      if (answer.skipped);
      else if (type === "RadioButton" && typeof value === "string") answer.option = value;
      else if (type === "Checkbox" && Array.isArray(value)) answer.option = value.join(",");
      else if (type === "Select" && value && typeof value === "object") answer.option = Object.values(value).flat().join(",");
      else if (typeof value === "string") Object.assign(answer, { hasText: value.length > 0, textLength: value.length });
      audit(actorId, "scenario_answer", { incidentGuid: ev.id, incidentNumber: ev.number, scenarioStep: body.stepId, answer });
    }
    // Параметры запроса аудита: фильтры обоих журналов, период, страница
    function auditQuery(q) {
      return { person: q.person, incident: q.incident, kind: q.kind, objectType: q.objectType, objectId: q.objectId, objectName: q.objectName, actor: q.actor, from: q.from, to: q.to, tz: q.tz, cursor: q.cursor, limit: q.limit };
    }
    // Инцидент фильтра: guid или номер, как его видит оператор (INC-0100 или 100); не то и не другое — null (400)
    const GUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    function auditIncident(value) {
      if (value == null) return undefined;
      if (GUID_RE.test(value)) return { guid: value.toLowerCase() };
      const m = /^(?:INC-)?0*([1-9][0-9]*)$/i.exec(String(value));
      return m ? { number: Number(m[1]) } : null;
    }
    const numberOf = (n) => Number(String(n || "").replace(/^INC-/i, ""));
    // Фильтры и период: без from и to — последние 7 суток; from позже to — null (400)
    function auditPeriod(q) {
      const to = q.to ? Date.parse(q.to) : now();
      const from = q.from ? Date.parse(q.from) : to - 7 * DAY_MS;
      if (Number.isNaN(from) || Number.isNaN(to) || from > to) return null;
      return { from, to };
    }
    const AUDIT_FILTERS = {
      actions: { person: "personId", incident: "incidentGuid", kind: "kind" },
      settings: { objectType: "objectType", objectId: "objectId", objectName: "objectName", actor: "actorId" },
    };
    function auditRows(journal, q, period) {
      const rows = journal === "actions" ? auditActions : settingsAudit;
      const by = AUDIT_FILTERS[journal];
      // Сначала новые; при одном времени — по id: курсор (время и id последней) не теряет и не повторяет строк
      const inc = auditIncident(q.incident);
      const name = q.objectName == null ? null : String(q.objectName).toLowerCase();
      return rows
        .filter((r) => Object.entries(by).every(([param, field]) => param === "incident" || param === "objectName" || q[param] == null || r[field] === q[param]))
        .filter((r) => !inc || (inc.guid ? String(r.incidentGuid).toLowerCase() === inc.guid : r.incidentNumber != null && numberOf(r.incidentNumber) === inc.number))
        .filter((r) => name == null || String(r.objectName || "").toLowerCase().includes(name))
        .filter((r) => Date.parse(r.at) >= period.from && Date.parse(r.at) <= period.to)
        .sort((a, b) => (a.at === b.at ? (a.id < b.id ? 1 : -1) : a.at < b.at ? 1 : -1));
    }
    const badRequest = () => problem(400, "BAD_REQUEST", ["workflow.error.bad_request"]);
    const noAudit = () => problem(403, "PERMISSION_DENIED", ["workflow.error.no_audit_access"]);
    // Права аудита (§5, §12.4): журнал действий — audit:actions:view, журнал изменений настроек — im.audit.settings.view,
    // его в первой версии даёт incident:schema:admin; выгрузка — audit:export вместе с правом смотреть выгружаемый журнал
    const AUDIT_VIEW = { actions: "audit:actions:view", settings: "incident:schema:admin" };
    const canAudit = (journal) => can(AUDIT_VIEW[journal]);
    function auditPage(journal, q) {
      if (!canAudit(journal)) return noAudit();
      const period = auditPeriod(q);
      const limit = q.limit == null ? 100 : Number(q.limit);
      if (!period || auditIncident(q.incident) === null || !Number.isInteger(limit) || limit < 1 || limit > 500) return badRequest();
      let rows = auditRows(journal, q, period);
      if (q.cursor) {
        const [at, id] = String(q.cursor).split("|");
        rows = rows.filter((r) => r.at < at || (r.at === at && r.id < id));
      }
      const items = rows.slice(0, limit);
      const last = items[items.length - 1];
      return { status: 200, body: Object.assign({ items }, rows.length > limit ? { next: `${last.at}|${last.id}` } : {}) };
    }
    // Подсказка фильтра (§12.4): по одной на инцидент или объект — из самой новой записи, сначала новые; q — часть текста без учёта регистра
    function auditSuggest(journal, q, rows) {
      if (!canAudit(journal)) return noAudit();
      const limit = q.limit == null ? 20 : Number(q.limit);
      if (!Number.isInteger(limit) || limit < 1 || limit > 50) return badRequest();
      const part = String(q.q || "").toLowerCase();
      const seen = new Map();
      rows
        .slice()
        .reverse()
        .sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0))
        .forEach((r) => seen.has(r.key) || seen.set(r.key, r));
      const items = [...seen.values()].filter((r) => String(r.text || "").toLowerCase().includes(part)).slice(0, limit).map((r) => r.item);
      return { status: 200, body: { items } };
    }
    // Защита от формул: ячейка, которая в Excel начнётся формулой (= + - @ после пробелов, или табуляция и перевод строки), — с апострофом
    const csvCell = (v) => {
      let s = v == null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
      if (/^[\s]*[=+\-@]/.test(s) || /^[\t\r\n]/.test(s)) s = "'" + s;
      return /[;"\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const CSV_COLUMNS = {
      actions: ["id", "at", "personId", "personName", "actorKind", "kind", "incidentGuid", "incidentNumber", "transition", "fromState", "toState", "reasonId", "targetPersonId", "targetGroupId", "relatedIncidentGuid", "relatedIncidentNumber", "scenarioStep", "answer", "details"],
      settings: ["id", "at", "actorId", "actorName", "objectType", "objectId", "objectName", "action", "fromVersion", "toVersion"],
    };
    // Выгрузка: CSV в UTF-8 с BOM, разделитель «;»; период — не больше 92 дней, строк — не больше 1 000 000.
    // Каждая выгрузка — запись audit_export в журнале действий
    // Время в CSV — в поясе tz браузера (имя IANA), «ГГГГ-ММ-ДД ЧЧ:ММ:СС ±ЧЧ:ММ»; без tz — UTC (§14.9)
    function csvTime(value, tz) {
      const ms = Date.parse(value);
      if (Number.isNaN(ms)) return value;
      const parts = Object.fromEntries(
        new Intl.DateTimeFormat("en-CA", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" })
          .formatToParts(new Date(ms))
          .map((p) => [p.type, p.value])
      );
      const local = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second);
      const off = Math.round((local - Math.floor(ms / 1000) * 1000) / 60000);
      const abs = Math.abs(off);
      const hm = `${String(Math.floor(abs / 60)).padStart(2, "0")}:${String(abs % 60).padStart(2, "0")}`;
      return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}:${parts.second} ${off < 0 ? "-" : "+"}${hm}`;
    }
    const validZone = (tz) => {
      try {
        new Intl.DateTimeFormat("en", { timeZone: tz });
        return /\//.test(tz) || tz === "UTC";
      } catch (e) {
        return false;
      }
    };
    function auditExport(journal, q) {
      if (!canAudit(journal)) return noAudit();
      // Смотреть можно, выгружать — нет: свой текст отказа, чтобы человек понял, какого права не хватает
      if (!can("audit:export")) return problem(403, "PERMISSION_DENIED", ["workflow.error.no_audit_export"]);
      const period = auditPeriod(q);
      if (!period || auditIncident(q.incident) === null || (q.tz != null && !validZone(q.tz))) return badRequest();
      const tz = q.tz == null ? "UTC" : q.tz;
      const rows = auditRows(journal, q, period);
      if (period.to - period.from > EXPORT_MAX_DAYS * DAY_MS || rows.length > EXPORT_MAX_ROWS)
        return problem(422, "AUDIT_EXPORT_TOO_LARGE", ["workflow.error.audit_export_too_large"]);
      const cols = CSV_COLUMNS[journal];
      const text = "﻿" + [cols.join(";")].concat(rows.map((r) => cols.map((c) => csvCell(c === "at" ? csvTime(r[c], tz) : r[c])).join(";"))).join("\r\n") + "\r\n";
      const filters = Object.fromEntries(Object.keys(AUDIT_FILTERS[journal]).filter((k) => q[k] != null).map((k) => [k, q[k]]));
      audit(ME, "audit_export", { details: { journal, filters, from: iso(period.from), to: iso(period.to), rows: rows.length } });
      return { status: 200, body: text, headers: { "Content-Type": "text/csv; charset=utf-8" } };
    }

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
    // Права аудита — не права оператора (§5, §12.4): у кого из прав машины только они, тот не видит ни одного инцидента
    // и устройства — очередь, карточки и справочники пусты, как на сервере (HasAnyMachinePermission)
    const AUDIT_ONLY = ["audit:actions:view", "audit:export"];
    const operatorRights = () => W.permissions.some((p) => !AUDIT_ONLY.includes(p.key) && can(p.key));

    /* ===== Устройства и группы ===== */

    const deviceSpec = (id) => DEVICE_CATALOG[id] || { name: id, type: "camera" };
    function deviceRef(id) {
      const spec = deviceSpec(id);
      const type = DEVICE_TYPES[spec.type] ? spec.type : "camera";
      return { guid: id, name: spec.name, typeId: type, typeLabel: DEVICE_TYPES[type].label, deleted: Boolean(spec.deleted) };
    }
    // Действующий адрес устройства (§1): введённый в МИ, иначе из источника; удалённое — без адреса
    function addressOf(id) {
      const spec = deviceSpec(id);
      return spec.deleted ? null : spec.addressIm || spec.address || null;
    }
    function findNode(nodes, id) {
      for (const node of nodes) {
        if (node.id === id) return node;
        const found = node.children ? findNode(node.children, id) : null;
        if (found) return found;
      }
      return null;
    }
    // Глубина группы в дереве: верхняя — 0; нет такой — 0
    function depthOf(nodes, id, depth) {
      for (const node of nodes) {
        if (node.isDevice) continue;
        if (node.id === id) return depth;
        const found = depthOf(node.children || [], id, depth + 1);
        if (found != null) return found;
      }
      return depth === 0 ? 0 : null;
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
    // Устройства вошедшего: по группам доступа его ролей, если у него есть права оператора
    const myAccessibleDevices = (roles) => (operatorRights() ? accessibleDevices(roles) : new Set());
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
    // Группы, куда входит устройство, — с предками: ссылка группы видна и при инциденте вложенной (§7)
    function groupsOfDevice(id) {
      const out = new Set();
      const walk = (nodes, path) =>
        nodes.forEach((node) => {
          if (node.isDevice) {
            if (node.id === id) path.forEach((g) => out.add(g));
          } else walk(node.children || [], path.concat(node.id));
        });
      walk(TREE, []);
      return out;
    }
    // Справочная ссылка (§7): область, группа с названием, прежняя площадка «не назначенной»
    function helpLinkView(l) {
      const group = l.groupGuid ? findNode(TREE, l.groupGuid) : null;
      return Object.assign({ icon: null }, l, {
        scope: l.scope,
        groupGuid: l.groupGuid || null,
        groupName: group ? group.name : null,
        legacySite: l.legacySite || null,
      });
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
    // Новый инцидент получает последнюю версию сценария своего правила (§14.5)
    function latestRow(guid) {
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
      auditAnswer(ev, actor, scriptOf(ev).steps.find((x) => x.id === body.stepId), body);
      const path = pathOf(ev);
      ev.viewStepId = path[Math.min(path.lastIndexOf(body.stepId) + 1, path.length - 1)];
      res.effects.filter((e) => e.type === "macro").forEach((e) => launchMacro(ev, actor, actorEngine, e));
      return res;
    }
    // Макрос — команда агенту объекта инцидента по uid макрокоманды (§14.5, D8–D9 плана 82).
    // Агента в прототипе нет: команда сразу «выполнена». Макрос без uid не исполняется — запись в журнал
    function launchMacro(ev, actor, actorEngine, effect) {
      if (!actorEngine.availability("run_macro", ev).ok) return;
      const name = effect.name;
      if (!effect.uid) {
        log(ev, actor, "workflow.journal.macro.unbound", { name });
        return;
      }
      log(ev, actor, "workflow.journal.macro.launched", { name });
      log(ev, actor, "workflow.journal.macro.done", { name });
      // Результат макроса — событием потока (§9, RULE-60); macroId — имя макроса из сценария
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
    function log(ev, whoId, template, vars, when, files) {
      ev.log.push(Object.assign({ at: when != null ? when : now(), whoId, k: template, v: vars || null }, files ? { files } : {}));
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
      // Условия правил по группе (§14.5, ARCH-15): устройство — в группе или во вложенной; глубина — сколько над группой групп
      deviceInGroup: (deviceId, groupId) => collectDeviceIds(findNode(TREE, groupId)).includes(deviceId),
      groupDepth: (groupId) => depthOf(TREE, groupId, 0),
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
      // Название дежурной группы правила (§8.1, М1) — снимок при приёме, у инцидента (ruleDutyGroupName)
      ruleGroupName: (ev) => ev.ruleDutyGroupName || ev.ruleDutyGroup,
      // Снимок названия (labelSnapshots машины) — текст на языке того, кто выполняет переход
      labelText: (key) => render(key),
      log,
      transferTargets: () => targets(),
      // Уровни справочника приоритетов (§2.5) — варианты формы смены приоритета (ТЗ-13), название — на языке сессии
      // Окна работ, пересекающиеся с инцидентом (§14.12): варианты поля «окно работ» формы закрытия
      maintenanceWindows: (ev) => windowsOfIncident(ev),
      inMaintenance: (ev) => windowsOfIncident(ev).length > 0,
      priorities: () => PRIORITIES.map((p) => ({ value: p.value, label: (p.name && (p.name[(session && session.preferences.locale) || "ru"] || p.name.ru)) || String(p.value) })),
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
      // Доставка уведомления (§9): получателей вычисляет машина (recipients). Оповещение оператору стенда — событие
      // потока; уведомление о закрытом «Ложной тревогой» соседе (about, notifySiblings, ARCH-15) — тоже; остальные
      // уведомления интерфейс выводит из событий о переходах
      deliver: (ev, recipients, { alert, transitionId, about, actor }) => {
        // Появление инцидента (intake.create): доставка — после записи события, вслед за incident.created (commitEvent);
        // оповещение «группа правила не может принять» — с названием группы (StreamTransitionIdPayload.groupName, М1)
        const born = [].concat(W.intake.create).includes(transitionId);
        if (born && intakeDeliveries) return intakeDeliveries.push(() => engineCtx.deliver(ev, recipients, { alert, transitionId, about, actor }));
        const extra = born && alert && ev.ruleDutyGroup ? { groupName: ev.ruleDutyGroupName } : {};
        if (alert && recipients.includes(ME)) emit("incident.alert", ev, "dispatcher", Object.assign({ transitionId }, extra));
        if (about && recipients.includes(ME)) emit("incident.sibling_closed", ev, actor, { siblingGuid: about.id, siblingNumber: about.number, closeResultId: about.closeResult });
      },
      // Инцидент изменился не своим переходом (действие мира touch): нарушение основного записано тому, кто был
      // в группе (recordBreach, §11.4, BUG-73), запись о закрытом «Ложной тревогой» соседе (notifySiblings, ARCH-15) — новая версия
      // и journal.appended всем, кому он виден, а не только адресату: карточка и выборка у них обновятся до следующего
      // действия, и оно не получит неожиданный 412
      onBreachShared: (ev, who) => {
        touch([ev]);
        emit("journal.appended", ev, who || "dispatcher", {});
      },
      // Карточку увели (§9): в событии — кто выполнил переход и какой, по нему клиент называет причину (BUG-86).
      // Только если она открыта у оператора стенда (контракт, BUG-105). Свой перерыв и выход карточку не уводят — в машине
      onEvict: (ev, who, transitionId, by) => {
        if (who === ME && session.openIncidentGuid === ev.id) emit("incident.card_evicted", ev, by || null, { transitionId });
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
      // Сброс — вход оператора и старт сервиса: молчание считается с этого момента — простой сервиса не молчание
      // операторов (§14.3, RULE-113)
      lastHeartbeat = now();
      serial.incident = 0;
      serial.macro = 0;
      serial.event = 0;
      serial.window = 0;
      auditActions = [];
      const data = JSON.parse(JSON.stringify(fixture));
      const delta = now() - Date.parse(data.capturedAt);
      const abs = (time) => (time == null ? null : Date.parse(time) + delta);
      // «С какого времени» состояние человека (§23.2) — тоже снимок: сдвигается вместе с остальными временами
      OPERATORS = data.people.operators.map((o) =>
        Object.assign(o, o.stateSince ? { stateSince: abs(o.stateSince) } : {}, o.lastSeenAt ? { lastSeenAt: abs(o.lastSeenAt) } : {})
      );
      GROUPS = data.people.dutyGroups.map((g) => Object.assign({ group: true }, g));
      ACTORS = OPERATORS.concat(GROUPS, data.people.system.map((a) => Object.assign({ system: true }, a)));
      DEVICE_TYPES = Object.fromEntries(data.deviceTypes.map((t) => [t.id, { label: t.label }]));
      DEVICE_CATALOG = Object.fromEntries(
        data.devices.map((d) => [
          d.id,
          // Адрес (§1, §19.1): из источника и введённый в МИ; удалённое устройство (deleted) — для сводки «устройство удалено»
          { name: d.name, type: d.type, position: d.position || null, thumbnailUrl: d.thumbnailUrl || null, address: d.address || null, addressIm: d.addressIm || null, deleted: Boolean(d.deleted) },
        ])
      );
      PLANS = data.plans || [];
      ACCESS_GROUPS = data.accessGroups || [];
      // У уровня — guid, как у уровня в базе сервера: по нему журнал настроек (priority:<guid>); в наборе его нет — постоянный по значению
      PRIORITIES = (data.priorities || [])
        .map((p) => Object.assign({ guid: `00000000-0000-4000-8000-${String(p.value).padStart(12, "0")}` }, p))
        .sort((a, b) => b.value - a.value);
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
      myDevices = myAccessibleDevices(rolesOverride || me.roles || []);
      SCENARIO_ROWS = Object.fromEntries(data.scenarios.rows.map((r) => [rowKey(r.guid, r.version), r]));
      RULES = (data.rules || []).map((r) => Object.assign({}, r, { createdAt: Date.parse(r.createdAt) || 0 }));
      // Окна набора — тоже снимок: времена сдвигаются вместе с остальными
      MAINT = (data.maintenanceWindows || []).map((w) =>
        Object.assign({}, w, { startsAt: abs(w.startsAt), endsAt: abs(w.endsAt), createdAt: abs(w.createdAt), endedEarlyAt: abs(w.endedEarlyAt || null) })
      );
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
        // Событие, номер его тревоги и правило-победитель (§14.5). Инцидент набора без события — сам себе событие
        eventGuid: inc.eventGuid || uuid("e", ++serial.event),
        alarmNumber: inc.alarmNumber || inc.number,
        // Правила уже нет в наборе — null, как у сервера при удалённом правиле (контракт IncidentCard.ruleGuid)
        ruleGuid: inc.ruleGuid && RULES.some((r) => r.guid === inc.ruleGuid) ? inc.ruleGuid : null,
        typeId: inc.eventType.id,
        typeGuid: inc.eventType.guid,
        type: inc.eventType.name,
        priority: inc.priority,
        priorityManual: Boolean(inc.priorityManual),
        occurredAt: abs(inc.occurredAt),
        deviceIds: inc.devices,
        cameras: camerasOf(inc.devices[0]),
        media: inc.media,
        state: inc.state,
        owner: inc.owner,
        assignmentGroup: inc.assignmentGroup,
        // Последняя группа-адресат (§2.2, решение 16 плана 90) — из набора, как есть: по ней первое принятие ставит acceptedGroup
        lastAssignedGroup: inc.lastAssignedGroup || null,
        escalationLevel: inc.escalationLevel,
        transferCount: inc.transferCount || 0,
        holdReason: inc.holdReason,
        closeResult: inc.closeResult,
        massCause: inc.closeCause,
        closeCauseLabel: inc.closeCauseLabel || null,
        closeComment: inc.result,
        closedBy: inc.closedBy,
        closedAt: abs(inc.closedAt),
        // Первое принятие (§2.2): кто и когда первым взял; закрытый без взятия — без реакции
        acceptedAt: abs(inc.acceptedAt),
        acceptedBy: inc.acceptedBy || null,
        // Дежурная группа до принятия (§2.2, решение 16 плана 90) — из набора, как есть
        acceptedGroup: inc.acceptedGroup || null,
        noReaction: Boolean(inc.noReaction),
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
      // События набора — из инцидентов: первым — тот, чей номер — номер тревоги, затем по номеру
      EVENTS = new Map();
      pendingIntake.clear();
      intakeLog = [];
      events.forEach((ev) => {
        const known = EVENTS.get(ev.eventGuid) || { guid: ev.eventGuid, typeId: ev.typeId, devices: ev.deviceIds, alarmNumber: ev.alarmNumber, incidentIds: [] };
        known.incidentIds.push(ev.id);
        EVENTS.set(ev.eventGuid, known);
      });
      const numbers = new Map(events.map((ev) => [ev.id, ev.number]));
      const numberOf = (id) => Number(String(numbers.get(id)).replace(/\D/g, "")) || 0;
      EVENTS.forEach((e) => e.incidentIds.sort((x, y) => (numbers.get(y) === e.alarmNumber) - (numbers.get(x) === e.alarmNumber) || numberOf(x) - numberOf(y)));
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
        // Когда потеряна связь (§12.3); null — связь есть
        linkLostAt: null,
      };
      SIM = opts.colleagues ? JSON.parse(JSON.stringify(opts.colleagues.SIM)) : { enabled: false };
      Object.keys(colleagueIdleSince).forEach((id) => delete colleagueIdleSince[id]);
      // Последний признак активности коллеги из набора (§12.3): его сессия молчит с этого момента
      OPERATORS.forEach((o) => o.id !== ME && o.lastSeenAt != null && (colleagueIdleSince[o.id] = o.lastSeenAt));
      // Перерывы коллег из набора — с их начала (stateSince); срок — по настройкам на момент загрузки (§12.2)
      breaks = {};
      statsCache = new Map();
      OPERATORS.forEach((o) => o.id !== ME && o.agentState === "not_ready" && breakStarted(o.id, o.reasonId, o.stateSince != null ? o.stateSince : now()));
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
    // rowForm — форма в строке очереди: варианты людей (source: transferTargets) не несёт — их список длинный и
    // нужен только при открытии формы, клиент берёт его из карточки (решение 74)
    function formView(tr, ev, surface, rowForm = false) {
      if (!tr || !tr.form) return {};
      const f = engine.form(tr.form, ev, { surface });
      const fieldOptions = {};
      const fieldRules = {};
      f.fields.forEach((field) => {
        fieldRules[field.name] = field.rules;
        if (!field.options) return;
        if (rowForm && field.source === "transferTargets") return;
        fieldOptions[field.name] = {
          options: field.options.map((o) => {
            const reason = o.why ? say([o.why]) : null;
            // Предупреждение варианта (§2.2, ARCH-15) — первое подходящее из машины; выбрать вариант не мешает
            const warning = say(o.warning);
            return Object.assign(
              { id: o.id, label: render(o.label), disabled: Boolean(o.disabled), reason: reason ? reason.text : null, warning },
              o.forValues ? { forValues: o.forValues } : {},
              o.commentRequired ? { commentRequired: true } : {},
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
            placement: a.placement || null,
            danger: Boolean(a.danger),
            bulkAllowed: Boolean(tr && tr.bulk && tr.bulk.allowed),
          },
          a.enabled ? formView(tr, ev, surface, surface === "queue") : {}
        );
      });
    }

    function badgeView(ev) {
      const b = engine.badge(ev);
      return { label: render(b.label[0], b.label[1]), style: b.style, template: b.label[0], vars: b.label[1] || {} };
    }

    // Соседи — инциденты того же события, кроме самого (§1, §14.5, факт siblingsOf машины). Только видимые
    // оператору: невидимый сосед не даёт ни номера, ни числа, ни статуса тревоги (§5, ARCH-15)
    const siblingsOf = (ev) => events.filter((e) => e.eventGuid === ev.eventGuid && e.id !== ev.id && canSee(e));

    function summary(ev, surface) {
      const src = eventSource(ev);
      return {
        guid: ev.id,
        number: ev.number,
        eventGuid: ev.eventGuid,
        alarmNumber: ev.alarmNumber,
        ruleGuid: ev.ruleGuid || null,
        occurredAt: iso(ev.occurredAt),
        createdAt: iso(ev.createdAt),
        eventType: { guid: ev.typeGuid, id: ev.typeId, name: ev.type },
        priority: ev.priority,
        // Ручной приоритет (ТЗ-13): автоматика его не меняет, переоткрытие сохраняет
        priorityManual: Boolean(ev.priorityManual),
        // Окна работ (ТЗ-21): создан в окне при mark; закрыт «Плановой проверкой» со ссылкой на окно
        maintenanceWindowId: ev.maintenanceWindowId || null,
        closeMaintenanceWindowId: ev.closeMaintenanceWindowId || null,
        sourceGroup: sourceGroupOf(ev),
        sourceDeviceTypeId: src ? deviceRef(src).typeId : null,
        // Источник и его действующий адрес — на момент чтения, не снимок события (§14.5, план 87а)
        source: src ? deviceRef(src) : null,
        address: src ? addressOf(src) : null,
        state: ev.state,
        stateCategory: STATES[ev.state].category,
        ownership: engine.ownership(ev),
        // Фильтры очереди, которые инцидент проходит для читающего (§7, план 87в): «Мои» и «Чужие» зависят от него
        filters: engine.queueFilters(ev),
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
        closeCauseLabel: ev.closeCauseLabel || null,
        closeResultLabel: ev.closeResult ? render(engine.closeResultLabel(ev)) : null,
        closedAt: iso(ev.closedAt),
        // Первое принятие (§2.2, план 90): ставит эффект машины markAccepted, потом не меняется
        acceptedAt: iso(ev.acceptedAt),
        acceptedBy: actorRef(ev.acceptedBy),
        // Дежурная группа до принятия (§2.2, решение 16 плана 90): ставят markAccepted и markNoReaction машины, потом не меняется
        // Удалённая группа остаётся группой: kind — duty_group, название — её id, как в ленте
        acceptedGroup: ev.acceptedGroup && !findActor(ev.acceptedGroup) ? { id: ev.acceptedGroup, kind: "duty_group", name: ev.acceptedGroup, role: "" } : actorRef(ev.acceptedGroup),
        timer: timerState(ev),
        holdTimer: holdTimerState(ev),
        slaBreached: Boolean(ev.slaBreached),
        breaches: (ev.breaches || []).map((b) => ({ kind: b.kind, at: iso(b.at), owner: actorRef(b.owner) })),
        linkedTo: ev.linkedTo || null,
        // Сколько привязанных — те же, что в GET …/linked: только видимые оператору (§5, ARCH-08 в15)
        linkedCount: events.filter((e) => e.linkedTo === ev.id && canSee(e)).length,
        // «Событие: ещё N» в строке очереди — видимые незакрытые соседи (§7, ARCH-15 В5)
        siblingCount: siblingsOf(ev).filter((e) => !engine.isDone(e)).length,
        scenarioProgress: progressOf(ev),
        scenarioTitle: rowOf(ev).name == null ? null : rowOf(ev).name,
        mediaKinds: ev.media === "video" ? ["video"] : ev.media === "map" ? ["map"] : ["video", "map"],
        schemaVersion: W.schema.version,
        version: String(ev.version),
        // Последний номер записи журнала (seq): его клиент присылает в journalSeen у закрытия (§14.1, RULE-142)
        journalSeq: ev.log.length,
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
        // Порядковый номер записи инцидента (§14.1, RULE-142): растёт с каждой записью, и у записанных задним числом
        seq: i + 1,
        at: iso(entry.at),
        actor: actorRef(entry.whoId, entry.who),
        kind: entryKind(entry),
        templateKey: entry.k,
        vars: entry.v || {},
        text: render(entry.k, entry.v),
        ...(entry.files ? { attachments: entry.files.map((f) => Object.assign({}, f)) } : {}),
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
          expected: snapshotOf(max == null ? matched : matched.slice(0, max)),
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
        // Правило, по которому создан инцидент (§14.5): название — для оператора; правила нет в наборе — null
        ruleName: (RULES.find((r) => r.guid === ev.ruleGuid) || {}).name || null,
        // Доступные действия карточки уже посчитаны в summary — условия машины второй раз не вычисляются
        note: noteView(ev, base.actions.filter((a) => a.enabled).map((a) => a.id)),
        devices: deviceIds.filter((id) => myDevices.has(id)).map(deviceRef),
        scenario: scenarioView(ev),
        journal: journalView(ev),
        media: mediaView(ev),
        result: ev.closeComment || null,
        alarm: alarmView(ev),
        maintenanceWindows: windowsOfIncident(ev).map((w) => ({ id: w.id, description: w.description, startsAt: iso(w.from), endsAt: iso(w.to) })),
      });
    }

    // Тревога инцидента в карточке (§5, §7, ARCH-15): номер, статус и соседи — все видимые, и закрытые, по номеру.
    // Статус вычисляется по себе и видимым соседям: «закрыта», когда закрыты все; ложная — все «Ложной тревогой»
    function alarmView(ev) {
      const siblings = siblingsOf(ev).sort(byNumber);
      const all = [ev].concat(siblings);
      const closed = all.every((e) => engine.isDone(e));
      return {
        eventGuid: ev.eventGuid,
        number: ev.alarmNumber,
        status: closed ? "closed" : "open",
        allFalseAlarm: closed && all.every((e) => engine.closedFalseAlarm(e)),
        siblings: siblings.map((e) => ({
          guid: e.id,
          number: e.number,
          scenarioTitle: rowOf(e).name == null ? null : rowOf(e).name,
          state: e.state,
          badge: badgeView(e),
          owner: actorRef(e.owner),
          closeResultLabel: e.closeResult ? render(engine.closeResultLabel(e)) : null,
        })),
      };
    }

    // План инцидента: тот, где стоит источник или первое устройство события с положением; ни у кого
    // положения нет — плана нет (площадки у инцидента нет, §1)
    function planOf(ev) {
      const ids = [eventSource(ev), ...(ev.deviceIds || []), ...(ev.cameras || [])].filter(Boolean);
      const placed = ids.map((id) => deviceSpec(id).position).find(Boolean);
      return (placed && PLANS.find((p) => p.id === placed.plan)) || null;
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
      const mine = GROUPS.filter((g) => membersOf(g).includes(ME));
      // Начало хранимого состояния (§22.8) — по журналу действий, как «с какого времени» экрана старшего (§23.2);
      // у производного «Занят» — начало «Готов». Записей и времени в наборе нет — поля нет
      const since = stateSinceOf(ME, session.agentState);
      return Object.assign({
        operator: {
          guid: ME,
          name: me.name,
          role: me.role,
          dutyGroupGuids: mine.map((g) => g.id),
          // Названия дежурных групп — для меню пользователя (§22.8), в том же порядке
          dutyGroups: mine.map((g) => ({ id: g.id, name: g.name })),
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
      }, since != null ? { agentStateSince: iso(since) } : {});
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
      // Порядок блока «Мне на принятие» принимается всегда, в обход operatorMayChange, — только он (§7)
      if (q.sort && q.sort === W.display.inboxBlock.sort && s.keys[q.sort]) return q.sort;
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

    // Поиск — по номеру, номеру тревоги (§7, ARCH-15), типу, названию устройства-источника и его действующему
    // адресу; у удалённого устройства ни название, ни адрес не ищутся (§7, план 87а). Поля — по отдельности:
    // строка не находится на стыке двух. Привязанные инциденты в списках не видны, но ищутся: их находит строка
    // основного, в ней — кто из привязанных подошёл (matchedLinked)
    const hit = (e, needle) => {
      const src = eventSource(e);
      const alive = src && !deviceSpec(src).deleted;
      return [e.number, e.alarmNumber, e.type, alive ? deviceSpec(src).name : null, alive ? addressOf(src) : null].some((v) => v != null && String(v).toLowerCase().includes(needle));
    };
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
        // Сценарий — свой у каждого инцидента: соседи по событию различаются только им (§19.2, ARCH-15)
        if (q.scenarioGuid && q.scenarioGuid !== "all" && !String(q.scenarioGuid).split(",").includes(e.scenarioGuid)) return false;
        // Приоритеты — список уровней через запятую
        if (q.priority != null && q.priority !== "" && !String(q.priority).split(",").some((v) => e.priority === Number(v))) return false;
        // Без строк одного из фильтров (блок «Мне на принятие» выбран отдельно, §7)
        if (q.exceptFilter && filters.get(e).includes(q.exceptFilter)) return false;
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
      const size = Math.min(200, Math.max(1, Number(q.pageSize) || PAGE_SIZE));
      const pages = Math.max(1, Math.ceil(list.length / size));
      const n = Math.min(Math.max(1, Number(q.page) || 1), pages);
      // На какой странице выбранный инцидент — если он виден при этих фильтрах (null — не виден)
      const idx = q.focusGuid ? list.findIndex((e) => e.id === q.focusGuid) : -1;
      const focusPage = idx === -1 ? null : Math.floor(idx / size) + 1;
      const found = (e) => (q.search ? linkedHits(e, String(q.search).toLowerCase()).map((x) => ({ guid: x.id, number: x.number })) : []);
      const item = (e) => Object.assign(summary(e, "queue"), found(e).length ? { matchedLinked: found(e) } : {});
      return { items: list.slice((n - 1) * size, n * size).map(item), total: list.length, page: n, pageSize: size, focusPage };
    }


    // Сужения очереди, общие для списка и счётчиков: всё, кроме filter, page и порядка
    function narrowed(q) {
      const n = { scenarioGuid: q.scenarioGuid, sourceGroupGuid: q.sourceGroupGuid, eventTypeGuid: q.eventTypeGuid, deviceTypeId: q.deviceTypeId, search: q.search, priority: q.priority };
      Object.keys(n).forEach((k) => (n[k] == null || n[k] === "") && delete n[k]);
      return n;
    }
    const unknownFilter = (id) => id != null && id !== "" && !W.queueFilters.some((f) => f.id === id);

    function counters(q) {
      const out = {};
      // Числа состояний — по тем же сужениям, что список, кроме самого фильтра (§19.2, §7)
      const list = visible(narrowed(q));
      const passed = list.map((e) => engine.queueFilters(e));
      // У фильтров с завершёнными (counted: false) счётчика нет: их число — total страницы списка (§7)
      W.queueFilters.filter((f) => f.counted !== false).forEach((f) => (out[f.id] = passed.filter((ids) => ids.includes(f.id)).length));
      return out;
    }

    // Числа приоритетов под фильтром: те же сужения, кроме самих приоритетов; нет ключа — 0
    function priorityCounters(q) {
      const f = W.queueFilters.find((x) => x.id === (q.filter || "open"));
      if (!f || f.counted === false) return badRequest();
      const out = {};
      const n = narrowed(q);
      delete n.priority;
      visible(Object.assign(n, { filter: f.id })).forEach((e) => (out[String(e.priority)] = (out[String(e.priority)] || 0) + 1));
      return { status: 200, body: out };
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

    // Справочник сценариев для фильтра очереди: сценарии правил и открытых инцидентов, по названию (§19.2).
    // Без прав оператора — пуст, как очередь
    function scenarioRefs() {
      if (!operatorRights()) return [];
      const seen = new Map();
      const add = (guid) => {
        const name = scenarioName(guid);
        if (guid && name != null && !seen.has(guid)) seen.set(guid, { guid, name });
      };
      RULES.forEach((r) => (r.scenarios || []).forEach(add));
      events.filter((e) => canSee(e) && !isDone(e)).forEach((e) => add(e.scenarioGuid));
      return [...seen.values()].sort((x, y) => x.name.localeCompare(y.name, "ru"));
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
    // Меняет ли переход версию записи (concurrency машины): нет — только запись в журнал
    const bumps = (tr) => !tr || !tr.concurrency || tr.concurrency.bumpsVersion !== false;
    // Версия записи (§14.1): ETag карточки — поле version в кавычках. Её читают GET и кэш клиента; действие оператора
    // её не сверяет (RULE-142): номер растёт от всего — от эскалации, записи о нарушении, чужого комментария
    const etag = (ev) => `"${ev.version}"`;

    // Что видел оператор (§14.1, RULE-142): переход сверяет то, на чём основано решение, — concurrency.expects машины:
    // состояние, адресата (определение addressee: владелец, а пока группа не приняла — группа; "" — ничей) и у закрытия
    // новые записи журнала после journalSeen. Совпало — переход выполняется при любой версии
    const expectsOf = (tr) => (tr && tr.concurrency && tr.concurrency.expects) || [];
    const addresseeOf = (ev) => engine.addressee(ev) || "";
    // Вид записи журнала: таймеров и системы — system, остальные — transition, если не задан свой (macro, external —
    // итог макроса и команды: новым событием не считается, RULE-144)
    const entryKind = (entry) => entry.kind || (entry.whoId === "dispatcher" || entry.whoId === "system" || (!entry.whoId && entry.who) ? "system" : "transition");
    // Новое событие для закрытия (journalNews машины): запись после journalSeen, не своя и вида из списка машины —
    // записи таймеров и системы о нарушении и потолке состояние и адресата не меняют, их не считаем
    const NEWS = (W.invariants.optimisticLocking || {}).journalNews || { kinds: [] };
    // Запись из templates — новое событие при любом виде: «сосед закрыт ложной тревогой» пишет система (logSiblings)
    const isNews = (e) => NEWS.kinds.includes(entryKind(e)) || (NEWS.templates || []).includes(e.k);
    const newsSince = (ev, seen) => ev.log.slice(Math.max(0, Number(seen) || 0)).some((e) => !(NEWS.ownExcluded && e.whoId === ME) && isNews(e));
    // Снимок строки для выборки: что сверит массовое действие и объединение (expected)
    const seenOf = (ev) => ({ state: ev.state, addressee: addresseeOf(ev), journalSeq: ev.log.length });
    const snapshotOf = (list) => Object.fromEntries(list.map((e) => [e.id, seenOf(e)]));
    // Что изменилось из того, что видел оператор: addressee | state | news; совпало всё — null. Не присланное не сверяется.
    // Закрытый теперь — всегда state: это решает changedProblem, через неё идут все отказы
    function changedOf(ev, expects, seen) {
      const s = seen || {};
      const stateChanged = expects.includes("state") && s.state != null && s.state !== ev.state;
      if (expects.includes("addressee") && s.addressee != null && String(s.addressee) !== addresseeOf(ev)) return "addressee";
      if (stateChanged) return "state";
      // Смена приоритета сверяет уровень, который видел оператор (RULE-143): две смены наперегонки не затирают друг друга
      if (expects.includes("priority") && s.priority != null && Number(s.priority) !== ev.priority) return "priority";
      if (expects.includes("news") && s.journalSeq != null && newsSince(ev, s.journalSeq)) return "news";
      return null;
    }
    // Отказ 412 INCIDENT_CHANGED: текст называет, что изменилось (§22.6) — уже ведёт другой человек (он владелец), передан
    // человеку, который ещё не принял, или группе, в общей очереди, другое состояние (закрыт — всегда так), новое событие,
    // сменился основной выборки
    function changedProblem(ev, found) {
      const who = addresseeOf(ev);
      // Закрытый теперь — всегда state, кто бы ни звал (переход, выборка, объединение, ответ на шаг — BUG-125):
      // закрывший коллега сменил и адресата, а оператору важнее, что инцидент закрыт
      const what = isDone(ev) && found !== "news" && found !== "primary" ? "state" : found;
      let why;
      if (what === "news") why = ["workflow.error.changed.news"];
      else if (what === "primary") why = ["workflow.error.changed.primary"];
      else if (what === "priority") why = ["workflow.error.changed.priority", { priority: priorityName(ev.priority) }];
      else if (what === "state") why = ["workflow.error.changed.state", { state: [STATES[ev.state].labelKey] }];
      else if (!who) why = ["workflow.error.changed.queue"];
      // Ведёт — состояние, где адресат — сам оператор (owner: operator машины); ждёт принятия (transfer_target) — передан
      else why = [STATES[ev.state].owner === "operator" ? "workflow.error.changed.taken" : "workflow.error.changed.addressed", { who: actorRef(who).name }];
      return problem(412, "INCIDENT_CHANGED", why, { details: { changed: what }, current: card(ev) });
    }
    // Клиент обязан сказать, что видел: не прислал — 428 (§14.1)
    const expectedRequired = () => problem(428, "PRECONDITION_REQUIRED", ["workflow.error.expected_required"]);

    // Переход — одно событие потока (§9, RULE-60): какой, чем вызван и что было → стало. Что сказать
    // наблюдателям, клиент берёт из машины (ui.observerNotice), а не из имени перехода
    function emitTransition(ev, transitionId, actorId, facts) {
      const f = facts || { from: {}, to: {} };
      // В аудит — до потока: поток не говорит об инцидентах вне групп доступа, аудит пишет всё (§12.4)
      auditTransition(ev, transitionId, actorId, f);
      emit("incident.transitioned", ev, actorId, transitionPayload(ev, transitionId, f));
    }
    // StreamTransitionedPayload: и у incident.transitioned, и у incident.created — какой переход появления (М1)
    function transitionPayload(ev, transitionId, f) {
      const tr = engine.transition(transitionId);
      return {
        transitionId,
        trigger: tr ? tr.trigger : null,
        state: { from: f.from.state || null, to: ev.state },
        owner: { from: actorRef(f.from.owner), to: actorRef(ev.owner) },
        addressee: actorRef(engine.addressee(ev)),
        // Адресовано смотрящему — ему или его дежурной группе (isSelf машины): поток у каждого оператора свой
        addressedToMe: engine.isSelf(engine.addressee(ev)),
        breach: f.breach || null,
      };
    }

    // Сбой вычисления — ошибка сервера: 500, текст ошибки в тело не попадает (CEL.md, PROC-44 в3)
    const internalProblem = () => problem(500, "INTERNAL_ERROR", ["workflow.error.transition_failed", { error: "internal error" }]);
    // Эффекты: ядро вернуло ошибку вместо отказа
    const evaluationFailed = (r) => r.why[0] === "workflow.error.transition_failed";
    // Условия и правила формы: ядро её бросает. Что бросил не CEL — ошибка самого прототипа, ей ответа нет
    const failedToCompute = (err) => {
      if (err.name !== "EvaluationError") throw err;
      return internalProblem();
    };
    // Не выполнено: сбой вычисления или форма не прошла — 422. Различаются по причине, а не по code: у пропущенного поля
    // своего кода нет, FORM_FIELD_REQUIRED — код по умолчанию
    const runFailure = (r) => (evaluationFailed(r) ? internalProblem() : problem(422, r.code || "FORM_FIELD_REQUIRED", r.why));

    function runTransition(id, ev, formValues, surface) {
      const tr = engine.transition(id);
      // Объединение — только через свой маршрут, выбор основного не дело клиента (RULE-101, решение 49)
      if (!tr || (tr.bulk && tr.bulk.mode === "merge")) return problem(404, "NOT_FOUND", ["workflow.error.unknown_action"]);
      const check = engine.availability(id, ev, { form: formValues, surface });
      if (!check.ok) return guardProblem(check);
      const before = ev.log.length;
      const r = engine.run(id, ev, formValues, { surface });
      if (!r.ok) return runFailure(r);
      // Запись только в журнал (concurrency.bumpsVersion: false машины, ТЗ-18) — версия прежняя
      if (bumps(tr)) touch([ev]);
      emitTransition(ev, id, ME, r.facts);
      // Последний адресат оператора — из поля адресата формы перехода, если оно есть (§8.2)
      const targetField = ((W.forms.find((f) => f.id === tr.form) || {}).fields || []).find((f) => f.source === "transferTargets");
      if (targetField && formValues && formValues[targetField.name]) session.lastTransferTargetId = formValues[targetField.name];
      const externalEffects = (r.external || []).map((x) => ({ fn: x.fn, target: x.target, status: "queued" }));
      // Ответ — заново после системных переходов, которые выполнит handle (ARCH-10): журнал — и их записи
      const view = () => ({ incident: card(ev), navigate: r.navigate || null, journalEntries: journalView(ev).slice(before), externalEffects, canceledTimerTrigger: r.canceled || null });
      return { status: 200, body: view(), view };
    }

    // Основной при объединении (§11) — mergePrimary машины. Ни одного подходящего — null. Выборка — по возрастанию
    // номера, а не в порядке отметки: у совсем равных основной — меньший номер, как в модели Quint
    const pickPrimary = (list) => engine.mergePrimary([...list].sort(byNumber));
    // Основной — всегда по §11.3 (mergePrimary машины): выбрать его клиент не может (RULE-101)
    function mergeIncidents(guids, expected) {
      const list = guids.map(find).filter(Boolean);
      if (list.length !== guids.length) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
      // Объединение — всё или ничего: у отмеченного после отметки другое состояние или адресат — не выполняется
      // (expected, §14.1, RULE-142); нет guid в снимке — не сверяется
      const expects = expectsOf(W.transitions.find((t) => t.bulk && t.bulk.mode === "merge"));
      const stale = list.map((e) => [e, changedOf(e, expects, (expected || {})[e.id])]).find(([, what]) => what);
      if (stale) return changedProblem(stale[0], stale[1]);
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
      if (!r.ok) return r.guard ? guardProblem(r) : evaluationFailed(r) ? internalProblem() : problem(422, "BULK_SELECTION_INVALID", r.why);
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
    // Кого касается действие на выборке (bulk.scope машины, §11.1, ARCH-15): primaryScenario — только отмеченных сценария
    // основного выборки (bulkPrimary машины, выборка — по возрастанию номера, как у объединения); остальные пропускаются
    // и не меняются. Без scope — все отмеченные. Основного нет (закрыть оператору нечего) — тоже все: действие
    // недоступно с причиной того, кто не проходит, а не «доступно» на пустой области
    function bulkScope(tr, list) {
      if (!tr || !tr.bulk || tr.bulk.scope !== "primaryScenario" || !list.length) return { list, skipped: [], primary: null };
      const primary = engine.bulkPrimary([...list].sort(byNumber));
      if (!primary) return { list, skipped: [], primary: null };
      const key = scenarioKey(primary);
      return { list: list.filter((e) => scenarioKey(e) === key), skipped: list.filter((e) => scenarioKey(e) !== key), primary };
    }
    function selectionActions(list) {
      const manual = W.transitions.filter((t) => t.trigger === "manual");
      return manual.map((tr) => {
        const mode = tr.bulk || { allowed: false };
        // Доступность и общая форма — только по тем, кого действие касается (bulk.scope, §11.1, ARCH-15)
        const scope = mode.allowed && mode.mode === "each_allowed" ? bulkScope(tr, list) : { list, skipped: [] };
        // По каждому отмеченному: доступно ли, а если нет — почему. Ни к одному не относится
        // (скрыто у каждого, как в карточке) — на панели не показывается
        const avail = scope.list.map((e) => [e, engine.availability(tr.id, e)]);
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
          ok && tr.form && mode.mode === "each_allowed" ? sharedForm(tr, scope, list.length) : {},
          // Сценарий основного выборки (bulk.scope): его клиент присылает в expectedScenario — основной сменился, действие
          // не выполняется (§11.1, RULE-142)
          scope.primary ? { scopeScenarioGuid: scenarioKey(scope.primary) } : {}
        );
      });
    }

    // Форма действия на выборке — одна на всех (§11, ARCH-08 в14): варианты полей — те, что есть у каждого
    // отмеченного, кого действие касается (выборка — из очереди); недоступный хоть у одного — недоступен; по умолчанию —
    // общее значение. Есть пропущенные другого сценария (bulk.scope, §11.1, ARCH-15) — пояснение называет, сколько
    // закроется и сколько останется открытыми
    function sharedForm(tr, scope, total) {
      const view = sharedFormOf(tr, scope.list);
      if (!scope.skipped.length) return view;
      const key = scenarioKey(scope.primary);
      // Ключ пояснения — машины (bulk.scopeNoteKey): по нему клиент узнаёт, что закроются не все отмеченные
      const note = say([tr.bulk.scopeNoteKey, { scenario: scenarioName(key) || key || "", n: scope.list.length, total, skipped: scope.skipped.length }]);
      return Object.assign(view, { formNote: { text: note.text, key: note.key, vars: note.vars } });
    }
    function sharedFormOf(tr, list) {
      const [first, ...rest] = list.map((e) => formView(tr, e, "queue"));
      const fieldOptions = {};
      Object.entries(first.fieldOptions).forEach(([name, f]) => {
        const others = rest.map((v) => v.fieldOptions[name] || { options: [] });
        const options = f.options
          .filter((o) => others.every((x) => x.options.some((y) => y.id === o.id)))
          .map((o) => {
            const same = [o].concat(others.map((x) => x.options.find((y) => y.id === o.id)));
            const off = same.find((y) => y.disabled);
            // Предупреждение — первое у отмеченных по порядку: хоть у одного есть — показывается
            const warned = same.find((y) => y.warning);
            return Object.assign({}, o, off ? { disabled: true, reason: off.reason } : {}, { warning: warned ? warned.warning : null });
          });
        const d = f.defaultValue;
        fieldOptions[name] = { options, defaultValue: d && others.every((x) => x.defaultValue === d) && options.some((o) => o.id === d && !o.disabled) ? d : null };
      });
      return { fieldOptions, fieldRules: first.fieldRules, formNote: first.formNote };
    }

    function selection(body) {
      // priority в теле — массив уровней; в запросе очереди — список через запятую
      const q = { filter: body.filter, exceptFilter: body.exceptFilter, search: body.search, sourceGroupGuid: body.sourceGroupGuid, eventTypeGuid: body.eventTypeGuid, scenarioGuid: body.scenarioGuid, deviceTypeId: body.deviceTypeId, priority: Array.isArray(body.priority) ? body.priority.join(",") : undefined };
      if (unknownFilter(body.exceptFilter)) return badRequest();
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
      return { status: 200, body: { incidentGuids: list.map((e) => e.id), expected: snapshotOf(list), truncated, actions: list.length ? selectionActions(list) : [] } };
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
          if (engine.agentReasonRequired(to) && !W.session.breakReasons.some((r) => r.id === body.reasonId)) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.reason_required"]);
          // Вход, выход, перерыв и возврат — в журнал действий (§12.4)
          audit(ME, to === "not_ready" ? "break" : to === "offline" ? "sign_out" : from === "offline" ? "sign_in" : "back", to === "not_ready" ? { reasonId: body.reasonId || undefined } : {});
          // Конец перерыва — снятие «перерыв затянулся» (§12.2): о своём перерыве оператору стенда ничего не приходит
          if (from === "not_ready") breakEnded(ME);
          if (to === "not_ready") {
            session.agentState = "not_ready";
            session.reasonId = body.reasonId || session.reasonId || null;
            breakStarted(ME, session.reasonId, now());
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
      ["GET", "/operator/incidents", (p, q) => (unknownFilter(q.exceptFilter) ? badRequest() : { status: 200, body: page(q) })],
      ["GET", "/operator/incidents/counters", (p, q) => ({ status: 200, body: counters(q) })],
      ["GET", "/operator/incidents/counters/priorities", (p, q) => priorityCounters(q)],
      ["POST", "/operator/incidents/selection", (p, q, body) => selection(body || {})],
      [
        "POST",
        "/operator/incidents/transitions/{transitionId}/bulk",
        (p, q, body) => {
          const guids = body.incidentGuids || [];
          // Контракт обещает uuid: иное — запрос не разобран, до всего остального, и ключ повтора не тратится (решение 95)
          if (!Array.isArray(guids) || !guids.every(isGuid)) return problem(400, "BAD_REQUEST", ["workflow.error.bad_request"]);
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
          // У действия с bulk.scope основной выбирается заново, по нынешним отмеченным: его сценарий — не тот, что назвала
          // форма (expectedScenario), — закрылся бы не тот сценарий. Не выполняется целиком, 412 INCIDENT_CHANGED
          // «основной сменился» (§11.1, ARCH-15, RULE-142): оператор открывает форму заново
          if (bulkTr && bulkTr.bulk.scope && body.expectedScenario != null) {
            const now = bulkScope(bulkTr, list).primary;
            if (!now || scenarioKey(now) !== body.expectedScenario) return changedProblem(now || list[0], "primary");
          }
          let navigate = null;
          const done = [];
          // Только те, кого действие касается (bulk.scope машины, §11.1, ARCH-15) — сервер проверяет сам, а не верит
          // панели: другой сценарий, чем у основного выборки, — в skipped, без изменений, кроме строки журнала открытого
          // соседа при ложной тревоге и её версии (RULE-138)
          const scope = bulkScope(bulkTr, list);
          const skipped = scope.skipped.map((ev) => ({ incidentGuid: ev.id, number: ev.number, reasonKey: bulkTr.bulk.skippedReasonKey }));
          scope.list.forEach((ev) => {
            // После отметки другое состояние или адресат (у закрытия — и новое событие) — не трогается: устаревшая
            // выборка не перебивает сделанное после неё (expected, §14.1, RULE-142). Эскалация без смены адресата не мешает
            const what = changedOf(ev, expectsOf(bulkTr), (body.expected || {})[ev.id]);
            if (what) {
              // Строке failed — Problem без карточки: актуальное клиент получит потоком и выборкой
              const problemBody = Object.assign({}, changedProblem(ev, what).body);
              delete problemBody.current;
              return failed.push({ incidentGuid: ev.id, problem: problemBody });
            }
            // Сбой вычисления — строка failed, остальные выполняются: выборка частично успешна
            let r;
            try {
              r = runTransition(p.transitionId, ev, body.formValues || {}, body.surface);
            } catch (err) {
              r = failedToCompute(err);
            }
            if (r.status === 200) {
              done.push(ev);
              navigate = r.body.navigate || navigate;
            } else failed.push({ incidentGuid: ev.id, problem: r.body });
          });
          const reply = () => {
            // Переход выполнен, а строку не собрать: это строка failed, ошибка всего ответа потеряла бы строки остальных
            const late = [];
            const succeeded = done.flatMap((ev) => {
              try {
                return [summary(ev, "queue")];
              } catch (err) {
                late.push({ incidentGuid: ev.id, problem: failedToCompute(err).body });
                return [];
              }
            });
            return { status: 200, body: { succeeded, failed: failed.concat(late), skipped, navigate } };
          };
          return Object.assign(reply(), { again: reply });
        },
      ],
      [
        "GET",
        "/operator/incidents/{incidentGuid}",
        (p) => {
          const ev = find(p.incidentGuid);
          return ev ? { status: 200, body: card(ev), headers: { ETag: etag(ev), "Cache-Control": "no-store" } } : problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
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
        (p, q, body) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          // Сверка того, что видел оператор (concurrency.expects, §14.1, RULE-142): не прислал — 428, изменилось — 412.
          // If-Match не проверяется. Переход объединения — только своим маршрутом: здесь 404 из runTransition
          const tr = engine.transition(p.transitionId);
          const expects = tr && !(tr.bulk && tr.bulk.mode === "merge") ? expectsOf(tr) : [];
          const b = body || {};
          if (expects.length) {
            // Что обязан прислать клиент — по expects перехода: state → expectedState, addressee → expectedAddressee,
            // priority → expectedPriority, news → journalSeen
            const field = { state: "expectedState", addressee: "expectedAddressee", priority: "expectedPriority", news: "journalSeen" };
            if (expects.some((k) => b[field[k]] == null)) return expectedRequired();
            const what = changedOf(ev, expects, { state: b.expectedState, addressee: b.expectedAddressee, priority: b.expectedPriority, journalSeq: b.journalSeen });
            if (what) return changedProblem(ev, what);
          }
          const res = runTransition(p.transitionId, ev, (body && body.formValues) || {}, body && body.surface);
          if (res.status !== 200) return res;
          const reply = () => ({ status: 200, body: res.view(), headers: { ETag: etag(ev) } });
          return Object.assign(reply(), { again: reply });
        },
      ],
      ["POST", "/operator/incidents/merge", (p, q, body) => mergeIncidents((body && body.incidentGuids) || [], body && body.expected)],
      [
        "DELETE",
        "/operator/incidents/{incidentGuid}/linked/{linkedGuid}",
        (p) => {
          // Сначала привязанный, затем основной: кто не видит основного, отсоединяет, как через POST (решение 104)
          const ev = find(p.linkedGuid);
          if (!ev || ev.linkedTo !== p.incidentGuid || ev.state !== "linked") return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          // «Отсоединить» — ручной переход машины из linked
          const detach = W.transitions.find((t) => t.id === "detach");
          const r = runTransition(detach.id, ev, {}, "card");
          if (r.status !== 200) return r;
          // Ответ — основной; не виден — карточка отсоединённого
          const reply = () => ({ status: 200, body: card(find(p.incidentGuid) || ev) });
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
          const detach = W.transitions.find((t) => t.id === "detach");
          const linked = events.filter((e) => e.linkedTo === primary.id && e.state === "linked" && canSee(e));
          const r = engine.runAll(detach.id, linked, {}, { surface: "card" });
          if (!r.ok) return r.guard || r.notFrom ? guardProblem(r) : runFailure(r);
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
        (p, q, body) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
          // Отвечает только тот, кому машина разрешает править сценарий (scenarioEdit, §10.4)
          // Что видел оператор (§14.1, RULE-142): владельца и ответ этого шага — его номер seq (RULE-146: время двух
          // ответов может совпасть). Не прислал — 428. Владелец другой — 412, как у перехода; шаг ответили после показа
          // (другая вкладка, двойное нажатие) — 409 STEP_CHANGED с актуальным сценарием. Версия не сверяется: запись
          // о нарушении или соседе ответу не мешает
          const b = body || {};
          if (b.expectedOwner == null || !("seenAnswer" in b)) return expectedRequired();
          if (String(b.expectedOwner) !== (ev.owner || "")) return changedProblem(ev, "addressee");
          if (!engine.canEditScenario(ev)) return problem(403, "PERMISSION_DENIED", ["workflow.error.read_only"]);
          const was = (ev.run.state || {})[b.stepId];
          if ((b.seenAnswer == null ? null : b.seenAnswer) !== ((was && was.seq) || null)) {
            const step = scriptOf(ev).steps.find((x) => x.id === b.stepId);
            // Кто ответил — по имени; автор без имени (ответ системы, нет в справочнике) — нейтральный текст без пустого «{who}»
            const who = was && was.by ? actorRef(was.by).name : "";
            const name = step ? stepName(step) : b.stepId;
            const why = who ? ["workflow.error.scenario.step_changed", { step: name, who }] : ["workflow.error.scenario.step_changed_anon", { step: name }];
            return problem(409, "STEP_CHANGED", why, { current: scenarioView(ev) });
          }
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
          return { status: 200, body: GROUPS.map((g) => ({ id: g.id, name: g.name, roles: (g.roles || []).slice(), userGroupIds: [], members: (g.members || []).slice(), memberIds: membersOf(g) })) };
        },
      ],
      // Люди поста (BUG-124): все, кого знает МИ, и я тоже — по ним настройки называют адресата по имени.
      // Давно не заходивший — stale в наборе
      [
        "GET",
        "/operator/admin/people",
        () => {
          if (!can("incident:schema:admin")) return problem(403, "PERMISSION_DENIED", ["workflow.error.no_schema_admin"]);
          return { status: 200, body: OPERATORS.map((o) => ({ id: o.id, name: o.name, stale: Boolean(o.stale) })) };
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
      // Аудит (§12.4): журнал действий и журнал настроек, каждый по своему праву (§5)
      ["GET", "/operator/admin/audit/actions", (p, q) => auditPage("actions", auditQuery(q))],
      ["GET", "/operator/admin/audit/actions/export", (p, q) => auditExport("actions", auditQuery(q))],
      ["GET", "/operator/admin/audit/settings", (p, q) => auditPage("settings", auditQuery(q))],
      ["GET", "/operator/admin/audit/settings/export", (p, q) => auditExport("settings", auditQuery(q))],
      ["GET", "/operator/admin/audit/incidents", (p, q) => auditSuggest("actions", { q: q.q, limit: q.limit }, auditActions.filter((r) => r.incidentGuid && r.incidentNumber).map((r) => ({ key: r.incidentGuid, at: r.at, text: r.incidentNumber, item: { guid: r.incidentGuid, number: r.incidentNumber } })))],
      [
        "GET",
        "/operator/admin/audit/people",
        (p, q) => {
          if (q.log != null && q.log !== "actions" && q.log !== "settings") return badRequest();
          const rows = q.log === "settings" ? settingsAudit.map((r) => ({ id: r.actorId, name: r.actorName, at: r.at })) : auditActions.filter((r) => r.personId).map((r) => ({ id: r.personId, name: r.personName, at: r.at }));
          return auditSuggest(q.log === "settings" ? "settings" : "actions", { q: q.q, limit: q.limit }, rows.map((r) => ({ key: r.id, at: r.at, text: r.name, item: { personId: r.id, personName: r.name } })));
        },
      ],
      ["GET", "/operator/admin/audit/objects", (p, q) => auditSuggest("settings", { q: q.q, limit: q.limit }, settingsAudit.filter((r) => q.objectType == null || r.objectType === q.objectType).map((r) => ({ key: `${r.objectType}|${r.objectId}`, at: r.at, text: r.objectName, item: { objectType: r.objectType, objectId: r.objectId, objectName: r.objectName } })))],
      [
        "GET",
        "/operator/admin/audit/settings/{id}",
        (p) => {
          if (!canAudit("settings")) return noAudit();
          const entry = settingsAudit.find((e) => e.id === p.id);
          return entry ? { status: 200, body: entry } : problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
        },
      ],
      [
        "GET",
        "/operator/admin/audit/usage",
        () => {
          if (!can("incident:schema:admin")) return noAudit();
          // Место в прототипе не кончается: уровень всегда ok
          const bytes = JSON.stringify(auditActions).length + JSON.stringify(settingsAudit).length;
          const day = auditActions.filter((r) => Date.parse(r.at) > now() - DAY_MS).length;
          return { status: 200, body: { bytes, rowsPerDay: day, level: "ok" } };
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
      ["GET", "/operator/reference/scenarios", () => ({ status: 200, body: scenarioRefs() })],
      [
        "GET",
        "/operator/reference/device-types",
        () => ({ status: 200, body: Object.entries(DEVICE_TYPES).map(([id, d]) => ({ id, label: d.label })) }),
      ],
      ["GET", "/operator/reference/source-groups", (p, q) => ({ status: 200, body: treeView(TREE, q.withCounters === "true") })],
      // Меню справки (§7, план 87а): с инцидентом — общие и ссылки групп, куда входит его источник (с вложенными);
      // инцидент не найден или не виден — только общие; «не назначена» в меню не попадает никогда.
      // Без инцидента — вкладка администрирования: весь справочник — только администратору схемы, иначе общие
      [
        "GET",
        "/operator/reference/help-links",
        (p, q) => {
          let keep;
          if (q.incidentGuid == null) keep = (l) => can("incident:schema:admin") || l.scope === "shared";
          else {
            const ev = events.find((e) => e.id === q.incidentGuid);
            const groups = ev && canSee(ev) ? groupsOfDevice(eventSource(ev)) : new Set();
            keep = (l) => l.scope === "shared" || (l.scope === "group" && groups.has(l.groupGuid));
          }
          return { status: 200, body: HELP_LINKS.filter(keep).map(helpLinkView) };
        },
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
    ].concat(MAINTENANCE_ROUTES(), opts.testSupport ? TEST_ROUTES() : []);

    /* ===== Тестовый стенд: только с testSupport, в боевой системе этих операций нет ===== */

    // Событие источника (§14.5): тип, устройства (первое — источник), площадка, время у источника. guid — от
    // источника (повтор приходит с тем же), нет — сервер даёт свой. Не годится — null
    function eventOf(spec) {
      const type = eventTypes().find((t) => t.id === spec.eventTypeId);
      const devices = Array.isArray(spec.deviceIds) ? spec.deviceIds : [];
      const badGuid = spec.eventGuid != null && !UUID.test(String(spec.eventGuid));
      if (!type || !devices.length || badGuid) return null;
      return {
        guid: spec.eventGuid || uuid("e", ++serial.event),
        type,
        devices: devices.slice(),
        occurredAt: spec.occurredAt ? Date.parse(spec.occurredAt) : now(),
      };
    }
    // Следующий номер инцидента: номера сквозные, INC-
    const nextNumber = () => Math.max(0, ...events.map((e) => Number(String(e.number).replace(/\D/g, "")) || 0)) + 1;

    // Инцидент события по правилу (§6.2, §14.5, RULE-61): запись из события, затем переход машины create — он ставит
    // владельца, уровень, норматив реакции и запись журнала. Сценарий — последняя версия, на ней инцидент и доигрывает.
    // В очередь не попадает: всё событие применяется вместе (commitEvent). Не создался — null
    /* ===== Окна плановых работ (§14.12, ТЗ-21) ===== */

    // Местные дата и время момента в поясе tz
    function zoneParts(ms, tz) {
      const f = new Intl.DateTimeFormat("en-CA", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });
      const o = Object.fromEntries(f.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
      return { y: +o.year, m: +o.month, d: +o.day, h: +o.hour, mi: +o.minute, s: +o.second };
    }
    const zoneOffset = (ms, tz) => {
      const p = zoneParts(ms, tz);
      return Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s) - Math.floor(ms / 1000) * 1000;
    };
    // Местное время → момент (§14.12, п. 3): двузначное — первое из двух, несуществующее — вперёд на величину перевода
    // (Temporal disambiguation: compatible)
    function zonedMs(y, m, d, h, mi, tz) {
      const local = Date.UTC(y, m - 1, d, h, mi);
      const before = local - zoneOffset(local - 864e5, tz);
      const after = local - zoneOffset(local + 864e5, tz);
      const fits = (c) => c + zoneOffset(c, tz) === local;
      if (fits(before) && fits(after)) return Math.min(before, after);
      if (fits(before)) return before;
      if (fits(after)) return after;
      return before;
    }
    // Интервалы окна вокруг момента at (§14.12): разовое — [начало, конец); повтор — дни D−1 и D местной даты at,
    // интервал дня через полночь кончается назавтра; всё обрезано рамкой [начало, конец)
    function windowIntervals(w, at) {
      const base = { id: w.id, device: w.deviceGuid || null, group: w.sourceGroupGuid || null, description: w.description || "" };
      if (!w.recurrence) return w.startsAt < w.endsAt ? [Object.assign({ from: w.startsAt, to: w.endsAt }, base)] : [];
      const tz = w.timeZone || "UTC";
      const p = zoneParts(at, tz);
      const hm = (t) => t.split(":").map(Number);
      const [sh, sm] = hm(w.recurrence.startTime);
      const [eh, em] = hm(w.recurrence.endTime);
      const overnight = eh * 60 + em <= sh * 60 + sm;
      const out = [];
      for (const k of [-1, 0]) {
        const day = new Date(Date.UTC(p.y, p.m - 1, p.d + k));
        if (!w.recurrence.days.includes(day.getUTCDay() || 7)) continue;
        const end = new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate() + (overnight ? 1 : 0)));
        const from = Math.max(w.startsAt, zonedMs(day.getUTCFullYear(), day.getUTCMonth() + 1, day.getUTCDate(), sh, sm, tz));
        const to = Math.min(w.endsAt, zonedMs(end.getUTCFullYear(), end.getUTCMonth() + 1, end.getUTCDate(), eh, em, tz));
        if (from < to) out.push(Object.assign({ from, to }, base));
      }
      return out;
    }
    // Вход отбора (intake.windows): интервалы всех окон организации на момент at — по началу, при равенстве по id
    const maintenanceIntervals = (at) =>
      MAINT.flatMap((w) => windowIntervals(w, at)).sort((a, b) => a.from - b.from || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    // Окна, пересекающиеся с инцидентом: устройство-источник и время события (карточка, форма закрытия)
    function windowsOfIncident(ev) {
      const src = eventSource(ev);
      if (!src || ev.occurredAt == null) return [];
      return engine.windowsCovering(maintenanceIntervals(ev.occurredAt), { guid: ev.eventGuid || "", eventType: ev.typeId, device: src, deviceType: deviceSpec(src).type, at: ev.occurredAt });
    }
    // Начало первого интервала окна (§14.12): у разового — начало; у серии — первый интервал дней повтора в рамке
    // (ищется по дням рамки, до недели вперёд); интервала нет — конец рамки
    function firstStart(w) {
      if (!w.recurrence) return w.startsAt;
      const found = [];
      for (let k = 0; k <= 8 && !found.length; k++) {
        const at = w.startsAt + k * 864e5;
        found.push(...windowIntervals(w, Math.min(at, w.endsAt - 1)).filter((x) => x.to > w.startsAt));
      }
      return found.length ? Math.min(...found.map((x) => x.from)) : w.endsAt;
    }
    // Состояние окна (§14.12): впереди — до начала первого интервала; идёт — от него до конца (у серии — и в
    // промежутках между интервалами); закончилось — после конца
    const windowStatus = (w) => (now() >= w.endsAt ? "ended" : now() < firstStart(w) ? "planned" : "active");
    /* ===== Состояние системы (§14.11, §20): что прототип знает — считает, остальное — числа стенда (demoFields) ===== */
    function systemStatus(q) {
      if (!can("incident:schema:admin")) return problem(403, "PERMISSION_DENIED", ["workflow.error.no_schema_admin"]);
      // Организация — из токена; параметров у запроса нет, чужую не запросить
      if (Object.keys(q || {}).length) return problem(400, "BAD_REQUEST", ["workflow.error.bad_request"]);
      const at = now();
      const MIN = 60000;
      const perMinute = Array.from({ length: 60 }, (_, i) => intakeLog.filter((t) => t > at - (60 - i) * MIN && t <= at - (59 - i) * MIN).length);
      const minIso = (list) => (list.length ? iso(Math.min(...list)) : null);
      const MB = 1048576;
      // Демо: размер базы растёт с числом инцидентов стенда; диск и прирост — правдоподобные числа
      const parts = [
        ["events", 180 * MB + events.length * 2048],
        ["incidents", 95 * MB + events.length * 6144],
        ["journal", 70 * MB + auditActions.length * 1024],
        ["comment_files", 40 * MB],
        ["maintenance_windows", MB + MAINT.length * 512],
      ].map(([name, bytes]) => ({ name, bytes }));
      const named = parts.reduce((s, x) => s + x.bytes, 0);
      const other = 48 * MB;
      const growthWeek = 210 * MB;
      const free = 50 * 1024 * MB;
      const audit = auditActions.map((r) => Date.parse(r.at)).concat(settingsAudit.map((r) => Date.parse(r.at)));
      const lastPurgeAt = at - 20 * MIN;
      return {
        status: 200,
        body: {
          at: iso(at),
          database: {
            scope: "server",
            bytes: named + other,
            growthDayBytes: 30 * MB,
            growthWeekBytes: growthWeek,
            diskFreeBytes: free,
            daysLeft: Math.floor(free / (growthWeek / 7)),
            searchIndex: "ready",
            parts: parts.sort((a, b) => b.bytes - a.bytes).concat({ name: "other", bytes: other }),
          },
          retention: {
            lastPurge: { at: iso(lastPurgeAt), incidents: 0, events: 0, streamEvents: 0 },
            nextPurgeAt: iso(lastPurgeAt + 60 * MIN),
            oldestEventAt: minIso(events.map((e) => e.createdAt).filter((x) => x != null)),
            oldestIncidentAt: minIso(events.map((e) => e.createdAt).filter((x) => x != null)),
            oldestAuditAt: minIso(audit.filter((x) => !Number.isNaN(x))),
          },
          server: {
            eventsPerMinute: perMinute,
            operatorsOnline: 1 + (SIM.enabled ? OPERATORS.filter((op) => op.id !== ME && !colleagueIdleSince[op.id]).length : 0),
            serverVersion: "prototype",
            workflowVersion: W.schema.version,
            maintenanceActive: MAINT.filter((w) => windowStatus(w) === "active").length,
          },
          demoFields: ["database", "retention.lastPurge", "retention.nextPurgeAt"],
        },
      };
    }

    /* ===== Смена и статистика: блок «Сейчас» (§23, план 90) ===== */

    // Текущая смена (§23.1): от последнего наступившего начала (входит в смену) до следующего (уже нет). Начала и
    // пояс — настройка поста shift машины; время суток → момент по правилам пояса на эту дату, как у окон работ (§14.12)
    function currentShift(at) {
      const tz = W.shift.timeZone;
      const p = zoneParts(at, tz);
      const moments = [];
      [-1, 0, 1].forEach((k) => {
        const day = new Date(Date.UTC(p.y, p.m - 1, p.d + k));
        W.shift.starts.forEach((hhmm) => {
          const [h, mi] = hhmm.split(":").map(Number);
          moments.push(zonedMs(day.getUTCFullYear(), day.getUTCMonth() + 1, day.getUTCDate(), h, mi, tz));
        });
      });
      moments.sort((a, b) => a - b);
      return { from: moments.filter((m) => m <= at).pop(), to: moments.find((m) => m > at), timeZone: tz };
    }
    // С какого времени (§23.2): последняя запись журнала действий (§12.4) о входе в хранимое состояние stored — вид записи —
    // переход состояния оператора машины в него (session.transitions: перерыв, возврат, вход, выход); на месте — ещё
    // восстановление связи (§12.3). До первой такой записи — время из набора (stateSince); не входил — null
    function stateSinceOf(id, stored) {
      const kinds = W.session.transitions.filter((t) => t.to === stored).map((t) => t.id);
      if (engine.onDuty(id)) kinds.push("link_restored");
      const last = auditActions.filter((r) => r.personId === id && kinds.includes(r.kind)).pop();
      if (last) return Date.parse(last.at);
      return (OPERATORS.find((o) => o.id === id) || {}).stateSince || null;
    }
    // Нет связи (§12.3): признак активности старше session.idleHoldSec — тот же порог, что у idle_hold. Возвращает
    // время последнего признака или null
    // «Нет связи» — состояние строки SupervisorNowRow.state контракта, не причина удержания с тем же id
    const NO_LINK = "no_link"; // SupervisorNowRow.state
    function linkLostAt(id) {
      const seen = id === ME ? lastHeartbeat : colleagueIdleSince[id];
      return seen != null && now() - seen >= W.session.idleHoldSec * 1000 ? seen : null;
    }
    // Состояние строки (§23.2): вышел и перерыв — хранимое; вошёл и молчит — «нет связи»; иначе хранимое или
    // производное «Занят» (session.states[].derived машины)
    function supervisorState(id) {
      const stored = agentStateOf(id);
      // Перерыв без связи — всё ещё перерыв, вышедший — вышел: «нет связи» — только у того, кто на месте (onDuty машины)
      const lost = engine.onDuty(id) ? linkLostAt(id) : null;
      if (lost != null) return { state: NO_LINK, since: lost };
      return { state: engine.shownAgentState(stored, id), since: stateSinceOf(id, stored) };
    }
    const breached = (e) => Boolean(e.slaBreached) || (e.breaches || []).length > 0;
    function median(xs) {
      if (!xs.length) return null;
      const s = xs.slice().sort((a, b) => a - b);
      const mid = Math.floor(s.length / 2);
      return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
    }
    /* ===== Затянувшийся перерыв (§12.2, §14.10, план 90, часть В) ===== */

    // Начало перерыва: срок — у причины в настройках сейчас; дальше смена срока и удаление причины его не меняют
    function breakStarted(id, reasonId, since) {
      const reason = W.session.breakReasons.find((r) => r.id === reasonId);
      breaks[id] = { since, reasonId: reasonId || null, maxMinutes: reason && reason.maxMinutes != null ? reason.maxMinutes : null, notified: false };
    }
    // Срок по времени вышел: с начала перерыва прошло не меньше срока. Без срока перерыв не затягивается
    function breakLate(id) {
      const b = breaks[id];
      return Boolean(b) && b.maxMinutes != null && now() >= b.since + b.maxMinutes * 60000;
    }
    // Кому оповещение: в прототипе поток один — у оператора стенда. Ему — с правом supervisor:view, не о себе и только
    // о людях из строк «Сейчас» (с incident:accept); без отбора по группам (решение 9 плана 90)
    const breakAudience = (id) => can("supervisor:view") && id !== ME && permsOf(id).includes("incident:accept");
    // Конец перерыва (вернулся или вышел из МИ): срок по времени вышел — снятие, даже если оповещение уйти не успело.
    // Без проверки incident:accept человека: его могли забрать во время перерыва, а лишнее снятие ничего не меняет (§12.2)
    function breakEnded(id) {
      if (breakLate(id) && can("supervisor:view") && id !== ME) emit("supervisor.break_overdue_cleared", null, null, { personId: id });
      delete breaks[id];
    }
    // Такт планировщика (§14.3): срок вышел — оповещение, одно на перерыв; пропущенное за простой — при догоне
    function breakTick() {
      Object.keys(breaks).forEach((id) => {
        const b = breaks[id];
        if (b.notified || !breakLate(id)) return;
        b.notified = true;
        if (breakAudience(id)) emit("supervisor.break_overdue", null, null, { personId: id, reasonId: b.reasonId, since: iso(b.since), maxMinutes: b.maxMinutes });
      });
    }

    // Строка оператора (§23.2): числа — по всем его инцидентам, а не по видимым старшему (решение 9 плана 90).
    // Привязанные — один раз, по основному: закрытые вместе с основным и в реакцию не идут
    function supervisorRow(id, shift) {
      const st = supervisorState(id);
      const reason = st.state === "not_ready" ? W.session.breakReasons.find((r) => r.id === reasonOf(id)) : null;
      const own = (state) => events.filter((e) => e.owner === id && e.state === state);
      const reactions = events.filter((e) => e.acceptedBy === id && e.acceptedAt != null && e.acceptedAt >= shift.from && !e.linkedTo).map((e) => (e.acceptedAt - e.createdAt) / 1000);
      return {
        person: actorRef(id),
        state: st.state,
        reasonId: reason ? reason.id : null,
        reasonLabel: reason ? render(reason.labelKey) : null,
        since: iso(st.since),
        // Срок перерыва вышел (§23.2): на перерыве и с его начала прошло не меньше срока — граница оповещения
        breakOverdue: st.state === "not_ready" && breakLate(id),
        dutyGroups: GROUPS.filter((g) => membersOf(g).includes(id)).map((g) => ({ id: g.id, name: g.name })),
        inProgress: own("in_progress").length,
        onHold: own("on_hold").length,
        overdue: own("in_progress").concat(own("on_hold")).filter(breached).length,
        closedThisShift: events.filter((e) => isDone(e) && e.closedBy === id && e.closedAt != null && e.closedAt >= shift.from && !e.linkedTo).length,
        medianReactionSec: median(reactions),
      };
    }
    // Открытые инциденты, видимые старшему, как в очереди (§5): сводка «Сейчас» и плитка «Открыто сейчас» (§23.2, §23.3)
    const visibleOpen = () => events.filter((e) => canSee(e) && engine.inQueueFilter(e, "open"));
    const SUMMARY_OF = { ready: "present", busy: "present", not_ready: "onBreak", [NO_LINK]: "noLink", offline: "signedOut" };
    function supervisorNow(q) {
      if (!can("supervisor:view")) return problem(403, "PERMISSION_DENIED", ["workflow.error.no_supervisor_view"]);
      const at = now();
      const shift = currentShift(at);
      // Строки — люди с правом incident:accept, как адресаты передачи (§8.1); фильтр — участники дежурной группы,
      // неизвестной группы — строк нет
      const group = q.dutyGroup ? GROUPS.find((g) => g.id === q.dutyGroup) : null;
      const people = OPERATORS.filter((o) => permsOf(o.id).includes("incident:accept")).filter((o) => !q.dutyGroup || (group && membersOf(group).includes(o.id)));
      const operators = people.map((o) => supervisorRow(o.id, shift));
      const summary = { present: 0, onBreak: 0, noLink: 0, signedOut: 0 };
      operators.forEach((r) => (summary[SUMMARY_OF[r.state]] += 1));
      // Ничьих и просрочено всего — по инцидентам, видимым старшему, как в очереди (§5); фильтр их не меняет
      const open = visibleOpen();
      summary.unowned = open.filter((e) => e.state === "new" || (e.state === "pending_acceptance" && !e.owner && Boolean(e.assignmentGroup))).length;
      summary.overdue = open.filter(breached).length;
      return { status: 200, body: { at: iso(at), shift: { from: iso(shift.from), to: iso(shift.to), timeZone: shift.timeZone }, summary, operators } };
    }

    /* ===== Смена и статистика: блок «За период» и выгрузка в CSV (§23.3, §23.4, план 90, часть Б) ===== */

    const STATS_PERIODS = { shift: null, today: 0, "7d": 6, "30d": 29 };
    const STATS_FILTERS = ["dutyGroup", "sourceGroup", "source", "eventType", "operator", "result", "maintenance"];
    const BREACH_KINDS = ["reaction", "resolution", "hold"];
    // Момент времени ISO 8601 (RFC 3339) с поясом; иначе NaN — неверный запрос
    const MOMENT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/i;
    const moment = (v) => (MOMENT.test(String(v)) ? Date.parse(v) : NaN);
    // Полночь местной даты момента at в поясе tz, сдвинутой на shiftDays суток: по правилам пояса на эту дату (§23.3)
    function zoneMidnight(at, tz, shiftDays) {
      const p = zoneParts(at, tz);
      return zonedMs(p.y, p.m, p.d + shiftDays, 0, 0, tz);
    }
    // Период запроса (§23.3): period или from и to, без них — 7d; обрезка — по началу хранения и «сейчас».
    // Неверный запрос — null (400)
    function statsPeriod(q) {
      const at = now();
      const tz = W.shift.timeZone;
      const custom = q.from != null || q.to != null;
      if (q.period != null && !(q.period in STATS_PERIODS)) return null;
      if (q.maintenance != null && q.maintenance !== "include" && q.maintenance !== "exclude") return null;
      if (custom && (q.from == null || q.to == null || q.period != null)) return null;
      let from = moment(q.from);
      let to = moment(q.to);
      if (custom && (Number.isNaN(from) || Number.isNaN(to) || from > to)) return null;
      if (!custom) {
        const back = STATS_PERIODS[q.period || "7d"];
        from = back == null ? currentShift(at).from : zoneMidnight(at, tz, -back);
        to = at;
      }
      const keepFrom = at - W.retention.closedIncidentsDays * DAY_MS;
      return { at, tz, keepFrom, from: Math.max(from, keepFrom), to: Math.min(to, at), fromClipped: from < keepFrom };
    }
    // Инциденты периода (§23.3): закрытые с closedAt в [from, to), видимые старшему, как в очереди (решение 3), без
    // привязанных — объединённые один раз, по основному
    const statsClosed = (from, to) => events.filter((e) => e.state === "closed" && e.closedAt != null && e.closedAt >= from && e.closedAt < to && canSee(e) && !e.linkedTo);
    // Фильтры — все сразу; окна работ по умолчанию не считаются; несуществующее значение — инцидентов нет
    function statsFilter(q) {
      const inGroup = q.sourceGroup != null ? new Set(collectDeviceIds(findNode(TREE, q.sourceGroup))) : null;
      return (e) =>
        (q.maintenance === "include" || !e.maintenanceWindowId) &&
        (q.dutyGroup == null || (q.dutyGroup === "none" ? !e.acceptedGroup : e.acceptedGroup === q.dutyGroup)) &&
        (!inGroup || inGroup.has(eventSource(e))) &&
        (q.source == null || eventSource(e) === q.source) &&
        (q.eventType == null || e.typeId === q.eventType) &&
        (q.operator == null || e.closedBy === q.operator) &&
        (q.result == null || e.closeResult === q.result);
    }
    // Время (решение 4): реакция — от появления до первого принятия, у закрытого без взятия её нет; закрытие — до closedAt
    const reactionOf = (e) => (e.acceptedAt != null && !e.noReaction ? (e.acceptedAt - e.createdAt) / 1000 : null);
    const resolutionOf = (e) => (e.closedAt - e.createdAt) / 1000;
    // Медиана и 90 % — как percentile_cont в PostgreSQL: место (n − 1) × p от нуля, между соседними — по прямой
    function percentile(xs, p) {
      if (!xs.length) return null;
      const s = xs.slice().sort((a, b) => a - b);
      const k = (s.length - 1) * p;
      const lo = Math.floor(k);
      return s[lo] + (s[Math.ceil(k)] - s[lo]) * (k - lo);
    }
    const timeOf = (xs) => ({ median: percentile(xs, 0.5), mean: xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null, p90: percentile(xs, 0.9) });
    const reactions = (list) => list.map(reactionOf).filter((x) => x != null);
    // Закрыт «Ложной тревогой» — определение closedFalseAlarm машины: плитка, график, причины ложных
    const isFalse = (e) => engine.closedFalseAlarm(e);
    function statsTotals(list, from, to) {
      return {
        from: iso(from),
        to: iso(to),
        incidents: list.length,
        falseAlarms: list.filter(isFalse).length,
        breached: list.filter(breached).length,
        reaction: timeOf(reactions(list)),
        resolution: timeOf(list.map(resolutionOf)),
      };
    }
    // Столбики (§23.3): по часам, если конец не позже того же местного времени через два дня после начала, иначе по
    // суткам пояса смены; первый и последний — неполные. Часы — настоящие: граница — следующий целый час по поясу
    function statsSeries(list, from, to, tz) {
      const p = zoneParts(from, tz);
      const hourly = to <= zonedMs(p.y, p.m, p.d + 2, p.h, p.mi, tz) + (from % 60000);
      const next = (t) => {
        if (!hourly) return zoneMidnight(t, tz, 1);
        const x = zoneParts(t, tz);
        return t - ((x.mi * 60 + x.s) * 1000 + (t % 1000)) + 3600000;
      };
      const buckets = [];
      for (let b = from; b < to; ) {
        const e = Math.min(next(b), to);
        const inside = list.filter((x) => x.closedAt >= b && x.closedAt < e);
        buckets.push({ from: iso(b), to: iso(e), notFalse: inside.filter((x) => !isFalse(x)).length, falseAlarms: inside.filter(isFalse).length, breached: inside.filter(breached).length });
        b = e;
      }
      return { granularity: hourly ? "hour" : "day", buckets };
    }
    const statsLocale = () => (session && session.preferences.locale) || "ru";
    const byLabel = (a, b) => (a == null || b == null ? (a == null) - (b == null) : a.localeCompare(b, statsLocale(), { sensitivity: "base", numeric: true }));
    // Название результата — по его labelKey в справочнике результатов, а не подпись по причине (labelByCause)
    function resultName(id) {
      const item = W.reasonCatalogs.close_result.items.find((i) => i.id === id);
      return item ? render(item.labelKey) : id;
    }
    // Причина закрытия (§23.3): название из справочника результата на языке запроса; нет в справочнике — снимок
    function causeName(e) {
      if (!e.massCause) return null;
      const result = W.reasonCatalogs.close_result.items.find((i) => i.id === e.closeResult);
      const catalog = result && result.causeCatalog ? W.reasonCatalogs[result.causeCatalog] : null;
      const item = catalog ? catalog.items.find((i) => i.id === e.massCause) : null;
      return item ? render(item.labelKey) : e.closeCauseLabel || null;
    }
    // Группы устройств, в которые устройство входит напрямую, по названию
    function deviceGroups(id) {
      const out = [];
      const walk = (nodes) => nodes.filter((n) => !n.isDevice).forEach((n) => ((n.children || []).some((c) => c.isDevice && c.id === id) && out.push(n), walk(n.children || [])));
      walk(TREE);
      return out.sort((a, b) => byLabel(a.name, b.name)).map((n) => ({ id: n.id, name: n.name }));
    }
    const groupsBy = (list, keyOf) => {
      const m = new Map();
      list.forEach((e) => {
        const k = keyOf(e);
        if (!m.has(k)) m.set(k, []);
        m.get(k).push(e);
      });
      return [...m.entries()];
    };
    const dutyName = (id) => (GROUPS.find((g) => g.id === id) || {}).name || null;
    function statsBody(keep, period) {
      const { at, tz, keepFrom, from, to, fromClipped } = period;
      const closed = statsClosed(from, to);
      const list = closed.filter(keep);
      const length = Math.max(0, to - from);
      const prevFrom = from - length;
      const open = visibleOpen();
      const results = groupsBy(list, (e) => e.closeResult)
        .map(([id, xs]) => ({ resultId: id, label: resultName(id), count: xs.length }))
        .sort((a, b) => b.count - a.count || byLabel(a.label, b.label));
      const causes = groupsBy(list.filter(isFalse), (e) => e.massCause || null)
        .map(([id, xs]) => ({ causeId: id, label: id ? causeName(xs[0]) : null, count: xs.length }))
        .sort((a, b) => b.count - a.count || byLabel(a.label, b.label));
      const devices = groupsBy(list, eventSource)
        .map(([id, xs]) => ({ source: { id, name: deviceSpec(id).name }, groups: deviceGroups(id), incidents: xs.length, falseAlarms: xs.filter(isFalse).length, breached: xs.filter(breached).length, medianReactionSec: percentile(reactions(xs), 0.5) }))
        .sort((a, b) => b.incidents - a.incidents || byLabel(a.source.name, b.source.name))
        .slice(0, 10);
      // Дежурные группы — по группе до принятия (решение 16): при равенстве — по названию, удалённые — по id после
      // названных; «Без группы» — последней
      const duty = groupsBy(list, (e) => e.acceptedGroup || null)
        .map(([id, xs]) => ({ groupId: id, name: id ? dutyName(id) : null, incidents: xs.length, falseAlarms: xs.filter(isFalse).length, breached: xs.filter(breached).length, medianReactionSec: percentile(reactions(xs), 0.5), medianResolutionSec: percentile(xs.map(resolutionOf), 0.5) }))
        .sort((a, b) => (a.groupId == null) - (b.groupId == null) || b.incidents - a.incidents || (a.name == null) - (b.name == null) || byLabel(a.name, b.name) || (a.groupId < b.groupId ? -1 : a.groupId > b.groupId ? 1 : 0));
      // Список фильтра «Оператор»: кто закрыл хоть один инцидент периода из видимых, без остальных фильтров, по имени
      const operators = [...new Set(closed.map((e) => e.closedBy).filter(Boolean))]
        .map((id) => actorRef(id))
        .filter((r) => r.kind === "operator")
        .sort((a, b) => byLabel(String(a.name), String(b.name)));
      return {
        retentionDays: W.retention.closedIncidentsDays,
        timeZone: tz,
        from: iso(from),
        to: iso(to),
        fromClipped,
        computedAt: iso(at),
        current: statsTotals(list, from, to),
        // Прошлый период — того же размера сразу перед текущим; начало раньше хранения — сравнения нет
        previous: prevFrom < keepFrom ? null : statsTotals(statsClosed(prevFrom, from).filter(keep), prevFrom, from),
        open: { open: open.length, overdue: open.filter(breached).length },
        series: statsSeries(list, from, to, tz),
        results,
        falseAlarmCauses: causes,
        devices,
        dutyGroups: duty,
        breachesByKind: BREACH_KINDS.map((kind) => ({ kind, incidents: list.filter((e) => (e.breaches || []).some((b) => b.kind === kind)).length })),
        operators,
        // Список фильтра «Дежурная группа» (§23.3): все нынешние группы поста по порядку групп, и группы самого старшего
        postDutyGroups: GROUPS.map((g) => ({ id: g.id, name: g.name })),
      };
    }
    // Тот же запрос того же человека в течение минуты заново не считается — прежний подсчёт с прежним computedAt
    const STATS_CACHE_MS = 60000;
    function supervisorStats(q) {
      if (!can("supervisor:view")) return problem(403, "PERMISSION_DENIED", ["workflow.error.no_supervisor_view"]);
      const period = statsPeriod(q);
      if (!period) return badRequest();
      // В ключе — и язык: названия результатов и причин приходят на языке запроса
      const key = JSON.stringify([ME, statsLocale(), Object.entries(q).sort()]);
      const hit = statsCache.get(key);
      if (hit && period.at >= hit.at && period.at - hit.at < STATS_CACHE_MS) return { status: 200, body: JSON.parse(JSON.stringify(hit.body)) };
      const body = statsBody(statsFilter(q), period);
      statsCache.set(key, { at: period.at, body });
      return { status: 200, body: JSON.parse(JSON.stringify(body)) };
    }
    // Время в CSV (§23.4): ISO 8601 до секунды с поясом смены — 2026-11-17T14:32:05+03:00
    function zoneIso(ms, tz) {
      const p = zoneParts(ms, tz);
      const off = Math.round(zoneOffset(ms, tz) / 60000);
      const two = (n) => String(n).padStart(2, "0");
      const hm = `${two(Math.floor(Math.abs(off) / 60))}:${two(Math.abs(off) % 60)}`;
      return `${p.y}-${two(p.m)}-${two(p.d)}T${two(p.h)}:${two(p.mi)}:${two(p.s)}${off < 0 ? "-" : "+"}${hm}`;
    }
    const STATS_CSV = ["number", "created", "accepted", "closed", "device", "device_groups", "event_type", "duty_group", "operator", "result", "cause", "reaction_sec", "resolution_sec", "breaches", "maintenance"];
    // «Выгрузить CSV» (§23.4): инциденты блока построчно — по времени закрытия, при равенстве по номеру; подписи — из
    // каталога строк на языке выгружающего; запись audit_export в журнал действий — в конце, с числом строк
    function supervisorStatsCsv(q) {
      if (!can("supervisor:view")) return problem(403, "PERMISSION_DENIED", ["workflow.error.no_supervisor_view"]);
      const period = statsPeriod(q);
      if (!period) return badRequest();
      const { tz, from, to } = period;
      const rows = statsClosed(from, to)
        .filter(statsFilter(q))
        .sort((a, b) => a.closedAt - b.closedAt || numberOf(a.number) - numberOf(b.number));
      const say = (k) => render(`workflow.supervisor.csv.${k}`);
      const secs = (v) => (v == null ? "" : String(Math.floor(v)));
      const line = (e) => {
        const src = eventSource(e);
        const kinds = BREACH_KINDS.filter((kind) => (e.breaches || []).some((b) => b.kind === kind));
        return [
          e.number,
          zoneIso(e.createdAt, tz),
          e.acceptedAt != null && !e.noReaction ? zoneIso(e.acceptedAt, tz) : "",
          zoneIso(e.closedAt, tz),
          src ? deviceSpec(src).name : "",
          src ? deviceGroups(src).map((g) => g.name).join(", ") : "",
          e.type,
          e.acceptedGroup ? dutyName(e.acceptedGroup) || say("deleted_group") : "",
          e.closedBy ? String(actorRef(e.closedBy).name) : "",
          resultName(e.closeResult),
          causeName(e) || "",
          secs(reactionOf(e)),
          secs(resolutionOf(e)),
          kinds.map((kind) => say(`breach.${kind}`)).join(", "),
          say(e.maintenanceWindowId ? "yes" : "no"),
        ];
      };
      const lines = [STATS_CSV.map((c) => say(`column.${c}`))].concat(rows.map(line));
      const text = "﻿" + lines.map((cells) => cells.map(csvCell).join(";")).join("\r\n") + "\r\n";
      const filters = Object.fromEntries(STATS_FILTERS.filter((k) => q[k] != null).map((k) => [k, q[k]]));
      audit(ME, "audit_export", { details: { journal: "supervisor_stats", filters, from: iso(from), to: iso(to), rows: rows.length } });
      // Имя файла (§23.4): день начала и последний день периода в поясе смены — конец периода в него не входит
      const day = (ms) => zoneIso(ms, tz).slice(0, 10);
      const name = `supervisor-stats-${day(from)}_${day(to > from ? to - 1 : to)}.csv`;
      return { status: 200, body: text, headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename=${name}` } };
    }

    function windowView(w) {
      return {
        id: w.id,
        deviceGuid: w.deviceGuid || null,
        sourceGroupGuid: w.sourceGroupGuid || null,
        startsAt: iso(w.startsAt),
        endsAt: iso(w.endsAt),
        timeZone: w.timeZone,
        recurrence: w.recurrence || null,
        description: w.description || "",
        status: windowStatus(w),
        endedEarlyAt: iso(w.endedEarlyAt),
        createdBy: actorRef(w.createdBy),
        createdAt: iso(w.createdAt),
      };
    }
    // Тело создания и правки → окно; неверное — null (422)
    function windowOf(body) {
      const b = body || {};
      const hasDev = b.deviceGuid != null && b.deviceGuid !== "";
      const hasGroup = b.sourceGroupGuid != null && b.sourceGroupGuid !== "";
      const startsAt = Date.parse(b.startsAt);
      const endsAt = Date.parse(b.endsAt);
      // Пояс не задан — UTC (клиент присылает пояс браузера администратора)
      const tz = b.timeZone || "UTC";
      const r = b.recurrence || null;
      const time = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
      const badRec = r && !(Array.isArray(r.days) && r.days.length && r.days.every((x) => Number.isInteger(x) && x >= 1 && x <= 7) && time.test(r.startTime || "") && time.test(r.endTime || ""));
      if (hasDev === hasGroup || !(startsAt < endsAt) || !validZone(tz) || badRec) return null;
      if (hasDev && !DEVICE_CATALOG[b.deviceGuid]) return null;
      if (hasGroup && !findNode(TREE, b.sourceGroupGuid)) return null;
      return {
        deviceGuid: hasDev ? b.deviceGuid : null,
        sourceGroupGuid: hasGroup ? b.sourceGroupGuid : null,
        startsAt,
        endsAt,
        timeZone: tz,
        recurrence: r ? { days: [...new Set(r.days)].sort((x, y) => x - y), startTime: r.startTime, endTime: r.endTime } : null,
        description: String(b.description || ""),
      };
    }
    const noMaintEdit = () => problem(403, "PERMISSION_DENIED", ["workflow.error.no_maintenance_edit"]);
    const badWindow = () => problem(422, "FORM_FIELD_INVALID", ["workflow.error.maintenance_invalid"]);
    // Начало не раньше «сейчас» минус допуск часов (maintenance.startSkewSec): окно не объясняет прошлое задним числом
    const startsInPast = (w) => w.startsAt < now() - ((W.maintenance || {}).startSkewSec || 0) * 1000;
    const pastStart = () => problem(422, "MAINTENANCE_WINDOW_STARTS_IN_PAST", ["workflow.error.maintenance_starts_in_past"]);
    // Окно видно оператору (§5): устройство окна — в его доступе; у окна на группу — в группе (с вложенными)
    // есть доступное ему устройство. Окон другой организации в MAINT нет
    const windowVisible = (w) => (w.device ? myDevices.has(w.device) : collectDeviceIds(findNode(TREE, w.group)).some((id) => myDevices.has(id)));
    // Идущие окна оператору (ТЗ-21, решение 2026-11-15): интервалы, накрывающие «сейчас» (windowsRunning машины),
    // видимые по доступу; nextChangeAt — ближайший конец идущего или начало следующего видимого интервала за сутки
    function maintenanceNow() {
      const t = now();
      const horizon = t + 864e5;
      const all = [];
      MAINT.forEach((w) => {
        const seen = new Set();
        for (let k = 0; k <= 2; k++)
          windowIntervals(w, Math.min(t + k * 864e5, Math.max(w.endsAt - 1, t))).forEach((x) => {
            const key = `${x.from}|${x.to}`;
            if (!seen.has(key) && x.to > t) seen.add(key) && all.push(x);
          });
      });
      const visible = all.filter(windowVisible);
      const running = engine.windowsRunning(visible, t).sort((a, b) => a.to - b.to || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
      const marks = visible.flatMap((x) => [x.from, x.to]).filter((m) => m > t && m <= horizon);
      const nodeName = (x) => (x.device ? deviceSpec(x.device).name : (findNode(TREE, x.group) || {}).name || "");
      return {
        windows: running.map((x) => ({ id: x.id, deviceGuid: x.device, sourceGroupGuid: x.group, objectName: nodeName(x), description: x.description, startsAt: iso(x.from), endsAt: iso(x.to) })),
        nextChangeAt: marks.length ? iso(Math.min(...marks)) : null,
      };
    }
    // Окна изменились — всем на посту: клиент перечитывает идущие окна (полоса и значки дерева)
    const windowsChanged = () => send({ type: "maintenance.windows_changed", at: iso(now()), incidentGuid: null, actor: actorRef(ME), incident: null, payload: {} });
    function MAINTENANCE_ROUTES() {
      const find = (id) => MAINT.find((w) => w.id === id) || null;
      return [
        ["GET", "/operator/maintenance-windows/current", () => ({ status: 200, body: maintenanceNow() })],
        ["GET", "/operator/admin/system-status", (p, q) => systemStatus(q)],
        // Смена и статистика: блок «Сейчас» (§23.2, план 90)
        ["GET", "/operator/supervisor/now", (p, q) => supervisorNow(q)],
        // Блок «За период» и его выгрузка в CSV (§23.3, §23.4, план 90, часть Б)
        ["GET", "/operator/supervisor/stats", (p, q) => supervisorStats(q)],
        ["GET", "/operator/supervisor/stats.csv", (p, q) => supervisorStatsCsv(q)],
        ["GET", "/operator/maintenance-windows", () => ({ status: 200, body: MAINT.slice().sort((a, b) => a.startsAt - b.startsAt).map(windowView) })],
        [
          "POST",
          "/operator/maintenance-windows",
          (p, q, body) => {
            if (!can("maintenance:edit")) return noMaintEdit();
            const w = windowOf(body);
            if (!w || w.endsAt <= now()) return badWindow();
            if (startsInPast(w)) return pastStart();
            const row = Object.assign({ id: uuid("a", ++serial.window, "000000000021") }, w, { createdBy: ME, createdAt: now(), endedEarlyAt: null });
            MAINT.push(row);
            windowsChanged();
            return { status: 201, body: windowView(row) };
          },
        ],
        [
          "PUT",
          "/operator/maintenance-windows/{id}",
          (p, q, body) => {
            if (!can("maintenance:edit")) return noMaintEdit();
            const row = find(p.id);
            if (!row) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
            const status = windowStatus(row);
            if (status === "ended") return problem(409, "MAINTENANCE_WINDOW_ENDED", ["workflow.error.maintenance_ended"]);
            const w = windowOf(body);
            if (!w || w.endsAt <= now()) return badWindow();
            if (status === "active") {
              // Идущее окно: меняются только конец и описание — иначе задним числом меняется итог прошлых событий
              const same = ["deviceGuid", "sourceGroupGuid", "startsAt", "timeZone"].every((k) => w[k] === row[k]) && JSON.stringify(w.recurrence) === JSON.stringify(row.recurrence || null);
              if (!same) return problem(409, "MAINTENANCE_WINDOW_ACTIVE", ["workflow.error.maintenance_active"]);
            } else if (w.startsAt !== row.startsAt && startsInPast(w)) return pastStart();
            Object.assign(row, w);
            windowsChanged();
            return { status: 200, body: windowView(row) };
          },
        ],
        [
          "DELETE",
          "/operator/maintenance-windows/{id}",
          (p) => {
            if (!can("maintenance:edit")) return noMaintEdit();
            const row = find(p.id);
            if (!row) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
            const status = windowStatus(row);
            if (status === "active") return problem(409, "MAINTENANCE_WINDOW_ACTIVE", ["workflow.error.maintenance_active"]);
            if (status === "ended") return problem(409, "MAINTENANCE_WINDOW_ENDED", ["workflow.error.maintenance_ended"]);
            MAINT = MAINT.filter((w) => w !== row);
            windowsChanged();
            return { status: 204, body: null };
          },
        ],
        [
          "POST",
          "/operator/maintenance-windows/{id}/end",
          (p) => {
            if (!can("maintenance:edit")) return noMaintEdit();
            const row = find(p.id);
            if (!row) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
            const status = windowStatus(row);
            if (status === "ended") return problem(409, "MAINTENANCE_WINDOW_ENDED", ["workflow.error.maintenance_ended"]);
            if (status === "planned") return badWindow();
            row.endsAt = now();
            row.endedEarlyAt = now();
            windowsChanged();
            return { status: 200, body: windowView(row) };
          },
        ],
      ];
    }

    function newIncident(event, rule, scenarioGuid, number, alarmNumber, priority, maintenanceWindowId) {
      const row = latestRow(scenarioGuid);
      if (!row) return null;
      // Дежурная группа правила-победителя (§8.1, М1): поле машины ruleDutyGroup и снимок названия на момент приёма;
      // группы уже нет — название неизвестно, остаётся id
      const dutyGroupId = rule.dutyGroupId || "";
      const dutyGroup = dutyGroupId ? GROUPS.find((g) => g.id === dutyGroupId) : null;
      const ev = {
        id: uuid(6, ++serial.incident),
        number,
        eventGuid: event.guid,
        alarmNumber,
        ruleGuid: rule.guid,
        maintenanceWindowId: maintenanceWindowId || null,
        closeMaintenanceWindowId: null,
        typeId: event.type.id,
        typeGuid: event.type.guid,
        type: event.type.name,
        priority,
        occurredAt: event.occurredAt,
        createdAt: now(),
        deviceIds: event.devices.slice(),
        cameras: camerasOf(event.devices[0]),
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
        ruleDutyGroup: dutyGroupId,
        ruleDutyGroupName: dutyGroupId ? (dutyGroup ? dutyGroup.name : dutyGroupId) : "",
      };
      // Переход появления — один из intake.create по условиям машины; уведомления и оповещения откладываются до
      // записи события (commitEvent): не создался сосед — их не было
      const deliveries = [];
      intakeDeliveries = deliveries;
      let res;
      try {
        res = engine.create(ev);
      } finally {
        intakeDeliveries = null;
      }
      if (!res.ok) return null;
      // Итог адресации (§12.5, $commentAddressing машины): аргумент условия ruleAddressingIs выполненного перехода —
      // у каждого перехода intake.create оно ровно одно (check_machine.py); нет — ошибка машины, а не «итога нет»
      const guards = (engine.transition(res.transitionId).guards || []).filter((g) => g.fn === "ruleAddressingIs");
      if (guards.length !== 1) throw new Error(`intake.create ${res.transitionId}: ruleAddressingIs × ${guards.length}`);
      const outcome = guards[0].args[0];
      pendingIntake.set(ev.id, {
        deliveries,
        transitionId: res.transitionId,
        facts: res.facts,
        // Итог — только у правила с группой: group или queue; none — у правила без группы, итога нет
        addressing: outcome === "none" ? null : { incidentGuid: ev.id, number: ev.number, ruleGuid: rule.guid, ruleName: rule.name || null, dutyGroupId, dutyGroupName: ev.ruleDutyGroupName, outcome },
      });
      return ev;
    }
    // Запись события и его инциденты — одной транзакцией (§14.5): в очередь и в поток — все вместе
    // Итог адресации по инциденту (§8.1, М1) хранится с событием — для «Почему?» (§12.5; прототип его не отдаёт);
    // уведомления и оповещения переходов появления — после incident.created
    function commitEvent(event, alarmNumber, created, maintenance) {
      const intake = created.map((ev) => pendingIntake.get(ev.id) || { deliveries: [], addressing: null });
      created.forEach((ev) => pendingIntake.delete(ev.id));
      const addressing = intake.map((x) => x.addressing).filter(Boolean);
      EVENTS.set(event.guid, { guid: event.guid, typeId: event.type.id, devices: event.devices, alarmNumber, incidentIds: created.map((ev) => ev.id), maintenance: maintenance || null, addressing });
      created.forEach((ev) => events.unshift(ev));
      // Какой переход появления и кому адресован (addressedToMe): по ui.observerNotice перехода клиент уведомляет
      // группу-адресата create_to_group так же, как адресата передачи (§8.1, М1)
      created.forEach((ev, i) => emit("incident.created", ev, "dispatcher", intake[i].transitionId ? transitionPayload(ev, intake[i].transitionId, intake[i].facts) : {}));
      intake.forEach((x) => x.deliveries.forEach((fn) => fn()));
    }

    // Событие проходит через правила (§14.5, intake машины): повтор — прежние инциденты; иначе по инциденту на
    // сценарий подошедших правил, правило-победитель — определения машины (engine.intake), от него приоритет;
    // порядок создания — по старшинству победителей, номер тревоги — номер первого. Всё или ничего: не создался один —
    // нет ни инцидентов, ни записи события, ответ — failed (какое правило и сценарий). Запрос не годится — null
    function intakeEvent(spec) {
      const event = eventOf(spec);
      if (!event) return null;
      const known = EVENTS.get(event.guid);
      // Повтор события — прежние инциденты, до окон: окно касается только создания новых (§14.12)
      if (known) return { eventGuid: known.guid, alarmNumber: known.alarmNumber, created: [], incidents: known.incidentIds.map(byId).filter(Boolean), maintenance: known.maintenance };
      intakeLog.push(now());
      const source = event.devices[0];
      const fact = { guid: event.guid, eventType: event.type.id, device: source, deviceType: deviceSpec(source).type, at: event.occurredAt };
      const won = engine.intake(RULES, fact);
      // Окна работ — после выбора победителей (intake.windows, §14.12): suppress — инцидентов нет, mark — с окном и
      // низшим уровнем справочника вместо приоритета правила (приоритет автоматики: priorityManual не ставится)
      const maintenance = engine.intakeWindows(won, maintenanceIntervals(event.occurredAt), fact);
      const picks = maintenance && maintenance.mode === "suppress" ? [] : won;
      const marked = maintenance && maintenance.mode === "mark" ? maintenance.windowId : null;
      const lowest = PRIORITIES.length ? PRIORITIES[PRIORITIES.length - 1].value : null;
      const first = nextNumber();
      const alarmNumber = picks.length ? `INC-${first}` : null;
      const created = [];
      for (const [k, pick] of picks.entries()) {
        let ev;
        try {
          ev = newIncident(event, pick.rule, pick.scenario, `INC-${first + k}`, alarmNumber, marked && lowest != null ? lowest : pick.rule.priority, marked);
        } catch (err) {
          // Исключение при появлении (сбой вычисления, ошибка машины) — соседи события тоже не создаются
          created.forEach((x) => pendingIntake.delete(x.id));
          throw err;
        }
        if (!ev) {
          created.forEach((x) => pendingIntake.delete(x.id));
          return { failed: { rule: pick.rule.name || pick.rule.guid, scenario: pick.scenario } };
        }
        created.push(ev);
      }
      commitEvent(event, alarmNumber, created, maintenance);
      return { eventGuid: event.guid, alarmNumber, created, incidents: created, maintenance };
    }

    // Базовое правило типа события: условие с этим типом события без устройства и группы — тип события, может быть с
    // типом устройства (§14.5: тип события — только вместе с устройством или типом устройства; эталонный набор)
    const baseRule = (typeId) =>
      RULES.find((r) => (r.scenarios || []).length && (r.conditions || []).some((c) => c.eventTypeId === typeId && !c.deviceGuid && !c.sourceGroupGuid)) || null;
    // Тестовый инцидент (POST /test/incidents): один инцидент в обход выбора — по правилу ruleGuid или базовому правилу
    // типа, первый сценарий правила. Приоритет — правила; priority в теле — подмена на прогон, приводится к уровню
    // справочника (§2.5). Каждый вызов — новое событие, номер тревоги — свой номер
    function createIncident(spec) {
      const event = eventOf(Object.assign({}, spec, { eventGuid: null }));
      const badPriority = spec.priority != null && !(Number.isInteger(spec.priority) && spec.priority >= SCALE.min && spec.priority <= SCALE.max);
      const rule = spec.ruleGuid != null ? RULES.find((r) => r.guid === spec.ruleGuid) || null : event && baseRule(event.type.id);
      if (!event || !rule || !(rule.scenarios || []).length || badPriority) return null;
      const number = `INC-${nextNumber()}`;
      const ev = newIncident(event, rule, rule.scenarios[0], number, number, spec.priority != null ? priorityLevel(spec.priority) : rule.priority);
      if (!ev) return null;
      commitEvent(event, number, [ev]);
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
          "/test/events",
          (p, q, body) => {
            const res = intakeEvent(body || {});
            if (!res) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.test.bad_event"]);
            // Запрос верный, а инцидент не создался (у правила нет сценария в наборе): ничего не создано и не записано
            if (res.failed) return problem(422, "FORM_FIELD_INVALID", ["workflow.error.test.event_failed", res.failed]);
            // Создан хоть один — 201; повтор события или не подошло ни одно правило — 200
            return {
              status: res.created.length ? 201 : 200,
              body: { eventGuid: res.eventGuid, alarmNumber: res.alarmNumber, created: res.created.length, incidents: res.incidents.map(card), maintenance: res.maintenance || null },
            };
          },
        ],
        [
          "POST",
          "/test/reset",
          (p, q, body) => {
            if (body.fixture && body.fixture !== "demo") return problem(404, "NOT_FOUND", ["workflow.error.test.no_fixture", { name: body.fixture }]);
            // Часы останавливаются: время в тестах идёт только по /test/clock
            // Остановленные часы — с целой секунды: сдвиги /test/clock целые, и тест попадает ровно в границу смены (§23.1)
            clock.frozenAt = body.freezeClock === false ? null : Math.floor((realNow() + clock.offset) / 1000) * 1000;
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
            // Окна набора заменили созданные прогоном — полоса работ и значки дерева перечитываются (ТЗ-21)
            windowsChanged();
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
              myDevices = myAccessibleDevices(person.roles);
            }
            const fired = runScheduler();
            return { status: 200, body: { operatorId: person.id, roles: person.roles, fired: fired.map((f) => ({ incidentGuid: f.id, transitionId: f.transition })) } };
          },
        ],
        [
          "PUT",
          "/test/operators/{operatorId}/agent-state",
          (p, q, body) => {
            // Коллега уходит на перерыв, возвращается или выходит из МИ (§12.1) — как его собственный запрос: переход
            // состояния оператора машины, сначала догон (BUG-82); runScheduler: false — такт ещё не наступил (§12.2)
            const person = OPERATORS.find((o) => o.id === p.operatorId);
            if (!person || person.id === ME) return problem(404, "NOT_FOUND", ["workflow.error.test.no_operator", { id: p.operatorId }]);
            const b = body || {};
            const from = person.agentState || "offline";
            const to = b.agentState;
            const label = (id) => [(W.session.states.find((s) => s.id === id) || {}).labelKey || String(id)];
            const move = W.session.transitions.find((t) => t.from.includes(from) && t.to === to);
            if (to !== from && !move) return problem(409, "TRANSITION_NOT_ALLOWED_FROM_STATE", ["workflow.error.agent_state_not_allowed", { from: label(from), to: label(to) }]);
            // Право — у состояния, куда переходит, как в собственном запросе (session.states[].permission)
            const target = W.session.states.find((st) => st.id === to);
            if (to !== from && target && target.permission && !permsOf(person.id).includes(target.permission)) return problem(403, "PERMISSION_DENIED", ["workflow.error.break_no_permission"]);
            if (to !== from && engine.agentReasonRequired(to) && !W.session.breakReasons.some((r) => r.id === b.reasonId)) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.reason_required"]);
            const tick = () => (b.runScheduler === false ? [] : runScheduler());
            const caught = tick();
            if (to !== from) {
              audit(person.id, move.id, to === "not_ready" && b.reasonId ? { reasonId: b.reasonId } : {});
              if (from === "not_ready") breakEnded(person.id);
              person.agentState = to;
              person.reasonId = to === "not_ready" ? b.reasonId || null : null;
              if (to === "not_ready") breakStarted(person.id, person.reasonId, now());
            }
            // Системные переходы от нового состояния (ушёл на перерыв — его в работе отложены, §12.2)
            const fired = caught.concat(tick());
            return { status: 200, body: { operatorId: person.id, agentState: person.agentState, reasonId: person.reasonId || null, fired: fired.map((f) => ({ incidentGuid: f.id, transitionId: f.transition })) } };
          },
        ],
        [
          "PUT",
          "/test/workflow",
          (p, q, body) => {
            // Новые настройки посреди прогона, без сброса данных, — как публикация (§14.6): клиенты перечитывают схему.
            // Идущие перерывы — со сроком на своё начало (§12.2)
            if (!body || !body.workflowPatch || typeof body.workflowPatch !== "object" || Array.isArray(body.workflowPatch)) return problem(422, "FORM_FIELD_REQUIRED", ["workflow.error.test.workflow_patch"]);
            // Сохранение настроек — новая версия схемы, как у публикации
            const next = mergePatch(W, body.workflowPatch);
            next.schema = Object.assign({}, next.schema, { version: W.schema.version + 1 });
            useWorkflow(next);
            emit("workflow.schema_published", null, null, { schemaVersion: W.schema.version });
            return { status: 200, body: { schemaVersion: W.schema.version } };
          },
        ],
        [
          "POST",
          "/test/operators/{operatorId}/incidents/{incidentGuid}/transitions/{transitionId}",
          (p, q, body) => {
            // Переход от имени коллеги (§17): его исполнитель машины — его права, состояние и проверки, как в эмуляции
            // коллег. Так тесты видят чужое действие глазами оператора стенда: уведомления, поток, карточку
            const person = OPERATORS.find((o) => o.id === p.operatorId);
            if (!person || person.id === ME) return problem(404, "NOT_FOUND", ["workflow.error.test.no_operator", { id: p.operatorId }]);
            // Инцидент вне доступа коллеги для него — то же, что несуществующий, как у /operator/* для оператора (§5)
            const ev = byId(p.incidentGuid);
            if (!ev || !hasAccess(person.id, ev)) return problem(404, "NOT_FOUND", ["workflow.error.not_found"]);
            // Сначала догнать то, что к этому моменту должно было сработать, как перед запросом оператора (BUG-82)
            const caught = runScheduler();
            const actor = colleague(person.id);
            const tr = actor.transition(p.transitionId);
            if (!tr || tr.trigger !== "manual") return problem(404, "NOT_FOUND", ["workflow.error.unknown_action"]);
            const formValues = (body && body.formValues) || {};
            const surface = (body && body.surface) || "card";
            const check = actor.availability(p.transitionId, ev, { form: formValues, surface });
            if (!check.ok) return guardProblem(check);
            const r = actor.run(p.transitionId, ev, formValues, { surface });
            if (!r.ok) return problem(422, r.code || "FORM_FIELD_REQUIRED", r.why);
            if (bumps(tr)) touch([ev]);
            emitTransition(ev, p.transitionId, person.id, r.facts);
            // Системные переходы, которые действие сделало возможными (закрыт основной — привязанные), — сразу
            const fired = caught.concat(runScheduler());
            return {
              status: 200,
              body: { operatorId: person.id, incidentGuid: ev.id, transitionId: p.transitionId, state: ev.state, fired: fired.map((f) => ({ incidentGuid: f.id, transitionId: f.transition })) },
            };
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
      let res;
      try {
        // Перед запросом оператора — всё, что уже наступило по времени (§14.3, ARCH-10): иначе действие между
        // тактами планировщика стёрло бы нарушение (BUG-82). Окно после дедлайна по-прежнему ждёт человека.
        // Сбой догона — 500: ничего не сделано, ключ не тратится (решение 212)
        if (acting) runScheduler();
        // Действие оператора — признак активности (§12.3, BUG-76): кто действует, тот не молчит; связь была потеряна —
        // запись «Связь восстановлена» в журнале действий (§12.4): от неё «с какого времени» на месте (§23.2)
        if (acting && session.linkLostAt != null) {
          session.linkLostAt = null;
          audit(ME, "link_restored", {});
        }
        if (acting) lastHeartbeat = now();
        res = route.fn(params, q, body || {}, lowerKeys(headers));
      } catch (err) {
        res = failedToCompute(err);
      }
      // После — системные переходы, которые запрос сделал возможными (передали вышедшему — сразу его группе), в
      // том же запросе: их события уходят в поток, ответ показывает инциденты уже после них (ARCH-10). Действие
      // уже зафиксировано: сбой здесь ответ не меняет — он остаётся тем, что зафиксировано, и запоминается по
      // ключу, а несделанное доделает следующий такт (решение 212)
      if (acting && res.status < 300) {
        try {
          if (runScheduler().length && res.again) res = res.again();
        } catch (err) {
          // Сбой вычисления и ошибка в коде (TypeError в res.again()) — оба в консоль, со стеком: ответ тот же,
          // но ошибка в коде видна, а не теряется под сбоем такта
          const kind = err && err.name === "EvaluationError" ? "evaluation error" : "code error";
          console.error(`scheduler after request failed (${kind}):`, method, path, (err && err.stack) || err);
        }
      }
      record(method, route.template, res.status, res.body, "http", res.headers);
      const out = { status: res.status, body: res.body, headers: res.headers };
      // Неразобранный запрос (400) и ошибка сервера (5xx) ключ не тратят: тот же ключ выполнит запрос заново (решения 95, 113)
      if (idem && res.status !== 400 && res.status < 500) answered.set(idem, { at: now(), res: JSON.parse(JSON.stringify(out)) });
      return out;
    }

    /* ===== Планировщик и эмуляция коллег ===== */

    // Автоматические переходы машины по дедлайнам (§6.2): в продукте их выполняет сервер
    function runScheduler() {
      // Потеря связи (§12.3): вошёл, а признака активности нет дольше idleHoldSec — запись «Потеря связи» в журнале
      // действий в момент, когда порог пройден, один раз до восстановления
      if (session.agentState !== "offline" && session.linkLostAt == null && lastHeartbeat != null && now() - lastHeartbeat >= W.session.idleHoldSec * 1000) {
        session.linkLostAt = lastHeartbeat + W.session.idleHoldSec * 1000;
        audit(ME, "link_lost", { at: iso(session.linkLostAt) });
      }
      // Чьи инциденты были мои — владельцем или адресатом, лично или группой (ownership машины): если после
      // переходов такой инцидент мне не виден, сервер сообщает об этом (§5)
      const wasMine = new Set(events.filter((e) => !isDone(e) && ["owner", "target"].includes(engine.ownership(e))).map((e) => e.id));
      // Системные переходы каждого человека — по его состоянию, как на бэкенде, а не только в эмуляции
      // коллег (RULE-47): переданное вышедшему сразу уходит его группе или в очередь. Один такт в общем порядке
      // по времени по всем людям (§14.3, решение 212), а не «сначала мои, потом каждого коллеги»
      const peers = OPERATORS.filter((op) => op.id !== ME).map((op) => colleague(op.id));
      const fired = engine.tick({ peers });
      fired.forEach(({ id, transition, facts, operator }) => {
        const ev = byId(id);
        touch([ev]);
        // Системный переход коллеги (scope: incidents_owned_by_agent, его состояние) — от имени системы
        if (operator !== ME) return emitTransition(ev, transition, "system", facts);
        const tr = engine.transition(transition);
        if (wasMine.has(id) && !canSee(ev)) {
          wasMine.delete(id);
          emitAccessLost(ev);
        }
        emitTransition(ev, transition, tr.actor || "dispatcher", facts);
      });
      // Затянувшиеся перерывы — тем же тактом (§12.2, §14.3)
      breakTick();
      return fired;
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
      // Его системные переходы — общим тактом по всем людям (§14.3)
      runScheduler();
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
      // Системные переходы молчащих коллег — уже в runScheduler, в общем порядке такта (§14.3)
      const fired = runScheduler();
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
