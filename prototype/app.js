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
    ppe: {
      title: "Отсутствие СИЗ",
      steps: [
        { id: "visual", type: "checkbox", label: "Отсутствие каски подтверждено по видео", required: true },
        {
          id: "verdict",
          type: "radio",
          label: "Классификация",
          required: true,
          options: ["Реальное нарушение", "Ошибка детектора", "Сотрудник вне рабочей зоны"],
        },
        {
          id: "who",
          type: "combo",
          label: "Кто нарушитель",
          options: ["Сотрудник склада", "Водитель поставщика", "Подрядчик", "Не идентифицирован"],
        },
        {
          id: "note",
          type: "edit",
          label: "Комментарий / кому передано",
          placeholder: "Табельный номер, бригадир, номер акта",
        },
        {
          id: "macros",
          type: "macros",
          label: "Макросы зоны",
          buttons: ["Голосовое оповещение в зону", "Уведомить инженера по охране труда"],
        },
      ],
    },
    alcohol: {
      title: "Превышение уровня алкоголя",
      steps: [
        { id: "visual", type: "checkbox", label: "Личность на точке прохода подтверждена по видео", required: true },
        {
          id: "verdict",
          type: "radio",
          label: "Результат проверки",
          required: true,
          options: ["Превышение подтверждено", "Повторный тест в норме", "Сбой алкорамки"],
        },
        {
          id: "level",
          type: "combo",
          label: "Показание прибора",
          options: ["0,3–0,5 ‰", "0,5–1,0 ‰", "Более 1,0 ‰", "Показание не считано"],
        },
        { id: "note", type: "edit", label: "Комментарий", placeholder: "ФИО, смена, кому передан сотрудник" },
        {
          id: "macros",
          type: "macros",
          label: "Макросы точки прохода",
          buttons: ["Заблокировать турникет", "Вызвать медпункт"],
        },
      ],
    },
    glass: {
      title: "Звук разбития стекла",
      steps: [
        { id: "audio", type: "checkbox", label: "Звуковое событие прослушано оператором", required: true },
        { id: "visual", type: "checkbox", label: "Повреждение видно на камерах зоны" },
        {
          id: "verdict",
          type: "radio",
          label: "Классификация",
          required: true,
          options: ["Разбитие витрины или стекла", "Бытовой шум: посуда, погрузка", "Ложная сработка детектора"],
        },
        { id: "note", type: "edit", label: "Комментарий", placeholder: "Что повреждено, вызвана ли охрана" },
        {
          id: "macros",
          type: "macros",
          label: "Макросы зоны",
          buttons: ["Включить сирену зоны", "Направить охрану к витрине"],
        },
      ],
    },
  };

  const DEVICE_TYPES = {
    camera: { icon: "videocam", label: "Камера видеонаблюдения" },
    "fire-detector": { icon: "local_fire_department", label: "Пожарный извещатель" },
    "panic-button": { icon: "crisis_alert", label: "Тревожная кнопка" },
    "ppe-detector": { icon: "engineering", label: "Детектор СИЗ" },
    "access-point": { icon: "sensor_door", label: "Виртуальная точка прохода" },
    microphone: { icon: "mic", label: "Микрофон" },
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
    "device-34": { name: "КПП — проходная", type: "camera" },
    "device-35": { name: "КПП — шлагбаум и въезд", type: "camera" },
    "fire-1": { name: "Датчик дыма 1", type: "fire-detector" },
    "fire-2": { name: "Датчик дыма 2", type: "fire-detector" },
    "fire-3": { name: "Датчик дыма 3", type: "fire-detector" },
    "fire-4": { name: "Датчик дыма 4", type: "fire-detector" },
    "fire-5": { name: "Датчик дыма 5", type: "fire-detector" },
    "fire-6": { name: "Датчик дыма — зона ожидания", type: "fire-detector" },
    "panic-1": { name: "Тревожная кнопка — пост охраны", type: "panic-button" },
    "panic-2": { name: "Тревожная кнопка — ресепшн", type: "panic-button" },
    "ppe-1": { name: "Детектор СИЗ — разгрузочная рампа", type: "ppe-detector" },
    "ppe-2": { name: "Детектор СИЗ — вход в цех", type: "ppe-detector" },
    "gate-1": { name: "Точка прохода — КПП склада", type: "access-point" },
    "gate-2": { name: "Точка прохода — турникет офиса", type: "access-point" },
    "mic-1": { name: "Микрофон — витрина у входа", type: "microphone" },
    "mic-2": { name: "Микрофон — торговый зал", type: "microphone" },
  };

  const DEVICES_IN_REPAIR = ["device-9", "device-19", "device-25", "fire-3", "ppe-2"];

  const PAGE_SIZE = 8;

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
              devices: ["device-1", "device-2", "fire-1", "gate-2"],
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
            {
              id: "group-11",
              name: "Склад №2",
              devices: ["device-11", "device-12", "device-8", "ppe-1", "ppe-2"],
            },
          ],
        },
        {
          id: "group-12",
          name: "Этаж Б",
          children: [{ id: "group-13", name: "Склад №3", devices: ["device-13", "device-14"] }],
        },
        {
          id: "group-30",
          name: "КПП и проходная",
          devices: ["device-34", "device-35", "gate-1"],
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
            { id: "group-23", name: "Магазин 1", devices: ["device-23", "device-24", "fire-5", "mic-2"] },
            { id: "group-24", name: "Магазин 2", devices: ["device-25", "device-26", "mic-1"] },
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
    {
      id: "group-detectors",
      name: "Детекторы и микрофоны",
      description: "Сквозная подборка аналитических детекторов, точек прохода и микрофонов.",
      children: [
        {
          id: "group-ppe",
          name: "Детекторы СИЗ",
          description: "Контроль средств индивидуальной защиты в производственных зонах.",
          devices: devicesOfType("ppe-detector"),
        },
        {
          id: "group-access",
          name: "Виртуальные точки прохода",
          description: "Турникеты, КПП и алкорамки, объединённые в виртуальные точки прохода.",
          devices: devicesOfType("access-point"),
        },
        {
          id: "group-mics",
          name: "Микрофоны",
          description: "Аудиодетекция: разбитие стекла, крик, выстрел.",
          devices: devicesOfType("microphone"),
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

  // Кадры видеомонитора: инлайновые SVG-сцены, viewBox 320x180, растягиваются по кадру.
  const SCENES = {
    hall: `
      <rect width="320" height="180" fill="#20283a"/>
      <rect width="320" height="94" fill="#2a3448"/>
      <polygon points="0,180 320,180 246,94 74,94" fill="#3d465c"/>
      <polygon points="74,94 246,94 240,105 80,105" fill="#2b3446"/>
      <rect x="128" y="38" width="64" height="56" fill="#8fa3c6" opacity=".4"/>
      <rect x="136" y="46" width="48" height="48" fill="#cddcf5" opacity=".28"/>
      <polygon points="0,100 66,96 66,152 0,172" fill="#4a556f"/>
      <polygon points="320,100 254,96 254,152 320,172" fill="#4a556f"/>
      <g fill="#93a6c9">
        <rect x="4" y="106" width="58" height="7"/><rect x="4" y="122" width="58" height="7"/>
        <rect x="4" y="138" width="58" height="7"/><rect x="258" y="106" width="58" height="7"/>
        <rect x="258" y="122" width="58" height="7"/><rect x="258" y="138" width="58" height="7"/>
      </g>
      <g fill="#eef4ff" opacity=".5">
        <rect x="92" y="16" width="136" height="5" rx="2.5"/><rect x="106" y="4" width="108" height="4" rx="2"/>
      </g>
      <g fill="#131a28" opacity=".85">
        <ellipse cx="142" cy="150" rx="11" ry="4"/>
        <path d="M135 150c0-17 3.5-28 7-28s7 11 7 28z"/><circle cx="142" cy="116" r="6.5"/>
        <ellipse cx="198" cy="167" rx="12" ry="4.5"/>
        <path d="M190 167c0-19 4-31 8-31s8 12 8 31z"/><circle cx="198" cy="129" r="7.5"/>
      </g>
    `,
    checkout: `
      <rect width="320" height="180" fill="#222a3c"/>
      <rect width="320" height="80" fill="#2d374c"/>
      <polygon points="0,180 320,180 260,80 60,80" fill="#3f4960"/>
      <g fill="#eef4ff" opacity=".45">
        <rect x="70" y="10" width="180" height="5" rx="2.5"/><rect x="96" y="26" width="128" height="4" rx="2"/>
      </g>
      <polygon points="24,112 150,104 150,140 24,156" fill="#5b6580"/>
      <polygon points="24,112 150,104 150,112 24,120" fill="#7d89a5"/>
      <polygon points="176,104 300,112 300,156 176,140" fill="#5b6580"/>
      <polygon points="176,104 300,112 300,120 176,112" fill="#7d89a5"/>
      <g fill="#1a2130"><rect x="60" y="86" width="16" height="20" rx="2"/><rect x="238" y="88" width="16" height="20" rx="2"/></g>
      <g fill="#8ff0c0" opacity=".8"><rect x="63" y="90" width="10" height="7"/><rect x="241" y="92" width="10" height="7"/></g>
      <g fill="#131a28" opacity=".85">
        <path d="M154 150c0-19 4-31 8-31s8 12 8 31z"/><circle cx="162" cy="112" r="7"/>
        <path d="M186 158c0-20 4-33 8-33s8 13 8 33z"/><circle cx="194" cy="118" r="7.5"/>
      </g>
      <g fill="#d9a13a" opacity=".55"><rect x="150" y="150" width="26" height="30"/></g>
    `,
    storefront: `
      <rect width="320" height="180" fill="#1c2434"/>
      <rect width="320" height="22" fill="#141b28"/>
      <rect x="96" y="7" width="128" height="5" rx="2.5" fill="#eef4ff" opacity=".5"/>
      <rect x="20" y="22" width="280" height="76" fill="#0b111d"/>
      <rect x="20" y="86" width="280" height="12" fill="#1b2432"/>
      <g fill="#233045"><rect x="30" y="32" width="52" height="54"/><rect x="240" y="28" width="54" height="58"/></g>
      <g fill="#f7d9a0" opacity=".65">
        <rect x="36" y="38" width="10" height="10"/><rect x="52" y="38" width="10" height="10"/>
        <rect x="36" y="56" width="10" height="10"/><rect x="248" y="36" width="12" height="12"/>
        <rect x="272" y="56" width="12" height="12"/>
      </g>
      <g><rect x="150" y="34" width="4" height="52" fill="#4b5566"/><circle cx="152" cy="31" r="5.5" fill="#f7d9a0"/></g>
      <polygon points="146,34 158,34 172,86 132,86" fill="#f7d9a0" opacity=".12"/>
      <g fill="#3a465e"><rect x="186" y="66" width="74" height="20" rx="5"/><rect x="202" y="54" width="44" height="15" rx="4"/></g>
      <g fill="#0e131c"><circle cx="204" cy="86" r="6"/><circle cx="244" cy="86" r="6"/></g>
      <g fill="#c9d8ee" opacity=".07"><rect x="23" y="26" width="86" height="70"/><rect x="117" y="26" width="86" height="70"/><rect x="211" y="26" width="86" height="70"/></g>
      <g fill="#8fa3c6">
        <rect x="16" y="18" width="288" height="6"/><rect x="16" y="96" width="288" height="8"/>
        <rect x="16" y="18" width="7" height="86"/><rect x="110" y="18" width="7" height="86"/>
        <rect x="204" y="18" width="7" height="86"/><rect x="297" y="18" width="7" height="86"/>
      </g>
      <polygon points="0,180 320,180 304,104 16,104" fill="#39435a"/>
      <polygon points="16,104 304,104 300,114 20,114" fill="#2d364a"/>
      <g stroke="#4a556f" stroke-width="1.5" opacity=".6">
        <line x1="80" y1="104" x2="52" y2="180"/><line x1="160" y1="104" x2="160" y2="180"/>
        <line x1="240" y1="104" x2="268" y2="180"/>
      </g>
      <g fill="#1a2333">
        <rect x="56" y="142" width="62" height="7" rx="2"/>
        <path d="M79 142c0-27 4-42 8-42s8 15 8 42z"/><circle cx="87" cy="95" r="8"/>
        <rect x="198" y="152" width="68" height="7" rx="2"/>
        <path d="M223 152c0-29 4-45 9-45s9 16 9 45z"/><circle cx="232" cy="99" r="9"/>
      </g>
    `,
    corridor: `
      <rect width="320" height="180" fill="#232b3d"/>
      <polygon points="0,0 320,0 320,180 0,180" fill="#283145"/>
      <polygon points="118,54 202,54 202,126 118,126" fill="#161d2b"/>
      <polygon points="0,0 118,54 118,126 0,180" fill="#38425a"/>
      <polygon points="320,0 202,54 202,126 320,180" fill="#333c53"/>
      <polygon points="0,180 320,180 202,126 118,126" fill="#454f68"/>
      <polygon points="0,0 320,0 202,54 118,54" fill="#1f2738"/>
      <g fill="#b04a5a" opacity=".85">
        <polygon points="202,58 250,36 250,146 202,124"/>
        <polygon points="252,35 292,17 292,164 252,147"/>
      </g>
      <g fill="#8a3a48" opacity=".9">
        <rect x="224" y="46" width="3" height="96"/><rect x="270" y="28" width="3" height="126"/>
      </g>
      <g fill="#f2f7ff" opacity=".55">
        <rect x="140" y="8" width="40" height="4" rx="2"/><rect x="132" y="26" width="56" height="4" rx="2"/>
      </g>
      <g fill="#c9d4e8" opacity=".14"><polygon points="118,126 202,126 240,180 80,180"/></g>
      <g fill="#131a28" opacity=".8">
        <ellipse cx="160" cy="128" rx="9" ry="3.5"/>
        <path d="M154 128c0-15 2.5-24 6-24s6 9 6 24z"/><circle cx="160" cy="99" r="5.5"/>
      </g>
    `,
    gate: `
      <rect width="320" height="180" fill="#1e2534"/>
      <rect width="320" height="104" fill="#28303f"/>
      <polygon points="0,180 320,180 288,104 32,104" fill="#3b4252"/>
      <rect x="84" y="18" width="152" height="86" fill="#4a5364"/>
      <g stroke="#38404f" stroke-width="3">
        <line x1="84" y1="30" x2="236" y2="30"/><line x1="84" y1="44" x2="236" y2="44"/>
        <line x1="84" y1="58" x2="236" y2="58"/><line x1="84" y1="72" x2="236" y2="72"/>
        <line x1="84" y1="86" x2="236" y2="86"/>
      </g>
      <rect x="78" y="12" width="164" height="8" fill="#5b6577"/>
      <g fill="#d9a13a" opacity=".75"><rect x="30" y="112" width="260" height="4"/><rect x="20" y="160" width="280" height="5"/></g>
      <g fill="#8c6a3a">
        <rect x="24" y="118" width="46" height="26"/><rect x="24" y="112" width="46" height="7" fill="#a98046"/>
        <rect x="252" y="122" width="50" height="30"/><rect x="252" y="115" width="50" height="8" fill="#a98046"/>
      </g>
      <g fill="#f7d9a0" opacity=".1"><ellipse cx="160" cy="112" rx="96" ry="34"/></g>
      <g fill="#eef4ff" opacity=".55"><rect x="140" y="4" width="40" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".85">
        <ellipse cx="196" cy="150" rx="12" ry="4"/>
        <path d="M188 150c0-20 4-32 8-32s8 12 8 32z"/><circle cx="196" cy="112" r="7"/>
      </g>
    `,
    dock: `
      <rect width="320" height="180" fill="#1a2130"/>
      <rect width="320" height="96" fill="#101724"/>
      <polygon points="0,180 320,180 300,96 20,96" fill="#39414f"/>
      <rect x="96" y="14" width="150" height="96" rx="4" fill="#54606f"/>
      <rect x="104" y="24" width="134" height="72" fill="#6c7887"/>
      <g stroke="#4a545f" stroke-width="3"><line x1="171" y1="24" x2="171" y2="96"/></g>
      <g fill="#3d4652"><rect x="104" y="96" width="134" height="14"/></g>
      <g fill="#d9a13a"><rect x="96" y="110" width="150" height="6"/></g>
      <g fill="#d9a13a" opacity=".7"><rect x="20" y="132" width="280" height="4"/><rect x="10" y="164" width="300" height="5"/></g>
      <g fill="#8c6a3a"><rect x="34" y="128" width="42" height="26"/><rect x="34" y="121" width="42" height="8" fill="#a98046"/></g>
      <g fill="#f7d9a0" opacity=".1"><ellipse cx="170" cy="120" rx="92" ry="30"/></g>
      <g fill="#eef4ff" opacity=".5"><rect x="52" y="6" width="34" height="5" rx="2.5"/><rect x="252" y="6" width="34" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".9">
        <ellipse cx="264" cy="152" rx="12" ry="4"/>
        <path d="M256 152c0-21 4-33 8-33s8 12 8 33z"/><circle cx="264" cy="113" r="7"/>
        <path d="M257 106h14v-4a7 7 0 0 0-14 0z" fill="#e8b93c"/>
      </g>
    `,
    racks: `
      <rect width="320" height="180" fill="#1d2432"/>
      <rect width="320" height="88" fill="#252d3c"/>
      <polygon points="0,180 320,180 236,88 84,88" fill="#3c4453"/>
      <polygon points="0,88 78,86 78,158 0,178" fill="#4d5769"/>
      <polygon points="320,88 242,86 242,158 320,178" fill="#4d5769"/>
      <g fill="#39414f">
        <rect x="0" y="98" width="78" height="6"/><rect x="0" y="118" width="78" height="6"/><rect x="0" y="138" width="78" height="6"/>
        <rect x="242" y="98" width="78" height="6"/><rect x="242" y="118" width="78" height="6"/><rect x="242" y="138" width="78" height="6"/>
      </g>
      <g fill="#a98046">
        <rect x="6" y="104" width="30" height="14"/><rect x="44" y="104" width="28" height="14"/>
        <rect x="6" y="124" width="30" height="14"/><rect x="248" y="104" width="30" height="14"/>
        <rect x="286" y="124" width="28" height="14"/><rect x="248" y="144" width="30" height="14"/>
      </g>
      <polygon points="84,88 236,88 232,96 88,96" fill="#2a3240"/>
      <rect x="140" y="52" width="40" height="36" fill="#151c28"/>
      <g fill="#f7d9a0" opacity=".1"><ellipse cx="160" cy="128" rx="80" ry="46"/></g>
      <g fill="#eef4ff" opacity=".5">
        <rect x="126" y="10" width="68" height="5" rx="2.5"/><rect x="136" y="30" width="48" height="4" rx="2"/>
      </g>
      <g fill="#d9a13a" opacity=".7">
        <polygon points="86,96 92,96 78,180 66,180"/><polygon points="234,96 228,96 242,180 254,180"/>
      </g>
    `,
    receiving: `
      <rect width="320" height="180" fill="#20283a"/>
      <rect width="320" height="92" fill="#29334a"/>
      <polygon points="0,180 320,180 276,92 44,92" fill="#3e485e"/>
      <g fill="#d9a13a" opacity=".55">
        <polygon points="88,110 232,110 246,146 74,146"/>
      </g>
      <g fill="#3e485e"><polygon points="98,116 222,116 234,140 86,140"/></g>
      <rect x="30" y="40" width="70" height="52" fill="#4b5568"/>
      <g fill="#a98046">
        <rect x="236" y="96" width="54" height="30"/><rect x="236" y="88" width="54" height="9" fill="#c29452"/>
        <rect x="244" y="128" width="54" height="30"/><rect x="244" y="120" width="54" height="9" fill="#c29452"/>
      </g>
      <g fill="#5b6580"><rect x="120" y="86" width="80" height="6"/><rect x="126" y="92" width="6" height="26"/><rect x="188" y="92" width="6" height="26"/></g>
      <g fill="#eef4ff" opacity=".5"><rect x="112" y="12" width="96" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".88">
        <ellipse cx="160" cy="142" rx="11" ry="4"/>
        <path d="M152 142c0-20 4-31 8-31s8 11 8 31z"/><circle cx="160" cy="105" r="7"/>
        <path d="M153 98h14v-4a7 7 0 0 0-14 0z" fill="#e8b93c"/>
      </g>
    `,
    checkpoint: `
      <rect width="320" height="180" fill="#222a3c"/>
      <rect width="320" height="84" fill="#2b3448"/>
      <polygon points="0,180 320,180 272,84 48,84" fill="#414b61"/>
      <rect x="18" y="16" width="104" height="68" fill="#1a2334"/>
      <rect x="26" y="24" width="88" height="52" fill="#7d93b8" opacity=".45"/>
      <rect x="198" y="16" width="104" height="68" fill="#333d52"/>
      <rect x="206" y="26" width="88" height="42" fill="#95a8c9" opacity=".35"/>
      <g fill="#5b6580">
        <rect x="96" y="96" width="10" height="58" rx="3"/><rect x="214" y="96" width="10" height="58" rx="3"/>
        <rect x="60" y="112" width="46" height="6" rx="3"/><rect x="214" y="112" width="46" height="6" rx="3"/>
        <rect x="106" y="112" width="34" height="5" rx="2.5"/><rect x="180" y="112" width="34" height="5" rx="2.5"/>
      </g>
      <g fill="#8ff0c0" opacity=".85"><circle cx="101" cy="92" r="4"/></g>
      <g fill="#f2717f" opacity=".9"><circle cx="219" cy="92" r="4"/></g>
      <g fill="#f7d9a0" opacity=".09"><ellipse cx="160" cy="110" rx="92" ry="32"/></g>
      <g fill="#eef4ff" opacity=".5"><rect x="132" y="6" width="56" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".9">
        <ellipse cx="162" cy="150" rx="12" ry="4.5"/>
        <path d="M154 150c0-21 4-33 8-33s8 12 8 33z"/><circle cx="162" cy="110" r="7.5"/>
      </g>
      <g fill="#5b6580" opacity=".8"><rect x="150" y="86" width="24" height="4" rx="2"/></g>
    `,
    barrier: `
      <rect width="320" height="180" fill="#5b7290"/>
      <rect width="320" height="72" fill="#7d9bbd"/>
      <g fill="#9fb8d4" opacity=".8"><ellipse cx="70" cy="26" rx="40" ry="12"/><ellipse cx="236" cy="18" rx="52" ry="13"/></g>
      <rect y="66" width="320" height="12" fill="#4c6076"/>
      <polygon points="0,180 320,180 296,78 24,78" fill="#3f4653"/>
      <g stroke="#e8eef8" stroke-width="4" stroke-dasharray="16 14" opacity=".8"><line x1="160" y1="78" x2="160" y2="180"/></g>
      <g fill="#2f3846"><rect x="228" y="40" width="72" height="56"/></g>
      <rect x="236" y="48" width="56" height="30" fill="#a8c0dc" opacity=".55"/>
      <rect x="228" y="34" width="80" height="8" fill="#4b5566"/>
      <g fill="#e0e6f0"><rect x="96" y="60" width="10" height="46" rx="3"/></g>
      <g><rect x="100" y="58" width="120" height="8" rx="4" fill="#e8443c"/>
         <g fill="#f4f7fb"><rect x="118" y="58" width="16" height="8"/><rect x="154" y="58" width="16" height="8"/><rect x="190" y="58" width="16" height="8"/></g>
      </g>
      <g fill="#2a3140"><rect x="176" y="96" width="96" height="42" rx="6"/><rect x="192" y="80" width="64" height="22" rx="5"/></g>
      <rect x="198" y="84" width="52" height="16" fill="#8fa8c8" opacity=".6"/>
      <g fill="#151b26"><circle cx="198" cy="140" r="10"/><circle cx="252" cy="140" r="10"/></g>
      <g fill="#f2d98a"><rect x="266" y="106" width="8" height="8" rx="2"/></g>
      <g fill="#3f4653"><rect x="0" y="72" width="320" height="4" opacity=".4"/></g>
      <g fill="#e0e6f0" opacity=".9"><rect x="40" y="52" width="4" height="54"/><rect x="30" y="44" width="24" height="10" rx="3"/></g>
    `,
    entrance: `
      <rect width="320" height="180" fill="#232b3d"/>
      <rect width="320" height="100" fill="#2b3448"/>
      <polygon points="0,180 320,180 288,100 32,100" fill="#414b61"/>
      <rect x="88" y="14" width="144" height="86" fill="#0f1725"/>
      <g fill="#a6c2e4" opacity=".45"><rect x="94" y="20" width="64" height="80"/><rect x="162" y="20" width="64" height="80"/></g>
      <g stroke="#c9d8ee" stroke-width="3" opacity=".8"><line x1="160" y1="14" x2="160" y2="100"/><line x1="88" y1="56" x2="232" y2="56"/></g>
      <g fill="#dfe8f5" opacity=".22"><polygon points="94,100 226,100 250,180 70,180"/></g>
      <g fill="#2f3a4d"><rect x="20" y="70" width="52" height="30" rx="4"/></g>
      <g fill="#4a7f5a"><ellipse cx="264" cy="86" rx="20" ry="14"/><rect x="256" y="86" width="16" height="20" fill="#6b5138"/></g>
      <g fill="#eef4ff" opacity=".5"><rect x="130" y="4" width="60" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".85">
        <ellipse cx="158" cy="146" rx="12" ry="4.5"/>
        <path d="M150 146c0-21 4-33 8-33s8 12 8 33z"/><circle cx="158" cy="106" r="7.5"/>
      </g>
      <g fill="#31394a"><rect x="104" y="150" width="112" height="18" rx="3"/></g>
    `,
    guard: `
      <rect width="320" height="180" fill="#242c3e"/>
      <rect width="320" height="112" fill="#2c3549"/>
      <polygon points="0,180 320,180 300,112 20,112" fill="#3f4859"/>
      <g fill="#39435a"><rect x="34" y="118" width="252" height="48" rx="5"/></g>
      <g fill="#4b566e"><rect x="34" y="112" width="252" height="9" rx="3"/></g>
      <g fill="#101725"><rect x="64" y="54" width="82" height="52" rx="3"/><rect x="164" y="54" width="82" height="52" rx="3"/></g>
      <g fill="#3f6f9e" opacity=".8"><rect x="69" y="59" width="72" height="42"/><rect x="169" y="59" width="72" height="42"/></g>
      <g fill="#7fa8d4" opacity=".45">
        <rect x="72" y="64" width="30" height="14"/><rect x="106" y="64" width="30" height="14"/>
        <rect x="172" y="82" width="64" height="14"/>
      </g>
      <g fill="#2b3345"><rect x="96" y="106" width="18" height="8"/><rect x="196" y="106" width="18" height="8"/></g>
      <g fill="#c0392b"><circle cx="272" cy="128" r="8"/></g>
      <g fill="#8a2a20"><circle cx="272" cy="128" r="12" opacity=".4"/></g>
      <g fill="#141a26" opacity=".8"><rect x="130" y="150" width="60" height="30" rx="6"/><rect x="146" y="140" width="28" height="14" rx="5"/></g>
      <g fill="#eef4ff" opacity=".4"><rect x="18" y="20" width="60" height="4" rx="2"/><rect x="242" y="20" width="60" height="4" rx="2"/></g>
    `,
    server: `
      <rect width="320" height="180" fill="#131a28"/>
      <polygon points="0,180 320,180 250,84 70,84" fill="#232b3c"/>
      <polygon points="0,0 70,84 70,180 0,180" fill="#1b2231"/>
      <polygon points="320,0 250,84 250,180 320,180" fill="#1b2231"/>
      <polygon points="0,0 320,0 250,84 70,84" fill="#10161f"/>
      <g fill="#2b3446"><polygon points="0,20 70,84 70,180 0,180"/></g>
      <g fill="#2b3446"><polygon points="320,20 250,84 250,180 320,180"/></g>
      <g fill="#0d131d">
        <rect x="6" y="40" width="58" height="130"/><rect x="256" y="40" width="58" height="130"/>
      </g>
      <g fill="#3ddc84" opacity=".85">
        <rect x="12" y="50" width="14" height="4"/><rect x="12" y="62" width="20" height="4"/><rect x="12" y="74" width="10" height="4"/>
        <rect x="12" y="98" width="18" height="4"/><rect x="12" y="122" width="14" height="4"/><rect x="12" y="146" width="20" height="4"/>
        <rect x="288" y="52" width="18" height="4"/><rect x="288" y="76" width="12" height="4"/>
        <rect x="288" y="104" width="20" height="4"/><rect x="288" y="140" width="14" height="4"/>
      </g>
      <g fill="#f2b23c" opacity=".8"><rect x="36" y="86" width="10" height="4"/><rect x="272" y="120" width="10" height="4"/></g>
      <g fill="#7fa8d4" opacity=".25"><polygon points="70,84 250,84 234,180 86,180"/></g>
      <g fill="#eef4ff" opacity=".45"><rect x="128" y="10" width="64" height="4" rx="2"/><rect x="140" y="26" width="40" height="3" rx="1.5"/></g>
    `,
  };

  const SCENE_BY_DEVICE = {
    "device-1": "entrance",
    "device-2": "guard",
    "device-8": "gate",
    "device-9": "racks",
    "device-10": "receiving",
    "device-11": "dock",
    "device-12": "racks",
    "device-18": "server",
    "device-23": "hall",
    "device-24": "checkout",
    "device-25": "corridor",
    "device-26": "storefront",
    "device-31": "entrance",
    "device-33": "guard",
    "device-34": "checkpoint",
    "device-35": "barrier",
  };

  // Мини-глифы устройств для планов: система координат -8..8.
  const DEVICE_GLYPH = {
    camera: `<rect x="-7" y="-4" width="9" height="8" rx="1.5"/><path d="M2.4 -2.2 7.4 -5.2V5.2L2.4 2.2z"/>`,
    "fire-detector": `<path d="M0 -7c3.2 3.4 4.8 4.9 4.8 7.4A4.8 4.8 0 0 1 0 6.6a4.8 4.8 0 0 1-4.8-5.4C-4.8 -1.8 -2 -3.4 0 -7z"/>`,
    "panic-button": `<circle r="6.8" opacity=".35"/><circle r="3.4"/>`,
    "ppe-detector": `<path d="M-7 3.2h14A7 7 0 0 0-7 3.2z"/><rect x="-8.4" y="3.6" width="16.8" height="2.8" rx="1.4"/>`,
    "access-point": `<rect x="-6.4" y="-7" width="12.8" height="14" rx="1.6" fill="none" stroke="currentColor" stroke-width="2.2"/><circle cx="3" cy="0" r="1.5"/>`,
    microphone: `<rect x="-2.8" y="-7" width="5.6" height="9" rx="2.8"/><path d="M-5.4 0a5.4 5.4 0 0 0 10.8 0" fill="none" stroke="currentColor" stroke-width="2.2"/><path d="M0 5.4v3.2" stroke="currentColor" stroke-width="2.2"/>`,
  };

  const PLANS = {
    mall: {
      title: "Торговый центр · 1-й этаж",
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="158" height="106" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="210" y="32" width="158" height="106" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="32" y="152" width="120" height="76" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="172" y="152" width="196" height="76" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="150" y1="138" x2="176" y2="138"/><line x1="270" y1="138" x2="300" y2="138"/>
          <line x1="60" y1="228" x2="110" y2="228"/>
        </g>
        <g fill="var(--map-room-2)" opacity=".9">
          <rect x="44" y="72" width="46" height="7"/><rect x="44" y="88" width="46" height="7"/>
        </g>
        <g fill="var(--map-room)" opacity=".9">
          <rect x="292" y="62" width="9" height="30"/><rect x="308" y="62" width="9" height="30"/><rect x="324" y="62" width="9" height="30"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="48">Магазин 1 · торговый зал</text>
          <text x="220" y="48">Магазин 2 · примерочные</text>
          <text x="42" y="170">Входная группа · витрина</text>
          <text x="182" y="170">Атриум · галерея</text>
        </g>
      `,
    },
    warehouse: {
      title: "Складской комплекс · Этаж А",
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="30" y="30" width="76" height="200" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="122" y="30" width="176" height="200" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="312" y="30" width="58" height="96" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="312" y="140" width="58" height="90" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g fill="var(--stroke-2)">
          <rect x="14" y="60" width="6" height="40"/><rect x="14" y="150" width="6" height="40"/>
        </g>
        <g fill="var(--map-room-2)" opacity=".95">
          <rect x="140" y="46" width="140" height="12"/><rect x="140" y="92" width="140" height="12"/>
          <rect x="140" y="158" width="140" height="12"/><rect x="140" y="200" width="140" height="12"/>
        </g>
        <g stroke="var(--warn)" stroke-width="2" stroke-dasharray="6 5" opacity=".6">
          <line x1="106" y1="130" x2="312" y2="130"/>
        </g>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="106" y1="112" x2="106" y2="146"/><line x1="298" y1="112" x2="298" y2="146"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="34" y="46">Рампа и ворота</text>
          <text x="140" y="42">Стеллажи А1–А8</text>
          <text x="140" y="152">Стеллажи А9–А16</text>
          <text x="316" y="46">Приёмка</text>
          <text x="316" y="156">Цех</text>
          <text x="206" y="124">Центральный проход</text>
        </g>
      `,
    },
    office: {
      title: "Главный офис · 1-й этаж",
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="168" height="82" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="216" y="32" width="152" height="106" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="32" y="130" width="168" height="98" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="216" y="154" width="152" height="74" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="200" y1="170" x2="216" y2="170"/><line x1="120" y1="114" x2="150" y2="114"/>
          <line x1="90" y1="228" x2="140" y2="228"/>
        </g>
        <g fill="var(--map-room)" opacity=".9">
          <rect x="44" y="140" width="66" height="14" rx="3"/>
          <rect x="232" y="168" width="80" height="14" rx="3"/>
        </g>
        <g fill="var(--map-room-2)" opacity=".9">
          <rect x="60" y="52" width="112" height="30" rx="4"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="46">Конференц-зал</text>
          <text x="226" y="46">Зона ожидания</text>
          <text x="42" y="146">Приемная и ресепшн</text>
          <text x="226" y="168">Пост охраны</text>
          <text x="60" y="222">Главный вход</text>
        </g>
      `,
    },
    lab: {
      title: "Технопарк · Корпус А",
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="158" height="94" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="210" y="32" width="158" height="94" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="32" y="140" width="336" height="36" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="32" y="190" width="158" height="38" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="210" y="190" width="158" height="38" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="96" y1="126" x2="130" y2="126"/><line x1="274" y1="126" x2="308" y2="126"/>
          <line x1="96" y1="190" x2="130" y2="190"/><line x1="274" y1="190" x2="308" y2="190"/>
        </g>
        <g fill="var(--map-room-2)" opacity=".9">
          <rect x="46" y="52" width="60" height="10" rx="2"/><rect x="46" y="72" width="60" height="10" rx="2"/>
          <rect x="228" y="52" width="60" height="10" rx="2"/><rect x="228" y="72" width="60" height="10" rx="2"/>
        </g>
        <g fill="var(--map-room)" opacity=".95">
          <rect x="320" y="44" width="16" height="34" rx="2"/><rect x="342" y="44" width="16" height="34" rx="2"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="46">Лаборатория 1</text>
          <text x="220" y="46">Лаборатория 2 · серверная</text>
          <text x="42" y="162">Коридор корпуса</text>
          <text x="42" y="212">Офис 1</text>
          <text x="220" y="212">Офис 2</text>
        </g>
      `,
    },
    checkpoint: {
      title: "КПП и проходная склада",
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="16" y="96" width="368" height="66" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <g stroke="var(--map-label)" stroke-width="2" stroke-dasharray="12 10" opacity=".5">
          <line x1="16" y1="129" x2="384" y2="129"/>
        </g>
        <rect x="204" y="30" width="112" height="58" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="36" y="176" width="132" height="56" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="2" opacity=".7">
          <line x1="60" y1="176" x2="60" y2="232"/><line x1="90" y1="176" x2="90" y2="232"/>
          <line x1="120" y1="176" x2="120" y2="232"/><line x1="150" y1="176" x2="150" y2="232"/>
        </g>
        <g fill="var(--crit)" opacity=".7"><rect x="112" y="92" width="70" height="6" rx="3"/></g>
        <g fill="var(--stroke-2)"><rect x="106" y="86" width="8" height="22" rx="2"/></g>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="240" y1="88" x2="270" y2="88"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="212" y="46">Проходная · турникеты</text>
          <text x="42" y="192">Парковка персонала</text>
          <text x="30" y="116">Въезд</text>
          <text x="330" y="116">Территория</text>
        </g>
      `,
    },
  };

  const DEVICE_POS = {
    "device-1": { plan: "office", x: 152, y: 214 },
    "device-2": { plan: "office", x: 60, y: 164 },
    "device-3": { plan: "office", x: 60, y: 48 },
    "device-4": { plan: "office", x: 176, y: 102 },
    "device-5": { plan: "office", x: 312, y: 100 },
    "device-6": { plan: "office", x: 346, y: 124 },
    "device-7": { plan: "office", x: 238, y: 122 },
    "device-31": { plan: "office", x: 300, y: 74 },
    "device-32": { plan: "office", x: 350, y: 50 },
    "device-33": { plan: "office", x: 258, y: 196 },
    "fire-1": { plan: "office", x: 150, y: 142 },
    "fire-2": { plan: "office", x: 170, y: 42 },
    "fire-6": { plan: "office", x: 240, y: 76 },
    "panic-1": { plan: "office", x: 300, y: 214 },
    "panic-2": { plan: "office", x: 44, y: 190 },
    "gate-2": { plan: "office", x: 112, y: 180 },

    "device-8": { plan: "warehouse", x: 44, y: 172 },
    "device-9": { plan: "warehouse", x: 208, y: 74 },
    "device-10": { plan: "warehouse", x: 340, y: 76 },
    "device-11": { plan: "warehouse", x: 66, y: 86 },
    "device-12": { plan: "warehouse", x: 160, y: 130 },
    "device-13": { plan: "warehouse", x: 340, y: 210 },
    "device-14": { plan: "warehouse", x: 66, y: 208 },
    "fire-3": { plan: "warehouse", x: 268, y: 46 },
    "ppe-1": { plan: "warehouse", x: 96, y: 122 },
    "ppe-2": { plan: "warehouse", x: 330, y: 162 },

    "device-15": { plan: "lab", x: 70, y: 62 },
    "device-16": { plan: "lab", x: 166, y: 116 },
    "device-17": { plan: "lab", x: 250, y: 62 },
    "device-18": { plan: "lab", x: 340, y: 62 },
    "device-19": { plan: "lab", x: 340, y: 112 },
    "device-20": { plan: "lab", x: 200, y: 158 },
    "device-21": { plan: "lab", x: 70, y: 212 },
    "device-22": { plan: "lab", x: 300, y: 212 },
    "fire-4": { plan: "lab", x: 162, y: 42 },

    "device-23": { plan: "mall", x: 96, y: 104 },
    "device-24": { plan: "mall", x: 166, y: 124 },
    "device-25": { plan: "mall", x: 258, y: 104 },
    "device-26": { plan: "mall", x: 62, y: 208 },
    "device-27": { plan: "mall", x: 240, y: 202 },
    "device-28": { plan: "mall", x: 300, y: 172 },
    "device-29": { plan: "mall", x: 344, y: 204 },
    "device-30": { plan: "mall", x: 350, y: 168 },
    "fire-5": { plan: "mall", x: 62, y: 62 },
    "mic-1": { plan: "mall", x: 116, y: 182 },
    "mic-2": { plan: "mall", x: 132, y: 70 },

    "device-34": { plan: "checkpoint", x: 292, y: 74 },
    "device-35": { plan: "checkpoint", x: 140, y: 148 },
    "gate-1": { plan: "checkpoint", x: 230, y: 74 },
  };

  const PLAN_BY_OBJECT = {
    "Торговый центр": "mall",
    "Складской комплекс": "warehouse",
    "Главный офис": "office",
    Технопарк: "lab",
  };

  function devView(id) {
    const spec = DEVICE_CATALOG[id] || {};
    return {
      id,
      name: spec.name || id,
      type: spec.type || "camera",
      typeLabel: (DEVICE_TYPES[spec.type] || DEVICE_TYPES.camera).label,
      scene: SCENE_BY_DEVICE[id] || "hall",
    };
  }

  // Источник инцидента — первое устройство в deviceIds: датчик, детектор или камера аналитики.
  function eventSource(ev) {
    return (ev.deviceIds && ev.deviceIds[0]) || (ev.cameras && ev.cameras[0]) || null;
  }

  function eventPlan(ev) {
    const ids = [eventSource(ev), ...(ev.deviceIds || []), ...(ev.cameras || [])].filter(Boolean);
    for (const id of ids) {
      if (DEVICE_POS[id]) return DEVICE_POS[id].plan;
    }
    return PLAN_BY_OBJECT[ev.object] || "mall";
  }

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
      answers: {},
      launched: [],
      log: [{ t: "14:31:08", who: "Диспетчер", text: "Событие поставлено в очередь" }],
    },
    {
      id: "INC-1850",
      time: "14:30:12",
      typeId: "glass",
      type: "Детекция звука разбития стекла",
      object: "Торговый центр",
      objectType: "Торговый центр",
      location: "Магазин 2, витрина у входа",
      region: "Торговый центр",
      priority: "high",
      status: "new",
      operator: null,
      slaSec: 300,
      deviceIds: ["mic-1", "device-26", "device-23"],
      media: "both",
      cameras: ["device-26", "device-23"],
      answers: {},
      launched: [],
      log: [
        { t: "14:30:12", who: "Аудиодетекция", text: "Микрофон «Витрина у входа»: спектр разбития стекла, 87 дБ" },
      ],
    },
    {
      id: "INC-1849",
      time: "14:29:35",
      typeId: "alcohol",
      type: "Детекция превышения уровня алкоголя",
      object: "Складской комплекс",
      objectType: "КПП",
      location: "КПП, проходная — турникет №2",
      region: "Складской комплекс",
      priority: "high",
      status: "new",
      operator: null,
      slaSec: 420,
      deviceIds: ["gate-1", "device-34", "device-35"],
      media: "both",
      cameras: ["device-34", "device-35"],
      answers: {},
      launched: [],
      log: [
        { t: "14:29:35", who: "Точка прохода", text: "Алкорамка на турникете №2: показание выше порога, проход заблокирован" },
      ],
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
      answers: { visual: true, verdict: "Недостаточно данных" },
      launched: [],
      log: [
        { t: "14:28:41", who: "Диспетчер", text: "Событие поставлено в очередь" },
        { t: "14:29:02", who: "Петрова М.", text: "Взято в работу · шаг 2/5" },
      ],
    },
    {
      id: "INC-1848",
      time: "14:26:14",
      typeId: "ppe",
      type: "Отсутствие каски",
      object: "Складской комплекс",
      objectType: "Склад",
      location: "Склад №2, разгрузочная рампа",
      region: "Складской комплекс",
      priority: "medium",
      status: "new",
      operator: null,
      slaSec: 720,
      deviceIds: ["ppe-1", "device-11", "device-8"],
      media: "both",
      cameras: ["device-11", "device-8"],
      answers: {},
      launched: [],
      log: [
        { t: "14:26:14", who: "Детектор СИЗ", text: "Зона рампы: человек без защитной каски, достоверность 0,93" },
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
      answers: {},
      launched: [],
      log: [{ t: "14:06:12", who: "Диспетчер", text: "Сработка пожарного датчика" }],
    },
    {
      id: "INC-1841",
      time: "13:58:44",
      typeId: "loiter",
      type: "Скопление людей",
      object: "Торговый центр",
      objectType: "Торговый центр",
      location: "2-й этаж, фойе кинотеатра",
      region: "Торговый центр",
      priority: "medium",
      status: "new",
      operator: null,
      slaSec: 660,
      deviceIds: ["device-29", "device-30"],
      media: "video",
      cameras: ["device-29", "device-30"],
      answers: {},
      launched: [],
      log: [{ t: "13:58:44", who: "Видеоаналитика", text: "Превышение плотности людей в зоне" }],
    },
    {
      id: "INC-1840",
      time: "13:51:09",
      typeId: "sabotage",
      type: "Саботаж камеры",
      object: "Технопарк",
      objectType: "Лаборатория",
      location: "Корпус А, лаборатория 2",
      region: "Технопарк",
      priority: "medium",
      status: "foreign",
      operator: "Сидоров К.",
      slaSec: 540,
      deviceIds: ["device-18", "device-17"],
      media: "video",
      cameras: ["device-18"],
      answers: { lost: true },
      launched: [],
      log: [
        { t: "13:51:09", who: "Видеоаналитика", text: "Потеря видеопотока" },
        { t: "13:52:31", who: "Сидоров К.", text: "Взято в работу · шаг 1/4" },
      ],
    },
    {
      id: "INC-1839",
      time: "13:44:57",
      typeId: "intrusion",
      type: "Проникновение",
      object: "Складской комплекс",
      objectType: "Склад",
      location: "Склад №2, центральный проход",
      region: "Складской комплекс",
      priority: "high",
      status: "new",
      operator: null,
      slaSec: 360,
      deviceIds: ["device-11", "device-12"],
      media: "both",
      cameras: ["device-11"],
      answers: {},
      launched: [],
      log: [{ t: "13:44:57", who: "Диспетчер", text: "Событие поставлено в очередь" }],
    },
    {
      id: "INC-1838",
      time: "13:37:12",
      typeId: "fire",
      type: "Пожарная тревога",
      object: "Главный офис",
      objectType: "Офис",
      location: "1-й этаж, конференц-зал",
      region: "Главный офис",
      priority: "critical",
      status: "new",
      operator: null,
      slaSec: 210,
      deviceIds: ["fire-2", "device-3", "device-4"],
      media: "both",
      cameras: ["device-3", "device-4"],
      answers: {},
      launched: [],
      log: [{ t: "13:37:12", who: "Диспетчер", text: "Сработка пожарного датчика" }],
    },
    {
      id: "INC-1837",
      time: "13:29:38",
      typeId: "loiter",
      type: "Скопление людей",
      object: "Главный офис",
      objectType: "Офис",
      location: "Приемная, зона ожидания",
      region: "Главный офис",
      priority: "low",
      status: "closed",
      operator: "Иванов А. С.",
      slaSec: 0,
      deviceIds: ["device-31", "device-32"],
      media: "video",
      cameras: ["device-31"],
      answers: { visual: true, verdict: "Наблюдать", note: "Очередь на регистрацию, разошлись сами" },
      launched: [],
      log: [
        { t: "13:29:38", who: "Видеоаналитика", text: "Скопление в зоне ожидания" },
        { t: "13:35:02", who: "Иванов А. С.", text: "Инцидент закрыт" },
      ],
    },
    {
      id: "INC-1836",
      time: "13:22:05",
      typeId: "intrusion",
      type: "Проникновение",
      object: "Технопарк",
      objectType: "Лаборатория",
      location: "Корпус А, вход в чистую зону",
      region: "Технопарк",
      priority: "high",
      status: "escalated",
      operator: "Дежурный ЦОД",
      slaSec: 150,
      deviceIds: ["device-16", "device-15"],
      media: "both",
      cameras: ["device-16"],
      answers: { visual: true, verdict: "Недостаточно данных" },
      launched: [],
      log: [{ t: "13:24:11", who: "Петрова М.", text: "Эскалация: требуется допуск в чистую зону" }],
    },
    {
      id: "INC-1835",
      time: "13:14:49",
      typeId: "sabotage",
      type: "Саботаж камеры",
      object: "Складской комплекс",
      objectType: "Склад",
      location: "Склад №3, холодильная камера",
      region: "Складской комплекс",
      priority: "medium",
      status: "new",
      operator: null,
      slaSec: 480,
      deviceIds: ["device-13"],
      media: "video",
      cameras: ["device-13"],
      answers: {},
      launched: [],
      log: [{ t: "13:14:49", who: "Видеоаналитика", text: "Резкое падение освещённости кадра" }],
    },
    {
      id: "INC-1834",
      time: "13:06:31",
      typeId: "fire",
      type: "Пожарная тревога",
      object: "Торговый центр",
      objectType: "Торговый центр",
      location: "2-й этаж, кухня ресторана",
      region: "Торговый центр",
      priority: "critical",
      status: "mine",
      operator: "Иванов А. С.",
      paused: true,
      stepIndex: 2,
      slaSec: 195,
      deviceIds: ["device-28", "device-27"],
      media: "both",
      cameras: ["device-27", "device-28"],
      answers: { visual: true, verdict: "Реальная", kind: "Задымление" },
      launched: [],
      log: [
        { t: "13:06:31", who: "Диспетчер", text: "Задымление на кухне" },
        { t: "13:08:44", who: "Иванов А. С.", text: "Обработка приостановлена на шаге 3" },
      ],
    },
    {
      id: "INC-1833",
      time: "12:58:17",
      typeId: "loiter",
      type: "Скопление людей",
      object: "Складской комплекс",
      objectType: "Склад",
      location: "Этаж А, разгрузочная рампа",
      region: "Складской комплекс",
      priority: "low",
      status: "new",
      operator: null,
      slaSec: 720,
      deviceIds: ["device-11", "device-10"],
      media: "video",
      cameras: ["device-11", "device-10"],
      answers: {},
      launched: [],
      log: [{ t: "12:58:17", who: "Видеоаналитика", text: "Группа людей у рампы дольше 10 минут" }],
    },
    {
      id: "INC-1832",
      time: "12:49:53",
      typeId: "intrusion",
      type: "Проникновение",
      object: "Главный офис",
      objectType: "Офис",
      location: "2-й этаж, отдел разработки",
      region: "Главный офис",
      priority: "medium",
      status: "foreign",
      operator: "Петрова М.",
      slaSec: 600,
      deviceIds: ["device-5"],
      media: "video",
      cameras: ["device-5"],
      answers: { visual: true },
      launched: [],
      log: [
        { t: "12:49:53", who: "СКУД", text: "Проход без карты в нерабочее время" },
        { t: "12:51:02", who: "Петрова М.", text: "Взято в работу · шаг 1/5" },
      ],
    },
    {
      id: "INC-1831",
      time: "12:41:26",
      typeId: "fire",
      type: "Пожарная тревога",
      object: "Технопарк",
      objectType: "Лаборатория",
      location: "Корпус А, лаборатория 1",
      region: "Технопарк",
      priority: "high",
      status: "closed",
      operator: "Сидоров К.",
      slaSec: 0,
      deviceIds: ["fire-4", "device-15", "device-16"],
      media: "map",
      cameras: ["device-15"],
      answers: { visual: true, verdict: "Ложная", kind: "Тест системы", note: "Плановая проверка АПС" },
      launched: [],
      log: [
        { t: "12:41:26", who: "Диспетчер", text: "Сработка пожарного датчика" },
        { t: "12:47:10", who: "Сидоров К.", text: "Инцидент закрыт: плановый тест" },
      ],
    },
    {
      id: "INC-1830",
      time: "12:33:04",
      typeId: "sabotage",
      type: "Саботаж камеры",
      object: "Торговый центр",
      objectType: "Торговый центр",
      location: "1-й этаж, витрина у входа",
      region: "Торговый центр",
      priority: "medium",
      status: "new",
      operator: null,
      slaSec: 420,
      deviceIds: ["device-26"],
      media: "video",
      cameras: ["device-26"],
      answers: {},
      launched: [],
      log: [{ t: "12:33:04", who: "Видеоаналитика", text: "Камера смещена с сектора обзора" }],
    },
    {
      id: "INC-1829",
      time: "12:25:40",
      typeId: "intrusion",
      type: "Проникновение",
      object: "Технопарк",
      objectType: "Офис",
      location: "Корпус Б, коридор",
      region: "Технопарк",
      priority: "low",
      status: "closed",
      operator: "Иванов А. С.",
      slaSec: 0,
      deviceIds: ["device-20"],
      media: "video",
      cameras: ["device-20"],
      answers: { visual: true, verdict: "Персонал / ложная", note: "Сотрудник клининга по графику" },
      launched: [],
      log: [
        { t: "12:25:40", who: "СКУД", text: "Открытие двери без карты" },
        { t: "12:28:55", who: "Иванов А. С.", text: "Инцидент закрыт" },
      ],
    },
    {
      id: "INC-1828",
      time: "12:17:12",
      typeId: "fire",
      type: "Пожарная тревога",
      object: "Главный офис",
      objectType: "Офис",
      location: "Приемная, зона ожидания",
      region: "Главный офис",
      priority: "high",
      status: "new",
      operator: null,
      slaSec: 330,
      deviceIds: ["fire-6", "device-31"],
      media: "both",
      cameras: ["device-31"],
      answers: {},
      launched: [],
      log: [{ t: "12:17:12", who: "Диспетчер", text: "Сработка датчика дыма в зоне ожидания" }],
    },
    {
      id: "INC-1827",
      time: "12:08:35",
      typeId: "loiter",
      type: "Скопление людей",
      object: "Торговый центр",
      objectType: "Торговый центр",
      location: "1-й этаж, кассовая зона",
      region: "Торговый центр",
      priority: "low",
      status: "new",
      operator: null,
      slaSec: 780,
      deviceIds: ["device-24"],
      media: "video",
      cameras: ["device-24"],
      answers: {},
      launched: [],
      log: [{ t: "12:08:35", who: "Видеоаналитика", text: "Очередь на кассах дольше норматива" }],
    },
    {
      id: "INC-1826",
      time: "11:59:48",
      typeId: "intrusion",
      type: "Проникновение",
      object: "Складской комплекс",
      objectType: "Склад",
      location: "Склад №1, стеллажи А1–А8",
      region: "Складской комплекс",
      priority: "medium",
      status: "closed",
      operator: "Петрова М.",
      slaSec: 0,
      deviceIds: ["device-9", "device-8"],
      media: "video",
      cameras: ["device-8"],
      answers: { visual: true, verdict: "Персонал / ложная", zone: "Склад" },
      launched: [],
      log: [
        { t: "11:59:48", who: "Видеоаналитика", text: "Движение в закрытой зоне" },
        { t: "12:04:19", who: "Петрова М.", text: "Инцидент закрыт" },
      ],
    },
  ];

  // Настройки диспетчера (в продукте задаются на сервере / в карточке фильтра).
  const SETTINGS = {
    autoEscalate: {
      enabled: true,
      // Статусы, при которых срабатывает автоэскалация по истечении SLA.
      statuses: ["new", "mine"],
      target: "Петрова М. · старший смены",
      reason: "Автоэскалация: превышен норматив реакции (SLA)",
    },
  };

  const state = {
    events: EVENTS,
    mode: "queue",
    groupsOn: true,
    mediaOn: true,
    themeMode: "dark",
    camFor: null,
    mobileView: "queue",
    page: 1,
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
    full: null,
    escalateId: null,
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

  const narrowQuery = window.matchMedia("(max-width: 900px)");

  function applyTheme(mode) {
    const theme = mode === "light" ? "light" : "dark";
    state.themeMode = theme;
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem("im-theme", theme);
    } catch (err) {
      /* ignore */
    }
    const label = theme === "light" ? "Светлая тема" : "Тёмная тема";
    const btn = $("themeToggle");
    btn.title = label;
    btn.setAttribute("aria-label", label);
    btn.setAttribute("aria-pressed", String(theme === "light"));
  }

  function showModal(id) {
    const modal = $(id);
    if (!modal) return;
    document.querySelectorAll(".modal:not([hidden])").forEach((m) => (m.hidden = true));
    modal.hidden = false;
    const focusTarget = modal.querySelector(".modal-actions .btn");
    if (focusTarget) focusTarget.focus();
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

  // Ручная эскалация доступна до взятия (новое) и из своей карточки (в работе / приостановлен).
  function canManualEscalate(ev) {
    return Boolean(ev) && (ev.status === "new" || ev.status === "mine");
  }

  function canAutoEscalate(ev) {
    if (!SETTINGS.autoEscalate.enabled || !ev || ev.autoEscalated) return false;
    if (ev.status === "closed" || ev.status === "escalated") return false;
    return SETTINGS.autoEscalate.statuses.includes(ev.status) && ev.slaSec <= 0;
  }

  function openEscalateModal(ev) {
    if (!canManualEscalate(ev)) return;
    state.selectedId = ev.id;
    state.escalateId = ev.id;
    $("escalateReason").value = "";
    $("modalEscalate").hidden = false;
  }

  function escalateEvent(ev, opts) {
    if (!ev || ev.status === "closed" || ev.status === "escalated") return false;
    const target = opts.target || SETTINGS.autoEscalate.target;
    const reason = opts.reason || "";
    const auto = Boolean(opts.auto);
    if (auto) {
      if (!SETTINGS.autoEscalate.enabled || ev.autoEscalated) return false;
      if (!SETTINGS.autoEscalate.statuses.includes(ev.status) || ev.slaSec > 0) return false;
      ev.autoEscalated = true;
    } else if (!canManualEscalate(ev)) {
      return false;
    }
    const prev = ev.status;
    ev.status = "escalated";
    ev.operator = target;
    ev.paused = false;
    ev.log.push({
      t: nowStamp(),
      who: auto ? "Диспетчер" : ME,
      text: auto
        ? `Автоэскалация → ${target}. ${reason || SETTINGS.autoEscalate.reason}`
        : `Эскалация → ${target}${prev === "new" ? " (до взятия)" : ""}. ${reason || "Причина не указана"}`,
    });
    toast(auto ? `Автоэскалация ${ev.id} → ${target}` : `Эскалация ${ev.id} → ${target}`);
    return true;
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

  // Цепочка групп от корня до той, где стоит устройство события.
  // Устройство может встречаться и в сквозных подборках — берём первое вхождение.
  function groupPathForDevices(deviceIds) {
    const wanted = new Set(deviceIds || []);
    const walk = (nodes, trail) => {
      for (const node of nodes) {
        if (node.isDevice) {
          if (wanted.has(node.id)) return trail;
          continue;
        }
        const found = walk(node.children || [], trail.concat(node.id));
        if (found) return found;
      }
      return null;
    };
    return walk(TREE, []) || [];
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

  function renderTreeHtml(nodes, level, trace) {
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
        const traced = trace.ids.has(item.id) ? (item.id === trace.leaf ? "trace trace-leaf" : "trace") : "";
        return `
          <li class="tree-node ${hasKids ? "has-children" : ""} ${open ? "open" : ""} ${
            state.groupId === item.id ? "active" : ""
          } ${traced} ${item.isDevice ? "is-device" : ""} ${hidden ? "hidden" : ""} level-${level}"
              data-id="${item.id}" data-type="${item.isDevice ? "device" : "group"}" role="treeitem">
            <div class="node-content" title="${escapeHtml(title)}">
              <span class="toggle-icon material-symbols-outlined">chevron_right</span>
              <span class="material-symbols-outlined">${icon}</span>
              <span class="node-text">${escapeHtml(name)}</span>
              ${!item.isDevice && hasKids ? `<span class="tree-badge">${badgeText(item)}</span>` : ""}
              ${openCount ? `<span class="tree-ev ${crit ? "crit" : ""}">${openCount}</span>` : ""}
            </div>
            ${hasKids ? `<ul role="group">${renderTreeHtml(item.children, level + 1, trace)}</ul>` : ""}
          </li>`;
      })
      .join("");
  }

  let tracedEventId = null;

  // Группа выбранного события подсвечивается вместе с родителями и
  // раскрывается — но только при смене события, чтобы не мешать сворачиванию
  function traceGroups() {
    const ev = selected();
    const path = ev ? groupPathForDevices(ev.deviceIds) : [];
    const changed = (ev ? ev.id : null) !== tracedEventId;
    if (changed) {
      tracedEventId = ev ? ev.id : null;
      path.forEach((id) => state.openGroups.add(id));
    }
    return { ids: new Set(path), leaf: path[path.length - 1] || null, changed };
  }

  function renderGroups() {
    const trace = traceGroups();
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
      ${renderTreeHtml(TREE, 0, trace)}
    `;
    const q = state.groupQuery.trim();
    const visible = [...$("groupsList").querySelectorAll(".tree-node")].filter(
      (n) => n.dataset.id !== "all" && !n.classList.contains("hidden")
    );
    $("groupsEmpty").hidden = !q || visible.length > 0;
    if (trace.changed) {
      const leaf = $("groupsList").querySelector(".trace-leaf > .node-content");
      if (leaf) leaf.scrollIntoView({ block: "nearest" });
    }
  }

  function pageSequence(current, total) {
    const set = new Set([1, total, current, current - 1, current + 1]);
    if (current <= 3) [2, 3, 4].forEach((n) => set.add(n));
    if (current >= total - 2) [total - 1, total - 2, total - 3].forEach((n) => set.add(n));
    const nums = [...set].filter((n) => n >= 1 && n <= total).sort((a, b) => a - b);
    const out = [];
    nums.forEach((n, i) => {
      if (i && n - nums[i - 1] > 1) out.push("gap");
      out.push(n);
    });
    return out;
  }

  function pageOfEvent(id) {
    const idx = visibleEvents().findIndex((e) => e.id === id);
    return idx === -1 ? state.page : Math.floor(idx / PAGE_SIZE) + 1;
  }

  function renderPager(total, pages, start, shown) {
    const pager = $("eventsPager");
    if (total <= PAGE_SIZE) {
      pager.hidden = true;
      pager.innerHTML = "";
      return;
    }
    const step = (page, icon, label, disabled) => `
      <button type="button" class="pager-btn" data-page="${page}" title="${label}" aria-label="${label}" ${
        disabled ? "disabled" : ""
      }>
        <span class="material-symbols-outlined">${icon}</span>
      </button>`;
    pager.hidden = false;
    pager.innerHTML = `
      <span class="pager-info">${start + 1}–${start + shown} из ${total}</span>
      <div class="pager-nav">
        ${step(state.page - 1, "chevron_left", "Предыдущая страница", state.page === 1)}
        ${pageSequence(state.page, pages)
          .map((p) =>
            p === "gap"
              ? `<span class="pager-gap" aria-hidden="true">…</span>`
              : `<button type="button" class="pager-btn ${p === state.page ? "current" : ""}" data-page="${p}" ${
                  p === state.page ? 'aria-current="page"' : ""
                } aria-label="Страница ${p}">${p}</button>`
          )
          .join("")}
        ${step(state.page + 1, "chevron_right", "Следующая страница", state.page === pages)}
      </div>
    `;
  }

  function renderEvents() {
    const list = visibleEvents();
    $("eventsCount").textContent = String(list.length);
    $("groupProcessBtn").disabled = state.checked.size < 2 || state.onBreak;
    const pages = Math.max(1, Math.ceil(list.length / PAGE_SIZE));
    state.page = Math.min(Math.max(1, state.page), pages);
    const start = (state.page - 1) * PAGE_SIZE;
    const pageItems = list.slice(start, start + PAGE_SIZE);
    renderPager(list.length, pages, start, pageItems.length);
    $("eventsList").innerHTML = pageItems
      .map((e) => {
        const st = statusLabel(e);
        const kind = actionKind(e);
        const act = ACTIONS[kind];
        const prog = stepProgress(e);
        const blocked = state.onBreak && (kind === "take" || kind === "resume");
        const canEsc = canManualEscalate(e);
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
                    : `<span class="event-sla ${e.slaSec < 120 ? "late" : ""}" data-sla="${
                        e.id
                      }" title="Время до нарушения норматива реакции">Норматив ${fmtSla(e.slaSec)}</span>`
                }
                ${prog.filled ? `<span class="event-prog">Сценарий ${prog.filled}/${prog.total}</span>` : ""}
              </div>
            </div>
            <div class="event-acts">
              ${
                canEsc && e.status === "new"
                  ? `<button type="button" class="btn ghost event-esc" data-escalate="${e.id}" title="Эскалировать без взятия в работу">Эскал.</button>`
                  : ""
              }
              <button type="button" class="btn ${act.style} event-act" data-act="${e.id}" title="${act.hint}" ${
                blocked ? "disabled" : ""
              }>${act.label}</button>
            </div>
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
        <div class="work-top">
          ${renderIncidentHead(ev, prog)}
          ${workNote(ev)}
          <ol class="crumbs" aria-label="Шаги сценария">
          ${steps
            .map((s, idx) => {
              const open = canOpenStep(ev, idx);
              const current = idx === i;
              const answer = stepAnswerText(ev, s);
              const nav = open && !current;
              return `
                <li class="crumb ${current ? "current" : ""} ${answer ? "done" : ""} ${
                  open ? "" : "locked"
                } ${nav ? "nav" : ""}" ${current ? 'aria-current="step"' : ""} ${
                  nav ? `data-crumb="${idx}" role="button" tabindex="0"` : ""
                } title="${escapeHtml(s.label)}">
                  <span class="crumb-track">
                    <span class="crumb-n">${idx + 1}</span>
                    <span class="crumb-line" aria-hidden="true"></span>
                  </span>
                  <span class="crumb-body">
                    <span class="crumb-name">${escapeHtml(stepShort(s))}</span>
                    ${answer && !current ? `<span class="crumb-ans">${escapeHtml(answer)}</span>` : ""}
                  </span>
                </li>
              `;
            })
            .join("")}
          </ol>
        </div>
        <div class="work-step">
          <div class="step-card">
            <div class="step-h">
              <strong>${escapeHtml(step.label)}</strong>
              <span>${i + 1} из ${steps.length}${step.required ? "" : " · необязательно"}</span>
            </div>
            ${renderStepControl(step, ev, editable)}
          </div>
        </div>
        <div class="work-bottom">
          <div class="scenario-actions">
            <button type="button" class="btn ghost" id="stepBack" ${i === 0 ? "disabled" : ""}>Назад</button>
            <div class="scenario-actions-end">
              ${mine || ev.status === "new" ? `<button type="button" class="btn ghost" id="escalateBtn">Эскалация</button>` : ""}
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
          <span class="sla ${
            ev.slaSec < 120 ? "late" : ""
          }" title="Время до нарушения норматива реакции">Норматив ${fmtSla(ev.slaSec)}</span>
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

  function mediaMode() {
    const ev = selected();
    return ev && ev.media ? ev.media : "both";
  }

  function applyMediaLayout() {
    $("panelMedia").dataset.media = mediaMode();
  }

  // Разворот на всю рабочую область и переключатели панелей — одна раскладка
  function applyLayoutState() {
    const ws = $("workspace");
    const mode = mediaMode();
    if (state.full && mode !== "both" && mode !== state.full) state.full = null;
    ws.dataset.groups = state.groupsOn ? "on" : "off";
    ws.dataset.mediapanel = state.mediaOn ? "on" : "off";
    if (state.full) ws.dataset.full = state.full;
    else delete ws.dataset.full;
  }

  function toggleFull(which) {
    state.full = state.full === which ? null : which;
    applyLayoutState();
    renderTopbar();
  }

  function renderVideo() {
    const ev = selected();
    const cams = ev && ev.cameras ? ev.cameras : [];
    if (!cams.length) {
      $("videoStage").innerHTML = `<div class="empty">К инциденту не привязаны камеры</div>`;
      $("camStrip").hidden = true;
      return;
    }
    if (!cams.includes(state.activeCam)) state.activeCam = cams[0];
    const idx = cams.indexOf(state.activeCam);
    const cam = devView(state.activeCam);
    const live = state.videoMode === "live";
    const many = cams.length > 1;

    $("videoStage").innerHTML = `
      <div class="cam" data-cam="${state.activeCam}">
        <svg class="cam-scene" viewBox="0 0 320 180" preserveAspectRatio="xMidYMid meet" aria-hidden="true">
          ${SCENES[cam.scene] || SCENES.hall}
        </svg>
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
              const c = devView(id);
              return `<button type="button" class="cam-tick ${
                i === idx ? "active" : ""
              }" data-cam="${id}" title="${escapeHtml(c.name)}" aria-label="${escapeHtml(c.name)}"></button>`;
            })
            .join("")}
        </div>
        <span class="cam-counter">${idx + 1} / ${cams.length}</span>
      `;
    }
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

  function deviceMarker(id, opts) {
    const pos = DEVICE_POS[id];
    if (!pos) return "";
    const dev = devView(id);
    const cls = ["dev-marker", `dev-${dev.type}`, opts.source ? "is-source" : "", opts.active ? "is-active" : ""]
      .filter(Boolean)
      .join(" ");
    const clickable = dev.type === "camera" ? ` data-cam="${id}"` : "";
    return `
      <g class="${cls}"${clickable} transform="translate(${pos.x},${pos.y})">
        <title>${escapeHtml(dev.typeLabel)}: ${escapeHtml(dev.name)}${opts.source ? " — источник события" : ""}</title>
        ${
          opts.source
            ? `<circle class="dev-halo" r="12">
                 <animate attributeName="r" values="11;20;11" dur="1.8s" repeatCount="indefinite"/>
                 <animate attributeName="opacity" values="0.5;0;0.5" dur="1.8s" repeatCount="indefinite"/>
               </circle>`
            : ""
        }
        <circle class="dev-bg" r="10.5"/>
        <g class="dev-glyph" transform="scale(0.8)">${DEVICE_GLYPH[dev.type] || DEVICE_GLYPH.camera}</g>
      </g>
    `;
  }

  function renderMap() {
    const ev = selected();
    if (!ev) {
      $("mapCaption").textContent = "Место сработки";
      $("mapRoot").innerHTML = `<div class="empty">Инцидент не выбран</div>`;
      return;
    }
    const planId = eventPlan(ev);
    const plan = PLANS[planId] || PLANS.mall;
    const source = eventSource(ev);
    $("mapCaption").textContent = plan.title;

    const ids = [...new Set([...(ev.deviceIds || []), ...(ev.cameras || [])])].filter(
      (id) => DEVICE_POS[id] && DEVICE_POS[id].plan === planId
    );
    // Источник рисуем последним, чтобы пульсация была поверх остальных значков.
    const ordered = ids.filter((id) => id !== source).concat(ids.includes(source) ? [source] : []);
    const markers = ordered
      .map((id) => deviceMarker(id, { source: id === source, active: id === state.activeCam }))
      .join("");

    const srcDev = source ? devView(source) : null;
    const camCount = (ev.cameras || []).length;

    $("mapRoot").innerHTML = `
      <svg class="map-svg" viewBox="0 0 400 260" role="img" aria-label="План: ${escapeHtml(plan.title)}">
        ${plan.svg}
        ${markers}
      </svg>
      <div class="map-legend">
        <span class="map-legend-src">${
          srcDev ? `${escapeHtml(srcDev.typeLabel)}: ${escapeHtml(srcDev.name)}` : "Источник не указан"
        }</span>
        <span class="map-legend-cams">${camCount ? `Камер в зоне: ${camCount}` : "Камеры не привязаны"}</span>
      </div>
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
    $("statusSla").textContent = ev.status === "closed" ? "" : `Осталось по нормативу ${fmtSla(ev.slaSec)}`;
  }

  function fmtSla(sec) {
    const m = Math.floor(Math.max(0, sec) / 60);
    const s = Math.max(0, sec) % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function renderAll() {
    const ws = $("workspace");
    if (state.mode !== "work" && state.mobileView === "card") state.mobileView = "queue";
    ws.dataset.mode = state.mode;
    ws.dataset.view = state.mobileView;
    applyLayoutState();
    renderTopbar();
    renderGroups();
    if (state.mode === "queue") {
      renderEvents();
    } else {
      renderWorkHeader(selected());
      renderScenario();
    }
    applyMediaLayout();
    renderVideo();
    renderMap();
    renderStatus();
    $("breakBanner").hidden = !state.onBreak;
  }

  function syncToggle(btn, on, iconOn, iconOff, titleOn, titleOff) {
    btn.classList.toggle("on", on);
    btn.setAttribute("aria-pressed", String(on));
    btn.querySelector(".material-symbols-outlined").textContent = on ? iconOn : iconOff;
    btn.title = on ? titleOn : titleOff;
  }

  function renderTopbar() {
    const groupsLocked = state.mode === "work" && !narrowQuery.matches;
    const groupsBtn = $("toggleGroups");
    syncToggle(
      groupsBtn,
      state.groupsOn,
      "left_panel_close",
      "left_panel_open",
      "Скрыть панель групп",
      "Показать панель групп"
    );
    groupsBtn.disabled = groupsLocked;
    if (groupsLocked) groupsBtn.title = "Панель групп скрыта на время обработки инцидента";
    [...$("mobileNav").children].forEach((b) => {
      const on = b.dataset.view === state.mobileView;
      b.classList.toggle("active", on);
      if (on) b.setAttribute("aria-current", "page");
      else b.removeAttribute("aria-current");
      if (b.dataset.view === "card") b.disabled = state.mode !== "work";
    });
    $("navQueueCount").textContent = String(state.events.filter((e) => e.status !== "closed").length);
    syncToggle(
      $("toggleMedia"),
      state.mediaOn,
      "right_panel_close",
      "right_panel_open",
      "Скрыть видеомонитор и карту",
      "Показать видеомонитор и карту"
    );
    const mode = mediaMode();
    syncToggle(
      $("videoFull"),
      state.full === "video",
      "close_fullscreen",
      "open_in_full",
      "Свернуть видеомонитор (Esc)",
      "Развернуть видеомонитор на всю рабочую область"
    );
    syncToggle(
      $("mapFull"),
      state.full === "map",
      "close_fullscreen",
      "open_in_full",
      "Свернуть карту (Esc)",
      "Развернуть карту на всю рабочую область"
    );
    $("videoFull").disabled = mode === "map";
    $("mapFull").disabled = mode === "video";
    $("dutyBadge").textContent = state.onBreak ? "Перерыв" : "На смене";
    $("dutyBadge").classList.toggle("off", state.onBreak);
    $("breakBtnLabel").textContent = state.onBreak ? "Вернуться на смену" : "Уйти на перерыв";
  }

  // При переходе к другому инциденту показываем камеру, ближайшую к источнику события.
  function focusCameras(ev) {
    if (!ev || !ev.cameras || !ev.cameras.length) return;
    if (state.camFor !== ev.id || !ev.cameras.includes(state.activeCam)) {
      state.activeCam = ev.cameras[0];
      state.camFor = ev.id;
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
    state.mobileView = "card";
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
    state.page = pageOfEvent(state.selectedId);
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
    state.mobileView = "card";
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

  function closeDrawer() {
    state.groupsOn = false;
    renderAll();
    $("toggleGroups").focus();
  }

  function closeMenus() {
    const open = [...document.querySelectorAll(".menu")].filter((m) => !m.querySelector(".menu-pop").hidden);
    open.forEach((menu) => {
      menu.querySelector(".menu-pop").hidden = true;
      menu.querySelector("[aria-haspopup]").setAttribute("aria-expanded", "false");
    });
    return open[0] || null;
  }

  /* ===== Сплиттеры: группы | очередь-карточка | видеомонитор + карта ===== */

  const LAYOUT_VARS = { groups: "--w-groups-user", media: "--w-media-user", video: "--h-video-user" };
  const LAYOUT_MIN = { groups: 200, media: 280, stage: 320, video: 160, map: 160 };
  const SPLIT_W = 1;

  function setLayoutVar(key, px) {
    document.documentElement.style.setProperty(LAYOUT_VARS[key], `${Math.round(px)}px`);
  }

  function storeLayout() {
    const style = document.documentElement.style;
    const data = {};
    Object.entries(LAYOUT_VARS).forEach(([key, name]) => {
      const px = parseFloat(style.getPropertyValue(name));
      if (px > 0) data[key] = Math.round(px);
    });
    try {
      localStorage.setItem("im-layout", JSON.stringify(data));
    } catch (err) {
      /* приватный режим: раскладка живёт только до перезагрузки */
    }
  }

  function restoreLayout() {
    let data = {};
    try {
      data = JSON.parse(localStorage.getItem("im-layout") || "{}") || {};
    } catch (err) {
      data = {};
    }
    Object.keys(LAYOUT_VARS).forEach((key) => {
      const px = Number(data[key]);
      if (px > 0) setLayoutVar(key, px);
    });
  }

  // Панель не уже своего минимума и не отбирает место у центральной колонки
  function splitRange(key) {
    if (key === "video") {
      const stack = $("panelMedia").getBoundingClientRect().height;
      return [LAYOUT_MIN.video, stack - LAYOUT_MIN.map - SPLIT_W];
    }
    const ws = $("workspace").getBoundingClientRect().width;
    const other = key === "groups" ? $("panelMedia") : $("panelGroups");
    const busy = other.getBoundingClientRect().width;
    return [LAYOUT_MIN[key], ws - busy - LAYOUT_MIN.stage - SPLIT_W * 2];
  }

  function splitSize(key) {
    if (key === "video") return $("panelVideo").getBoundingClientRect().height;
    return $(key === "groups" ? "panelGroups" : "panelMedia").getBoundingClientRect().width;
  }

  function clampSize(v, min, max) {
    return max < min ? min : Math.min(Math.max(v, min), max);
  }

  function bindSplitter(id, key, axis) {
    const el = $(id);
    el.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      const [min, max] = splitRange(key);
      const from = axis === "col" ? e.clientX : e.clientY;
      const size = splitSize(key);
      // Панель справа растёт влево, поэтому знак смещения зеркальный
      const sign = key === "media" ? -1 : 1;
      el.setPointerCapture(e.pointerId);
      el.classList.add("dragging");
      document.body.dataset.resize = axis;
      const move = (ev) => {
        const to = axis === "col" ? ev.clientX : ev.clientY;
        setLayoutVar(key, clampSize(size + (to - from) * sign, min, max));
      };
      const stop = () => {
        el.classList.remove("dragging");
        delete document.body.dataset.resize;
        el.removeEventListener("pointermove", move);
        el.removeEventListener("pointerup", stop);
        el.removeEventListener("pointercancel", stop);
        storeLayout();
      };
      el.addEventListener("pointermove", move);
      el.addEventListener("pointerup", stop);
      el.addEventListener("pointercancel", stop);
    });
    el.addEventListener("dblclick", () => {
      document.documentElement.style.removeProperty(LAYOUT_VARS[key]);
      storeLayout();
    });
    el.addEventListener("keydown", (e) => {
      const dir = { ArrowLeft: -1, ArrowUp: -1, ArrowRight: 1, ArrowDown: 1 }[e.key];
      if (!dir) return;
      e.preventDefault();
      e.stopPropagation();
      const [min, max] = splitRange(key);
      const step = e.shiftKey ? 48 : 16;
      setLayoutVar(key, clampSize(splitSize(key) + (key === "media" ? -dir : dir) * step, min, max));
      storeLayout();
    });
  }

  function bind() {
    restoreLayout();
    bindSplitter("splitGroups", "groups", "col");
    bindSplitter("splitMedia", "media", "col");
    bindSplitter("splitVideo", "video", "row");
    $("themeToggle").addEventListener("click", () => {
      applyTheme(state.themeMode === "light" ? "dark" : "light");
    });
    $("toggleGroups").addEventListener("click", () => {
      state.groupsOn = !state.groupsOn;
      applyLayoutState();
      renderTopbar();
    });
    $("toggleMedia").addEventListener("click", () => {
      state.mediaOn = !state.mediaOn;
      if (!state.mediaOn) state.full = null;
      applyLayoutState();
      renderTopbar();
    });
    $("videoFull").addEventListener("click", () => toggleFull("video"));
    $("mapFull").addEventListener("click", () => toggleFull("map"));
    $("backToQueue").addEventListener("click", () => backToQueue());
    $("eventFilter").addEventListener("change", (e) => {
      state.filter = e.target.value;
      state.page = 1;
      renderEvents();
    });
    $("eventSearch").addEventListener("input", (e) => {
      state.search = e.target.value;
      state.page = 1;
      renderEvents();
    });
    $("mobileNav").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-view]");
      if (!btn || btn.disabled) return;
      state.mobileView = btn.dataset.view;
      if (state.groupsOn && narrowQuery.matches) state.groupsOn = false;
      renderAll();
    });
    $("groupsScrim").addEventListener("click", closeDrawer);
    $("groupsClose").addEventListener("click", closeDrawer);
    $("eventsPager").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-page]");
      if (!btn || btn.disabled) return;
      state.page = Number(btn.dataset.page);
      renderEvents();
      $("eventsList").scrollTop = 0;
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
      state.page = 1;
      if (narrowQuery.matches) state.groupsOn = false;
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
      const esc = e.target.closest("[data-escalate]");
      if (esc) {
        openEscalateModal(state.events.find((x) => x.id === esc.dataset.escalate));
        return;
      }
      const row = e.target.closest("[data-id]");
      if (!row || row.dataset.id === state.selectedId) return;
      state.selectedId = row.dataset.id;
      focusCameras(selected());
      renderEvents();
      renderGroups();
      applyMediaLayout();
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
    $("scenarioRoot").addEventListener("keydown", (e) => {
      if (e.key !== "Enter" && e.key !== " ") return;
      const crumb = e.target.closest("[data-crumb]");
      if (!crumb) return;
      e.preventDefault();
      e.stopPropagation();
      crumb.click();
    });
    $("scenarioRoot").addEventListener("click", (e) => {
      const ev = selected();
      if (!ev) return;
      const crumb = e.target.closest("[data-crumb]");
      if (crumb) {
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
        openEscalateModal(ev);
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
      closeMenus();
      toast(state.onBreak ? "Перерыв. Новые события не назначаются" : "Вы снова на смене");
      renderAll();
    });
    $("hotkeysBtn").addEventListener("click", () => {
      closeMenus();
      $("modalHotkeys").hidden = false;
    });
    document.querySelectorAll(".menu").forEach((menu) => {
      const trigger = menu.querySelector("[aria-haspopup]");
      const pop = menu.querySelector(".menu-pop");
      trigger.addEventListener("click", () => {
        const willOpen = pop.hidden;
        closeMenus();
        pop.hidden = !willOpen;
        trigger.setAttribute("aria-expanded", String(willOpen));
      });
      menu.addEventListener("click", (e) => {
        const item = e.target.closest("[data-doc]");
        if (!item) return;
        e.preventDefault();
        closeMenus();
        showModal(item.dataset.doc);
      });
    });
    document.addEventListener("click", (e) => {
      if (!e.target.closest(".menu")) closeMenus();
    });
    document.querySelectorAll("[data-close]").forEach((btn) => {
      btn.addEventListener("click", () => {
        $(btn.dataset.close).hidden = true;
      });
    });
    $("escalateConfirm").addEventListener("click", () => {
      const id = state.escalateId || state.selectedId;
      const ev = state.events.find((e) => e.id === id);
      if (!ev || !canManualEscalate(ev)) return;
      const ok = escalateEvent(ev, {
        target: $("escalateTarget").value,
        reason: $("escalateReason").value,
      });
      $("modalEscalate").hidden = true;
      $("escalateReason").value = "";
      state.escalateId = null;
      if (!ok) return;
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
    state.mobileView = "card";
    renderAll();
  }

  function onKey(e) {
    if (e.target.matches("input, textarea, select")) return;
    if (e.key === "ArrowLeft") return stepCamera(-1);
    if (e.key === "ArrowRight") return stepCamera(1);
    if (e.key === "Escape") {
      const openMenu = closeMenus();
      if (openMenu) {
        openMenu.querySelector("[aria-haspopup]").focus();
        return;
      }
      const openModal = document.querySelector(".modal:not([hidden])");
      if (openModal) {
        openModal.hidden = true;
        return;
      }
      if (state.full) {
        toggleFull(state.full);
        return;
      }
      if (state.groupsOn && narrowQuery.matches) {
        closeDrawer();
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
      if (canManualEscalate(ev)) openEscalateModal(ev);
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
    const stamp = nowStamp();
    $("clock").textContent = stamp;
    $("clock").dateTime = stamp;
    let escalated = false;
    state.events.forEach((e) => {
      if (e.status === "closed") return;
      e.slaSec -= 1;
      if (canAutoEscalate(e) && escalateEvent(e, { auto: true, reason: SETTINGS.autoEscalate.reason })) {
        escalated = true;
        if (state.mode === "work" && state.selectedId === e.id) state.mode = "queue";
      }
    });
    if (escalated) {
      renderAll();
      return;
    }
    document.querySelectorAll("[data-sla]").forEach((el) => {
      const e = state.events.find((x) => x.id === el.dataset.sla);
      if (!e) return;
      el.textContent = `Норматив ${fmtSla(e.slaSec)}`;
      el.classList.toggle("late", e.slaSec < 120);
    });
    const ev = selected();
    if (ev && ev.status !== "closed") {
      const sla = $("scenarioRoot").querySelector(".sla");
      if (sla) {
        sla.textContent = `Норматив ${fmtSla(ev.slaSec)}`;
        sla.classList.toggle("late", ev.slaSec < 120);
      }
      $("statusSla").textContent = `Осталось по нормативу ${fmtSla(ev.slaSec)}`;
    }
  }, 1000);

  let savedTheme = "dark";
  try {
    savedTheme = localStorage.getItem("im-theme") || "dark";
  } catch (err) {
    savedTheme = "dark";
  }
  applyTheme(savedTheme);
  if (narrowQuery.matches) state.groupsOn = false;
  narrowQuery.addEventListener("change", (e) => {
    state.groupsOn = !e.matches;
    renderAll();
  });
  bind();
  renderAll();
})();
