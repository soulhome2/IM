/* Исполнитель машины состояний в браузере: Specification/Workflow_machine/workflow_schema.v4.json,
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
    const isMine = (ev) => ev.owner === ME;
    // «Я» как адресат: сам оператор и группы, в которые он входит (§10.1)
    const isSelf = (id) => Boolean(id) && (id === ME || (isGroup(id) && ctx.memberOf(id, ME)));
    // Адресат: владелец-человек, а пока группа не приняла — сама группа (assignment_group, §8.1)
    const addressee = (ev) => ev.owner || ev.assignmentGroup || null;
    const isTarget = (ev) => isSelf(addressee(ev));
    const isDone = (ev) => states[ev.state] && states[ev.state].category === "done";
    // Объединение (§11): основной инцидент привязанного — по linkedTo
    const byId = (id) => (id ? ctx.events().find((e) => e.id === id) || null : null);
    const unowned = (ev) => !ev.owner && !ev.assignmentGroup;
    // Отношение смотрящего к инциденту (§2.4). Инцидент, ожидающий моего принятия, — «мне
    // адресован», даже если владельцем записан я сам: так передают лично оператору
    function ownership(ev) {
      if (ev.state === "pending_acceptance" && isTarget(ev)) return "target";
      if (isMine(ev)) return "owner";
      return isTarget(ev) ? "target" : "other";
    }
    // Условие «отношение ко мне» в scopeRule: владелец — это мой инцидент, адресат — адресованный мне
    const matchesOwnership = (ev, role) => (role === "owner" ? isMine(ev) : role === "target" ? isTarget(ev) : ownership(ev) === role);
    const asList = (v) => (Array.isArray(v) ? v : [v]);
    const catalogItem = (catalog, id) => (catalogs[catalog] ? catalogs[catalog].items.find((i) => i.id === id) : null);
    const refToId = (ref) => (typeof ref === "string" && ref.includes(":") ? ref.split(":")[1] : ref);
    // Следующий уровень автоэскалации (§8.3): ближайший выше текущего и не выше потолка, адресат
    // которого может принять — право «Принимать» и доступ к объекту (§5, §8.1); остальные пропускаются.
    // Пропускается и уровень, где принять может только тот, у кого инцидент уже есть: его адресат или
    // группа, где принять может только владелец, — как «Исключение владельца» у передачи (RULE-93)
    const nextLevel = (ev) =>
      W.escalation.levels
        .filter((l) => l.level > ev.escalationLevel && l.level <= W.escalation.maxLevel)
        .sort((a, b) => a.level - b.level)
        .find((l) => {
          const target = refToId(l.targetRef);
          if (target === addressee(ev)) return false;
          return !ctx.canAccept || ctx.canAccept(target, ev, ev.owner);
        }) || null;

    /* ===== Нормативы (§4, правило 2) ===== */

    // Самая специфичная строка overrides, иначе byPriority, иначе defaultSec
    function baseNorm(ev, timerId) {
      const t = timers[timerId];
      let best = null;
      let bestScore = -1;
      (t.overrides || []).forEach((o) => {
        const keys = Object.keys(o).filter((k) => k !== "sec");
        const match = keys.every((k) =>
          k === "eventType" ? o[k] === ev.typeId : k === "sourceGroup" ? ctx.inGroup(ev, o[k]) : o[k] === ev[k]
        );
        if (match && keys.length > bestScore) {
          best = o.sec;
          bestScore = keys.length;
        }
      });
      if (best != null) return best;
      if (t.byPriority && t.byPriority[ev.priority] != null) return t.byPriority[ev.priority];
      return t.defaultSec;
    }

    // Норматив реакции уровня автоэскалации (§8.3)
    // Уровень 0 — инцидент не эскалировался: обычный норматив (передача уровень не меняет, RULE-76)
    function levelNorm(ev, level) {
      const levels = W.escalation.levels;
      const found = level > 0 ? levels.find((l) => l.level === level) || levels[levels.length - 1] : null;
      return found ? found.reactionSec : baseNorm(ev, "reaction");
    }

    /* ===== Таймеры: дедлайны — метки времени (§4, правило 1) ===== */

    // Где у инцидента прототипа лежат дедлайн и остаток таймера (deadlineField машины)
    const FIELDS = {
      reaction: { due: "reactionDueAt" },
      resolution: { due: "resolutionDueAt", left: "resolutionLeftMs" },
      hold: { due: "holdDueAt", since: "holdSince" },
    };
    const dueOf = (ev, id) => ev[FIELDS[id].due];
    // Чьё нарушение у привязанного инцидента: владельца основного (§11.4)
    const breachOwnerOfLinked = (ev) => {
      const p = ev.linkedTo && ctx.events().find((x) => x.id === ev.linkedTo);
      return p ? addressee(p) : null;
    };

    // Длительность таймера: из справочника (secFrom, например срок удержания по причине),
    // по уровню эскалации или по нормативам (§4)
    function timerSec(ev, id, arg) {
      const t = timers[id];
      if (t.secFrom) {
        const [catalog, attr] = t.secFrom.replace("reasonCatalogs.", "").split("[].");
        const item = catalogItem(catalog, ev.holdReason);
        return item ? item[attr] * (attr === "maxMinutes" ? 60 : 1) : null;
      }
      if (arg === "byEscalationLevel" || arg === "escalation.level.reactionSec") return levelNorm(ev, ev.escalationLevel);
      if (typeof arg === "number") return arg;
      return baseNorm(ev, id);
    }

    // Таймер с startsOnce запускается один раз за жизнь инцидента: дальше start = продолжить с остатка
    function startTimer(ev, id, arg) {
      const t = timers[id];
      if (t.startsOnce) return resumeTimer(ev, id);
      const sec = timerSec(ev, id, arg);
      ev[FIELDS[id].due] = sec == null ? null : now() + sec * 1000;
      if (FIELDS[id].since) ev[FIELDS[id].since] = now();
    }
    function stopTimer(ev, id) {
      if (timers[id].startsOnce) return pauseTimer(ev, id);
      ev[FIELDS[id].due] = null;
      if (FIELDS[id].since) ev[FIELDS[id].since] = null;
    }
    // Пауза и продолжение — только у таймеров с pausable (норматив закрытия, RULE-07)
    function pauseTimer(ev, id) {
      const f = FIELDS[id];
      if (!timers[id].pausable || !f.left) return stopTimer(ev, id);
      if (ev[f.due]) ev[f.left] = Math.max(0, ev[f.due] - now());
      ev[f.due] = null;
    }
    function resumeTimer(ev, id) {
      const f = FIELDS[id];
      if (!timers[id].pausable || !f.left) return startTimer(ev, id);
      if (ev[f.due]) return;
      const left = ev[f.left] != null ? ev[f.left] : timerSec(ev, id) * 1000;
      // Истёкший и уже сработавший норматив (RULE-50): возврат в работу не даёт нового срока —
      // остаётся прежний дедлайн, он отработан. Новый запуск — только restartTimer (переоткрытие)
      const fired = ev.firedTimers && ev.firedTimers[id];
      if (left === 0 && fired) {
        ev[f.due] = fired;
        ev[f.left] = null;
        return;
      }
      ev[f.due] = now() + left;
      ev[f.left] = null;
    }

    // Срабатывание по дедлайну — один раз на каждый дедлайн, как у планировщика на сервере (§14.3)
    function timerExpired(ev, id) {
      const due = dueOf(ev, id);
      if (!due || due > now()) return false;
      ev.firedTimers = ev.firedTimers || {};
      return ev.firedTimers[id] !== due;
    }
    function markFired(ev, id) {
      ev.firedTimers = ev.firedTimers || {};
      ev.firedTimers[id] = dueOf(ev, id);
    }

    /* ===== Лимиты (§10.2): привязанные инциденты объединённого в лимит не входят — у них нет владельца ===== */

    function units(stateId, ev) {
      const own = ev ? ev.id : null;
      return new Set(
        ctx
          .events()
          .filter((e) => e.state === stateId && isMine(e))
          .map((e) => e.id)
          .filter((u) => u !== own)
      );
    }

    /* ===== Условия: реестр машины (§14.8) ===== */

    const GUARDS = {
      hasPermission: (ev, [key]) => (ctx.can(key) ? null : ["workflow.guard.no_permission", { p: key }]),
      // Область права — по scopeRule условия: own, если выполнено хоть одно из anyOf (§5)
      hasScopedPermission: (ev, [prefix], opts, guard) => {
        const rule = (guard && guard.scopeRule && guard.scopeRule.own) || { anyOf: [] };
        const own = rule.anyOf.some((c) => (c.state ? ev.state === c.state : c.ownership ? matchesOwnership(ev, c.ownership) : false));
        const key = `${prefix}:${own ? "own" : "any"}`;
        return ctx.can(key) ? null : ["workflow.guard.no_permission", { p: key }];
      },
      isOwner: (ev) => (isMine(ev) ? null : ["workflow.guard.not_owner"]),
      // «Не мой» и «не мне адресован» — по отношению смотрящего (§2.4): инцидент, ожидающий моего
      // принятия, — адресованный мне, даже если владельцем записан я сам (BUG-60)
      isNotOwner: (ev) => (ownership(ev) === "owner" ? ["workflow.guard.already_owner"] : null),
      isTarget: (ev) => (isTarget(ev) ? null : ["workflow.guard.not_target"]),
      isNotTarget: (ev) => (ownership(ev) === "target" ? ["workflow.guard.is_target"] : null),
      // Адресат передачи из формы — не сам оператор (§10.1). До заполнения формы условие выполнено
      targetIsNotSelf: (ev, args, opts) => {
        const target = opts && opts.form ? opts.form.targetId : null;
        return isSelf(target) ? ["workflow.guard.transfer_to_self"] : null;
      },
      targetCanAccept: (ev, args, opts) => {
        const target = opts && opts.form ? opts.form.targetId : null;
        return !target || ctx.canAccept(target, ev) ? null : ["workflow.guard.target_cannot_accept"];
      },
      targetHasAccess: (ev, args, opts) => {
        const target = opts && opts.form ? opts.form.targetId : null;
        return !target || ctx.hasAccess(target, ev) ? null : ["workflow.guard.target_no_access"];
      },
      // На перерыве и после выхода — только просмотр (§10.4, §12.1): какие состояния такие, решает машина
      agentReady: () => {
        const st = W.session.states.find((s) => s.id === ctx.agentState());
        return st && st.readOnly ? [st.readOnlyReasonKey] : null;
      },
      agentStateIs: (ev, [stateId]) => (ctx.agentState() === stateId ? null : ["workflow.guard.agent_state"]),
      addresseeHasAccess: (ev, [expected]) => {
        const who = addressee(ev);
        if (!who) return ["workflow.guard.no_addressee"];
        return Boolean(ctx.hasAccess && ctx.hasAccess(who, ev)) === expected ? null : ["workflow.guard.addressee_access"];
      },
      // У адресата открытого основного есть ли доступ к объекту привязанного (§11.4, §5, RULE-71)
      primaryAddresseeHasAccess: (ev, [expected]) => {
        const p = ev.linkedTo && byId(ev.linkedTo);
        const who = p && !isDone(p) ? addressee(p) : null;
        if (!who) return ["workflow.guard.no_addressee"];
        return Boolean(ctx.hasAccess && ctx.hasAccess(who, ev)) === expected ? null : ["workflow.guard.primary_addressee_access"];
      },
      addresseeCanAccept: (ev, [expected]) => {
        const who = addressee(ev);
        if (!who) return ["workflow.guard.no_addressee"];
        return Boolean(ctx.canAccept && ctx.canAccept(who, ev)) === expected ? null : ["workflow.guard.addressee_can_accept"];
      },
      escalationTargetAvailable: (ev, [expected]) => (Boolean(nextLevel(ev)) === expected ? null : ["workflow.guard.no_escalation_level"]),
      ownerHasDutyGroup: (ev, [expected]) => (Boolean(ev.owner && ctx.dutyGroupOf(ev.owner)) === expected ? null : ["workflow.guard.owner_duty_group"]),
      // Сколько секунд сессия оператора не присылает признак активности (§12.3) — знает сервер (ctx.idleSec)
      agentIdleFor: (ev, [path]) => (ctx.idleSec && ctx.idleSec() - (ctx.now() - now()) / 1000 >= setting(path) ? null : ["workflow.guard.agent_online"]),
      // Лимит null — без ограничения (§10.2, RULE-69)
      withinActiveLimit: (ev) => {
        if (W.limits.maxActive == null) return null;
        const u = units("in_progress", ev);
        if (u.size < W.limits.maxActive) return null;
        // В подсказке — номер инцидента, который держит лимит
        const busy = ctx.events().find((e) => e.state === "in_progress" && isMine(e) && u.has(e.id));
        return ["workflow.guard.active_limit", { n: W.limits.maxActive, id: busy ? busy.number || busy.id : "" }];
      },
      withinHoldLimit: (ev) =>
        W.limits.maxOnHold == null || units("on_hold", ev).size < W.limits.maxOnHold ? null : ["workflow.guard.hold_limit", { n: W.limits.maxOnHold }],
      // Точно, без округления до минуты (BUG-31): «не больше reopenWindowMin минут»
      withinReopenWindow: (ev) =>
        now() - (ev.closedAt || 0) <= W.limits.reopenWindowMin * 60000
          ? null
          : ["workflow.guard.reopen_window", { n: W.limits.reopenWindowMin }],
      requiredStepsFilled: (ev, [setId]) => (ctx.stepsFilled(ev, setId) ? null : ["workflow.guard.required_steps"]),
      closeResultAllowed: (ev, [resultId], opts) => {
        const options = closeResults(ev, opts && opts.surface);
        if (resultId) {
          const o = options.find((x) => x.id === resultId);
          if (!o) return ["workflow.guard.result_unavailable"];
          return o.disabled ? [o.why] : null;
        }
        if (options.some((o) => !o.disabled)) return null;
        return options.length ? [options[0].why] : ["workflow.guard.no_permission", { p: "incident:close" }];
      },
      timerExpired: (ev, [id]) => (timerExpired(ev, id) ? null : ["workflow.guard.timer_not_expired"]),
      holdReasonIn: (ev, [list]) => (asList(list).includes(ev.holdReason) ? null : ["workflow.guard.other_hold_reason"]),
      stateIs: (ev, [list]) => (asList(list).includes(ev.state) ? null : ["workflow.guard.wrong_state"]),
      settingEnabled: (ev, [key]) => (setting(key) ? null : ["workflow.guard.setting_off"]),
      settingIs: (ev, [key, expected]) => (setting(key) === expected ? null : ["workflow.guard.setting_other"]),
      isOwnerOrUnowned: (ev) => (isMine(ev) || unowned(ev) ? null : ["workflow.guard.not_owner"]),
      // Основной из формы — другой, открытый, не привязанный; новый или мой в работе. До формы выполнено
      mergePrimaryValid: (ev, args, opts) => {
        const id = opts && opts.form ? opts.form.primaryId : null;
        const p = byId(id);
        const ok = p && p !== ev && !p.linkedTo && (p.state === "new" || (p.state === "in_progress" && isMine(p)));
        return ok ? null : ["workflow.guard.merge_primary"];
      },
      sameScenarioAsPrimary: (ev, args, opts) => {
        const p = byId(opts && opts.form ? opts.form.primaryId : null);
        return p && ctx.scenarioKey(p) === ctx.scenarioKey(ev) ? null : ["workflow.guard.merge_scenario"];
      },
      // Основной «мой» (§2.4) — в работе или отложен у меня; ожидающий моего принятия — ещё не мой:
      // до «Принять» его никто не ведёт, отсоединять нельзя ни человеку, ни группе (RULE-78)
      primaryEditable: (ev) => {
        const p = byId(ev.linkedTo);
        return p && (ownership(p) === "owner" || unowned(p)) ? null : ["workflow.guard.primary_not_editable"];
      },
      primaryClosed: (ev) => {
        const p = byId(ev.linkedTo);
        return p && isDone(p) ? null : ["workflow.guard.primary_open"];
      },
      targetHasAccessToLinked: (ev, args, opts) => {
        const target = opts && opts.form ? opts.form.targetId : null;
        if (!target) return null;
        const linked = ctx.events().filter((e) => e.linkedTo === ev.id && !isDone(e));
        return linked.every((e) => ctx.hasAccess(target, e)) ? null : ["workflow.guard.target_no_access_linked"];
      },
    };

    function setting(path) {
      if (typeof path !== "string") return path;
      return path.split(".").reduce((o, k) => (o == null ? o : o[k]), W);
    }

    // Результаты закрытия, которые этот оператор может выбрать для этого инцидента (§2.2)
    function closeResults(ev, surface) {
      const out = [];
      catalogs.close_result.items.forEach((item) => {
        if (!ctx.can(item.permission)) return;
        if (!item.fromStates.includes(ev.state)) return;
        if (item.ownerOnlyInStates.includes(ev.state) && !isMine(ev)) return;
        if (surface && item.surfaces && !item.surfaces.includes(surface)) return;
        const stepsOk = item.requiredStepSet === "none" || ctx.stepsFilled(ev, item.requiredStepSet);
        out.push({ id: item.id, label: item.labelKey, disabled: !stepsOk, why: stepsOk ? null : "workflow.guard.required_steps" });
      });
      return out;
    }

    // Первое невыполненное условие: { why, hidden } по onFail реестра; null — всё выполнено
    function firstFail(ev, guards, opts) {
      for (const g of guards || []) {
        const fn = GUARDS[g.fn];
        if (!fn) return { why: ["workflow.error.guard_not_implemented", { fn: g.fn }], hidden: false, guard: g.fn };
        const args = (g.args || []).map((a) => (a === "form.resultId" ? opts && opts.form && opts.form.resultId : a));
        const why = fn(ev, args, opts, g);
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

    // Обязательность поля: required или requiredFrom "reasonCatalog:<справочник>.<признак>" —
    // признак позиции, выбранной в поле той же формы с source "reasonCatalog:<справочник>"
    function fieldRequired(f, field, values) {
      if (!field.requiredFrom) return Boolean(field.required);
      const [catalog, attr] = field.requiredFrom.replace("reasonCatalog:", "").split(".");
      const source = f.fields.find((x) => x.source === `reasonCatalog:${catalog}`);
      const item = source ? catalogItem(catalog, values[source.name]) : null;
      return Boolean(item && item[attr]);
    }

    // Ключ подписи результата; если у результата есть справочник причин и причина выбрана — подписи причины
    function closeResultLabel(ev) {
      const item = catalogItem("close_result", ev.closeResult);
      if (!item) return "";
      const cause = item.causeCatalog && ev.massCause ? catalogItem(item.causeCatalog, ev.massCause) : null;
      return cause ? cause.labelKey : item.labelKey;
    }

    function value(arg, ev, form, scope) {
      // Модификаторы адресата: .ifGroup — только группа, .ifPerson — только человек, иначе null
      const mod = typeof arg === "string" && arg.match(/^(.+)\.(ifGroup|ifPerson)$/);
      if (mod) {
        const v = value(mod[1], ev, form, scope);
        return v && isGroup(v) === (mod[2] === "ifGroup") ? v : null;
      }
      if (arg === "actor") return scope.actor;
      if (arg === "now") return now();
      if (typeof arg === "string" && arg.startsWith("form.")) {
        const v = form ? form[arg.slice(5)] : undefined;
        return v == null || v === "" ? null : v;
      }
      if (arg === "escalation.level.target") return scope.level ? refToId(scope.level.targetRef) : null;
      if (arg === "escalation.level.number") return scope.level ? scope.level.level : null;
      if (arg === "owner.dutyGroup") return ev.owner ? ctx.dutyGroupOf(ev.owner) : null;
      return arg;
    }

    const FLAG_FIELD = { closed_by: "closedBy", closed_at: "closedAt", close_result: "closeResult", close_cause: "massCause", result: "closeComment", sla_breached: "slaBreached", escalation_level: "escalationLevel", transfer_count: "transferCount" };

    const EFFECTS = {
      setOwner: (ev, [arg], s) => {
        ev.owner = value(arg, ev, s.form, s);
      },
      setAssignmentGroup: (ev, [arg], s) => {
        ev.assignmentGroup = value(arg, ev, s.form, s);
      },
      setHoldReason: (ev, [arg], s) => {
        ev.holdReason = value(arg, ev, s.form, s);
      },
      clearHoldReason: (ev) => {
        ev.holdReason = null;
      },
      // ifStopped — только если таймер не идёт: идущий продолжается (RULE-76, «Передать» не обнуляет реакцию)
      startTimer: (ev, [id, arg, mode]) => {
        if (mode === "ifStopped" && dueOf(ev, id)) return;
        startTimer(ev, id, arg);
      },
      stopTimer: (ev, [id]) => stopTimer(ev, id),
      pauseTimer: (ev, [id]) => pauseTimer(ev, id),
      // ifStarted — только если таймер уже запускался (идёт или на паузе с остатком): ещё не шедший не запускается
      resumeTimer: (ev, [id, mode]) => {
        if (mode === "ifStarted" && !dueOf(ev, id) && ev[FIELDS[id].left] == null) return;
        resumeTimer(ev, id);
      },
      // Запуск заново, без остатка: длительность из настройки, иначе обычный норматив (RULE-11)
      restartTimer: (ev, [id, settingPath]) => {
        const f = FIELDS[id];
        const configured = settingPath ? setting(settingPath) : null;
        const sec = configured != null ? configured : baseNorm(ev, id);
        ev[f.due] = now() + sec * 1000;
        if (f.left) ev[f.left] = null;
      },
      // Нарушение — запись «какое, когда, чьё»; отметка sla_breached — есть хоть одно (RULE-12)
      // Нарушение по таймеру датируется дедлайном, а не моментом выполнения после окна (RULE-63)
      // primaryOwner — нарушение на владельца основного: у привязанного своего нет (§11.4)
      recordBreach: (ev, [kind, who], s) => {
        ev.breaches = ev.breaches || [];
        ev.breaches.push({ kind, at: s.deadline != null ? s.deadline : now(), owner: who === "primaryOwner" ? breachOwnerOfLinked(ev) : addressee(ev) });
        ev.slaBreached = true;
      },
      increment: (ev, [field]) => {
        const key = FLAG_FIELD[field] || field;
        ev[key] = (ev[key] || 0) + 1;
      },
      setFlag: (ev, [field, arg], s) => {
        ev[FLAG_FIELD[field] || field] = value(arg, ev, s.form, s);
      },
      appendLog: (ev, [template], s) => ctx.log(ev, s.actor, template, vars(ev, s.form, s.logVars), now()),
      returnToQueue: () => {},
      evictOpenCard: (ev, [who], s) => ctx.onEvict(ev, who === "owner" ? ev.owner : s.previousOwner, s.transitionId),
      setCursor: (ev) => ctx.setCursor(ev),
      setLinkedTo: (ev, [arg], s) => {
        ev.linkedTo = value(arg, ev, s.form, s);
      },
      // Связь с основным снимается. С шаблонами — если связь была, запись в журнал события и основного:
      // переоткрытое событие, закрытое вместе с основным, работает само по себе (BUG-42)
      clearLink: (ev, [own, primary], s) => {
        const p = ev.linkedTo && byId(ev.linkedTo);
        ev.linkedTo = null;
        if (!p) return;
        const at = now();
        if (own) ctx.log(ev, s.actor, own, { primaryNumber: p.number }, at);
        if (primary) s.after.push(() => ctx.log(p, s.actor, primary, { number: ev.number }, at));
      },
      // Заполненные шаги привязанного — в незаполненные шаги основного (сценарий у них один); у привязанного
      // ответы остаются как история. Что переносится, решает машина сценариев (ctx.shareAnswers, §14.5).
      // Что перенесено — запись в журнале основного
      copyAnswersToPrimary: (ev, [template], s) => {
        const p = byId(s.form && s.form.primaryId);
        if (!p) return;
        const at = now();
        s.after.push(() => {
          const n = ctx.shareAnswers(ev, p, at);
          if (n && template) ctx.log(p, s.actor, template, { number: ev.number, n }, at);
        });
      },
      // Открытые привязанные объединяемого — новому основному: привязанного у привязанного не бывает.
      // Закрытые вместе с прежним основным остаются при нём как история
      relinkToPrimary: (ev, [template], s) => {
        const p = byId(s.form && s.form.primaryId);
        if (!p) return;
        const children = ctx.events().filter((e) => e.linkedTo === ev.id && !isDone(e));
        const at = now();
        s.after.push(() =>
          children.forEach((e) => {
            e.linkedTo = p.id;
            if (template) ctx.log(e, s.actor, template, { primaryNumber: p.number }, at);
          })
        );
      },
      copyCloseFromPrimary: (ev) => {
        const p = byId(ev.linkedTo);
        if (!p) return;
        Object.assign(ev, { closeResult: p.closeResult, massCause: p.massCause, closeComment: p.closeComment, closedBy: p.closedBy });
      },
      // Алерт (§9, RULE-43) — внешний эффект: уходит после того, как переход применён. Кому — решает
      // сервер (на месте и с доступом к объекту); никому — запись в журнал из машины
      notify: (ev, [who], s) => {
        if (who !== "alerts.target") return;
        s.after.push((inc) => {
          const sent = ctx.notifyAlert ? ctx.notifyAlert(inc, refToId(setting("alerts.target")), s.transitionId) : 0;
          if (!sent) ctx.log(inc, s.actor, W.alerts.noRecipientLog, {}, now());
        });
      },
      externalCommand: () => {},
    };

    // Переход атомарен (§14.1, §14.2): эффекты выполняются на черновике инцидента, и только если
    // все прошли без ошибки, черновик становится инцидентом. Неизвестный эффект — ошибка, а не пропуск
    function draftOf(ev) {
      return Object.assign({}, ev, { log: ev.log.slice(), breaches: (ev.breaches || []).slice() });
    }
    function effectsOn(draft, tr, form, actor, extra) {
      const scope = {
        actor,
        deadline: extra && extra.deadline != null ? extra.deadline : null,
        form,
        transitionId: tr.id,
        after: [],
        previousOwner: draft.owner,
        // Состояние до перехода: черновик получает новое раньше эффектов
        level: nextLevel(draft),
        logVars: { previousOwnerName: ctx.actorName(addressee(draft)) },
      };
      if (tr.to) draft.state = tr.to;
      tr.effects.forEach((e) => {
        const fn = EFFECTS[e.fn];
        if (!fn) throw Object.assign(new Error(e.fn), { why: ["workflow.error.effect_not_implemented", { fn: e.fn }] });
        fn(draft, e.args || [], scope);
      });
      // Внешние эффекты для ответа перехода (§14.2, TransitionResult.externalEffects): кому или какая
      // команда. Нет получателя или это сам выполняющий — уведомления нет (BUG-30)
      const recipient = { owner: draft.owner, previousOwner: scope.previousOwner, newTarget: addressee(draft) };
      const external = tr.effects
        .filter((e) => e.kind === "external")
        .map((e) => {
          const [arg] = e.args || [];
          const target = e.fn !== "notify" ? arg : arg === "alerts.target" ? refToId(setting(arg)) : recipient[arg] || null;
          return { fn: e.fn, target };
        })
        .filter((x) => x.target && x.target !== actor);
      return { after: scope.after, external };
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
      const before = list.map(snap);
      const drafts = list.map(draftOf);
      let done;
      try {
        done = drafts.map((d) => effectsOn(d, tr, form, actor, extra));
      } catch (err) {
        return { ok: false, why: ["workflow.error.transition_failed", { error: err.why || err.message }] };
      }
      list.forEach((ev, i) => Object.assign(ev, drafts[i]));
      // Внешние эффекты — только после применения перехода
      list.forEach((ev, i) => done[i].after.forEach((fn) => fn(ev)));
      return { ok: true, external: done.map((d) => d.external), facts: list.map((ev, i) => factsOf(before[i], ev)) };
    }

    // Проверка формы (§14.8: form.*): обязательные поля и комментарий по строке справочника
    function validateForm(tr, ev, form) {
      const f = tr.form ? forms[tr.form] : null;
      if (!f) return null;
      for (const field of f.fields) {
        if (field.visibleWhen && !field.visibleWhen.in.includes(form[field.visibleWhen.field])) continue;
        const required = fieldRequired(f, field, form);
        const v = form[field.name];
        if (required && (v == null || String(v).trim() === "")) {
          return field.kind === "text" ? ["workflow.error.reason_required"] : ["workflow.error.field_required", { name: [field.labelKey] }];
        }
      }
      return null;
    }

    function run(id, ev, form, opts) {
      const tr = transitions[id];
      if (!tr) return { ok: false, why: ["workflow.error.unknown_action"] };
      form = form || {};
      const a = availability(id, ev, { form, surface: opts && opts.surface });
      if (!a.ok) return { ok: false, why: a.why };
      const bad = validateForm(tr, ev, form);
      if (bad) return { ok: false, why: bad };
      const canceled = windowBefore(ev, id);
      const applied = applyEffects(tr, ev, form, ME);
      if (!applied.ok) return applied;
      const facts = applied.facts[0];
      windowAfter(ev, canceled, facts);
      return { ok: true, navigate: tr.ui.navigate, external: applied.external[0], facts, canceled: canceled ? canceled.tr.id : null };
    }

    // Ручное действие в окне после дедлайна выигрывает у таймера (§10.1, правило 5; RULE-63) — у одиночного
    // перехода и у объединения (BUG-62). До эффектов: отменённое срабатывание отмечено, чьё нарушение — запомнено
    function windowBefore(ev, id) {
      const canceled = overridden(ev, id);
      if (!canceled) return null;
      canceled.owner = ev.linkedTo ? breachOwnerOfLinked(ev) : addressee(ev);
      canceled.logAt = ev.log.length;
      ev.firedTimers = Object.assign({}, ev.firedTimers, { [canceled.timer]: canceled.due });
      return canceled;
    }
    // После эффектов: нарушение — то, что записал бы отменённый переход, на момент дедлайна; запись в журнал —
    // перед записью о самом действии
    function windowAfter(ev, canceled, facts) {
      if (!canceled) return;
      canceled.tr.effects.filter((x) => x.fn === "recordBreach").forEach((x) => {
        ev.breaches = (ev.breaches || []).concat({ kind: x.args[0], at: canceled.due, owner: canceled.owner });
        ev.slaBreached = true;
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
    function momentOf(ev, tr, after) {
      let moment = null;
      for (const g of tr.guards || []) {
        if (g.fn === "timerExpired") {
          const due = dueOf(ev, g.args[0]);
          if (!due) return null;
          moment = Math.max(moment || 0, due);
        } else if (g.fn === "agentIdleFor") {
          if (!ctx.idleSec) return null;
          moment = Math.max(moment || 0, ctx.now() - ctx.idleSec() * 1000 + setting(g.args[0]) * 1000);
        }
      }
      if (moment == null) return after != null ? after : ctx.now();
      return after != null ? Math.max(moment, after) : moment;
    }
    function tick(opts) {
      const changed = [];
      const agentOnly = Boolean(opts && opts.agentOnly);
      ctx.events().forEach((ev) => {
        // Один и тот же переход в один и тот же момент — не больше раза за такт: ошибка в условии
        // не зациклит планировщик
        const done = new Set();
        let last = null;
        for (let step = 0; step < 50 && !isDone(ev); step++) {
          const ready = [];
          W.transitions.forEach((tr) => {
            if (tr.trigger !== "timer" && tr.trigger !== "system") return;
            if (agentOnly && tr.trigger === "system" && tr.scope !== "incidents_owned_by_agent") return;
            if (!tr.from.includes(ev.state)) return;
            if (tr.scope === "incidents_owned_by_agent" && !isMine(ev)) return;
            const moment = momentOf(ev, tr, last);
            if (moment == null || moment > ctx.now() || done.has(`${tr.id}@${moment}`)) return;
            at = moment;
            const fail = firstFail(ev, tr.guards);
            at = null;
            if (!fail) ready.push({ tr, moment });
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
          if (!next) return;
          done.add(`${next.tr.id}@${next.moment}`);
          // Выполняется по таймеру — после окна, но не позже готового системного: тогда и при прыжке
          // часов оба — в момент системного, как при шагах (BUG-38)
          const sysAt = Math.min(ctx.now(), ...ready.filter((c) => c.tr.trigger === "system").map((c) => c.moment));
          const runAt = next.tr.trigger === "timer" ? Math.min(Math.max(next.moment + GRACE_MS, last || 0), sysAt) : next.moment;
          at = runAt;
          let facts = null;
          try {
            const timerGuard = (next.tr.guards || []).find((g) => g.fn === "timerExpired");
            const deadline = timerGuard ? dueOf(ev, timerGuard.args[0]) : null;
            if (timerGuard) markFired(ev, timerGuard.args[0]);
            const applied = applyEffects(next.tr, ev, {}, next.tr.actor || "dispatcher", { deadline });
            if (!applied.ok) return;
            facts = applied.facts[0];
          } finally {
            at = null;
          }
          last = runAt;
          changed.push({ id: ev.id, transition: next.tr.id, facts });
        }
      });
      return changed;
    }

    // Можно ли править шаги сценария (§10.4, scenarioEdit машины); нет — карточка на просмотр
    const canEditScenario = (ev) => Boolean(ev) && !firstFail(ev, W.scenarioEdit.guards);

    /* ===== Формы, бейджи, массовые действия ===== */

    function noteFor(f, ev, extra) {
      const role = ownership(ev);
      const note = (f.notes || []).find((n) => {
        const w = n.when || {};
        if (w.state && w.state !== ev.state) return false;
        if (w.ownership && w.ownership !== role) return false;
        return true;
      });
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

    function form(formId, ev, opts) {
      const f = forms[formId];
      if (!f) return null;
      const fields = f.fields.map((field) => {
        let options = null;
        let defaultValue = null;
        if (field.source === "transferTargets") {
          const excludes = field.excludes || [];
          options = ctx
            .transferTargets(ev)
            .filter(
              (o) =>
                !(excludes.includes("self") && isSelf(o.id)) &&
                !(excludes.includes("currentOwner") && o.id === addressee(ev)) &&
                !(excludes.includes("noAccess") && !ctx.hasAccess(o.id, ev)) &&
                !(excludes.includes("cannotAccept") && !ctx.canAccept(o.id, ev))
            );
          if (field.defaultFrom && options.some((o) => o.id === ctx.defaultTransferTarget())) defaultValue = ctx.defaultTransferTarget();
        } else if (field.source && field.source.startsWith("reasonCatalog:")) {
          const catalog = field.source.split(":")[1];
          if (field.optionsFrom === "actions" && catalog === "close_result") {
            options = closeResults(ev, opts && opts.surface).map((o) => ({ id: o.id, label: o.label, disabled: o.disabled, why: o.why }));
          } else {
            options = catalogs[catalog].items
              .filter((i) => !(field.excludeSystemItems && i.setBy === "system"))
              .map((i) => ({ id: i.id, label: i.labelKey }));
          }
          if (field.defaultWhen && ctx.stepsFilled(ev, field.defaultWhen.requiredStepsFilled)) defaultValue = field.defaultWhen.value;
        }
        return Object.assign({}, field, { options, defaultValue });
      });
      return { id: f.id, title: f.titleKey, confirmLabel: f.confirmKey, style: f.style, note: noteFor(f, ev, opts && opts.noteVars), fields };
    }

    // Бейдж под смотрящего оператора (§2.4)
    function badge(ev) {
      const role = ownership(ev);
      const rule = W.badges.rules.find((r) => {
        if (r.state !== ev.state) return false;
        if (r.when && r.when.closeResult && r.when.closeResult !== ev.closeResult) return false;
        // Адресат — группа или человек: передачу группе может принять любой из неё (§2.4)
        if (r.when && r.when.addressee && r.when.addressee !== (isGroup(addressee(ev)) ? "group" : "person")) return false;
        return r.viewerRole === "any" || r.viewerRole === role;
      });
      if (!rule) return { label: [states[ev.state].labelKey], style: ev.state };
      const hold = catalogItem("hold", ev.holdReason);
      return {
        label: [rule.labelKey, { ownerName: ctx.actorName(addressee(ev)), holdReasonLabel: hold ? [hold.labelKey] : "", closeResultLabel: closeResultLabel(ev) ? [closeResultLabel(ev)] : "" }],
        style: rule.style,
      };
    }

    const bulk = (id) => (transitions[id] && transitions[id].bulk) || { allowed: false };

    // Фильтр очереди по описанию из машины (queueFilters): состояния, категории, отношение ко мне
    function inQueueFilter(ev, filterId) {
      const f = W.queueFilters.find((q) => q.id === filterId);
      if (!f) return true;
      if (f.states && !f.states.includes(ev.state)) return false;
      if (f.stateCategories && !f.stateCategories.includes(states[ev.state].category)) return false;
      if (f.ownership && f.ownership !== ownership(ev)) return false;
      return true;
    }

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
    function merge(primary, others) {
      const check = mergeCheck(primary, others);
      if (!check.ok) return check;
      // Окно после дедлайна — как у одиночного перехода: у каждого привязанного и у основного, если его берут (BUG-62)
      const canceled = others.map((ev) => windowBefore(ev, check.tr.id));
      const primaryCanceled = check.take ? windowBefore(primary, check.take.id) : null;
      const applied = applyAll(check.tr, others, check.form, ME);
      if (!applied.ok) return applied;
      others.forEach((ev, i) => windowAfter(ev, canceled[i], applied.facts[i]));
      applied.transitionId = check.tr.id;
      if (check.take) {
        const r = applyEffects(check.take, primary, {}, ME);
        if (!r.ok) return r;
        windowAfter(primary, primaryCanceled, r.facts[0]);
        applied.taken = { transitionId: check.take.id, facts: r.facts[0] };
      }
      return applied;
    }

    return {
      workflow: W,
      implemented: { guards: Object.keys(GUARDS), effects: Object.keys(EFFECTS) },
      transition: (id) => transitions[id] || null,
      nav: (id) => navActions[id] || null,
      isNav: (id) => Boolean(navActions[id]),
      isDone,
      isTarget,
      isSelf,
      fieldRequired,
      addressee,
      ownership,
      inQueueFilter,
      availability,
      actions,
      session: W.session,
      run,
      create,
      form,
      badge,
      bulk,
      closeResults,
      norm: baseNorm,
      startTimer,
      stopTimer,
      pauseTimer,
      resumeTimer,
      tick,
      canEditScenario,
      closeResultLabel,
      merge,
      mergeCheck,
      units,
    };
  }

  window.IMEngine = { create };
})();
