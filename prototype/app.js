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

  const DEVICE_TYPES = {
    camera: { icon: "videocam", label: "Камера видеонаблюдения" },
    "fire-detector": { icon: "local_fire_department", label: "Пожарный извещатель" },
    "panic-button": { icon: "crisis_alert", label: "Тревожная кнопка" },
  };

  const DEVICE_CATALOG = {
    "device-1": { name: "Главный вход", type: "camera" },
    "device-2": { name: "Стойка ресепшн", type: "camera" },
    "device-3": { name: "Конференц-зал — сцена", type: "camera" },
    "device-4": { name: "Конференц-зал — общий план", type: "camera" },
    "device-5": { name: "Опенспейс разработки", type: "camera" },
    "device-6": { name: "Маркетинг — рабочая зона", type: "camera" },
    "device-7": { name: "Переговорная «Невада»", type: "camera" },
    "device-8": { name: "Ворота погрузки А", type: "camera" },
    "device-9": { name: "Стеллажи А1–А8", type: "camera" },
    "device-10": { name: "Зона приёмки товара", type: "camera" },
    "device-11": { name: "Разгрузочная рампа", type: "camera" },
    "device-12": { name: "Центральный проход", type: "camera" },
    "device-13": { name: "Холодильная камера", type: "camera" },
    "device-14": { name: "Пост погрузчика", type: "camera" },
    "device-15": { name: "Испытательный стенд", type: "camera" },
    "device-16": { name: "Вход в чистую зону", type: "camera" },
    "device-17": { name: "Лабораторные столы", type: "camera" },
    "device-18": { name: "Серверная стойка", type: "camera" },
    "device-19": { name: "Вытяжной шкаф", type: "camera" },
    "device-20": { name: "Коридор корпуса Б", type: "camera" },
    "device-21": { name: "Переговорная «Юпитер»", type: "camera" },
    "device-22": { name: "Офисная кухня", type: "camera" },
    "device-23": { name: "Торговый зал", type: "camera" },
    "device-24": { name: "Кассовая зона", type: "camera" },
    "device-25": { name: "Коридор примерочных", type: "camera" },
    "device-26": { name: "Витрина у входа", type: "camera" },
    "device-27": { name: "Зал ресторана", type: "camera" },
    "device-28": { name: "Кухня ресторана", type: "camera" },
    "device-29": { name: "Фойе и бар", type: "camera" },
    "device-30": { name: "Кинозал №3", type: "camera" },
    "device-31": { name: "Зона ожидания — общий план", type: "camera" },
    "device-32": { name: "Гардероб", type: "camera" },
    "device-33": { name: "Обзор поста охраны", type: "camera" },
    "fire-1": { name: "Датчик дыма 1", type: "fire-detector" },
    "fire-2": { name: "Датчик дыма 2", type: "fire-detector" },
    "fire-3": { name: "Датчик дыма 3", type: "fire-detector" },
    "fire-4": { name: "Датчик дыма 4", type: "fire-detector" },
    "fire-5": { name: "Датчик дыма 5", type: "fire-detector" },
    "fire-6": { name: "Датчик дыма — зона ожидания", type: "fire-detector" },
    "panic-1": { name: "Тревожная кнопка — пост охраны", type: "panic-button" },
    "panic-2": { name: "Тревожная кнопка — ресепшн", type: "panic-button" },
  };

  const DEVICES_IN_REPAIR = ["device-9", "device-19", "device-25", "fire-3"];

  function devicesOfType(type) {
    return Object.keys(DEVICE_CATALOG).filter((id) => DEVICE_CATALOG[id].type === type);
  }
  function workingOfType(type) {
    return devicesOfType(type).filter((id) => !DEVICES_IN_REPAIR.includes(id));
  }
  function inRepairOfType(type) {
    return devicesOfType(type).filter((id) => DEVICES_IN_REPAIR.includes(id));
  }

  const TOPOLOGY = [
    {
      id: "group-1",
      name: "Главный офис",
      children: [
        {
          id: "group-2",
          name: "1-й этаж",
          children: [
            {
              id: "group-3",
              name: "Приемная",
              devices: ["device-1", "device-2", "fire-1"],
              children: [
                { id: "group-28", name: "Зона ожидания", devices: ["device-31", "device-32", "fire-6"] },
                { id: "group-29", name: "Пост охраны", devices: ["device-33", "panic-1", "panic-2"] },
              ],
            },
            { id: "group-4", name: "Конференц-зал", devices: ["device-3", "device-4", "fire-2", "device-1"] },
          ],
        },
        {
          id: "group-5",
          name: "2-й этаж",
          children: [
            { id: "group-6", name: "Отдел разработки", devices: ["device-5"] },
            { id: "group-7", name: "Отдел маркетинга", devices: ["device-6", "device-7"] },
          ],
        },
      ],
    },
    {
      id: "group-8",
      name: "Складской комплекс",
      children: [
        {
          id: "group-9",
          name: "Этаж А",
          children: [
            { id: "group-10", name: "Склад №1", devices: ["device-8", "device-9", "device-10", "fire-3"] },
            { id: "group-11", name: "Склад №2", devices: ["device-11", "device-12", "device-8"] },
          ],
        },
        {
          id: "group-12",
          name: "Этаж Б",
          children: [{ id: "group-13", name: "Склад №3", devices: ["device-13", "device-14"] }],
        },
      ],
    },
    {
      id: "group-14",
      name: "Технопарк",
      children: [
        {
          id: "group-15",
          name: "Корпус А",
          children: [
            { id: "group-16", name: "Лаборатория 1", devices: ["device-15", "device-16", "fire-4"] },
            { id: "group-17", name: "Лаборатория 2", devices: ["device-17", "device-18", "device-19"] },
          ],
        },
        {
          id: "group-18",
          name: "Корпус Б",
          children: [
            { id: "group-19", name: "Офис 1", devices: ["device-20", "device-15"] },
            { id: "group-20", name: "Офис 2", devices: ["device-21", "device-22"] },
          ],
        },
      ],
    },
    {
      id: "group-21",
      name: "Торговый центр",
      children: [
        {
          id: "group-22",
          name: "1-й этаж",
          children: [
            { id: "group-23", name: "Магазин 1", devices: ["device-23", "device-24", "fire-5"] },
            { id: "group-24", name: "Магазин 2", devices: ["device-25", "device-26"] },
          ],
        },
        {
          id: "group-25",
          name: "2-й этаж",
          children: [
            { id: "group-26", name: "Ресторан", devices: ["device-27", "device-28"] },
            { id: "group-27", name: "Кинотеатр", devices: ["device-29", "device-30"] },
          ],
        },
      ],
    },
    {
      id: "group-all-cameras",
      name: "Все камеры",
      description: "Сквозная подборка камер видеонаблюдения со всех объектов, разделённая по состоянию оборудования.",
      children: [
        {
          id: "group-cameras-working",
          name: "Рабочие",
          description: "Камеры в штатной работе.",
          devices: workingOfType("camera"),
        },
        {
          id: "group-cameras-repair",
          name: "В ремонте",
          description: "Камеры, временно выведенные из эксплуатации.",
          devices: inRepairOfType("camera"),
        },
      ],
    },
    {
      id: "group-fire-detectors",
      name: "Пожарные датчики",
      description: "Сквозная подборка пожарных датчиков со всех объектов, разделённая по состоянию оборудования.",
      children: [
        {
          id: "group-fire-working",
          name: "Рабочие",
          description: "Датчики в штатной работе.",
          devices: workingOfType("fire-detector"),
        },
        {
          id: "group-fire-repair",
          name: "В ремонте",
          description: "Датчики, временно выведенные из эксплуатации.",
          devices: inRepairOfType("fire-detector"),
        },
      ],
    },
  ];

  function buildTree(nodes) {
    return nodes.map((node) => {
      const group = { id: node.id, name: node.name };
      if (node.description) group.description = node.description;
      group.children = node.children ? buildTree(node.children) : [];
      (node.devices || []).forEach((deviceId) => {
        group.children.push({ id: deviceId, isDevice: true });
      });
      return group;
    });
  }

  const TREE = buildTree(TOPOLOGY);

  function camScene(id) {
    const name = (DEVICE_CATALOG[id] && DEVICE_CATALOG[id].name) || "";
    if (/дыма|пожар/i.test(name)) return "fire";
    if (/ворот|вход|рамп/i.test(name)) return "gate";
    if (/стеллаж|приёмк|погруз/i.test(name)) return "park";
    return "hall";
  }

  function cameraOf(id, x, y) {
    const spec = DEVICE_CATALOG[id];
    return { id, name: spec ? spec.name : id, scene: camScene(id), x, y };
  }

  const CAMERAS = {
    "device-1": cameraOf("device-1", 92, 150),
    "device-8": cameraOf("device-8", 140, 80),
    "device-9": cameraOf("device-9", 220, 140),
    "device-10": cameraOf("device-10", 300, 110),
    "device-11": cameraOf("device-11", 180, 160),
    "device-18": cameraOf("device-18", 200, 120),
    "device-23": cameraOf("device-23", 210, 118),
    "device-24": cameraOf("device-24", 318, 92),
    "device-25": cameraOf("device-25", 180, 160),
    "device-26": cameraOf("device-26", 70, 210),
    "device-33": cameraOf("device-33", 92, 150),
  };

  const EVENTS = [
    {
      id: "INC-1847",
      time: "14:31:08",
      typeId: "fire",
      type: "Пожарная тревога",
      object: "Торговый центр",
      objectType: "Торговый центр",
      location: "Магазин 1, торговый зал",
      region: "Торговый центр",
      priority: "critical",
      status: "new",
      operator: null,
      slaSec: 240,
      deviceIds: ["fire-5", "device-23", "device-24"],
      media: "both",
      cameras: ["device-23", "device-24", "device-26"],
      pin: { x: 210, y: 118 },
      answers: {},
      launched: [],
      log: [{ t: "14:31:08", who: "Диспетчер", text: "Событие поставлено в очередь" }],
    },
    {
      id: "INC-1846",
      time: "14:28:41",
      typeId: "intrusion",
      type: "Проникновение",
      object: "Складской комплекс",
      objectType: "Склад",
      location: "Склад №1, ворота погрузки А",
      region: "Складской комплекс",
      priority: "high",
      status: "foreign",
      operator: "Петрова М.",
      slaSec: 420,
      deviceIds: ["device-8", "device-9", "device-10"],
      media: "video",
      cameras: ["device-8", "device-10", "device-11"],
      pin: { x: 140, y: 80 },
      answers: { visual: true, verdict: "Недостаточно данных" },
      launched: [],
      log: [
        { t: "14:28:41", who: "Диспетчер", text: "Событие поставлено в очередь" },
        { t: "14:29:02", who: "Петрова М.", text: "Взято в работу · шаг 2/5" },
      ],
    },
    {
      id: "INC-1845",
      time: "14:22:17",
      typeId: "sabotage",
      type: "Саботаж камеры",
      object: "Торговый центр",
      objectType: "Торговый центр",
      location: "Магазин 2, коридор примерочных",
      region: "Торговый центр",
      priority: "medium",
      status: "mine",
      operator: "Иванов А. С.",
      paused: true,
      stepIndex: 1,
      slaSec: 900,
      deviceIds: ["device-25"],
      media: "video",
      cameras: ["device-25", "device-26"],
      pin: { x: 180, y: 160 },
      answers: { lost: true },
      launched: [],
      log: [
        { t: "14:22:17", who: "Диспетчер", text: "Потеря видеопотока «Коридор примерочных»" },
        { t: "14:23:05", who: "Иванов А. С.", text: "Взято в работу" },
        { t: "14:24:40", who: "Иванов А. С.", text: "Обработка приостановлена на шаге 2" },
      ],
    },
    {
      id: "INC-1844",
      time: "14:19:03",
      typeId: "loiter",
      type: "Скопление людей",
      object: "Торговый центр",
      objectType: "Торговый центр",
      location: "1-й этаж, витрина у входа",
      region: "Торговый центр",
      priority: "medium",
      status: "new",
      operator: null,
      slaSec: 600,
      deviceIds: ["device-26", "device-23"],
      media: "both",
      cameras: ["device-26", "device-23"],
      pin: { x: 92, y: 150 },
      answers: {},
      launched: [],
      log: [{ t: "14:19:03", who: "Диспетчер", text: "Детектор скопления" }],
    },
    {
      id: "INC-1843",
      time: "14:11:55",
      typeId: "intrusion",
      type: "Проникновение",
      object: "Главный офис",
      objectType: "Офис",
      location: "Приемная, пост охраны",
      region: "Главный офис",
      priority: "high",
      status: "escalated",
      operator: "Дежурный ЦОД",
      slaSec: 180,
      deviceIds: ["panic-1", "device-33"],
      media: "map",
      cameras: [],
      pin: { x: 92, y: 150 },
      answers: { visual: true, verdict: "Реальное проникновение" },
      launched: ["Включить сирену"],
      log: [
        { t: "14:12:20", who: "Сидоров К.", text: "Эскалация в ЦОД: нет доступа к объекту" },
      ],
    },
    {
      id: "INC-1842",
      time: "14:06:12",
      typeId: "fire",
      type: "Пожарная тревога",
      object: "Складской комплекс",
      objectType: "Склад",
      location: "Склад №1, датчик дыма 3",
      region: "Складской комплекс",
      priority: "high",
      status: "new",
      operator: null,
      slaSec: 300,
      deviceIds: ["fire-3", "device-8", "device-10"],
      media: "map",
      cameras: [],
      pin: { x: 300, y: 110 },
      answers: {},
      launched: [],
      log: [{ t: "14:06:12", who: "Диспетчер", text: "Сработка пожарного датчика" }],
    },
  ];

  const state = {
    events: EVENTS,
    mode: "queue",
    groupsOn: true,
    groupId: "all",
    openGroups: new Set(TREE.map((n) => n.id)),
    groupQuery: "",
    filter: "open",
    search: "",
    selectedId: "INC-1847",
    checked: new Set(),
    onBreak: false,
    videoMode: "archive",
    activeCam: "device-23",
  };

  const ACTIONS = {
    take: { label: "Взять", style: "primary", hint: "Взять инцидент в работу" },
    resume: { label: "Возобновить", style: "primary", hint: "Продолжить приостановленную обработку" },
    open: { label: "Открыть", style: "outline", hint: "Посмотреть ход обработки другого оператора" },
    view: { label: "Просмотр", style: "outline", hint: "Открыть карточку закрытого инцидента" },
  };

  const $ = (id) => document.getElementById(id);

  function nowStamp() {
    return new Date().toLocaleTimeString("ru-RU", { hour12: false });
  }

  function applyTheme(theme) {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem("im-theme", theme);
    } catch (err) {
      /* ignore */
    }
    [...$("themeMode").children].forEach((b) => b.classList.toggle("active", b.dataset.theme === theme));
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

  function scenarioSteps(ev) {
    return SCENARIOS[ev.typeId].steps;
  }

  function stepShort(step) {
    if (step.type === "checkbox") return "Подтверждение";
    return step.label;
  }

  function stepAnswerText(ev, step) {
    if (step.type === "checkbox") return ev.answers[step.id] ? "Да" : "";
    if (step.type === "macros") return ev.launched.length ? `${ev.launched.length} макрос` : "";
    return ev.answers[step.id] || "";
  }

  function isStepValid(ev, step) {
    if (!step.required) return true;
    if (step.type === "checkbox") return ev.answers[step.id] === true;
    if (step.type === "macros") return true;
    return Boolean(ev.answers[step.id]);
  }

  function scenarioDone(ev) {
    return scenarioSteps(ev).every((s) => isStepValid(ev, s));
  }

  function firstOpenStep(ev) {
    const steps = scenarioSteps(ev);
    const blocked = steps.findIndex((s) => s.required && !isStepValid(ev, s));
    if (blocked !== -1) return blocked;
    const empty = steps.findIndex((s) => !stepAnswerText(ev, s));
    return empty === -1 ? steps.length - 1 : empty;
  }

  function canOpenStep(ev, index) {
    const steps = scenarioSteps(ev);
    if (index < 0 || index >= steps.length) return false;
    return steps.slice(0, index).every((s) => isStepValid(ev, s));
  }

  function ensureCursor(ev) {
    if (typeof ev.stepIndex !== "number") ev.stepIndex = firstOpenStep(ev);
    const last = scenarioSteps(ev).length - 1;
    if (ev.stepIndex < 0) ev.stepIndex = 0;
    if (ev.stepIndex > last) ev.stepIndex = last;
    if (!canOpenStep(ev, ev.stepIndex)) ev.stepIndex = firstOpenStep(ev);
  }

  function goToStep(ev, index) {
    if (!canOpenStep(ev, index)) return;
    ev.stepIndex = index;
    renderScenario();
    renderStatus();
  }

  function stepProgress(ev) {
    const steps = scenarioSteps(ev);
    const filled = steps.filter((s) => Boolean(stepAnswerText(ev, s))).length;
    return { filled, total: steps.length };
  }

  function statusLabel(ev) {
    if (ev.status === "mine") {
      return ev.paused ? { text: "Приостановлен", cls: "pause" } : { text: "В работе", cls: "mine" };
    }
    if (ev.status === "foreign") return { text: ev.operator, cls: "foreign" };
    if (ev.status === "escalated") return { text: "Эскалация", cls: "esc" };
    if (ev.status === "closed") return { text: "Закрыто", cls: "ok" };
    return { text: "Новое", cls: "new" };
  }

  function actionKind(ev) {
    if (ev.status === "closed") return "view";
    if (ev.status === "mine") return "resume";
    if (ev.status === "foreign" || ev.status === "escalated") return "open";
    return "take";
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function deviceInfo(node) {
    const id = typeof node === "string" ? node : node.id;
    const spec = DEVICE_CATALOG[id];
    return {
      id,
      name: spec ? spec.name : id,
      deviceType: spec ? spec.type : "camera",
    };
  }

  function orderedChildren(data) {
    const groups = data.filter((item) => !item.isDevice);
    const devices = data.filter((item) => item.isDevice);
    return groups.concat(devices);
  }

  function findNode(nodes, id) {
    for (const node of nodes) {
      if (node.id === id) return node;
      if (node.children) {
        const found = findNode(node.children, id);
        if (found) return found;
      }
    }
    return null;
  }

  function collectDeviceIds(node) {
    if (!node) return [];
    if (node.isDevice) return [node.id];
    const ids = [];
    (node.children || []).forEach((child) => {
      ids.push(...collectDeviceIds(child));
    });
    return [...new Set(ids)];
  }

  function deviceHasOpenIncident(id) {
    return state.events.some((e) => e.status !== "closed" && (e.deviceIds || []).includes(id));
  }

  function visibleChildren(nodes) {
    return orderedChildren(nodes || []).filter((item) => !item.isDevice || deviceHasOpenIncident(item.id));
  }

  function badgeText(node) {
    const children = node.children || [];
    const groups = children.filter((c) => !c.isDevice).length;
    const devices = children.filter((c) => c.isDevice && deviceHasOpenIncident(c.id)).length;
    return `${groups}/${devices}`;
  }

  function eventsForDevices(deviceIds) {
    const set = new Set(deviceIds);
    return state.events.filter((e) => (e.deviceIds || []).some((id) => set.has(id)));
  }

  function eventsInNode(node) {
    return eventsForDevices(collectDeviceIds(node));
  }

  function nodeLabel(node) {
    if (!node) return "";
    if (node.isDevice) return deviceInfo(node).name;
    return node.name;
  }

  function nodeMatchesQuery(node, q) {
    if (!q) return true;
    if (node.isDevice && !deviceHasOpenIncident(node.id)) return false;
    if (nodeLabel(node).toLowerCase().includes(q)) return true;
    return visibleChildren(node.children).some((child) => nodeMatchesQuery(child, q));
  }

  function visibleEvents() {
    let list = state.events;
    if (state.groupId !== "all") {
      const node = findNode(TREE, state.groupId);
      const ids = node ? collectDeviceIds(node) : [state.groupId];
      list = eventsForDevices(ids);
    }
    return list.filter((e) => {
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

  function renderTreeHtml(nodes, level) {
    const q = state.groupQuery.trim().toLowerCase();
    return visibleChildren(nodes)
      .map((item) => {
        const kids = item.isDevice ? [] : visibleChildren(item.children);
        const hasKids = kids.length > 0;
        const info = item.isDevice ? deviceInfo(item) : null;
        const icon = info ? DEVICE_TYPES[info.deviceType].icon : "folder";
        const name = info ? info.name : item.name;
        const evs = item.isDevice ? eventsForDevices([item.id]) : eventsInNode(item);
        const openCount = evs.filter((e) => e.status !== "closed").length;
        const crit = evs.some((e) => e.priority === "critical" && e.status !== "closed");
        const hidden = q && !nodeMatchesQuery(item, q);
        const forceOpen = Boolean(q && hasKids && nodeMatchesQuery(item, q));
        const open = forceOpen || state.openGroups.has(item.id);
        const title = item.description || name;
        return `
          <li class="tree-node ${hasKids ? "has-children" : ""} ${open ? "open" : ""} ${
            state.groupId === item.id ? "active" : ""
          } ${item.isDevice ? "is-device" : ""} ${hidden ? "hidden" : ""} level-${level}"
              data-id="${item.id}" data-type="${item.isDevice ? "device" : "group"}" role="treeitem">
            <div class="node-content" title="${escapeHtml(title)}">
              <span class="toggle-icon material-symbols-outlined">chevron_right</span>
              <span class="material-symbols-outlined">${icon}</span>
              <span class="node-text">${escapeHtml(name)}</span>
              ${!item.isDevice && hasKids ? `<span class="tree-badge">${badgeText(item)}</span>` : ""}
              ${openCount ? `<span class="tree-ev ${crit ? "crit" : ""}">${openCount}</span>` : ""}
            </div>
            ${hasKids ? `<ul role="group">${renderTreeHtml(item.children, level + 1)}</ul>` : ""}
          </li>`;
      })
      .join("");
  }

  function renderGroups() {
    const collapseBtn = $("groupsCollapseAll");
    const expanded = state.openGroups.size > 0;
    collapseBtn.querySelector(".material-symbols-outlined").textContent = expanded
      ? "unfold_less"
      : "unfold_more";
    collapseBtn.title = expanded ? "Свернуть все группы" : "Развернуть все группы";

    const open = state.events.filter((e) => e.status !== "closed");
    const crit = open.some((e) => e.priority === "critical");
    $("groupsList").innerHTML = `
      <li class="tree-node tree-all ${state.groupId === "all" ? "active" : ""}" data-id="all" data-type="group">
        <div class="node-content">
          <span class="toggle-icon material-symbols-outlined"></span>
          <span class="material-symbols-outlined">folder_open</span>
          <span class="node-text">Все события</span>
          <span class="tree-ev ${crit ? "crit" : ""}">${open.length}</span>
        </div>
      </li>
      ${renderTreeHtml(TREE, 0)}
    `;
    const q = state.groupQuery.trim();
    const visible = [...$("groupsList").querySelectorAll(".tree-node")].filter(
      (n) => n.dataset.id !== "all" && !n.classList.contains("hidden")
    );
    $("groupsEmpty").hidden = !q || visible.length > 0;
  }

  function renderEvents() {
    const list = visibleEvents();
    $("eventsCount").textContent = String(list.length);
    $("groupProcessBtn").disabled = state.checked.size < 2 || state.onBreak;
    $("eventsList").innerHTML = list
      .map((e) => {
        const st = statusLabel(e);
        const kind = actionKind(e);
        const act = ACTIONS[kind];
        const prog = stepProgress(e);
        const blocked = state.onBreak && (kind === "take" || kind === "resume");
        return `
          <article class="event ${state.selectedId === e.id ? "selected" : ""}" data-id="${e.id}">
            <input class="pick" type="checkbox" data-check="${e.id}" aria-label="Выбрать ${e.id}" ${
              state.checked.has(e.id) ? "checked" : ""
            } />
            <div class="event-pri ${e.priority}"></div>
            <div class="event-main">
              <div class="event-title">
                <strong>${escapeHtml(e.type)}</strong>
                <time>${e.time}</time>
              </div>
              <div class="event-sub">${e.id} · ${escapeHtml(e.object)} · ${escapeHtml(e.location)}</div>
              <div class="event-foot">
                <span class="badge ${st.cls}">${escapeHtml(st.text)}</span>
                ${
                  e.status === "closed"
                    ? ""
                    : `<span class="event-sla ${e.slaSec < 120 ? "late" : ""}" data-sla="${e.id}">SLA ${fmtSla(
                        e.slaSec
                      )}</span>`
                }
                ${prog.filled ? `<span class="event-prog">Сценарий ${prog.filled}/${prog.total}</span>` : ""}
              </div>
            </div>
            <button type="button" class="btn ${act.style} event-act" data-act="${e.id}" title="${act.hint}" ${
              blocked ? "disabled" : ""
            }>${act.label}</button>
          </article>
        `;
      })
      .join("") || `<div class="empty">Нет событий в текущем фильтре</div>`;
  }

  function renderWorkHeader(ev) {
    $("workTitle").textContent = ev ? `${ev.id} · ${ev.type}` : "Обработка";
  }

  function workNote(ev) {
    if (ev.status === "foreign" || ev.status === "escalated") {
      return `<div class="work-note">Инцидент обрабатывает ${escapeHtml(
        ev.operator
      )}. Просмотр без изменений — при необходимости перехватите.</div>`;
    }
    if (ev.status === "closed") {
      return `<div class="work-note ok">Инцидент закрыт. Карточка доступна только для просмотра.</div>`;
    }
    if (ev.status === "mine" && state.onBreak) {
      return `<div class="work-note">Вы на перерыве — изменения по сценарию недоступны.</div>`;
    }
    return "";
  }

  function renderScenario() {
    const ev = selected();
    const root = $("scenarioRoot");
    if (!ev) {
      root.innerHTML = `<div class="empty">Инцидент не выбран</div>`;
      return;
    }
    const steps = scenarioSteps(ev);
    const prog = stepProgress(ev);
    const mine = ev.status === "mine";
    const foreign = ev.status === "foreign" || ev.status === "escalated";
    const editable = mine && !state.onBreak;

    ensureCursor(ev);
    const i = ev.stepIndex;
    const step = steps[i];
    const last = i === steps.length - 1;
    const canNext = isStepValid(ev, step);
    const canClose = scenarioDone(ev) && editable;
    const incomplete = steps.findIndex((s) => s.required && !isStepValid(ev, s));

    root.innerHTML = `
      <div class="work-doc">
        ${renderIncidentHead(ev, prog)}
        ${workNote(ev)}
        <nav class="crumbs" aria-label="Шаги сценария">
          ${steps
            .map((s, idx) => {
              const open = canOpenStep(ev, idx);
              const current = idx === i;
              const answer = stepAnswerText(ev, s);
              return `
                <button type="button" class="crumb ${current ? "current" : ""} ${answer ? "done" : ""} ${
                  open ? "" : "locked"
                }" data-crumb="${idx}" ${open ? "" : "disabled"} title="${escapeHtml(s.label)}">
                  <span class="crumb-n">${idx + 1}</span>
                  <span class="crumb-body">
                    <span class="crumb-name">${escapeHtml(stepShort(s))}</span>
                    ${answer && !current ? `<span class="crumb-ans">${escapeHtml(answer)}</span>` : ""}
                  </span>
                </button>
              `;
            })
            .join("")}
        </nav>
        <div class="step-card">
          <div class="step-h">
            <strong>${escapeHtml(step.label)}</strong>
            <span>${i + 1} из ${steps.length}${step.required ? "" : " · необязательно"}</span>
          </div>
          ${renderStepControl(step, ev, editable)}
        </div>
        <div class="scenario-actions">
          <button type="button" class="btn ghost" id="stepBack" ${i === 0 ? "disabled" : ""}>Назад</button>
          <div class="scenario-actions-end">
            ${mine ? `<button type="button" class="btn ghost" id="escalateBtn">Эскалация</button>` : ""}
            ${
              foreign
                ? `<button type="button" class="btn danger" id="takeoverBtn" ${
                    state.onBreak ? "disabled" : ""
                  }>Перехватить</button>`
                : ""
            }
            ${
              editable
                ? last && canClose
                  ? `<button type="button" class="btn primary" id="closeBtn">Закрыть инцидент</button>`
                  : `<button type="button" class="btn primary" id="stepNext" ${canNext ? "" : "disabled"}>${
                      last ? "К незаполненным" : "Далее"
                    }</button>`
                : !last && canOpenStep(ev, i + 1)
                  ? `<button type="button" class="btn outline" id="stepNext">Далее</button>`
                  : ""
            }
          </div>
        </div>
        ${
          last && editable && !canClose && incomplete !== -1
            ? `<p class="step-hint">Сначала шаг ${incomplete + 1}: ${escapeHtml(stepShort(steps[incomplete]))}</p>`
            : ""
        }
        ${renderLog(ev)}
      </div>
    `;
  }

  function renderLog(ev) {
    const items = ev.log.slice(-4);
    if (!items.length) return "";
    return `
      <div class="log">
        <h4>Журнал</h4>
        <ul>
          ${items
            .map((l) => `<li><b>${escapeHtml(l.t)}</b> · ${escapeHtml(l.who)} — ${escapeHtml(l.text)}</li>`)
            .join("")}
        </ul>
      </div>
    `;
  }

  function renderIncidentHead(ev, prog) {
    return `
      <div class="incident-head">
        <div class="incident-kicker">
          <span>${ev.id}</span>
          <span class="sla ${ev.slaSec < 120 ? "late" : ""}">SLA ${fmtSla(ev.slaSec)}</span>
        </div>
        <h3>${escapeHtml(ev.type)}</h3>
        <div class="incident-meta">${escapeHtml(ev.object)} · ${escapeHtml(ev.location)}</div>
        <div class="progress"><i style="width:${Math.round((prog.filled / prog.total) * 100)}%"></i></div>
      </div>
    `;
  }

  function renderStepControl(step, ev, enabled) {
    const dis = enabled ? "" : "disabled";
    if (step.type === "checkbox") {
      const on = ev.answers[step.id] === true;
      return `
        <button type="button" class="confirm-btn ${on ? "on" : ""}" data-confirm="${step.id}" ${dis}>
          <span class="material-symbols-outlined">${on ? "check_circle" : "radio_button_unchecked"}</span>
          ${on ? "Подтверждено" : "Подтвердить"}
        </button>
      `;
    }
    if (step.type === "radio") {
      return `<div class="radios">${step.options
        .map(
          (o) =>
            `<label class="${ev.answers[step.id] === o ? "picked" : ""}"><input type="radio" name="${
              step.id
            }" data-ans="${step.id}" value="${escapeHtml(o)}" ${
              ev.answers[step.id] === o ? "checked" : ""
            } ${dis} /> ${escapeHtml(o)}</label>`
        )
        .join("")}</div>`;
    }
    if (step.type === "combo") {
      return `<select data-ans="${step.id}" ${dis}><option value="">Выберите…</option>${step.options
        .map((o) => `<option ${ev.answers[step.id] === o ? "selected" : ""}>${escapeHtml(o)}</option>`)
        .join("")}</select>`;
    }
    if (step.type === "edit") {
      return `<textarea rows="4" data-ans="${step.id}" placeholder="${escapeHtml(
        step.placeholder || "Можно пропустить"
      )}" ${dis}>${escapeHtml(ev.answers[step.id] || "")}</textarea>`;
    }
    if (step.type === "macros") {
      return `<div class="macro-row">${step.buttons
        .map((b) => {
          const on = ev.launched.includes(b);
          return `<button type="button" class="btn ${on ? "ok" : ""}" data-macro="${escapeHtml(b)}" ${dis}>${
            on ? "Запущено · " : ""
          }${escapeHtml(b)}</button>`;
        })
        .join("")}</div>`;
    }
    return "";
  }

  function applyMediaLayout(ev) {
    $("panelMedia").dataset.media = ev && ev.media ? ev.media : "both";
  }

  function renderVideo() {
    const ev = selected();
    const cams = ev && ev.cameras ? ev.cameras : [];
    if (!cams.length) {
      $("videoStage").innerHTML = `<div class="empty">К инциденту не привязаны камеры</div>`;
      $("camStrip").hidden = true;
      $("timeline").hidden = true;
      return;
    }
    if (!cams.includes(state.activeCam)) state.activeCam = cams[0];
    const idx = cams.indexOf(state.activeCam);
    const cam = CAMERAS[state.activeCam] || cameraOf(state.activeCam, 200, 120);
    const live = state.videoMode === "live";
    const many = cams.length > 1;

    $("videoStage").innerHTML = `
      <div class="cam active" data-cam="${state.activeCam}">
        <div class="scene scene-${cam.scene}">
          <div class="glow"></div><div class="figure"></div><div class="path"></div>
          <div class="slot"></div><div class="bar"></div>
        </div>
        <div class="cam-hud">
          <div>
            <div class="mode-tag ${state.videoMode}">${live ? "LIVE" : "АРХИВ"}</div>
            <b>${escapeHtml(cam.name)}</b>
          </div>
          <span>${live ? nowStamp() : ev.time}</span>
        </div>
      </div>
      ${
        many
          ? `
        <button type="button" class="cam-nav prev" data-cam-step="-1" title="Предыдущая камера (←)" aria-label="Предыдущая камера">
          <span class="material-symbols-outlined">chevron_left</span>
        </button>
        <button type="button" class="cam-nav next" data-cam-step="1" title="Следующая камера (→)" aria-label="Следующая камера">
          <span class="material-symbols-outlined">chevron_right</span>
        </button>`
          : ""
      }
    `;

    $("camStrip").hidden = !many;
    if (many) {
      $("camStrip").innerHTML = `
        <div class="cam-ticks">
          ${cams
            .map((id, i) => {
              const c = CAMERAS[id] || cameraOf(id, 200, 120);
              return `<button type="button" class="cam-tick ${
                i === idx ? "active" : ""
              }" data-cam="${id}" title="${escapeHtml(c.name)}" aria-label="${escapeHtml(c.name)}"></button>`;
            })
            .join("")}
        </div>
        <span class="cam-counter">${idx + 1} / ${cams.length}</span>
      `;
    }

    $("timeline").hidden = false;
    $("tlTime").textContent = live ? nowStamp() : ev.time;
    $("timeline").style.opacity = live ? "0.35" : "1";
  }

  function stepCamera(delta) {
    const ev = selected();
    const cams = ev && ev.cameras ? ev.cameras : [];
    if (cams.length < 2) return;
    const i = cams.indexOf(state.activeCam);
    state.activeCam = cams[(Math.max(0, i) + delta + cams.length) % cams.length];
    renderVideo();
    renderMap();
  }

  function renderMap() {
    const ev = selected();
    $("mapCaption").textContent = ev ? `${ev.object} · ${ev.location}` : "Место сработки";
    const cams = ev ? ev.cameras : [];
    const pin = ev ? ev.pin : { x: 210, y: 118 };
    $("mapRoot").innerHTML = `
      <svg class="map-svg" viewBox="0 0 400 260" role="img" aria-label="План места инцидента">
        <rect x="24" y="24" width="352" height="212" fill="var(--map-floor)" stroke="var(--stroke-2)"/>
        <rect x="40" y="40" width="90" height="70" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="140" y="40" width="140" height="90" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="290" y="40" width="70" height="70" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="40" y="150" width="200" height="70" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="250" y="150" width="110" height="70" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <text x="50" y="58" fill="var(--map-label)" font-size="10">вход</text>
        <text x="150" y="58" fill="var(--map-label)" font-size="10">атриум / зона события</text>
        <text x="50" y="166" fill="var(--map-label)" font-size="10">паркинг / двор</text>
        <circle class="map-pin" cx="${pin.x}" cy="${pin.y}" r="7">
          <animate attributeName="r" values="6;9;6" dur="1.6s" repeatCount="indefinite"/>
        </circle>
        ${cams
          .map((id) => {
            const c = CAMERAS[id] || cameraOf(id, 200, 120);
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
      state.mode === "work"
        ? `Обработка ${ev.id}`
        : ev.status === "mine"
          ? `${ev.id} · ${ev.paused ? "приостановлен" : "в работе"}`
          : ev.status === "foreign"
            ? `${ev.id} у оператора ${ev.operator}`
            : `${ev.id} · ${statusLabel(ev).text}`;
    $("statusSteps").textContent =
      state.mode === "work" && typeof ev.stepIndex === "number"
        ? `Шаг ${ev.stepIndex + 1} из ${prog.total}`
        : `Сценарий ${prog.filled}/${prog.total}`;
    $("statusSla").textContent = ev.status === "closed" ? "" : `Осталось SLA ${fmtSla(ev.slaSec)}`;
  }

  function fmtSla(sec) {
    const m = Math.floor(Math.max(0, sec) / 60);
    const s = Math.max(0, sec) % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function renderAll() {
    const ws = $("workspace");
    ws.dataset.mode = state.mode;
    ws.dataset.groups = state.groupsOn ? "on" : "off";
    $("toggleGroups").classList.toggle("on", state.groupsOn);
    renderGroups();
    if (state.mode === "queue") {
      renderEvents();
    } else {
      renderWorkHeader(selected());
      renderScenario();
    }
    applyMediaLayout(selected());
    renderVideo();
    renderMap();
    renderStatus();
    $("dutyBadge").textContent = state.onBreak ? "Перерыв" : "На смене";
    $("dutyBadge").classList.toggle("off", state.onBreak);
    $("breakBanner").hidden = !state.onBreak;
    $("breakBtn").textContent = state.onBreak ? "На смену" : "Перерыв";
  }

  function focusCameras(ev) {
    if (ev && ev.cameras && ev.cameras.length && !ev.cameras.includes(state.activeCam)) {
      state.activeCam = ev.cameras[0];
    }
  }

  function openWork(ev) {
    if (!ev) return;
    const kind = actionKind(ev);
    if ((kind === "take" || kind === "resume") && state.onBreak) {
      toast("На перерыве события не назначаются");
      return;
    }
    state.selectedId = ev.id;
    focusCameras(ev);
    if (kind === "take") {
      ev.status = "mine";
      ev.operator = ME;
      ev.paused = false;
      ev.stepIndex = firstOpenStep(ev);
      ev.log.push({ t: nowStamp(), who: ME, text: "Взято в работу" });
      toast(`${ev.id} в работе`);
    } else if (kind === "resume") {
      ev.paused = false;
      ensureCursor(ev);
      ev.log.push({ t: nowStamp(), who: ME, text: `Обработка возобновлена на шаге ${ev.stepIndex + 1}` });
    }
    state.mode = "work";
    renderAll();
  }

  function backToQueue() {
    const ev = selected();
    if (ev && ev.status === "mine" && !ev.paused) {
      ev.paused = true;
      ensureCursor(ev);
      ev.log.push({ t: nowStamp(), who: ME, text: `Обработка приостановлена на шаге ${ev.stepIndex + 1}` });
      toast(`${ev.id} приостановлен — возобновите из очереди`);
    }
    state.mode = "queue";
    renderAll();
  }

  function takeover(ev) {
    if (state.onBreak) {
      toast("На перерыве события не назначаются");
      return;
    }
    const prev = ev.operator;
    const prog = stepProgress(ev);
    ev.status = "mine";
    ev.operator = ME;
    ev.paused = false;
    ensureCursor(ev);
    ev.log.push({
      t: nowStamp(),
      who: ME,
      text: `Перехват у ${prev}. Прогресс сценария сохранён (${prog.filled}/${prog.total})`,
    });
    toast(`Перехвачен ${ev.id}`);
    state.mode = "work";
    renderAll();
  }

  function closeEvent(ev) {
    if (!scenarioDone(ev)) {
      toast("Сначала заполните обязательные шаги сценария");
      return;
    }
    ev.status = "closed";
    ev.paused = false;
    ev.log.push({ t: nowStamp(), who: ME, text: "Инцидент закрыт. Результат уйдёт в AxxonData" });
    toast(`${ev.id} закрыт`);
    const next = state.events.find((e) => e.status === "new");
    if (next) {
      state.selectedId = next.id;
      focusCameras(next);
    }
    state.checked.delete(ev.id);
    state.mode = "queue";
    renderAll();
  }

  function bind() {
    $("themeMode").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-theme]");
      if (!btn) return;
      applyTheme(btn.dataset.theme);
    });
    $("toggleGroups").addEventListener("click", () => {
      state.groupsOn = !state.groupsOn;
      $("workspace").dataset.groups = state.groupsOn ? "on" : "off";
      $("toggleGroups").classList.toggle("on", state.groupsOn);
    });
    $("backToQueue").addEventListener("click", () => backToQueue());
    $("eventFilter").addEventListener("change", (e) => {
      state.filter = e.target.value;
      renderEvents();
    });
    $("eventSearch").addEventListener("input", (e) => {
      state.search = e.target.value;
      renderEvents();
    });
    $("groupSearch").addEventListener("input", (e) => {
      state.groupQuery = e.target.value;
      renderGroups();
    });
    $("groupsList").addEventListener("click", (e) => {
      const toggle = e.target.closest(".toggle-icon");
      const node = e.target.closest(".tree-node");
      if (!node) return;
      const id = node.dataset.id;
      if (toggle && node.classList.contains("has-children")) {
        e.stopPropagation();
        if (state.openGroups.has(id)) state.openGroups.delete(id);
        else state.openGroups.add(id);
        renderGroups();
        return;
      }
      if (!e.target.closest(".node-content")) return;
      state.groupId = id;
      const list = visibleEvents();
      if (list.length && !list.some((ev) => ev.id === state.selectedId)) {
        state.selectedId = list[0].id;
        if (list[0].cameras && list[0].cameras[0]) state.activeCam = list[0].cameras[0];
      }
      renderAll();
    });
    $("eventsList").addEventListener("click", (e) => {
      const check = e.target.closest("[data-check]");
      if (check) {
        const id = check.dataset.check;
        if (state.checked.has(id)) state.checked.delete(id);
        else state.checked.add(id);
        renderEvents();
        return;
      }
      const act = e.target.closest("[data-act]");
      if (act) {
        openWork(state.events.find((x) => x.id === act.dataset.act));
        return;
      }
      const row = e.target.closest("[data-id]");
      if (!row || row.dataset.id === state.selectedId) return;
      state.selectedId = row.dataset.id;
      focusCameras(selected());
      renderEvents();
      applyMediaLayout(selected());
      renderVideo();
      renderMap();
      renderStatus();
    });
    $("scenarioRoot").addEventListener("change", (e) => {
      const ev = selected();
      if (!ev || ev.status !== "mine") return;
      const el = e.target.closest("[data-ans]");
      if (!el) return;
      ev.answers[el.dataset.ans] = el.type === "checkbox" ? el.checked : el.value;
      if (!canOpenStep(ev, ev.stepIndex)) ev.stepIndex = firstOpenStep(ev);
      renderScenario();
      renderStatus();
    });
    $("scenarioRoot").addEventListener("click", (e) => {
      const ev = selected();
      if (!ev) return;
      const crumb = e.target.closest("[data-crumb]");
      if (crumb && !crumb.disabled) {
        goToStep(ev, Number(crumb.dataset.crumb));
        return;
      }
      if (e.target.closest("#stepBack")) {
        goToStep(ev, ev.stepIndex - 1);
        return;
      }
      if (e.target.closest("#stepNext")) {
        const steps = scenarioSteps(ev);
        if (ev.stepIndex < steps.length - 1 && canOpenStep(ev, ev.stepIndex + 1)) {
          goToStep(ev, ev.stepIndex + 1);
        } else {
          goToStep(ev, firstOpenStep(ev));
        }
        return;
      }
      const confirm = e.target.closest("[data-confirm]");
      if (confirm && ev.status === "mine" && !state.onBreak) {
        const id = confirm.dataset.confirm;
        ev.answers[id] = ev.answers[id] !== true;
        if (!canOpenStep(ev, ev.stepIndex)) ev.stepIndex = firstOpenStep(ev);
        renderScenario();
        renderStatus();
        return;
      }
      if (e.target.closest("#takeoverBtn")) return takeover(ev);
      if (e.target.closest("#closeBtn")) return closeEvent(ev);
      if (e.target.closest("#escalateBtn")) {
        $("modalEscalate").hidden = false;
        return;
      }
      const macro = e.target.closest("[data-macro]");
      if (macro && ev.status === "mine" && !state.onBreak) {
        const name = macro.dataset.macro;
        if (!ev.launched.includes(name)) ev.launched.push(name);
        toast(`Макрос: ${name}`);
        renderScenario();
      }
    });
    $("groupProcessBtn").addEventListener("click", () => groupProcess());
    $("videoStage").addEventListener("click", (e) => {
      const nav = e.target.closest("[data-cam-step]");
      if (nav) stepCamera(Number(nav.dataset.camStep));
    });
    $("camStrip").addEventListener("click", (e) => {
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
      ev.paused = false;
      $("modalEscalate").hidden = true;
      $("escalateReason").value = "";
      toast(`Эскалация ${ev.id} → ${ev.operator}`);
      state.mode = "queue";
      renderAll();
    });
    $("groupsCollapseAll").addEventListener("click", () => {
      if (state.openGroups.size) state.openGroups.clear();
      else TREE.forEach((n) => state.openGroups.add(n.id));
      renderGroups();
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
      ev.paused = false;
      ev.answers = { ...first.answers };
      ev.log.push({
        t: nowStamp(),
        who: ME,
        text: `Групповая обработка вместе с ${ids.filter((x) => x !== id).join(", ")}`,
      });
    });
    state.selectedId = first.id;
    focusCameras(first);
    toast(`Группа из ${ids.length} событий в одной карточке`);
    state.mode = "work";
    renderAll();
  }

  function onKey(e) {
    if (e.target.matches("input, textarea, select")) return;
    if (e.key === "ArrowLeft") return stepCamera(-1);
    if (e.key === "ArrowRight") return stepCamera(1);
    if (e.key === "Escape") {
      const openModal = document.querySelector(".modal:not([hidden])");
      if (openModal) {
        openModal.hidden = true;
        return;
      }
      if (state.mode === "work") backToQueue();
      return;
    }
    const key = e.key.toLowerCase();
    if (key === "?" || (e.shiftKey && e.key === "/")) {
      $("modalHotkeys").hidden = !$("modalHotkeys").hidden;
    }
    if (key === "b") $("breakBtn").click();
    if (key === "e") {
      const ev = selected();
      if (ev && ev.status === "mine" && state.mode === "work") $("modalEscalate").hidden = false;
    }
    if (key === "n") {
      const next = state.events.find((x) => x.status === "new");
      if (next) openWork(next);
    }
    if (key === "t") {
      const ev = selected();
      if (ev && (ev.status === "foreign" || ev.status === "escalated")) takeover(ev);
    }
    if (key === "g") groupProcess();
    if (e.key === "Enter") {
      const ev = selected();
      if (ev && ev.status === "mine" && state.mode === "work") closeEvent(ev);
    }
    if (["1", "2", "3", "4"].includes(e.key)) {
      const ev = selected();
      const cam = ev && ev.cameras && ev.cameras[Number(e.key) - 1];
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
    document.querySelectorAll("[data-sla]").forEach((el) => {
      const e = state.events.find((x) => x.id === el.dataset.sla);
      if (!e) return;
      el.textContent = `SLA ${fmtSla(e.slaSec)}`;
      el.classList.toggle("late", e.slaSec < 120);
    });
    const ev = selected();
    if (ev && ev.status !== "closed") {
      const sla = $("scenarioRoot").querySelector(".sla");
      if (sla) {
        sla.textContent = `SLA ${fmtSla(ev.slaSec)}`;
        sla.classList.toggle("late", ev.slaSec < 120);
      }
      $("statusSla").textContent = `Осталось SLA ${fmtSla(ev.slaSec)}`;
    }
  }, 1000);

  let savedTheme = "dark";
  try {
    savedTheme = localStorage.getItem("im-theme") || "dark";
  } catch (err) {
    savedTheme = "dark";
  }
  applyTheme(savedTheme);
  bind();
  renderAll();
})();
