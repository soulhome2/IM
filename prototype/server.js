/* Встроенный сервер прототипа. Отвечает на запросы ровно по контракту
   Specification/State_machine/openapi.json и хранит всё, что в продукте хранит бэкенд:
   инциденты, журнал, ответы сценария, сессию оператора. Переходы выполняет исполнитель
   машины (engine.js), автоматические — планировщик раз в секунду (§6.2). Интерфейс (app.js)
   разговаривает с ним только через api.js, теми же запросами, что с настоящим бэкендом.
   Работает в той же вкладке: страница открывается и с диска (file://), и с сайта.
   Демо: один оператор («me»), права — весь каталог, эмуляция коллег (§17).

   Параметры create(): workflow, demo — машина и демо-данные (данные копируются: у каждого
   сервера свои); now — часы; autoTick: false — планировщик не запускается сам, его шаг
   вызывают тесты (tick); colleagues: false — без эмуляции коллег; permissions — права
   оператора списком ключей (по умолчанию — весь каталог, кроме настройки схемы). */
(() => {
  function create(opts) {
    const W = opts.workflow;
    const D = JSON.parse(JSON.stringify(opts.demo));
    const now = opts.now || (() => Date.now());
    const ME = "me";
    const iso = (ms) => (ms == null ? null : new Date(ms).toISOString());

    /* ===== Люди и права ===== */

    const ACTORS = D.ACTORS;
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
    const PERMISSIONS = opts.permissions || W.permissions.map((p) => p.key).filter((key) => key !== "incident:schema:admin");
    const can = (key) => PERMISSIONS.includes(key);

    const session = {
      agentState: "ready",
      reasonId: null,
      openIncidentGuid: null,
      preferences: { defaultTransferTargetId: "petrova", locale: "ru" },
    };

    /* ===== Устройства и группы ===== */

    const DEVICE_TYPES = D.DEVICE_TYPES;
    const deviceSpec = (id) => D.DEVICE_CATALOG[id] || { name: id, type: "camera" };
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
      return walk(D.TREE) || { guid: "all", name: "Все события" };
    }
    const touches = (ev, ids) => (ev.deviceIds || []).some((id) => ids.includes(id));

    /* ===== Сценарий (до подключения машины сценариев, §14.5, §17) ===== */

    const scenarioOf = (ev) => D.SCENARIOS[ev.typeId];
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

    function stamp(ms) {
      const d = new Date(ms);
      const pad = (n) => String(n).padStart(2, "0");
      return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    }
    // Время в демо-данных записано строкой «чч:мм:сс» — на сегодня, не позже текущего момента
    function atFromStamp(s) {
      const [h, m, sec] = s.split(":").map(Number);
      const d = new Date(now());
      d.setHours(h, m, sec || 0, 0);
      if (d.getTime() > now() + 1000) d.setDate(d.getDate() - 1);
      return d.getTime();
    }
    function log(ev, whoId, template, vars) {
      ev.log.push({ at: now(), whoId, k: template, v: vars || null });
    }

    /* ===== Демо-данные → модель машины ===== */

    const events = D.EVENTS;
    const GROUPS = D.GROUPS;

    const engine = IMEngine.create({
      workflow: W,
      me: ME,
      now,
      events: () => events,
      can,
      isGroup: (id) => GROUPS.some((g) => g.id === id),
      memberOf: (groupId, userId) => {
        const group = GROUPS.find((g) => g.id === groupId);
        return Boolean(group && group.members.includes(userId));
      },
      inGroup: (ev, groupId) => touches(ev, collectDeviceIds(findNode(D.TREE, groupId))),
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
    });

    // Время событий — к моменту запуска: самое свежее событие минуту назад, промежутки сохраняются
    function shiftDemoTimes(list) {
      const isStamp = (s) => typeof s === "string" && /^\d{1,2}:\d\d:\d\d$/.test(s);
      const toSec = (s) => s.split(":").reduce((acc, part) => acc * 60 + Number(part), 0);
      const pad = (n) => String(n).padStart(2, "0");
      const fmt = (sec) => {
        const day = ((sec % 86400) + 86400) % 86400;
        return `${pad(Math.floor(day / 3600))}:${pad(Math.floor((day % 3600) / 60))}:${pad(day % 60)}`;
      };
      const stamps = list.flatMap((ev) => [ev.time, ...(ev.log || []).map((entry) => entry.t)]).filter(isStamp);
      if (!stamps.length) return;
      const d = new Date(now());
      const shift = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds() - 60 - Math.max(...stamps.map(toSec));
      list.forEach((ev) => {
        if (isStamp(ev.time)) ev.time = fmt(toSec(ev.time) + shift);
        (ev.log || []).forEach((entry) => {
          if (isStamp(entry.t)) entry.t = fmt(toSec(entry.t) + shift);
        });
      });
    }

    function migrateEvents(list) {
      shiftDemoTimes(list);
      const byName = {};
      D.OPERATORS.forEach((op) => (byName[op.name] = op.id));
      const startReaction = (ev, arg) => engine.startTimer(ev, "reaction", arg);
      list.forEach((ev) => {
        const legacy = ev.status;
        ev.occurredAt = atFromStamp(ev.time);
        ev.log = (ev.log || []).map((entry) => ({
          at: entry.t ? atFromStamp(entry.t) : now(),
          whoId: entry.whoId || byName[entry.who] || null,
          who: entry.who || null,
          k: entry.k || entry.text,
          v: entry.v || null,
        }));
        ev.owner = ev.operator ? byName[ev.operator] || null : null;
        ev.escalationLevel = 0;
        ev.holdReason = null;
        ev.closeResult = ev.closeResult || null;
        ev.massCause = null;
        ev.slaBreached = false;
        ev.breaches = [];
        ev.groupId = null;
        ev.holdSince = null;
        ev.holdDueAt = null;
        ev.assignmentGroup = null;
        ev.closedAt = null;
        ev.reactionDueAt = null;
        ev.resolutionDueAt = null;
        ev.resolutionLeftMs = null;
        ev.version = 1;
        if (legacy === "new") {
          ev.state = "new";
          ev.owner = null;
          startReaction(ev);
        } else if (legacy === "mine") {
          ev.owner = ME;
          if (ev.paused) {
            ev.state = "on_hold";
            ev.holdReason = ev.holdReason || "third_party";
            engine.startTimer(ev, "hold");
            ev.holdSince -= 4 * 60000;
            ev.holdDueAt -= 4 * 60000;
            ev.resolutionLeftMs = (ev.slaSec || 600) * 1000;
          } else {
            ev.state = "in_progress";
            engine.resumeTimer(ev, "resolution");
          }
        } else if (legacy === "foreign") {
          ev.state = "in_progress";
          engine.resumeTimer(ev, "resolution");
        } else if (legacy === "escalated") {
          ev.state = "pending_acceptance";
          ev.escalationLevel = 1;
          startReaction(ev);
        } else {
          ev.state = "closed";
          ev.closeResult = ev.closeResult || "processed";
          ev.closedAt = now() - 3 * 3600000;
        }
        delete ev.status;
        delete ev.operator;
        delete ev.paused;
      });

      // Демонстрационные ситуации, которых не было в первой версии модели
      const pick = (id) => list.find((e) => e.id === id);
      const inbox = pick("INC-1836");
      if (inbox) {
        inbox.owner = null;
        inbox.assignmentGroup = "grp-leads";
        inbox.escalationLevel = 1;
        startReaction(inbox, "byEscalationLevel");
        log(inbox, "sidorov", "Эскалация → {who}. {why}", { who: "Дежурная группа старших", why: "Нужен допуск в зону" });
      }
      // Второй инцидент, адресованный лично оператору: на нём проверяется «Отклонить»
      const inboxMine = pick("INC-1843");
      if (inboxMine) {
        inboxMine.owner = ME;
        startReaction(inboxMine, "byEscalationLevel");
        log(inboxMine, "noc", "Передано → {who} (уровень {lvl}). {why}", {
          who: D.ME,
          lvl: inboxMine.escalationLevel,
          why: "Нужна проверка по камерам площадки",
        });
      }
      const falseAlarm = pick("INC-1826");
      if (falseAlarm) {
        falseAlarm.closeResult = "false_alarm";
        falseAlarm.closedAt = now() - 25 * 60000;
        log(falseAlarm, "sidorov", "Закрыт без обработки: {why}. {note}", { why: "Ложная тревога", note: "Сработка от уборщика" });
      }
      const fresh = pick("INC-1837");
      if (fresh) fresh.closedAt = now() - 12 * 60000;
    }

    migrateEvents(events);

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
        number: ev.id,
        occurredAt: iso(ev.occurredAt),
        eventType: { guid: ev.typeId, id: ev.typeId, name: ev.type },
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
        scenarioGuid: ev.typeId,
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
        guid: `${ev.id}-${i}`,
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
        eventType: { guid: ev.typeId, id: ev.typeId, name: ev.type },
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
        devices: deviceIds.map(deviceRef),
        scenario: scenarioView(ev),
        journal: journalView(ev),
        media: mediaView(ev),
        group: groupView(ev),
        result: ev.closeComment || null,
      });
    }

    function mediaView(ev) {
      const src = eventSource(ev);
      return {
        cameras: (ev.cameras || []).map((id) => ({
          guid: id,
          name: deviceSpec(id).name,
          isSource: id === src,
          archiveUrl: null,
          liveUrl: null,
          archiveStartAt: iso(ev.occurredAt),
          thumbnailUrl: null,
        })),
        // Положение значков на плане — у подсистемы карт; встроенный сервер отдаёт только состав
        map: {
          planName: ev.site || null,
          markers: [...new Set([...(ev.deviceIds || []), ...(ev.cameras || [])])].map((id) => ({ deviceGuid: id, isSource: id === src })),
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
          dutyGroupGuids: GROUPS.filter((g) => g.members.includes(ME)).map((g) => g.id),
        },
        shift: shiftView(),
        agentState: session.agentState === "not_ready" ? "not_ready" : usage().activeCount ? "busy" : "ready",
        agentStateReasonId: session.reasonId,
        permissions: PERMISSIONS.slice(),
        limits: Object.fromEntries(Object.entries(W.limits).filter(([key]) => !key.startsWith("$"))),
        usage: usage(),
        preferences: JSON.parse(JSON.stringify(session.preferences)),
        workflowSchemaVersion: 4,
        permissionIssues: [],
      };
    }

    // Адресаты передачи. Себя и своих групп в списке нет (§8.1, §10.1)
    function targets() {
      return D.OPERATORS.concat(GROUPS).map((op) => ({
        id: op.id,
        kind: op.group ? "duty_group" : "operator",
        name: op.name,
        label: op.name,
        role: op.role,
        available: op.duty === "на смене",
        availabilityLabel: op.duty === "на смене" ? null : op.duty,
        memberIds: op.members || [],
      }));
    }

    /* ===== Очередь: фильтр, группа, типы, поиск, страница ===== */

    function visible(q) {
      let list = events;
      if (q.sourceGroupGuid && q.sourceGroupGuid !== "all") {
        const node = findNode(D.TREE, q.sourceGroupGuid);
        const ids = node ? collectDeviceIds(node) : [q.sourceGroupGuid];
        list = list.filter((e) => touches(e, ids));
      }
      return list.filter((e) => {
        if (q.filter && !engine.inQueueFilter(e, q.filter)) return false;
        if (q.eventTypeGuid && q.eventTypeGuid !== "all" && e.typeId !== q.eventTypeGuid) return false;
        if (q.deviceTypeId && q.deviceTypeId !== "all") {
          const src = eventSource(e);
          if (!src || deviceSpec(src).type !== q.deviceTypeId) return false;
        }
        if (q.search) {
          const needle = String(q.search).toLowerCase();
          if (!`${e.id} ${e.type} ${e.site} ${e.location}`.toLowerCase().includes(needle)) return false;
        }
        return true;
      });
    }

    function page(q) {
      const list = visible(q);
      const size = Math.max(1, Number(q.pageSize) || D.PAGE_SIZE);
      const pages = Math.max(1, Math.ceil(list.length / size));
      const n = Math.min(Math.max(1, Number(q.page) || 1), pages);
      // На какой странице выбранный инцидент — если он виден при этих фильтрах (null — не виден)
      const idx = q.focusGuid ? list.findIndex((e) => e.id === q.focusGuid) : -1;
      const focusPage = idx === -1 ? null : Math.floor(idx / size) + 1;
      return { items: list.slice((n - 1) * size, n * size).map((e) => summary(e, "queue")), total: list.length, page: n, pageSize: size, focusPage };
    }

    function counters() {
      const out = {};
      W.queueFilters.forEach((f) => (out[f.id] = events.filter((e) => engine.inQueueFilter(e, f.id)).length));
      return out;
    }

    function treeView(nodes) {
      return nodes
        .filter((n) => !n.isDevice)
        .map((n) => {
          const ids = collectDeviceIds(n);
          const open = events.filter((e) => !isDone(e) && touches(e, ids));
          const devices = (n.children || [])
            .filter((c) => c.isDevice)
            .map((c) => {
              const evs = events.filter((e) => !isDone(e) && touches(e, [c.id]));
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
        if (!seen.has(e.typeId)) seen.set(e.typeId, { guid: e.typeId, id: e.typeId, name: e.type, defaultReactionSec: engine.norm({ typeId: e.typeId, priority: "medium" }, "reaction") });
      });
      return [...seen.values()];
    }

    /* ===== Поток серверных событий (§9: поток вместо опроса) ===== */

    const listeners = new Set();
    let seq = 0;
    function emit(type, ev, actorId, payload) {
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
      requiredStepsFilled: "REQUIRED_STEPS_NOT_FILLED",
      withinReopenWindow: "REOPEN_WINDOW_EXPIRED",
    };
    function guardProblem(check) {
      if (check.notFrom) return problem(409, "TRANSITION_NOT_ALLOWED_FROM_STATE", check.why);
      return problem(403, GUARD_CODE[check.guard] || "GUARD_FAILED", check.why, check.guard ? { guard: check.guard } : {});
    }

    /* ===== Маршруты API ===== */

    const find = (guid) => events.find((e) => e.id === guid) || null;
    const touch = (list) => list.forEach((e) => (e.version += 1));

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
      ["GET", "/operator/workflow/active", () => ({ status: 200, body: W })],
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
            return { status: 200, body: { session: sessionView(), affectedIncidents: fired.map((f) => summary(find(f.id), "queue")) } };
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
          const list = (body.incidentGuids || []).map(find).filter(Boolean);
          if (!list.length) return problem(422, "BULK_SELECTION_INVALID", ["Выборка пуста"]);
          const succeeded = [];
          const failed = [];
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
          return ev ? { status: 200, body: card(ev) } : problem(404, "NOT_FOUND", ["Инцидент не найден"]);
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
        (p, q, body) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["Инцидент не найден"]);
          if (body && body.expectedState && body.expectedState !== ev.state) {
            return problem(412, "VERSION_CONFLICT", ["Инцидент уже изменён: {state}", { state: STATES[ev.state].label }], { current: card(ev) });
          }
          return runTransition(p.transitionId, ev, (body && body.formValues) || {}, body && body.surface);
        },
      ],
      [
        "POST",
        "/operator/incident-groups",
        (p, q, body) => {
          const list = (body.incidentGuids || []).map(find).filter(Boolean);
          const groupId = `GRP-${String(now()).slice(-4)}`;
          const r = engine.createGroup(list, groupId);
          if (!r.ok) return r.guard ? guardProblem(r) : problem(422, "BULK_SELECTION_INVALID", r.why);
          list.forEach((ev) => {
            ev.groupCreatedAt = now();
            log(ev, ME, "Групповая обработка {grp} вместе с {ids}", {
              grp: groupId,
              ids: list
                .filter((x) => x.id !== ev.id)
                .map((x) => x.id)
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
        (p, q, body) => {
          const ev = find(p.incidentGuid);
          if (!ev) return problem(404, "NOT_FOUND", ["Инцидент не найден"]);
          // Ответы пишет только тот, кому машина разрешает править сценарий (scenarioEdit, §10.4)
          if (!engine.canEditScenario(ev)) return problem(403, "PERMISSION_DENIED", ["Карточка открыта на просмотр"]);
          Object.assign(ev.answers, (body && body.answers) || {});
          if (!canOpenStep(ev, cursorOf(ev))) ev.stepIndex = firstOpenStep(ev);
          touch([ev]);
          return { status: 200, body: scenarioView(ev) };
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
          return { status: 202, body: { executionGuid: `MAC-${ev.version}`, macroId: p.macroId, status: "delivered", queuedAt: iso(now()) } };
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
          if (ev) list = list.filter((o) => o.id !== engine.addressee(ev));
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
      ["GET", "/operator/reference/source-groups", () => ({ status: 200, body: treeView(D.TREE) })],
      ["GET", "/operator/reference/priorities", () => ({ status: 200, body: ["critical", "high", "medium", "low"].map((id) => ({ id })) })],
    ];

    const compiled = ROUTES.map(([method, template, fn]) => {
      const names = [];
      const re = new RegExp(`^${template.replace(/\{(\w+)\}/g, (m, name) => (names.push(name), "([^/]+)"))}$`);
      return { method, template, re, names, fn };
    });

    // Образцы ответов — для самопроверки: она сверяет их со схемами openapi.json.
    // По каждому маршруту, коду и типу события — первые несколько, чтобы покрыть все виды ответов
    const recorded = [];
    const samples = new Map();
    function record(method, template, status, body, kind) {
      const key = `${method} ${template} ${status} ${body && body.type ? body.type : ""}`;
      const n = samples.get(key) || 0;
      if (n >= 12) return;
      samples.set(key, n + 1);
      recorded.push({ method, template, status, body: JSON.parse(JSON.stringify(body)), kind: kind || "http" });
    }

    function handle(method, url, body) {
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
      const res = route.fn(params, q, body || {});
      record(method, route.template, res.status, res.body);
      return res;
    }

    /* ===== Планировщик и эмуляция коллег ===== */

    // Автоматические переходы машины по дедлайнам (§6.2): в продукте их выполняет сервер
    function runScheduler() {
      const fired = engine.tick();
      fired.forEach(({ id, transition }) => {
        const ev = find(id);
        touch([ev]);
        const tr = engine.transition(transition);
        emit(transition === "auto_escalate" ? "incident.auto_escalated" : "incident.state_changed", ev, tr.actor || "dispatcher", {
          transitionId: transition,
          addressee: actorRef(engine.addressee(ev)),
        });
      });
      return fired;
    }

    const SIM = D.SIM;
    const foreignActive = () => events.filter((e) => e.state === "in_progress" && e.owner && e.owner !== ME && !e.groupId);

    // Коллега забирает одно из новых событий первой страницы очереди — не то, что открыто у оператора
    function simTakeEvent() {
      const pool = visible({ filter: "open" })
        .slice(0, D.PAGE_SIZE)
        .filter((e) => e.state === "new" && e.id !== session.openIncidentGuid);
      // В верхней части очереди всегда оставляем новое событие, чтобы оператору было что взять
      if (pool.length < 2) return;
      const ev = pool[pool.length - 1];
      const who = SIM.colleagues[SIM.taken % SIM.colleagues.length];
      ev.state = "in_progress";
      ev.owner = who;
      ev.stepIndex = 0;
      engine.stopTimer(ev, "reaction");
      engine.resumeTimer(ev, "resolution");
      log(ev, who, "Взято в работу");
      SIM.taken += 1;
      touch([ev]);
      emit("incident.state_changed", ev, who, { transitionId: "claim" });
    }

    // Чужой сценарий продвигается на один шаг: меняются прогресс и журнал
    function simAdvanceEvent() {
      const pool = foreignActive().filter((e) => !scenarioDone(e));
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
        ev.launched.push(step.buttons[0]);
        done = ["запущен макрос «{name}»", { name: step.buttons[0] }];
      } else if (step.options) {
        ev.answers[step.id] = step.options[Math.floor(Math.random() * step.options.length)];
        done = ev.answers[step.id];
      } else {
        ev.answers[step.id] = D.SIM_NOTES[Math.floor(Math.random() * D.SIM_NOTES.length)];
        done = ev.answers[step.id];
      }
      ev.stepIndex = Math.min(idx + 1, steps.length - 1);
      log(ev, ev.owner, "Шаг {i}/{n} · {name}: {done}", { i: idx + 1, n: steps.length, name: stepShort(step), done });
      touch([ev]);
      emit("journal.appended", ev, ev.owner, {});
    }

    // Коллега передаёт свой инцидент оператору: появляется «Вам на принятие»
    function simHandoff() {
      const pool = foreignActive().filter((e) => e.escalationLevel < W.escalation.maxLevel);
      if (!pool.length) return;
      const ev = pool[0];
      const from = ev.owner;
      engine.applyAs("transfer", ev, { targetId: ME, comment: "Нужен оператор с доступом к архиву площадки" }, from);
      touch([ev]);
      emit("incident.owner_changed", ev, from, { transitionId: "transfer", addressee: actorRef(ME) });
    }

    // Отвал оператора (§12.3): сессия не отвечает, инцидент откладывается системой
    function simDrop() {
      const pool = foreignActive();
      if (!pool.length) return;
      const ev = pool[pool.length - 1];
      const owner = ev.owner;
      engine.applyAs("system_hold_idle", ev, {}, "system");
      touch([ev]);
      emit("incident.state_changed", ev, "system", { transitionId: "system_hold_idle", previousOwner: actorRef(owner) });
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

    if (opts.colleagues === false) SIM.enabled = false;
    if (opts.autoTick !== false) {
      setInterval(() => {
        const fired = runScheduler();
        if (!fired.length) simulateColleagues();
      }, 1000);
    }

    return { handle, subscribe, recorded, tick: runScheduler, routes: ROUTES.map(([method, template]) => `${method} ${template}`) };
  }

  window.IMServer = { create };
})();
