/* Стенд тестов API: окружение со своим сервером и часами, проверки, запуск и отчёт.
   Окружение — встроенный сервер прототипа (server.js) с управляемыми часами: без эмуляции
   коллег, планировщик шагает только по advance(). Тесты говорят с ним через api.js —
   теми же запросами, что интерфейс и будущий бэкенд.
   Отчёт: <pre id="apitest-log">, итог — data-apitest="pass|fail" у <html>. */
(() => {
  const tests = [];
  const servers = [];
  const enc = encodeURIComponent;

  // Часы стенда: фиксированный день, чтобы прогон был воспроизводимым
  const START = new Date(2026, 9, 3, 12, 0, 0).getTime();

  function makeEnv(opts) {
    let clock = START;
    const server = IMServer.create({
      workflow: window.IM_WORKFLOW,
      demo: window.IM_DEMO,
      now: () => clock,
      autoTick: false,
      colleagues: false,
      permissions: opts && opts.permissions,
    });
    const api = IMApi.create({ server });
    servers.push(server);
    const env = {
      server,
      api,
      get now() {
        return clock;
      },
      // Время идёт вперёд, планировщик делает шаг: автоматические переходы по дедлайнам
      advance(sec) {
        clock += sec * 1000;
        return server.tick();
      },
      call: (method, path, body) => api.raw(method, path, body),
      async ok(method, path, body) {
        const res = await api.raw(method, path, body);
        if (res.status >= 400) throw new Error(`${method} ${path} → ${res.status} ${res.body && res.body.message}`);
        return res.body;
      },
      all: async (filter) => (await env.ok("GET", `/operator/incidents?filter=${filter || "all"}&pageSize=1000`)).items,
      card: (id) => env.ok("GET", `/operator/incidents/${enc(id)}`),
      session: () => env.ok("GET", "/operator/session"),
      act: (id, transition, formValues, surface, expectedState) =>
        api.raw("POST", `/operator/incidents/${enc(id)}/transitions/${enc(transition)}`, {
          formValues: formValues || {},
          surface: surface || "card",
          expectedState,
        }),
      async find(pred, filter) {
        const list = await env.all(filter);
        return list.find(pred) || null;
      },
    };
    return env;
  }

  // Значения формы перехода из вариантов, которые отдал сервер (fieldOptions): по умолчанию —
  // его значение по умолчанию или первый доступный вариант; текстовые поля — комментарий
  function formFor(action, overrides) {
    const values = { comment: "тест" };
    Object.entries((action && action.fieldOptions) || {}).forEach(([name, field]) => {
      const enabled = field.options.filter((o) => !o.disabled);
      const pick = enabled.some((o) => o.id === field.defaultValue) ? field.defaultValue : enabled[0] && enabled[0].id;
      if (pick) values[name] = pick;
    });
    return Object.assign(values, overrides || {});
  }

  // Ответы на все обязательные шаги сценария — чтобы стал доступен «Обработан»
  function fullAnswers(card) {
    const answers = {};
    card.scenario.steps.forEach((s) => {
      if (s.type === "Checkbox") answers[s.id] = true;
      else if (s.type === "RadioButton" || s.type === "Select") answers[s.id] = s.view.options[0];
      else if (s.type === "Comment") answers[s.id] = "тест";
    });
    return answers;
  }

  const actionOf = (inc, id) => (inc.actions || []).find((a) => a.id === id) || null;

  class Failure extends Error {}
  const fmt = (v) => JSON.stringify(v);
  const assert = {
    ok(cond, msg) {
      if (!cond) throw new Failure(msg || "условие не выполнено");
    },
    eq(actual, expected, msg) {
      if (fmt(actual) !== fmt(expected)) throw new Failure(`${msg || "значение"}: ${fmt(actual)} вместо ${fmt(expected)}`);
    },
    near(actual, expected, tolerance, msg) {
      if (Math.abs(actual - expected) > tolerance) throw new Failure(`${msg || "значение"}: ${actual} вместо ≈${expected}`);
    },
    status(res, status, code, msg) {
      const got = `${res.status}${res.body && res.body.code ? " " + res.body.code : ""}`;
      const want = `${status}${code ? " " + code : ""}`;
      if (res.status !== status || (code && (!res.body || res.body.code !== code))) {
        throw new Failure(`${msg || "ответ"}: ${got} вместо ${want}${res.body && res.body.message ? ` — ${res.body.message}` : ""}`);
      }
    },
  };

  function test(name, fn) {
    tests.push({ name, fn });
  }

  async function run() {
    const lines = [];
    let failed = 0;
    for (const t of tests) {
      const started = Date.now();
      try {
        const note = await t.fn();
        lines.push(`PASS  ${t.name}${note ? ` — ${note}` : ""}`);
      } catch (err) {
        failed += 1;
        lines.push(`FAIL  ${t.name} — ${err instanceof Failure ? err.message : err && err.stack ? err.stack.split("\n").slice(0, 2).join(" ") : err}`);
      }
      if (Date.now() - started > 20000) lines.push(`      (долго: ${Date.now() - started} мс)`);
    }
    // Все ответы всех окружений — со схемами openapi.json
    const recordedAll = servers.flatMap((s) => s.recorded);
    // Покрытие: каждый маршрут встроенного сервера вызван хоть одним тестом
    const called = new Set(recordedAll.filter((r) => r.kind === "http").map((r) => `${r.method} ${r.template}`));
    const routes = servers.length ? servers[0].routes : [];
    const uncovered = routes.filter((r) => !called.has(r));
    const ops = Object.entries(window.IM_OPENAPI.paths).flatMap(([path, item]) =>
      Object.keys(item)
        .filter((m) => ["get", "post", "put", "patch", "delete"].includes(m))
        .map((m) => `${m.toUpperCase()} ${path}`)
    );
    const notImplemented = ops.filter((op) => !routes.includes(op) && op !== "GET /operator/stream");
    if (uncovered.length) {
      failed += 1;
      lines.push(`FAIL  Каждый маршрут сервера покрыт тестами — без тестов: ${uncovered.join(", ")}`);
    } else lines.push(`PASS  Каждый маршрут сервера покрыт тестами — ${routes.length} маршрутов`);
    lines.push(`INFO  Во встроенном сервере нет операций контракта: ${notImplemented.join(", ") || "—"}`);
    const problems = IMContract.problems(window.IM_OPENAPI, recordedAll);
    if (problems.length) {
      failed += 1;
      lines.push(`FAIL  Ответы соответствуют openapi.json — расхождений ${problems.length}: ${problems.slice(0, 12).join("; ")}`);
    } else lines.push(`PASS  Ответы соответствуют openapi.json — ${recordedAll.length} ответов`);
    const summary = failed ? `Тесты API: ${failed} из ${tests.length + 2} не прошли` : `Тесты API: все ${tests.length + 2} прошли`;
    document.documentElement.dataset.apitest = failed ? "fail" : "pass";
    lines.forEach((l) => console.log(`APITEST ${l}`));
    console.log(`APITEST ${summary}`);
    document.getElementById("apitest-summary").textContent = summary;
    document.getElementById("apitest-log").textContent = lines.join("\n");
  }

  window.IMTest = { test, run, makeEnv, formFor, fullAnswers, actionOf, assert, enc };
})();
