/* Тесты исполнителя машины сценариев (prototype/scenario.js) на примерах машины сценариев.
   Что проверяется — спецификация DSL v1 и профиль МИ (Specification/Scenario_machine/README.md).
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

  // Вложение для шага Image — как в демо-runner DSL: данные в самом прогоне
  const attachment = (stepId, n) => ({ id: `att-${stepId}-${n || 1}`, stepId, source: "operator", mime: "image/png", capturedAt: at(), dataBase64: "" });

  // Ответ, который исполнитель обязан принять; variant выбирает вариант — так обходятся разные ветки
  function validAnswer(step, variant) {
    const v = step.view;
    const ids = (v.options || []).map((o) => o.id);
    switch (step.type) {
      case "RadioButton":
      case "Select":
        return { value: ids[variant % ids.length] };
      case "Checkbox": {
        const need = Math.max(v.minSelected || 0, S.isRequired(step) ? 1 : 0, 1);
        const n = Math.min(v.maxSelected || ids.length, need);
        return { value: ids.slice(variant % ids.length).concat(ids).slice(0, n) };
      }
      case "Comment":
        return { value: v.readonly ? "" : "Комментарий оператора".padEnd(v.minLength || 0, ".") };
      case "Datetime":
        return { value: v.min || { date: "2026-10-19", time: "14:30:00", datetime: "2026-10-19T14:30:00+03:00" }[v.kind] };
      case "Image": {
        const att = attachment(step.id);
        return { value: [att.id], attachments: [att] };
      }
      default:
        return { value: null };
    }
  }

  // Согласованность прогона: текущий шаг — конец пути, у завершённого его нет; прогресс не больше итога
  function consistent(script, result, where) {
    const p = S.path(script, result);
    if (result.completedAt) assert.eq(result.currentStepId, null, `${where}: у завершённого нет текущего шага`);
    else assert.eq(result.currentStepId, p[p.length - 1], `${where}: текущий шаг — конец пути`);
    p.slice(0, -1).forEach((id) => assert.ok(result.state[id], `${where}: шаг пути ${id} без ответа`));
    const prog = S.progress(script, result);
    assert.ok(prog.total === null || prog.filled <= prog.total, `${where}: прогресс ${prog.filled} из ${prog.total}`);
    if (result.completedAt) assert.eq(prog.filled, prog.total, `${where}: завершённый — N из N`);
    assert.eq(S.stepsFilled(script, result, "closing"), Boolean(result.completedAt), `${where}: набор closing — прогон завершён`);
    assert.ok(S.stepsFilled(script, result, "none"), `${where}: набор none — всегда`);
  }

  // Пройти сценарий до конца, отвечая на каждый текущий шаг
  function walk(script, variant) {
    let r = S.start(script, at());
    const effects = [];
    const warnings = [];
    for (let guard = 0; !r.completedAt && guard < 100; guard++) {
      const step = stepOf(script, r.currentStepId);
      const a = validAnswer(step, variant);
      const res = S.answer(script, r, step.id, a.value, { at: at(), by: "op-1", attachments: a.attachments });
      assert.ok(res.ok, `${step.id}: ответ ${fmt(a.value)} отклонён — ${res.error}`);
      if (res.result.currentStepId === r.currentStepId && !res.result.completedAt) throw new Error(`${step.id}: прогон не идёт дальше`);
      r = res.result;
      effects.push(...res.effects);
      warnings.push(...res.warnings);
      consistent(script, r, step.id);
    }
    assert.ok(r.completedAt, "прогон не завершился");
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

  /* ===== Все примеры ===== */

  const VALID = Object.keys(EX).filter((k) => !/bad-1|bad-3/.test(k));

  test("Каждый пример проходится до finish в нескольких ветках; прогон согласован после каждого ответа", () => {
    VALID.forEach((name) => {
      const script = EX[name];
      [0, 1, 2, 3].forEach((variant) => {
        try {
          const { result, effects } = walk(script, variant);
          const macros = result.history.filter((e) => e.action === "callMacro").map((e) => e.macroId);
          assert.eq(effects.map((e) => e.macroId), macros, "запуск макросов — те же, что в history");
          assert.ok(!result.history.some((e) => e.action === "escalate" || e.action === "assign"), "escalate и assign не исполняются");
        } catch (err) {
          throw new Error(`${name}, вариант ${variant}: ${err.message}`);
        }
      });
    });
  });

  test("Старт: текущий — начальный шаг, путь из него, ответов нет; чужая старшая версия формата — отказ", () => {
    const script = ex("01-perimeter-alarm.json");
    const r = S.start(script, at());
    assert.eq([r.currentStepId, r.completedAt, r.state, r.history], ["verify_event", null, {}, []]);
    assert.eq(S.path(script, r), ["verify_event"]);
    let thrown = false;
    try {
      S.start(Object.assign(ex("01-perimeter-alarm.json"), { dslVersion: "2.0" }), at());
    } catch (err) {
      thrown = true;
    }
    assert.ok(thrown, "DSL 2.0 не исполняется");
  });

  /* ===== Переходы, обязательность ===== */

  test("Ветвление: первое подходящее правило, иначе default; журнал — answer и transition с номером правила", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = S.start(script, at());
    r = answerOk(script, r, "verify_event", "false_alarm").result;
    assert.eq(r.currentStepId, "btn_close_false");
    assert.eq(r.history.map((e) => [e.action, e.to || e.value, e.matchedRule]), [["answer", "false_alarm", undefined], ["transition", "btn_close_false", 0]]);
    let r2 = S.start(script, at());
    r2 = answerOk(script, r2, "verify_event", "animal").result;
    assert.eq(r2.currentStepId, "operator_note", "default");
    assert.eq(r2.history[1].matchedRule, null, "default — matchedRule null");
  });

  test("Обязательный шаг: без ответа не пропустить; кнопка не пропускается; необязательный — пропуск со skipped", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = answerOk(script, S.start(script, at()), "verify_event", "real_intrusion").result;
    refused(script, r, "snapshot", [], "required");
    refused(script, r, "snapshot", null, "required", { skip: true });
    refused(script, r, "snapshot", ["att-x"], "attachments");
    const att = attachment("snapshot");
    r = answerOk(script, r, "snapshot", [att.id], { attachments: [att] }).result;
    assert.eq(r.attachments.map((a) => a.id), [att.id], "вложение — в прогоне");
    refused(script, r, "operator_note", "   ", "required");
    r = answerOk(script, r, "operator_note", "Нарушитель ушёл").result;
    refused(script, r, "btn_close_real", null, "required", { skip: true });

    const show = ex("showcase/00-primitives.json");
    let s = S.start(show, at());
    ["intro", "next_to_radios", "radio_vertical", "radio_horizontal", "checkbox_single", "checkbox_group", "select_single", "select_long_list", "comment_short"].forEach((id) => {
      s = answerOk(show, s, id, validAnswer(stepOf(show, id), 0).value).result;
    });
    s = answerOk(show, s, "comment_multiline", null, { skip: true }).result;
    assert.eq(s.state.comment_multiline.skipped, true, "skipped: true");
    assert.eq(s.state.comment_multiline.value, null);
    assert.eq(s.history.filter((e) => e.stepId === "comment_multiline").map((e) => e.action), ["skip", "transition"]);
  });

  test("Проверка значений по типу шага: варианты, число отмеченных, формат даты, «только для показа»", () => {
    const show = ex("showcase/00-primitives.json");
    const check = (id, value) => S.checkValue(stepOf(show, id), value, []);
    assert.eq(check("radio_vertical", "nope"), "option");
    assert.eq(check("checkbox_group", []), "count", "меньше minSelected");
    assert.eq(check("checkbox_group", ["smoke", "smell", "alarm", "people"]), "count", "больше maxSelected");
    assert.eq(check("checkbox_group", ["smoke", "smoke"]), "option", "повтор");
    assert.eq(check("checkbox_group", ["smoke", "fire"]), "option", "чужой вариант");
    assert.eq(check("datetime_date", "19.10.2026"), "format");
    assert.eq(check("datetime_time", "14:30"), null);
    assert.eq(check("datetime_full", "2026-10-19T14:30"), null);
    assert.eq(check("intro", "текст"), "readonly");
    assert.eq(check("intro", ""), null);
    const r = answerOk(show, S.start(show, at()), "intro", "").result;
    assert.eq(r.state.intro.value, null, "у шага «только для показа» значения нет");
  });

  test("Шаг без пути: ответ не на шаг пути — отказ; ответ на кнопку хранится как null", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = S.start(script, at());
    refused(script, r, "operator_note", "x", "not_on_path");
    refused(script, r, "no_such_step", "x", "unknown_step");
    r = answerOk(script, r, "verify_event", "false_alarm").result;
    r = answerOk(script, r, "btn_close_false", true).result;
    assert.eq(r.state.btn_close_false.value, null);
    assert.ok(r.completedAt, "finish завершает прогон");
    assert.eq(r.history[r.history.length - 1].action, "finish");
  });

  /* ===== Прогресс, курсор, наборы ===== */

  test("Прогресс «N из M»: M — пройденное плюс кратчайший остаток до finish; на финише M из M; курсор", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = S.start(script, at());
    assert.eq(S.progress(script, r), { filled: 0, total: 2, step: 1 }, "кратчайший путь — ложная тревога и кнопка");
    r = answerOk(script, r, "verify_event", "real_intrusion").result;
    assert.eq(S.progress(script, r), { filled: 1, total: 4, step: 2 }, "после ветвления M вырос");
    const att = attachment("snapshot");
    r = answerOk(script, r, "snapshot", [att.id], { attachments: [att] }).result;
    r = answerOk(script, r, "operator_note", "Нарушитель ушёл за периметр").result;
    assert.eq(S.cursor(script, r), "btn_close_real");
    assert.ok(!S.stepsFilled(script, r, "closing"), "до finish набор closing не выполнен");
    r = answerOk(script, r, "btn_close_real", null).result;
    assert.eq(S.progress(script, r), { filled: 4, total: 4, step: 4 });
    assert.eq(S.cursor(script, r), "btn_close_real", "у завершённого курсор — последний шаг пути");
    assert.ok(S.stepsFilled(script, r, "closing"));
  });

  /* ===== «Назад» и переответ (решение в7) ===== */

  function toNote(script) {
    let r = answerOk(script, S.start(script, at()), "verify_event", "real_intrusion").result;
    const att = attachment("snapshot");
    r = answerOk(script, r, "snapshot", [att.id], { attachments: [att] }).result;
    return r;
  }

  test("Переответ без смены ветки: хвост пути и его ответы остаются, текущий шаг прежний", () => {
    const script = ex("01-perimeter-alarm.json");
    const before = toNote(script);
    const r = answerOk(script, before, "verify_event", "real_intrusion").result;
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

  test("Переответ в завершённом прогоне: другая ветка снимает завершение; шаг с editable: false — отказ", () => {
    const script = ex("01-perimeter-alarm.json");
    let r = answerOk(script, S.start(script, at()), "verify_event", "false_alarm").result;
    r = answerOk(script, r, "btn_close_false", null).result;
    refused(script, r, "btn_close_false", null, "not_editable");
    const same = answerOk(script, r, "verify_event", "false_alarm").result;
    assert.ok(same.completedAt, "та же ветка — прогон остаётся завершённым");
    const other = answerOk(script, r, "verify_event", "animal").result;
    assert.eq([other.completedAt, other.currentStepId], [null, "operator_note"]);
    assert.ok(!S.stepsFilled(script, other, "closing"), "набор closing снова не выполнен");
    assert.ok(!other.state.btn_close_false, "кнопка выпавшей ветки без ответа");
  });

  /* ===== Действия по профилю МИ (решение в8) ===== */

  test("callMacro — внешний эффект и запись в history; assign и escalate не исполняются, предупреждение", () => {
    const script = ex("07-restricted-area-breach.json");
    let r = answerOk(script, S.start(script, at()), "facility_type", "server_room").result;
    r = answerOk(script, r, "intruder_count", "one").result;
    const res = answerOk(script, r, "behavior", ["armed"]);
    assert.eq(res.effects.map((e) => e.macroId), ["MACRO_FULL_LOCKDOWN", "MACRO_CALL_POLICE_URGENT"]);
    assert.eq(res.effects[0].stepId, "behavior");
    assert.ok(res.warnings.some((w) => /assign/.test(w)), "предупреждение об assign");
    assert.ok(!res.result.history.some((e) => e.action === "assign"), "assign не в history");
    assert.eq(res.result.currentStepId, "compare_with_normal");

    const obj = ex("04-suspicious-object.json");
    let o = answerOk(obj, S.start(obj, at()), "object_visible", "yes").result;
    const esc = answerOk(obj, o, "risk_factors", ["wires_visible"]);
    assert.ok(esc.warnings.some((w) => /escalate/.test(w)), "предупреждение об escalate");
    assert.eq(esc.effects.map((e) => e.macroId), ["MACRO_AREA_LOCKDOWN"]);
  });

  test("generateReport и finish — только в history прогона; эффектов для инцидента нет", () => {
    const script = ex("04-suspicious-object.json");
    let r = answerOk(script, S.start(script, at()), "object_visible", "yes").result;
    r = answerOk(script, r, "risk_factors", ["wires_visible"]).result;
    const att = attachment("high_risk_photo");
    r = answerOk(script, r, "high_risk_photo", [att.id], { attachments: [att] }).result;
    const res = answerOk(script, r, "btn_close_high", null);
    assert.eq(res.effects, []);
    assert.eq(res.result.history.slice(-3).map((e) => e.action), ["answer", "generateReport", "finish"]);
  });

  test("Ошибка вычисления условия — ложь; переход на несуществующий шаг — остаёмся с предупреждением", () => {
    const script = ex("01-perimeter-alarm.json");
    stepOf(script, "verify_event").transitions.rules.unshift({ when: { no_such_operator: [1] }, goto: "btn_close_false" });
    const r = answerOk(script, S.start(script, at()), "verify_event", "animal").result;
    assert.eq(r.currentStepId, "operator_note", "неизвестный оператор — правило ложно");
    const bad = ex("architecture/A5-anti-patterns/bad-1-schema-broken-goto.json");
    const step = stepOf(bad, bad.initialStepId);
    const res = S.answer(bad, S.start(bad, at()), step.id, validAnswer(step, 0).value, { at: at() });
    assert.ok(res.ok && res.result.currentStepId === step.id, "остаёмся на шаге");
    assert.ok(res.warnings.some((w) => /несуществующий/.test(w)));
  });

  /* ===== Перенос ответов при объединении (решение в11) ===== */

  test("Перенос: ответы привязанного — в неотвеченные шаги основного, прогон основного идёт по ним дальше, макросы не повторяются", () => {
    const script = ex("07-restricted-area-breach.json");
    let linked = answerOk(script, S.start(script, at()), "facility_type", "server_room").result;
    linked = answerOk(script, linked, "intruder_count", "one").result;
    linked = answerOk(script, linked, "behavior", ["armed"]).result;
    const primary = S.start(script, at());
    const { result, moved } = S.share(script, linked, script, primary, { at: at() });
    assert.eq(moved, ["facility_type", "intruder_count", "behavior"]);
    assert.eq(result.currentStepId, "compare_with_normal", "основной дошёл до первого незаполненного");
    assert.ok(!result.history.some((e) => e.action === "callMacro"), "макросы не повторяются");
    consistent(script, result, "перенос");
  });

  test("Перенос: заполненное в основном не перезаписывается; пропущенные, чужой тип и недопустимый вариант — не переносятся", () => {
    const v1 = ex("01-perimeter-alarm.json");
    let linked = answerOk(v1, S.start(v1, at()), "verify_event", "animal").result;
    linked = answerOk(v1, linked, "operator_note", "Лиса у забора").result;
    const v2 = ex("01-perimeter-alarm.json");
    v2.metadata.version = 2;
    stepOf(v2, "verify_event").view.options = stepOf(v2, "verify_event").view.options.filter((o) => o.id !== "animal");
    const a = S.share(v1, linked, v2, S.start(v2, at()), { at: at() });
    assert.eq(a.moved, ["operator_note"], "варианта animal в версии основного нет");
    assert.eq(a.result.currentStepId, "verify_event", "текущий шаг основного без ответа — прогон стоит");

    const v3 = ex("01-perimeter-alarm.json");
    stepOf(v3, "operator_note").type = "RadioButton";
    assert.eq(S.share(v1, linked, v3, S.start(v3, at()), { at: at() }).moved, ["verify_event"], "чужой тип не переносится");

    const own = answerOk(v1, S.start(v1, at()), "verify_event", "weather").result;
    const b = S.share(v1, linked, v1, own, { at: at() });
    assert.eq(b.result.state.verify_event.value, "weather", "заполненное в основном не перезаписано");
  });

  test("Перенос из завершённого прогона завершает прогон основного: набор closing выполнен", () => {
    const script = ex("01-perimeter-alarm.json");
    let linked = answerOk(script, S.start(script, at()), "verify_event", "false_alarm").result;
    linked = answerOk(script, linked, "btn_close_false", null).result;
    const { result } = S.share(script, linked, script, S.start(script, at()), { at: at() });
    assert.ok(result.completedAt && S.stepsFilled(script, result, "closing"));
    consistent(script, result, "перенос завершённого");
  });

  /* ===== Эталонный набор ===== */

  test("Прохождения инцидентов эталонного набора — те, что даёт исполнитель: те же ответы в том же порядке", () => {
    const fx = window.IM_FIXTURE;
    const rows = Object.fromEntries(fx.scenarios.rows.map((r) => [`${r.guid}/${r.version}`, r.script]));
    fx.incidents.forEach((inc) => {
      const script = rows[`${inc.scenarioGuid}/${inc.scenarioVersion}`];
      assert.ok(script, `${inc.number}: нет сценария ${inc.scenarioGuid} версии ${inc.scenarioVersion}`);
      const stored = inc.scenarioResult;
      let r = S.start(script, stored.history.length ? stored.history[0].ts : at());
      stored.history.filter((h) => h.action === "answer" || h.action === "skip").forEach((h) => {
        const res = S.answer(script, r, h.stepId, h.value, { at: h.ts, by: h.by, skip: h.action === "skip" });
        assert.ok(res.ok, `${inc.number}: ответ на ${h.stepId} отклонён — ${res.error}`);
        r = res.result;
      });
      assert.eq(r, stored, `${inc.number}: прохождение`);
      consistent(script, r, inc.number);
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
