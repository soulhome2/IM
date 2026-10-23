/* Стенд тестов API: окружение, проверки, запуск и отчёт.
   Тесты говорят с сервером только запросами из openapi.json — как интерфейс и бэкенд.
   Каждый тест начинает с POST /test/reset (эталонный набор fixtures/demo.json, часы
   остановлены), время сдвигает POST /test/clock. Поэтому один и тот же набор проходит:
   - встроенный сервер прототипа (по умолчанию: tests/api.html);
   - тестовый стенд бэкенда: tests/api.html?api=https://адрес — бэкенд должен поддерживать
     /test/reset и /test/clock и разрешать запросы со страницы (CORS);
   - петля: tests/api.html?api=loopback со страницы по http (python3 -m http.server) — тот же
     встроенный сервер, но за сетевым клиентом: fetch, заголовки, поток SSE (loopback-sw.js).
   Ответы сверяются со схемами openapi.json, покрытие — по операциям контракта.
   Отчёт: <pre id="apitest-log">, итог — data-apitest="pass|fail" у <html>. */
(() => {
  const tests = [];
  const enc = encodeURIComponent;
  const apiBase = new URLSearchParams(location.search).get("api");
  const spec = window.IM_OPENAPI;

  // Один сервер на весь прогон: встроенный — со служебными операциями стенда, без своих часов
  // и без эмуляции коллег; внешний — тестовый стенд бэкенда; петля — встроенный по сети
  let api = null;
  async function connect() {
    if (apiBase === "loopback") {
      if (location.protocol === "file:" || !("serviceWorker" in navigator)) {
        throw new Error("петля работает только со страницы по http(s): python3 -m http.server и http://127.0.0.1:8000/tests/api.html?api=loopback");
      }
      await navigator.serviceWorker.register("loopback-sw.js");
      await navigator.serviceWorker.ready;
      if (!navigator.serviceWorker.controller) {
        await new Promise((resolve) => navigator.serviceWorker.addEventListener("controllerchange", resolve, { once: true }));
      }
      return IMApi.create({ baseUrl: new URL("loopback-api", location.href).href });
    }
    if (apiBase) return IMApi.create({ baseUrl: apiBase });
    return IMApi.create({
      server: IMServer.create({
        workflow: window.IM_WORKFLOW,
        fixture: window.IM_FIXTURE,
        strings: window.IM_STRINGS,
        colleagues: false,
        autoTick: false,
        testSupport: true,
      }),
    });
  }

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

  async function makeEnv(opts) {
    const reset = await raw("POST", "/test/reset", {
      fixture: "demo",
      operatorPermissions: (opts && opts.permissions) || undefined,
      operatorRoles: (opts && opts.roles) || undefined,
      // Изменения схемы и набора на этот прогон — JSON Merge Patch (PROC-13)
      workflowPatch: (opts && opts.workflowPatch) || undefined,
      fixturePatch: (opts && opts.fixturePatch) || undefined,
    });
    if (reset.status !== 200) throw new Error(`Тестовый стенд не сбросился: POST /test/reset → ${reset.status}`);
    let clock = Date.parse(reset.body.now);
    let openIncidentGuid = null;
    const env = {
      api,
      get now() {
        return clock;
      },
      // Признак активности оператора стенда (§12.3) и какая карточка у него открыта
      async heartbeat(guid) {
        if (guid !== undefined) openIncidentGuid = guid;
        const res = await raw("POST", "/operator/session/heartbeat", { openIncidentGuid });
        if (res.status !== 204) throw new Error(`POST /operator/session/heartbeat → ${res.status}`);
        return res;
      },
      // Время идёт вперёд, сервер выполняет всё, что за это время должно было сработать.
      // Оператор стенда на месте: часы идут шагами короче idleHoldSec, перед каждым — признак
      // активности. Иначе бэкенд по §12.3 отложил бы его инциденты с причиной «нет связи»
      async advance(sec) {
        const step = Math.max(1, window.IM_WORKFLOW.session.idleHoldSec - 1);
        const fired = [];
        let left = sec;
        do {
          const chunk = Math.min(left, step);
          await env.heartbeat();
          const res = await raw("POST", "/test/clock", { advanceSec: chunk });
          if (res.status !== 200) throw new Error(`POST /test/clock → ${res.status}`);
          clock = Date.parse(res.body.now);
          fired.push(...res.body.fired);
          left -= chunk;
        } while (left > 0);
        return fired;
      },
      call: (method, path, body, headers) => raw(method, path, body, headers),
      async ok(method, path, body) {
        const res = await raw(method, path, body);
        if (res.status >= 400) throw new Error(`${method} ${path} → ${res.status} ${res.body && res.body.message}`);
        return res.body;
      },
      all: async (filter) => (await env.ok("GET", `/operator/incidents?filter=${filter || "all"}&pageSize=1000`)).items,
      card: (id) => env.ok("GET", `/operator/incidents/${enc(id)}`),
      // Идентификатор инцидента по номеру из эталонного набора (INC-1836): guid — UUID
      async guidOf(number) {
        const found = (await env.all("all")).find((e) => e.number === number);
        if (!found) throw new Error(`нет инцидента ${number}`);
        return found.guid;
      },
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
      // Ответ на шаг сценария ({ stepId, value | skip }) — с той же версией записи, что и переход
      async answer(id, body, ifMatch) {
        const version = ifMatch === undefined ? await env.etag(id) : ifMatch;
        return raw("POST", `/operator/incidents/${enc(id)}/scenario/answer`, body, version === null ? {} : { "If-Match": version });
      },
      // Ответ на текущий шаг прохождения — первый вариант или то, что задано (variant — какой по счёту)
      async answerCurrent(id, variant) {
        const sc = (await env.card(id)).scenario;
        const step = sc.script.steps.find((x) => x.id === sc.result.currentStepId);
        return env.answer(id, answerFor(step, variant || 0));
      },
      // Пройти сценарий до finish — чтобы стал доступен «Обработан» (набор closing, §14.5)
      async passScenario(id, variant) {
        for (let guard = 0; guard < 30; guard++) {
          const sc = (await env.card(id)).scenario;
          if (sc.result.completedAt) return sc;
          const res = await env.answerCurrent(id, variant);
          if (res.status !== 200) return res;
        }
        throw new Error("сценарий не проходится до конца");
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
    Object.assign(values, overrides || {});
    // Невидимое поле не отправляется (README машины, «Формы»): видно ли — по fieldRules и выбранному значению.
    // Заданное тестом явно остаётся
    Object.entries((action && action.fieldRules) || {}).forEach(([name, r]) => {
      const rule = r.dependsOn ? r.byValue[values[r.dependsOn] || ""] || r : r;
      if (rule.visible === false && !(overrides && name in overrides)) delete values[name];
    });
    return values;
  }

  // Ответ, который подходит к шагу (машина сценариев, профиль МИ): вариант по счёту (у Select — в каждом списке),
  // отметок сколько нужно, текст; вложение необязательно — шаг Image пропускается
  function answerFor(step, variant) {
    const v = step.view;
    const nth = (options) => options[(variant || 0) % options.length].id;
    switch (step.type) {
      case "RadioButton":
        return { stepId: step.id, value: nth(v.options) };
      case "Select":
        return { stepId: step.id, value: Object.fromEntries(v.lists.map((l) => [l.id, [nth(l.options)]])) };
      case "Checkbox":
        return { stepId: step.id, value: v.options.map((o) => o.id).slice(0, Math.max(1, v.minSelected)) };
      case "Comment":
        return { stepId: step.id, value: v.readonly ? "" : "тест".padEnd(v.minLength || 0, ".") };
      case "Datetime":
        return { stepId: step.id, value: "2026-10-19T14:30:00Z" };
      case "Image":
        return { stepId: step.id, skip: true };
      default:
        return { stepId: step.id, value: null };
    }
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
  // Редактор схемы и правка справочника приоритетов — вне прототипа (§14.8, §2.5)
  const NOT_COVERED = /^(GET|POST|PUT) \/operator\/workflow\/schemas|^(POST|PUT|DELETE) \/operator\/admin\/priorities/;

  // Отчёт: строки в <pre id="apitest-log"> и в консоль, итог — атрибут data-apitest.
  // С ?report=/адрес — ещё и POST туда: так его забирает tools/check_loopback.py
  function finish(lines, summary, failed) {
    const reportTo = new URLSearchParams(location.search).get("report");
    if (reportTo) {
      const body = lines.concat(summary, `RESULT ${failed ? "fail" : "pass"}`).join("\n");
      fetch(reportTo, { method: "POST", body }).catch(() => {});
    }
    document.documentElement.dataset.apitest = failed ? "fail" : "pass";
    lines.forEach((l) => console.log(`APITEST ${l}`));
    console.log(`APITEST ${summary}`);
    document.getElementById("apitest-summary").textContent = summary;
    document.getElementById("apitest-log").textContent = lines.join("\n");
  }

  async function run() {
    const lines = [`INFO  Сервер: ${apiBase === "loopback" ? "петля: встроенный сервер по сети" : apiBase || "встроенный сервер прототипа"}`];
    let failed = 0;
    try {
      api = await connect();
    } catch (err) {
      lines.push(`FAIL  Тестовый стенд доступен — ${err.message}`);
      return finish(lines, "Тесты API не запущены: стенд недоступен", true);
    }
    api.subscribe((message) => recorded.push({ method: "GET", template: "/operator/stream", status: 200, body: message, kind: "stream" }));
    // Сначала — доступен ли стенд: иначе каждый тест упал бы с одной и той же сетевой ошибкой
    const probe = await api.raw("POST", "/test/reset", { fixture: "demo" }).catch((err) => ({ status: 0, error: err }));
    if (probe.status !== 200) {
      const why =
        probe.status === 0
          ? "сервер не ответил: нет сети, неверный адрес или бэкенд не разрешает запросы со страницы (CORS)"
          : `POST /test/reset → ${probe.status}: на сервере нет служебных операций тестового стенда`;
      lines.push(`FAIL  Тестовый стенд доступен — ${why}`);
      return finish(lines, "Тесты API не запущены: стенд недоступен", true);
    }
    // ?only=<имя теста> — только он; ?failfast — до первого падения (так мутации кода проверяются
    // быстрее: чтобы поймать порчу, хватает одного упавшего теста, PROC-17); ?first=<имя теста> — он первым,
    // потом остальные по порядку (мутации кода: первым — тест, поймавший порчу в прошлый раз). Тесты
    // независимы — каждый со сброса стенда, поэтому порядок на итог не влияет
    const params = new URLSearchParams(location.search);
    const only = params.get("only");
    const failfast = params.has("failfast");
    const first = tests.find((t) => t.name === params.get("first"));
    let firstFailed = null;
    for (const t of first ? [first].concat(tests.filter((x) => x !== first)) : tests) {
      if (only && t.name !== only) continue;
      if (failfast && failed) break;
      const started = Date.now();
      try {
        const note = await t.fn();
        lines.push(`PASS  ${t.name}${note ? ` — ${note}` : ""}`);
      } catch (err) {
        failed += 1;
        if (!firstFailed) firstFailed = t.name;
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
    // Какой тест упал первым — имя целиком, для подсказок мутаций кода (в строке FAIL за ним идёт причина)
    document.documentElement.dataset.apitestFirstFailed = firstFailed || "";
    if (only || (failfast && failed)) {
      const total = only ? 1 : tests.length;
      return finish(lines, failed ? `Тесты API: ${failed} из ${total} не прошли` : `Тесты API: ${total} прошли`, failed);
    }
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
    lines.push(`INFO  Не проверяются: ${ops.filter((op) => NOT_COVERED.test(op)).join(", ")} — редактор схемы и правка справочника приоритетов вне прототипа`);
    const total = tests.length + 2;
    const summary = failed ? `Тесты API: ${failed} из ${total} не прошли` : `Тесты API: все ${total} прошли`;
    finish(lines, summary, failed);
  }

  // Адрес сервера по сети (петля или бэкенд); встроенный — null: тесты протокола потока идут только по сети
  const baseUrl = apiBase === "loopback" ? new URL("loopback-api", location.href).href : apiBase || null;
  window.IMTest = { test, run, makeEnv, formFor, answerFor, actionOf, assert, enc, external: Boolean(apiBase), baseUrl };
})();
