/* Клиент API операторской части (Specification/State_machine/openapi.json).
   Интерфейс говорит только с ним. Два режима:
   - встроенный (по умолчанию): запрос уходит во встроенный сервер server.js в этой же вкладке —
     прототип работает без сети и с диска;
   - внешний (index.html?api=https://…): тот же запрос уходит на настоящий бэкенд по HTTP,
     поток событий — по SSE. Бэкенд должен разрешать запросы со страницы (CORS).
   Ответы всегда приходят обещанием, как по сети. Ошибка — объект { status, problem }. */
(() => {
  function create(opts) {
    const copy = (value) => (value === undefined || value === null ? value : JSON.parse(JSON.stringify(value)));

    if (opts.baseUrl) {
      const base = opts.baseUrl.replace(/\/$/, "");
      const raw = (method, path, body) =>
        fetch(base + path, {
          method,
          headers: body === undefined ? {} : { "Content-Type": "application/json" },
          body: body === undefined ? undefined : JSON.stringify(body),
          credentials: "include",
        }).then(async (res) => {
          const text = await res.text();
          return { status: res.status, body: text ? JSON.parse(text) : null };
        });
      const subscribe = (fn) => {
        const source = new EventSource(`${base}/operator/stream`, { withCredentials: true });
        source.onmessage = (e) => fn(JSON.parse(e.data));
        return () => source.close();
      };
      return wrap(raw, subscribe);
    }

    const server = opts.server;
    // Ответ копируется, как будто прошёл по сети: интерфейс не может поменять данные сервера
    const raw = (method, path, body) =>
      Promise.resolve().then(() => {
        const res = server.handle(method, path, copy(body));
        return { status: res.status, body: copy(res.body) };
      });
    return wrap(raw, (fn) => server.subscribe(fn));
  }

  // raw — ответ как есть: { status, body }. Остальные методы отдают тело, ошибку — исключением
  function wrap(raw, subscribe) {
    const request = (method, path, body) =>
      raw(method, path, body).then((res) => {
        if (res.status >= 400) throw { status: res.status, problem: res.body };
        return res.body;
      });
    const qs = (params) => {
      const pairs = Object.entries(params || {}).filter(([, v]) => v !== undefined && v !== null && v !== "");
      return pairs.length ? `?${pairs.map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join("&")}` : "";
    };
    return {
      raw: (method, path, body) => raw(method, path, body),
      get: (path, params) => request("GET", path + qs(params)),
      post: (path, body) => request("POST", path, body || {}),
      put: (path, body) => request("PUT", path, body || {}),
      patch: (path, body) => request("PATCH", path, body || {}),
      del: (path) => request("DELETE", path),
      subscribe,
    };
  }

  window.IMApi = { create };
})();
