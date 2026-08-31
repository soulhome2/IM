(() => {
  const ME = "Иванов А. С.";

  const SCENARIOS = {
    fire: {
      title: "Пожарная тревога",
      steps: [
        { id: "visual", type: "checkbox", label: "Тревога подтверждена по видео", required: true },
        {
          id: "verdict",
          type: "radio",
          label: "Классификация",
          required: true,
          options: ["Реальная", "Ложная", "Требует выезда"],
        },
        {
          id: "kind",
          type: "combo",
          label: "Тип сработки",
          options: ["Задымление", "Открытое пламя", "Датчик без визуального подтверждения", "Тест системы"],
        },
        { id: "note", type: "edit", label: "Комментарий / номер наряда", placeholder: "Что сделано, кого вызвали" },
        {
          id: "macros",
          type: "macros",
          label: "Макросы объекта",
          buttons: ["Оповещение по объекту", "Разблокировать эвакуационные выходы"],
        },
      ],
    },
    intrusion: {
      title: "Проникновение",
      steps: [
        { id: "visual", type: "checkbox", label: "Нарушитель виден в кадре", required: true },
        {
          id: "verdict",
          type: "radio",
          label: "Классификация",
          required: true,
          options: ["Реальное проникновение", "Персонал / ложная", "Недостаточно данных"],
        },
        {
          id: "zone",
          type: "combo",
          label: "Зона",
          options: ["Периметр", "Служебный вход", "Склад", "Офисная зона"],
        },
        { id: "note", type: "edit", label: "Описание", placeholder: "Маршрут, приметы, действия охраны" },
        { id: "macros", type: "macros", label: "Макросы", buttons: ["Включить сирену", "Переключить PTZ на зону"] },
      ],
    },
    sabotage: {
      title: "Саботаж камеры",
      steps: [
        { id: "lost", type: "checkbox", label: "Подтверждена потеря видео / закрытие объектива" },
        {
          id: "verdict",
          type: "radio",
          label: "Причина",
          required: true,
          options: ["Умышленное воздействие", "Неисправность", "Погодные условия"],
        },
        { id: "note", type: "edit", label: "Комментарий", placeholder: "Камера, симптомы, заявка в сервис" },
        { id: "macros", type: "macros", label: "Макросы", buttons: ["Создать заявку на ремонт"] },
      ],
    },
    loiter: {
      title: "Скопление / праздношатание",
      steps: [
        { id: "visual", type: "checkbox", label: "Ситуация подтверждена", required: true },
        {
          id: "verdict",
          type: "radio",
          label: "Решение",
          required: true,
          options: ["Направить охрану", "Наблюдать", "Ложная"],
        },
        { id: "note", type: "edit", label: "Комментарий" },
      ],
    },
  };

  const CAMERAS = {
    mega_atrium: { id: "mega_atrium", name: "ТЦ Мега · атриум", scene: "fire", x: 210, y: 118 },
    mega_l2: { id: "mega_l2", name: "ТЦ Мега · 2 этаж галерея", scene: "hall", x: 318, y: 92 },
    mega_entry: { id: "mega_entry", name: "ТЦ Мега · главный вход", scene: "gate", x: 92, y: 150 },
    mega_park: { id: "mega_park", name: "ТЦ Мега · паркинг B2", scene: "park", x: 70, y: 210 },
    wh_gate: { id: "wh_gate", name: "Склад-14 · КПП", scene: "gate", x: 140, y: 80 },
    wh_yard: { id: "wh_yard", name: "Склад-14 · двор", scene: "hall", x: 220, y: 140 },
    wh_aisle: { id: "wh_aisle", name: "Склад-14 · ряд C", scene: "hall", x: 300, y: 110 },
    park_r3: { id: "park_r3", name: "Паркинг Юг · ряд 3", scene: "park", x: 180, y: 160 },
    office_hall: { id: "office_hall", name: "БЦ Лидер · холл 4", scene: "hall", x: 200, y: 120 },
  };

  const EVENTS = [
    {
      id: "INC-1847",
      time: "14:31:08",
      typeId: "fire",
      type: "Пожарная тревога",
      object: "ТЦ «Мега»",
      objectType: "Торговый центр",
      location: "2 этаж, атриум",
      region: "Центр",
      priority: "critical",
      status: "new",
      operator: null,
      slaSec: 240,
      cameras: ["mega_atrium", "mega_l2", "mega_entry", "mega_park"],
      pin: { x: 210, y: 118 },
      answers: {},
      launched: [],
      log: [{ t: "14:31:08", who: "Диспетчер", text: "Событие поставлено в очередь" }],
      customGroup: "mega-cluster",
    },
    {
      id: "INC-1846",
      time: "14:28:41",
      typeId: "intrusion",
      type: "Проникновение",
      object: "Склад-14",
      objectType: "Склад",
      location: "КПП, калитка 2",
      region: "Север",
      priority: "high",
      status: "foreign",
      operator: "Петрова М.",
      slaSec: 420,
      cameras: ["wh_gate", "wh_yard", "wh_aisle"],
      pin: { x: 140, y: 80 },
      answers: { visual: true, verdict: "Недостаточно данных" },
      launched: [],
      log: [
        { t: "14:28:41", who: "Диспетчер", text: "Событие поставлено в очередь" },
        { t: "14:29:02", who: "Петрова М.", text: "Взято в работу · шаг 2/5" },
      ],
      customGroup: "north-perim",
    },
    {
      id: "INC-1845",
      time: "14:22:17",
      typeId: "sabotage",
      type: "Саботаж камеры",
      object: "Паркинг Юг",
      objectType: "Паркинг",
      location: "Ряд 3, камера P-12",
      region: "Юг",
      priority: "medium",
      status: "new",
      operator: null,
      slaSec: 900,
      cameras: ["park_r3"],
      pin: { x: 180, y: 160 },
      answers: {},
      launched: [],
      log: [{ t: "14:22:17", who: "Диспетчер", text: "Потеря видеопотока P-12" }],
      customGroup: "south-park",
    },
    {
      id: "INC-1844",
      time: "14:19:03",
      typeId: "loiter",
      type: "Скопление людей",
      object: "ТЦ «Мега»",
      objectType: "Торговый центр",
      location: "Главный вход",
      region: "Центр",
      priority: "medium",
      status: "new",
      operator: null,
      slaSec: 600,
      cameras: ["mega_entry", "mega_atrium"],
      pin: { x: 92, y: 150 },
      answers: {},
      launched: [],
      log: [{ t: "14:19:03", who: "Диспетчер", text: "Детектор скопления" }],
      customGroup: "mega-cluster",
    },
    {
      id: "INC-1843",
      time: "14:11:55",
      typeId: "intrusion",
      type: "Проникновение",
      object: "БЦ «Лидер»",
      objectType: "Офис",
      location: "4 этаж, серверная",
      region: "Центр",
      priority: "high",
      status: "escalated",
      operator: "Дежурный ЦОД",
      slaSec: 180,
      cameras: ["office_hall"],
      pin: { x: 200, y: 120 },
      answers: { visual: true, verdict: "Реальное проникновение" },
      launched: ["Включить сирену"],
      log: [
        { t: "14:12:20", who: "Сидоров К.", text: "Эскалация в ЦОД: нет доступа к объекту" },
      ],
      customGroup: "center-office",
    },
    {
      id: "INC-1842",
      time: "14:06:12",
      typeId: "fire",
      type: "Пожарная тревога",
      object: "Склад-14",
      objectType: "Склад",
      location: "Ряд C, датчик ДП-4",
      region: "Север",
      priority: "high",
      status: "new",
      operator: null,
      slaSec: 300,
      cameras: ["wh_aisle", "wh_yard"],
      pin: { x: 300, y: 110 },
      answers: {},
      launched: [],
      log: [{ t: "14:06:12", who: "Диспетчер", text: "Сработка пожарного датчика" }],
      customGroup: "north-perim",
    },
  ];

  const CUSTOM_GROUPS = [
    { id: "mega-cluster", name: "ТЦ Мега как единый объект", hint: "Атриум + вход + паркинг" },
    { id: "north-perim", name: "Северный периметр", hint: "Склад-14 и КПП" },
    { id: "south-park", name: "Южные паркинги", hint: "Список объектов оператора" },
    { id: "center-office", name: "Офисы Центра", hint: "БЦ Лидер и соседние" },
  ];

  const state = {
    events: EVENTS,
    groupMode: "region",
    groupId: "all",
    filter: "open",
    search: "",
    selectedId: "INC-1847",
    checked: new Set(),
    onBreak: false,
    videoMode: "archive",
    activeCam: "mega_atrium",
    layout: "default",
  };

  const $ = (id) => document.getElementById(id);

  function nowStamp() {
    return new Date().toLocaleTimeString("ru-RU", { hour12: false });
  }

  function toast(text) {
    const el = document.createElement("div");
    el.className = "toast";
    el.textContent = text;
    $("toasts").appendChild(el);
    setTimeout(() => el.remove(), 3200);
  }

  function selected() {
    return state.events.find((e) => e.id === state.selectedId) || null;
  }

  function scenarioDone(ev) {
    const sc = SCENARIOS[ev.typeId];
    return sc.steps
      .filter((s) => s.required)
      .every((s) => {
        const v = ev.answers[s.id];
        return s.type === "checkbox" ? v === true : Boolean(v);
      });
  }

  function stepProgress(ev) {
    const sc = SCENARIOS[ev.typeId];
    const filled = sc.steps.filter((s) => {
      const v = ev.answers[s.id];
      if (s.type === "macros") return ev.launched.length > 0;
      if (s.type === "checkbox") return v === true;
      return Boolean(v);
    }).length;
    return { filled, total: sc.steps.length };
  }

  function statusLabel(ev) {
    if (ev.status === "mine") return { text: "Моё", cls: "mine" };
    if (ev.status === "foreign") return { text: ev.operator, cls: "foreign" };
    if (ev.status === "escalated") return { text: "Эскалация", cls: "esc" };
    if (ev.status === "closed") return { text: "Закрыто", cls: "ok" };
    return { text: "Новое", cls: "new" };
  }

  function groups() {
    const open = state.events.filter((e) => e.status !== "closed");
    const buckets = new Map();
    const add = (id, name, ev, hint) => {
      if (!buckets.has(id)) buckets.set(id, { id, name, hint, items: [] });
      buckets.get(id).items.push(ev);
    };

    if (state.groupMode === "region") {
      open.forEach((e) => add(e.region, e.region, e));
    } else if (state.groupMode === "type") {
      open.forEach((e) => add(e.typeId, e.type, e));
    } else if (state.groupMode === "object") {
      open.forEach((e) => add(e.objectType, e.objectType, e));
    } else {
      CUSTOM_GROUPS.forEach((g) => {
        open.filter((e) => e.customGroup === g.id).forEach((e) => add(g.id, g.name, e, g.hint));
      });
    }

    return [{ id: "all", name: "Все открытые", items: open }, ...buckets.values()];
  }

  function visibleEvents() {
    const g = groups().find((x) => x.id === state.groupId) || groups()[0];
    return g.items.filter((e) => {
      if (state.filter === "open" && e.status === "closed") return false;
      if (state.filter === "mine" && e.status !== "mine") return false;
      if (state.filter === "foreign" && e.status !== "foreign" && e.status !== "escalated") return false;
      if (state.search) {
        const q = state.search.toLowerCase();
        const blob = `${e.id} ${e.type} ${e.object} ${e.location}`.toLowerCase();
        if (!blob.includes(q)) return false;
      }
      return true;
    });
  }

  function renderGroups() {
    const root = $("groupsList");
    root.innerHTML = groups()
      .map((g) => {
        const crit = g.items.filter((e) => e.priority === "critical" && e.status !== "closed").length;
        const countCls = crit ? "crit" : g.items.length ? "warn" : "";
        return `
          <button type="button" class="group-item ${state.groupId === g.id ? "active" : ""}" data-group="${g.id}">
            <span class="name">${g.name}</span>
            <span class="count ${countCls}">${g.items.length}</span>
          </button>
          ${g.hint && state.groupId === g.id ? `<div class="group-sub">${g.hint}</div>` : ""}
        `;
      })
      .join("");
  }

  function renderEvents() {
    const list = visibleEvents();
    $("eventsCount").textContent = String(list.length);
    $("groupProcessBtn").disabled = state.checked.size < 2 || state.onBreak;
    $("eventsList").innerHTML = list
      .map((e) => {
        const st = statusLabel(e);
        return `
          <article class="event ${state.selectedId === e.id ? "selected" : ""}" data-id="${e.id}">
            <input class="pick" type="checkbox" data-check="${e.id}" ${state.checked.has(e.id) ? "checked" : ""} />
            <div class="event-pri ${e.priority}"></div>
            <div class="event-main">
              <div class="event-title">
                <strong>${e.type}</strong>
                <time>${e.time}</time>
              </div>
              <div class="event-sub">${e.id} · ${e.object} · ${e.location}</div>
            </div>
            <div class="event-side">
              <span class="badge ${st.cls}">${st.text}</span>
            </div>
          </article>
        `;
      })
      .join("") || `<div class="empty">Нет событий в текущем фильтре</div>`;
  }

  function renderScenario() {
    const ev = selected();
    const root = $("scenarioRoot");
    if (!ev) {
      root.innerHTML = `<div class="empty">Выберите событие в очереди</div>`;
      return;
    }
    const sc = SCENARIOS[ev.typeId];
    const prog = stepProgress(ev);
    const canClose = scenarioDone(ev) && ev.status === "mine" && !state.onBreak;
    const mine = ev.status === "mine";
    const foreign = ev.status === "foreign" || ev.status === "escalated";

    root.innerHTML = `
      <div class="incident-head">
        <div class="incident-kicker">
          <span>${ev.id}</span>
          <span class="sla ${ev.slaSec < 120 ? "late" : ""}">SLA ${fmtSla(ev.slaSec)}</span>
        </div>
        <h3>${ev.type}</h3>
        <div class="incident-meta">${ev.object} · ${ev.location} · ${ev.region}</div>
        <div class="progress"><i style="width:${Math.round((prog.filled / prog.total) * 100)}%"></i></div>
      </div>
      <form class="scenario-form" id="scenarioForm">
        ${sc.steps
          .map((step, i) => renderStep(step, i, ev, mine && !state.onBreak))
          .join("")}
      </form>
      <div class="scenario-actions">
        ${
          ev.status === "new"
            ? `<button type="button" class="btn primary" id="takeBtn" ${state.onBreak ? "disabled" : ""}>Взять в работу</button>`
            : ""
        }
        ${
          foreign
            ? `<button type="button" class="btn danger" id="takeoverBtn" ${state.onBreak ? "disabled" : ""}>Перехватить</button>`
            : ""
        }
        ${
          mine
            ? `<button type="button" class="btn ghost" id="escalateBtn">Эскалация</button>
               <button type="button" class="btn ok" id="closeBtn" ${canClose ? "" : "disabled"}>Закрыть инцидент</button>`
            : ""
        }
      </div>
      <div class="log">
        <h4>Ход обработки</h4>
        <ul>${ev.log.map((l) => `<li><b>${l.t}</b> · ${l.who} — ${l.text}</li>`).join("")}</ul>
      </div>
    `;
  }

  function renderStep(step, index, ev, enabled) {
    const n = String(index + 1).padStart(2, "0");
    const dis = enabled ? "" : "disabled";
    let control = "";
    if (step.type === "checkbox") {
      control = `<div class="checks"><label><input type="checkbox" data-ans="${step.id}" ${ev.answers[step.id] ? "checked" : ""} ${dis} /> ${step.label}</label></div>`;
    } else if (step.type === "radio") {
      control = `<div class="radios">${step.options
        .map(
          (o) =>
            `<label><input type="radio" name="${step.id}" data-ans="${step.id}" value="${o}" ${
              ev.answers[step.id] === o ? "checked" : ""
            } ${dis} /> ${o}</label>`
        )
        .join("")}</div>`;
    } else if (step.type === "combo") {
      control = `<select data-ans="${step.id}" ${dis}><option value="">Выберите…</option>${step.options
        .map((o) => `<option ${ev.answers[step.id] === o ? "selected" : ""}>${o}</option>`)
        .join("")}</select>`;
    } else if (step.type === "edit") {
      control = `<textarea rows="2" data-ans="${step.id}" placeholder="${step.placeholder || ""}" ${dis}>${
        ev.answers[step.id] || ""
      }</textarea>`;
    } else if (step.type === "macros") {
      control = `<div class="macro-row">${step.buttons
        .map((b) => {
          const on = ev.launched.includes(b);
          return `<button type="button" class="btn ${on ? "ok" : ""}" data-macro="${b}" ${dis}>${
            on ? "Запущено: " : ""
          }${b}</button>`;
        })
        .join("")}</div>`;
    }
    const title = step.type === "checkbox" ? "Шаг сценария" : step.label;
    return `<div class="step"><div class="step-h"><strong>${title}</strong><span>${n}${
      step.required ? " · обяз." : ""
    }</span></div>${step.type === "checkbox" ? "" : ""}${control}</div>`;
  }

  function renderVideo() {
    const ev = selected();
    const cams = ev ? ev.cameras : ["mega_atrium"];
    if (!cams.includes(state.activeCam)) state.activeCam = cams[0];
    $("videoGrid").innerHTML = cams
      .map((id) => {
        const cam = CAMERAS[id];
        const tag = state.videoMode === "live" ? "LIVE" : "АРХИВ";
        return `
          <div class="cam ${state.activeCam === id ? "active" : ""}" data-cam="${id}">
            <div class="scene scene-${cam.scene}">
              <div class="glow"></div><div class="figure"></div><div class="path"></div>
              <div class="slot"></div><div class="bar"></div>
            </div>
            <div class="cam-hud">
              <div>
                <div class="mode-tag ${state.videoMode}">${tag}</div>
                <b>${cam.name}</b>
              </div>
              <span>${state.videoMode === "live" ? nowStamp() : ev ? ev.time : "--:--:--"}</span>
            </div>
          </div>
        `;
      })
      .join("");
    $("tlTime").textContent = ev ? ev.time : nowStamp();
    $("timeline").style.opacity = state.videoMode === "live" ? "0.35" : "1";
  }

  function renderMap() {
    const ev = selected();
    $("mapCaption").textContent = ev ? `${ev.object} · ${ev.location}` : "Место сработки";
    const cams = ev ? ev.cameras : [];
    const pin = ev ? ev.pin : { x: 210, y: 118 };
    $("mapRoot").innerHTML = `
      <svg class="map-svg" viewBox="0 0 400 260" role="img" aria-label="План места инцидента">
        <rect x="24" y="24" width="352" height="212" fill="#1b2026" stroke="#3a4049"/>
        <rect x="40" y="40" width="90" height="70" fill="#222830" stroke="#3a4049"/>
        <rect x="140" y="40" width="140" height="90" fill="#262c34" stroke="#3a4049"/>
        <rect x="290" y="40" width="70" height="70" fill="#222830" stroke="#3a4049"/>
        <rect x="40" y="150" width="200" height="70" fill="#222830" stroke="#3a4049"/>
        <rect x="250" y="150" width="110" height="70" fill="#262c34" stroke="#3a4049"/>
        <text x="50" y="58" fill="#8d949e" font-size="10">вход</text>
        <text x="150" y="58" fill="#8d949e" font-size="10">атриум / зона события</text>
        <text x="50" y="166" fill="#8d949e" font-size="10">паркинг / двор</text>
        <circle class="map-pin" cx="${pin.x}" cy="${pin.y}" r="7">
          <animate attributeName="r" values="6;9;6" dur="1.6s" repeatCount="indefinite"/>
        </circle>
        ${cams
          .map((id) => {
            const c = CAMERAS[id];
            return `<rect class="cam-dot ${state.activeCam === id ? "active" : ""}" data-cam="${id}" x="${c.x - 4}" y="${
              c.y - 4
            }" width="8" height="8"/>`;
          })
          .join("")}
      </svg>
    `;
  }

  function renderStatus() {
    const ev = selected();
    const open = state.events.filter((e) => e.status !== "closed").length;
    $("statusQueue").textContent = `В очереди: ${open}`;
    if (!ev) {
      $("statusIncident").textContent = "Очередь ожидает выбора события";
      $("statusSteps").textContent = "";
      $("statusSla").textContent = "";
      return;
    }
    const prog = stepProgress(ev);
    $("statusIncident").textContent =
      ev.status === "mine"
        ? `Обрабатываю ${ev.id}`
        : ev.status === "foreign"
          ? `${ev.id} у оператора ${ev.operator}`
          : `${ev.id} · ${statusLabel(ev).text}`;
    $("statusSteps").textContent = `Сценарий ${prog.filled}/${prog.total}`;
    $("statusSla").textContent = `Осталось SLA ${fmtSla(ev.slaSec)}`;
  }

  function fmtSla(sec) {
    const m = Math.floor(Math.max(0, sec) / 60);
    const s = Math.max(0, sec) % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function renderAll() {
    renderGroups();
    renderEvents();
    renderScenario();
    renderVideo();
    renderMap();
    renderStatus();
    $("dutyBadge").textContent = state.onBreak ? "Перерыв" : "На смене";
    $("dutyBadge").classList.toggle("off", state.onBreak);
    $("breakBanner").hidden = !state.onBreak;
    $("breakBtn").textContent = state.onBreak ? "На смену" : "Перерыв";
  }

  function takeEvent(ev, mode) {
    if (state.onBreak) {
      toast("На перерыве события не назначаются");
      return;
    }
    const prev = ev.operator;
    ev.status = "mine";
    ev.operator = ME;
    ev.log.push({
      t: nowStamp(),
      who: ME,
      text:
        mode === "takeover"
          ? `Перехват у ${prev}. Прогресс сценария сохранён (${stepProgress(ev).filled}/${stepProgress(ev).total})`
          : "Взято в работу",
    });
    toast(mode === "takeover" ? `Перехвачен ${ev.id}` : `${ev.id} в работе`);
    renderAll();
  }

  function closeEvent(ev) {
    if (!scenarioDone(ev)) {
      toast("Сначала заполните обязательные шаги сценария");
      return;
    }
    ev.status = "closed";
    ev.log.push({ t: nowStamp(), who: ME, text: "Инцидент закрыт. Результат уйдёт в AxxonData" });
    toast(`${ev.id} закрыт`);
    const next = state.events.find((e) => e.status === "new");
    state.selectedId = next ? next.id : ev.id;
    state.checked.delete(ev.id);
    renderAll();
  }

  function bind() {
    $("groupMode").addEventListener("change", (e) => {
      state.groupMode = e.target.value;
      state.groupId = "all";
      renderAll();
    });
    $("layoutMode").addEventListener("change", (e) => {
      state.layout = e.target.value;
      $("workspace").dataset.layout = state.layout;
    });
    $("eventFilter").addEventListener("change", (e) => {
      state.filter = e.target.value;
      renderEvents();
    });
    $("eventSearch").addEventListener("input", (e) => {
      state.search = e.target.value;
      renderEvents();
    });
    $("groupsList").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-group]");
      if (!btn) return;
      state.groupId = btn.dataset.group;
      renderAll();
    });
    $("eventsList").addEventListener("click", (e) => {
      const check = e.target.closest("[data-check]");
      if (check) {
        e.stopPropagation();
        const id = check.dataset.check;
        if (state.checked.has(id)) state.checked.delete(id);
        else state.checked.add(id);
        renderEvents();
        return;
      }
      const row = e.target.closest("[data-id]");
      if (!row) return;
      state.selectedId = row.dataset.id;
      const ev = selected();
      if (ev) state.activeCam = ev.cameras[0];
      renderAll();
    });
    $("scenarioRoot").addEventListener("change", (e) => {
      const ev = selected();
      if (!ev || ev.status !== "mine") return;
      const el = e.target.closest("[data-ans]");
      if (!el) return;
      ev.answers[el.dataset.ans] = el.type === "checkbox" ? el.checked : el.value;
      ev.log.push({ t: nowStamp(), who: ME, text: `Шаг «${el.dataset.ans}» обновлён` });
      renderScenario();
      renderStatus();
    });
    $("scenarioRoot").addEventListener("click", (e) => {
      const ev = selected();
      if (!ev) return;
      if (e.target.id === "takeBtn") takeEvent(ev, "take");
      if (e.target.id === "takeoverBtn") takeEvent(ev, "takeover");
      if (e.target.id === "closeBtn") closeEvent(ev);
      if (e.target.id === "escalateBtn") $("modalEscalate").hidden = false;
      const macro = e.target.closest("[data-macro]");
      if (macro && ev.status === "mine" && !state.onBreak) {
        const name = macro.dataset.macro;
        if (!ev.launched.includes(name)) ev.launched.push(name);
        ev.log.push({ t: nowStamp(), who: ME, text: `Запущен макрос «${name}»` });
        toast(`Макрос: ${name}`);
        renderScenario();
      }
    });
    $("groupProcessBtn").addEventListener("click", () => groupProcess());
    $("videoGrid").addEventListener("click", (e) => {
      const cam = e.target.closest("[data-cam]");
      if (!cam) return;
      state.activeCam = cam.dataset.cam;
      renderVideo();
      renderMap();
    });
    $("mapRoot").addEventListener("click", (e) => {
      const cam = e.target.closest("[data-cam]");
      if (!cam) return;
      state.activeCam = cam.dataset.cam;
      renderVideo();
      renderMap();
    });
    $("videoMode").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-mode]");
      if (!btn) return;
      state.videoMode = btn.dataset.mode;
      [...$("videoMode").children].forEach((b) => b.classList.toggle("active", b === btn));
      renderVideo();
    });
    $("breakBtn").addEventListener("click", () => {
      state.onBreak = !state.onBreak;
      toast(state.onBreak ? "Перерыв. Новые события не назначаются" : "Вы снова на смене");
      renderAll();
    });
    $("hotkeysBtn").addEventListener("click", () => {
      $("modalHotkeys").hidden = false;
    });
    $("linksBtn").addEventListener("click", () => {
      const pop = $("linksMenu").querySelector(".menu-pop");
      pop.hidden = !pop.hidden;
      $("linksBtn").setAttribute("aria-expanded", String(!pop.hidden));
    });
    $("linksMenu").addEventListener("click", (e) => {
      const a = e.target.closest("[data-link]");
      if (!a) return;
      e.preventDefault();
      toast(`Открыть: ${a.dataset.link}`);
      $("linksMenu").querySelector(".menu-pop").hidden = true;
    });
    document.addEventListener("click", (e) => {
      if (!e.target.closest("#linksMenu")) {
        $("linksMenu").querySelector(".menu-pop").hidden = true;
      }
    });
    document.querySelectorAll("[data-close]").forEach((btn) => {
      btn.addEventListener("click", () => {
        $(btn.dataset.close).hidden = true;
      });
    });
    $("escalateConfirm").addEventListener("click", () => {
      const ev = selected();
      if (!ev || ev.status !== "mine") return;
      ev.status = "escalated";
      ev.operator = $("escalateTarget").value;
      ev.log.push({
        t: nowStamp(),
        who: ME,
        text: `Эскалация → ${ev.operator}. ${$("escalateReason").value || "Причина не указана"}`,
      });
      $("modalEscalate").hidden = true;
      toast(`Эскалация ${ev.id}`);
      renderAll();
    });
    document.querySelectorAll("[data-collapse]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const panel = $(btn.dataset.collapse);
        panel.classList.toggle("collapsed");
        btn.textContent = panel.classList.contains("collapsed") ? "+" : "−";
      });
    });
    document.addEventListener("keydown", onKey);
  }

  function groupProcess() {
    if (state.checked.size < 2) return;
    if (state.onBreak) return;
    const ids = [...state.checked];
    const first = state.events.find((e) => e.id === ids[0]);
    ids.forEach((id) => {
      const ev = state.events.find((e) => e.id === id);
      ev.status = "mine";
      ev.operator = ME;
      ev.answers = { ...first.answers };
      ev.log.push({
        t: nowStamp(),
        who: ME,
        text: `Групповая обработка вместе с ${ids.filter((x) => x !== id).join(", ")}`,
      });
    });
    state.selectedId = first.id;
    toast(`Группа из ${ids.length} событий в одной карточке`);
    renderAll();
  }

  function onKey(e) {
    if (e.target.matches("input, textarea, select")) return;
    const key = e.key.toLowerCase();
    if (key === "?" || (e.shiftKey && e.key === "/")) {
      $("modalHotkeys").hidden = !$("modalHotkeys").hidden;
    }
    if (key === "b") $("breakBtn").click();
    if (key === "e") {
      const ev = selected();
      if (ev && ev.status === "mine") $("modalEscalate").hidden = false;
    }
    if (key === "n") {
      const next = state.events.find((x) => x.status === "new");
      if (next) {
        state.selectedId = next.id;
        takeEvent(next, "take");
      }
    }
    if (key === "t") {
      const ev = selected();
      if (ev && (ev.status === "foreign" || ev.status === "escalated")) takeEvent(ev, "takeover");
    }
    if (key === "g") groupProcess();
    if (e.key === "Enter") {
      const ev = selected();
      if (ev && ev.status === "mine") closeEvent(ev);
    }
    if (["1", "2", "3", "4"].includes(e.key)) {
      const ev = selected();
      if (!ev) return;
      const cam = ev.cameras[Number(e.key) - 1];
      if (cam) {
        state.activeCam = cam;
        renderVideo();
        renderMap();
      }
    }
  }

  setInterval(() => {
    $("clock").textContent = nowStamp();
    state.events.forEach((e) => {
      if (e.status !== "closed") e.slaSec -= 1;
    });
    const ev = selected();
    if (ev && ev.status !== "closed") {
      const sla = document.querySelector(".sla");
      if (sla) {
        sla.textContent = `SLA ${fmtSla(ev.slaSec)}`;
        sla.classList.toggle("late", ev.slaSec < 120);
      }
      $("statusSla").textContent = `Осталось SLA ${fmtSla(ev.slaSec)}`;
    }
  }, 1000);

  bind();
  renderAll();
})();
