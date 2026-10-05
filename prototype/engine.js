/* Исполнитель машины состояний в браузере: Specification/State_machine/workflow.v4.json,
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

    const now = () => ctx.now();
    const isGroup = (id) => Boolean(id) && ctx.isGroup(id);
    const isMine = (ev) => ev.owner === ME;
    // «Я» как адресат: сам оператор и группы, в которые он входит (§10.1)
    const isSelf = (id) => Boolean(id) && (id === ME || (isGroup(id) && ctx.memberOf(id, ME)));
    // Адресат: владелец-человек, а пока группа не приняла — сама группа (assignment_group, §8.1)
    const addressee = (ev) => ev.owner || ev.assignmentGroup || null;
    const isTarget = (ev) => isSelf(addressee(ev));
    const isDone = (ev) => states[ev.state] && states[ev.state].category === "done";
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
    function levelNorm(ev, level) {
      const levels = W.escalation.levels;
      const found = levels.find((l) => l.level === level) || levels[levels.length - 1];
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

    /* ===== Лимиты (§10.2): группа сценария — одна единица ===== */

    function units(stateId, ev) {
      const own = ev ? ev.groupId || ev.id : null;
      return new Set(
        ctx
          .events()
          .filter((e) => e.state === stateId && isMine(e))
          .map((e) => e.groupId || e.id)
          .filter((u) => u !== own)
      );
    }

    /* ===== Условия: реестр машины (§14.8) ===== */

    const GUARDS = {
      hasPermission: (ev, [key]) => (ctx.can(key) ? null : ["Нет права: {p}", { p: key }]),
      // Область права — по scopeRule условия: own, если выполнено хоть одно из anyOf (§5)
      hasScopedPermission: (ev, [prefix], opts, guard) => {
        const rule = (guard && guard.scopeRule && guard.scopeRule.own) || { anyOf: [] };
        const own = rule.anyOf.some((c) => (c.state ? ev.state === c.state : c.ownership ? matchesOwnership(ev, c.ownership) : false));
        const key = `${prefix}:${own ? "own" : "any"}`;
        return ctx.can(key) ? null : ["Нет права: {p}", { p: key }];
      },
      isOwner: (ev) => (isMine(ev) ? null : ["Вы не владелец инцидента"]),
      isNotOwner: (ev) => (isMine(ev) ? ["Инцидент уже ваш"] : null),
      isOwnerInStates: (ev, [list]) => (!asList(list).includes(ev.state) || isMine(ev) ? null : ["Вы не владелец инцидента"]),
      isTarget: (ev) => (isTarget(ev) ? null : ["Передача адресована другому"]),
      isNotTarget: (ev) => (isTarget(ev) && !isMine(ev) ? ["Передача адресована вам"] : null),
      // Адресат передачи из формы — не сам оператор (§10.1). До заполнения формы условие выполнено
      targetIsNotSelf: (ev, args, opts) => {
        const target = opts && opts.form ? opts.form.targetId : null;
        return isSelf(target) ? ["Передача на себя запрещена"] : null;
      },
      agentReady: () => (ctx.agentState() === "not_ready" ? ["На перерыве доступен только просмотр"] : null),
      agentStateIs: (ev, [stateId]) => (ctx.agentState() === stateId ? null : ["Неподходящее состояние оператора"]),
      // Сколько секунд сессия оператора не присылает признак активности (§12.3) — знает сервер (ctx.idleSec)
      agentIdleFor: (ev, [path]) => (ctx.idleSec && ctx.idleSec() >= setting(path) ? null : ["Оператор на связи"]),
      // extra — сколько единиц добавит действие сверх единицы самого инцидента (§10.2)
      withinActiveLimit: (ev, [extra = 0]) => {
        const u = units("in_progress", ev);
        if (u.size + extra < W.limits.maxActive) return null;
        if (extra) return ["Лимит активных ({n}): после исключения в работе станет больше", { n: W.limits.maxActive }];
        return ["Лимит активных ({n}). Сначала закройте или отложите {id}", { n: W.limits.maxActive, id: [...u][0] }];
      },
      withinHoldLimit: (ev) =>
        units("on_hold", ev).size < W.limits.maxOnHold ? null : ["Больше {n} отложенных держать нельзя", { n: W.limits.maxOnHold }],
      withinReopenWindow: (ev) =>
        Math.round((now() - (ev.closedAt || 0)) / 60000) <= W.limits.reopenWindowMin
          ? null
          : ["Срок переоткрытия истёк: {n} мин", { n: W.limits.reopenWindowMin }],
      requiredStepsFilled: (ev, [setId]) => (ctx.stepsFilled(ev, setId) ? null : ["Заполните обязательные шаги закрытия"]),
      closeResultAllowed: (ev, [resultId], opts) => {
        const options = closeResults(ev, opts && opts.surface);
        if (resultId) {
          const o = options.find((x) => x.id === resultId);
          if (!o) return ["Результат недоступен"];
          return o.disabled ? [o.why] : null;
        }
        if (options.some((o) => !o.disabled)) return null;
        return options.length ? [options[0].why] : ["Нет права: {p}", { p: "incident:close" }];
      },
      timerExpired: (ev, [id]) => (timerExpired(ev, id) ? null : ["Норматив не истёк"]),
      flagBelow: (ev, [field, n]) => (flagValue(ev, field) < setting(n) ? null : ["Достигнут предел"]),
      flagAtLeast: (ev, [field, n]) => (flagValue(ev, field) >= setting(n) ? null : ["Предел не достигнут"]),
      holdReasonIn: (ev, [list]) => (asList(list).includes(ev.holdReason) ? null : ["Другая причина удержания"]),
      stateIs: (ev, [list]) => (asList(list).includes(ev.state) ? null : ["Недоступно в текущем состоянии"]),
      canReadDone: (ev) => (isMine(ev) || ev.closedBy === ME || ctx.can("incident:read:any") ? null : ["Нет права открывать чужие карточки"]),
      // Сколько инцидентов отмечено для массового действия; без выборки условие выполнено
      minSelected: (ev, [n], opts) =>
        opts && opts.selectedCount != null && opts.selectedCount < n ? ["Выберите хотя бы {n} события", { n }] : null,
      settingEnabled: (ev, [key]) => (setting(key) ? null : ["Выключено настройкой"]),
    };

    const flagValue = (ev, field) => (field === "escalation_level" ? ev.escalationLevel : ev[field]);
    function setting(path) {
      if (typeof path !== "string") return path;
      if (path === "escalation.onResolutionOverdue.alert") return W.escalation.onResolutionOverdue === "alert";
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
        out.push({ id: item.id, label: item.label, disabled: !stepsOk, why: stepsOk ? null : "Заполните обязательные шаги закрытия" });
      });
      return out;
    }

    // Первое невыполненное условие: { why, hidden } по onFail реестра; null — всё выполнено
    function firstFail(ev, guards, opts) {
      for (const g of guards || []) {
        const fn = GUARDS[g.fn];
        if (!fn) return { why: [`Условие не реализовано: ${g.fn}`], hidden: false, guard: g.fn };
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
      if (tr && !tr.from.includes(ev.state)) return { hidden: true, notFrom: true, why: ["Недоступно в текущем состоянии"] };
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
          label: tr.label,
          hint: a.why || tr.hint || tr.label,
          style: tr.ui.style || "outline",
          enabled: Boolean(a.ok),
          formId: tr.form,
          hotkey: tr.ui.hotkey,
          navigate: tr.ui.navigate,
        });
      });
      W.navActions.items.forEach((nav) => {
        if (!nav.surface.includes(surface)) return;
        const a = availability(nav.id, ev);
        if (a.hidden || !a.ok) return;
        out.push({ id: nav.id, kind: "nav", label: nav.label, hint: nav.hint || nav.label, style: nav.style, enabled: true });
      });
      // Навигация — первой: «Продолжить», «Открыть», «Просмотр» стоят во главе колонки
      return out.filter((a) => a.kind === "nav").concat(out.filter((a) => a.kind === "transition"));
    }

    /* ===== Выполнение перехода (/transitions, §6) ===== */

    function vars(ev, form, extra) {
      const prog = ctx.progress(ev);
      const hold = catalogItem("hold", ev.holdReason);
      return Object.assign(
        {
          comment: (form && form.comment) || "",
          stepNumber: ctx.stepNumber(ev),
          holdReasonLabel: hold ? hold.label : "",
          targetName: ctx.actorName(addressee(ev)),
          escalationLevel: ev.escalationLevel,
          closeResultLabel: closeResultLabel(ev),
          filledSteps: prog.filled,
          totalSteps: prog.total,
          escalationReason: W.escalation.reason,
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

    // Подпись результата; если у результата есть справочник причин и причина выбрана — подпись причины
    function closeResultLabel(ev) {
      const item = catalogItem("close_result", ev.closeResult);
      if (!item) return "";
      const cause = item.causeCatalog && ev.massCause ? catalogItem(item.causeCatalog, ev.massCause) : null;
      return cause ? cause.label : item.label;
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
      return arg;
    }

    const FLAG_FIELD = { closed_by: "closedBy", closed_at: "closedAt", close_result: "closeResult", close_cause: "massCause", result: "closeComment", sla_breached: "slaBreached" };

    const EFFECTS = {
      setState: (ev, [stateId]) => {
        ev.state = stateId;
      },
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
      startTimer: (ev, [id, arg]) => startTimer(ev, id, arg),
      stopTimer: (ev, [id]) => stopTimer(ev, id),
      pauseTimer: (ev, [id]) => pauseTimer(ev, id),
      resumeTimer: (ev, [id]) => resumeTimer(ev, id),
      // Запуск заново, без остатка: длительность из настройки, иначе обычный норматив (RULE-11)
      restartTimer: (ev, [id, settingPath]) => {
        const f = FIELDS[id];
        const configured = settingPath ? setting(settingPath) : null;
        const sec = configured != null ? configured : baseNorm(ev, id);
        ev[f.due] = now() + sec * 1000;
        if (f.left) ev[f.left] = null;
      },
      // Нарушение — запись «какое, когда, чьё»; отметка sla_breached — есть хоть одно (RULE-12)
      recordBreach: (ev, [kind]) => {
        ev.breaches = ev.breaches || [];
        ev.breaches.push({ kind, at: now(), owner: addressee(ev) });
        ev.slaBreached = true;
      },
      increment: (ev, [field]) => {
        if (field === "escalation_level") ev.escalationLevel += 1;
        else ev[field] = (ev[field] || 0) + 1;
      },
      setFlag: (ev, [field, arg], s) => {
        ev[FLAG_FIELD[field] || field] = value(arg, ev, s.form, s);
      },
      appendLog: (ev, [template], s) => ctx.log(ev, s.actor, template, vars(ev, s.form, s.logVars)),
      returnToQueue: () => {},
      evictOpenCard: (ev, [who], s) => ctx.onEvict(ev, who === "owner" ? ev.owner : s.previousOwner, s.transitionId),
      setCursor: (ev) => ctx.setCursor(ev),
      clearGroup: (ev) => {
        ev.groupId = null;
      },
      notify: () => {},
      externalCommand: () => {},
    };

    // Переход атомарен (§14.1, §14.2): эффекты выполняются на черновике инцидента, и только если
    // все прошли без ошибки, черновик становится инцидентом. Неизвестный эффект — ошибка, а не пропуск
    function draftOf(ev) {
      return Object.assign({}, ev, { log: ev.log.slice(), breaches: (ev.breaches || []).slice() });
    }
    function effectsOn(draft, tr, form, actor) {
      const scope = {
        actor,
        form,
        transitionId: tr.id,
        previousOwner: draft.owner,
        level: W.escalation.levels.find((l) => l.level === draft.escalationLevel + 1) || null,
        logVars: { previousOwnerName: ctx.actorName(addressee(draft)) },
      };
      if (tr.to) draft.state = tr.to;
      tr.effects.forEach((e) => {
        const fn = EFFECTS[e.fn];
        if (!fn) throw new Error(`Эффект не реализован: ${e.fn}`);
        fn(draft, e.args || [], scope);
      });
    }
    function applyEffects(tr, ev, form, actor) {
      return applyAll(tr, [ev], form, actor);
    }
    // Несколько инцидентов одним действием — тоже атомарно: либо все, либо ни один
    function applyAll(tr, list, form, actor) {
      const drafts = list.map(draftOf);
      try {
        drafts.forEach((d) => effectsOn(d, tr, form, actor));
      } catch (err) {
        return { ok: false, why: ["Переход не выполнен: {error}", { error: err.message }] };
      }
      list.forEach((ev, i) => Object.assign(ev, drafts[i]));
      return { ok: true };
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
          return field.kind === "text" ? ["Укажите причину — поле обязательно"] : ["Заполните поле «{name}»", { name: field.label }];
        }
      }
      return null;
    }

    function run(id, ev, form, opts) {
      const tr = transitions[id];
      if (!tr) return { ok: false, why: ["Неизвестное действие"] };
      form = form || {};
      const a = availability(id, ev, { form, surface: opts && opts.surface });
      if (!a.ok) return { ok: false, why: a.why };
      const bad = validateForm(tr, ev, form);
      if (bad) return { ok: false, why: bad };
      const applied = applyEffects(tr, ev, form, ME);
      if (!applied.ok) return applied;
      return { ok: true, navigate: tr.ui.navigate };
    }

    /* ===== Автоматические переходы (§6.2): планировщик ===== */

    // Автоматические и системные переходы машины (trigger: timer / system), чьи условия
    // выполнены. Таймер, по которому срабатывает переход, — из его условия timerExpired.
    // scope: incidents_owned_by_agent — только инциденты текущего оператора (перерыв, §12.2)
    // agentOnly — только переходы, привязанные к оператору (scope: incidents_owned_by_agent):
    // так сервер проверяет состояние каждого оператора, не запуская общие таймеры повторно
    function tick(opts) {
      const changed = [];
      const agentOnly = Boolean(opts && opts.agentOnly);
      ctx.events().forEach((ev) => {
        if (isDone(ev)) return;
        W.transitions.forEach((tr) => {
          if (tr.trigger !== "timer" && tr.trigger !== "system") return;
          if (agentOnly && tr.scope !== "incidents_owned_by_agent") return;
          if (!tr.from.includes(ev.state)) return;
          if (tr.scope === "incidents_owned_by_agent" && !isMine(ev)) return;
          if (firstFail(ev, tr.guards)) return;
          const timerGuard = (tr.guards || []).find((g) => g.fn === "timerExpired");
          if (timerGuard) markFired(ev, timerGuard.args[0]);
          if (applyEffects(tr, ev, {}, tr.actor || "dispatcher").ok) changed.push({ id: ev.id, transition: tr.id });
        });
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
        if (w.grouped && !(extra && extra.groupSize > 1)) return false;
        return true;
      });
      if (!note) return null;
      const prog = ctx.progress(ev);
      return [
        note.text,
        Object.assign(
          {
            nextEscalationLevel: ev.escalationLevel + 1,
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
            .filter((o) => !(excludes.includes("self") && isSelf(o.id)) && !(excludes.includes("currentOwner") && o.id === addressee(ev)));
          if (field.defaultFrom && options.some((o) => o.id === ctx.defaultTransferTarget())) defaultValue = ctx.defaultTransferTarget();
        } else if (field.source && field.source.startsWith("reasonCatalog:")) {
          const catalog = field.source.split(":")[1];
          if (field.optionsFrom === "actions" && catalog === "close_result") {
            options = closeResults(ev, opts && opts.surface).map((o) => ({ id: o.id, label: o.label, disabled: o.disabled, why: o.why }));
          } else {
            options = catalogs[catalog].items
              .filter((i) => !(field.excludeSystemItems && i.setBy === "system"))
              .map((i) => ({ id: i.id, label: i.label }));
          }
          if (field.defaultWhen && ctx.stepsFilled(ev, field.defaultWhen.requiredStepsFilled)) defaultValue = field.defaultWhen.value;
        }
        return Object.assign({}, field, { options, defaultValue });
      });
      return { id: f.id, title: f.title, confirmLabel: f.confirmLabel, style: f.style, note: noteFor(f, ev, opts && opts.noteVars), fields };
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
      if (!rule) return { label: [states[ev.state].label], style: ev.state };
      const hold = catalogItem("hold", ev.holdReason);
      return {
        label: [rule.label, { ownerName: ctx.actorName(addressee(ev)), holdReasonLabel: hold ? hold.label : "", closeResultLabel: closeResultLabel(ev) }],
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

    // «Обработать как одно» (§11): «Взять» с bulk.createsGroup на каждом отмеченном и общий group_id.
    // Условия и общие поля — из grouping машины. group_id ставится до проверки «Взять»: группа
    // считается в лимите активных одной единицей
    function createGroup(list, groupId) {
      const g = W.grouping;
      const claim = W.transitions.find((t) => t.bulk && t.bulk.createsGroup);
      if (!g.enabled || !claim) return { ok: false, why: ["Групповая обработка выключена"] };
      if (!g.permissions.every(ctx.can)) return { ok: false, why: ["Нет права на групповую обработку"] };
      if (list.length < g.createFrom.minItems) return { ok: false, why: ["Выберите хотя бы {n} события", { n: g.createFrom.minItems }] };
      if (list.length > g.createFrom.maxItems) return { ok: false, why: ["Не больше {max} событий в группе", { max: g.createFrom.maxItems }] };
      if (!list.every((e) => g.createFrom.states.includes(e.state))) return { ok: false, why: ["В группу берутся только новые события"] };
      if (g.createFrom.sameEventType && list.some((e) => e.typeId !== list[0].typeId)) {
        return { ok: false, why: ["В группе должен быть один тип события"] };
      }
      list.forEach((ev) => (ev.groupId = groupId));
      const blocked = list.find((ev) => !availability(claim.id, ev).ok);
      if (blocked) {
        const { why, guard } = availability(claim.id, blocked);
        list.forEach((ev) => (ev.groupId = null));
        return { ok: false, why, guard };
      }
      const applied = applyAll(claim, list, {}, ME);
      if (!applied.ok) {
        list.forEach((ev) => (ev.groupId = null));
        return applied;
      }
      if (g.shared.includes("scenarioAnswers")) list.forEach((ev) => ctx.shareAnswers(ev, list[0]));
      return { ok: true };
    }

    const canExcludeFromGroup = (ev) => Boolean(ev && ev.groupId) && !firstFail(ev, W.grouping.excludeGuards);
    // Почему исключить нельзя — для подсказки на кнопке
    const excludeBlock = (ev) => (ev && ev.groupId ? (firstFail(ev, W.grouping.excludeGuards) || {}).why || null : null);

    // Ручное исключение из группы сценария (§11, grouping.memberLeavesGroupOn: manual_exclude):
    // инцидент остаётся в работе со своей копией ответов
    function excludeFromGroup(ev) {
      if (!ev.groupId || !W.grouping.memberLeavesGroupOn.includes("manual_exclude")) return { ok: false, why: ["Инцидент не в группе"] };
      const fail = firstFail(ev, W.grouping.excludeGuards);
      if (fail) return { ok: false, why: fail.why, guard: fail.guard };
      ev.groupId = null;
      ctx.detachAnswers(ev);
      ctx.log(ev, ME, "Исключён из групповой обработки");
      return { ok: true };
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
      createGroup,
      excludeFromGroup,
      canExcludeFromGroup,
      excludeBlock,
      units,
    };
  }

  window.IMEngine = { create };
})();
