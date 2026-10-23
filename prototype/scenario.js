/* Исполнитель машины сценариев в браузере: формат сценария — формат редактора продукта
   (Specification/Scenario_machine/, спецификация и схема формата сценария v1; CHANGELOG). Переходы — как в предпросмотре
   редактора (playerEngine.ts), операторы условий — как в его jsonLogic.ts (хэши в ORIGIN.md); прохождение
   (scenarioResult) — спецификация, раздел 9; где формат молчит — профиль МИ из README машины сценариев.

   Чистые функции над сценарием (script) и прохождением (scenarioResult). Об инциденте, владельце и очереди
   не знает: что можно отвечать (scenarioEdit), решает машина инцидента, а внешние эффекты (запуск макросов)
   исполняет сервер — здесь они только возвращаются. Условия вычисляет json-logic-js
   (prototype/vendor/json-logic-js), подключённый раньше этого файла. */
(() => {
  const logic = window.jsonLogic;
  // Ответ Datetime — момент: часовой пояс обязателен, «Z» или смещение (BUG-72)
  const DATETIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/;
  const WITH_RULES = ["RadioButton", "Checkbox", "Select"];

  /* Операторы над отмеченными вариантами — как в редакторе продукта (jsonLogic.ts, спецификация, раздел 7):
     стандартный JSONLogic сравнивает массив со строкой через приведение к строке. Остальные — стандартные */
  logic.add_operation("in", (needle, haystack) => {
    if (Array.isArray(haystack)) {
      if (Array.isArray(needle)) return haystack.length > 0 && needle.length > 0 && haystack.every((x) => needle.includes(x));
      return haystack.includes(needle);
    }
    if (typeof haystack === "string") {
      if (Array.isArray(needle)) return needle.some((x) => haystack.includes(String(x)));
      return haystack.includes(String(needle));
    }
    return false;
  });
  logic.add_operation("==", (a, b) => {
    if (Array.isArray(a) && !Array.isArray(b)) return a.includes(b);
    if (Array.isArray(b) && !Array.isArray(a)) return b.includes(a);
    return a == b; // нестрогое сравнение — как в JSONLogic и редакторе
  });
  logic.add_operation("!=", (a, b) => {
    if (Array.isArray(a) && !Array.isArray(b)) return !a.includes(b);
    if (Array.isArray(b) && !Array.isArray(a)) return !b.includes(a);
    return a != b;
  });

  const clone = (x) => JSON.parse(JSON.stringify(x));
  const stepOf = (script, id) => script.steps.find((s) => s.id === id) || null;
  const isAnswer = (ev) => ev.action === "answer" || ev.action === "skip";
  const sameList = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
  const unique = (xs) => new Set(xs).size === xs.length;

  // Обязательный шаг (спецификация, раздел 9, «Пропуск шага»): Checkbox — minSelected > 0; Image — никогда;
  // кнопка — ответ нажатием: обязательности у неё нет, но и пропустить её нельзя
  function isRequired(step) {
    if (step.type === "Checkbox") return step.view.minSelected > 0;
    if (step.type === "Image" || step.type === "Message") return false;
    return step.view.required === true;
  }
  const canSkip = (step) => step.type !== "Message" && !isRequired(step);

  function start(script) {
    if (!stepOf(script, script.scenario.initialStep)) throw new Error(`нет начального шага ${script.scenario.initialStep}`);
    return { state: {}, history: [], currentStepId: script.scenario.initialStep, completedAt: null };
  }

  // Что видит условие: ответ своего шага (спецификация, раздел 7). Пропуск — value null, пустые отметки
  function contextOf(step, value) {
    if (step.type === "RadioButton") return { value: value == null ? null : value };
    if (step.type === "Checkbox") return { selected: Array.isArray(value) ? value : [] };
    if (step.type === "Select") return value && typeof value === "object" ? value : {};
    return {};
  }

  // Условие на контексте: ошибка вычисления — ложь, пустое условие не срабатывает (как в редакторе)
  function apply(condition, context) {
    if (!condition || typeof condition !== "object" || !Object.keys(condition).length) return false;
    try {
      return Boolean(logic.apply(condition, context));
    } catch (err) {
      return false;
    }
  }

  // Первое правило с истинным условием, иначе default; у финального шага переходы не читаются — null
  function evaluate(step, value) {
    if (step.finish) return null;
    const rules = WITH_RULES.includes(step.type) ? step.transitions.rules || [] : [];
    const context = contextOf(step, value);
    for (let i = 0; i < rules.length; i++) if (apply(rules[i].condition, context)) return { outcome: rules[i], ruleIndex: i };
    return { outcome: step.transitions.default, ruleIndex: "default" };
  }

  // Пригоден ли ответ для шага: null — да, иначе причина. Значения — спецификация, раздел 9
  function checkValue(step, value, attachments) {
    const v = step.view;
    switch (step.type) {
      case "Message":
        return null;
      case "RadioButton":
        return typeof value === "string" && v.options.some((o) => o.id === value) ? null : "option";
      case "Checkbox": {
        const ids = v.options.map((o) => o.id);
        if (!Array.isArray(value) || value.some((x) => !ids.includes(x)) || !unique(value)) return "option";
        return value.length < v.minSelected || (v.maxSelected != null && value.length > v.maxSelected) ? "count" : null;
      }
      case "Select": {
        if (!value || typeof value !== "object" || Array.isArray(value)) return "type";
        const lists = new Map(v.lists.map((l) => [l.id, l.options.map((o) => o.id)]));
        for (const [id, picked] of Object.entries(value)) {
          const ids = lists.get(id);
          if (!ids || !Array.isArray(picked) || picked.some((x) => !ids.includes(x)) || !unique(picked)) return "option";
        }
        return v.required && v.lists.some((l) => !(value[l.id] || []).length) ? "required" : null;
      }
      case "Comment": {
        // Только для показа (readonly): ответа нет, «Далее» его подтверждает
        if (v.readonly) return value == null || value === "" ? null : "readonly";
        if (typeof value !== "string") return "type";
        const len = value.trim().length;
        if (v.required && len === 0) return "required";
        if (len > 0 && len < (v.minLength || 0)) return "length";
        return v.maxLength != null && value.length > v.maxLength ? "length" : null;
      }
      case "Datetime": {
        if (typeof value !== "string" || !DATETIME.test(value) || Number.isNaN(Date.parse(value))) return "format";
        if ((v.min && Date.parse(value) < Date.parse(v.min)) || (v.max && Date.parse(value) > Date.parse(v.max))) return "range";
        return null;
      }
      case "Image": {
        // Вложение одно (профиль МИ); id — среди вложений этого шага
        if (typeof value !== "string") return "type";
        return (attachments || []).some((a) => a.stepId === step.id && a.id === value) ? null : "attachments";
      }
    }
    return "type";
  }

  // Каноническое значение (спецификация, раздел 9): у кнопки и у шага «только для показа» значения нет;
  // у Select — все списки шага, неотмеченные — пустые; Datetime — в UTC с точностью до секунды
  function canonical(step, raw) {
    if (step.type === "Message" || (step.type === "Comment" && step.view.readonly)) return null;
    if (step.type === "Select") return Object.fromEntries(step.view.lists.map((l) => [l.id, (raw[l.id] || []).slice()]));
    if (step.type === "Datetime") return new Date(raw).toISOString().replace(/\.\d+Z$/, "Z");
    return raw;
  }

  // Путь — шаги, пройденные к текущему, по журналу прохождения. Ответ на шаг пути и события того же ответа
  // (переход, finish) решают, что дальше: переход на следующий шаг пути — путь остаётся; на другой —
  // хвост после шага заменяется; finish или «остаться» — путь кончается этим шагом (профиль МИ, решение в7)
  function path(script, result) {
    let p = [script.scenario.initialStep];
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

  // Куда ведёт ответ: { finished, next, events, effects, warnings }.
  // withMacro = false — при переносе ответов: макрос уже был в другом инциденте
  function follow(script, step, value, at, withMacro) {
    const out = { finished: false, next: step.id, events: [], effects: [], warnings: [] };
    const evaluated = evaluate(step, value);
    if (!evaluated) {
      out.finished = true;
      out.events.push({ ts: at, stepId: step.id, action: "finish" });
      return out;
    }
    const { outcome, ruleIndex } = evaluated;
    if (outcome.macro && withMacro) {
      const m = outcome.macro;
      const args = m.args && Object.keys(m.args).length ? { args: m.args } : {};
      out.events.push(Object.assign({ ts: at, stepId: step.id, action: "macro", name: m.name }, args));
      out.effects.push({ type: "macro", name: m.name, args: m.args || {}, stepId: step.id });
    }
    const goto = outcome.goto;
    if (goto == null || goto === step.id) {
      // goto: null бывает только у финального шага — проверка сценария такое не пропускает
      out.warnings.push(`${step.id}: перехода нет — остаёмся на шаге`);
    } else if (!stepOf(script, goto)) {
      out.warnings.push(`${step.id}: переход на несуществующий шаг ${goto} — остаёмся на шаге`);
    } else {
      out.events.push({ ts: at, stepId: step.id, action: "transition", to: goto, matchedRule: ruleIndex === "default" ? null : ruleIndex });
      out.next = goto;
    }
    return out;
  }

  // Ответ на шаг пути: текущий — всегда; пройденный — если он revisitable (решение в7).
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
    if (!isCurrent && step.revisitable === false) return { ok: false, error: "not_editable" };
    if (o.skip && !canSkip(step)) return { ok: false, error: "required" };
    const attachments = (o.attachments || []).filter((a) => a.stepId === stepId);
    const error = o.skip ? null : checkValue(step, raw, attachments);
    if (error) return { ok: false, error };

    const r = clone(result);
    const value = o.skip ? null : canonical(step, raw);
    r.state[stepId] = o.skip ? { value: null, answeredAt: at, by, skipped: true } : { value, answeredAt: at, by };
    if (step.type === "Image") {
      // Повторный ответ заменяет вложение шага: прежний id в state больше не действует
      const kept = (r.attachments || []).filter((a) => a.stepId !== stepId);
      r.attachments = o.skip ? kept : kept.concat(clone(attachments.filter((a) => a.id === value)));
    }
    r.history.push(o.skip ? { ts: at, stepId, action: "skip", by } : { ts: at, stepId, action: "answer", value, by });
    const res = follow(script, step, value, at, true);
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

  // Куда может уйти ответ: id шагов или "finish" у финального шага
  function outcomesOf(step) {
    if (step.finish) return ["finish"];
    const rules = WITH_RULES.includes(step.type) ? step.transitions.rules || [] : [];
    return rules.concat([step.transitions.default]).map((o) => (o.goto && o.goto !== step.id ? o.goto : null));
  }

  // Сколько шагов от этого до конца по кратчайшему пути, считая его и финальный шаг; конца нет — null
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

  // Курсор: текущий шаг прохождения; у завершённого — последний шаг пути (решение в5)
  function cursor(script, result) {
    if (!result.completedAt) return result.currentStepId;
    const p = path(script, result);
    return p[p.length - 1];
  }

  // «N из M»: N — отвеченные шаги пути, M — N плюс кратчайший остаток до конца; step — номер курсора в пути (решение в6)
  function progress(script, result) {
    const p = path(script, result);
    const filled = p.filter((id) => result.state[id]).length;
    if (result.completedAt) return { filled, total: filled, step: p.length };
    const rest = remaining(script, result.currentStepId);
    const done = result.state[result.currentStepId] ? 1 : 0;
    return { filled, total: rest == null ? null : filled + rest - done, step: p.length };
  }

  // Наборы обязательных шагов (решение в5): closing — прохождение завершено, none — всегда
  const stepsFilled = (script, result, setId) => setId === "none" || (setId === "closing" && Boolean(result.completedAt));

  // Перенос ответов при объединении (решение в11): ответы шагов с тем же id и типом, допустимые в сценарии
  // основного, — в его неотвеченные шаги. Пропущенные не переносятся. Если текущий шаг основного получил
  // ответ, прохождение идёт дальше по перенесённым ответам: макросы не повторяются, конец — да.
  // Ответ: { result, moved }
  function share(fromScript, fromResult, toScript, toResult, opts) {
    const at = (opts && opts.at) || new Date().toISOString();
    const r = clone(toResult);
    const moved = [];
    // Только в шаги пути основного, по мере продвижения (BUG-87): текущий шаг получает ответ привязанного, путь идёт
    // дальше по нему; у следующего ответа нет — перенос кончается. Шаг вне пути или впереди разрыва не заполняется:
    // иначе «N из M» и набор шагов для закрытия расходились бы с тем, что пройдено
    const settled = [];
    while (!r.completedAt && r.currentStepId && !settled.includes(r.currentStepId)) {
      const id = r.currentStepId;
      const entry = fromResult.state[id];
      const src = stepOf(fromScript, id);
      const step = stepOf(toScript, id);
      if (!entry || entry.skipped || r.state[id] || !src || !step || src.type !== step.type) break;
      const attachments = (fromResult.attachments || []).filter((a) => a.stepId === id);
      if (checkValue(step, entry.value, attachments)) break;
      r.state[id] = clone(entry);
      if (attachments.length) r.attachments = (r.attachments || []).concat(clone(attachments));
      moved.push(id);
      settled.push(id);
      r.history.push({ ts: at, stepId: step.id, action: "answer", value: entry.value, by: entry.by == null ? null : entry.by });
      const res = follow(toScript, step, entry.value, at, false);
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

  window.IMScenario = { start, answer, path, ahead, cursor, progress, stepsFilled, share, evaluate, apply, contextOf, checkValue, isRequired, canSkip, remaining };
})();
