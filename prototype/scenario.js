/* Исполнитель машины сценариев в браузере: формат DSL v1 (Specification/Scenario_machine/).
   Перенос исполнителя runner-web (stateMachine.ts, transitionEvaluator.ts — хэши в ORIGIN.md) и профиль
   МИ из README машины сценариев: как МИ исполняет то, о чём спецификация молчит.

   Чистые функции над сценарием (script) и прогоном (scenarioResult, спецификация, раздел 9). Об инциденте,
   владельце и очереди не знает: что можно отвечать (scenarioEdit), решает машина инцидента, а внешние
   эффекты (запуск макросов) исполняет сервер — здесь они только возвращаются. Условия переходов вычисляет
   json-logic-js (prototype/vendor/json-logic-js), подключённый раньше этого файла. */
(() => {
  const logic = window.jsonLogic;
  const DSL_MAJOR = 1;
  // view.required по умолчанию — по схеме: у RadioButton, Select и Datetime да, у остальных нет
  const REQUIRED_BY_DEFAULT = { RadioButton: true, Select: true, Datetime: true, Checkbox: false, Comment: false, Image: false };
  const DATE = /^\d{4}-\d{2}-\d{2}$/;
  const TIME = /^\d{2}:\d{2}(:\d{2})?$/;
  const DATETIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})?$/;

  const clone = (x) => JSON.parse(JSON.stringify(x));
  const stepOf = (script, id) => script.steps.find((s) => s.id === id) || null;
  const isAnswer = (ev) => ev.action === "answer" || ev.action === "skip";
  const sameList = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

  // Кнопка — ответ нажатием: обязательности у неё нет, пропустить её нельзя
  const isRequired = (step) =>
    step.type !== "Button" && (step.view.required !== undefined ? step.view.required === true : REQUIRED_BY_DEFAULT[step.type] === true);
  const canSkip = (step) => step.type !== "Button" && !isRequired(step);

  function start(script, at) {
    const major = Number(String(script.dslVersion).split(".")[0]);
    // Спецификация, раздел 13.2 (О3): старшую версию формата выше своей исполнитель не исполняет
    if (major !== DSL_MAJOR) throw new Error(`DSL ${script.dslVersion}: исполнитель знает только ${DSL_MAJOR}.x`);
    if (!stepOf(script, script.initialStepId)) throw new Error(`нет начального шага ${script.initialStepId}`);
    return { dslVersion: script.dslVersion, state: {}, history: [], currentStepId: script.initialStepId, completedAt: null };
  }

  // Первое правило с истинным when, иначе default (спецификация, раздел 7). Ошибка вычисления — ложь
  function evaluate(transitions, state) {
    if (!transitions) return null;
    const rules = transitions.rules || [];
    for (let i = 0; i < rules.length; i++) {
      let truthy = false;
      try {
        truthy = Boolean(logic.apply(rules[i].when, { state }));
      } catch (err) {
        truthy = false;
      }
      if (truthy) return { outcome: rules[i], ruleIndex: i };
    }
    return { outcome: transitions.default, ruleIndex: "default" };
  }

  // Пригоден ли ответ для шага: null — да, иначе причина. Значения — по таблице спецификации, раздел 9
  function checkValue(step, value, attachments) {
    const v = step.view;
    const ids = (v.options || []).map((o) => o.id);
    switch (step.type) {
      case "Button":
        return null;
      case "RadioButton":
      case "Select":
        return typeof value === "string" && ids.includes(value) ? null : "option";
      case "Checkbox": {
        if (!Array.isArray(value) || value.some((x) => !ids.includes(x)) || new Set(value).size !== value.length) return "option";
        const min = Math.max(v.minSelected || 0, isRequired(step) ? 1 : 0);
        return value.length < min || (v.maxSelected != null && value.length > v.maxSelected) ? "count" : null;
      }
      case "Comment": {
        // Только для показа (readonly): ответа нет, «Далее» его подтверждает
        if (v.readonly) return value == null || value === "" ? null : "readonly";
        if (typeof value !== "string") return "type";
        const len = value.trim().length;
        if (isRequired(step) && len === 0) return "required";
        if (len > 0 && len < (v.minLength || 0)) return "length";
        return v.maxLength != null && value.length > v.maxLength ? "length" : null;
      }
      case "Datetime": {
        const format = { date: DATE, time: TIME, datetime: DATETIME }[v.kind];
        if (typeof value !== "string" || !format || !format.test(value)) return "format";
        if (v.kind === "datetime" && Number.isNaN(Date.parse(value))) return "format";
        const key = (x) => (v.kind === "datetime" ? Date.parse(x) : v.kind === "time" && x.length === 5 ? `${x}:00` : x);
        if ((v.min && key(value) < key(v.min)) || (v.max && key(value) > key(v.max))) return "range";
        return null;
      }
      case "Image": {
        if (!Array.isArray(value) || value.some((x) => typeof x !== "string")) return "type";
        if (isRequired(step) && value.length === 0) return "required";
        if (!v.allowMultiple && value.length > 1) return "count";
        const known = (attachments || []).filter((a) => a.stepId === step.id).map((a) => a.id);
        return value.every((id) => known.includes(id)) ? null : "attachments";
      }
    }
    return "type";
  }

  // Каноническое значение (спецификация, раздел 9): у кнопки и у шага «только для показа» значения нет
  const canonical = (step, raw) => (step.type === "Button" || (step.type === "Comment" && step.view.readonly) ? null : raw);

  // Путь — шаги, пройденные к текущему, по журналу прогона. Ответ на шаг пути и события того же ответа
  // (переход, finish) решают, что дальше: переход на следующий шаг пути — путь остаётся; на другой —
  // хвост после шага заменяется; finish или «остаться» — путь кончается этим шагом (профиль МИ, решение в7)
  function path(script, result) {
    let p = [script.initialStepId];
    const h = result.history;
    for (let k = 0; k < h.length; k++) {
      if (!isAnswer(h[k])) continue;
      const i = p.lastIndexOf(h[k].stepId);
      if (i < 0) continue;
      let finished = false;
      let to = null;
      for (let j = k + 1; j < h.length && !isAnswer(h[j]); j++) {
        if (h[j].stepId !== h[k].stepId) continue;
        if (h[j].action === "finish") finished = true;
        if (h[j].action === "transition") to = h[j].to;
      }
      if (finished || !to) p = p.slice(0, i + 1);
      else if (p[i + 1] !== to) p = p.slice(0, i + 1).concat(to);
    }
    return p;
  }

  // Куда ведёт ответ по найденному правилу: { finished, next, events, effects, warnings }.
  // withActions = false — при переносе ответов: макросы и отчёт уже были в другом инциденте
  function follow(script, step, evaluated, at, withActions) {
    const out = { finished: false, next: step.id, events: [], effects: [], warnings: [] };
    if (!evaluated) {
      // Шаг без переходов runner-web считает концом сценария
      out.finished = true;
      return out;
    }
    const { outcome, ruleIndex } = evaluated;
    (outcome.actions || []).forEach((a) => {
      const args = a.args || {};
      if (a.type === "finish") {
        out.finished = true;
        out.events.push(Object.assign({ ts: at, stepId: step.id, action: "finish" }, args.resolution != null ? { resolution: args.resolution } : {}));
      } else if (!withActions) {
        return;
      } else if (a.type === "callMacro") {
        out.events.push(Object.assign({ ts: at, stepId: step.id, action: "callMacro", macroId: args.macroId }, args.params ? { params: args.params } : {}));
        out.effects.push({ type: "callMacro", macroId: args.macroId, params: args.params || null, stepId: step.id });
      } else if (a.type === "generateReport") {
        out.events.push(Object.assign({ ts: at, stepId: step.id, action: "generateReport" }, args.templateId ? { templateId: args.templateId } : {}));
      } else {
        // escalate, assign и неизвестные — не исполняются: ответы на переходы инцидента не влияют (решение в8)
        out.warnings.push(`${step.id}: действие ${a.type} не исполняется`);
      }
    });
    if (out.finished) return out;
    const hasGoto = Object.prototype.hasOwnProperty.call(outcome, "goto");
    const goto = outcome.goto == null ? null : outcome.goto;
    if (!hasGoto && ruleIndex === "default") {
      out.warnings.push(`${step.id}: default без goto и без finish — остаёмся на шаге`);
    } else if (goto && goto !== step.id) {
      if (!stepOf(script, goto)) {
        out.warnings.push(`${step.id}: переход на несуществующий шаг ${goto} — остаёмся на шаге`);
      } else {
        out.events.push({ ts: at, stepId: step.id, action: "transition", to: goto, matchedRule: ruleIndex === "default" ? null : ruleIndex });
        out.next = goto;
      }
    }
    return out;
  }

  // Ответ на шаг пути: текущий — всегда; пройденный — если он editable (решение в7).
  // opts: at, by, skip, attachments (для Image). Ответ: { ok, result, effects, warnings } или { ok: false, error }
  function answer(script, result, stepId, raw, opts) {
    const o = opts || {};
    const at = o.at || new Date().toISOString();
    const by = o.by == null ? null : o.by;
    const step = stepOf(script, stepId);
    if (!step) return { ok: false, error: "unknown_step" };
    const before = path(script, result);
    const i = before.lastIndexOf(stepId);
    if (i < 0) return { ok: false, error: "not_on_path" };
    const isCurrent = !result.completedAt && i === before.length - 1;
    if (!isCurrent && step.editable === false) return { ok: false, error: "not_editable" };
    if (o.skip && !canSkip(step)) return { ok: false, error: "required" };
    const attachments = (o.attachments || []).filter((a) => a.stepId === stepId);
    const error = o.skip ? null : checkValue(step, raw, attachments);
    if (error) return { ok: false, error };

    const r = clone(result);
    const value = o.skip ? null : canonical(step, raw);
    r.state[stepId] = o.skip ? { value: null, answeredAt: at, by, skipped: true } : { value, answeredAt: at, by };
    if (step.type === "Image") {
      // Повторный ответ заменяет вложения шага: прежние id в state больше не действуют
      const kept = (r.attachments || []).filter((a) => a.stepId !== stepId);
      r.attachments = o.skip ? kept : kept.concat(clone(attachments.filter((a) => value.includes(a.id))));
    }
    r.history.push(o.skip ? { ts: at, stepId, action: "skip", by } : { ts: at, stepId, action: "answer", value, by });
    const res = follow(script, step, evaluate(step.transitions, r.state), at, true);
    r.history.push(...res.events);

    // Шаги, выпавшие из пути, — без ответа: ответы остаются только в history (решение в7)
    const after = path(script, r);
    const dropped = before.filter((id) => !after.includes(id));
    dropped.forEach((id) => delete r.state[id]);
    if (r.attachments) r.attachments = r.attachments.filter((a) => !dropped.includes(a.stepId));
    if (r.attachments && !r.attachments.length) delete r.attachments;

    if (res.finished) {
      r.currentStepId = null;
      r.completedAt = at;
    } else if (!isCurrent && sameList(before, after) && i < before.length - 1) {
      // Переответ без смены ветки: хвост пути и завершённость — прежние
    } else {
      r.currentStepId = after[after.length - 1];
      r.completedAt = null;
    }
    return { ok: true, result: r, effects: res.effects, warnings: res.warnings };
  }

  // Шаги, по которым ответ может уйти дальше: goto или "finish"
  function outcomesOf(step) {
    if (!step.transitions) return ["finish"];
    return (step.transitions.rules || []).concat(step.transitions.default ? [step.transitions.default] : []).map((o) =>
      (o.actions || []).some((a) => a.type === "finish") ? "finish" : o.goto && o.goto !== step.id ? o.goto : null
    );
  }

  // Сколько шагов от этого до конца по кратчайшему пути, считая его и шаг с finish; конца нет — null
  function remaining(script, from) {
    const dist = new Map([[from, 1]]);
    const queue = [from];
    while (queue.length) {
      const id = queue.shift();
      const step = stepOf(script, id);
      if (!step) continue;
      const outs = outcomesOf(step);
      if (outs.includes("finish")) return dist.get(id);
      outs.forEach((g) => {
        if (g && !dist.has(g) && stepOf(script, g)) {
          dist.set(g, dist.get(id) + 1);
          queue.push(g);
        }
      });
    }
    return null;
  }

  // Шаги впереди: кратчайший путь от текущего шага до конца, без самого текущего; у пройденного — пусто.
  // Обход тот же, что у remaining: путь и шаги впереди вместе дают M в «N из M» (RULE-95)
  function ahead(script, result) {
    if (result.completedAt) return [];
    const from = result.currentStepId;
    const prev = new Map([[from, null]]);
    const queue = [from];
    while (queue.length) {
      const id = queue.shift();
      const step = stepOf(script, id);
      if (!step) continue;
      const outs = outcomesOf(step);
      if (outs.includes("finish")) {
        const out = [];
        for (let x = id; x !== from; x = prev.get(x)) out.unshift(x);
        return out;
      }
      outs.forEach((g) => {
        if (g && !prev.has(g) && stepOf(script, g)) {
          prev.set(g, id);
          queue.push(g);
        }
      });
    }
    return [];
  }

  // Курсор: текущий шаг прогона; у завершённого — последний шаг пути (решение в5)
  function cursor(script, result) {
    if (!result.completedAt) return result.currentStepId;
    const p = path(script, result);
    return p[p.length - 1];
  }

  // «N из M»: N — отвеченные шаги пути, M — N плюс кратчайший остаток до finish; step — номер курсора в пути (решение в6)
  function progress(script, result) {
    const p = path(script, result);
    const filled = p.filter((id) => result.state[id]).length;
    if (result.completedAt) return { filled, total: filled, step: p.length };
    const rest = remaining(script, result.currentStepId);
    const done = result.state[result.currentStepId] ? 1 : 0;
    return { filled, total: rest == null ? null : filled + rest - done, step: p.length };
  }

  // Наборы обязательных шагов (решение в5): closing — прогон дошёл до finish, none — всегда
  const stepsFilled = (script, result, setId) => setId === "none" || (setId === "closing" && Boolean(result.completedAt));

  // Перенос ответов при объединении (решение в11): ответы шагов с тем же id и типом, допустимые в сценарии
  // основного, — в его неотвеченные шаги. Пропущенные не переносятся. Если текущий шаг основного получил
  // ответ, прогон идёт дальше по перенесённым ответам: макросы и отчёт не повторяются, finish — да.
  // Ответ: { result, moved }
  function share(fromScript, fromResult, toScript, toResult, opts) {
    const at = (opts && opts.at) || new Date().toISOString();
    const r = clone(toResult);
    const moved = [];
    Object.keys(fromResult.state).forEach((id) => {
      const entry = fromResult.state[id];
      const src = stepOf(fromScript, id);
      const dst = stepOf(toScript, id);
      if (!entry || entry.skipped || r.state[id] || !src || !dst || src.type !== dst.type) return;
      const attachments = (fromResult.attachments || []).filter((a) => a.stepId === id);
      if (checkValue(dst, entry.value, attachments)) return;
      r.state[id] = clone(entry);
      if (attachments.length) r.attachments = (r.attachments || []).concat(clone(attachments));
      moved.push(id);
    });
    const settled = [];
    while (!r.completedAt && moved.includes(r.currentStepId) && !settled.includes(r.currentStepId)) {
      const step = stepOf(toScript, r.currentStepId);
      const entry = r.state[step.id];
      settled.push(step.id);
      r.history.push({ ts: at, stepId: step.id, action: "answer", value: entry.value, by: entry.by == null ? null : entry.by });
      const res = follow(toScript, step, evaluate(step.transitions, r.state), at, false);
      r.history.push(...res.events);
      if (res.finished) {
        r.currentStepId = null;
        r.completedAt = at;
      } else if (res.next === step.id) {
        break;
      } else {
        r.currentStepId = res.next;
      }
    }
    return { result: r, moved };
  }

  window.IMScenario = { start, answer, path, ahead, cursor, progress, stepsFilled, share, evaluate, checkValue, isRequired, canSkip, remaining };
})();
