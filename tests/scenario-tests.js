/* Тесты исполнителя машины сценариев (prototype/scenario.js) на примерах машины сценариев.
   Что проверяется — спецификация формата сценария v1 (формат редактора продукта) и профиль МИ (Specification/Scenario_machine/README.md).
   Отчёт: <pre id="scenariotest-log">, итог — data-scenariotest="pass|fail" у <html>. */
(() => {
  const S = window.IMScenario;
  const EX = window.IM_SCENARIO_EXAMPLES;
  const tests = [];
  const test = (name, fn) => tests.push({ name, fn });
  const fmt = (v) => JSON.stringify(v);
  const assert = {
    ok(cond, msg) {
      if (!cond) throw new Error(msg || "условие не выполнено");
    },
    eq(actual, expected, msg) {
      if (fmt(actual) !== fmt(expected)) throw new Error(`${msg || "значение"}: ${fmt(actual)} вместо ${fmt(expected)}`);
    },
  };
  const clone = (x) => JSON.parse(JSON.stringify(x));
  const ex = (name) => clone(EX[name]);
  const stepOf = (script, id) => script.steps.find((s) => s.id === id);
  let tick = 0;
  const at = () => new Date(Date.UTC(2026, 9, 19, 8, 0, tick++)).toISOString();

  // Вложение для шага Image — данные в самом прохождении (спецификация, раздел 9)
  const attachment = (stepId, n) => ({ id: `att-${stepId}-${n || 1}`, stepId, source: "operator", mime: "image/png", capturedAt: at(), dataBase64: "" });

  // Ответ, который исполнитель обязан принять; variant выбирает вариант — так обходятся разные ветки
  function validAnswer(step, variant) {
    const v = step.view;
    switch (step.type) {
      case "RadioButton":
        return { value: v.options[variant % v.options.length].id };
      case "Select":
        return { value: Object.fromEntries(v.lists.map((l) => [l.id, [l.options[variant % l.options.length].id]])) };
      case "Checkbox": {
        const ids = v.options.map((o) => o.id);
        const n = Math.min(v.maxSelected != null ? v.maxSelected : ids.length, Math.max(v.minSelected, 1));
        return { value: ids.slice(variant % ids.length).concat(ids).slice(0, n) };
      }
      case "Comment":
        return { value: v.readonly ? "" : "Комментарий оператора".padEnd(v.minLength || 0, ".") };
      case "Datetime":
        return { value: "2026-10-19T11:30:00Z" };
      case "Image": {
        const att = attachment(step.id);
        return { value: att.id, attachments: [att] };
      }
      default:
        return { value: null };
    }
  }

  // Согласованность прохождения: текущий шаг — конец пути, у завершённого его нет; прогресс не больше итога
  function consistent(script, result, where) {
    const p = S.path(script, result);
    if (result.completedAt) assert.eq(result.currentStepId, null, `${where}: у завершённого нет текущего шага`);
    else assert.eq(result.currentStepId, p[p.length - 1], `${where}: текущий шаг — конец пути`);
    p.slice(0, -1).forEach((id) => assert.ok(result.state[id], `${where}: шаг пути ${id} без ответа`));
    const prog = S.progress(script, result);
    assert.ok(prog.total === null || prog.filled <= prog.total, `${where}: прогресс ${prog.filled} из ${prog.total}`);
    if (result.completedAt) assert.eq(prog.filled, prog.total, `${where}: завершённый — N из N`);
    // Шаги впереди (RULE-95): путь и они вместе — M в «N из M»; у завершённого впереди ничего
    const ahead = S.ahead(script, result);
    if (prog.total !== null) assert.eq(p.length + ahead.length, prog.total, `${where}: шагов на пути и впереди — M`);
    if (result.completedAt) assert.eq(ahead, [], `${where}: у завершённого шагов впереди нет`);
    assert.eq(S.stepsFilled(script, result, "closing"), Boolean(result.completedAt), `${where}: набор closing — прохождение завершено`);
    assert.ok(S.stepsFilled(script, result, "none"), `${where}: набор none — всегда`);
  }

  // Пройти сценарий до конца, отвечая на каждый текущий шаг
  function walk(script, variant) {
    let r = S.start(script);
    const effects = [];
    const warnings = [];
    for (let guard = 0; !r.completedAt && guard < 100; guard++) {
      const step = stepOf(script, r.currentStepId);
      const a = validAnswer(step, variant);
      const res = S.answer(script, r, step.id, a.value, { at: at(), by: "op-1", attachments: a.attachments });
      assert.ok(res.ok, `${step.id}: ответ ${fmt(a.value)} отклонён — ${res.error}`);
      if (res.result.currentStepId === r.currentStepId && !res.result.completedAt) throw new Error(`${step.id}: прохождение не идёт дальше`);
      r = res.result;
      effects.push(...res.effects);
      warnings.push(...res.warnings);
      consistent(script, r, step.id);
    }
    assert.ok(r.completedAt, "прохождение не завершилось");
    return { result: r, effects, warnings };
  }

  const answerOk = (script, r, stepId, value, extra) => {
    const res = S.answer(script, r, stepId, value, Object.assign({ at: at(), by: "op-1" }, extra || {}));
    assert.ok(res.ok, `${stepId}: ответ ${fmt(value)} отклонён — ${res.error}`);
    consistent(script, res.result, stepId);
    return res;
  };
  const refused = (script, r, stepId, value, error, extra) => {
    const res = S.answer(script, r, stepId, value, Object.assign({ at: at() }, extra || {}));
    assert.eq(res.ok ? "принят" : res.error, error, `${stepId}: ${fmt(value)}`);
  };
  const snap = (script, r) => {
    const att = attachment("snapshot");
    return answerOk(script, r, "snapshot", att.id, { attachments: [att] }).result;
  };

  /* ===== Все примеры ===== */

  const VALID = Object.keys(EX).filter((k) => !/bad-1|bad-3/.test(k));

  test("Каждый пример проходится до конца в нескольких ветках; прохождение согласовано после каждого ответа", () => {
    VALID.forEach((name) => {
      const script = EX[name];
      [0, 1, 2, 3].forEach((variant) => {
        try {
          const { result, effects } = walk(script, variant);
          const macros = result.history.filter((e) => e.action === "macro").map((e) => e.name);
          assert.eq(effects.map((e) => e.name), macros, "запуск макросов — те же, что в history");
          assert.eq(result.history[result.history.length - 1].action, "finish", "последнее событие — finish");
        } catch (err) {
          throw new Error(`${name}, вариант ${variant}: ${err.message}`);
        }
      });
    });
  });

  test("Старт: текущий — первый шаг, путь из него, ответов нет; первого шага нет — отказ", () => {
    const script = ex("01-perimeter-alarm.json");
    const r = S.start(script);
    assert.eq([r.currentStepId, r.completedAt, r.state, r.history], ["verify_event", null, {}, []]);
    assert.ok(!("dslVersion" in r), "номера формата в прохождении нет");
    assert.eq(S.path(script, r), ["verify_event"]);
    let thrown = false;
    try {
      S.start(Object.assign(ex("01-perimeter-alarm.json"), { scenario: Object.assign({}, script.scenario, { initialStep: "nope" }) }));
    } catch (err) {
      thrown = true;
    }
    assert.ok(thrown, "без первого шага прохождение не начинается");
  });

  /* ===== Переходы, обязательность ===== */

  test("Ветвление: первое подходящее правило, иначе default; журнал — answer и transition с номером правила", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = S.start(script);
    r = answerOk(script, r, "verify_event", "false_alarm").result;
    assert.eq(r.currentStepId, "btn_close_false");
    assert.eq(r.history.map((e) => [e.action, e.to || e.value, e.matchedRule]), [["answer", "false_alarm", undefined], ["transition", "btn_close_false", 0]]);
    let r2 = S.start(script);
    r2 = answerOk(script, r2, "verify_event", "animal").result;
    assert.eq(r2.currentStepId, "operator_note", "default");
    assert.eq(r2.history[1].matchedRule, null, "default — matchedRule null");
  });

  test("Обязательный шаг: без ответа не пропустить; кнопка не пропускается; необязательный и Image — пропуск со skipped", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = answerOk(script, S.start(script), "verify_event", "real_intrusion").result;
    refused(script, r, "snapshot", "att-x", "attachments");
    const skipped = answerOk(script, r, "snapshot", null, { skip: true }).result;
    assert.eq([skipped.state.snapshot.skipped, skipped.currentStepId], [true, "operator_note"], "Image необязателен");
    r = snap(script, r);
    assert.eq(r.attachments.map((a) => a.id), [r.state.snapshot.value], "вложение одно — в прохождении");
    refused(script, r, "operator_note", "   ", "required");
    refused(script, r, "operator_note", null, "required", { skip: true });
    r = answerOk(script, r, "operator_note", "Нарушитель ушёл").result;
    refused(script, r, "btn_close_real", null, "required", { skip: true });

    const show = ex("showcase/00-primitives.json");
    let s = S.start(show);
    ["intro", "next_to_radios", "radio_vertical", "radio_horizontal", "checkbox_single", "checkbox_group", "select_single", "select_long_list", "comment_short"].forEach((id) => {
      s = answerOk(show, s, id, validAnswer(stepOf(show, id), 0).value).result;
    });
    s = answerOk(show, s, "comment_multiline", null, { skip: true }).result;
    assert.eq(s.state.comment_multiline.skipped, true, "skipped: true");
    assert.eq(s.state.comment_multiline.value, null);
    assert.eq(s.history.filter((e) => e.stepId === "comment_multiline").map((e) => e.action), ["skip", "transition"]);
  });

  test("Проверка значений по типу шага: варианты, число отмеченных, списки Select, дата и время, вложение, «только для показа»", () => {
    const show = ex("showcase/00-primitives.json");
    const check = (id, value, atts) => S.checkValue(stepOf(show, id), value, atts || []);
    assert.eq(check("radio_vertical", "nope"), "option");
    assert.eq(check("checkbox_group", []), "count", "меньше minSelected");
    assert.eq(check("checkbox_group", ["smoke", "smell", "alarm", "people"]), "count", "больше maxSelected");
    assert.eq(check("checkbox_group", ["smoke", "smoke"]), "option", "повтор");
    assert.eq(check("checkbox_group", ["smoke", "fire"]), "option", "чужой вариант");
    const list = stepOf(show, "select_single").view.lists[0];
    assert.eq(check("select_single", list.options[0].id), "type", "Select — объект списков");
    assert.eq(check("select_single", { nope: [list.options[0].id] }), "option", "чужой список");
    assert.eq(check("select_single", { [list.id]: ["nope"] }), "option", "чужой вариант списка");
    assert.eq(check("select_single", { [list.id]: [] }), "required", "обязательный — в каждом списке хоть одно");
    assert.eq(check("select_single", { [list.id]: list.options.slice(0, 2).map((o) => o.id) }), null, "в списке можно отметить несколько");
    assert.eq(check("datetime_date", "19.10.2026"), "format");
    assert.eq(check("datetime_date", "2026-10-19"), "format", "только дата — не ответ: шаг всегда дата и время");
    assert.eq(check("datetime_full", "2026-10-19T11:30:00Z"), null);
    assert.eq(check("datetime_full", "2025-12-31T10:00:00Z"), "range", "раньше min");
    assert.eq(check("image_operator", ["att-1"]), "type", "вложение одно — строка");
    assert.eq(check("image_operator", "att-1", [{ id: "att-1", stepId: "image_operator" }]), null);
    assert.eq(check("intro", "текст"), "readonly");
    assert.eq(check("intro", ""), null);
    const r = answerOk(show, S.start(show), "intro", "").result;
    assert.eq(r.state.intro.value, null, "у шага «только для показа» значения нет");
    const sel = answerOk(show, answerOk(show, answerOk(show, answerOk(show, answerOk(show, answerOk(show, r, "next_to_radios", null).result,
      "radio_vertical", "low").result, "radio_horizontal", "yes").result, "checkbox_single", ["ack"]).result, "checkbox_group", ["smoke"]).result,
      "select_single", { [list.id]: [list.options[1].id] }).result;
    assert.eq(sel.state.select_single.value, { [list.id]: [list.options[1].id] }, "ответ Select — объект списков");
  });

  test("Datetime: ответ — только с часовым поясом; смещение записывается в UTC (BUG-72)", () => {
    const script = {
      scenario: { id: "dt", name: "Дата и время", version: 1, createdAt: "", updatedAt: "", initialStep: "when" },
      steps: [{ id: "when", type: "Datetime", title: "Когда", description: "", revisitable: true, multitasking: false, report: false, finish: true,
        view: { label: "Когда", required: true, min: null, max: null }, transitions: { default: { goto: null, macro: null } } }],
    };
    refused(script, S.start(script), "when", "2026-10-19T14:30", "format");
    refused(script, S.start(script), "when", "2026-10-19T14:30:00", "format");
    assert.eq(answerOk(script, S.start(script), "when", "2026-10-19T14:30:00+05:00").result.state.when.value, "2026-10-19T09:30:00Z", "смещение — в UTC");
    assert.eq(answerOk(script, S.start(script), "when", "2026-10-19T09:30:00.250Z").result.state.when.value, "2026-10-19T09:30:00Z", "до секунды");
  });

  test("Шаг без пути: ответ не на шаг пути — отказ; ответ на кнопку хранится как null; финальный шаг завершает", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = S.start(script);
    refused(script, r, "operator_note", "x", "not_on_path");
    refused(script, r, "no_such_step", "x", "unknown_step");
    r = answerOk(script, r, "verify_event", "false_alarm").result;
    r = answerOk(script, r, "btn_close_false", true).result;
    assert.eq(r.state.btn_close_false.value, null);
    assert.ok(r.completedAt, "ответ на финальный шаг завершает прохождение");
    assert.eq(r.history.slice(-2).map((e) => e.action), ["answer", "finish"]);
  });

  /* ===== Прогресс, курсор, наборы ===== */

  test("Прогресс «N из M»: M — пройденное плюс кратчайший остаток до конца; на конце M из M; курсор", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = S.start(script);
    assert.eq(S.progress(script, r), { filled: 0, total: 2, step: 1 }, "кратчайший путь — ложная тревога и кнопка");
    r = answerOk(script, r, "verify_event", "real_intrusion").result;
    assert.eq(S.progress(script, r), { filled: 1, total: 4, step: 2 }, "после ветвления M вырос");
    r = snap(script, r);
    r = answerOk(script, r, "operator_note", "Нарушитель ушёл за периметр").result;
    assert.eq(S.cursor(script, r), "btn_close_real");
    assert.ok(!S.stepsFilled(script, r, "closing"), "до конца набор closing не выполнен");
    r = answerOk(script, r, "btn_close_real", null).result;
    assert.eq(S.progress(script, r), { filled: 4, total: 4, step: 4 });
    assert.eq(S.cursor(script, r), "btn_close_real", "у завершённого курсор — последний шаг пути");
    assert.ok(S.stepsFilled(script, r, "closing"));
  });

  test("Шаги впереди — кратчайший путь до конца без текущего шага; меняются от ответа (RULE-95)", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = S.start(script);
    assert.eq(S.ahead(script, r), ["btn_close_false"], "в начале — ложная тревога и кнопка");
    r = answerOk(script, r, "verify_event", "real_intrusion").result;
    assert.eq(S.ahead(script, r), ["operator_note", "btn_close_real"], "после «реального проникновения»");
  });

  /* ===== «Назад» и переответ (решение в7) ===== */

  const toNote = (script) => snap(script, answerOk(script, S.start(script), "verify_event", "real_intrusion").result);

  test("Переответ без смены ветки: хвост пути и его ответы остаются, текущий шаг прежний", () => {
    const script = ex("01-perimeter-alarm.json");
    const r = answerOk(script, toNote(script), "verify_event", "real_intrusion").result;
    assert.eq(S.path(script, r), ["verify_event", "snapshot", "operator_note"]);
    assert.eq(r.currentStepId, "operator_note");
    assert.ok(r.state.snapshot && r.attachments.length === 1, "ответ на снимок остался");
  });

  test("Переответ со сменой ветки: выпавшие шаги без ответа, их вложения удалены, в history ответы остаются", () => {
    const script = ex("01-perimeter-alarm.json");
    const r = answerOk(script, toNote(script), "verify_event", "animal").result;
    assert.eq(S.path(script, r), ["verify_event", "operator_note"]);
    assert.eq(r.currentStepId, "operator_note");
    assert.ok(!r.state.snapshot, "ответ выпавшего шага убран из state");
    assert.ok(!r.attachments, "вложения выпавшего шага удалены");
    assert.ok(r.history.some((e) => e.stepId === "snapshot" && e.action === "answer"), "в history ответ остался");
  });

  test("Переответ в завершённом прохождении: другая ветка снимает завершение; шаг с revisitable: false — отказ", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = answerOk(script, S.start(script), "verify_event", "false_alarm").result;
    r = answerOk(script, r, "btn_close_false", null).result;
    refused(script, r, "btn_close_false", null, "not_editable");
    const same = answerOk(script, r, "verify_event", "false_alarm").result;
    assert.ok(same.completedAt, "та же ветка — прохождение остаётся завершённым");
    const other = answerOk(script, r, "verify_event", "animal").result;
    assert.eq([other.completedAt, other.currentStepId], [null, "operator_note"]);
    assert.ok(!S.stepsFilled(script, other, "closing"), "набор closing снова не выполнен");
    assert.ok(!other.state.btn_close_false, "кнопка выпавшей ветки без ответа");
  });

  /* ===== Макрос и флаги шага (спецификация, раздел 8; решение в8) ===== */

  test("Макрос исхода — внешний эффект и запись macro в history; один на исход", () => {
    const script = ex("07-restricted-area-breach.json");
    let r = answerOk(script, S.start(script), "facility_type", validAnswer(stepOf(script, "facility_type"), 0).value).result;
    r = answerOk(script, r, "intruder_count", "one").result;
    const res = answerOk(script, r, "behavior", ["armed"]);
    assert.eq(res.effects.map((e) => [e.type, e.name, e.stepId]), [["macro", "MACRO_FULL_LOCKDOWN + MACRO_CALL_POLICE_URGENT", "behavior"]]);
    assert.eq(res.result.history.filter((e) => e.action === "macro").map((e) => e.name), ["MACRO_FULL_LOCKDOWN + MACRO_CALL_POLICE_URGENT"]);
    assert.eq(res.warnings, []);
    assert.eq(res.result.currentStepId, "compare_with_normal");

    const obj = ex("04-suspicious-object.json");
    const o = answerOk(obj, S.start(obj), "object_visible", "yes").result;
    assert.eq(answerOk(obj, o, "risk_factors", ["wires_visible"]).effects.map((e) => e.name), ["MACRO_AREA_LOCKDOWN"]);
    // Ни одно правило не сработало — путь по default: «Признаков риска нет» делает его достижимым
    assert.eq(answerOk(obj, o, "risk_factors", ["none_found"]).result.currentStepId, "low_risk_action");
  });

  test("Финальный шаг: переходы и макросы на нём не читаются; флаги report и multitasking не исполняются", () => {
    const script = ex("04-suspicious-object.json");
    let r = answerOk(script, S.start(script), "object_visible", "yes").result;
    r = answerOk(script, r, "risk_factors", ["wires_visible"]).result;
    const att = attachment("high_risk_photo");
    r = answerOk(script, r, "high_risk_photo", att.id, { attachments: [att] }).result;
    const last = stepOf(script, "btn_close_high");
    Object.assign(last, { report: true, multitasking: true });
    last.transitions.default = { goto: "object_visible", macro: { name: "НЕ_ЗАПУСКАТЬ", args: {} } };
    const res = answerOk(script, r, "btn_close_high", null);
    assert.eq(res.effects, []);
    assert.ok(res.result.completedAt, "прохождение завершено");
    assert.eq(res.result.history.slice(-2).map((e) => e.action), ["answer", "finish"]);
  });

  test("Ошибка вычисления и пустое условие — ложь; правила у типа без правил не читаются; переход на несуществующий шаг — остаёмся", () => {
    const script = ex("01-perimeter-alarm.json");
    const rules = stepOf(script, "verify_event").transitions.rules;
    rules.unshift({ condition: { no_such_operator: [1] }, goto: "btn_close_false", macro: null }, { condition: {}, goto: "btn_close_false", macro: null });
    let r = answerOk(script, S.start(script), "verify_event", "animal").result;
    assert.eq(r.currentStepId, "operator_note", "неизвестный оператор и {} — правила ложны");
    stepOf(script, "operator_note").transitions.rules = [{ condition: { "==": [1, 1] }, goto: "btn_close_false", macro: null }];
    r = answerOk(script, r, "operator_note", "Лиса у забора, ушла").result;
    assert.eq(r.currentStepId, "btn_close_real", "у Comment правила не читаются — default");
    const bad = ex("architecture/A5-anti-patterns/bad-1-schema-broken-goto.json");
    const step = stepOf(bad, bad.scenario.initialStep);
    const res = S.answer(bad, S.start(bad), step.id, null, { at: at() });
    assert.ok(res.ok && res.result.currentStepId === step.id, "остаёмся на шаге");
    assert.ok(res.warnings.some((w) => /несуществующий/.test(w)));
  });

  test("Условие видит только ответ своего шага; == и in над отмеченными — как в редакторе продукта", () => {
    const obj = ex("04-suspicious-object.json");
    const risk = stepOf(obj, "risk_factors");
    assert.eq(S.contextOf(risk, ["leaking"]), { selected: ["leaking"] });
    assert.eq(S.contextOf(stepOf(obj, "object_visible"), "yes"), { value: "yes" });
    risk.transitions.rules = [
      { condition: { in: [{ var: "selected" }, ["crowded_area", "leaking"]] }, goto: "high_risk_photo", macro: null },
      { condition: { "==": [{ var: "selected" }, "size_large"] }, goto: "medium_risk_action", macro: null },
      { condition: { "==": [{ var: "value" }, "yes"] }, goto: "btn_close_resolved", macro: null },
    ];
    const to = (picked) => S.evaluate(risk, picked).outcome.goto;
    assert.eq(to(["leaking", "crowded_area", "near_critical"]), "high_risk_photo", "in: отмечено всё из условия");
    assert.eq(to(["leaking"]), "low_risk_action", "in: отмечено не всё — дальше");
    assert.eq(to(["size_large", "near_critical"]), "medium_risk_action", "==: вариант среди отмеченных");
    assert.eq(to(["near_critical"]), "low_risk_action", "ответ другого шага условию не виден");
  });

  /* ===== Перенос ответов при объединении (решение в11) ===== */

  test("Перенос: ответы привязанного — в неотвеченные шаги основного, прохождение основного идёт по ним дальше, макросы не повторяются", () => {
    const script = ex("07-restricted-area-breach.json");
    let linked = answerOk(script, S.start(script), "facility_type", validAnswer(stepOf(script, "facility_type"), 0).value).result;
    linked = answerOk(script, linked, "intruder_count", "one").result;
    linked = answerOk(script, linked, "behavior", ["armed"]).result;
    const { result, moved } = S.share(script, linked, script, S.start(script), { at: at() });
    assert.eq(moved, ["facility_type", "intruder_count", "behavior"]);
    assert.eq(result.currentStepId, "compare_with_normal", "основной дошёл до первого незаполненного");
    assert.ok(!result.history.some((e) => e.action === "macro"), "макросы не повторяются");
    consistent(script, result, "перенос");
  });

  test("Перенос: заполненное в основном не перезаписывается; пропущенные, чужой тип и недопустимый вариант — не переносятся; только по пути основного (BUG-87)", () => {
    const v1 = ex("01-perimeter-alarm.json");
    let linked = answerOk(v1, S.start(v1), "verify_event", "animal").result;
    linked = answerOk(v1, linked, "operator_note", "Лиса у забора").result;
    const v2 = ex("01-perimeter-alarm.json");
    v2.scenario.version = 2;
    stepOf(v2, "verify_event").view.options = stepOf(v2, "verify_event").view.options.filter((o) => o.id !== "animal");
    const a = S.share(v1, linked, v2, S.start(v2), { at: at() });
    // Варианта animal в версии основного нет: текущий шаг без ответа — перенос стоит, заметка впереди не переносится
    assert.eq(a.moved, [], "варианта animal в версии основного нет — дальше по пути не переносится");
    assert.eq(a.result.currentStepId, "verify_event", "текущий шаг основного без ответа — прохождение стоит");

    const v3 = ex("01-perimeter-alarm.json");
    stepOf(v3, "operator_note").type = "RadioButton";
    assert.eq(S.share(v1, linked, v3, S.start(v3), { at: at() }).moved, ["verify_event"], "чужой тип не переносится");

    const own = answerOk(v1, S.start(v1), "verify_event", "weather").result;
    const b = S.share(v1, linked, v1, own, { at: at() });
    assert.eq(b.result.state.verify_event.value, "weather", "заполненное в основном не перезаписано");

    // Петля: после заметки — снова оценка. Текущий шаг основного уже отвечен на прошлом круге — его ответ остаётся
    const loop = ex("01-perimeter-alarm.json");
    stepOf(loop, "operator_note").transitions.default.goto = "verify_event";
    let lap = answerOk(loop, S.start(loop), "verify_event", "weather").result;
    lap = answerOk(loop, lap, "operator_note", "Ветер качает ветки").result;
    assert.eq(lap.currentStepId, "verify_event", "основной снова на оценке, ответ прошлого круга при ней");
    const c = S.share(loop, linked, loop, lap, { at: at() });
    assert.eq([c.moved, c.result.state.verify_event.value], [[], "weather"], "ответ прошлого круга не перезаписан");
  });

  test("Перенос из завершённого прохождения завершает прохождение основного: набор closing выполнен", () => {
    const script = ex("01-perimeter-alarm.json");
    let linked = answerOk(script, S.start(script), "verify_event", "false_alarm").result;
    linked = answerOk(script, linked, "btn_close_false", null).result;
    const { result } = S.share(script, linked, script, S.start(script), { at: at() });
    assert.ok(result.completedAt && S.stepsFilled(script, result, "closing"));
    consistent(script, result, "перенос завершённого");
  });

  /* ===== Условия: та же семантика, что у проверки tools/check_scenarios.py ===== */

  test("Крайние случаи JSONLogic: исполнитель даёт то же, что записано в tests/jsonlogic-cases.js (по нему сверяется и проверка на Python)", () => {
    const bad = window.IM_JSONLOGIC_CASES.filter((c) => S.apply(c.when, c.data) !== c.fires);
    assert.eq(bad.map((c) => JSON.stringify(c.when) + " при " + JSON.stringify(c.data)).slice(0, 3), [], "расхождения");
  });

  /* ===== Эталонный набор ===== */

  test("Прохождения инцидентов эталонного набора — те, что даёт исполнитель: те же ответы в том же порядке", () => {
    const fx = window.IM_FIXTURE;
    const rows = Object.fromEntries(fx.scenarios.rows.map((r) => [`${r.guid}/${r.version}`, r.script]));
    fx.incidents.forEach((inc) => {
      const script = rows[`${inc.scenarioGuid}/${inc.scenarioVersion}`];
      assert.ok(script, `${inc.number}: нет сценария ${inc.scenarioGuid} версии ${inc.scenarioVersion}`);
      const stored = inc.scenarioResult;
      let r = S.start(script);
      stored.history.filter((h) => h.action === "answer" || h.action === "skip").forEach((h) => {
        const res = S.answer(script, r, h.stepId, h.value, { at: h.ts, by: h.by, skip: h.action === "skip" });
        assert.ok(res.ok, `${inc.number}: ответ на ${h.stepId} отклонён — ${res.error}`);
        r = res.result;
      });
      assert.eq(r, stored, `${inc.number}: прохождение`);
      consistent(script, r, inc.number);
      // Отвечать может только тот, кто ведёт инцидент (scenarioEdit): у каждого ответа есть by, и к этому моменту
      // по журналу он взял инцидент в работу — «Взято», «Принято», «Перехват» или «Возобновлено» (DATA-08)
      const took = ["workflow.journal.claim", "workflow.journal.accept", "workflow.journal.takeover", "workflow.journal.resume"];
      stored.history.filter((h) => h.action === "answer" || h.action === "skip").forEach((h) => {
        assert.ok(h.by, `${inc.number}: ответ на ${h.stepId} без by`);
        const last = inc.journal.filter((j) => j.at <= h.ts && took.includes(j.template)).pop();
        assert.ok(last && last.actor === h.by, `${inc.number}: ответ ${h.by} на ${h.stepId}, а в работе по журналу — ${last && last.actor}`);
      });
    });
  });

  /* ===== Прогон ===== */

  function report(lines, failed) {
    const summary = failed ? `Провалено: ${failed} из ${tests.length}` : `Пройдено: ${tests.length} из ${tests.length}`;
    document.documentElement.dataset.scenariotest = failed ? "fail" : "pass";
    lines.forEach((l) => console.log(`SCENARIOTEST ${l}`));
    console.log(`SCENARIOTEST ${summary}`);
    document.getElementById("scenariotest-summary").textContent = summary;
    document.getElementById("scenariotest-log").textContent = lines.join("\n");
  }

  document.addEventListener("DOMContentLoaded", () => {
    const lines = [`INFO  Примеров: ${Object.keys(EX).length}`];
    let failed = 0;
    tests.forEach((t) => {
      try {
        t.fn();
        lines.push(`PASS  ${t.name}`);
      } catch (err) {
        failed++;
        lines.push(`FAIL  ${t.name}\n      ${err.message}`);
      }
    });
    report(lines, failed);
  });
})();
