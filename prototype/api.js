/* Клиент API операторской части (Specification/State_machine/openapi.json).
   Интерфейс говорит только с ним. Два режима:
   - встроенный (по умолчанию): запрос уходит во встроенный сервер server.js в этой же вкладке —
     прототип работает без сети и с диска;
   - внешний (index.html?api=https://…): тот же запрос уходит на настоящий бэкенд по HTTP,
     поток событий — по SSE. Бэкенд должен разрешать запросы со страницы (CORS).
   Ответы всегда приходят обещанием, как по сети. Ошибка — объект { status, problem }.
   Заголовки — как в HTTP: версия записи уходит в If-Match, приходит в ETag (§14.1). */
(() => {
  function create(opts) {
    const copy = (value) => (value === undefined || value === null ? value : JSON.parse(JSON.stringify(value)));

    if (opts.baseUrl) {
      const base = opts.baseUrl.replace(/\/$/, "");
      const raw = (method, path, body, headers) =>
        fetch(base + path, {
          method,
          headers: Object.assign(body === undefined ? {} : { "Content-Type": "application/json" }, headers || {}),
          body: body === undefined ? undefined : JSON.stringify(body),
          credentials: "include",
        }).then(async (res) => {
          const text = await res.text();
          // Имена заголовков — строчными, как их отдаёт fetch. ETag виден странице, только если
          // бэкенд перечислил его в Access-Control-Expose-Headers
          const got = {};
          res.headers.forEach((value, name) => (got[name] = value));
          return { status: res.status, body: text ? JSON.parse(text) : null, headers: got };
        });
      const subscribe = (fn) => {
        const source = new EventSource(`${base}/operator/stream`, { withCredentials: true });
        // Сообщения без имени (без строки event:), тип — в data.type; id: — для Last-Event-ID
        source.onmessage = (e) => fn(JSON.parse(e.data), { lastEventId: e.lastEventId });
        return () => source.close();
      };
      return wrap(raw, subscribe);
    }

    const server = opts.server;
    // Ответ копируется, как будто прошёл по сети: интерфейс не может поменять данные сервера
    const raw = (method, path, body, headers) =>
      Promise.resolve().then(() => {
        const res = server.handle(method, path, copy(body), copy(headers));
        // Имена заголовков — строчными, как у fetch
        const got = {};
        Object.entries(res.headers || {}).forEach(([name, value]) => (got[name.toLowerCase()] = String(value)));
        return { status: res.status, body: copy(res.body), headers: got };
      });
    return wrap(raw, (fn) => server.subscribe((message) => fn(message, { lastEventId: message.id })));
  }

  // raw — ответ как есть: { status, body, headers }. Остальные методы отдают тело, ошибку — исключением
  function wrap(raw, subscribe) {
    const request = (method, path, body, headers) =>
      raw(method, path, body, headers).then((res) => {
        if (res.status >= 400) throw { status: res.status, problem: res.body };
        return res.body;
      });
    const qs = (params) => {
      const pairs = Object.entries(params || {}).filter(([, v]) => v !== undefined && v !== null && v !== "");
      return pairs.length ? `?${pairs.map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join("&")}` : "";
    };
    return {
      raw: (method, path, body, headers) => raw(method, path, body, headers),
      get: (path, params) => request("GET", path + qs(params)),
      post: (path, body, headers) => request("POST", path, body || {}, headers),
      put: (path, body) => request("PUT", path, body || {}),
      patch: (path, body, headers) => request("PATCH", path, body || {}, headers),
      del: (path) => request("DELETE", path),
      subscribe,
    };
  }

  window.IMApi = { create };
})();
