/* Стенд тестов API: окружение, проверки, запуск и отчёт.
   Тесты говорят с сервером только запросами из openapi.json — как интерфейс и бэкенд.
   Каждый тест начинает с POST /test/reset (эталонный набор fixtures/demo.json, часы
   остановлены), время сдвигает POST /test/clock. Поэтому один и тот же набор проходит:
   - встроенный сервер прототипа (по умолчанию: tests/api.html);
   - тестовый стенд бэкенда: tests/api.html?api=https://адрес — бэкенд должен поддерживать
     /test/reset и /test/clock и разрешать запросы со страницы (CORS).
   Ответы сверяются со схемами openapi.json, покрытие — по операциям контракта.
   Отчёт: <pre id="apitest-log">, итог — data-apitest="pass|fail" у <html>. */
(() => {
  const tests = [];
  const enc = encodeURIComponent;
  const apiBase = new URLSearchParams(location.search).get("api");
  const spec = window.IM_OPENAPI;

  // Один сервер на весь прогон: встроенный — со служебными операциями стенда, без своих часов
  // и без эмуляции коллег; внешний — тестовый стенд бэкенда
  const api = apiBase
    ? IMApi.create({ baseUrl: apiBase })
    : IMApi.create({
        server: IMServer.create({
          workflow: window.IM_WORKFLOW,
          fixture: window.IM_FIXTURE,
          colleagues: false,
          autoTick: false,
          testSupport: true,
        }),
      });

  // Каждый ответ запоминается вместе с операцией контракта — для сверки схем и покрытия
  const recorded = [];
  const templates = Object.keys(spec.paths).map((path) => {
    const names = [];
    const re = new RegExp(`^${path.replace(/\{(\w+)\}/g, (m, n) => (names.push(n), "([^/]+)"))}$`);
    return { path, re, params: names.length };
  });
  function templateOf(path) {
    const bare = path.split("?")[0];
    const hits = templates.filter((t) => t.re.test(bare)).sort((a, b) => a.params - b.params);
    return hits.length ? hits[0].path : null;
  }
  async function raw(method, path, body, headers) {
    const res = await api.raw(method, path, body, headers);
    const template = templateOf(path);
    // 404 на адрес, которого нет в контракте, — правильный ответ, сверять нечего
    if (template || res.status !== 404) {
      recorded.push({ method, template: template || path.split("?")[0], status: res.status, body: res.body, headers: res.headers || {}, kind: "http" });
    }
    return res;
  }
  api.subscribe((message) => recorded.push({ method: "GET", template: "/operator/stream", status: 200, body: message, kind: "stream" }));

  async function makeEnv(opts) {
    const reset = await raw("POST", "/test/reset", {
      fixture: "demo",
      operatorPermissions: (opts && opts.permissions) || undefined,
    });
    if (reset.status !== 200) throw new Error(`Тестовый стенд не сбросился: POST /test/reset → ${reset.status}`);
    let clock = Date.parse(reset.body.now);
    const env = {
      api,
      get now() {
        return clock;
      },
      // Время идёт вперёд, сервер выполняет всё, что за это время должно было сработать
      async advance(sec) {
        const res = await raw("POST", "/test/clock", { advanceSec: sec });
        if (res.status !== 200) throw new Error(`POST /test/clock → ${res.status}`);
        clock = Date.parse(res.body.now);
        return res.body.fired;
      },
      call: (method, path, body, headers) => raw(method, path, body, headers),
      async ok(method, path, body) {
        const res = await raw(method, path, body);
        if (res.status >= 400) throw new Error(`${method} ${path} → ${res.status} ${res.body && res.body.message}`);
        return res.body;
      },
      all: async (filter) => (await env.ok("GET", `/operator/incidents?filter=${filter || "all"}&pageSize=1000`)).items,
      card: (id) => env.ok("GET", `/operator/incidents/${enc(id)}`),
      session: () => env.ok("GET", "/operator/session"),
      // Версия записи для If-Match (§14.1) — из ETag свежего чтения карточки, как у клиента,
      // который только что её открыл
      async etag(id) {
        const res = await raw("GET", `/operator/incidents/${enc(id)}`);
        // Нет инцидента — версии нет: запрос уйдёт без If-Match, сервер ответит 404
        if (res.status === 404) return null;
        if (res.status !== 200) throw new Error(`GET карточки ${id} → ${res.status}`);
        if (!res.headers.etag) throw new Error(`GET карточки ${id}: нет заголовка ETag`);
        return res.headers.etag;
      },
      // Переход. ifMatch: не задан — версия свежего чтения; null — запрос без If-Match
      async act(id, transition, formValues, surface, expectedState, ifMatch) {
        const version = ifMatch === undefined ? await env.etag(id) : ifMatch;
        return raw(
          "POST",
          `/operator/incidents/${enc(id)}/transitions/${enc(transition)}`,
          { formValues: formValues || {}, surface: surface || "card", expectedState },
          version === null ? {} : { "If-Match": version }
        );
      },
      // Ответы сценария — с той же версией записи, что и переход
      async answer(id, answers, ifMatch) {
        const version = ifMatch === undefined ? await env.etag(id) : ifMatch;
        return raw("PATCH", `/operator/incidents/${enc(id)}/scenario/answers`, { answers }, version === null ? {} : { "If-Match": version });
      },
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

  // Операции контракта, которые тесты не обязаны вызывать: редактор схемы — вне прототипа
  const NOT_COVERED = /^(GET|POST|PUT) \/operator\/workflow\/schemas/;

  async function run() {
    const lines = [`INFO  Сервер: ${apiBase || "встроенный сервер прототипа"}`];
    let failed = 0;
    // Сначала — доступен ли стенд: иначе каждый тест упал бы с одной и той же сетевой ошибкой
    const probe = await api.raw("POST", "/test/reset", { fixture: "demo" }).catch((err) => ({ status: 0, error: err }));
    if (probe.status !== 200) {
      const why =
        probe.status === 0
          ? "сервер не ответил: нет сети, неверный адрес или бэкенд не разрешает запросы со страницы (CORS)"
          : `POST /test/reset → ${probe.status}: на сервере нет служебных операций тестового стенда`;
      lines.push(`FAIL  Тестовый стенд доступен — ${why}`);
      document.documentElement.dataset.apitest = "fail";
      document.getElementById("apitest-summary").textContent = "Тесты API не запущены: стенд недоступен";
      document.getElementById("apitest-log").textContent = lines.join("\n");
      lines.forEach((l) => console.log(`APITEST ${l}`));
      return;
    }
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
    // Все ответы — со схемами openapi.json
    const problems = IMContract.problems(spec, recorded);
    if (problems.length) {
      failed += 1;
      lines.push(`FAIL  Ответы соответствуют openapi.json — расхождений ${problems.length}: ${problems.slice(0, 12).join("; ")}`);
    } else lines.push(`PASS  Ответы соответствуют openapi.json — ${recorded.length} ответов`);
    // Покрытие: каждая операция контракта вызвана хоть одним тестом
    const called = new Set(recorded.map((r) => `${r.method} ${r.template}`));
    const ops = Object.entries(spec.paths).flatMap(([path, item]) =>
      Object.keys(item)
        .filter((m) => ["get", "post", "put", "patch", "delete"].includes(m))
        .map((m) => `${m.toUpperCase()} ${path}`)
    );
    const uncovered = ops.filter((op) => !called.has(op) && !NOT_COVERED.test(op));
    if (uncovered.length) {
      failed += 1;
      lines.push(`FAIL  Каждая операция контракта покрыта тестами — без тестов: ${uncovered.join(", ")}`);
    } else lines.push(`PASS  Каждая операция контракта покрыта тестами — ${ops.length - ops.filter((op) => NOT_COVERED.test(op)).length} операций`);
    lines.push(`INFO  Не проверяются: ${ops.filter((op) => NOT_COVERED.test(op)).join(", ")} — редактор схемы вне прототипа`);
    const total = tests.length + 2;
    const summary = failed ? `Тесты API: ${failed} из ${total} не прошли` : `Тесты API: все ${total} прошли`;
    document.documentElement.dataset.apitest = failed ? "fail" : "pass";
    lines.forEach((l) => console.log(`APITEST ${l}`));
    console.log(`APITEST ${summary}`);
    document.getElementById("apitest-summary").textContent = summary;
    document.getElementById("apitest-log").textContent = lines.join("\n");
  }

  window.IMTest = { test, run, makeEnv, formFor, fullAnswers, actionOf, assert, enc, external: Boolean(apiBase) };
})();
