/* Исполнитель машины состояний в браузере: Specification/Workflow_machine/workflow_schema.v1.json,
   подключённой как window.IM_WORKFLOW (prototype/workflow.js).

   Решает, какие действия доступны (/actions), выполняет переход (/transitions), строит
   формы и бейджи, считает нормативы и выполняет автоматические переходы по таймерам.
   Его вызывает только встроенный сервер прототипа (server.js) — интерфейс сюда не
   обращается, он говорит с сервером запросами API. Своей таблицы переходов здесь нет:
   условия и эффекты берутся из реестров машины (§14.8). Образец для исполнителя бэкенда.

   Данные инцидента и всё, что относится к сценарию, журналу и людям, передаёт сервер
   через ctx в create(). */
(() => {
  function create(ctx) {
    const W = ctx.workflow;
    const ME = ctx.me;
    const transitions = Object.fromEntries(W.transitions.map((t) => [t.id, t]));
    const navActions = Object.fromEntries(W.navActions.items.map((n) => [n.id, n]));
    const guardRegistry = Object.fromEntries(W.registries.guards.map((g) => [g.fn, g]));
    const forms = Object.fromEntries(W.forms.map((f) => [f.id, f]));
    const timers = Object.fromEntries(W.timers.map((t) => [t.id, t]));
    const catalogs = W.reasonCatalogs;
    const states = Object.fromEntries(W.states.map((s) => [s.id, s]));

    // Момент, «в который» выполняется автоматический переход (RULE-41): планировщик догоняет
    // пропущенное по времени наступления, и эффекты считают время от этого момента
    let at = null;
    const now = () => (at != null ? at : ctx.now());
    // Окно после дедлайна (§10.1, правило 5; RULE-63): переход по таймеру — через graceSec после дедлайна
    const GRACE_MS = (((W.invariants || {}).manualWinsOverTimer || {}).graceSec || 0) * 1000;
    const isGroup = (id) => Boolean(id) && ctx.isGroup(id);
    const byId = (id) => (id ? ctx.events().find((e) => e.id === id) || null : null);
    const catalogItem = (catalog, id) => (catalogs[catalog] ? catalogs[catalog].items.find((i) => i.id === id) : null);

    /* ===== Таймеры: дедлайны — метки времени (§4, правило 1) ===== */

    // Где у инцидента прототипа лежат дедлайн и остаток таймера (deadlineField машины)
    const FIELDS = {
      // Остаток реакции при остановке — с него «Вернуть в очередь» её продолжает (RULE-104)
      reaction: { due: "reactionDueAt", left: "reactionLeftMs" },
      resolution: { due: "resolutionDueAt", left: "resolutionLeftMs" },
      hold: { due: "holdDueAt", since: "holdSince" },
    };
    const dueOf = (ev, id) => ev[FIELDS[id].due];
    // Срабатывание отмечается планировщиком: каждый дедлайн срабатывает один раз (§14.3)
    function markFired(ev, id) {
      ev.firedTimers = Object.assign({}, ev.firedTimers, { [id]: dueOf(ev, id) });
    }

    /* ===== Язык выражений машины (CEL.md, ARCH-07) ===== */

    // Смысл условий и эффектов — выражения машины: здесь своих правил нет
    if (!window.IMCel) throw new Error("cel: prototype/cel-runtime.js is not loaded");
    const cel = IMCel.create(W);
    if (cel.errors.length) throw new Error(`cel: ${cel.errors.join("; ")}`);
    // Мост к данным сервера: инцидент прототипа → Incident машины, таймеры — по FIELDS
    const celTimer = (ev, id) => {
      const f = FIELDS[id];
      return { due: ev[f.due], paused: Boolean(f.left) && ev[f.left] != null, left: f.left ? ev[f.left] : 0, fired: (ev.firedTimers || {})[id], since: f.since ? ev[f.since] : 0 };
    };
    const celIncident = (ev) =>
      cel.value(
        "Incident",
        {
          id: ev.id, number: ev.number, eventType: ev.typeId, priority: ev.priority, occurredAt: ev.occurredAt, state: ev.state, owner: ev.owner,
          assignmentGroup: ev.assignmentGroup, holdReasonId: ev.holdReason, escalationLevel: ev.escalationLevel,
          transferCount: ev.transferCount, closeResultId: ev.closeResult, closeCauseId: ev.massCause, result: ev.closeComment,
          closedBy: ev.closedBy, closedAt: ev.closedAt, slaBreached: ev.slaBreached, breaches: ev.breaches,
          timers: Object.fromEntries(Object.keys(FIELDS).map((id) => [id, celTimer(ev, id)])),
          linkedTo: ev.linkedTo, linkedAt: ev.linkedAt, leftGroup: ev.leftGroup, scenario: ctx.scenarioKey ? ctx.scenarioKey(ev) : null,
          eventGuid: ev.eventGuid,
        },
        ev
      );
    // Факты мира (cel.world машины) — из данных сервера; «я» — оператор этого исполнителя
    const celWorld = {
      can: (who, p) => (who === ME ? ctx.can(p) : Boolean(ctx.permsOf && ctx.permsOf(who).includes(p))),
      access: (who, x) => Boolean(ctx.hasAccess && ctx.hasAccess(who, cel.source(x))),
      isOperator: (id) => Boolean(ctx.isOperator && ctx.isOperator(id)),
      isGroup: (id) => isGroup(id),
      members: (g) => (ctx.membersOf ? ctx.membersOf(g) : []),
      dutyGroups: () => (ctx.dutyGroups ? ctx.dutyGroups() : []),
      // Кому вообще можно передавать — люди и дежурные группы сервера (§8.1, BUG-85)
      transferTargets: () => (ctx.transferTargets ? ctx.transferTargets().map((o) => o.id) : []),
      inSourceGroup: (x, g) => ctx.inGroup(cel.source(x), g),
      // Условия правил по группе (§14.5): устройство в группе или во вложенной, глубина группы в дереве
      deviceInGroup: (d, g) => Boolean(ctx.deviceInGroup && ctx.deviceInGroup(d, g)),
      groupDepth: (g) => (ctx.groupDepth ? ctx.groupDepth(g) : 0),
      agentState: (who) => (who === ME ? ctx.agentState() : ctx.agentStateOf(who)),
      idleSec: (who) => (who === ME && ctx.idleSec ? Math.floor(ctx.idleSec() - (ctx.now() - now()) / 1000) : 0),
      stepsFilled: (x, setId) => ctx.stepsFilled(cel.source(x), setId),
      lastTransferTarget: (who) => (who === ME && ctx.defaultTransferTarget ? ctx.defaultTransferTarget() || "" : ""),
    };
    const celScope = (ev, opts) => ({
      me: ME,
      actor: ME,
      incident: celIncident(ev),
      incidents: () => ctx.events().map(celIncident),
      form: (opts && opts.form) || {},
      surface: (opts && opts.surface) || "",
      now: now(),
      world: celWorld,
    });

    // Определения машины (cel.definitions) для сервера и форм: адресат, отношение смотрящего, «я» как адресат
    const def = (name, ...args) => cel.call(name, args, celWorld);
    const addressee = (ev) => def("addressee", celIncident(ev)) || null;
    const ownership = (ev) => def("ownership", ME, celIncident(ev));
    const isSelf = (id) => def("isSelf", ME, id || "");
    const isTarget = (ev) => def("isTarget", ME, celIncident(ev));
    const isDone = (ev) => def("isDone", celIncident(ev));
    // Закрыт «Ложной тревогой» — для статуса тревоги в карточке (§7, ARCH-15)
    const closedFalseAlarm = (ev) => def("closedFalseAlarm", celIncident(ev));
    const hasAccess = (id, ev) => def("hasAccess", id || "", celIncident(ev));
    const canAccept = (id, ev) => def("canAccept", id || "", celIncident(ev), "");
    const norm = (ev, timerId) => cel.out(def("norm", celIncident(ev), def("timerDef", timerId)));
    // Мои инциденты в состоянии — для счётчиков сессии (§10.2): mineIn машины, привязанные не в счёт
    const units = (stateId) => new Set(Array.from(def("mineIn", ctx.events().map(celIncident), ME, stateId, ""), (x) => x.id));

    function setting(path) {
      if (typeof path !== "string") return path;
      return path.split(".").reduce((o, k) => (o == null ? o : o[k]), W);
    }

    // Первое невыполненное условие: { why, hidden } по onFail реестра; null — всё выполнено
    function firstFail(ev, guards, opts) {
      let scope = null;
      for (const g of guards || []) {
        if (!cel.hasGuard(g.fn)) return { why: ["workflow.error.guard_not_implemented", { fn: g.fn }], hidden: false, guard: g.fn };
        const why = cel.guard(g.fn, g.args || [], scope || (scope = celScope(ev, opts)), g);
        if (why) return { why, hidden: (guardRegistry[g.fn] || {}).onFail === "hide", guard: g.fn };
      }
      return null;
    }

    /* ===== Доступность и список действий (/actions, §7) ===== */

    function availability(id, ev, opts) {
      const tr = transitions[id];
      const nav = navActions[id];
      if (!ev || (!tr && !nav)) return { hidden: true };
      if (tr && !tr.from.includes(ev.state)) return { hidden: true, notFrom: true, why: ["workflow.guard.wrong_state"] };
      const fail = firstFail(ev, tr ? tr.guards : nav.guards, opts);
      // guard — какое условие не выполнено: по нему сервер выбирает код ошибки
      if (fail) return { hidden: fail.hidden, disabled: true, why: fail.why, guard: fail.guard };
      return { ok: true };
    }

    function actions(ev, surface) {
      const out = [];
      W.transitions.forEach((tr) => {
        if (tr.trigger !== "manual" || !tr.ui.surface.includes(surface)) return;
        const a = availability(tr.id, ev, { surface });
        if (a.hidden) return;
        out.push({
          id: tr.id,
          kind: "transition",
          label: tr.labelKey,
          hint: a.why || tr.hintKey || tr.labelKey,
          style: tr.ui.style || "outline",
          enabled: Boolean(a.ok),
          formId: tr.form,
          navigate: tr.ui.navigate,
        });
      });
      W.navActions.items.forEach((nav) => {
        if (!nav.surface.includes(surface)) return;
        const a = availability(nav.id, ev);
        if (a.hidden || !a.ok) return;
        out.push({ id: nav.id, kind: "nav", label: nav.labelKey, hint: nav.hintKey || nav.labelKey, style: nav.style, icon: nav.icon || null, enabled: true });
      });
      // Во главе колонки — основная кнопка (§7): «Взять», «Принять», «Продолжить», «Возобновить»;
      // за ней навигация — «Открыть», «Просмотр», потом остальные. Адресату «Принять» — первой,
      // «Открыть» — второй (BUG-60)
      const rank = (a) => (a.style === "primary" ? 0 : a.kind === "nav" ? 1 : 2);
      return out.sort((x, y) => rank(x) - rank(y));
    }

    /* ===== Выполнение перехода (/transitions, §6) ===== */

    function vars(ev, form, extra) {
      const prog = ctx.progress(ev);
      const hold = catalogItem("hold", ev.holdReason);
      return Object.assign(
        {
          comment: (form && form.comment) || "",
          stepNumber: ctx.stepNumber(ev),
          // Подстановки, которые сами переводятся, — ключом каталога (§14.9)
          holdReasonLabel: hold ? [hold.labelKey] : "",
          targetName: ctx.actorName(addressee(ev)),
          escalationLevel: ev.escalationLevel,
          closeResultLabel: closeResultLabel(ev) ? [closeResultLabel(ev)] : "",
          filledSteps: prog.filled,
          totalSteps: prog.total,
          escalationReason: [W.escalation.reasonKey],
          primaryNumber: ev.linkedTo && byId(ev.linkedTo) ? byId(ev.linkedTo).number : "",
        },
        extra || {}
      );
    }

    // Правило интерфейса машины (CEL.md, «Правила интерфейса»): бейдж, фильтр очереди, пояснение и поля формы
    const ruleOf = (where, scope, option) => cel.rule(where, scope, option) === true;
    const fieldAt = (f, field, k) => `forms.${f.id}.fields.${field.name}.${k}`;
    // Видно ли поле и обязательно ли при значениях формы из scope; невидимое — не обязательно
    function fieldRule(f, field, scope) {
      const visible = field.visibleExpr == null || ruleOf(fieldAt(f, field, "visibleExpr"), scope);
      return { visible, required: visible && ruleOf(fieldAt(f, field, "requiredExpr"), scope) };
    }

    // Ключ подписи результата; если у результата есть справочник причин и причина выбрана — подписи причины
    function closeResultLabel(ev) {
      const item = catalogItem("close_result", ev.closeResult);
      if (!item) return "";
      const cause = item.causeCatalog && ev.massCause ? catalogItem(item.causeCatalog, ev.massCause) : null;
      return cause ? cause.labelKey : item.labelKey;
    }

    // Переход атомарен (§14.1, §14.2): эффекты выполняются на черновиках инцидентов, и только если
    // все прошли без ошибки, черновики становятся инцидентами. Неизвестный эффект — ошибка, а не пропуск
    function draftOf(ev) {
      return Object.assign({}, ev, { log: ev.log.slice(), breaches: (ev.breaches || []).slice() });
    }
    function applyEffects(tr, ev, form, actor, extra) {
      return applyAll(tr, [ev], form, actor, extra);
    }
    // Что было и что стало — для события потока (§9, RULE-60): состояние, владелец, адресат, новое нарушение
    const snap = (ev) => ({ state: ev.state, owner: ev.owner, addressee: addressee(ev), breaches: (ev.breaches || []).length });
    function factsOf(before, ev) {
      const added = (ev.breaches || []).slice(before.breaches);
      return { from: before, to: snap(ev), breach: added.length ? added[added.length - 1].kind : null };
    }

    // Несколько инцидентов одним действием — тоже атомарно: либо все, либо ни один
    function applyAll(tr, list, form, actor, extra) {
      const r = applySteps([{ tr, list, form, extra }], actor);
      return r.ok ? Object.assign({ ok: true }, r.steps[0]) : r;
    }
    // Несколько переходов одной транзакцией (§11: объединение и «Взять» основного): черновики общие — следующий
    // переход видит сделанное предыдущим; ошибка в любом — не меняется ничего
    function applySteps(steps, actor) {
      const before = steps.map((st) => st.list.map(snap));
      const tx = { drafts: new Map(), insts: new Map(), after: [] };
      let done;
      try {
        done = steps.map((st) => celApply(st.tr, st.list, st.form, actor, st.extra, tx));
      } catch (err) {
        return { ok: false, why: ["workflow.error.transition_failed", { error: err.why || err.message }] };
      }
      done[done.length - 1].commit();
      // Внешние эффекты — только после применения перехода
      tx.after.forEach((fn) => fn());
      return { ok: true, steps: done.map((d, k) => ({ external: d.external, facts: steps[k].list.map((ev, i) => factsOf(before[k][i], ev)) })) };
    }

    /* ===== Эффекты машины (do, CEL.md) ===== */

    // Значение CEL инцидента → поля инцидента прототипа (обратный мост к celIncident)
    function writeBack(x, ev) {
      const o = cel.out;
      Object.assign(ev, {
        state: x.state, owner: x.owner || null, assignmentGroup: x.assignmentGroup || null, holdReason: x.holdReasonId || null,
        escalationLevel: o(x.escalationLevel), transferCount: o(x.transferCount), closeResult: x.closeResultId || null,
        massCause: x.closeCauseId || null, closeComment: x.result || null, closedBy: x.closedBy || null, closedAt: o(x.closedAt) || null,
        slaBreached: x.slaBreached, breaches: x.breaches.map((b) => ({ kind: b.kind, at: o(b.at), owner: b.owner || null })),
        linkedTo: x.linkedTo || null, linkedAt: o(x.linkedAt) || null,
        leftGroup: x.leftGroup.primaryId ? { primaryId: x.leftGroup.primaryId, linkedAt: o(x.leftGroup.linkedAt), at: o(x.leftGroup.at) } : null,
      });
      const fired = Object.assign({}, ev.firedTimers);
      Object.entries(FIELDS).forEach(([id, f]) => {
        const t = x.timers.get(id);
        ev[f.due] = o(t.due) || null;
        if (f.left) ev[f.left] = t.paused ? o(t.left) : null;
        if (f.since) ev[f.since] = o(t.since) || null;
        if (t.fired) fired[id] = o(t.fired);
        else delete fired[id];
      });
      ev.firedTimers = fired;
    }
    // Эффекты перехода на черновиках: инциденты перехода и те, кого эффекты коснулись. Журнал, курсор
    // сценария и перенос ответов — в черновики; уведомления, внешние команды, вытеснение карточки, новая
    // версия — после применения (after). opts.before — инцидент «до» вместо черновика (окно после дедлайна)
    function celApply(tr, list, form, actor, extra, tx) {
      const { drafts, insts, after } = tx || { drafts: new Map(), insts: new Map(), after: [] };
      const own = new Map(list.map((ev) => [ev.id, ev]));
      const real = (id) => own.get(id) || byId(id);
      const draft = (id) => drafts.get(id) || (drafts.set(id, draftOf(real(id))), drafts.get(id));
      const inst = (id) => insts.get(id) || (insts.set(id, celIncident(drafts.get(id) || real(id))), insts.get(id));
      let cur = null;
      const store = {
        incidents: () => ctx.events().map((e) => inst(e.id)),
        touch: (x) => writeBack(x, draft(x.id)),
        world: (action, a) => {
          const target = a.incident || a.from ? draft((a.incident || a.from).id) : null;
          if (action === "log") {
            const v = a.vars != null ? cel.out(a.vars) : vars(target, cur.form, { previousOwnerName: cur.previousOwnerName });
            const same = a.once ? target.log.find((x) => x.k === a.key && x.at === now()) : null;
            if (same) same.v = v;
            else ctx.log(target, a.actor || cur.actor, a.key, v, now());
          } else if (action === "setCursor") {
            if (ctx.setCursor) ctx.setCursor(target);
          } else if (action === "shareAnswers") {
            // Перенос — в черновик основного: следующий привязываемый видит уже перенесённое
            if (!a.to || !real(a.to)) return;
            const p = draft(a.to);
            const n = ctx.shareAnswers ? ctx.shareAnswers(target, p, now()) : 0;
            if (n && a.logKey) ctx.log(p, cur.actor, a.logKey, { number: target.number, n }, now());
          } else if (action === "notify") {
            // Уведомление (§9): кому, кто получит и запись «некому» — выражения машины; сервер только доставляет
            const { actor: who, transitionId } = cur;
            const id = target.id;
            const recipients = Array.from(a.recipients || [], String);
            cur.external.push({ fn: "notify", target: a.to });
            after.push(() => {
              const inc = real(id);
              if (ctx.deliver) ctx.deliver(inc, recipients, { alert: Boolean(a.alert), transitionId });
              if (!recipients.length && a.emptyLog) ctx.log(inc, who, a.emptyLog, {}, now());
            });
          } else if (action === "command") {
            cur.external.push({ fn: "externalCommand", target: a.command });
          } else if (action === "evict") {
            // Кто увёл карточку — тот, кто выполнил переход: себе о своей передаче интерфейс не говорит (BUG-86)
            const { transitionId, actor: by } = cur;
            const who = a.who || null;
            const id = target.id;
            after.push(() => ctx.onEvict && ctx.onEvict(real(id), who, transitionId, by));
          } else if (action === "touch") {
            const id = target.id;
            after.push(() => ctx.onBreachShared && ctx.onBreachShared(real(id)));
          }
        },
      };
      const external = list.map((ev) => {
        draft(ev.id);
        const d = drafts.get(ev.id);
        const before = (extra && extra.before) || celIncident(d);
        cur = { form: form || {}, actor, transitionId: tr.id, previousOwnerName: ctx.actorName(def("addressee", before) || null), external: [] };
        if (tr.to) d.state = tr.to;
        insts.set(ev.id, celIncident(d));
        const scope = { me: ME, actor, incident: insts.get(ev.id), before, form: form || {}, now: now(), deadline: extra && extra.deadline != null ? extra.deadline : null, world: celWorld };
        tr.effects.forEach((e) => {
          if (!cel.hasEffect(e.fn)) throw Object.assign(new Error(e.fn), { why: ["workflow.error.effect_not_implemented", { fn: e.fn }] });
          cel.effect(e.fn, e.args, scope, store);
        });
        // Внешние эффекты для ответа перехода (§14.2, TransitionResult.externalEffects) — те, что выполнили
        // операции эффектов: кому уведомление или какая команда
        return cur.external;
      });
      return {
        external,
        after,
        // Момент последнего перехода инцидента — ядру: переход по молчанию не раньше него (BUG-76)
        commit: () => drafts.forEach((d, id) => Object.assign(real(id), d, { changedAt: now() })),
      };
    }

    // Проверка формы (§14.8: form.*): обязательные поля и комментарий по строке справочника. Значение поля-списка —
    // по тем же правилам, что варианты формы (ARCH-09): поле видно, значение — среди вариантов (источник, optionExpr)
    // и доступно (enabledExpr). Иначе — code: значение недопустимо, а не пропущено
    function validateForm(tr, ev, form, surface) {
      const f = tr.form ? forms[tr.form] : null;
      if (!f) return null;
      const scope = celScope(ev, { form, surface });
      for (const field of f.fields) {
        const v = form[field.name];
        const empty = v == null || String(v).trim() === "";
        const rule = fieldRule(f, field, scope);
        if (rule.required && empty) {
          return { why: field.kind === "text" ? ["workflow.error.reason_required"] : ["workflow.error.field_required", { name: [field.labelKey] }] };
        }
        if (!field.source || empty) continue;
        const offered =
          rule.visible &&
          candidates(field, ev).some((o) => o.id === v) &&
          (field.optionExpr == null || ruleOf(fieldAt(f, field, "optionExpr"), scope, v)) &&
          (field.enabledExpr == null || ruleOf(fieldAt(f, field, "enabledExpr"), scope, v));
        if (!offered) return { why: ["workflow.error.field_invalid", { name: [field.labelKey] }], code: "FORM_FIELD_INVALID" };
      }
      return null;
    }

    function run(id, ev, form, opts) {
      const tr = transitions[id];
      if (!tr) return { ok: false, why: ["workflow.error.unknown_action"] };
      form = form || {};
      const a = availability(id, ev, { form, surface: opts && opts.surface });
      if (!a.ok) return { ok: false, why: a.why };
      const bad = validateForm(tr, ev, form, opts && opts.surface);
      if (bad) return { ok: false, why: bad.why, code: bad.code };
      const canceled = windowBefore(ev, id);
      const applied = applyEffects(tr, ev, form, ME);
      if (!applied.ok) {
        windowUndo(ev, canceled);
        return applied;
      }
      const facts = applied.facts[0];
      windowAfter(ev, canceled, facts);
      return { ok: true, navigate: tr.ui.navigate, external: applied.external[0], facts, canceled: canceled ? canceled.tr.id : null };
    }

    // Ручное действие в окне после дедлайна выигрывает у таймера (§10.1, правило 5; RULE-63) — у одиночного
    // перехода и у объединения (BUG-62). До эффектов: отменённое срабатывание отмечено, чьё нарушение — запомнено
    function windowBefore(ev, id) {
      const canceled = overridden(ev, id);
      if (!canceled) return null;
      // Инцидент до действия: нарушение — на того, кто был адресатом в момент дедлайна
      canceled.before = celIncident(ev);
      canceled.logAt = ev.log.length;
      canceled.firedBefore = ev.firedTimers;
      ev.firedTimers = Object.assign({}, ev.firedTimers, { [canceled.timer]: canceled.due });
      return canceled;
    }
    // Переход не применился — отметка снимается: таймер по окончании окна сработает, нарушение не теряется
    function windowUndo(ev, canceled) {
      if (canceled) ev.firedTimers = canceled.firedBefore;
    }
    // После эффектов: нарушение — то, что записал бы отменённый переход, — его же эффектом recordBreach машины,
    // на момент дедлайна и на адресата до действия; запись в журнал — перед записью о самом действии
    function windowAfter(ev, canceled, facts) {
      if (!canceled) return;
      canceled.tr.effects.filter((x) => x.fn === "recordBreach").forEach((x) => {
        const done = celApply({ id: canceled.tr.id, to: null, effects: [x] }, [ev], {}, "dispatcher", { deadline: canceled.due, before: canceled.before });
        done.commit();
        done.after.forEach((fn) => fn());
        facts.breach = x.args[0];
      });
      ctx.log(ev, "dispatcher", "workflow.journal.timer_overridden", { timer: [timers[canceled.timer].labelKey], transition: [canceled.tr.labelKey] }, now());
      ev.log.splice(canceled.logAt, 0, ev.log.pop());
    }

    // Переход по таймеру, чей дедлайн наступил, а окно ещё не кончилось: ручное действие его отменяет (RULE-63)
    function overridden(ev, manualId) {
      if (!GRACE_MS) return null;
      let found = null;
      W.transitions.forEach((tr) => {
        if (tr.trigger !== "timer" || !tr.from.includes(ev.state)) return;
        const g = (tr.guards || []).find((x) => x.fn === "timerExpired");
        const due = g ? dueOf(ev, g.args[0]) : null;
        if (!due || due > now() || due + GRACE_MS <= now() || (ev.firedTimers || {})[g.args[0]] === due) return;
        // Таймер после ручного перехода продолжается (continuesOn) — окно срабатывание не отменяет:
        // переход по таймеру выполнится по окончании окна, уже из нового состояния (RULE-83)
        if ((timers[g.args[0]].continuesOn || []).includes(manualId)) return;
        at = due;
        const fail = firstFail(ev, tr.guards);
        at = null;
        if (!fail && (!found || due < found.due)) found = { tr, timer: g.args[0], due };
      });
      return found;
    }

    // Появление инцидента (§6.2, RULE-61): переход машины с trigger: event — без исходного состояния,
    // от имени его actor. Его выполняет появление, а не кнопка и не планировщик
    function create(ev) {
      const tr = W.transitions.find((t) => t.trigger === "event");
      if (!tr) return { ok: false, why: ["workflow.error.unknown_action"] };
      const applied = applyEffects(tr, ev, {}, tr.actor || "dispatcher");
      return applied.ok ? Object.assign(applied, { facts: applied.facts[0] }) : applied;
    }

    /* ===== Событие через правила (§14.5, раздел intake машины) ===== */

    // Правило сервера → Rule машины: поля условия — по именам машины, необязательные — opt; createdAt — мс
    const celRule = (r) =>
      cel.value(
        "Rule",
        {
          guid: r.guid, priority: r.priority, createdAt: r.createdAt, scenarios: r.scenarios || [],
          conditions: (r.conditions || []).map((c) => ({ eventType: c.eventTypeId, device: c.deviceGuid, deviceType: c.deviceTypeId, group: c.sourceGroupGuid })),
        },
        r
      );
    // Какие инциденты даёт событие: по сценарию подошедших правил (intake.match) — правило-победитель (первое из
    // intake.winner). Порядок создания — чей победитель старше (ruleBeats), сценарии одного правила — по его списку,
    // полное равенство — порядок списка правил. Ответ — [{ scenario, rule }] с правилами сервера; пусто — инцидентов нет
    function intake(rules, event) {
      const I = W.intake;
      const e = cel.value("Event", event);
      const all = rules.map(celRule);
      const scenarios = [...new Set(all.filter((r) => def(I.match, r, e)).flatMap((r) => Array.from(r.scenarios)))];
      const picks = scenarios.map((s) => ({ scenario: s, rule: def(I.winner, all, e, s)[0] }));
      const beats = (a, b) => def("ruleBeats", a, b, e);
      picks.sort((x, y) =>
        x.rule === y.rule
          ? x.rule.scenarios.indexOf(x.scenario) - y.rule.scenarios.indexOf(y.scenario)
          : beats(x.rule, y.rule) ? -1 : beats(y.rule, x.rule) ? 1 : all.indexOf(x.rule) - all.indexOf(y.rule)
      );
      return picks.map((p) => ({ scenario: p.scenario, rule: cel.source(p.rule) }));
    }

    /* ===== Автоматические переходы (§6.2): планировщик ===== */

    // Автоматические и системные переходы машины (trigger: timer / system), чьи условия
    // выполнены. Таймер, по которому срабатывает переход, — из его условия timerExpired.
    // scope: incidents_owned_by_agent — только инциденты текущего оператора (перерыв, §12.2)
    // agentOnly — только переходы, привязанные к оператору (scope: incidents_owned_by_agent):
    // так сервер проверяет состояние каждого оператора, не запуская общие таймеры повторно
    // Порядок (RULE-41): из готовых переходов инцидента первым — тот, чьё условие наступило раньше,
    // при равенстве — по порядку в машине; после каждого — выбор заново. Тогда результат тот же, как
    // если бы планировщик проверял каждую секунду, — и после простоя сервиса (§9, §14.3).
    // after — момент перехода, выполненного перед этим над тем же инцидентом (RULE-48): то, что он
    // сделал возможным, наступает не раньше него; переход без таймера — сразу после него.
    // Момент перехода по таймеру — дедлайн; окно после него (RULE-63) ждёт только действия человека
    // since — с какого момента системный переход без таймера возможен: был готов до догона — сейчас; стал
    // готов после перехода в этом такте — в момент того перехода (ARCH-13). Так и переход, который стал возможен
    // после другого перехода того же инцидента, наступает не раньше него (RULE-48)
    function momentOf(ev, tr, since) {
      let moment = null;
      for (const g of tr.guards || []) {
        if (g.fn === "timerExpired") {
          const due = dueOf(ev, g.args[0]);
          if (!due) return null;
          moment = Math.max(moment || 0, due);
        } else if (g.fn === "agentIdleFor") {
          if (!ctx.idleSec) return null;
          // Не раньше последнего перехода инцидента: молчание сделало переход возможным, только когда
          // инцидент уже был таким (RULE-48, BUG-76)
          moment = Math.max(moment || 0, ctx.now() - ctx.idleSec() * 1000 + setting(g.args[0]) * 1000, ev.changedAt || 0);
        }
      }
      return moment == null ? since : moment;
    }
    // Что выполнил бы планировщик у инцидента следующим: переход и момент; null — ничего
    function nextOf(ev, s, agentOnly) {
      const ready = [];
      W.transitions.forEach((tr) => {
        if (tr.trigger !== "timer" && tr.trigger !== "system") return;
        if (agentOnly && tr.trigger === "system" && tr.scope !== "incidents_owned_by_agent") return;
        if (!tr.from.includes(ev.state)) return;
        if (tr.scope === "incidents_owned_by_agent" && ev.owner !== ME) return;
        const key = `${ev.id}|${tr.id}`;
        const moment = momentOf(ev, tr, s.since.has(key) ? s.since.get(key) : s.lastRun != null ? s.lastRun : ctx.now());
        if (moment == null || moment > ctx.now() || s.done.has(`${key}@${moment}`)) return;
        at = moment;
        const fail = firstFail(ev, tr.guards);
        at = null;
        if (fail) s.since.delete(key);
        else {
          if (!s.since.has(key)) s.since.set(key, moment);
          ready.push({ tr, moment });
        }
      });
      // Переход по таймеру ждёт окна после дедлайна (RULE-63), но только действия человека: готов
      // системный — переход по таймеру первым, как без окна, и нарушение не теряется (RULE-67).
      // Без системного проверка оператора (agentOnly) общих таймеров не запускает
      const system = ready.some((c) => c.tr.trigger === "system");
      let next = null;
      ready.forEach((c) => {
        if (c.tr.trigger === "timer" && !system && (agentOnly || c.moment + GRACE_MS > ctx.now())) return;
        if (!next || c.moment < next.moment) next = c;
      });
      if (!next) return null;
      // Выполняется по таймеру — после окна, но не позже готового системного: тогда и при прыжке
      // часов оба — в момент системного, как при шагах (BUG-38). Не раньше перехода, выполненного в
      // такте до него: его сделанное этот переход уже видит (ARCH-13). Раньше бывает, только если условие
      // перехода по таймеру зависит от другого инцидента — таких в машине нет, это защита
      const sysAt = Math.min(ctx.now(), ...ready.filter((c) => c.tr.trigger === "system").map((c) => c.moment));
      const runAt = next.tr.trigger === "timer" ? Math.min(Math.max(next.moment + GRACE_MS, s.last.get(ev.id) || 0), sysAt) : next.moment;
      return { ev, tr: next.tr, moment: next.moment, runAt: Math.max(runAt, s.lastRun || 0) };
    }
    // Такт планировщика — догон в общем порядке по времени (§14.3, ARCH-13): из готовых у всех инцидентов
    // первым — переход с самым ранним моментом, при равенстве — инцидент раньше по списку; после каждого —
    // выбор заново. Так переход одного инцидента, который открыл переход другого, наступает раньше, и после
    // простоя исход тот же, что при проверке каждую секунду
    function tick(opts) {
      const changed = [];
      const agentOnly = Boolean(opts && opts.agentOnly);
      // Один и тот же переход инцидента в один и тот же момент — не больше раза за такт, у инцидента — не больше
      // 50 переходов: ошибка в условии не зациклит планировщик
      const s = { done: new Set(), last: new Map(), count: new Map(), since: new Map(), lastRun: null };
      for (;;) {
        let best = null;
        ctx.events().forEach((ev) => {
          if (isDone(ev) || (s.count.get(ev.id) || 0) >= 50) return;
          const c = nextOf(ev, s, agentOnly);
          if (c && (!best || c.runAt < best.runAt)) best = c;
        });
        if (!best) break;
        const { ev, tr, runAt } = best;
        s.done.add(`${ev.id}|${tr.id}@${best.moment}`);
        s.count.set(ev.id, (s.count.get(ev.id) || 0) + 1);
        at = runAt;
        let facts = null;
        try {
          const timerGuard = (tr.guards || []).find((g) => g.fn === "timerExpired");
          const deadline = timerGuard ? dueOf(ev, timerGuard.args[0]) : null;
          if (timerGuard) markFired(ev, timerGuard.args[0]);
          const applied = applyEffects(tr, ev, {}, tr.actor || "dispatcher", { deadline });
          if (applied.ok) facts = applied.facts[0];
        } finally {
          at = null;
        }
        if (!facts) continue;
        s.last.set(ev.id, runAt);
        s.lastRun = runAt;
        changed.push({ id: ev.id, transition: tr.id, facts });
      }
      return changed;
    }

    function timerEffect(fn, ev, args) {
      const done = celApply({ id: fn, to: null, effects: [{ kind: "transactional", fn, args }] }, [ev], {}, "dispatcher");
      done.commit();
    }

    // Можно ли править шаги сценария (§10.4, scenarioEdit машины); нет — карточка на просмотр
    const canEditScenario = (ev) => Boolean(ev) && !firstFail(ev, W.scenarioEdit.guards);

    /* ===== Формы, бейджи, массовые действия ===== */

    function noteFor(f, ev, scope, extra) {
      const note = (f.notes || []).find((n, i) => ruleOf(`forms.${f.id}.notes.${i}.expr`, scope));
      if (!note) return null;
      const prog = ctx.progress(ev);
      return [
        note.textKey,
        Object.assign(
          {
            ownerName: ctx.actorName(addressee(ev)),
            filledSteps: prog.filled,
            totalSteps: prog.total,
            minutesSinceClose: Math.max(1, Math.round((now() - (ev.closedAt || now())) / 60000)),
          },
          extra || {}
        ),
      ];
    }

    // Варианты поля-списка до отбора: адресаты передачи — от сервера, иначе — позиции справочника
    function candidates(field, ev) {
      if (field.source === "transferTargets") return ctx.transferTargets(ev);
      const catalog = catalogs[String(field.source).replace("reasonCatalog:", "")];
      return catalog ? catalog.items.map((i) => ({ id: i.id, label: i.labelKey })) : [];
    }

    // Форма перехода под оператора и инцидент: варианты полей — те, что пропускает optionExpr, недоступные по
    // enabledExpr — с причиной disabledKey; значение по умолчанию — defaultExpr, если это доступный вариант.
    // rules — видно ли поле и обязательно ли; зависит от поля формы — таблицей по его вариантам (dependsOn, byValue)
    function form(formId, ev, opts) {
      const f = forms[formId];
      if (!f) return null;
      const scope = celScope(ev, { surface: opts && opts.surface });
      const fields = f.fields.map((field) => {
        if (!field.source) return { field, options: null, defaultValue: null };
        const options = candidates(field, ev)
          .filter((o) => field.optionExpr == null || ruleOf(fieldAt(f, field, "optionExpr"), scope, o.id))
          .map((o) => (field.enabledExpr == null || ruleOf(fieldAt(f, field, "enabledExpr"), scope, o.id) ? o : Object.assign({}, o, { disabled: true, why: field.disabledKey })));
        const d = field.defaultExpr != null ? cel.rule(fieldAt(f, field, "defaultExpr"), scope) : "";
        return { field, options, defaultValue: d && options.some((o) => o.id === d && !o.disabled) ? d : null };
      });
      const optionsOf = (name) => (fields.find((x) => x.field.name === name) || {}).options || [];
      return {
        id: f.id,
        title: f.titleKey,
        confirmLabel: f.confirmKey,
        style: f.style,
        note: noteFor(f, ev, scope, opts && opts.noteVars),
        fields: fields.map(({ field, options, defaultValue }) => {
          const dep = ["requiredExpr", "visibleExpr"].flatMap((k) => cel.formRefs(fieldAt(f, field, k)))[0];
          let rules = fieldRule(f, field, scope);
          if (dep) {
            const byValue = Object.fromEntries(["", ...optionsOf(dep).map((o) => o.id)].map((v) => [v, fieldRule(f, field, Object.assign({}, scope, { form: { [dep]: v } }))]));
            rules = Object.assign({ dependsOn: dep, byValue }, byValue[""]);
          }
          return { name: field.name, kind: field.kind, labelKey: field.labelKey, source: field.source || null, options, defaultValue, rules };
        }),
      };
    }

    // Бейдж под смотрящего оператора (§2.4): первое правило машины, чьё выражение истинно
    function badge(ev) {
      const scope = celScope(ev);
      const rule = W.badges.rules.find((r, i) => ruleOf(`badges.rules.${i}.expr`, scope));
      if (!rule) return { label: [states[ev.state].labelKey], style: ev.state };
      const hold = catalogItem("hold", ev.holdReason);
      return {
        label: [rule.labelKey, { ownerName: ctx.actorName(addressee(ev)), holdReasonLabel: hold ? [hold.labelKey] : "", closeResultLabel: closeResultLabel(ev) ? [closeResultLabel(ev)] : "" }],
        style: rule.style,
      };
    }

    // Пояснение в карточке (cardNotes машины, §6.3): первое правило, чьё выражение истинно; actions — доступные
    // смотрящему действия карточки (уже посчитаны — переданы, иначе считаются). [ключ, подстановки] и вид плашки; нет правила — null
    function cardNote(ev, enabledIds) {
      const actionIds = enabledIds || actions(ev, "card").filter((a) => a.enabled).map((a) => a.id);
      const scope = Object.assign(celScope(ev, { surface: "card" }), { actions: actionIds });
      const i = ((W.cardNotes || {}).rules || []).findIndex((n, k) => ruleOf(`cardNotes.rules.${k}.expr`, scope));
      if (i < 0) return null;
      const n = W.cardNotes.rules[i];
      const hold = catalogItem("hold", ev.holdReason);
      const label = closeResultLabel(ev);
      return {
        note: [
          n.textKey,
          {
            who: ctx.actorName(addressee(ev)),
            owner: ctx.actorName(ev.owner),
            level: ev.escalationLevel || 0,
            why: label ? [label] : "",
            holdReason: hold ? [hold.labelKey] : "",
            primaryNumber: ev.linkedTo && byId(ev.linkedTo) ? byId(ev.linkedTo).number : "",
          },
        ],
        style: n.style || "",
      };
    }

    const bulk = (id) => (transitions[id] && transitions[id].bulk) || { allowed: false };

    // Фильтры очереди машины (queueFilters), которые проходит инцидент для этого оператора. В списках —
    // инциденты хотя бы одного фильтра: привязанные объединённого живут в карточке основного (§11)
    const queueFilters = (ev) => {
      const scope = celScope(ev);
      return W.queueFilters.filter((q) => ruleOf(`queueFilters.${q.id}.expr`, scope)).map((q) => q.id);
    };
    const inQueueFilter = (ev, filterId) => !W.queueFilters.some((q) => q.id === filterId) || ruleOf(`queueFilters.${filterId}.expr`, celScope(ev));

    // Производное состояние оператора (session.states[].derived машины, §12, RULE-99): не хранится, показывается
    // вместо хранимого derived.of, когда его выражение истинно; смены состояния идут от хранимого
    const shownAgentState = (stored) => {
      const scope = { me: ME, actor: ME, incident: undefined, incidents: () => ctx.events().map(celIncident), form: {}, surface: "", now: now(), world: celWorld };
      const d = W.session.states.find((s) => s.derived && s.derived.of === stored && ruleOf(`session.states.${s.id}.derived.expr`, scope));
      return d ? d.id : stored;
    };

    // «Взять в работу» на выборке (§11): переход с bulk.mode merge на каждом, кроме основного,
    // и, если основной новый, — grouping.takeWith на нём. Всё или ничего: сначала проверка всех
    function mergeCheck(primary, others) {
      const tr = W.transitions.find((t) => t.bulk && t.bulk.mode === "merge");
      if (!tr) return { ok: false, why: ["workflow.error.unknown_action"] };
      const form = { primaryId: primary.id };
      for (const ev of others) {
        const a = availability(tr.id, ev, { form });
        // ev — какой из объединяемых не проходит: панель выборки называет его номер
        if (!a.ok) return { ok: false, why: a.why, guard: a.guard, ev };
      }
      const take = W.transitions.find((t) => t.id === W.grouping.takeWith);
      const taking = Boolean(take && take.from.includes(primary.state));
      if (taking) {
        const a = availability(take.id, primary);
        if (!a.ok) return { ok: false, why: a.why, guard: a.guard, ev: primary };
      }
      return { ok: true, tr, form, take: taking ? take : null };
    }
    // Один переход на нескольких инцидентах — всё или ничего (§11, ARCH-08 в6): сначала условия всех, потом
    // эффекты на одних черновиках; окно после дедлайна — у каждого. Не проходит — какой (ev) и почему
    function runAll(id, list, form, opts) {
      const tr = transitions[id];
      if (!tr) return { ok: false, why: ["workflow.error.unknown_action"] };
      for (const ev of list) {
        const a = availability(id, ev, { form, surface: opts && opts.surface });
        if (!a.ok) return { ok: false, why: a.why, guard: a.guard, notFrom: a.notFrom, ev };
        const bad = validateForm(tr, ev, form || {}, opts && opts.surface);
        if (bad) return { ok: false, why: bad.why, code: bad.code, ev };
      }
      const canceled = list.map((ev) => windowBefore(ev, id));
      const applied = applyAll(tr, list, form || {}, ME);
      if (!applied.ok) {
        list.forEach((ev, i) => windowUndo(ev, canceled[i]));
        return applied;
      }
      list.forEach((ev, i) => windowAfter(ev, canceled[i], applied.facts[i]));
      return applied;
    }
    function merge(primary, others) {
      const check = mergeCheck(primary, others);
      if (!check.ok) return check;
      // Окно после дедлайна — как у одиночного перехода: у каждого привязанного и у основного, если его берут (BUG-62)
      const canceled = others.map((ev) => windowBefore(ev, check.tr.id));
      const primaryCanceled = check.take ? windowBefore(primary, check.take.id) : null;
      // Объединение и «Взять» основного — одна транзакция: не прошло одно — не меняется ничего
      const steps = [{ tr: check.tr, list: others, form: check.form }].concat(check.take ? [{ tr: check.take, list: [primary], form: {} }] : []);
      const applied = applySteps(steps, ME);
      if (!applied.ok) {
        others.forEach((ev, i) => windowUndo(ev, canceled[i]));
        windowUndo(primary, primaryCanceled);
        return applied;
      }
      const [joined, taken] = applied.steps;
      others.forEach((ev, i) => windowAfter(ev, canceled[i], joined.facts[i]));
      if (taken) windowAfter(primary, primaryCanceled, taken.facts[0]);
      return Object.assign({ ok: true, transitionId: check.tr.id }, joined, taken ? { taken: { transitionId: check.take.id, facts: taken.facts[0] } } : {});
    }

    return {
      workflow: W,
      transition: (id) => transitions[id] || null,
      nav: (id) => navActions[id] || null,
      isNav: (id) => Boolean(navActions[id]),
      isDone,
      closedFalseAlarm,
      isTarget,
      isSelf,
      addressee,
      ownership,
      inQueueFilter,
      queueFilters,
      shownAgentState,
      availability,
      actions,
      session: W.session,
      run,
      create,
      intake,
      form,
      badge,
      cardNote,
      bulk,
      norm,
      // Инцидент так, как его видят выражения машины: для сверки с моделью Quint (tools/check_quint_replay.mjs)
      celView: (ev) => cel.plain(celIncident(ev)),
      // Ключи порядка очереди (queueSort.keys машины): меньше — выше
      sortKeys: (ev, orderId) => {
        const scope = celScope(ev);
        return ((W.queueSort.keys || {})[orderId] || []).map((k, i) => Number(cel.rule(`queueSort.keys.${orderId}.${i}`, scope)));
      },
      // На месте ли человек (onDuty машины): для подписей «кого нет» у адресатов
      onDuty: (id) => def("onDuty", id || ""),
      // Основной при объединении, если его не назвал оператор (§11): mergePrimary машины; нет — null
      mergePrimary: (list) => {
        const r = def("mergePrimary", Array.from(list, celIncident), ME);
        return r.length ? cel.source(r[0]) : null;
      },
      hasAccess,
      canAccept,
      // Таймеры при загрузке набора — эффектами машины, без перехода
      startTimer: (ev, id, mode) => timerEffect("startTimer", ev, [id, mode]),
      stopTimer: (ev, id) => timerEffect("stopTimer", ev, [id]),
      pauseTimer: (ev, id) => timerEffect("pauseTimer", ev, [id]),
      resumeTimer: (ev, id) => timerEffect("resumeTimer", ev, [id]),
      tick,
      canEditScenario,
      closeResultLabel,
      merge,
      mergeCheck,
      runAll,
      units,
    };
  }

  window.IMEngine = { create };
})();
