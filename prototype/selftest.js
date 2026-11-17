/* Самопроверка прототипа. Запуск: открыть index.html?selftest.
   Проходит основные переходы через интерфейс, как оператор, и показывает отчёт.
   Без параметра ничего не делает. После прогона демо-данные в этой вкладке
   изменены — для чистого прототипа перезагрузите страницу без ?selftest.
   Для CI: на <html> ставится data-selftest="pass" или "fail", текст отчёта — в #selftest-log.
   Шаги, которые продолжают работу с инцидентом предыдущего шага, называют его третьим
   аргументом step(). Если он не прошёл, шаг не выполняется и пишется SKIP с первой причиной.
   После упавшего шага прототип возвращается в очередь и освобождает лимит активных,
   чтобы независимые шаги дальше не падали следом. */
(() => {
  // Что видел оператор в карточке или строке (§14.1, RULE-142) — тело запроса перехода служебным запросом стенда
  const seenBody = (c) => ({ expectedState: c.state, expectedAddressee: (c.addressee && c.addressee.id) || "", expectedPriority: c.priority, journalSeen: c.journalSeq });
  // Страница, открытая самопроверкой в узкой рамке: сообщает, шире ли она экрана, сколько места
  // над очередью занимают шапка и фильтры и работает ли кнопка «Фильтры» (BUG-50)
  if (new URLSearchParams(location.search).has("widthcheck")) {
    const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const height = (sel) => {
      const el = document.querySelector(sel);
      return el ? el.getBoundingClientRect().height : 0;
    };
    window.addEventListener("load", async () => {
      await pause(300);
      const wide = [...document.querySelectorAll("body *")]
        .filter((el) => el.getBoundingClientRect().right > innerWidth + 1)
        .slice(0, 3)
        .map((el) => el.id || el.className);
      const filters = Math.round(height("#panelEvents .panel-h") + height("#eventsToolbar"));
      const more = document.getElementById("eventsMoreBtn");
      const typesHidden = height("#eventsTypes") === 0;
      more.click();
      const typesShown = height("#eventsTypes") > 0 && more.getAttribute("aria-expanded") === "true";
      // Отметить один тип устройства — на кнопке число выбранных
      document.querySelector('[data-tb-toggle="deviceTypes"]').click();
      await pause(50);
      const box = document.querySelector('input[data-tb="deviceTypes"]');
      if (box) box.click();
      await pause(50);
      const count = document.getElementById("eventsMoreN");
      const counted = !count.hidden && count.textContent === "1";
      more.click();
      const closed = height("#eventsTypes") === 0;
      // Панель групп поверх узкого экрана — слой: Esc закрывает её, фокус — на кнопку панели (RULE-91)
      const ws = document.getElementById("workspace");
      const toggle = document.getElementById("toggleGroups");
      toggle.click();
      await pause(50);
      const drawerOpened = ws.dataset.groups === "on";
      // Длинные названия на узком экране не обрезаны до неразличимых (BUG-65): найденные — не длиннее двух
      // строк без потерь, текущее найденное — целиком
      const search = document.getElementById("groupSearch");
      const find = async (q) => {
        search.value = q;
        search.dispatchEvent(new Event("input", { bubbles: true }));
        await pause(50);
      };
      await find("Конференц-зал —");
      const cut = (el) => el.scrollHeight > el.clientHeight + 1 || el.scrollWidth > el.clientWidth + 1;
      const hits = [...document.querySelectorAll("#groupsList .tree-node:not(.hidden) > .node-content mark")].map((m) => m.closest(".node-text"));
      const names = { count: hits.length, cut: hits.filter(cut).map((el) => el.textContent) };
      await find("турникет");
      const current = document.querySelector("#groupsList .hit-current > .node-content .node-text");
      // В демо-данных нет названия длиннее двух строк — проверяется, что у текущего нет ограничения строк
      names.currentCut = !current || cut(current) || getComputedStyle(current).getPropertyValue("-webkit-line-clamp") !== "none";
      await find("");
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
      await pause(50);
      const drawer = { opened: drawerOpened, closed: ws.dataset.groups === "off", focus: document.activeElement === toggle };
      parent.postMessage(
        { widthcheck: true, width: innerWidth, scroll: document.documentElement.scrollWidth, wide, filters, more: { typesHidden, typesShown, counted, closed }, drawer, names },
        "*"
      );
    });
    return;
  }
  if (!new URLSearchParams(location.search).has("selftest")) return;

  const $ = (id) => document.getElementById(id);
  const errors = [];
  window.addEventListener("error", (e) => errors.push(e.message || "ошибка JS"));

  const results = [];
  // Встроенный сервер отвечает без задержки, а приложение не ждёт таймеров: паузы 40 мс после действия
  // и 100 мс после сброса стенда хватает с запасом. Дольше ждут только шаги с таймерами (плашки, часы)
  const wait = (ms = 40) => new Promise((resolve) => setTimeout(resolve, ms));
  const mode = () => $("workspace").dataset.mode;
  const root = () => $("scenarioRoot");
  const expect = (cond, msg) => {
    if (!cond) throw new Error(msg);
  };

  async function setFilter(value) {
    const select = $("eventFilter");
    select.value = value;
    select.dispatchEvent(new Event("change"));
    await wait();
  }

  // Недоступная кнопка действия помечена aria-disabled: она остаётся в фокусе и объясняет причину
  const off = (b) => b.disabled || b.getAttribute("aria-disabled") === "true";

  // Первая доступная кнопка перехода; ev — номер инцидента, если важен конкретный
  function button(scope, id, ev) {
    const list = [...scope.querySelectorAll(`[data-do="${id}"]`)];
    return list.find((b) => !off(b) && (!ev || b.dataset.ev === ev)) || null;
  }

  async function click(el) {
    el.click();
    await wait();
  }

  // Поле формы перехода по имени из машины: resultId, causeId, comment, targetId…
  const field = (name) => $("dialogFields").querySelector(`[data-field="${name}"]`);

  async function setField(name, value) {
    field(name).value = value;
    field(name).dispatchEvent(new Event("change", { bubbles: true }));
    await wait();
  }

  // Комментарий, который самопроверка вводит в формы. Латиницей: введённый оператором текст
  // не переводится, и проверка перевода не должна его считать
  const NOTE = "selftest";

  async function confirmDialog(text) {
    expect(!$("modalDialog").hidden, "форма перехода не открылась");
    const comment = field("comment");
    if (text && comment && !comment.closest("[data-field-box]").hidden) comment.value = text;
    await click($("dialogConfirm"));
  }

  // Остаток норматива закрытия в строке состояния карточки, в секундах
  function resolutionLeft() {
    const m = $("statusSla").textContent.match(/(\d+):(\d\d)/);
    return m ? Number(m[1]) * 60 + Number(m[2]) : null;
  }

  // Кнопка перехода у конкретного инцидента — на любой странице очереди
  async function buttonOnPages(id, ev) {
    let b = button($("eventsList"), id, ev);
    for (let page = 2; !b && page <= 20; page++) {
      const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
      if (!nav || nav.disabled) break;
      await click(nav);
      b = button($("eventsList"), id, ev);
    }
    return b;
  }

  // Строка инцидента в очереди — на любой странице
  async function rowOnPages(ev) {
    let row = $("eventsList").querySelector(`[data-id="${ev}"]`);
    for (let page = 2; !row && page <= 20; page++) {
      const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
      if (!nav || nav.disabled) break;
      await click(nav);
      row = $("eventsList").querySelector(`[data-id="${ev}"]`);
    }
    return row;
  }

  async function pressKey(key, mods) {
    document.body.dispatchEvent(new KeyboardEvent("keydown", Object.assign({ key, bubbles: true }, mods)));
    await wait();
  }

  // Идентификатор инцидента по номеру из эталонного набора: guid — UUID, на экране — номер
  const guidOf = (number) => window.IM_FIXTURE.incidents.find((i) => i.number === number).guid;
  // Инцидент набора в Торговом центре: площадка — группа устройств (§1), источник — в группе ТЦ или во вложенной
  function inMall(guid) {
    const fx = window.IM_FIXTURE;
    const find = (groups) => groups.reduce((hit, g) => hit || (g.name === "Торговый центр" ? g : null), null);
    const all = (g) => (g.devices || []).concat(...(g.groups || []).map(all));
    const inc = fx.incidents.find((i) => i.guid === guid);
    return Boolean(inc) && all(find(fx.sourceGroups)).includes(inc.devices[0]);
  }

  async function openOwn(id) {
    if (mode() === "work") return;
    await setFilter("mine");
    const b = button($("eventsList"), "open_card", id) || button($("eventsList"), "resume", id);
    expect(b, `${id} нет среди своих инцидентов`);
    await click(b);
    expect(mode() === "work", `карточка ${id} не открылась`);
  }

  // Итог каждого шага по имени и, для пропущенных, — шаг, из-за которого пропущен
  const status = {};
  const cause = {};

  // ?selftest&failfast — после первого падения остальные шаги не выполняются (PROC-17: мутации кода)
  const FAILFAST = new URLSearchParams(location.search).has("failfast");
  // Начало шага — записи колокольчика раньше него к шагу не относятся: журнал живёт дольше шага (§22.5)
  let stepAt = 0;
  async function step(name, fn, after) {
    stepAt = Date.now();
    if (FAILFAST && results.some((r) => !r.ok)) {
      status[name] = "skip";
      results.push({ ok: true, skipped: true, name, note: "пропущен: failfast" });
      return;
    }
    if (after && status[after] !== "ok") {
      cause[name] = status[after] === "skip" ? cause[after] : after;
      status[name] = "skip";
      results.push({ ok: true, skipped: true, name, note: `пропущен: зависит от «${cause[name]}»` });
      return;
    }
    const before = errors.length;
    let ok = true;
    let note = "";
    try {
      note = (await fn()) || "";
    } catch (err) {
      ok = false;
      note = err.message;
    }
    const errs = errors.slice(before);
    if (errs.length) {
      ok = false;
      note = `${note ? note + "; " : ""}ошибка JS: ${errs.join("; ")}`;
    }
    results.push({ ok, name, note });
    status[name] = ok ? "ok" : "fail";
    if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
    await wait();
    if (!ok) await recover();
  }

  // После падения: к очереди, с перерыва и после выхода — обратно, свои инциденты «В работе» — в очередь
  async function recover() {
    try {
      if (mode() === "work") await click($("backToQueue"));
      if (!$("breakBanner").hidden) await click($("breakBtn"));
      if (!$("signedOutBanner").hidden) await click($("signInBtn"));
      for (let i = 0; i < 5; i++) {
        await setFilter("mine");
        const open = button($("eventsList"), "open_card");
        if (!open) break;
        await click(open);
        const release = button(root(), "release");
        if (!release) break;
        await click(release);
        await confirmDialog(NOTE);
      }
      if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
    } catch (err) {
      results.push({ ok: false, name: "Уборка после упавшего шага", note: err.message });
    }
  }

  // Контраст текста с фоном по WCAG: фон — первый непрозрачный слой с наложением полупрозрачных
  function contrast(el) {
    const parse = (c) => {
      const n = (c.match(/[\d.]+/g) || []).map(Number);
      const srgb = c.startsWith("color(");
      const k = srgb ? 255 : 1;
      return { r: n[0] * k, g: n[1] * k, b: n[2] * k, a: n[3] == null ? 1 : n[3] };
    };
    const over = (top, base) => ({
      r: top.r * top.a + base.r * (1 - top.a),
      g: top.g * top.a + base.g * (1 - top.a),
      b: top.b * top.a + base.b * (1 - top.a),
    });
    const layers = [];
    for (let e = el; e; e = e.parentElement) {
      const c = parse(getComputedStyle(e).backgroundColor);
      if (c.a > 0) layers.push(c);
      if (c.a >= 1) break;
    }
    let bg = { r: 255, g: 255, b: 255 };
    layers.reverse().forEach((c) => (bg = over(c, bg)));
    const fg = over(parse(getComputedStyle(el).color), bg);
    const lum = ({ r, g, b }) => {
      const f = (v) => ((v /= 255) <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };
    const [hi, lo] = [lum(fg), lum(bg)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  }

  async function setTheme(theme) {
    if (document.documentElement.dataset.theme !== theme) await click($("themeToggle"));
    // Цвета темы меняются плавно (transition): замерять — после конца перехода. В обычном окне время идёт
    // по-настоящему, и без ожидания контраст замерялся посреди перехода. Пауза — на остаток самого долгого перехода:
    // ожидание finished в безоконном Chrome съедало по 6–10 с виртуального времени
    const left = document.getAnimations().filter((a) => a instanceof CSSTransition).map((a) => {
      const t = a.effect.getTiming();
      return t.duration + t.delay - (a.currentTime || 0);
    });
    await wait(Math.max(0, ...left) + 20);
  }

  // Шаги сценария: подтвердить, выбрать первый вариант; ответ уходит по «Далее»
  async function answerCurrentStep() {
    const confirm = root().querySelector("[data-confirm]");
    if (confirm && !confirm.classList.contains("on")) await click(confirm);
    const radios = root().querySelectorAll('input[type="radio"][data-ans]');
    if (radios.length && ![...radios].some((r) => r.checked)) await click(radios[0]);
  }

  // Непереведённые строки: текст и подсказки с кириллицей, включая скрытые справочные окна.
  // Не считаются: уведомления, созданные до смены языка, и карточка, оставшаяся
  // от прошлого инцидента, пока открыта очередь, — они не перерисовываются.
  // Ключ каталога строк на экране вместо текста (§14.9): workflow.<область>.…
  const KEY_ON_SCREEN = /\bworkflow\.[a-z_]+\./;

  // Русский текст или ключ каталога вместо текста — на другом языке интерфейса ни того ни другого быть не должно
  const findRussian = () => findText(/[Ѐ-ӿ]|\bworkflow\.[a-z_]+\./);
  const findKeys = () => findText(KEY_ON_SCREEN);

  function findText(cyr) {
    const skip = (el) =>
      // Записи колокольчика — на языке, на котором записаны (§22.5); панель закрыта — их не видно
      el.closest("[data-i18n-skip], script, style, #selftest-report, #toasts, #toastList, #bellList") ||
      (el.closest("#bellPanel") && $("bellPanel").hidden) ||
      (el.closest("#modalDialog") && $("modalDialog").hidden) ||
      (el.closest("#adminTable, #adminTabs, #adminNote") && $("modalAdmin").hidden) ||
      (el.closest("#shiftScreen") && $("shiftScreen").hidden) ||
      (el.closest("#panelScenario") && mode() !== "work");
    const found = new Set();
    // Одна и та же строка для разных инцидентов и номеров считается один раз
    const add = (text) => found.add(text.trim().replace(/INC-\d+/g, "INC-…").replace(/\d+/g, "N"));
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (cyr.test(node.nodeValue) && !skip(node.parentElement)) add(node.nodeValue);
    }
    document.body.querySelectorAll("[title], [placeholder], [aria-label]").forEach((el) => {
      if (skip(el)) return;
      ["title", "placeholder", "aria-label"].forEach((attr) => {
        const value = el.getAttribute(attr);
        if (value && cyr.test(value)) add(value);
      });
    });
    if (cyr.test(document.title)) add(document.title);
    return [...found];
  }

  async function checkLanguage(lang) {
    const select = $("langSelect");
    const original = select.value;
    select.value = lang;
    select.dispatchEvent(new Event("change"));
    await wait();
    const leftovers = new Set(findRussian());
    // Карточка тоже должна быть переведена: открываем завершённый инцидент на просмотр
    await setFilter("done");
    const view = button($("eventsList"), "view");
    if (view) {
      await click(view);
      findRussian().forEach((s) => leftovers.add(s));
      await click($("backToQueue"));
    }
    // Настройки администратора: каждая вкладка
    if (!$("adminBtn").hidden) {
      await click($("adminBtn"));
      for (const tab of [...$("adminTabs").querySelectorAll("[data-admin-tab]")].map((b) => b.dataset.adminTab)) {
        await click($("adminTabs").querySelector(`[data-admin-tab="${tab}"]`));
        findRussian().forEach((s) => leftovers.add(s));
      }
      await click(document.querySelector('[data-close="modalAdmin"]'));
    }
    // Экран «Смена и статистика» (§23)
    if (!$("screenTabs").hidden) {
      await click($("tabShift"));
      for (let i = 0; i < 40 && !$("shiftTable").querySelector("tbody tr"); i++) await wait(100);
      findRussian().forEach((s) => leftovers.add(s));
      await click($("screenTabs").querySelector('[data-screen="queue"]'));
    }
    await setFilter("open");
    select.value = original;
    select.dispatchEvent(new Event("change"));
    await wait();
    const list = [...leftovers];
    expect(!list.length, `не переведено ${list.length}: «${list.slice(0, 8).join("», «")}»${list.length > 8 ? " …" : ""}`);
  }

  // Самопроверка написана под лимит активных 1, а в машине — без ограничения: стенд задаёт 1 на весь прогон.
  // extra — изменения стенда шага (JSON Merge Patch): свой limits заменяет этот
  async function standReset(extra) {
    const body = Object.assign({}, extra);
    body.workflowPatch = Object.assign({ limits: { maxActive: 1 } }, body.workflowPatch);
    return window.IM_SELFTEST_API.raw("POST", "/test/reset", body);
  }

  async function run() {
    if (window.IM_SELFTEST_API) {
      await standReset({ fixture: "demo" });
      await wait(400);
    }
    let closedId = null;
    let workId = null;
    let acceptedId = null;
    let acceptedLeft = null;
    let freshId = null;

    await step("Взять новое событие", async () => {
      await setFilter("open");
      const b = button($("eventsList"), "claim");
      expect(b, "нет доступной кнопки «Взять»");
      closedId = b.dataset.ev;
      await click(b);
      expect(mode() === "work", "карточка не открылась");
      // Одиночная отметка до нажатия — утверждение «Подтверждаю», верное и до отметки, и после (BUG-69)
      const confirm = root().querySelector("[data-confirm]");
      if (confirm) expect(!confirm.classList.contains("on") && /Подтверждаю/.test(confirm.textContent), `до отметки на кнопке «${confirm.textContent.trim()}»`);
      // Шаги впереди серым (RULE-95): на экране столько шагов, сколько M в «Шаг N из M»; на шаги впереди не перейти
      const m = $("statusSteps").textContent.match(/из (\d+)/);
      // «Итог» — без номера, в M не входит
      const crumbs = root().querySelectorAll(".crumb:not(.summary-crumb)");
      expect(m && crumbs.length === Number(m[1]), `шагов на экране ${crumbs.length}, а в строке состояния «${$("statusSteps").textContent}»`);
      expect([...root().querySelectorAll(".crumb.ahead")].every((c) => c.dataset.crumb === undefined) && root().querySelector(".crumb.ahead"), "шагов впереди нет или на них можно перейти");
      return closedId;
    });

    await step("Нижняя панель карточки — один ряд: главные действия машины, остальные в «Ещё», «Закрыть без обработки» последним; «Комментарий» в шапке", async () => {
      const stand = window.IM_SELFTEST_API;
      const W = window.IM_WORKFLOW;
      const ui = (id) => (W.transitions.find((x) => x.id === id) || {}).ui || {};
      const card = await stand.get(`/operator/incidents/${encodeURIComponent(closedId)}`);
      const acts = card.actions.filter((a) => a.kind === "transition");
      expect(acts.every((a) => a.placement === (ui(a.id).placement || "menu")), "у действий сервера нет placement из машины");
      const ids = (sel) => [...root().querySelectorAll(sel)].map((b) => b.dataset.do);
      const want = (p) => acts.filter((a) => (ui(a.id).placement || "menu") === p).map((a) => a.id);
      const bottom = ids(".work-acts > [data-do]");
      expect(JSON.stringify(bottom) === JSON.stringify(want("primary")), `в нижней панели ${bottom.join(", ")}, ожидались ${want("primary").join(", ")}`);
      expect(bottom.includes("transfer"), "«Передать» не в нижней панели");
      const more = root().querySelector("#moreActs");
      expect(more && more.getAttribute("aria-haspopup") === "menu", "нет кнопки «Ещё»");
      const menu = ids(".more-menu [role=menuitem]:not(.more-primary)");
      const rest = want("menu");
      expect(menu.length === rest.length && rest.every((id) => menu.includes(id)), `в меню ${menu.join(", ")}, ожидались ${rest.join(", ")}`);
      expect(menu[menu.length - 1] === "close" && ui("close").danger, `последним в меню ${menu[menu.length - 1]}`);
      expect(root().querySelector(".more-menu [role=separator] + [data-do=close]"), "перед «Закрыть без обработки» нет разделителя");
      expect(!root().querySelector(".work-bottom [data-do=comment]") && root().querySelector(".incident-head [data-do=comment]"), "«Комментарий» не в шапке карточки");
      // Один ряд: всё на одной линии
      const box = (sel) => root().querySelector(sel).getBoundingClientRect();
      const line = ["#backToQueue", ".work-acts", "#moreActs", "#stepBack", "#stepNext"].map((s) => Math.round(box(s).top + box(s).height / 2));
      expect(Math.max(...line) - Math.min(...line) < 6, `нижняя панель не в один ряд: ${line.join(", ")}`);
      expect(!root().querySelector("#stepBack").classList.contains("primary") && root().querySelector("#stepNext").classList.contains("primary"), "акцентная — не только «Далее»");
      // Клавиатура: Enter открывает, стрелка — следующий пункт, Esc закрывает и возвращает фокус на «Ещё»
      const pop = root().querySelector(".more-menu");
      more.focus();
      more.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
      await wait(30);
      expect(!pop.hidden && more.getAttribute("aria-expanded") === "true", "Enter не открыл меню");
      const items = [...pop.querySelectorAll("[role=menuitem]")].filter((b) => b.offsetParent);
      expect(document.activeElement === items[0], "фокус не на первом пункте меню");
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
      expect(document.activeElement === items[1], "стрелка вниз не перевела фокус");
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
      await wait(30);
      expect(pop.hidden && document.activeElement === root().querySelector("#moreActs"), "Esc не закрыл меню или фокус не вернулся на «Ещё»");
      return `${bottom.join(", ")} | ${menu.join(", ")}`;
    });

    await step(
      "Камера и план — из ответа сервера: картинка камеры, источник на плане",
      async () => {
        await openOwn(closedId);
        expect($("videoStage").querySelector(".cam-scene"), "нет картинки камеры");
        expect($("mapRoot").querySelector(".dev-marker.is-source"), "на плане нет источника события");
        const caption = $("mapCaption").textContent.trim();
        expect(caption && caption !== "Место сработки", `подпись плана: «${caption}»`);
        return caption;
      },
      "Взять новое событие"
    );

    await step(
      "Журнал карточки — текстом из каталога строк, а не ключами (§14.9, RULE-66)",
      async () => {
        await openOwn(closedId);
        // Журнал — строкой под кнопками: последняя запись видна сразу, весь — по нажатию, Esc сворачивает
        const bar = root().querySelector("[data-log-toggle]");
        expect(bar && /Взято в работу/.test(bar.textContent), `в строке журнала не последняя запись: «${bar ? bar.textContent.trim() : "нет строки"}»`);
        await click(bar);
        const items = [...root().querySelectorAll(".log-pop li")].map((li) => li.textContent.replace(/\s+/g, " ").trim());
        expect(items.length, "журнал не раскрылся");
        document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
        await wait(100);
        expect(!root().querySelector(".log-pop") && mode() === "work", "Esc не свернул журнал или закрыл карточку");
        expect(!items.some((x) => /workflow\./.test(x)), `в журнале ключ вместо текста: «${items.find((x) => /workflow\./.test(x))}»`);
        expect(/Взято в работу/.test(items[items.length - 1]), `последняя запись: «${items[items.length - 1]}»`);
        return items[items.length - 1];
      },
      "Взять новое событие"
    );

    await step(
      "На экране нет ключей каталога вместо текста: очередь, карточка, настройки (§14.9, RULE-66)",
      async () => {
        const found = new Set(findKeys());
        if (mode() === "work") await click($("backToQueue"));
        findKeys().forEach((x) => found.add(x));
        await openOwn(closedId);
        findKeys().forEach((x) => found.add(x));
        if (!$("adminBtn").hidden) {
          await click($("adminBtn"));
          for (const tab of [...$("adminTabs").querySelectorAll("[data-admin-tab]")].map((b) => b.dataset.adminTab)) {
            await click($("adminTabs").querySelector(`[data-admin-tab="${tab}"]`));
            findKeys().forEach((x) => found.add(x));
          }
          await click(document.querySelector('[data-close="modalAdmin"]'));
        }
        const list = [...found];
        expect(!list.length, `ключи вместо текста: «${list.slice(0, 6).join("», «")}»`);
        return "нет";
      },
      "Взять новое событие"
    );

    await step("Ответ с вариантами сохраняется после «Далее»", async () => {
      await openOwn(closedId);
      for (let i = 0; i < 6; i++) {
        const radios = root().querySelectorAll('input[type="radio"][data-ans]');
        if (radios.length >= 2) {
          const n = Number(root().querySelector(".crumb.current .crumb-n").textContent);
          const picked = radios[1].closest("label").textContent.trim();
          await click(radios[1]);
          await click($("stepNext"));
          const saved = root().querySelectorAll(".crumb")[n - 1].querySelector(".crumb-ans");
          const text = saved ? saved.textContent.trim() : "";
          expect(text === picked, `выбран вариант «${picked}», после «Далее» записан «${text}»`);
          return `шаг ${n}`;
        }
        await answerCurrentStep();
        expect($("stepNext") && !off($("stepNext")), "кнопка «Далее» недоступна");
        await click($("stepNext"));
      }
      throw new Error("в сценарии не нашлось шага с вариантами");
    }, "Взять новое событие");

    await step("«Назад» и «Далее» недоступны — с причиной по нажатию, как остальные кнопки (BUG-91)", async () => {
      // Новый инцидент на просмотре: первый шаг, дальше шагов нет — обе кнопки недоступны
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
      const row = [...$("eventsList").querySelectorAll(".event")].find((r) => r.querySelector('[data-do="claim"]') && button(r, "view"));
      expect(row, "нет нового инцидента, который можно посмотреть");
      await click(button(row, "view"));
      expect(mode() === "work", "карточка на просмотр не открылась");
      const lastToast = () => ($("toasts").lastElementChild || {}).textContent || "";
      try {
        for (const [id, why] of [
          ["stepBack", "Это первый шаг"],
          ["stepNext", "Дальше шагов пока нет: сценарий ещё не пройден"],
        ]) {
          const b = $(id);
          expect(b && off(b) && !b.disabled, `«${b && b.textContent.trim()}» — не aria-disabled или disabled`);
          expect(b.title === why, `причина «${b.textContent.trim()}»: «${b.title}»`);
          await click(b);
          expect(lastToast() === why, `по нажатию «${b.textContent.trim()}» — «${lastToast()}»`);
        }
      } finally {
        await click($("backToQueue"));
      }
      return "первый шаг; дальше шагов нет";
    });

    await step("Невыданный ответ на пройденном шаге не остаётся после ухода с шага: в поле — записанный (BUG-70)", async () => {
      await openOwn(closedId);
      const count = root().querySelectorAll(".crumb").length;
      for (let n = 1; n <= count; n++) {
        const crumb = root().querySelectorAll(".crumb")[n - 1];
        if (crumb.dataset.crumb === undefined) continue;
        await click(crumb);
        const radios = [...root().querySelectorAll('input[type="radio"][data-ans]')];
        const saved = radios.find((r) => r.checked);
        if (!saved) continue;
        // Выбрать другой вариант и уйти на соседний шаг пути, не нажимая «Далее»
        await click(radios.find((r) => !r.checked));
        await click(n > 1 ? $("stepBack") : $("stepNext"));
        await click(root().querySelectorAll(".crumb")[n - 1]);
        const now = root().querySelector('input[type="radio"][data-ans]:checked');
        expect(now && now.value === saved.value, `в поле «${now && now.value}», а записан «${saved.value}»`);
        return `шаг ${n}: ${saved.value}`;
      }
      throw new Error("на пути нет пройденного шага с вариантами");
    }, "Ответ с вариантами сохраняется после «Далее»");

    await step("Макрос по ответу сценария: переответ «Реальная» на пройденном шаге запускает макрос, на шаге — «Запущено» (§14.5)", async () => {
      await openOwn(closedId);
      const count = root().querySelectorAll(".crumb").length;
      for (let n = 1; n <= count; n++) {
        const crumb = root().querySelectorAll(".crumb")[n - 1];
        if (crumb.dataset.crumb !== undefined) await click(crumb);
        const radios = root().querySelectorAll('input[type="radio"][data-ans]');
        if (!radios.length) continue;
        // Пройденный шаг можно переответить (revisitable): первый вариант запускает макрос площадки
        expect(!radios[0].checked, "первый вариант уже выбран — переответа не будет");
        await click(radios[0]);
        await click($("stepNext"));
        await click($("stepBack"));
        const launched = root().querySelector(".step-card .macro-row .btn.ok");
        expect(launched && /Запущено/.test(launched.textContent), `ответ «${radios[0].value}» не запустил макрос`);
        return `шаг ${n}: ${launched.textContent.trim()}`;
      }
      throw new Error("на пути сценария нет шага с вариантами");
    }, "Ответ с вариантами сохраняется после «Далее»");

    await step("Завершить инцидент по сценарию: ответ на последний шаг ведёт на «Итог», форма не открывается; «Назад» — к последнему шагу, «Далее» — снова «Итог»; «Завершить инцидент» закрывает «Обработан» (§7)", async () => {
      await openOwn(closedId);
      const finish = () => root().querySelector("[data-finish]");
      for (let i = 0; i < 10; i++) {
        await answerCurrentStep();
        const next = $("stepNext");
        expect(next && !off(next), "сценарий не проходится до конца");
        await click(next);
        await wait(200);
        if (!finish()) continue;
        expect($("modalDialog").hidden, "после последнего шага открылась форма");
        expect(root().querySelector(".summary-crumb.current"), "«Итог» в ленте шагов не текущий");
        expect(off($("stepNext")), "на «Итоге» «Далее» доступна");
        expect(!finish().disabled, "«Завершить инцидент» недоступна");
        await click($("stepBack"));
        const [, at, of] = $("statusSteps").textContent.match(/Шаг (\d+) из (\d+)/) || [];
        expect(at && at === of && !finish(), `«Назад» с «Итога» — не на последний шаг: «${$("statusSteps").textContent}»`);
        expect(!off($("stepNext")), "на последнем шаге пройденного сценария «Далее» к «Итогу» недоступна");
        await click($("stepNext"));
        expect(finish(), "«Далее» с последнего шага не вернула на «Итог»");
        const note = root().querySelector("[data-summary-comment]");
        note.value = NOTE;
        note.dispatchEvent(new Event("input", { bubbles: true }));
        await click(finish());
        await wait(200);
        expect(mode() === "queue", "после «Завершить инцидент» карточка не закрылась");
        const card = await window.IM_SELFTEST_API.get(`/operator/incidents/${encodeURIComponent(closedId)}`);
        expect(card.closeResultId === "processed" && card.result === NOTE, `закрыт «${card.closeResultId}» с комментарием «${card.result}»`);
        return closedId;
      }
      throw new Error("последний шаг так и не наступил");
    }, "Макрос по ответу сценария: переответ «Реальная» на пройденном шаге запускает макрос, на шаге — «Запущено» (§14.5)");

    // Поле текущего шага — ответ, который карточка отправит по «Далее» (кнопка шага отправляет сама)
    async function fillStep(step) {
      const one = (sel) => root().querySelector(sel);
      const put = async (el, value, type) => {
        el.value = value;
        el.dispatchEvent(new Event(type, { bubbles: true }));
        await wait();
      };
      if (step.type === "Message") return click(one("[data-press]"));
      if (step.type === "RadioButton") return click(one('input[type="radio"][data-ans]'));
      if (step.type === "Select") {
        // В каждом списке — первый вариант; карточка перерисовывается после каждой отметки — искать заново
        for (const list of step.view.lists) {
          const box = one(`[data-list="${step.id}"][data-list-id="${list.id}"]`);
          if (!box.checked) await click(box);
        }
        return null;
      }
      if (step.type === "Checkbox" && one("[data-confirm]")) return one("[data-confirm].on") ? null : click(one("[data-confirm]"));
      if (step.type === "Checkbox") return click(one("[data-check]"));
      if (step.type === "Comment" && one("textarea[data-ans]")) return put(one("textarea[data-ans]"), NOTE, "input");
      if (step.type === "Datetime") {
        const el = one("[data-when]");
        return put(el, { date: "2026-10-19", time: "14:30", "datetime-local": "2026-10-19T14:30" }[el.type], "change");
      }
      if (step.type === "Image" && one("[data-snap]")) return click(one("[data-snap]"));
      if (step.type === "Image" && one("[data-file]")) {
        const files = new DataTransfer();
        files.items.add(new File(["selftest"], "selftest.png", { type: "image/png" }));
        one("[data-file]").files = files.files;
        one("[data-file]").dispatchEvent(new Event("change", { bubbles: true }));
        // Файл читается асинхронно: ответ готов, когда карточка показывает вложение
        const attached = () => /Фото: 1/.test((one(".step-card .macro-row") || {}).textContent || "");
        for (let k = 0; k < 25 && !attached(); k++) await wait();
        return expect(attached(), "файл не прикрепился");
      }
      return null;
    }
    const loadScript = (src) =>
      new Promise((done, fail) => {
        const el = Object.assign(document.createElement("script"), { src, onload: done, onerror: () => fail(new Error(`не загрузился ${src}`)) });
        document.head.appendChild(el);
      });

    await step("Сценарий со всеми типами шагов (showcase машины сценариев) проходится в карточке: отметки, выбор, список, текст, дата и время, снимок, файл, кнопки (§14.5)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      if (!window.IM_SCENARIO_EXAMPLES) await loadScript("../tests/scenario-examples.js");
      // Новая версия сценария пожара — showcase: новый инцидент получает последнюю версию
      const fireGuid = window.IM_FIXTURE.scenarios.keys.fire;
      const rows = window.IM_FIXTURE.scenarios.rows;
      const version = Math.max(...rows.filter((r) => r.guid === fireGuid).map((r) => r.version)) + 1;
      const show = JSON.parse(JSON.stringify(window.IM_SCENARIO_EXAMPLES["showcase/00-primitives.json"]));
      show.scenario = Object.assign(show.scenario, { id: fireGuid, version });
      if (mode() !== "queue") await click($("backToQueue"));
      await standReset({ fixture: "demo", fixturePatch: { scenarios: { rows: rows.concat({ guid: fireGuid, version, name: show.scenario.name, script: show }) } } });
      await wait(100);
      try {
        const fire = (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find((e) => e.eventType.id === "fire");
        const source = (await stand.get(`/operator/incidents/${encodeURIComponent(fire.guid)}`)).source.guid;
        const created = await stand.raw("POST", "/test/incidents", { eventTypeId: "fire", deviceIds: [source] });
        expect(created.status === 201 && created.body.scenario.scenarioVersion === version, `инцидент не на версии ${version}`);
        const guid = created.body.guid;
        await setFilter("open");
        const claim = await buttonOnPages("claim", guid);
        expect(claim, "новый инцидент нельзя взять");
        await click(claim);
        expect(mode() === "work", "карточка не открылась");
        const seen = new Set();
        for (let i = 0; i < 40; i++) {
          const sc = (await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).scenario;
          if (sc.result.completedAt) break;
          const st = sc.script.steps.find((x) => x.id === sc.result.currentStepId);
          seen.add(st.type);
          // Карточка перерисовывается после ответа сервера — ждём, пока она покажет этот шаг
          const shown = () => (root().querySelector(".step-h strong") || {}).textContent === (st.title || st.view.label);
          for (let k = 0; k < 25 && !shown(); k++) await wait();
          expect(shown(), `карточка не показала шаг «${st.id}»`);
          await fillStep(st).catch((err) => {
            throw new Error(`шаг «${st.id}» (${st.type}): ${err.message}`);
          });
          if (st.type === "Message") continue;
          const next = $("stepNext");
          expect(next && !off(next), `шаг «${st.id}»: «Далее» недоступна`);
          await click(next);
        }
        const sc = (await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).scenario;
        expect(sc.result.completedAt, "сценарий не пройден до конца");
        const missed = ["Message", "RadioButton", "Checkbox", "Select", "Comment", "Image", "Datetime"].filter((x) => !seen.has(x));
        expect(!missed.length, `не встретились типы шагов: ${missed.join(", ")}`);
        // Ответы «дата и время» на шагах пути — местными датой и временем, не строкой ISO (BUG-71)
        await click(root().querySelectorAll(".crumb")[0]);
        const iso = [...root().querySelectorAll(".crumb-ans")].map((x) => x.textContent).find((x) => /\d{4}-\d{2}-\d{2}T|\d{2}:\d{2}:\d{2}/.test(x));
        expect(!iso, `ответ на пути строкой ISO: «${iso}»`);
        const atts = sc.result.attachments || [];
        expect(atts.some((a) => a.source === "operator" && a.fileName === "selftest.png") && atts.some((a) => a.source === "camera"), "нет вложений: файл оператора и снимок камеры");
        return `${sc.path.length} шагов, ${seen.size} типов`;
      } finally {
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Обязательный Select из двух списков — «Далее» серая, пока один пуст; Image — второй файл заменяет первый, вложение одно (спецификация, разделы 6.3, 6.5; PROC-33)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Новая версия пожара: у «Тип сработки» два обязательных списка, после него — файл оператора
      const fireGuid = window.IM_FIXTURE.scenarios.keys.fire;
      const rows = window.IM_FIXTURE.scenarios.rows;
      const latest = rows.filter((r) => r.guid === fireGuid).sort((a, b) => b.version - a.version)[0];
      const script = JSON.parse(JSON.stringify(latest.script));
      const version = latest.version + 1;
      script.scenario.version = version;
      const kind = script.steps.find((x) => x.id === "kind");
      kind.view.required = true;
      kind.view.lists.push({ id: "floor", label: "Этаж", options: [{ id: "f1", label: "1" }, { id: "f2", label: "2" }], default: [] });
      const photo = { id: "photo", type: "Image", title: "Снимок", description: "", revisitable: true, multitasking: false, report: false, finish: false,
        view: { label: "Снимок", source: "operator", image: null }, transitions: { default: { goto: kind.transitions.default.goto, macro: null } } };
      kind.transitions.default.goto = "photo";
      script.steps.push(photo);
      if (mode() !== "queue") await click($("backToQueue"));
      await standReset({ fixture: "demo", fixturePatch: { scenarios: { rows: rows.concat({ guid: fireGuid, version, name: latest.name, script }) } } });
      await wait(100);
      try {
        const fire = (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find((e) => e.eventType.id === "fire");
        const source = (await stand.get(`/operator/incidents/${encodeURIComponent(fire.guid)}`)).source.guid;
        const created = await stand.raw("POST", "/test/incidents", { eventTypeId: "fire", deviceIds: [source] });
        expect(created.status === 201 && created.body.scenario.scenarioVersion === version, `инцидент не на версии ${version}`);
        const guid = created.body.guid;
        await setFilter("open");
        const claim = await buttonOnPages("claim", guid);
        expect(claim, "новый инцидент нельзя взять");
        await click(claim);
        expect(mode() === "work", "карточка не открылась");
        const current = async () => {
          const sc = (await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).scenario;
          return sc.script.steps.find((x) => x.id === sc.result.currentStepId);
        };
        const showStep = async (st) => {
          const shown = () => (root().querySelector(".step-h strong") || {}).textContent === st.title;
          for (let k = 0; k < 25 && !shown(); k++) await wait();
          expect(shown(), `карточка не показала шаг «${st.id}»`);
        };
        // Подтверждение и классификация — как обычно, до «Тип сработки»
        for (let n = 0; n < 4; n++) {
          const st = await current();
          if (st.id === "kind") break;
          await showStep(st);
          await fillStep(st);
          await click($("stepNext"));
        }
        const st = await current();
        expect(st.id === "kind", `ожидался шаг «Тип сработки», а текущий — «${st.id}»`);
        await showStep(st);
        const box = (list) => root().querySelector(`[data-list="kind"][data-list-id="${list}"]`);
        expect(off($("stepNext")), "«Далее» доступна без отметок в обязательных списках");
        await click(box("kind"));
        expect(off($("stepNext")), "«Далее» доступна, хотя список «Этаж» пуст");
        await click(box("floor"));
        expect(!off($("stepNext")), "«Далее» недоступна, хотя отмечено в обоих списках");
        await click($("stepNext"));
        await showStep(photo);
        // Файл читается асинхронно: вложение готово, когда карточка перерисовала поле (новый элемент) и показывает «Фото: 1»
        const attach = async (name) => {
          const input = root().querySelector('[data-file="photo"]');
          const files = new DataTransfer();
          files.items.add(new File([name], name, { type: "image/png" }));
          input.files = files.files;
          input.dispatchEvent(new Event("change", { bubbles: true }));
          const ready = () =>
            root().querySelector('[data-file="photo"]') !== input && /Фото: 1/.test((root().querySelector(".step-card .macro-row") || {}).textContent || "");
          for (let k = 0; k < 25 && !ready(); k++) await wait();
          expect(ready(), `файл ${name} не прикрепился`);
        };
        await attach("first.png");
        await attach("second.png");
        await click($("stepNext"));
        await wait(200);
        const sc = (await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).scenario;
        const entry = sc.result.state.photo;
        const atts = (sc.result.attachments || []).filter((a) => a.stepId === "photo");
        expect(entry && typeof entry.value === "string" && atts.length === 1 && atts[0].id === entry.value, `ответ Image: ${JSON.stringify(entry && entry.value)}, вложений ${atts.length}`);
        expect(atts[0].fileName === "second.png", `ушёл файл «${atts[0].fileName}», а не второй — «second.png»`);
        expect(JSON.stringify(sc.result.state.kind.value) === JSON.stringify({ kind: [kind.view.lists[0].options[0].id], floor: ["f1"] }), `ответ Select: ${JSON.stringify(sc.result.state.kind.value)}`);
        return "Select — оба списка, Image — второй файл";
      } finally {
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Значения по умолчанию и описание шага: поле открывается заполненным, «Далее» доступна, по ней записывается значение по умолчанию (спецификация, раздел 6)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Новая версия пожара: отметка «Подтверждаю» отмечена заранее, у классификации — вариант по умолчанию и описание
      const fireGuid = window.IM_FIXTURE.scenarios.keys.fire;
      const rows = window.IM_FIXTURE.scenarios.rows;
      const latest = rows.filter((r) => r.guid === fireGuid).sort((a, b) => b.version - a.version)[0];
      const script = JSON.parse(JSON.stringify(latest.script));
      const version = latest.version + 1;
      script.scenario.version = version;
      const at = (id) => script.steps.find((x) => x.id === id);
      at("visual").view.options[0].default = true;
      const verdict = at("verdict");
      verdict.view.default = verdict.view.options[verdict.view.options.length - 1].id;
      verdict.description = "Смотрите кадр целиком";
      if (mode() !== "queue") await click($("backToQueue"));
      await standReset({ fixture: "demo", fixturePatch: { scenarios: { rows: rows.concat({ guid: fireGuid, version, name: latest.name, script }) } } });
      await wait(100);
      try {
        const fire = (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find((e) => e.eventType.id === "fire");
        const source = (await stand.get(`/operator/incidents/${encodeURIComponent(fire.guid)}`)).source.guid;
        const created = await stand.raw("POST", "/test/incidents", { eventTypeId: "fire", deviceIds: [source] });
        expect(created.status === 201 && created.body.scenario.scenarioVersion === version, `инцидент не на версии ${version}`);
        const guid = created.body.guid;
        await setFilter("open");
        const claim = await buttonOnPages("claim", guid);
        expect(claim, "новый инцидент нельзя взять");
        await click(claim);
        expect(mode() === "work", "карточка не открылась");
        expect(root().querySelector("[data-confirm].on"), "«Подтверждаю» не отмечено по умолчанию");
        expect($("stepNext") && !off($("stepNext")), "«Далее» недоступна при значении по умолчанию");
        await click($("stepNext"));
        await wait(200);
        const sc = (await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).scenario;
        expect(JSON.stringify(sc.result.state.visual && sc.result.state.visual.value) === '["confirmed"]', "по «Далее» не записалось значение по умолчанию");
        const picked = root().querySelector('input[type="radio"][data-ans]:checked');
        expect(picked && picked.value === verdict.view.default, `классификация по умолчанию — «${picked && picked.value}», а не «${verdict.view.default}»`);
        expect([...root().querySelectorAll(".step-q")].some((p) => p.textContent.includes("Смотрите кадр целиком")), "описание шага не показано");
        return `${verdict.view.default}, описание показано`;
      } finally {
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Шаги-кнопки (Message) в сценарии набора: INC-1839 на второй версии «Проникновения» — «Сообщил охране», «Доложил»; последняя ведёт на «Итог» (§14.5)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      if (mode() !== "queue") await click($("backToQueue"));
      await standReset({ fixture: "demo" });
      await wait(100);
      try {
        const inc = (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find((e) => e.number === "INC-1839");
        expect(inc, "в наборе нет INC-1839");
        const guid = inc.guid;
        const first = (await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).scenario;
        expect(first.scenarioVersion === 2, `INC-1839 на версии ${first.scenarioVersion}, а не 2`);
        await setFilter("open");
        const claim = await buttonOnPages("claim", guid);
        expect(claim, "INC-1839 нельзя взять");
        await click(claim);
        expect(mode() === "work", "карточка не открылась");
        const pressed = [];
        for (let i = 0; i < 10; i++) {
          const sc = (await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).scenario;
          if (sc.result.completedAt) break;
          const st = sc.script.steps.find((x) => x.id === sc.result.currentStepId);
          const shown = () => (root().querySelector(".step-h strong") || {}).textContent === (st.title || st.view.label);
          for (let k = 0; k < 25 && !shown(); k++) await wait();
          expect(shown(), `карточка не показала шаг «${st.id}»`);
          // Классификация — первый вариант, «Реальное проникновение»: ветка с «Сообщите охране»
          await fillStep(st);
          if (st.type === "Message") {
            pressed.push(st.view.label);
            await wait(200);
            if (root().querySelector("[data-finish]")) break;
            continue;
          }
          const next = $("stepNext");
          expect(next && !off(next), `шаг «${st.id}»: «Далее» недоступна`);
          await click(next);
        }
        expect(pressed.join(", ") === "Сообщил охране, Доложил", `нажаты кнопки шагов: «${pressed.join(", ")}»`);
        const card = await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`);
        expect(card.scenario.result.completedAt, "сценарий не пройден до конца");
        const macros = card.journal.filter((j) => j.templateKey === "workflow.journal.macro.launched").map((j) => j.vars.name);
        expect(macros.join() === "Сирена и PTZ на зону", `макросы в журнале: «${macros.join(", ")}», а не один «Сирена и PTZ на зону»`);
        // Макрос с uid — команда агенту объекта; агента в прототипе нет — итог «выполнено» сразу (план 82, D9)
        const done = card.journal.filter((j) => j.templateKey === "workflow.journal.macro.done").map((j) => j.vars.name);
        expect(done.join() === "Сирена и PTZ на зону", `итог макроса в журнале: «${done.join(", ")}», а не «выполнен» у «Сирена и PTZ на зону»`);
        const finish = root().querySelector("[data-finish]");
        expect($("modalDialog").hidden && finish && !finish.disabled, "после «Доложил» карточка не на «Итоге» с «Завершить инцидент»");
        await click(finish);
        await wait(200);
        expect(mode() === "queue", "после закрытия карточка не закрылась");
        return pressed.join(", ");
      } finally {
        if (!$("modalDialog").hidden) await click(document.querySelector('[data-close="modalDialog"]'));
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Шаг без переответа (revisitable: false): INC-1852 «Оставленный предмет» — замок в ленте только у «Эвакуации»; на ней поля недоступны и сказано почему, на «Владельце» — доступны (спецификация, раздел 8)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      if (mode() !== "queue") await click($("backToQueue"));
      await standReset({ fixture: "demo" });
      await wait(100);
      try {
        const guid = guidOf("INC-1852");
        await openOwn(guid);
        const sc = (await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).scenario;
        const locked = sc.script.steps.filter((s) => s.revisitable === false).map((s) => s.title);
        expect(locked.join() === "Эвакуация", `шаги без переответа в сценарии: «${locked.join(", ")}», а не одна «Эвакуация»`);
        const crumbs = () => [...root().querySelectorAll(".crumb")];
        const name = (c) => c.querySelector(".crumb-name").textContent.replace("lock", "").trim();
        const withLock = crumbs().filter((c) => c.querySelector(".crumb-lock")).map(name);
        expect(withLock.join() === "Эвакуация", `замок в ленте у шагов: «${withLock.join(", ")}», а не только у «Эвакуации»`);
        const goTo = async (title) => {
          const c = crumbs().find((x) => name(x) === title);
          expect(c && c.dataset.crumb !== undefined, `на шаг «${title}» нельзя перейти из ленты`);
          await click(c);
          expect((root().querySelector(".step-h strong") || {}).textContent === title, `карточка не показала шаг «${title}»`);
        };
        await goTo("Эвакуация");
        const evac = crumbs().find((x) => x.querySelector(".crumb-lock"));
        expect(evac.title.includes("Ответ не меняется после перехода дальше"), `подсказка у шага с замком: «${evac.title}»`);
        const radios = () => [...root().querySelectorAll('.step-card input[type="radio"]')];
        expect(radios().length && radios().every((r) => r.disabled), "на пройденной «Эвакуации» варианты доступны");
        expect(root().querySelector(".step-locked"), "на пройденной «Эвакуации» не сказано, почему ответ не изменить");
        await goTo("Владелец");
        expect(radios().length && radios().every((r) => !r.disabled), "на пройденном «Владельце» варианты недоступны");
        expect(!root().querySelector(".step-locked") && !root().querySelector(".step-lock"), "на «Владельце» пометка шага без переответа");
        return "замок — у «Эвакуации», «Владелец» переотвечается";
      } finally {
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Норматив реакции по сценарию: у медпункта свой срок, строка со сценарием точнее строки по приоритету (§4, ARCH-15)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const keys = window.IM_FIXTURE.scenarios.keys;
      const event = { eventTypeId: "fire", deviceIds: ["20000000-0002-4000-8000-000000000005"] };
      const timers = window.IM_WORKFLOW.timers.map((t) =>
        t.id === "reaction" ? Object.assign({}, t, { overrides: t.overrides.concat([{ scenario: keys.medical, sec: 90 }]) }) : t);
      try {
        await standReset({ fixture: "demo", workflowPatch: { timers } });
        const res = await stand.raw("POST", "/test/events", event);
        expect(res.status === 201, `событие: ${res.status}`);
        const secOf = (key) => {
          const c = res.body.incidents.find((x) => x.scenario.scenarioGuid === key);
          return (Date.parse(c.timer.dueAt) - Date.parse(c.createdAt)) / 1000;
        };
        const med = secOf(keys.medical);
        const fire = secOf(keys.fire);
        expect(med === 90 && fire === 420, `норматив реакции: медпункт ${med} с (ждали 90), пожар ${fire} с (ждали 420)`);
        return `медпункт ${med} с, пожар ${fire} с`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Событие через правила: инцидент на каждый сценарий, повтор ничего не создаёт (§14.5, ARCH-15)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const keys = window.IM_FIXTURE.scenarios.keys;
      const rule = (tail) => `80000000-0000-4000-8000-00000000000${tail}`;
      // Датчик дыма 5 в торговом центре: базовое правило пожара и правило медпункта
      const event = { eventTypeId: "fire", deviceIds: ["20000000-0002-4000-8000-000000000005"] };
      const count = async () => (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.length;
      try {
        const before = await count();
        const res = await stand.raw("POST", "/test/events", event);
        expect(res.status === 201, `событие: ${res.status}`);
        const b = res.body;
        const sc = b.incidents.map((c) => c.scenario.scenarioGuid);
        expect(b.created === 2 && sc.length === 2 && sc.includes(keys.fire) && sc.includes(keys.medical), `сценарии: ${sc.join(", ")}`);
        expect(b.incidents.every((c) => c.eventGuid === b.eventGuid && c.alarmNumber === b.alarmNumber), "у инцидентов не одно событие и не один номер тревоги");
        expect(b.alarmNumber === b.incidents[0].number && sc[0] === keys.medical, `номер тревоги ${b.alarmNumber} — не первого, медпункта`);
        const fire = b.incidents.find((c) => c.scenario.scenarioGuid === keys.fire);
        const med = b.incidents.find((c) => c.scenario.scenarioGuid === keys.medical);
        expect(fire.priority === 75 && fire.ruleGuid === rule(1), `пожар: приоритет ${fire.priority}, правило ${fire.ruleGuid}`);
        expect(med.priority === 100 && med.ruleGuid === rule(9), `медпункт: приоритет ${med.priority}, правило ${med.ruleGuid}`);
        const again = await stand.raw("POST", "/test/events", Object.assign({ eventGuid: b.eventGuid }, event));
        expect(again.status === 200 && again.body.created === 0 && again.body.alarmNumber === b.alarmNumber, `повтор: ${again.status}, создано ${again.body.created}`);
        expect(again.body.incidents.map((c) => c.guid).join() === b.incidents.map((c) => c.guid).join(), "повтор вернул не те инциденты");
        expect((await count()) === before + 2, "в очереди не два новых инцидента");
        // Порядок — по точности победителя, а не по приоритету (решение 2026-10-28): медпункт с приоритетом 25 и условием
        // по самому датчику (точнее типа устройства у базового пожара) — всё равно первый. В наборе точность у обоих одна —
        // тип устройства (§14.5), там медпункт первый по приоритету
        const rules = window.IM_FIXTURE.rules.map((r) =>
          r.guid === rule(9) ? Object.assign({}, r, { priority: 25, conditions: [{ eventTypeId: "fire", deviceGuid: event.deviceIds[0] }] }) : r
        );
        await standReset({ fixture: "demo", fixturePatch: { rules } });
        const low = (await stand.raw("POST", "/test/events", event)).body;
        const order = low.incidents.map((c) => `${c.scenario.scenarioGuid === keys.medical ? "медпункт" : "пожар"} ${c.priority}`).join(", ");
        expect(order === "медпункт 25, пожар 75" && low.alarmNumber === low.incidents[0].number, `порядок при медпункте 25: ${order}, тревога ${low.alarmNumber}`);
        // Правила равны во всём — решает guid (intake.ruleOrder машины), а не порядок строк набора
        const tie = (tail, scenario) => ({ guid: rule(tail), name: `ничья ${tail}`, priority: 50, createdAt: "2026-09-01T09:00:00Z", scenarios: [scenario], conditions: [{ eventTypeId: "fire", deviceTypeId: "fire-detector" }] });
        await standReset({ fixture: "demo", fixturePatch: { rules: [tie("e", keys.fire), tie("d", keys.medical)] } });
        const tied = (await stand.raw("POST", "/test/events", event)).body;
        expect(tied.incidents.map((c) => c.ruleGuid).join() === [rule("d"), rule("e")].join(), `при равенстве правил первым — не меньший guid: ${tied.incidents.map((c) => c.ruleGuid).join(", ")}`);
        return `тревога ${b.alarmNumber}: ${b.incidents.map((c) => c.number).join(", ")}; медпункт 25 — первый; равенство — по guid`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Выключенное правило (active: false) не создаёт инцидент и не перекрывает включённое; без поля — включено (§14.5, ТЗ-2а)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const keys = window.IM_FIXTURE.scenarios.keys;
      const rule = (tail) => `80000000-0000-4000-8000-00000000000${tail}`;
      const smoke5 = "20000000-0002-4000-8000-000000000005";
      const event = (n) => ({ eventTypeId: "fire", deviceIds: [smoke5] });
      const mk = (tail, extra) => Object.assign({ guid: rule(tail), name: `правило ${tail}`, priority: 50, createdAt: "2026-09-01T09:00:00Z", scenarios: [keys.fire], conditions: [{ eventTypeId: "fire" }] }, extra);
      try {
        // Единственное подошедшее правило выключено — инцидента нет
        await standReset({ fixture: "demo", fixturePatch: { rules: [mk("e", { active: false })] } });
        const off = await stand.raw("POST", "/test/events", event(1));
        expect(off.body.created === 0 && off.body.incidents.length === 0 && off.body.alarmNumber == null, `выключенное правило создало ${off.body.created} инц., тревога ${off.body.alarmNumber}`);
        // Выключенное точнее и старше по приоритету, но включённое всё равно побеждает
        const sharp = mk("d", { active: false, priority: 100, conditions: [{ eventTypeId: "fire", deviceGuid: smoke5 }] });
        await standReset({ fixture: "demo", fixturePatch: { rules: [sharp, mk("e")] } });
        const on = await stand.raw("POST", "/test/events", event(2));
        expect(on.body.created === 1 && on.body.incidents[0].ruleGuid === rule("e") && on.body.incidents[0].priority === 50, `включённое: создано ${on.body.created}, правило ${(on.body.incidents[0] || {}).ruleGuid}, приоритет ${(on.body.incidents[0] || {}).priority}`);
        // Правило без поля active — включено (по умолчанию true)
        await standReset({ fixture: "demo", fixturePatch: { rules: [mk("e")] } });
        const dflt = await stand.raw("POST", "/test/events", event(3));
        expect(dflt.body.created === 1, `правило без active создало ${dflt.body.created}`);
        // Эталонный набор: у каждого правила поле есть и оно включено; контракт описывает поле и вердикт объяснения
        expect(window.IM_FIXTURE.rules.every((r) => r.active === true), "у правил эталонного набора нет active: true");
        const sc = window.IM_OPENAPI.components.schemas;
        const f = sc.IncidentRule && sc.IncidentRule.properties.active;
        expect(f && f.type === "boolean" && f.default === true, "IncidentRule.active в контракте — не boolean с умолчанием true");
        expect(sc.EventExplanationRule.properties.verdict.enum.includes("disabled"), "в вердиктах объяснения нет disabled");
        return "выключенное — не создаёт и не перекрывает; без поля — включено; набор и контракт на месте";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Правила инцидента нет в наборе — ruleGuid и ruleName null, как у сервера (контракт IncidentCard.ruleGuid)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const rule = (tail) => `80000000-0000-4000-8000-00000000000${tail}`;
      const card = (number) => stand.get(`/operator/incidents/${window.IM_FIXTURE.incidents.find((i) => i.number === number).guid}`);
      try {
        await standReset({ fixture: "demo", fixturePatch: { rules: window.IM_FIXTURE.rules.filter((r) => r.guid !== rule(7)) } });
        const gone = await card("INC-1850");
        expect(gone.ruleGuid === null && gone.ruleName === null, `INC-1850 без правила: ${gone.ruleGuid}, ${gone.ruleName}`);
        const kept = await card("INC-1847");
        expect(kept.ruleGuid === rule(1) && kept.ruleName, `INC-1847 с правилом: ${kept.ruleGuid}, ${kept.ruleName}`);
        return "удалённое правило — null, остальные на месте";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Тревога в очереди и карточке: номер тревоги, «событие: ещё 1», блок «По этому событию» (§7, ARCH-15)", async () => {
      // Тревога INC-1847 набора: пожар INC-1847 и сосед — медпункт INC-1853
      const fire = guidOf("INC-1847");
      const med = guidOf("INC-1853");
      try {
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
        const fireRow = await rowOnPages(fire);
        expect(fireRow, "INC-1847 нет в «Открытых»");
        const sub = (row) => row.querySelector(".event-sub").textContent;
        // Текст чипа — без названия значка
        const chip = (row) => [...((row.querySelector("[data-siblings]") || {}).childNodes || [])].filter((n) => n.nodeType === 3).map((n) => n.textContent).join("").trim();
        expect(!/тревога/.test(sub(fireRow)), `у INC-1847 номер тревоги свой — не показывается: «${sub(fireRow)}»`);
        expect(chip(fireRow) === "событие: ещё 1", `чип INC-1847: «${chip(fireRow)}»`);
        expect(!fireRow.querySelector(".chip.linked[data-siblings]"), "чип соседей — не чип привязанных");
        // Подсказка чипа — номера и бейджи соседей, подгружается при наведении
        const fireChip = fireRow.querySelector("[data-siblings]");
        fireChip.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
        await wait(100);
        // Курсор ушёл со списка: иначе список заморожен под ним до конца прогона (§22.1)
        $("eventsList").dispatchEvent(new MouseEvent("mouseleave"));
        expect(/INC-1853 — Медпомощь при пожаре · Новое/.test(fireChip.title), `подсказка чипа INC-1847: «${fireChip.title}»`);
        const medRow = await rowOnPages(med);
        expect(medRow, "INC-1853 нет в «Открытых»");
        expect(/^INC-1853 · тревога INC-1847$/.test(sub(medRow).trim()), `у INC-1853 — после номера «тревога INC-1847»: «${sub(medRow)}»`);
        expect(chip(medRow) === "событие: ещё 1", `чип INC-1853: «${chip(medRow)}»`);
        // Карточка INC-1847: блок над шагами, строка соседа без кнопок действий
        await setFilter("open");
        const view = await buttonOnPages("view", fire);
        expect(view, "у INC-1847 нет «Посмотреть»");
        await click(view);
        expect(mode() === "work", "карточка INC-1847 не открылась");
        const block = $("alarmBlock");
        expect(block, "в карточке нет блока «По этому событию»");
        const text = block.textContent.replace(/\s+/g, " ");
        expect(text.includes("Тревога INC-1847 · открыта"), `статус тревоги: «${text}»`);
        expect(text.includes("INC-1853 — Медпомощь при пожаре"), `строка соседа: «${text}»`);
        expect(!block.querySelector("[data-do]"), "в блоке соседей — кнопки действий");
        expect(block.compareDocumentPosition(root().querySelector(".crumbs")) & Node.DOCUMENT_POSITION_FOLLOWING, "блок — не над шагами");
        // Номер соседа — «Посмотреть»: карточка INC-1853 на просмотр
        await click(block.querySelector(`[data-sibling="${med}"]`));
        await wait(200);
        const num = $("workTitle").querySelector(".work-num");
        expect(mode() === "work" && num && num.textContent === "INC-1853", `открылся не INC-1853: «${num ? num.textContent : "нет"}»`);
        const back = ($("alarmBlock") || { textContent: "" }).textContent.replace(/\s+/g, " ");
        expect(back.includes("INC-1847 — "), `в карточке INC-1853 сосед — INC-1847: «${back}»`);
        expect(!root().querySelector(".crumbs.live"), "карточка INC-1853 открылась не на просмотр");
        return `INC-1853 · тревога INC-1847; «${chip(medRow)}»; ${block.querySelector(".alarm-head > span:last-child").textContent}`;
      } finally {
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Дубликат при соседях: предупреждение под списком результатов, закрыть можно (§2.2, ARCH-15)", async () => {
      // Взять и открыть «Закрыть без обработки»; warning() — видимое предупреждение под списком результатов
      const warning = () => {
        const el = $("dialogFields").querySelector('[data-warning="resultId"]');
        return el && !el.hidden ? el.textContent : "";
      };
      async function closeForm(number) {
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
        const claim = await buttonOnPages("claim", guidOf(number));
        expect(claim, `у ${number} нет «Взять»`);
        await click(claim);
        expect(mode() === "work", `карточка ${number} не открылась`);
        const close = button(root(), "close");
        expect(close, `в карточке ${number} нет «Закрыть без обработки»`);
        await click(close);
        expect(!$("modalDialog").hidden, `форма закрытия ${number} не открылась`);
      }
      try {
        // Тревога INC-1847 набора: у пожара INC-1847 сосед — медпункт INC-1853
        await closeForm("INC-1847");
        expect(!warning(), `предупреждение без выбранного результата: «${warning()}»`);
        await setField("resultId", "duplicate");
        const text = warning();
        expect(/другие службы той же тревоги/.test(text), `у «Дубликата» нет предупреждения о соседях: «${text}»`);
        expect(/\(1\)/.test(text), `число соседей в предупреждении: «${text}»`);
        await setField("resultId", "false_alarm");
        expect(!warning(), `у «Ложной тревоги» — предупреждение: «${warning()}»`);
        // Предупреждение не запрещает: «Дубликат» с комментарием закрывает
        await setField("resultId", "duplicate");
        await confirmDialog(NOTE);
        expect(mode() === "queue", "«Дубликатом» не закрылось");
        // У медпункта INC-1853 сосед INC-1847 теперь закрыт — свой текст: они уже закрыты
        await closeForm("INC-1853");
        await setField("resultId", "duplicate");
        expect(/уже закрыты/.test(warning()), `у INC-1853 нет предупреждения о закрытых соседях: «${warning()}»`);
        // Закрыть и его: лимит активных самопроверки — один
        await confirmDialog(NOTE);
        expect(mode() === "queue", "INC-1853 «Дубликатом» не закрылось");
        // INC-1851 — без соседей
        await closeForm("INC-1851");
        await setField("resultId", "duplicate");
        expect(!warning(), `у INC-1851 соседей нет, а предупреждение есть: «${warning()}»`);
        document.querySelector('[data-close="modalDialog"]').click();
        await wait();
        return text;
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Массовый сбой на выборке двух сценариев: закрыт свой сценарий, о пропущенных — уведомление (§11.1, ARCH-15)", async () => {
      const stand = window.IM_SELFTEST_API;
      const state = async (number) => (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(guidOf(number))}`)).body.state;
      // Отметить инцидент на любой странице «Открытых»: листание выборку не снимает
      async function tick(number) {
        const first = $("eventsPager").querySelector('[data-page="1"]');
        if (first && !first.disabled) await click(first);
        const row = await rowOnPages(guidOf(number));
        expect(row, `в «Открытых» нет ${number}`);
        await click(row.querySelector(`[data-check="${guidOf(number)}"]`));
      }
      try {
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
        // Пожары INC-1847 и INC-1851 и медпункт INC-1853 — сосед INC-1847; основной выборки — INC-1851 (пожар)
        for (const number of ["INC-1847", "INC-1851", "INC-1853"]) await tick(number);
        expect($("selBar").textContent.includes("Отмечено: 3"), `панель: «${$("selBar").textContent.trim()}»`);
        const b = $("selBar").querySelector('[data-sel-do="close"]');
        expect(b && !off(b), "«Закрыть без обработки» на панели выборки недоступна");
        await click(b);
        expect(!$("modalDialog").hidden, "форма закрытия выборки не открылась");
        const note = $("dialogNote").textContent;
        expect(/Закроются инциденты сценария .*2 из 3.*Других сценариев — 1/.test(note), `пояснение формы: «${note}»`);
        await setField("resultId", "mass");
        await setField("causeId", window.IM_WORKFLOW.reasonCatalogs.mass_fault.items[0].id);
        await confirmDialog(NOTE);
        await wait(200);
        const text = ($("toasts").lastElementChild || {}).textContent || "";
        expect(/Закрыто: 2\. Не закрыты: 1 — другой сценарий: INC-1853/.test(text), `уведомление: «${text}»`);
        const states = [await state("INC-1847"), await state("INC-1851"), await state("INC-1853")];
        expect(states.join(",") === "closed,closed,new", `состояния INC-1847, INC-1851, INC-1853: ${states.join(", ")}`);
        return text;
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        if (!$("clearSelectionBtn").disabled) await click($("clearSelectionBtn"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Бейдж чужого инцидента в работе — ФИО владельца: в очереди, в карточке и в строке состояния (§2.4, BUG-51)", async () => {
      await setFilter("foreign");
      const row = [...$("eventsList").querySelectorAll(".event")].find((r) => r.querySelector(".badge.foreign"));
      expect(row, "в «Чужих» нет инцидента в работе у коллеги");
      const names = window.IM_FIXTURE.people.operators.map((o) => o.name);
      const text = row.querySelector(".badge.foreign").textContent.trim();
      expect(names.includes(text), `бейдж в очереди: «${text}», а не ФИО коллеги`);
      const id = row.dataset.id;
      await click(button($("eventsList"), "view", id));
      expect(mode() === "work", "чужая карточка не открылась");
      const card = $("workTitle").querySelector(".badge.foreign");
      expect(card && card.textContent.trim() === text, `бейдж в карточке: «${card ? card.textContent.trim() : "нет"}», а не «${text}»`);
      expect($("statusIncident").textContent.trim().endsWith(text), `строка состояния: «${$("statusIncident").textContent.trim()}»`);
      await click($("backToQueue"));
      return `${id}: ${text}`;
    });

    let foreignTransferred = null;
    await step("Передать чужой инцидент", async () => {
      await setFilter("foreign");
      const rows = [...$("eventsList").querySelectorAll(".event")].filter(
        (r) => r.querySelector('[data-do="view"]') && r.querySelector('[data-do="transfer"]:not([aria-disabled="true"])')
      );
      expect(rows.length, "нет чужих инцидентов, которые можно передать");
      foreignTransferred = rows[0].dataset.id;
      await click(button($("eventsList"), "transfer", foreignTransferred));
      // Прошлой передачи нет — адресата форма не выбирает (BUG-45): поле пустое, «Передать» без него не отправляет
      const input = $("dialogFields").querySelector('[data-target-input="targetId"]');
      expect(field("targetId").value === "" && input.placeholder === "Выберите адресата", `без прошлой передачи в поле «${field("targetId").value || input.placeholder}»`);
      await confirmDialog(NOTE);
      expect(!$("modalDialog").hidden, "«Передать» без адресата закрыла форму");
      // Не всплывает (§22.6): подсказка у самого поля и aria-invalid
      const warn = $("dialogFields").querySelector('[data-field-error="targetId"]');
      expect(warn && !warn.hidden && warn.textContent.includes("Заполните поле «Кому передать»"), `подсказка у поля: «${warn ? warn.textContent : "нет"}»`);
      expect($("dialogFields").querySelector('[data-target-input="targetId"]').getAttribute("aria-invalid") === "true", "у пустого поля нет aria-invalid");
      expect(![...$("toasts").children].some((x) => /Заполните поле/.test(x.textContent)), "«Заполните поле» всплыло сообщением");
      await click(input);
      await click($("dialogFields").querySelector('[data-target-pick="sidorov"]'));
      await confirmDialog(NOTE);
      await setFilter("all");
      const row = await rowOnPages(foreignTransferred);
      expect(row && row.textContent.includes("Ожидает принятия"), `${foreignTransferred} не ожидает принятия после передачи`);
      // Передача — в журнале действий аудита: handover с адресатом (§12.4, план 71)
      const audit = await window.IM_SELFTEST_API.get("/operator/admin/audit/actions", { incident: foreignTransferred, kind: "handover" });
      expect(audit.items.some((r) => r.transition === "transfer" && r.targetPersonId === "sidorov"), `в аудите нет передачи Сидорову: ${JSON.stringify(audit.items)}`);
      return foreignTransferred;
    });

    // Строка очереди не несёт адресатов (решение 74): форма берёт их из карточки при открытии
    await step("Передача из строки очереди открывает форму с адресатами", async () => {
      await setFilter("foreign");
      const row = [...$("eventsList").querySelectorAll(".event")].find(
        (r) => r.dataset.id !== foreignTransferred && r.querySelector('[data-do="transfer"]:not([aria-disabled="true"])')
      );
      expect(row, "нет чужого инцидента, который можно передать");
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const card = await stand.get(`/operator/incidents/${encodeURIComponent(row.dataset.id)}`);
      const inRow = (await stand.get("/operator/incidents", { filter: "foreign", pageSize: 200 })).items.find((e) => e.guid === row.dataset.id);
      const transfer = (ev) => (ev.actions || []).find((a) => a.id === "transfer");
      expect(transfer(inRow) && !(transfer(inRow).fieldOptions || {}).targetId, "строка очереди несёт адресатов");
      expect(transfer(card).fieldOptions.targetId.options.length, "у карточки нет адресатов");
      await click(button($("eventsList"), "transfer", row.dataset.id));
      expect(!$("modalDialog").hidden, "форма передачи из строки не открылась");
      await click($("dialogFields").querySelector('[data-target-input="targetId"]'));
      const picks = $("dialogFields").querySelectorAll("[data-target-pick]").length;
      expect(picks === transfer(card).fieldOptions.targetId.options.length, `адресатов в форме ${picks}, в карточке ${transfer(card).fieldOptions.targetId.options.length}`);
      await click($("modalDialog").querySelector('[data-close="modalDialog"]'));
      await setFilter("all");
      return `${row.dataset.id}: адресатов ${picks}`;
    });

    // Два быстрых нажатия на разные строки: форма открывается по последнему, ответ первого её не перебивает
    await step("Два быстрых нажатия «Передать»: форма — по последней строке", async () => {
      await setFilter("foreign");
      const rows = [...$("eventsList").querySelectorAll(".event")].filter(
        (r) => r.dataset.id !== foreignTransferred && r.querySelector('[data-do="transfer"]:not([aria-disabled="true"])')
      );
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Сидоров — последний адресат передачи, на нём стоят следующие шаги: берём тех, кому его можно передать
      const withSidorov = [];
      for (const r of rows) {
        const card = await stand.get(`/operator/incidents/${encodeURIComponent(r.dataset.id)}`);
        const transfer = (card.actions || []).find((a) => a.id === "transfer");
        const ids = transfer && transfer.fieldOptions && transfer.fieldOptions.targetId ? transfer.fieldOptions.targetId.options.map((o) => o.id) : [];
        if (ids.includes("sidorov")) withSidorov.push(r.dataset.id);
      }
      expect(withSidorov.length >= 2, "нет двух чужих инцидентов, которые можно передать Сидорову");
      const [first, second] = withSidorov;
      const buttons = [first, second].map((g) => button($("eventsList"), "transfer", g));
      expect(buttons.every(Boolean), `нет кнопок «Передать»: ${buttons.map(Boolean)}`);
      buttons.forEach((b) => b.click());
      await wait();
      expect(!$("modalDialog").hidden, "форма передачи не открылась");
      await click($("dialogFields").querySelector('[data-target-input="targetId"]'));
      // Сидоров — последний адресат передачи, на нём стоят следующие шаги
      const pick = $("dialogFields").querySelector('[data-target-pick="sidorov"]');
      expect(pick, "в форме нет Сидорова");
      await click(pick);
      await confirmDialog(NOTE);
      const stateOf = async (guid) => (await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).state;
      const [s1, s2] = [await stateOf(first), await stateOf(second)];
      expect(s2 === "pending_acceptance" && s1 !== "pending_acceptance", `передан не тот: первый «${s1}», второй «${s2}»`);
      await setFilter("all");
      return `${second}: передан последний из двух`;
    });

    await step("Перехватить чужой инцидент", async () => {
      await setFilter("foreign");
      const row = [...$("eventsList").querySelectorAll(".event")].find(
        (r) => r.dataset.id !== foreignTransferred && r.querySelector('[data-do="view"]') && r.textContent.includes("Закрытие")
      );
      expect(row, "нет чужого инцидента в работе");
      const id = row.dataset.id;
      await click(button($("eventsList"), "view", id));
      expect(mode() === "work", "чужая карточка не открылась");
      const take = button(root(), "takeover", id);
      expect(take, "в чужой карточке нет кнопки «Перехватить»");
      const note = root().querySelector(".work-note");
      expect(note && !note.textContent.includes(".."), `две точки подряд: «${note ? note.textContent : ""}»`);
      await click(take);
      await confirmDialog();
      await click($("backToQueue"));
      await setFilter("mine");
      expect(button($("eventsList"), "open_card", id), `${id} не стал моим «В работе»`);
      // Освобождаем лимит активных для следующих шагов
      await openOwn(id);
      await click(button(root(), "release"));
      await confirmDialog(NOTE);
      return id;
    });

    await step("Взять, вернуться к очереди, продолжить", async () => {
      await setFilter("open");
      const b = button($("eventsList"), "claim");
      expect(b, "нет доступной кнопки «Взять»");
      workId = b.dataset.ev;
      await click(b);
      await click($("backToQueue"));
      expect(mode() === "queue", "«К очереди» не вернул к очереди");
      await openOwn(workId);
      return workId;
    });

    await step("Недоступная кнопка объясняет причину по нажатию", async () => {
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
      const b = [...$("eventsList").querySelectorAll('[data-do="claim"]')].find(off);
      expect(b, "при занятом лимите нет недоступной кнопки «Взять»");
      expect(b.getAttribute("aria-disabled") === "true" && !b.disabled, "недоступная кнопка не получает фокус и нажатие");
      // Новое уведомление — новый последний элемент: старые исчезают сами, считать их нельзя
      const before = $("toasts").lastElementChild;
      await click(b);
      const last = $("toasts").lastElementChild;
      const text = last ? last.textContent : "";
      expect(last && last !== before && text.includes("Лимит активных"), `нажатие не объяснило причину: «${text}»`);
      expect(!/[0-9a-f]{8}-[0-9a-f]{4}-/.test(text), `в подсказке идентификатор вместо номера: «${text}»`);
      return text;
    }, "Взять, вернуться к очереди, продолжить");

    await step("Отложить: причина пуста, пока оператор не выберет сам", async () => {
      await openOwn(workId);
      const b = button(root(), "hold");
      expect(b, "в карточке нет кнопки «Отложить»");
      await click(b);
      // От причины зависит срок удержания — за оператора её не выбирают (RULE-110)
      expect(field("reasonId").value === "", `причина выбрана за оператора: «${field("reasonId").value}»`);
      await setField("reasonId", "third_party");
      await confirmDialog();
      expect(mode() === "queue", "после «Отложить» карточка не закрылась");
      await setFilter("mine");
      const row = $("eventsList").querySelector(`[data-id="${workId}"]`);
      expect(row && row.querySelector("[data-hold-timer]"), "у отложенного не виден срок удержания");
    }, "Взять, вернуться к очереди, продолжить");

    await step("Возобновить", async () => {
      await setFilter("mine");
      const b = button($("eventsList"), "resume", workId);
      expect(b, `у ${workId} нет кнопки «Возобновить»`);
      await click(b);
      expect(mode() === "work", "карточка не открылась");
    }, "Отложить: причина пуста, пока оператор не выберет сам");

    await step("Передать: поле с поиском по подстроке; «На месте», потом «Нет на месте» с причиной; себя и своей группы нет", async () => {
      await openOwn(workId);
      const b = button(root(), "transfer");
      expect(b, "в карточке нет кнопки «Передать»");
      await click(b);
      const input = () => $("dialogFields").querySelector('[data-target-input="targetId"]');
      const menu = () => $("dialogFields").querySelector('[data-target-combo="targetId"] .mselect-menu');
      expect(input(), "«Кому передать» — не поле с поиском");
      expect(field("targetId").value === "sidorov", `прошлый адресат не подставлен: «${field("targetId").value}»`);
      // Окно передачи постоянного размера: список — поверх формы, и при открытии, и при наборе
      const card = $("modalDialog").querySelector(".modal-card");
      const size = () => `${card.offsetWidth}×${card.offsetHeight}`;
      const closedSize = size();
      await click(input());
      expect(menu(), "щелчок по полю не открыл список");
      expect(size() === closedSize, `окно изменило размер при открытии списка: ${closedSize} → ${size()}`);
      const offered = [...menu().querySelectorAll("[data-target-pick]")].map((o) => o.dataset.targetPick);
      const self = offered.filter((id) => id === "me" || id === "grp-leads");
      expect(!self.length, `среди адресатов есть сам оператор или его группа: ${self.join(", ")}`);
      const heads = [...menu().querySelectorAll(".mselect-head")].map((h) => h.textContent);
      expect(heads.join(" | ") === "На месте | Нет на месте", `разделы: ${heads.join(" | ")}`);
      // Для экранного диктора: имя поля — подпись и выбранный, раздел — группа с названием (BUG-46)
      const name = input().getAttribute("aria-label");
      expect(name === "Кому передать, Сидоров К.", `имя поля для диктора: «${name}»`);
      const groups = [...menu().querySelectorAll('[role="group"]')].map((g) => (document.getElementById(g.getAttribute("aria-labelledby")) || {}).textContent);
      expect(groups.join(" | ") === "На месте | Нет на месте", `группы списка для диктора: ${groups.join(" | ")}`);
      const items = [...menu().querySelectorAll(".mselect-head, [data-target-pick]")];
      const awayAt = items.findIndex((el) => el.textContent === "Нет на месте");
      const at = (id) => items.findIndex((el) => el.dataset.targetPick === id);
      expect(at("sidorov") < awayAt && at("grp-response") < awayAt && at("orlova") > awayAt, "Сидоров и «Группа реагирования» — на месте, Орлова — нет");
      const note = (id) => menu().querySelector(`[data-target-pick="${id}"] em`).textContent;
      expect(note("orlova") === "оператор · перерыв: Обед", `у Орловой «${note("orlova")}»`);
      expect(note("sidorov") === "оператор", `у Сидорова «${note("sidorov")}»`);
      // Поиск по подстроке: «рлов» — только Орлова; раздел, где никого не осталось, скрыт
      input().value = "рлов";
      input().dispatchEvent(new Event("input", { bubbles: true }));
      await wait();
      const shown = [...menu().querySelectorAll("[data-target-pick]:not([hidden])")].map((o) => o.dataset.targetPick);
      expect(shown.join() === "orlova", `по «рлов» найдены: ${shown.join(", ")}`);
      expect(size() === closedSize, `окно изменило размер при наборе: ${closedSize} → ${size()}`);
      const left = [...menu().querySelectorAll(".mselect-head:not([hidden])")].map((h) => h.textContent);
      expect(left.join() === "Нет на месте", `видны разделы: ${left.join(", ")}`);
      // Набранный текст — не выбор (BUG-43): набор снял прежний выбор
      expect(field("targetId").value === "", `после набора в поле осталось «${field("targetId").value}»`);
      // Esc закрывает список, а не форму; поле пустое, «Передать» без выбора не отправляет; выбор — щелчком
      input().dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
      await wait();
      expect(!menu() && !$("modalDialog").hidden, "Esc закрыл форму, а не только список");
      expect(input().placeholder === "Выберите адресата", `после набора без выбора в поле «${input().placeholder}»`);
      await confirmDialog(NOTE);
      expect(!$("modalDialog").hidden, "«Передать» с набранным, но не выбранным адресатом закрыла форму");
      // Фокус ушёл в «Причину» — список закрылся; адресаты — не в порядке Tab (BUG-44)
      await click(input());
      expect([...menu().querySelectorAll("[data-target-pick]")].every((o) => o.tabIndex === -1), "адресаты списка — в порядке Tab");
      field("comment").focus();
      // Окно не активно (запустили и ушли на другую вкладку) — браузер переносит фокус без события ухода: оно — вручную
      if (!document.hasFocus()) input().dispatchEvent(new FocusEvent("focusout", { bubbles: true, relatedTarget: field("comment") }));
      await wait();
      expect(!menu(), "фокус ушёл в «Причину», а список адресатов открыт");
      // Клавиши (PROC-21): ↓ открывает список и ведёт к адресатам, ↑ с первого — обратно в поле, Enter — первый подходящий
      const key = (el, k) => el.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true }));
      key(input(), "ArrowDown");
      await wait();
      expect(menu(), "↓ в поле не открыл список");
      key(input(), "ArrowDown");
      await wait();
      const first = menu().querySelector(".target-opt:not([hidden])");
      expect(document.activeElement === first, "↓ не перевёл фокус на первого адресата");
      key(first, "ArrowUp");
      await wait();
      expect(document.activeElement === input(), "↑ с первого адресата не вернул фокус в поле");
      input().value = "сид";
      input().dispatchEvent(new Event("input", { bubbles: true }));
      await wait();
      key(input(), "Enter");
      await wait();
      expect(!menu() && field("targetId").value === "sidorov", `Enter по «сид» выбрал «${field("targetId").value}», список ${menu() ? "открыт" : "закрыт"}`);
      await click(input());
      await click(menu().querySelector('[data-target-pick="petrova"]'));
      expect(!menu() && field("targetId").value === "petrova", "Петрова не выбрана");
      expect(input().placeholder === "Петрова М.", `в поле «${input().placeholder}»`);
      await confirmDialog(NOTE);
      expect(mode() === "queue", "после «Передать» карточка не закрылась");
    }, "Возобновить");

    await step("Адресат смотрит карточку до «Принять» (BUG-60)", async () => {
      await setFilter("inbox");
      for (const n of ["INC-1843", "INC-1836"]) {
        const id = guidOf(n);
        const row = $("eventsList").querySelector(`[data-id="${id}"]`);
        expect(row, `${n} нет в «Мне на принятие»`);
        const first = row.querySelector(".event-acts [data-do]");
        expect(first && first.dataset.do === "accept", `${n}: первая в колонке «${first ? first.dataset.do : "нет"}», а нужно «Принять»`);
        expect(row.querySelector('.event-open[data-do="view"]'), `${n}: нет значка «Посмотреть» у названия`);
        await click(button($("eventsList"), "view", id));
        expect(mode() === "work", `${n}: карточка адресата не открылась`);
        for (const a of ["accept", "reject", "transfer"]) expect(button(root(), a), `${n}: в карточке нет кнопки ${a}`);
        expect(!button(root(), "takeover"), `${n}: в карточке адресата «Перехватить» — принимают, а не перехватывают (BUG-55)`);
        await click($("backToQueue"));
        const badge = $("eventsList").querySelector(`[data-id="${id}"] .badge`);
        expect(badge && /Вам на принятие|Вашей группе/.test(badge.textContent), `${n}: после просмотра бейдж «${badge ? badge.textContent : "нет"}»`);
      }
      return "INC-1843, INC-1836";
    });

    await step("«Посмотреть» — значок у каждого инцидента; открывает карточку, ничего не меняя (RULE-80, RULE-81)", async () => {
      await setFilter("all");
      const rows = [...$("eventsList").querySelectorAll(".event")];
      const without = rows.filter((r) => !r.querySelector('.event-open[data-do="view"]'));
      expect(rows.length && !without.length, `без значка: ${without.map((r) => r.querySelector(".event-sub").textContent.split(" ·")[0]).join(", ") || "строк нет"}`);
      const eye = rows[0].querySelector('.event-open[data-do="view"]');
      expect(eye.getAttribute("aria-label").startsWith("Посмотреть: ") && eye.title && eye.querySelector(".event-eye") && eye.querySelector("strong"), `подпись «${eye.getAttribute("aria-label")}», подсказка «${eye.title}»: глаз и название — одна кнопка`);
      expect(!$("eventsList").querySelector('.event-acts [data-do="view"]'), "«Посмотреть» попала в колонку кнопок");
      // Свой отложенный — карточка с «Возобновить», остаётся отложенным; новый — с «Взять», остаётся новым
      await setFilter("open");
      const fresh = $("eventsList").querySelector('.event [data-do="claim"]');
      expect(fresh, "в «Открытых» нет нового");
      const freshId = fresh.closest(".event").dataset.id;
      for (const [id, filter, act, still] of [[guidOf("INC-1834"), "mine", "resume", "Отложен"], [freshId, "open", "claim", "Новое"]]) {
        await setFilter(filter);
        const row = await rowOnPages(id);
        const n = row ? row.querySelector(".event-sub").textContent.split(" ·")[0] : id;
        expect(row, `${n} нет в списке`);
        await click(row.querySelector('[data-do="view"]'));
        expect(mode() === "work", `${n}: карточка не открылась`);
        expect(button(root(), act), `${n}: в карточке нет ${act}`);
        await click($("backToQueue"));
        const badge = (await rowOnPages(id)).querySelector(".badge");
        expect(badge.textContent.includes(still), `${n}: после просмотра бейдж «${badge.textContent}»`);
      }
      return `${rows.length} строк; свой отложенный и новый открыты и не изменились`;
    });

    await step("Отклонить адресованную передачу", async () => {
      await setFilter("inbox");
      const badge = $("eventsList").querySelector(`[data-id="${guidOf("INC-1843")}"] .badge`);
      expect(badge && badge.textContent.includes("Вам на принятие"), `у адресованного лично бейдж «${badge ? badge.textContent : "нет"}»`);
      const b = button($("eventsList"), "reject", guidOf("INC-1843"));
      expect(b, "у INC-1843 нет кнопки «Отклонить»");
      await click(b);
      await confirmDialog(NOTE);
      await setFilter("open");
      const row = await rowOnPages(guidOf("INC-1843"));
      const text = row ? row.textContent : "";
      expect(text.includes("Новое"), "после «Отклонить» инцидент не стал новым");
      // Уровень меняет только автоэскалация: INC-1843 передан вручную — уровня нет и после «Отклонить» (RULE-76)
      expect(!text.includes("ур."), "после «Отклонить» у вручную переданного появился уровень эскалации");
      return "INC-1843";
    });

    await step("Принять адресованную передачу", async () => {
      await setFilter("inbox");
      const badge = $("eventsList").querySelector(`[data-id="${guidOf("INC-1836")}"] .badge`);
      expect(badge && badge.textContent.includes("Вашей группе"), `у переданного группе бейдж «${badge ? badge.textContent : "нет"}»`);
      const b = button($("eventsList"), "accept", guidOf("INC-1836"));
      expect(b, "нет инцидентов на принятие");
      acceptedId = b.dataset.ev;
      await click(b);
      expect(mode() === "work", "карточка не открылась");
      acceptedLeft = resolutionLeft();
      // Даём нормативу закрытия пройти, чтобы потом отличить продолжение от перезапуска
      await wait(2500);
      return acceptedId;
    });

    await step("Вернуть в очередь", async () => {
      // Норматив закрытия шёл, пока инцидент был в работе: часы стенда стоят — сдвинуть на 5 с. Отсчёт — по
      // времени сервера (BUG-103), часы пульта на него не влияют
      if (window.IM_SELFTEST_API) {
        await window.IM_SELFTEST_API.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        await window.IM_SELFTEST_API.raw("POST", "/test/clock", { advanceSec: 5 });
      }
      await openOwn(acceptedId);
      const b = button(root(), "release");
      expect(b, "в карточке нет кнопки «Вернуть в очередь»");
      await click(b);
      await confirmDialog(NOTE);
      expect(mode() === "queue", "после возврата карточка не закрылась");
    }, "Принять адресованную передачу");

    await step("Норматив закрытия не обнуляется при возврате в очередь", async () => {
      expect(acceptedLeft != null, "при «Принять» не было отсчёта норматива закрытия");
      await setFilter("open");
      let b = button($("eventsList"), "claim", acceptedId);
      for (let page = 2; !b && page <= 20; page++) {
        const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
        if (!nav || nav.disabled) break;
        await click(nav);
        b = button($("eventsList"), "claim", acceptedId);
      }
      expect(b, `${acceptedId} нет в очереди`);
      await click(b);
      const left = resolutionLeft();
      expect(left != null && left < acceptedLeft, `было ${acceptedLeft} с, после повторного взятия ${left} с`);
      return `${acceptedLeft} → ${left} с`;
    }, "Вернуть в очередь");

    await step("Закрыть с результатом «Ложная тревога» без сценария", async () => {
      await openOwn(acceptedId);
      const b = button(root(), "close");
      expect(b, "в карточке нет кнопки «Закрыть»");
      await click(b);
      // «Закрыть без обработки»: «Обработан» в форме нет — им закрывает «Итог»
      expect(/без обработки/.test(b.textContent), `кнопка закрытия — «${b.textContent.trim()}»`);
      expect(!field("resultId").querySelector('option[value="processed"]'), "в форме «Закрыть без обработки» есть «Обработан»");
      await setField("resultId", "false_alarm");
      await click($("dialogConfirm"));
      expect(!$("modalDialog").hidden, "закрылось без обязательной причины");
      await setField("causeId", "animal");
      await confirmDialog(NOTE);
      expect(mode() === "queue", "после закрытия карточка не закрылась");
      await setFilter("done");
      let row = $("eventsList").querySelector(`[data-id="${acceptedId}"]`);
      for (let page = 2; !row && page <= 20; page++) {
        const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
        if (!nav || nav.disabled) break;
        await click(nav);
        row = $("eventsList").querySelector(`[data-id="${acceptedId}"]`);
      }
      expect(row && row.textContent.includes("Ложная тревога"), `${acceptedId} не помечен результатом «Ложная тревога»`);
      await setFilter("open");
      return acceptedId;
    }, "Норматив закрытия не обнуляется при возврате в очередь");

    await step("Причина закрытия по результату (ТЗ-4): список — по forValues, смена результата очищает причину, «Другое» требует комментарий, карточка и журнал — снимок", async () => {
      const W = window.IM_WORKFLOW;
      // Набор пунктов, без порядка: список идёт по названию (§2.2), порядок проверяет свой шаг
      const ids = (c) => W.reasonCatalogs[c].items.map((i) => i.id).sort().join(",");
      // Предлагаемые варианты причины — видимые и доступные, без подсказки
      const offered = () => [...field("causeId").options].filter((o) => o.value && !o.hidden && !o.disabled).map((o) => o.value).sort().join(",");
      const starred = (name) => /\*\s*$/.test(($("dialogFields").querySelector(`[data-label-for="${name}"]`) || {}).textContent || "");
      const stand = window.IM_SELFTEST_API;
      if (mode() !== "queue") await click($("backToQueue"));
      await setFilter("open");
      const b = button($("eventsList"), "claim");
      expect(b, "нет доступной кнопки «Взять»");
      const id = b.dataset.ev;
      try {
        await click(b);
        expect(mode() === "work", "карточка не открылась");
        await click(button(root(), "close"));
        await setField("resultId", "false_alarm");
        expect(offered() === ids("false_alarm_cause"), `у «Ложной тревоги» причины: ${offered()}`);
        await setField("causeId", "animal");
        await setField("resultId", "mass");
        expect(field("causeId").value === "", `смена результата не очистила причину: «${field("causeId").value}»`);
        expect(offered() === ids("mass_fault"), `у «Массового сбоя» причины: ${offered()}`);
        await setField("resultId", "false_alarm");
        await setField("causeId", "animal");
        expect(!starred("comment"), "у «Животные» комментарий помечен обязательным");
        await setField("causeId", "other");
        expect(starred("comment"), "у «Другое» комментарий не помечен обязательным");
        field("comment").value = "";
        await click($("dialogConfirm"));
        expect(!$("modalDialog").hidden, "«Другое» закрылось без комментария");
        await setField("causeId", "animal");
        field("comment").value = "";
        await click($("dialogConfirm"));
        await wait(200);
        const card = (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(id)}`)).body;
        const animal = window.IM_STRINGS.ru["workflow.catalog.false_alarm_cause.animal"];
        expect(card.state === "closed" && card.closeCauseId === "animal", `не закрыт с причиной animal: ${card.state}, ${card.closeCauseId}`);
        expect(card.closeCauseLabel === animal, `снимок — не текст названия: «${card.closeCauseLabel}»`);
        const close = card.journal.filter((j) => j.templateKey === "workflow.journal.close").pop();
        expect(close && close.text.includes(animal), `в журнале закрытия нет причины: «${close && close.text}»`);
        // Причину удалили из справочника, а инцидент с ней закрыт: карточка показывает снимок, а не код
        const fx = window.IM_FIXTURE;
        const gone = Object.assign(JSON.parse(JSON.stringify(fx.incidents.find((i) => i.number === "INC-1837"))), { closeResult: "false_alarm", closeCause: "removed_cause", closeCauseLabel: "Сорока на датчике" });
        await standReset({ fixture: "demo", fixturePatch: { incidents: fx.incidents.map((i) => (i.number === "INC-1837" ? gone : i)) } });
        await wait(100);
        const old = (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(gone.guid)}`)).body;
        expect(old.closeCauseLabel === "Сорока на датчике", `снимок удалённой причины: «${old.closeCauseLabel}»`);
        await setFilter("done");
        const view = await buttonOnPages("view", gone.guid);
        expect(view, "у закрытого INC-1837 нет «Посмотреть»");
        await click(view);
        expect(root().textContent.includes("Сорока на датчике"), "карточка закрытого не показывает снимок причины");
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await setFilter("open");
        await wait(100);
      }
    });

    await step("Стартовый набор настроек поста (§20, решение 2026-11-15): новый пост получает причины из файла набора; заданный список, и пустой тоже, не трогается", async () => {
      const stand = window.IM_SELFTEST_API;
      const D = window.IM_POST_DEFAULTS;
      const P = window.IMPostSettings;
      expect(D && P && typeof P.withDefaults === "function", "нет стартового набора (post-defaults.js) или IMPostSettings.withDefaults");
      const ids = (list) => (list || []).map((x) => x.id);
      const holdIds = (w) => ids(w.reasonCatalogs.hold.items.filter((r) => r.setBy !== "system"));
      // Новый пост (ни одной версии): весь набор — версией 1; сброс стенда — тот же новый пост
      await standReset({ fixture: "demo" });
      const served = (await stand.raw("GET", "/operator/workflow/active")).body;
      expect(JSON.stringify(holdIds(served)) === JSON.stringify(ids(D.reasonCatalogs.hold.items)), `причины удержания поста не из набора: ${holdIds(served)}`);
      ["mass_fault", "false_alarm_cause"].forEach((c) =>
        expect(JSON.stringify(ids(served.reasonCatalogs[c].items)) === JSON.stringify(ids(D.reasonCatalogs[c].items)), `${c}: пункты поста не из набора: ${ids(served.reasonCatalogs[c].items)}`)
      );
      expect(JSON.stringify(ids(served.session.breakReasons)) === JSON.stringify(ids(D.session.breakReasons)), `причины перерыва поста не из набора: ${ids(served.session.breakReasons)}`);
      const fresh = P.withDefaults(null, D);
      expect(JSON.stringify(fresh.settings) === JSON.stringify(D) && fresh.added.length === 4, `новому посту не весь набор: ${JSON.stringify(fresh.added)}`);
      // Существующий пост: ложатся только списки, которых в опубликованных настройках нет; очищенный ([]) — пуст
      const published = { reasonCatalogs: { false_alarm_cause: { items: [] } }, session: { breakReasons: [{ id: "own", labelKey: "workflow.session.state.not_ready" }] } };
      const once = P.withDefaults(published, D);
      expect(JSON.stringify(once.added) === JSON.stringify(["reasonCatalogs.hold.items", "reasonCatalogs.mass_fault.items"]), `добавлены не те списки: ${JSON.stringify(once.added)}`);
      expect(once.settings.reasonCatalogs.false_alarm_cause.items.length === 0, "очищенный список ложных тревог вернулся из набора");
      expect(JSON.stringify(ids(once.settings.session.breakReasons)) === '["own"]', "заданные причины перерыва заменены набором");
      expect(published.reasonCatalogs.hold === undefined, "опубликованные настройки изменены на месте");
      const W = P.apply(P.base, once.settings);
      expect(W.reasonCatalogs.false_alarm_cause.items.length === 0, "у очищенного списка на машине поста есть пункты");
      expect(JSON.stringify(holdIds(W)) === JSON.stringify(ids(D.reasonCatalogs.hold.items)), "причины удержания набора не легли на машину поста");
      // Всё задано — новой версии нет; повтор шага ничего не добавляет
      expect(P.withDefaults(once.settings, D).added.length === 0, "повторный шаг добавил списки");
      // Черновик администратора: при публикации списки, которых в нём нет, берутся из новой версии
      const draft = P.withDefaults({ reasonCatalogs: { hold: { items: [] } } }, D, once.added);
      expect(JSON.stringify(draft.added) === '["reasonCatalogs.mass_fault.items"]' && draft.settings.reasonCatalogs.hold.items.length === 0, `черновик пересчитан неверно: ${JSON.stringify(draft.added)}`);
    });

    await step("Сброс — пост как новый (§20, решение 2026-11-15): после прогона с очищенными списками сброс возвращает причины стартового набора", async () => {
      const stand = window.IM_SELFTEST_API;
      const D = window.IM_POST_DEFAULTS;
      const ids = (list) => JSON.stringify((list || []).filter((r) => r.setBy !== "system").map((x) => x.id));
      const lists = (w) => ({ hold: ids(w.reasonCatalogs.hold.items), mass: ids(w.reasonCatalogs.mass_fault.items), fa: ids(w.reasonCatalogs.false_alarm_cause.items), br: ids(w.session.breakReasons) });
      const sys = window.IM_WORKFLOW.reasonCatalogs.hold.items.filter((r) => r.setBy === "system");
      try {
        await standReset({ fixture: "demo", workflowPatch: { reasonCatalogs: { hold: { items: sys }, mass_fault: { items: [] }, false_alarm_cause: { items: [] } }, session: { breakReasons: [] } } });
        const cleared = lists((await stand.raw("GET", "/operator/workflow/active")).body);
        expect(Object.values(cleared).every((v) => v === "[]"), `списки поста не очистились: ${JSON.stringify(cleared)}`);
        await standReset({ fixture: "demo" });
        const after = lists((await stand.raw("GET", "/operator/workflow/active")).body);
        const want = { hold: ids(D.reasonCatalogs.hold.items), mass: ids(D.reasonCatalogs.mass_fault.items), fa: ids(D.reasonCatalogs.false_alarm_cause.items), br: ids(D.session.breakReasons) };
        expect(JSON.stringify(after) === JSON.stringify(want), `после сброса причины не из стартового набора: ${JSON.stringify(after)}`);
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
      }
    });

    await step("Справочник причин без пунктов (решение 2026-11-15): причина не нужна и поля нет; есть пункт — без причины отказ; нет причин удержания — «Отложить» нет", async () => {
      const stand = window.IM_SELFTEST_API;
      const W = window.IM_WORKFLOW;
      const sys = W.reasonCatalogs.hold.items.filter((r) => r.setBy === "system");
      const act = async (guid, tr, formValues) => {
        const card = await stand.raw("GET", `/operator/incidents/${encodeURIComponent(guid)}`);
        return stand.raw("POST", `/operator/incidents/${encodeURIComponent(guid)}/transitions/${tr}`, Object.assign({ formValues, surface: "card" }, seenBody(card.body)));
      };
      try {
        // Пустые справочники: машина задаёт только устройство, пунктов заводит администратор поста
        await standReset({ fixture: "demo", workflowPatch: { reasonCatalogs: { false_alarm_cause: { items: [] }, hold: { items: sys } } } });
        await wait(100);
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
        const b = button($("eventsList"), "claim");
        expect(b, "нет доступной кнопки «Взять»");
        const id = b.dataset.ev;
        await click(b);
        expect(mode() === "work", "карточка не открылась");
        expect(!button(root(), "hold"), "без причин удержания «Отложить» доступно");
        const held = await act(id, "hold", { reasonId: "break", comment: "" });
        expect(held.status >= 400, `отложено без причин оператора: ${held.status}`);
        await click(button(root(), "close"));
        await setField("resultId", "false_alarm");
        const box = $("dialogFields").querySelector('[data-field-box="causeId"]');
        expect(!box || box.hidden, "у пустого справочника поле причины видно");
        await click($("dialogConfirm"));
        await wait(200);
        const card = (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(id)}`)).body;
        expect(card.state === "closed" && !card.closeCauseId, `ложная тревога без причины не закрылась: ${card.state}, ${card.closeCauseId}`);
        // Пункт есть — причина обязательна
        await standReset({ fixture: "demo", workflowPatch: { reasonCatalogs: { false_alarm_cause: { items: [{ id: "bird", labelKey: "workflow.form.close.field.causeId", setBy: "operator" }] } } } });
        await wait(100);
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
        const b2 = button($("eventsList"), "claim");
        expect(b2, "нет доступной кнопки «Взять»");
        const inc = { guid: b2.dataset.ev };
        await click(b2);
        if (mode() !== "queue") await click($("backToQueue"));
        const bad = await act(inc.guid, "close", { resultId: "false_alarm", causeId: "", comment: "" });
        expect(bad.status >= 400, `закрыто без причины при непустом справочнике: ${bad.status}`);
        const ok = await act(inc.guid, "close", { resultId: "false_alarm", causeId: "bird", comment: "" });
        expect(ok.status === 200, `с причиной не закрылось: ${ok.status} ${JSON.stringify(ok.body)}`);
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await setFilter("open");
        await wait(100);
      }
    });

    await step("Списки причин — по алфавиту (решение 2026-11-15): перерыв, «Отложить», причины ложной тревоги и массового сбоя, вкладка «Причины» — по названию, а не по порядку настроек поста", async () => {
      const W = window.IM_WORKFLOW;
      const own = (items) => items.filter((r) => r.setBy !== "system");
      const sys = W.reasonCatalogs.hold.items.filter((r) => r.setBy === "system");
      // Настройки поста — в обратном порядке стартового набора: порядок списка от них не зависит
      const rev = (items) => items.slice().reverse();
      const patch = {
        session: { breakReasons: rev(W.session.breakReasons) },
        reasonCatalogs: {
          hold: { items: rev(own(W.reasonCatalogs.hold.items)).concat(sys) },
          false_alarm_cause: { items: rev(W.reasonCatalogs.false_alarm_cause.items) },
          mass_fault: { items: rev(W.reasonCatalogs.mass_fault.items) },
        },
      };
      const coll = new Intl.Collator("ru", { sensitivity: "base", numeric: true });
      const byName = (list) => list.every((x, i) => i === 0 || coll.compare(list[i - 1], x) <= 0);
      const shown = (name) => [...field(name).options].filter((o) => o.value && !o.hidden).map((o) => o.textContent.trim());
      const check = (name, what, n) => {
        const list = shown(name);
        expect(list.length === n, `${what}: в списке ${list.length} пунктов, а не ${n}: ${list.join(", ")}`);
        expect(byName(list), `${what} — не по алфавиту: ${list.join(", ")}`);
      };
      try {
        await standReset({ fixture: "demo", workflowPatch: patch });
        await wait(100);
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
        const b = button($("eventsList"), "claim");
        expect(b, "нет доступной кнопки «Взять»");
        await click(b);
        expect(mode() === "work", "карточка не открылась");
        await click(button(root(), "hold"));
        check("reasonId", "причины «Отложить»", own(W.reasonCatalogs.hold.items).length);
        document.querySelector('[data-close="modalDialog"]').click();
        await click(button(root(), "close"));
        await setField("resultId", "false_alarm");
        check("causeId", "причины ложной тревоги", W.reasonCatalogs.false_alarm_cause.items.length);
        // «Другое» — на своём месте по букве, а не в конце
        const other = window.IM_STRINGS.ru["workflow.catalog.false_alarm_cause.other"];
        const list = shown("causeId");
        expect(list.indexOf(other) >= 0 && list.indexOf(other) < list.length - 1, `«${other}» не на своём месте: ${list.join(", ")}`);
        await setField("resultId", "mass");
        check("causeId", "причины массового сбоя", W.reasonCatalogs.mass_fault.items.length);
        document.querySelector('[data-close="modalDialog"]').click();
        await click($("backToQueue"));
        await click($("breakBtn"));
        check("reasonId", "причины перерыва", W.session.breakReasons.length);
        document.querySelector('[data-close="modalDialog"]').click();
        // Вкладка «Причины» настроек: каждый список — по названию
        await click($("adminBtn"));
        await click($("adminTabs").querySelector('[data-admin-tab="reasons"]'));
        const rows = [...$("adminTable").querySelectorAll("tbody tr")].filter((r) => r.cells.length === 2);
        expect(rows.length >= 4, `на вкладке «Причины» ${rows.length} строк`);
        rows.forEach((r) => {
          const lines = r.cells[1].innerHTML.split("<br>").map((h) => {
            const d = document.createElement("div");
            d.innerHTML = h;
            return d.textContent.trim();
          });
          expect(byName(lines), `«${r.cells[0].textContent.trim()}» на вкладке — не по алфавиту: ${lines.join(", ")}`);
        });
        await click(document.querySelector('[data-close="modalAdmin"]'));
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        if (!$("modalAdmin").hidden) document.querySelector('[data-close="modalAdmin"]').click();
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
        await setFilter("open");
      }
    });

    await step("Причины перерыва без пунктов (решение 2026-11-15): пустой список — перерыв без причины, поля нет; есть пункт — без причины отказ", async () => {
      const stand = window.IM_SELFTEST_API;
      const put = (body) => stand.raw("PUT", "/operator/session/agent-state", body);
      try {
        await standReset({ fixture: "demo", workflowPatch: { session: { breakReasons: [] } } });
        await wait(100);
        if (mode() !== "queue") await click($("backToQueue"));
        await click($("breakBtn"));
        expect(!$("modalDialog").hidden, "форма перерыва не открылась");
        expect(!field("reasonId"), "при пустом списке причин поле причины есть");
        await click($("dialogConfirm"));
        await wait(200);
        expect(!$("breakBanner").hidden, "без причин оператор не ушёл на перерыв");
        await click($("breakBtn"));
        await wait(200);
        expect($("breakBanner").hidden, "не вернулся с перерыва");
        await standReset({ fixture: "demo", workflowPatch: { session: { breakReasons: [{ id: "probe", labelKey: "workflow.session.state.not_ready" }] } } });
        await wait(100);
        const bad = await put({ agentState: "not_ready" });
        expect(bad.status === 422, `перерыв без причины при непустом списке: ${bad.status}`);
        const ok = await put({ agentState: "not_ready", reasonId: "probe" });
        expect(ok.status === 200, `с причиной перерыв не начался: ${ok.status}`);
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        await standReset({ fixture: "demo" });
        await wait(100);
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
      }
    });

    await step("«Обработан» недоступен, пока сценарий не заполнен: в «Закрыть без обработки» его нет, «Итога» не открыть", async () => {
      await setFilter("open");
      const b = button($("eventsList"), "claim");
      expect(b, "нет доступной кнопки «Взять»");
      freshId = b.dataset.ev;
      await click(b);
      expect(mode() === "work", "карточка не открылась");
      const close = button(root(), "close");
      expect(close, "в карточке нет кнопки «Закрыть»");
      await click(close);
      const processed = field("resultId").querySelector('option[value="processed"]');
      const other = field("resultId").querySelector('option[value="false_alarm"]');
      expect(!processed, "в форме «Закрыть без обработки» есть «Обработан»");
      expect(root().querySelector(".summary-crumb.locked") && !root().querySelector("[data-crumb=summary]"), "на «Итог» можно перейти при пустом сценарии");
      expect(other && !other.disabled, "«Ложная тревога» недоступна");
      expect(field("resultId").value === "", `результат выбран за оператора: «${field("resultId").value}»`);
      await click($("dialogConfirm"));
      expect(!$("modalDialog").hidden, "закрылось без выбранного результата");
      document.querySelector('[data-close="modalDialog"]').click();
      await wait();
      return freshId;
    });

    await step("«К очереди» из своей карточки — инцидент остаётся в работе", async () => {
      await openOwn(freshId);
      await click($("backToQueue"));
      expect(mode() === "queue", "«К очереди» не вернула к очереди");
      await setFilter("mine");
      expect(button($("eventsList"), "open_card", freshId), `${freshId} больше не «В работе»`);
    }, "«Обработан» недоступен, пока сценарий не заполнен: в «Закрыть без обработки» его нет, «Итога» не открыть");

    await step("Перерыв с открытой карточкой: инцидент отложен, карточка — просмотр", async () => {
      await openOwn(freshId);
      await click($("breakBtn"));
      await confirmDialog();
      // Карточка не закрывается, а становится просмотром (§9, §14.8): править отложенный нельзя
      expect(mode() === "work", "на перерыве карточка закрылась, а должна стать просмотром");
      expect(!root().querySelector('#stepNext:not([aria-disabled="true"])'), "на перерыве сценарий можно править");
      await click($("backToQueue"));
      await setFilter("mine");
      const row = $("eventsList").querySelector(`[data-id="${freshId}"]`);
      const text = row ? row.textContent : "";
      await click($("breakBtn"));
      expect(text.includes("Перерыв оператора"), `${freshId} не отложен с причиной «Перерыв оператора»`);
    }, "«К очереди» из своей карточки — инцидент остаётся в работе");

    await step("Закрыть отложенный с результатом «Массовый сбой»", async () => {
      await setFilter("mine");
      const b = button($("eventsList"), "close", freshId);
      expect(b, `у отложенного ${freshId} нет кнопки «Закрыть»`);
      await click(b);
      expect(field("resultId").value === "mass", "в форме не выбран массовый сбой");
      expect(field("causeId") && !field("causeId").closest("[data-field-box]").hidden, "нет причины сбоя");
      expect(field("causeId").value === "", `причина сбоя выбрана за оператора: «${field("causeId").value}»`);
      await setField("causeId", "power");
      await confirmDialog(NOTE);
      await setFilter("done");
      const row = await rowOnPages(freshId);
      expect(row && row.textContent.includes("Закрыто ·"), `${freshId} не закрыт с результатом`);
    }, "Перерыв с открытой карточкой: инцидент отложен, карточка — просмотр");

    await step("Переоткрыть: инцидент в работе, результат очищен", async () => {
      await setFilter("done");
      const b = await buttonOnPages("reopen", freshId);
      expect(b, `у ${freshId} нет кнопки «Переоткрыть»`);
      await click(b);
      await confirmDialog(NOTE);
      expect(mode() === "work", "после переоткрытия карточка не открылась");
      expect($("statusSla").textContent.includes("Закрытие"), "норматив закрытия не идёт");
      // В режиме карточки очередь не перерисовывается: сначала к очереди
      await click($("backToQueue"));
      await setFilter("mine");
      const row = $("eventsList").querySelector(`[data-id="${freshId}"]`);
      expect(row && !row.textContent.includes("Закрыто"), `${freshId} всё ещё помечен закрытым`);
      // Освобождаем лимит активных для следующего шага
      await openOwn(freshId);
      await click(button(root(), "release"));
      await confirmDialog(NOTE);
    }, "Закрыть отложенный с результатом «Массовый сбой»");

    await step("Фильтр по типу устройства поверх группы", async () => {
      await setFilter("all");
      const total = $("eventsList").querySelectorAll(".event").length;
      await click($("deviceTypeFilter").querySelector("[data-tb-toggle]"));
      await click($("deviceTypeFilter").querySelector('[data-tb][value="fire-detector"]'));
      await wait();
      const rows = [...$("eventsList").querySelectorAll(".event")];
      const stray = rows.filter((r) => !r.textContent.includes("Пожарная тревога"));
      await click($("deviceTypeFilter").querySelector("[data-tb-clear]"));
      await click($("eventsList"));
      await setFilter("open");
      expect(rows.length, "по типу «Пожарный извещатель» ничего не нашлось");
      expect(!stray.length, `у пожарного извещателя нашлись события другого типа: ${stray.length}`);
      return `${rows.length} из ${total}`;
    });

    await step("Закрыть без обработки из очереди", async () => {
      await setFilter("open");
      const b = [...$("eventsList").querySelectorAll('[data-do="close"]')].find((x) => {
        const row = x.closest(".event");
        return !off(x) && row && row.querySelector('[data-do="claim"]');
      });
      expect(b, "у новых событий нет кнопки «Закрыть»");
      const id = b.dataset.ev;
      await click(b);
      // Причину сбоя за оператора не выбирают (RULE-110)
      if (field("resultId").value === "mass") {
        expect(field("causeId").value === "", `причина сбоя выбрана за оператора: «${field("causeId").value}»`);
        await setField("causeId", "power");
      }
      await confirmDialog(NOTE);
      await setFilter("open");
      expect(!$("eventsList").querySelector(`[data-id="${id}"]`), `${id} остался среди открытых`);
      return id;
    });

    await step("Фильтр по типу события поверх группы", async () => {
      await setFilter("all");
      const before = $("eventsList").querySelectorAll(".event").length;
      await click($("eventTypeFilter").querySelector("[data-tb-toggle]"));
      const box = $("eventTypeFilter").querySelector("[data-tb]");
      expect(box, "в фильтре нет ни одного типа события");
      const opt = { textContent: box.closest("label").textContent.trim() };
      await click(box);
      await wait();
      const rows = [...$("eventsList").querySelectorAll(".event")];
      const stray = rows.filter((r) => !r.textContent.includes(opt.textContent));
      await click($("eventTypeFilter").querySelector("[data-tb-clear]"));
      await click($("eventsList"));
      await setFilter("open");
      expect(rows.length, `по типу «${opt.textContent}» ничего не нашлось`);
      expect(!stray.length, `в выборке «${opt.textContent}» есть события другого типа: ${stray.length}`);
      return `${opt.textContent}: ${rows.length} из ${before}`;
    });

    await step("Фильтр «Сценарий»: в очереди только инциденты выбранного сценария (§19.2, ARCH-15)", async () => {
      await setFilter("all");
      const before = $("eventsList").querySelectorAll(".event").length;
      await click($("scenarioFilter").querySelector("[data-tb-toggle]"));
      const boxes = [...$("scenarioFilter").querySelectorAll("[data-tb]")];
      expect(boxes.length >= 2, "в фильтре меньше двух сценариев");
      const box = boxes.find((b) => b.closest("label").textContent.trim() === window.IM_FIXTURE.scenarios.rows.find((r) => r.guid === window.IM_FIXTURE.scenarios.keys.medical).name);
      expect(box, "в фильтре нет сценария медпункта");
      await click(box);
      await wait();
      const rows = [...$("eventsList").querySelectorAll(".event")];
      const stray = rows.filter((r) => !r.textContent.includes("INC-1853"));
      await click($("scenarioFilter").querySelector("[data-tb-clear]"));
      await click($("eventsList"));
      await setFilter("open");
      expect(rows.length, "по сценарию ничего не нашлось");
      expect(!stray.length, `в выборке есть инциденты другого сценария: ${stray.length}`);
      return `${rows.length} из ${before}`;
    });

    await step("Списки — поле с набором: текст отбирает варианты, Enter отмечает первый подходящий, Esc закрывает", async () => {
      const type = async (input, text) => {
        input.value = text;
        input.dispatchEvent(new Event("input", { bubbles: true }));
        await wait();
      };
      const press = async (input, key) => {
        input.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true }));
        await wait();
      };
      const field = () => $("deviceTypeFilter").querySelector("[data-tb-toggle]");
      // На узком окне (<1280, §7) типы — под «Фильтры»: поле скрыто, фокус в него не встанет
      const opened = !$("eventsTypes").offsetHeight;
      if (opened) await click($("eventsMoreBtn"));
      await setFilter("all");
      try {
        await click(field());
        const opts = () => [...$("deviceTypeFilter").querySelectorAll(".mselect-opt")];
        const all = opts().map((o) => o.textContent.trim());
        expect(all.length > 1, "в списке типов устройств меньше двух вариантов");
        const want = all[all.length - 1];
        await type(field(), want.toLowerCase());
        const shown = opts().filter((o) => !o.hidden).map((o) => o.textContent.trim());
        expect(shown.length < all.length && shown.includes(want), `набор «${want}» не отобрал варианты: ${shown.join(", ")}`);
        expect(document.activeElement === field(), "фокус ушёл из поля");
        await press(field(), "Enter");
        expect(field().title === shown[0], `Enter отметил «${field().title}», а не «${shown[0]}»`);
        expect(field().value === "" && document.activeElement === field(), "после отметки набранное не стёрлось или фокус ушёл из поля");
        await press(field(), "Escape");
        expect(!$("deviceTypeFilter").classList.contains("open"), "Esc не закрыл список");
        // Окно «Выделить по фильтру»: то же поле; ничего не подошло — «Нет вариантов»
        await click(document.querySelector('.tree-all [data-filter="select"]'));
        const events = () => $("groupingRows").querySelector('[data-ms-toggle="0:eventTypeIds"]');
        await click(events());
        await type(events(), "нет такого события");
        const menu = events().parentElement.querySelector(".mselect-menu");
        expect(menu && !menu.querySelector(".mselect-opt:not([hidden])"), "в окне фильтра набор не отобрал варианты");
        expect(!menu.querySelector("[data-combo-none]").hidden, "нет надписи «Нет вариантов»");
        await click(document.querySelector('[data-close="modalGrouping"]'));
        return `${want}: ${shown.length} из ${all.length}`;
      } finally {
        if (!$("modalGrouping").hidden) await click(document.querySelector('[data-close="modalGrouping"]'));
        await click(field());
        const clear = $("deviceTypeFilter").querySelector("[data-tb-clear]");
        if (clear) await click(clear);
        await click($("eventsList"));
        await setFilter("open");
        if (opened && $("eventsTypes").offsetHeight) await click($("eventsMoreBtn"));
      }
    });

    await step("Шапка очереди: числа без своей группы, блок «Мне на принятие» не прячется фильтрами и не повторяется в списке (§7, план 87в)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand && window.IM_SELFTEST_UI, "нет служебных операций стенда в режиме самопроверки");
      const UI = window.IM_SELFTEST_UI;
      const cfg = window.IM_WORKFLOW.display.inboxBlock;
      expect(JSON.stringify(UI.priorityLetters(["Критический", "Красный", "Высокий"])) === JSON.stringify(["Кри", "Кра", "В"]), `буквы приоритетов: ${UI.priorityLetters(["Критический", "Красный", "Высокий"])}`);
      expect([1600, 1400, 1100, 800].map(UI.headLayout).join() === "full,more,compact,phone", "раскладка шапки по ширине");
      const stateN = (id) => Number(([...$("eventFilter").options].find((o) => o.value === id) || { textContent: "" }).textContent.match(/(\d+)(?: \+\d+)?$/)?.[1]);
      const priBtns = () => [...$("priorityButtons").querySelectorAll("[data-pri]")];
      const priN = () => priBtns().map((b) => (b.querySelector(".n") ? Number(b.querySelector(".n").textContent) : null));
      const blockIds = () => [...$("eventsList").querySelectorAll(".inbox-row")].map((r) => r.dataset.id);
      const pressed = () => priBtns().filter((b) => b.getAttribute("aria-pressed") === "true").map((b) => Number(b.dataset.pri));
      if (mode() !== "queue") await click($("backToQueue"));
      try {
        await setFilter("open");
        await wait(200);
        const inbox = await stand.get("/operator/incidents", { filter: cfg.filter, sort: cfg.sort, pageSize: cfg.maxRows });
        const ids0 = blockIds();
        expect(ids0.join() === inbox.items.map((e) => e.guid).join(), `блок: ${ids0.length} строк, сервер: ${inbox.items.length}`);
        expect(inbox.total === 0 ? $("eventsList").querySelector(".inbox-block.empty") : true, "пустой блок — без строки «ничего нет»");
        const listIds = [...$("eventsList").querySelectorAll(".event")].map((r) => r.dataset.id);
        expect(!ids0.some((g) => listIds.includes(g)), "строка блока повторяется в списке");
        expect($("clearSelectionBtn").hidden, "«Снять» виден, а ничего не отмечено");
        // Приоритет, которого нет у строк блока: блок фильтром не прячется, числа остальных приоритетов не обнуляются
        const rowPri = new Set(inbox.items.map((e) => e.priority));
        const levels = priBtns().map((b) => Number(b.dataset.pri));
        const pick = levels.find((v) => !rowPri.has(v)) ?? levels[0];
        const before = priN();
        const openBefore = stateN("open");
        await click(priBtns().find((b) => Number(b.dataset.pri) === pick));
        await wait(200);
        expect(pressed().join() === String(pick), `выбранные приоритеты: ${pressed()}`);
        expect(priN().join() === before.join(), `числа приоритетов изменились от своего выбора: ${before} → ${priN()}`);
        const narrowed = await stand.get("/operator/incidents/counters", { priority: String(pick) });
        expect(stateN("open") === narrowed.open && stateN("open") <= openBefore, `«Открытые»: ${stateN("open")}, сервер: ${narrowed.open}`);
        expect(blockIds().join() === ids0.join(), "блок спрятан или изменён фильтром по приоритету");
        // Второй уровень — рядом с первым, а не вместо него
        const other = levels.find((v) => v !== pick);
        await click(priBtns().find((b) => Number(b.dataset.pri) === other));
        await wait(200);
        expect(pressed().length === 2, `второй приоритет заменил первый: ${pressed()}`);
        // «По фильтру…» (§11.2) берёт узел и состояние, без приоритетов и без блока: приоритеты шапки его не сужают
        const filterCount = async () => {
          await click(document.querySelector('.tree-all [data-filter="select"]'));
          await wait(100);
          const n = Number(($("groupingConfirm").textContent.match(/\d+/) || [NaN])[0]);
          await click(document.querySelector('[data-close="modalGrouping"]'));
          return n;
        };
        const byFilterNarrow = await filterCount();
        // «Мне на принятие» выбрано — блока нет: список и есть эти инциденты
        await setFilter(cfg.filter);
        await wait(200);
        expect(!$("eventsList").querySelector(".inbox-block"), "блок виден, когда выбрано «Мне на принятие»");
        // Фильтр без счётчиков: чисел на кнопках приоритетов нет
        await setFilter("done");
        await wait(200);
        expect(priN().every((n) => n == null) && !$("eventsList").querySelector(".inbox-block"), "у «Завершённых» есть числа приоритетов или блок");
        // Пусто после фильтров — «Сбросить фильтры»: возвращает «Открытые», снимает приоритеты и поиск
        $("eventSearch").value = "нет-такого-инцидента-zz";
        $("eventSearch").dispatchEvent(new Event("input", { bubbles: true }));
        await wait(100);
        const reset = $("eventsList").querySelector("[data-reset-filters]");
        expect(reset, "после фильтров пусто, а кнопки «Сбросить фильтры» нет");
        await click(reset);
        await wait(100);
        expect($("eventFilter").value === "open" && !pressed().length && $("eventSearch").value === "", `после сброса: ${$("eventFilter").value}, приоритетов ${pressed().length}, поиск «${$("eventSearch").value}»`);
        expect(blockIds().join() === ids0.join(), "после сброса блок другой");
        expect((await filterCount()) === byFilterNarrow, `«По фильтру…» зависит от приоритетов шапки: ${byFilterNarrow}`);
        return `блок ${ids0.length} из ${inbox.total}, приоритет ${pick}`;
      } finally {
        if (pressed().length) {
          for (const b of priBtns().filter((x) => x.getAttribute("aria-pressed") === "true")) await click(b);
        }
        await setFilter("open");
      }
    });

    await step("Новые строки и скрытое фильтром: freezeAbove держит всё выше курсора, hiddenBy — что прячет строку (§22.1, §22.3)", async () => {
      const ui = window.IM_SELFTEST_UI;
      const r = (guid, extra) => Object.assign({ guid }, extra || {});
      const ids = (rows) => rows.map((x) => x.guid + (x.gone ? "*" : "")).join(",");
      // b ушла, n пришла выше якоря c, e — ниже; a обновилась на месте
      const f = ui.freezeAbove([r("a"), r("b"), r("c"), r("d")], [r("n"), r("a", { v: 2 }), r("c"), r("d"), r("e")], "c");
      expect(ids(f.rows) === "a,b*,c,d,e" && ids(f.newAbove) === "n", `заморозка: ${ids(f.rows)} / новые ${ids(f.newAbove)}`);
      expect(f.rows[0].v === 2, "строка выше курсора не обновилась на месте");
      const free = ui.freezeAbove([r("a"), r("b")], [r("n"), r("a")], null);
      expect(ids(free.rows) === "n,a" && !free.newAbove.length, `без курсора: ${ids(free.rows)}`);
      const below = ui.freezeAbove([r("a"), r("b")], [r("a"), r("n"), r("b")], "a");
      expect(ids(below.rows) === "a,n,b" && !below.newAbove.length, `новая ниже курсора встаёт сразу: ${ids(below.rows)}`);
      const inc = { filters: ["open"], priority: 100, eventType: { guid: "T" }, sourceDeviceTypeId: "camera" };
      const q = (extra) => Object.assign({ filter: "open", priorities: [], eventTypes: [], deviceTypes: [], scenarios: [], groupId: "all", search: "", blockFilter: null }, extra);
      const why = (i, extra) => ui.hiddenBy(i, q(extra)).join(",");
      expect(why(inc, {}) === "", `ничего не прячет: ${why(inc, {})}`);
      expect(why(inc, { filter: "mine" }) === "filter", `«Мои»: ${why(inc, { filter: "mine" })}`);
      expect(why(inc, { priorities: [75] }) === "priority" && why(inc, { priorities: [75, 100] }) === "", "приоритеты");
      expect(why(inc, { eventTypes: ["U"], deviceTypes: ["door"] }) === "eventType,deviceType", `типы: ${why(inc, { eventTypes: ["U"], deviceTypes: ["door"] })}`);
      expect(why(inc, { scenarios: ["S"], groupId: "G", search: "x" }) === "scenario,node,search", "сценарий, узел и поиск — могут прятать");
      expect(why(Object.assign({}, inc, { filters: ["open", "inbox"] }), { filter: "mine", priorities: [75], blockFilter: "inbox" }) === "", "инцидент блока фильтрами не прячется");
      return "заморозка, сброс, hiddenBy";
    });

    await step("Раскладка: граница заморозки — по якорю в новом порядке; строка поста — серьёзное и «и ещё N», диск — только администратору; «Уже взял {who}» (§22.1, §22.4, §22.6)", async () => {
      const ui = window.IM_SELFTEST_UI;
      const r = (guid) => ({ guid });
      const ids = (rows) => rows.map((x) => x.guid + (x.gone ? "*" : "")).join(",");
      // a (выше якоря b) сервер увёл в самый низ: новая n под якорем — не «новая выше», встаёт сразу
      const moved = ui.freezeAbove([r("a"), r("b"), r("c")], [r("b"), r("c"), r("n"), r("a")], "b");
      expect(ids(moved.rows) === "a,b,c,n" && !moved.newAbove.length, `строка выше якоря ушла вниз: ${ids(moved.rows)} / новые ${ids(moved.newAbove)}`);
      // Якорь ушёл: граница — ближайшая замороженная над ним, что ещё есть
      const gone = ui.freezeAbove([r("a"), r("b"), r("c")], [r("n"), r("a"), r("m"), r("c")], "b");
      expect(ids(gone.rows) === "a,b*,m,c" && ids(gone.newAbove) === "n", `якорь ушёл: ${ids(gone.rows)} / новые ${ids(gone.newAbove)}`);
      const defs = window.IM_WORKFLOW.display.postStatus;
      expect(defs.map((d) => d.id).join() === "connection,disk,sound_off,maintenance,only_important", `порядок пунктов машины: ${defs.map((d) => d.id).join()}`);
      const line = (active, admin) => {
        const x = ui.postStatusLine(active, defs, admin);
        return `${x.top ? x.top.id : "—"}+${x.more}`;
      };
      expect(line(["only_important", "maintenance", "connection"], false) === "connection+2", `три состояния: ${line(["only_important", "maintenance", "connection"], false)}`);
      expect(line(["maintenance", "only_important"], false) === "maintenance+1", `работы и «Только важное»: ${line(["maintenance", "only_important"], false)}`);
      expect(line(["disk", "sound_off"], false) === "sound_off+0", `диск у оператора: ${line(["disk", "sound_off"], false)}`);
      expect(line(["disk", "sound_off"], true) === "disk+1", `диск у администратора: ${line(["disk", "sound_off"], true)}`);
      expect(line([], true) === "—+0", "без состояний строка пуста");
      // Отказ 412 INCIDENT_CHANGED (RULE-142): что изменилось — details.changed, кто теперь — current, без второго запроса
      // Ключ текста — как у сервера: «уже ведёт» (changed.taken) — только когда адресат теперь другой и он владелец
      const keyOf = (changed) => (changed === "addressee" ? "workflow.error.changed.taken" : `workflow.error.changed.${changed}`);
      const err = (code, changed, current, key = keyOf(changed)) => ({ status: 412, problem: { code, messageKey: key, details: { changed }, current } });
      const petrova = { owner: { id: "petrova", name: "Петрова Е. А." } };
      const late = (id, code, changed, current, key) => ui.lateText(id, err(code, changed, current, key), "me");
      expect(late("claim", "INCIDENT_CHANGED", "addressee", petrova) === "Уже взял Петрова Е. А.", `опоздал со «Взять»: ${late("claim", "INCIDENT_CHANGED", "addressee", petrova)}`);
      expect(late("accept", "INCIDENT_CHANGED", "addressee", petrova) === "Уже принял Петрова Е. А.", `опоздал с «Принять»: ${late("accept", "INCIDENT_CHANGED", "addressee", petrova)}`);
      expect(late("claim", "INCIDENT_CHANGED", "addressee", { owner: { id: "me" } }) === null && late("claim", "GUARD_FAILED", "addressee", petrova) === null && late("claim", "INCIDENT_CHANGED", "addressee", { owner: null }) === null, "«Уже взял» — не только когда инцидент у другого");
      // Изменилось не адресат (новое событие, состояние) — обычная ошибка с текстом сервера, не «опоздал»
      expect(late("claim", "INCIDENT_CHANGED", "news", petrova) === null && late("claim", "INCIDENT_CHANGED", "state", petrova) === null, "«Уже взял» без смены адресата");
      // Передан человеку, который ещё не принял, — не «опоздал»: текст сервера «…передан» (RULE-142, A1)
      expect(late("claim", "INCIDENT_CHANGED", "addressee", petrova, "workflow.error.changed.addressed") === null, "«Уже взял» о переданном, но не принятом");
      return "граница по якорю; connection+2, диск только администратору; «Уже взял Петрова Е. А.»";
    });

    await step("Итог моего действия — одна плашка в шапке справа от строки поста: 300 пропущенных — коротко, «ещё N», итог поверх ошибки на время, «✕» убирает все, колокольчик не растёт (§22.6, BUG-123)", async () => {
      const ui = window.IM_SELFTEST_UI;
      const shown = () => [...$("toasts").children].filter((x) => !x.hidden);
      const one = () => {
        const v = shown();
        expect(v.length <= 1, `плашек сразу: ${v.length}`);
        return v[0] || null;
      };
      const rect = (el) => el.getBoundingClientRect();
      const bellCount = () => `${$("bellCount").hidden ? 0 : $("bellCount").textContent}/${$("bellList").children.length}`;
      const bellAt = bellCount();
      const out = [];
      ui.toastMs(60);
      try {
        // Ошибки прежних шагов — «✕»: отсюда счёт «ещё N» с нуля
        const left = $("toasts").querySelector(".toast-close");
        if (left) await click(left);
        await wait(100);
        // 300 пропущенных выборки — синтетикой: число и причина, номера — два и «и ещё N»
        const skipped = Array.from({ length: 300 }, (_, i) => ({ incidentGuid: `g${i}`, number: `INC-${9000 + i}`, reasonKey: "workflow.error.selection.other_scenario" }));
        const big = ui.skippedText(skipped);
        expect(big === "Не закрыты: 300 — другой сценарий: INC-9000, INC-9001 и ещё 298", `300 пропущенных: «${big}»`);
        const few = ui.skippedText(skipped.slice(0, 5));
        expect(few === "Не закрыты: 5 — другой сценарий: INC-9000, INC-9001, INC-9002, INC-9003, INC-9004", `5 пропущенных: «${few}»`);
        const first = `Закрыто: 120. ${big}`;
        ui.toast(first, "error");
        const a = one();
        expect(a && a.dataset.kind === "error" && a.textContent === first, `плашка ошибки: «${a && a.textContent}»`);
        // Плашка — в шапке (широкое окно) или сразу под ней (узкое), одной строкой; «✕» на экране
        const bar = rect(document.querySelector(".topbar"));
        const box = rect(a);
        const x = rect(a.querySelector(".toast-close"));
        expect(box.height <= 40 && box.height <= innerHeight / 3, `высота плашки ${Math.round(box.height)} px при окне ${innerHeight}`);
        expect(box.top >= bar.top - 1 && box.top <= bar.bottom + 8, `плашка не в шапке и не сразу под ней: ${Math.round(box.top)} при шапке ${Math.round(bar.top)}–${Math.round(bar.bottom)}`);
        expect(x.width > 0 && x.left >= 0 && x.right <= innerWidth && x.top >= 0 && x.bottom <= innerHeight, "«✕» не на экране");
        expect(a.title === first, `нет подсказки с полным текстом: «${a.title}»`);
        // Вторая ошибка заменяет первую, на плашке «ещё 1»; нажатие — список прежних под плашкой
        const second = "Ошибка самопроверки: вторая";
        ui.toast(second, "error");
        const b = one();
        expect(b.textContent === second && b.querySelector("[data-toast-more]") && b.querySelector("[data-toast-more]").dataset.toastMore === "ещё 1", `вторая ошибка: «${b.textContent}», «${(b.querySelector("[data-toast-more]") || {}).dataset ? b.querySelector("[data-toast-more]").dataset.toastMore : "нет"}»`);
        await click(b.querySelector(".toast-text"));
        const list = $("toastList");
        expect(!list.hidden && list.textContent.includes(first) && list.textContent.includes(second), `список ошибок: «${list.hidden ? "скрыт" : list.textContent}»`);
        expect(rect(list).height <= innerHeight / 3 + 1, `список выше трети экрана: ${Math.round(rect(list).height)} px`);
        await click(b.querySelector(".toast-text"));
        expect(list.hidden, "второе нажатие не убрало список");
        // Щелчок в списке его не закрывает, мимо — закрывает; Esc — тоже
        await click(b.querySelector(".toast-text"));
        await click(list);
        expect(!list.hidden, "щелчок в списке его закрыл");
        await click(document.querySelector(".brand"));
        expect(list.hidden, "щелчок мимо не закрыл список");
        await click(b.querySelector(".toast-text"));
        document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
        expect(list.hidden, "Esc не закрыл список");
        // Итог при висящей ошибке — поверх неё на время, затем ошибка возвращается
        const done = "Итог самопроверки: обработано";
        ui.toast(done);
        const c = one();
        expect(c && c.dataset.kind === "done" && c.textContent === done && !c.querySelector(".toast-close"), `итог поверх ошибки: «${c && c.textContent}»`);
        await wait(200);
        const d = one();
        expect(d && d.dataset.kind === "error" && d.textContent === second, `после итога не вернулась ошибка: «${d && d.textContent}»`);
        // Новый итог заменяет прежний
        ui.toast("Итог 1");
        ui.toast("Итог 2");
        expect(one().textContent === "Итог 2" && ![...$("toasts").children].some((y) => y.textContent === "Итог 1"), "новый итог не заменил прежний");
        await wait(200);
        // «✕» убирает все ошибки
        await click(one().querySelector(".toast-close"));
        expect(!one(), "«✕» убрал не все ошибки");
        // Без ошибок итог уходит сам
        ui.toast("Итог 3");
        await wait(200);
        expect(!one(), "итог не ушёл сам");
        expect(bellCount() === bellAt, `колокольчик изменился: ${bellAt} → ${bellCount()}`);
        out.push(`${Math.round(box.width)}×${Math.round(box.height)} px`, big);
      } finally {
        ui.toastMs(null);
        $("toasts").replaceChildren();
        $("toastList").hidden = true;
      }
      return out.join("; ");
    });

    await step("Перерыв и возврат с перерыва", async () => {
      await click($("breakBtn"));
      expect(field("reasonId"), "перерыв не спросил причину");
      await confirmDialog();
      expect(!$("breakBanner").hidden, "плашка перерыва не появилась");
      await click($("breakReturn"));
      expect($("breakBanner").hidden, "кнопка на плашке не вернула с перерыва");
    });

    await step("Меню справки: общие ссылки и ссылка группы — только при инциденте её устройств (§7, RULE-49)", async () => {
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
      // Площадка — группа устройств (§1): ссылка группы Торгового центра — у инцидентов, источник которых в нём
      const fx = window.IM_FIXTURE;
      const inGroup = (gid) => {
        const find = (groups) => groups.reduce((hit, g) => hit || (g.id === gid ? g : find(g.groups || [])), null);
        const all = (g) => (g.devices || []).concat(...(g.groups || []).map(all));
        return new Set(all(find(fx.sourceGroups)));
      };
      const evacLink = fx.helpLinks.find((l) => l.scope === "group");
      const mallDevices = inGroup(evacLink.groupGuid);
      const sourceIn = (id) => mallDevices.has((fx.incidents.find((i) => i.guid === id) || { devices: [] }).devices[0]);
      // Строки одиночных событий: у строки группы события могут быть с разных площадок
      const rows = [...$("eventsList").querySelectorAll(".event:not(.event-group)")].filter((r) => fx.incidents.some((i) => i.guid === r.dataset.id));
      const mall = rows.find((r) => sourceIn(r.dataset.id));
      const other = rows.find((r) => !sourceIn(r.dataset.id));
      expect(mall && other, "в очереди нет инцидентов ТЦ и других площадок");
      // Строку ищем заново: после щелчка очередь перерисовывается
      const linksFor = async (row) => {
        await click($("eventsList").querySelector(`.event[data-id="${row.dataset.id}"]`));
        await click($("helpBtn"));
        await wait(150);
        const text = $("helpLinks").textContent;
        document.body.click();
        return text;
      };
      const evac = evacLink.title;
      const common = fx.helpLinks.find((l) => l.scope === "shared").title;
      const atOther = await linksFor(other);
      expect(atOther.includes(common) && !atOther.includes(evac), `не в ТЦ: «${atOther.trim()}»`);
      const atMall = await linksFor(mall);
      expect(atMall.includes(evac), `в ТЦ нет ссылки «${evac}»`);
    });

    await step("Настройки администратора: вкладки из машины, значения и данные МИ (§20)", async () => {
      expect(!$("adminBtn").hidden, "пункта «Настройки администратора» нет в меню");
      await click($("adminBtn"));
      expect(!$("modalAdmin").hidden, "экран настроек не открылся");
      const tabs = [...$("adminTabs").querySelectorAll("[data-admin-tab]")];
      expect(tabs.length === window.IM_WORKFLOW.adminSettings.tabs.length, `вкладок ${tabs.length}, в машине ${window.IM_WORKFLOW.adminSettings.tabs.length}`);
      // План 77: вкладок с настройками четыре — сроки и эскалация, работа оператора, причины, хранение (ТЗ-21: и плановые работы); прежние
      // вкладки — разделами внутри, в том же порядке, и ни одна настройка не потерялась. Хранение — последней (решение 2026-11-15).
      // Звук (§21) — сразу после работы оператора
      const settingTabs = window.IM_WORKFLOW.adminSettings.tabs.filter((x) => x.items).map((x) => x.id);
      expect(settingTabs.join() === "timing,operator,sound,reasons,maintenance,storage", `вкладки с настройками: ${settingTabs.join(", ")}`);
      const groupsOf = { timing: "norms,escalation", operator: "queue,limits,session,shift,links", storage: "retention" };
      for (const [id, want] of Object.entries(groupsOf)) {
        await click($("adminTabs").querySelector(`[data-admin-tab="${id}"]`));
        await wait(200);
        const shownGroups = [...$("adminTable").querySelectorAll("[data-admin-group]")].map((r) => r.dataset.adminGroup).join();
        expect(shownGroups === want, `вкладка «${id}»: разделы ${shownGroups}, а не ${want}`);
        const tab = window.IM_WORKFLOW.adminSettings.tabs.find((x) => x.id === id);
        const rows = [...$("adminTable").tBodies[0].rows].filter((r) => !r.classList.contains("admin-group") && !r.querySelector("table"));
        expect(rows.length === tab.items.length, `вкладка «${id}»: строк настроек ${rows.length}, в машине ${tab.items.length}`);
      }
      // Справочные ссылки — раздел «Работы оператора» с данными из запроса
      await click($("adminTabs").querySelector('[data-admin-tab="operator"]'));
      await wait(200);
      expect($("adminTable").querySelector('[data-admin-group="links"] + tr table tbody tr'), "в разделе «Справочные ссылки» нет ссылок из запроса");
      expect(!$("adminTabs").querySelector('[data-admin-tab="links"], [data-admin-tab="limits"], [data-admin-tab="retention"]'), "прежние вкладки остались наверху");
      const allPaths = window.IM_WORKFLOW.adminSettings.tabs.flatMap((x) => (x.items || []).map((i) => i.path));
      expect(new Set(allPaths).size === allPaths.length, "настройка повторяется в двух вкладках");
      // Быстрое переключение: поздний ответ вкладки-запроса не затирает уже открытую вкладку с разделами (ревью плана 77)
      $("adminTabs").querySelector('[data-admin-tab="priorities"]').click();
      $("adminTabs").querySelector('[data-admin-tab="reasons"]').click();
      await wait(400);
      expect(/Нет связи с оператором/.test($("adminTable").textContent), "ответ «Приоритетов» перерисовал открытые «Причины»");
      await click($("adminTabs").querySelector('[data-admin-tab="operator"]'));
      await wait(200);
      const row = [...$("adminTable").querySelectorAll("tr")].find((r) => /В работе одновременно/.test(r.textContent));
      // Стенд самопроверки задал лимит 1 (standReset): экран показывает действующую схему
      expect(row && row.cells[1].textContent.trim() === "1", "лимит активных не показан или не совпадает со схемой");
      // Значения перечня — подписями из машины, а не машинным словом (BUG-26)
      await click($("adminTabs").querySelector('[data-admin-tab="timing"]'));
      const overdue = [...$("adminTable").querySelectorAll("tr")].find((r) => /Просрочка закрытия/.test(r.textContent));
      // Значение перечня в машине — ключ каталога строк (§14.9): ждём его русскую строку
      const key = window.IM_WORKFLOW.adminSettings.tabs.find((x) => x.id === "timing").items.find((i) => i.path === "escalation.onResolutionOverdue").values[window.IM_WORKFLOW.escalation.onResolutionOverdue];
      const expected = window.IM_STRINGS.ru[key];
      expect(overdue && overdue.cells[1].textContent.trim() === expected, `«Просрочка закрытия»: «${overdue && overdue.cells[1].textContent.trim()}» вместо «${expected}»`);
      // Срок «Нет связи» — из порогов молчания, а не «без срока» (deadlineFromIdle, BUG-119)
      await click($("adminTabs").querySelector('[data-admin-tab="reasons"]'));
      expect(/Нет связи с оператором \(порог «в очередь» минус «отложить»\)/.test($("adminTable").textContent), "срок «Нет связи» на экране — не из порогов молчания");
      // Срок хранения закрытых — вкладка «Хранение и резервная копия», значение из машины (§14.11)
      await click($("adminTabs").querySelector('[data-admin-tab="storage"]'));
      const kept = [...$("adminTable").querySelectorAll("tr")].find((r) => /Хранить закрытые инциденты/.test(r.textContent));
      const days = window.IM_WORKFLOW.retention.closedIncidentsDays;
      expect(kept && kept.cells[1].textContent.includes(String(days)), `срок хранения не показан или не ${days}: «${kept && kept.cells[1].textContent.trim()}»`);
      // Срок хранения аудита — 1095 дней по умолчанию, в той же вкладке (§14.11, план 71)
      const auditDays = window.IM_WORKFLOW.retention.auditDays;
      expect(auditDays === 1095, `срок хранения аудита в машине ${auditDays}, а не 1095`);
      const auditKept = [...$("adminTable").querySelectorAll("tr")].find((r) => /Хранить аудит/.test(r.textContent));
      expect(auditKept && auditKept.cells[1].textContent.includes("1095"), `срок хранения аудита не показан: «${auditKept && auditKept.cells[1].textContent.trim()}»`);
      await click($("adminTabs").querySelector('[data-admin-tab="duty_groups"]'));
      expect(/Старшие операторы/.test($("adminTable").textContent), "дежурных групп из запроса нет");
      // Связи камер многие-ко-многим (§19.1, RULE-70): название, устройства, камеры — как в наборе
      await click($("adminTabs").querySelector('[data-admin-tab="camera_links"]'));
      const multi = window.IM_FIXTURE.cameraLinks.find((l) => l.devices.length > 1);
      const linkRow = [...$("adminTable").querySelectorAll("tbody tr")].find((r) => r.cells[0].textContent.trim() === multi.name);
      expect(linkRow, `связи «${multi.name}» нет во вкладке`);
      expect(linkRow.cells.length === 3 && linkRow.cells[1].textContent.split(", ").length === multi.devices.length, `у связи «${multi.name}» не ${multi.devices.length} устройства`);
      await click(document.querySelector('[data-close="modalAdmin"]'));
      expect($("modalAdmin").hidden, "экран настроек не закрылся");
    });

    await step("Состояние системы: свой раздел из трёх блоков; «Хранение» — без статистики, со ссылкой (§14.11, §20)", async () => {
      await click($("adminBtn"));
      expect($("adminTabs").querySelector('[data-admin-tab="system_status"]'), "раздела «Состояние системы» нет");
      await click($("adminTabs").querySelector('[data-admin-tab="storage"]'));
      await wait(200);
      expect(!$("adminTable").querySelector("[data-status-block]") && !/Размер базы|Свободно на диске/.test($("adminTable").textContent), "на «Хранении» осталась статистика");
      const link = $("adminNote").querySelector('[data-admin-goto="system_status"]');
      expect(link && /Посмотреть состояние/.test(link.textContent), "на «Хранении» нет ссылки «Посмотреть состояние»");
      await click(link);
      await wait(100);
      const blocks = [...$("adminTable").querySelectorAll("[data-status-block]")].map((r) => r.dataset.statusBlock).join();
      expect(blocks === "database,retention,server", `блоки: ${blocks}`);
      expect(/общий для сервера/i.test($("adminTable").textContent), "размер базы не помечен «общий для сервера»");
      const refresh = $("adminNote").querySelector("[data-admin-refresh]");
      expect(refresh, "нет кнопки «Обновить»");
      await click(refresh);
      await wait(200);
      expect($("adminTable").querySelector('[data-status-block="server"]'), "после «Обновить» блоков нет");
      await click(document.querySelector('[data-close="modalAdmin"]'));
    });

    // Взять новое в работу служебным запросом стенда — с тем, что видно в карточке, как клиент
    async function standClaim(stand, guid) {
      const card = await stand.raw("GET", `/operator/incidents/${encodeURIComponent(guid)}`);
      const res = await stand.raw("POST", `/operator/incidents/${encodeURIComponent(guid)}/transitions/claim`, Object.assign({ formValues: {}, surface: "queue" }, seenBody(card.body)));
      expect(res.status === 200, `не взялся: ${res.status}`);
    }

    await step("Выход из МИ: подтверждение, дальше только просмотр, вход (§12.1)", async () => {
      // Инцидент в работе: подтверждение считает свои в работе (BUG-25)
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const fresh = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.state === "new");
      await standClaim(stand, fresh.guid);
      const mine = (await stand.get("/operator/incidents", { filter: "mine", pageSize: 1000 })).items.filter((e) => e.state === "in_progress").length;
      await setFilter("open");
      await click($("signOutBtn"));
      await wait(200);
      expect(!$("modalDialog").hidden && /вернутся в очередь/.test($("dialogNote").textContent), "выход не спросил подтверждения");
      expect(mine >= 1 && $("dialogNote").textContent.includes(`: ${mine},`), `в подтверждении не ${mine} в работе: «${$("dialogNote").textContent}»`);
      await confirmDialog();
      expect(!$("signedOutBanner").hidden, "плашка «Вы вышли» не появилась");
      expect($("dutyBadge").textContent === "Вышел", `в шапке «${$("dutyBadge").textContent}» вместо «Вышел»`);
      const claims = [...$("eventsList").querySelectorAll('[data-do="claim"]')];
      expect(claims.length && claims.every(off), "после выхода «Взять» доступно");
      await click($("signInBtn"));
      expect($("signedOutBanner").hidden, "кнопка «Войти» не вернула в МИ");
      expect([...$("eventsList").querySelectorAll('[data-do="claim"]')].some((b) => !off(b)), "после входа «Взять» недоступно");
    });

    await step("Панель выборки: недоступное кому-то из отмеченных — бледное, с номером и причиной", async () => {
      // Новый и чужой в работе: «Перехватить» относится только к чужому — видна, но недоступна из-за нового
      try {
        // Оба — в одном списке «Все», при необходимости на разных страницах: между страницами отметки сохраняются
        await setFilter("all");
        const tickFirst = async (pick) => {
          for (let page = 1; page <= 6; page++) {
            const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
            if (page > 1 && (!nav || nav.disabled)) break;
            if (nav) await click(nav);
            const row = [...$("eventsList").querySelectorAll(".event")].find(pick);
            if (row) return click($("eventsList").querySelector(`[data-check="${row.dataset.id}"]`)).then(() => row);
          }
          return null;
        };
        expect(await tickFirst((r) => r.querySelector('[data-do="claim"]')), "в списке нет нового");
        expect(await tickFirst((r) => r.querySelector(".badge.foreign")), "нет чужих инцидентов в работе");
        expect($("selBar").textContent.includes("Отмечено: 2"), `панель: «${$("selBar").textContent.trim()}»`);
        const b = $("selBar").querySelector('[data-sel-do="takeover"]');
        expect(b && off(b), "«Перехватить» не показана бледной");
        expect(/^INC-\d+: \S/.test(b.title), `причина без номера: «${b.title}»`);
        expect(!$("selBar").querySelector('[data-sel-do="accept"]'), "«Принять» показана, хотя ни к одному не относится");
        await click(b);
        const note = [...$("toasts").children].some((x) => x.textContent.includes(b.title));
        expect(note, "по клику причина не показана");
        return b.title;
      } finally {
        if (!$("clearSelectionBtn").disabled) await click($("clearSelectionBtn"));
        await setFilter("open");
      }
    });

    await step("Частичная передача выборки: уведомление называет не переданные (§11, BUG-28)", async () => {
      // Отмечены новые в ТЦ и вне его, у Петровой на время — доступ только к ТЦ: передаются только из ТЦ
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const roles = window.IM_FIXTURE.people.operators.find((o) => o.id === "petrova").roles;
      await stand.raw("PUT", "/test/operators/petrova/roles", { roles: ["Оператор ТЦ"] });
      try {
        await setFilter("open");
        const rows = [...$("eventsList").querySelectorAll(".event")].filter((r) => r.querySelector('[data-do="transfer"]') && r.querySelector('[data-do="claim"]'));
        const mall = (r) => inMall(r.dataset.id);
        const sent = rows.filter(mall).slice(0, 2);
        const kept = rows.filter((r) => !mall(r)).slice(0, 1);
        expect(sent.length && kept.length, "на странице нет новых в ТЦ и вне его");
        for (const r of sent.concat(kept)) await click($("eventsList").querySelector(`[data-check="${r.dataset.id}"]`));
        const b = $("selBar").querySelector('[data-sel-do="transfer"]');
        expect(b && !off(b), "в панели выборки нет «Передать»");
        await click(b);
        const title = $("dialogTitle").textContent;
        expect(title === `Передать ${sent.length + kept.length} инцидента`, `заголовок окна: «${title}»`);
        await setField("targetId", "petrova");
        await confirmDialog(NOTE);
        await wait(200);
        const note = [...$("toasts").children].find((x) => /Передано/.test(x.textContent));
        const text = note ? note.textContent : "нет";
        expect(text.includes(`Передано: ${sent.length}`) && text.includes(`Не выполнено: ${kept.length}`), `уведомление: «${text}»`);
        return text;
      } finally {
        await stand.raw("PUT", "/test/operators/petrova/roles", { roles });
        if (!$("clearSelectionBtn").disabled) await click($("clearSelectionBtn"));
        await setFilter("open");
      }
    });

    await step("Кнопка на отмеченной строке — только этот инцидент; массовые действия — только панель выборки (§11)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      await setFilter("open");
      const ids = [...$("eventsList").querySelectorAll(".event")].filter((r) => r.querySelector('[data-do="claim"]')).slice(0, 2).map((r) => r.dataset.id);
      expect(ids.length === 2, "нет двух новых событий");
      for (const id of ids) await click($("eventsList").querySelector(`[data-check="${id}"]`));
      const claim = $("eventsList").querySelector(`[data-do="claim"][data-ev="${ids[0]}"]`);
      expect(claim && !off(claim), `«Взять» на отмеченной строке недоступна: ${claim ? claim.title : "нет кнопки"}`);
      await click(claim);
      try {
        const [first, second] = await Promise.all(ids.map((g) => stand.get(`/operator/incidents/${encodeURIComponent(g)}`)));
        expect(first.state === "in_progress" && second.state === "new", `взято не одно: ${first.state}, ${second.state}`);
        return `${first.number} взят, ${second.number} остался новым`;
      } finally {
        await stand.raw("POST", "/operator/incidents/transitions/release/bulk", { incidentGuids: [ids[0]], formValues: { comment: NOTE }, surface: "card" });
        if (mode() === "work") await click($("backToQueue"));
        if (!$("clearSelectionBtn").disabled) await click($("clearSelectionBtn"));
        await setFilter("open");
      }
    });

    await step("Горячих клавиш нет: Shift+D, N, A, Shift+A, Ctrl+A ничего не делают", async () => {
      await setFilter("open");
      expect(!$("selectSimilarBtn"), "кнопка «Однотипные» осталась");
      expect(!$("hotkeysBtn") && !$("modalHotkeys"), "справка по клавишам осталась");
      // «Снять» доступна, только когда выборка не пуста — на любой странице очереди
      const picked = () => !$("clearSelectionBtn").disabled;
      await click($("eventsList").querySelector("[data-check]"));
      expect(picked(), "галочка ничего не выбрала");
      for (const [k, mods] of [["D", { shiftKey: true }], ["n"], ["a"], ["A", { shiftKey: true }], ["A", { ctrlKey: true }]]) {
        await pressKey(k, mods);
        expect(picked() && mode() === "queue", `клавиша ${k} что-то сделала`);
      }
      await click($("clearSelectionBtn"));
      expect(!picked(), "«Снять» не сняла выделение");
    });

    await step("Esc закрывает окно, очередь не трогает", async () => {
      await setFilter("open");
      await click($("breakBtn"));
      expect(!$("modalDialog").hidden, "окно перерыва не открылось");
      await pressKey("Escape");
      expect($("modalDialog").hidden, "Esc не закрыл окно");
      expect(mode() === "queue" && $("breakBanner").hidden, "Esc что-то сделал кроме закрытия окна");
    });

    await step("Esc в карточке: сначала закрывает форму, потом сворачивает развёрнутое видео, потом — карточку, как «К очереди»; инцидент остаётся моим (§13, RULE-87, RULE-91)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      if (mode() !== "queue") await click($("backToQueue"));
      await setFilter("open");
      const b = button($("eventsList"), "claim");
      expect(b, "нет доступной кнопки «Взять»");
      const id = b.dataset.ev;
      await click(b);
      expect(mode() === "work", "карточка не открылась");
      try {
        await click(button(root(), "transfer"));
        expect(!$("modalDialog").hidden, "форма «Передать» не открылась");
        await pressKey("Escape");
        expect($("modalDialog").hidden && mode() === "work", "первый Esc должен закрыть только форму");
        // Развёрнутое видео — тоже слой поверх карточки: Esc сначала сворачивает его (RULE-91)
        await click($("videoFull"));
        expect($("workspace").dataset.full === "video", "видео не развернулось");
        await pressKey("Escape");
        expect(!$("workspace").dataset.full && mode() === "work", "Esc при развёрнутом видео должен свернуть только видео");
        expect(document.activeElement === $("videoFull"), "после Esc фокус не вернулся на кнопку «Развернуть видео»");
        await pressKey("Escape");
        await wait(100);
        expect(mode() === "queue", "второй Esc не вернул к очереди");
        const card = await stand.get(`/operator/incidents/${id}`);
        expect(card.state === "in_progress" && card.owner && card.owner.id === "me", `Esc что-то поменял: ${card.state}, ${card.owner && card.owner.id}`);
      } finally {
        await stand.raw("POST", "/operator/incidents/transitions/release/bulk", { incidentGuids: [id], formValues: { comment: NOTE }, surface: "card" });
      }
    });

    await step("На телефоне 360 пикселей страница не шире экрана; шапка очереди и фильтры — не выше 160 px, поиск — отдельной строкой (BUG-94), типы — под «Фильтры» с числом выбранных (BUG-50); Esc закрывает панель групп (RULE-91); названия в дереве различимы (BUG-65)", async () => {
      const frame = document.createElement("iframe");
      frame.style.cssText = "position:fixed;left:-9999px;top:0;width:360px;height:740px;border:0";
      const report = new Promise((resolve) => {
        const onMessage = (e) => {
          if (!e.data || !e.data.widthcheck) return;
          window.removeEventListener("message", onMessage);
          resolve(e.data);
        };
        window.addEventListener("message", onMessage);
        // Узкая страница отвечает после load — а он ждёт шрифты из сети (Inter, Material Symbols): бывает и 8 с
        setTimeout(() => resolve(null), 15000);
      });
      frame.src = location.pathname.split("/").pop() + "?widthcheck";
      document.body.appendChild(frame);
      const r = await report;
      frame.remove();
      expect(r, "узкая страница не ответила");
      expect(r.scroll <= r.width, `ширина ${r.scroll} при экране ${r.width}: ${r.wide.join(", ")}`);
      // Поиск — отдельной строкой не уже 160 px (BUG-94, решение 2026-10-23): порог шапки — 160 px вместо 120
      expect(r.filters <= 160, `шапка очереди и фильтры — ${r.filters} px, на список мало места`);
      expect(r.more.typesHidden, "типы видны без «Фильтры»");
      expect(r.more.typesShown, "«Фильтры» не открыли типы");
      expect(r.more.counted, "на «Фильтры» нет числа выбранных типов");
      expect(r.more.closed, "«Фильтры» не закрыли типы");
      expect(r.drawer.opened, "панель групп не открылась");
      expect(r.names.count >= 2 && !r.names.cut.length, `названия в дереве обрезаны: найдено ${r.names.count}, обрезаны — ${r.names.cut.join(", ")}`);
      expect(!r.names.currentCut, "текущее найденное показано не целиком");
      expect(r.drawer.closed && r.drawer.focus, `Esc не закрыл панель групп или фокус не на её кнопке: ${JSON.stringify(r.drawer)}`);
      return `${r.scroll} из ${r.width}, шапка и фильтры ${r.filters} px, Esc закрывает панель групп`;
    });

    await step("Контраст отсчётов, бейджей, уровня, кнопок действий и списка «Кому передать» не ниже 4,5:1 в обеих темах", async () => {
      const original = document.documentElement.dataset.theme;
      const low = new Set();
      for (const theme of ["light", "dark"]) {
        await setTheme(theme);
        await setFilter("all");
        for (let page = 1; page <= 20; page++) {
          const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
          if (page > 1 && (!nav || nav.disabled)) break;
          if (nav && page > 1) await click(nav);
          // Кнопки действий — тоже (BUG-52): «Взять», «Передать», «Закрыть» и остальные доступные
          $("eventsList").querySelectorAll('.event-sla, .badge, .chip.lvl, .event-act:not([aria-disabled="true"])').forEach((el) => {
            const r = contrast(el);
            if (r < 4.5) low.add(`${theme} ${el.className}: ${r.toFixed(2)}`);
          });
        }
        // Кнопки карточки чужого инцидента: «Перехватить», «Передать» (BUG-52)
        await setFilter("foreign");
        await click($("eventsList").querySelector('[data-do="view"]'));
        root().querySelectorAll('.btn:not([aria-disabled="true"]):not(:disabled)').forEach((el) => {
          const r = contrast(el);
          if (r < 4.5) low.add(`${theme} карточка, «${el.textContent.trim()}»: ${r.toFixed(2)}`);
        });
        expect(button(root(), "takeover"), "в карточке чужого нет «Перехватить» — шаг контраста её не проверил");
        await click($("backToQueue"));
        await setFilter("all");
        // Список «Кому передать» (BUG-47): выбранный на месте и выбранный отсутствующий, имена и пояснения
        for (const picked of ["sidorov", "orlova"]) {
          await click(button($("eventsList"), "transfer"));
          field("targetId").value = picked;
          await click($("dialogFields").querySelector('[data-target-input="targetId"]'));
          $("dialogFields").querySelectorAll(".target-opt span, .target-opt em").forEach((el) => {
            const r = contrast(el);
            const opt = el.closest(".target-opt");
            const what = `${opt.getAttribute("aria-selected") === "true" ? "выбранный" : "адресат"}${opt.classList.contains("away") ? " отсутствующий" : ""} ${el.tagName.toLowerCase()}`;
            if (r < 4.5) low.add(`${theme} «Кому передать», ${what}: ${r.toFixed(2)}`);
          });
          await click($("modalDialog").querySelector('[data-close="modalDialog"]'));
        }
      }
      await setTheme(original);
      await setFilter("open");
      expect(!low.size, `низкий контраст: ${[...low].join("; ")}`);
    });

    await step("Время событий в очереди не позже текущего", async () => {
      // Момент целиком — из datetime, а не время суток: после полуночи вчерашние события не «из будущего» (PROC-46)
      const now = Date.now();
      await setFilter("all");
      const times = [...$("eventsList").querySelectorAll(".event time")];
      expect(times.length && times.every((el) => !Number.isNaN(Date.parse(el.getAttribute("datetime")))), "у времени события есть datetime");
      const late = times.filter((el) => Date.parse(el.getAttribute("datetime")) > now + 5000).map((el) => el.textContent.trim());
      await setFilter("open");
      expect(!late.length, `события из будущего: ${late.join(", ")}`);
    });

    await step("Цвет полоски очереди — из приоритета инцидента (§1, §4, BUG-39), с подписью для скринридера", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const byGuid = Object.fromEntries((await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.map((e) => [e.guid, e.priority]));
      // Справочник приоритетов — справочник МИ, не схема (§2.5, RULE-68)
      const byPriority = Object.fromEntries((await stand.get("/operator/reference/priorities")).map((p) => [p.value, p]));
      await setFilter("all");
      const missing = new Set();
      const wrongColor = new Set();
      const noLabel = new Set();
      for (let page = 1; page <= 20; page++) {
        const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
        if (page > 1 && (!nav || nav.disabled)) break;
        if (nav && page > 1) await click(nav);
        $("eventsList").querySelectorAll(".event").forEach((row) => {
          const el = row.querySelector(".event-pri");
          const priority = byPriority[byGuid[row.dataset.id]];
          const bg = getComputedStyle(el).backgroundColor;
          if (bg === "transparent" || bg === "rgba(0, 0, 0, 0)") missing.add(priority.value);
          // Цвет строки — тот, что настроен для её приоритета в машине, не свой в коде интерфейса
          if (el.dataset.color !== priority.color) wrongColor.add(`${priority.value}: ${el.dataset.color} ≠ ${priority.color}`);
          if (!el.getAttribute("aria-label")) noLabel.add(priority.value);
        });
      }
      await setFilter("open");
      expect(!missing.size, `нет цвета у приоритета: ${[...missing].join(", ")}`);
      expect(!wrongColor.size, `цвет полоски не из настройки приоритета: ${[...wrongColor].join(", ")}`);
      expect(!noLabel.size, `нет aria-label у полоски приоритета: ${[...noLabel].join(", ")}`);
    });

    await step("Перевод на английский", () => checkLanguage("en"));

    // Уведомления о событиях потока, до которых без стенда не дойти: роли и часы — служебными
    // операциями встроенного сервера (PROC-12)
    const stand = window.IM_SELFTEST_API;
    const toastWith = (re) => [...$("toasts").children].find((t) => re.test(t.textContent));
    // Чужое и автоматическое — не всплывает, а запись в колокольчике (§22.2, §22.6): записи этого шага
    const noticesNow = () => [...$("bellList").querySelectorAll("[data-notice]")].filter((li) => Number(li.dataset.at) >= stepAt);
    const noticeWith = (re) => noticesNow().find((li) => re.test(li.textContent));
    const noticeList = () => noticesNow().map((li) => li.textContent).join(" | ");
    async function claimFromQueue(accept) {
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
      const row = [...$("eventsList").querySelectorAll(".event")].find((r) => accept(r) && button(r, "claim"));
      expect(row, "нет нового инцидента, который можно взять");
      const number = (row.textContent.match(/INC-\d+/) || [])[0];
      await click(button(row, "claim"));
      return number;
    }

    await step("Потеря доступа: уведомление с номером, карточка закрыта (§5, BUG-24)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const number = await claimFromQueue((r) => !inMall(r.dataset.id) && !/Торговый центр/.test(r.textContent));
      expect(mode() === "work", "карточка взятого инцидента не открылась");
      await stand.raw("PUT", "/test/operators/me/roles", { roles: ["Оператор ТЦ"] });
      await wait(100);
      const toast = noticeWith(/вам больше не доступен/);
      try {
        expect(toast && toast.textContent.includes(number), `нет записи в колокольчике о потере доступа к ${number}`);
        expect(!toastWith(/вам больше не доступен/), "потеря доступа всплыла сообщением, а не записью в колокольчике");
        expect(mode() === "queue", "карточка недоступного инцидента не закрылась");
      } finally {
        await stand.raw("PUT", "/test/operators/me/roles", { roles: ["Оператор"] });
        await wait(200);
      }
      return toast.textContent;
    });

    await step("Оповещение получателю: уведомление о нарушении норматива закрытия (§9, RULE-43)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const number = await claimFromQueue(() => true);
      let toast = null;
      // Часы шагами короче порога «нет связи», перед каждым — признак активности
      for (let i = 0; i < 12 && !toast; i++) {
        await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        await stand.raw("POST", "/test/clock", { advanceSec: 240 });
        await wait(150);
        toast = noticeWith(new RegExp(`Оповещение: ${number} — Норматив закрытия нарушен`));
      }
      expect(toast, `нет уведомления об оповещении по ${number}`);
      return toast.textContent;
    });

    await step("Уведомление о переходе — из машины: появился инцидент, автоэскалация (§9, RULE-60, BUG-32)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const fire = (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find((e) => e.eventType.id === "fire");
      const source = (await stand.get(`/operator/incidents/${encodeURIComponent(fire.guid)}`)).source.guid;
      const top = Math.max(...window.IM_FIXTURE.priorities.map((p) => p.value));
      const created = await stand.raw("POST", "/test/incidents", { eventTypeId: "fire", priority: top, deviceIds: [source] });
      expect(created.status === 201, `инцидент не появился: ${created.status}`);
      const number = created.body.number;
      const norm = window.IM_WORKFLOW.timers.find((t) => t.id === "reaction").overrides.find((o) => o.priority === top).sec;
      await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
      const grace = (window.IM_WORKFLOW.invariants.manualWinsOverTimer || {}).graceSec || 0;
      await stand.raw("POST", "/test/clock", { advanceSec: norm + grace + 1 });
      await wait(200);
      const toast = noticeWith(new RegExp(`Автоэскалация ${number} → `));
      expect(toast, `нет уведомления об автоэскалации ${number}`);
      return toast.textContent;
    });

    // Сбрасывает стенд в конце — стоит перед шагом, который и так начинается со сброса
    await step("address: источник и адрес — строка очереди, поиск, карточка, меню справки по группе (§1, §7, план 87а)", async () => {
      if (mode() === "work") await click($("backToQueue"));
      const stand = window.IM_SELFTEST_API;
      const fx = window.IM_FIXTURE;
      const device = (id) => fx.devices.find((d) => d.id === id);
      const inc = (n) => fx.incidents.find((i) => i.number === n);
      const sourceOf = (n) => device(inc(n).devices[0]);
      // Поиск очереди — по фильтру «Все»: строки, которые нашлись
      const search = async (text) => {
        $("eventSearch").value = text;
        $("eventSearch").dispatchEvent(new Event("input", { bubbles: true }));
        await wait(100);
        return [...$("eventsList").querySelectorAll(".event")].map((r) => r.dataset.id);
      };
      const rowOf = async (n) => {
        await search(n);
        return $("eventsList").querySelector(`.event[data-id="${guidOf(n)}"]`);
      };
      const sourceLine = async (n) => {
        const row = await rowOf(n);
        expect(row, `${n} не нашёлся поиском по номеру`);
        const line = row.querySelector(".event-source");
        expect(line, `${n}: под заголовком нет строки «устройство · адрес»`);
        return line;
      };
      await setFilter("all");
      try {
        // Торговый центр: «устройство · адрес», полный адрес — во всплывающей подсказке, длинный обрезается многоточием
        const mall = sourceOf("INC-1847");
        expect(mall.address && !mall.addressIm, "у источника INC-1847 в наборе нет адреса источника");
        const line = await sourceLine("INC-1847");
        expect(line.textContent.trim() === `${mall.name} · ${mall.address}`, `строка INC-1847: «${line.textContent.trim()}»`);
        expect(line.title === mall.address, `подсказка строки INC-1847: «${line.title}»`);
        const css = getComputedStyle(line);
        expect(css.textOverflow === "ellipsis" && css.whiteSpace === "nowrap" && css.overflow === "hidden", `строка источника не обрезается многоточием: ${css.textOverflow}, ${css.whiteSpace}, ${css.overflow}`);
        // Поиск — по части адреса и по названию устройства
        const part = mall.address.split(", ").slice(1).join(", ");
        expect((await search(part.slice(0, 14))).includes(guidOf("INC-1847")), `поиск по части адреса «${part.slice(0, 14)}» не нашёл INC-1847`);
        expect((await search(mall.name)).includes(guidOf("INC-1847")), `поиск по устройству «${mall.name}» не нашёл INC-1847`);
        // Адрес, введённый в МИ, — вместо адреса источника: и в строке, и в поиске
        const typed = sourceOf("INC-1827");
        expect(typed.addressIm && typed.address && typed.addressIm !== typed.address, "у источника INC-1827 в наборе нет addressIm, отличного от адреса источника");
        const typedLine = await sourceLine("INC-1827");
        expect(typedLine.textContent.trim() === `${typed.name} · ${typed.addressIm}` && typedLine.title === typed.addressIm, `INC-1827: «${typedLine.textContent.trim()}», подсказка «${typedLine.title}» — а действует адрес МИ «${typed.addressIm}»`);
        expect((await search(typed.addressIm)).includes(guidOf("INC-1827")), "поиск по адресу МИ не нашёл INC-1827");
        expect(!(await search(typed.address)).includes(guidOf("INC-1827")), "поиск по заменённому адресу источника нашёл INC-1827");
        // Устройство без адреса — только название
        const bare = sourceOf("INC-1840");
        expect(!bare.address && !bare.addressIm, "у источника INC-1840 в наборе есть адрес");
        const bareLine = await sourceLine("INC-1840");
        expect(bareLine.textContent.trim() === bare.name && !bareLine.title, `INC-1840 без адреса: «${bareLine.textContent.trim()}», подсказка «${bareLine.title}»`);
        // Карточка: блок «Источник» — устройство, тип, адрес
        const type = fx.deviceTypes.find((t) => t.id === mall.type).label;
        await rowOf("INC-1847");
        await click(button($("eventsList"), "view", guidOf("INC-1847")));
        expect(mode() === "work", "карточка INC-1847 не открылась");
        const block = root().querySelector(".incident-source");
        const text = block ? block.textContent.replace(/\s+/g, " ") : "";
        expect(block && /Источник/.test(text) && text.includes(mall.name) && text.includes(type) && text.includes(mall.address), `блок «Источник» карточки: «${text.trim()}»`);
        await click($("backToQueue"));
        await rowOf("INC-1840");
        await click(button($("eventsList"), "view", guidOf("INC-1840")));
        const bareBlock = root().querySelector(".incident-source");
        expect(bareBlock && bareBlock.textContent.includes(bare.name) && !bareBlock.querySelector(".src-address"), `карточка INC-1840: «${bareBlock ? bareBlock.textContent.trim() : "нет блока"}»`);
        await click($("backToQueue"));
        // Меню справки: ссылка группы Торгового центра — при его инциденте, при инциденте Главного офиса — нет;
        // «не назначена» — никогда
        const group = fx.helpLinks.find((l) => l.scope === "group");
        const lost = fx.helpLinks.find((l) => l.scope === "unassigned");
        expect(group && lost, "в наборе нет ссылки группы или ссылки «не назначена»");
        const menuAt = async (n) => {
          await rowOf(n);
          await click($("eventsList").querySelector(`.event[data-id="${guidOf(n)}"]`));
          await click($("helpBtn"));
          await wait(150);
          const t = $("helpLinks").textContent;
          document.body.click();
          return t;
        };
        const atMall = await menuAt("INC-1847");
        expect(atMall.includes(group.title) && !atMall.includes(lost.title), `меню при INC-1847: «${atMall.trim()}»`);
        // Инцидент Главного офиса — по почтовой части действующего адреса источника ($commentAddresses набора)
        const officeAddress = fx.sourceGroups.find((g) => g.name === "Главный офис").address;
        const office = fx.incidents.find((i) => i.state === "new" && (sourceOf(i.number).addressIm || sourceOf(i.number).address || "").startsWith(officeAddress));
        const atOffice = await menuAt(office.number);
        expect(!atOffice.includes(group.title) && !atOffice.includes(lost.title), `меню при ${office.number} (Главный офис): «${atOffice.trim()}»`);
        // Без права администратора схемы справочник без инцидента — только общие
        const all = await stand.get("/operator/reference/help-links");
        expect(all.some((l) => l.scope === "unassigned") && all.some((l) => l.scope === "group"), "администратору без инцидента — не весь справочник");
        await standReset({ fixture: "demo", operatorPermissions: window.IM_WORKFLOW.permissions.map((p) => p.key).filter((k) => k !== "incident:schema:admin") });
        await wait(400);
        const plain = await stand.get("/operator/reference/help-links");
        expect(plain.length && plain.every((l) => l.scope === "shared"), `без права администратора без инцидента: ${plain.map((l) => `${l.id}:${l.scope}`).join(", ")}`);
        // Удалённое устройство: «устройство удалено», адреса нет; ни название, ни адрес не ищутся
        await standReset({ fixture: "demo", fixturePatch: { devices: fx.devices.map((d) => (d.id === mall.id ? Object.assign({}, d, { deleted: true }) : d)) } });
        await wait(400);
        await setFilter("all");
        const goneLine = await sourceLine("INC-1847");
        expect(goneLine.textContent.trim() === "устройство удалено" && !goneLine.title, `удалённый источник INC-1847: «${goneLine.textContent.trim()}», подсказка «${goneLine.title}»`);
        expect(!(await search(part.slice(0, 14))).includes(guidOf("INC-1847")), "адрес удалённого устройства нашёлся поиском");
        expect(!(await search(mall.name)).includes(guidOf("INC-1847")), "название удалённого устройства нашлось поиском");
        await rowOf("INC-1847");
        await click(button($("eventsList"), "view", guidOf("INC-1847")));
        const goneBlock = root().querySelector(".incident-source");
        expect(goneBlock && /устройство удалено/.test(goneBlock.textContent) && !goneBlock.textContent.includes(mall.address), `карточка удалённого источника: «${goneBlock ? goneBlock.textContent.trim() : "нет блока"}»`);
        await click($("backToQueue"));
      } finally {
        await search("");
        await standReset({ fixture: "demo" });
        await wait(400);
        await setFilter("open");
      }
    });

    await step("rule-addressing: адресация из правила — группе, в очередь с оповещением, без группы (§8.1, §6.2, М1)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      if (mode() === "work") await click($("backToQueue"));
      const fx = window.IM_FIXTURE;
      // Датчик дыма 1 в приёмной главного офиса — вне торгового центра; правило — только базовое правило пожара
      const smoke1 = "20000000-0002-4000-8000-000000000001";
      const fireRule = fx.rules.find((r) => r.guid === "80000000-0000-4000-8000-000000000001");
      const groupName = (id) => fx.people.dutyGroups.find((g) => g.id === id).name;
      // Состояния и роли коллег — поверх набора; группа правила — dutyGroupId (§17: поле задаёт набор)
      const setup = async (dutyGroupId, states) => {
        const people = JSON.parse(JSON.stringify(fx.people));
        people.operators.forEach((o) => Object.assign(o, (states || {})[o.id] || {}));
        const rule = Object.assign({}, fireRule, dutyGroupId ? { dutyGroupId } : {});
        await standReset({ fixture: "demo", fixturePatch: { people, rules: [rule] } });
        await wait(100);
        const res = await stand.raw("POST", "/test/events", { eventTypeId: "fire", deviceIds: [smoke1] });
        expect(res.status === 201 && res.body.created === 1, `событие: ${res.status}, создано ${res.body.created}`);
        await wait(100);
        return stand.get(`/operator/incidents/${encodeURIComponent(res.body.incidents[0].guid)}`);
      };
      const journalOf = (card) => card.journal.map((j) => j.templateKey).filter((k) => /^workflow\.journal\.(create|create_to_group|rule_group_cannot_accept)$/.test(k));
      const out = [];
      try {
        // 1. Группа «Старшие операторы» (я и Петрова): я на месте, с доступом и правом — сразу у группы
        const a = await setup("grp-leads");
        expect(a.state === "pending_acceptance", `у группы: состояние ${a.state}`);
        expect(a.assignmentGroup && a.assignmentGroup.id === "grp-leads" && !a.owner, `у группы: адресат ${a.assignmentGroup && a.assignmentGroup.id}, владелец ${a.owner && a.owner.id}`);
        expect(a.escalationLevel === 0 && a.transferCount === 0, `у группы: уровень ${a.escalationLevel}, передач ${a.transferCount}`);
        const born = a.journal.find((j) => j.templateKey === "workflow.journal.create_to_group");
        expect(journalOf(a).join() === "workflow.journal.create_to_group" && born.vars.targetName === groupName("grp-leads"), `у группы: журнал ${journalOf(a).join()}, группа «${born && born.vars.targetName}»`);
        await setFilter("inbox");
        expect($("eventsList").querySelector(`[data-id="${a.guid}"]`), `${a.number} нет в «Мне на принятие» участника группы`);
        // Уведомление участнику группы-адресата — как при передаче (ui.observerNotice перехода появления, newAddressee)
        const notice = (n, g) => noticeWith(new RegExp(`Новый ${n} — вашей группе «${groupName(g)}»`));
        expect(notice(a.number, "grp-leads"), `участнику группы нет уведомления о ${a.number}`);
        out.push(`у группы ${a.number}, уведомление участнику`);
        // 2. «Группа реагирования»: все вышли из МИ — «Новое» в очереди, оповещение с названием группы
        const b = await setup("grp-response", { sidorov: { agentState: "offline" }, gusev: { agentState: "offline" } });
        expect(b.state === "new" && !b.assignmentGroup && !b.owner, `все вышли: состояние ${b.state}, адресат ${b.assignmentGroup && b.assignmentGroup.id}`);
        const queued = b.journal.find((j) => j.templateKey === "workflow.journal.rule_group_cannot_accept");
        expect(journalOf(b).join() === "workflow.journal.rule_group_cannot_accept" && queued.vars.ruleGroupName === groupName("grp-response"), `все вышли: журнал ${journalOf(b).join()}, группа «${queued && queued.vars.ruleGroupName}»`);
        // Получатель оповещений (alerts.target) — «Старшие операторы», я в ней: уведомление с номером и группой
        const toast = noticeWith(new RegExp(`Оповещение: ${b.number} — .*«${groupName("grp-response")}»`));
        expect(toast, `нет оповещения по ${b.number} с названием группы`);
        out.push(`все вышли — в очередь, «${toast.textContent}»`);
        // 3. Сидоров на перерыве, Гусев вышел: перерыв не мешает — у группы
        const c = await setup("grp-response", { sidorov: { agentState: "not_ready" }, gusev: { agentState: "offline" } });
        expect(c.state === "pending_acceptance" && c.assignmentGroup && c.assignmentGroup.id === "grp-response", `перерыв: состояние ${c.state}, адресат ${c.assignmentGroup && c.assignmentGroup.id}`);
        // Я не в «Группе реагирования» — уведомления адресату мне нет
        expect(!notice(c.number, "grp-response"), `не участнику группы пришло уведомление о ${c.number}`);
        out.push("перерыв — у группы, не участнику уведомления нет");
        // 4. «Охрана ТЦ»: Кузнецов на месте, но устройство вне ТЦ — доступа нет, в очередь
        const d = await setup("grp-tc", { kuznetsov: { agentState: "ready" } });
        expect(d.state === "new" && !d.assignmentGroup && journalOf(d).join() === "workflow.journal.rule_group_cannot_accept", `нет доступа: состояние ${d.state}, журнал ${journalOf(d).join()}`);
        out.push("без доступа — в очередь");
        // 5. Группы с таким id нет (isGroup ложно) — в очередь, а не ошибка приёма
        const e = await setup("grp-missing");
        expect(e.state === "new" && journalOf(e).join() === "workflow.journal.rule_group_cannot_accept", `группы нет: состояние ${e.state}, журнал ${journalOf(e).join()}`);
        out.push("группы нет — в очередь");
        // 6. У правила нет группы — как раньше: «Новое», запись create
        const f = await setup(null);
        expect(f.state === "new" && !f.assignmentGroup && journalOf(f).join() === "workflow.journal.create", `без группы: состояние ${f.state}, журнал ${journalOf(f).join()}`);
        out.push("без группы — как раньше");
        return out.join("; ");
      } finally {
        await standReset({ fixture: "demo" });
        await wait(400);
        await setFilter("open");
      }
    });

    await step("Карточку увели — у прежнего владельца уведомление с причиной: эскалация по нормативу закрытия (§6.2, §14.8, BUG-86)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const esc = window.IM_WORKFLOW.escalation;
      await standReset({ fixture: "demo", workflowPatch: { escalation: Object.assign({}, esc, { onResolutionOverdue: "escalate" }) } });
      await wait(100);
      let toast = null;
      try {
        const number = await claimFromQueue(() => true);
        expect(mode() === "work", "карточка взятого инцидента не открылась");
        const what = window.IM_STRINGS.ru[window.IM_WORKFLOW.transitions.find((x) => x.id === "resolution_escalate").labelKey];
        // Карточка открыта — сервер знает это из признака активности (BUG-105)
        const open = (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find((e) => e.number === number).guid;
        // Часы шагами короче порога «нет связи», перед каждым — признак активности
        for (let i = 0; i < 12 && !toast; i++) {
          await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: open });
          await stand.raw("POST", "/test/clock", { advanceSec: 240 });
          await wait(150);
          toast = noticeWith(new RegExp(`${number}: карточка только для просмотра — ${what}`));
        }
        expect(toast, `нет записи в колокольчике с причиной у прежнего владельца ${number}`);
        // Полоса в самой карточке (§22.7): «{что} — только просмотр», карточка открыта
        await wait(200);
        const bar = $("scenarioRoot").querySelector("[data-evicted]");
        expect(mode() === "work" && bar && bar.textContent.includes(what) && /только просмотр/.test(bar.textContent), `полоса в карточке: «${bar ? bar.textContent.trim() : "нет"}», режим ${mode()}`);
        expect(!toastWith(/карточка только для просмотра|только просмотр/), "увели карточку — всплыло сообщение");
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
      return toast.textContent;
    });

    await step("Ложная тревога у соседа — уведомление адресату соседа, закрывшему — нет (§6.1, ARCH-15)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Уровень 1 эскалации — группа старших операторов (я и Петрова): истекла реакция медпункта INC-1853 — он ждёт принятия у неё
      const esc = window.IM_WORKFLOW.escalation;
      const levels = esc.levels.map((l, i) => (i === 0 ? Object.assign({}, l, { targetKind: "group", target: "grp-leads", reactionSec: 120 }) : l));
      const fire = guidOf("INC-1847");
      const med = guidOf("INC-1853");
      const label = window.IM_STRINGS.ru["workflow.catalog.close_result.false_alarm"];
      const notice = new RegExp(`INC-1847 того же события закрыт: ${label}`);
      // Действие Петровой — служебной операцией стенда, от её имени (§17)
      const asPetrova = (transitionId, formValues) =>
        stand.raw("POST", `/test/operators/petrova/incidents/${encodeURIComponent(fire)}/transitions/${transitionId}`, { formValues: formValues || {}, surface: "card" });
      // Часы — за реакцию медпункта и окно после дедлайна, шагами короче порога «нет связи», перед каждым — признак активности
      async function medToLeads(openGuid) {
        const due = Date.parse((await stand.get(`/operator/incidents/${encodeURIComponent(med)}`)).timer.dueAt);
        const grace = (window.IM_WORKFLOW.invariants.manualWinsOverTimer || {}).graceSec || 0;
        let left = Math.ceil((due - Date.parse((await stand.raw("POST", "/test/clock", { advanceSec: 0 })).body.now)) / 1000) + grace + 1;
        for (; left > 0; left -= 240) {
          await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: openGuid });
          await stand.raw("POST", "/test/clock", { advanceSec: Math.min(240, left) });
        }
        await wait(200);
        const s = (await stand.get(`/operator/incidents/${encodeURIComponent(med)}`)).state;
        expect(s === "pending_acceptance", `INC-1853 не ждёт принятия: ${s}`);
      }
      const toasts = noticeList;
      let toast = null;
      try {
        // Закрываю я: пожар INC-1847 у меня в работе, карточка открыта; я в группе-адресате медпункта — но уведомления мне нет
        await standReset({ fixture: "demo", workflowPatch: { escalation: Object.assign({}, esc, { levels }) } });
        await wait(100);
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
        const claim = await buttonOnPages("claim", fire);
        expect(claim, "у INC-1847 нет «Взять»");
        await click(claim);
        expect(mode() === "work", "карточка INC-1847 не открылась");
        await medToLeads(fire);
        const close = button(root(), "close");
        expect(close, "в карточке INC-1847 нет «Закрыть без обработки»");
        await click(close);
        await setField("resultId", "false_alarm");
        await setField("causeId", "animal");
        await confirmDialog(NOTE);
        await wait(100);
        expect(!noticeWith(notice), `закрывшему — уведомление о своём закрытии: ${toasts()}`);
        if (mode() !== "queue") await click($("backToQueue"));
        // Закрывает Петрова: я — другой участник группы-адресата, уведомление мне есть. У неё уже есть инцидент в работе —
        // лимит активных самопроверки (1) снят
        await standReset({ fixture: "demo", workflowPatch: { escalation: Object.assign({}, esc, { levels }), limits: { maxActive: null } } });
        await wait(100);
        expect((await asPetrova("claim")).status === 200, "Петрова не взяла INC-1847");
        await medToLeads(null);
        const closed = await asPetrova("close", { resultId: "false_alarm", causeId: "animal", comment: "тест" });
        expect(closed.status === 200, `Петрова не закрыла INC-1847: ${closed.status}`);
        await wait(100);
        toast = noticeWith(notice);
        expect(toast, `нет уведомления о ложной тревоге соседа: ${toasts()}`);
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
      return toast.textContent;
    });

    // Запрос оператора стенда с тем, что видно в карточке (§14.1, RULE-142)
    async function standAct(guid, transitionId, formValues, surface) {
      const card = await stand.raw("GET", `/operator/incidents/${encodeURIComponent(guid)}`);
      return stand.raw("POST", `/operator/incidents/${encodeURIComponent(guid)}/transitions/${transitionId}`, Object.assign({ formValues: formValues || {}, surface: surface || "card" }, seenBody(card.body)));
    }
    // Переход от имени Петровой — служебной операцией стенда (§17)
    const petrovaAct = (guid, transitionId, formValues) =>
      stand.raw("POST", `/test/operators/petrova/incidents/${encodeURIComponent(guid)}/transitions/${transitionId}`, { formValues: formValues || {}, surface: "card" });

    await step("Комментарий в карточке: не владелец с правом пишет в журнал, состояние то же; без права, пустой, 6-й файл — отказ; к закрытому — можно; правки и удаления нет (ТЗ-18, 19)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const W = window.IM_WORKFLOW;
      const max = W.limits.commentMaxFiles;
      expect(max === 5 && W.limits.commentMaxLength > 0 && W.limits.attachmentMaxBytes > 0 && (W.limits.attachmentTypes || []).includes("image/png"), `пределы комментария в машине: ${JSON.stringify(W.limits)}`);
      expect(W.permissions.some((p) => p.key === "incident:comment"), "нет права incident:comment");
      const tr = W.transitions.find((x) => x.id === "comment");
      expect(tr && tr.to == null && W.states.every((s) => tr.from.includes(s.id)), "нет действия comment без смены состояния из всех состояний");
      // Правки и удаления нет: ни действия машины, ни маршрута контракта
      const editors = W.transitions.filter((x) => /comment/.test(x.id) && x.id !== "comment").map((x) => x.id);
      const routes = Object.entries(window.IM_OPENAPI.paths).filter(([p, v]) => /journal|comment/.test(p) && (v.put || v.patch || v.delete)).map(([p]) => p);
      expect(!editors.length && !routes.length, `правка или удаление комментария: ${editors.concat(routes).join(", ")}`);
      const file = (i) => ({ id: `f${i}`, fileName: `n${i}.png`, mime: "image/png", size: 4, dataBase64: "AAAA" });
      try {
        const list = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items;
        const fresh = list.find((e) => e.state === "new");
        expect(fresh, "нет нового инцидента");
        const before = (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(fresh.guid)}`)).body;
        const ok = await standAct(fresh.guid, "comment", { comment: "note one", files: [file(1)] });
        expect(ok.status === 200, `комментарий к чужому новому: ${ok.status} ${JSON.stringify(ok.body)}`);
        const after = ok.body.incident;
        expect(after.state === before.state && JSON.stringify(after.owner) === JSON.stringify(before.owner), `состояние или владелец изменились: ${after.state}`);
        const entry = after.journal.filter((j) => j.templateKey === "workflow.journal.comment").pop();
        expect(entry && entry.actor && entry.actor.id === window.IM_FIXTURE.operator && entry.at && entry.vars.comment === "note one", `запись журнала: ${JSON.stringify(entry)}`);
        expect((entry.attachments || []).length === 1 && entry.attachments[0].fileName === "n1.png", `вложения записи: ${JSON.stringify(entry.attachments)}`);
        const empty = await standAct(fresh.guid, "comment", { comment: "", files: [] });
        expect(empty.status !== 200 && empty.body.code === "COMMENT_EMPTY", `пустой комментарий: ${empty.status} ${empty.body.code}`);
        const many = await standAct(fresh.guid, "comment", { comment: "x", files: [1, 2, 3, 4, 5, 6].map(file) });
        expect(many.status !== 200 && many.body.code === "ATTACHMENT_LIMIT", `${max + 1}-й файл: ${many.status} ${many.body.code}`);
        const big = await standAct(fresh.guid, "comment", { comment: "x", files: [Object.assign(file(1), { size: W.limits.attachmentMaxBytes + 1 })] });
        expect(big.status !== 200 && big.body.code === "ATTACHMENT_TOO_LARGE", `большой файл: ${big.status} ${big.body.code}`);
        const exe = await standAct(fresh.guid, "comment", { comment: "x", files: [Object.assign(file(1), { mime: "application/x-msdownload" })] });
        expect(exe.status !== 200 && exe.body.code === "ATTACHMENT_TYPE", `недопустимый тип: ${exe.status} ${exe.body.code}`);
        // К закрытому — можно: результат и момент закрытия не меняются
        const closed = (await stand.get("/operator/incidents", { filter: "done", pageSize: 1000 })).items.find((e) => e.state === "closed");
        expect(closed, "нет закрытого инцидента");
        const was = (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(closed.guid)}`)).body;
        const late = await standAct(closed.guid, "comment", { comment: "after review" });
        expect(late.status === 200, `комментарий к закрытому: ${late.status} ${JSON.stringify(late.body)}`);
        const now = late.body.incident;
        expect(now.state === "closed" && now.closeResultId === was.closeResultId && now.closedAt === was.closedAt, `закрытый изменился: ${now.state} ${now.closeResultId} ${now.closedAt}`);
        // Без права — отказ
        await standReset({ fixture: "demo", operatorPermissions: W.permissions.map((p) => p.key).filter((k) => k !== "incident:comment") });
        const denied = await standAct(fresh.guid, "comment", { comment: "x" });
        expect(denied.status === 403 && denied.body.code === "PERMISSION_DENIED", `без права incident:comment: ${denied.status} ${denied.body.code}`);
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Комментарий не меняет версию: владелец открыл форму закрытия, старший смены комментирует — закрытие владельца проходит без конфликта (ТЗ-18, решение 2026-11-14)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const fresh = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.state === "new");
        await standClaim(stand, fresh.guid);
        const card = await stand.raw("GET", `/operator/incidents/${encodeURIComponent(fresh.guid)}`);
        const etag = card.headers.etag || card.headers.ETag;
        const note = await petrovaAct(fresh.guid, "comment", { comment: "senior note" });
        expect(note.status === 200, `комментарий Петровой: ${note.status} ${JSON.stringify(note.body)}`);
        const after = await stand.raw("GET", `/operator/incidents/${encodeURIComponent(fresh.guid)}`);
        expect((after.headers.etag || after.headers.ETag) === etag, `версия изменилась: ${etag} → ${after.headers.etag || after.headers.ETag}`);
        // Свой (owner) взгляд — после чужого комментария: комментарий — новое событие, его владелец видит в карточке
        const close = await stand.raw("POST", `/operator/incidents/${encodeURIComponent(fresh.guid)}/transitions/close`, Object.assign({ formValues: { resultId: "false_alarm", causeId: "animal" }, surface: "card" }, seenBody(after.body)));
        expect(close.status === 200, `закрытие владельца после чужого комментария: ${close.status} ${close.body && close.body.code}`);
        return `версия ${etag}`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Эскалация: метка «Эскалация: <название уровня>» в строке и в заголовке карточки, подсказка «шаг N из M», на втором шаге — где не взяли; запись журнала с названием (§8.3)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const esc = window.IM_WORKFLOW.escalation;
      const [l1, l2] = esc.levels;
      expect(l1 && l2 && l1.name && l2.name, `у уровней поставки нет названий: ${JSON.stringify(esc.levels)}`);
      // Уровень 1 — я: эскалированный инцидент приходит мне на принятие; уровень 2 — как в поставке
      const levels = [Object.assign({}, l1, { targetKind: "user", target: "me" }), l2];
      const grace = (window.IM_WORKFLOW.invariants.manualWinsOverTimer || {}).graceSec || 0;
      // Часы — за реакцию и окно после дедлайна, шагами короче порога «нет связи», перед каждым — признак активности
      async function overdue(guid) {
        const due = Date.parse((await stand.get(`/operator/incidents/${encodeURIComponent(guid)}`)).timer.dueAt);
        let left = Math.ceil((due - Date.parse((await stand.raw("POST", "/test/clock", { advanceSec: 0 })).body.now)) / 1000) + grace + 1;
        for (; left > 0; left -= 240) {
          await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
          await stand.raw("POST", "/test/clock", { advanceSec: Math.min(240, left) });
        }
        await wait(100);
        return stand.get(`/operator/incidents/${encodeURIComponent(guid)}`);
      }
      const chipOf = async (guid) => {
        const row = await rowOnPages(guid);
        return row && row.querySelector(".chip.lvl");
      };
      try {
        await standReset({ fixture: "demo", workflowPatch: { escalation: Object.assign({}, esc, { levels }), limits: { maxActive: null } } });
        await wait(100);
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
        const fire = (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find((e) => e.eventType.id === "fire");
        const source = (await stand.get(`/operator/incidents/${encodeURIComponent(fire.guid)}`)).source.guid;
        const created = await stand.raw("POST", "/test/incidents", { eventTypeId: "fire", priority: 25, deviceIds: [source] });
        expect(created.status === 201, `инцидент не появился: ${created.status}`);
        const guid = created.body.guid;
        expect(!(await chipOf(guid)), "у неэскалированного (уровень 0) — метка эскалации");
        const one = await overdue(guid);
        expect(one.escalationLevel === 1 && one.state === "pending_acceptance", `после реакции: уровень ${one.escalationLevel}, ${one.state}`);
        const entry = one.journal.find((j) => j.templateKey === "workflow.journal.auto_escalate");
        expect(entry && entry.text.includes(`«${l1.name}», шаг 1`), `запись журнала: ${entry ? entry.text : "нет"}`);
        const c1 = await chipOf(guid);
        expect(c1 && c1.textContent.trim() === `Эскалация: ${l1.name}` && c1.title === `Автоэскалация, шаг 1 из ${esc.maxLevel}`, `уровень 1: «${c1 ? c1.textContent : "нет"}», подсказка «${c1 ? c1.title : ""}»`);
        const two = await overdue(guid);
        expect(two.escalationLevel === 2, `после второй реакции: уровень ${two.escalationLevel}, ${two.state}`);
        const c2 = await chipOf(guid);
        const tip2 = `Автоэскалация, шаг 2 из ${esc.maxLevel} — не взят вовремя на шаге «${l1.name}»`;
        expect(c2 && c2.textContent.trim() === `Эскалация: ${l2.name}` && c2.title === tip2, `уровень 2: «${c2 ? c2.textContent : "нет"}», подсказка «${c2 ? c2.title : ""}»`);
        // Заголовок карточки — та же метка
        const row = await rowOnPages(guid);
        await click(row.querySelector('[data-do="view"], [data-do="open_card"]'));
        expect(mode() === "work", "карточка не открылась");
        const head = $("workTitle").querySelector(".chip.lvl");
        expect(head && head.textContent.trim() === `Эскалация: ${l2.name}` && head.title === tip2, `заголовок карточки: «${head ? head.textContent : "нет"}»`);
        await click($("backToQueue"));
        // Уровень без названия — «Уровень N»
        await standReset({ fixture: "demo", workflowPatch: { escalation: Object.assign({}, esc, { levels: [Object.assign({}, levels[0], { name: "  " }), l2] }), limits: { maxActive: null } } });
        await wait(100);
        await setFilter("open");
        const plain = await stand.raw("POST", "/test/incidents", { eventTypeId: "fire", priority: 25, deviceIds: [source] });
        const p1 = await overdue(plain.body.guid);
        const pe = p1.journal.find((j) => j.templateKey === "workflow.journal.auto_escalate");
        const c0 = await chipOf(plain.body.guid);
        expect(c0 && c0.textContent.trim() === "Эскалация: Уровень 1" && pe && pe.text.includes("«Уровень 1», шаг 1"), `без названия: «${c0 ? c0.textContent : "нет"}», журнал «${pe ? pe.text : "нет"}»`);
        return `${c1.textContent.trim()}; ${c2.title}`;
      } finally {
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Комментарий в окне после дедлайна реакции не отменяет автоэскалацию (ТЗ-18, §10.1, правило 5; RULE-83)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const fire = (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find((e) => e.eventType.id === "fire");
        const source = (await stand.get(`/operator/incidents/${encodeURIComponent(fire.guid)}`)).source.guid;
        const top = Math.max(...window.IM_FIXTURE.priorities.map((p) => p.value));
        const created = await stand.raw("POST", "/test/incidents", { eventTypeId: "fire", priority: top, deviceIds: [source] });
        expect(created.status === 201, `инцидент не появился: ${created.status}`);
        const guid = created.body.guid;
        const norm = window.IM_WORKFLOW.timers.find((t) => t.id === "reaction").overrides.find((o) => o.priority === top).sec;
        const grace = (window.IM_WORKFLOW.invariants.manualWinsOverTimer || {}).graceSec || 0;
        expect(grace > 1, "окно после дедлайна не больше секунды");
        await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        await stand.raw("POST", "/test/clock", { advanceSec: norm + 1 });
        const res = await standAct(guid, "comment", { comment: "in window" });
        expect(res.status === 200 && res.body.canceledTimerTrigger == null, `комментарий в окне отменил срабатывание: ${res.status} ${res.body.canceledTimerTrigger}`);
        await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        await stand.raw("POST", "/test/clock", { advanceSec: grace + 2 });
        const card = (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(guid)}`)).body;
        const keys = card.journal.map((j) => j.templateKey);
        expect(keys.includes("workflow.journal.auto_escalate") && !keys.includes("workflow.journal.timer_overridden"), `журнал: ${keys.join(", ")}`);
        return card.state;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Кнопка «Комментарий» в карточке закрытого: форма с текстом и файлами, запись с файлом в журнале (ТЗ-18, 19)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const closed = (await stand.get("/operator/incidents", { filter: "done", pageSize: 1000 })).items.find((e) => e.state === "closed");
        await setFilter("done");
        const view = await buttonOnPages("view", closed.guid);
        expect(view, "у закрытого нет «Посмотреть»");
        await click(view);
        const b = button(root(), "comment");
        expect(b, "в карточке нет кнопки «Комментарий»");
        expect(b.closest(".incident-head"), "«Комментарий» закрытой карточки не в шапке");
        await click(b);
        expect(!$("modalDialog").hidden, "форма комментария не открылась");
        const input = $("dialogFields").querySelector('input[type="file"][data-files="files"]');
        expect(input, "в форме нет выбора файлов");
        const files = new DataTransfer();
        files.items.add(new File(["png"], "shot.png", { type: "image/png" }));
        input.files = files.files;
        input.dispatchEvent(new Event("change", { bubbles: true }));
        for (let k = 0; k < 25 && !/shot\.png/.test($("dialogFields").textContent); k++) await wait();
        expect(/shot\.png/.test($("dialogFields").textContent), "файл не прикрепился в форме");
        field("comment").value = NOTE;
        await click($("dialogConfirm"));
        await wait(100);
        expect($("modalDialog").hidden, "форма не закрылась");
        const card = (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(closed.guid)}`)).body;
        const entry = card.journal.filter((j) => j.templateKey === "workflow.journal.comment").pop();
        expect(entry && entry.vars.comment === NOTE && (entry.attachments || []).some((a) => a.fileName === "shot.png"), `запись журнала: ${JSON.stringify(entry)}`);
        expect(root().querySelector(".log-file") && /shot\.png/.test(root().textContent), "журнал карточки не показывает файл");
        return entry.text;
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await setFilter("open");
        await wait(100);
      }
    });

    /* ===== Ручная смена приоритета (ТЗ-13, §2.5, §4, §6.3) ===== */

    // Уровни справочника по убыванию; инцидент — новый пожар самого срочного уровня
    const prLevels = () => window.IM_FIXTURE.priorities.map((p) => p.value).sort((a, b) => b - a);
    const prCard = async (guid) => (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(guid)}`)).body;
    const prNewTop = async () => (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.state === "new" && e.priority === prLevels()[0]);
    const prNorm = (timerId, level) => {
      const t = window.IM_WORKFLOW.timers.find((x) => x.id === timerId);
      const o = (t.overrides || []).find((x) => x.priority === level && Object.keys(x).length === 2);
      return o ? o.sec : (t.byPriority || {})[String(level)] != null ? t.byPriority[String(level)] : t.defaultSec;
    };

    await step("Смена приоритета с правом и причиной: приоритет новый, «замок» priorityManual, запись «было → стало, кто, почему» (ТЗ-13)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const W = window.IM_WORKFLOW;
      expect(W.permissions.some((p) => p.key === "incident:priority"), "нет права incident:priority");
      const tr = W.transitions.find((x) => x.id === "change_priority");
      expect(tr && tr.to == null && !tr.from.includes("closed"), "нет действия change_priority без смены состояния из незакрытых");
      try {
        const inc = await prNewTop();
        const low = prLevels()[prLevels().length - 1];
        const res = await standAct(inc.guid, "change_priority", { priority: String(low), comment: "selftest reason" });
        expect(res.status === 200, `смена приоритета: ${res.status} ${JSON.stringify(res.body)}`);
        const c = res.body.incident;
        expect(c.priority === low && c.priorityManual === true && c.state === inc.state, `инцидент: ${c.priority} ${c.priorityManual} ${c.state}`);
        const e = c.journal.filter((j) => j.templateKey === "workflow.journal.priority_changed").pop();
        expect(e && e.vars.from === inc.priority && e.vars.to === low && e.vars.comment === "selftest reason" && e.actor && e.actor.id === window.IM_FIXTURE.operator, `запись журнала: ${JSON.stringify(e)}`);
        return e.text;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Смена приоритета пересортировывает очередь: поднятый встаёт выше всех уровнем ниже (ТЗ-13, §7)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const list = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items;
        const low = list.filter((e) => e.state === "new").sort((a, b) => a.priority - b.priority)[0];
        const top = prLevels()[0];
        expect(low && low.priority < top, "нет нового ниже самого срочного уровня");
        const res = await standAct(low.guid, "change_priority", { priority: String(top), comment: "raise" });
        expect(res.status === 200, `смена приоритета: ${res.status} ${res.body && res.body.code}`);
        const after = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items;
        const at = after.findIndex((e) => e.guid === low.guid);
        expect(after.slice(0, at).every((e) => e.priority >= top) && after.slice(at).every((e) => e.priority <= top), `порядок очереди: ${after.map((e) => e.priority).join(",")}`);
        return `место ${list.findIndex((e) => e.guid === low.guid) + 1} → ${at + 1}`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Смена приоритета без права incident:priority — отказ 403 PERMISSION_DENIED (ТЗ-13, §5)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        await standReset({ fixture: "demo", operatorPermissions: window.IM_WORKFLOW.permissions.map((p) => p.key).filter((k) => k !== "incident:priority") });
        const inc = await prNewTop();
        const res = await standAct(inc.guid, "change_priority", { priority: String(prLevels()[1]), comment: "x" });
        expect(res.status === 403 && res.body.code === "PERMISSION_DENIED", `без права: ${res.status} ${res.body && res.body.code}`);
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Смена приоритета без причины — отказ 422, приоритет прежний (ТЗ-13)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      expect((window.IM_WORKFLOW.transitions || []).some((x) => x.id === "change_priority"), "нет действия change_priority");
      try {
        const inc = await prNewTop();
        const res = await standAct(inc.guid, "change_priority", { priority: String(prLevels()[1]), comment: "  " });
        expect(res.status === 422, `без причины: ${res.status} ${res.body && res.body.code}`);
        expect((await prCard(inc.guid)).priority === inc.priority, "приоритет изменился");
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Смена приоритета по устаревшему уровню — отказ 412 «Приоритет уже изменён», первая смена не затёрта (§14.1, RULE-143)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const inc = await prNewTop();
        const seen = (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(inc.guid)}`)).body;
        const [first, second] = prLevels().filter((v) => v !== seen.priority);
        expect((await standAct(inc.guid, "change_priority", { priority: String(first), comment: "x" })).status === 200, "первая смена не прошла");
        // Вторая вкладка видела прежний уровень
        const res = await stand.raw("POST", `/operator/incidents/${encodeURIComponent(inc.guid)}/transitions/change_priority`, Object.assign({ formValues: { priority: String(second), comment: "y" }, surface: "card" }, seenBody(seen)));
        expect(res.status === 412 && res.body.details && res.body.details.changed === "priority", `устаревший уровень: ${res.status} ${res.body && res.body.details && res.body.details.changed}`);
        expect(/^Приоритет уже изменён: /.test(res.body.message), `текст отказа: ${res.body.message}`);
        expect((await prCard(inc.guid)).priority === first, "первая смена затёрта");
        return res.body.message;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Смена приоритета на тот же уровень — отказ PRIORITY_UNCHANGED без записи в журнал (ТЗ-13)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const inc = await prNewTop();
        const before = (await prCard(inc.guid)).journal.length;
        const res = await standAct(inc.guid, "change_priority", { priority: String(inc.priority), comment: "same" });
        expect(res.status === 403 && res.body.code === "PRIORITY_UNCHANGED", `тот же уровень: ${res.status} ${res.body && res.body.code}`);
        expect((await prCard(inc.guid)).journal.length === before, "в журнале появилась запись");
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Смена приоритета: ненаступивший срок реакции пересчитан от прежней точки отсчёта по нормативу нового уровня (ТЗ-13, §4)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const inc = await prNewTop();
        const was = await prCard(inc.guid);
        const low = prLevels()[prLevels().length - 1];
        const res = await standAct(inc.guid, "change_priority", { priority: String(low), comment: "lower" });
        expect(res.status === 200, `смена приоритета: ${res.status} ${res.body && res.body.code}`);
        const shift = Date.parse(res.body.incident.timer.dueAt) - Date.parse(was.timer.dueAt);
        const want = (prNorm("reaction", low) - prNorm("reaction", inc.priority)) * 1000;
        expect(res.body.incident.timer.id === "reaction" && shift === want, `срок реакции сдвинут на ${shift} мс, а нужно ${want}`);
        return `${was.timer.dueAt} → ${res.body.incident.timer.dueAt}`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Смена приоритета: выполненный норматив реакции не тронут — после «Вернуть в очередь» реакция с прежнего остатка (ТЗ-13, §4)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const inc = await prNewTop();
        const was = await prCard(inc.guid);
        await standClaim(stand, inc.guid);
        const claimedAt = Date.parse((await prCard(inc.guid)).timer.serverTime || new Date().toISOString());
        const left = Date.parse(was.timer.dueAt) - claimedAt;
        const res = await standAct(inc.guid, "change_priority", { priority: String(prLevels()[prLevels().length - 1]), comment: "lower" });
        expect(res.status === 200, `смена приоритета: ${res.status} ${res.body && res.body.code}`);
        const back = await standAct(inc.guid, "release", { comment: "back" });
        expect(back.status === 200, `вернуть в очередь: ${back.status}`);
        const t = back.body.incident.timer;
        const got = Date.parse(t.dueAt) - Date.parse(t.serverTime);
        expect(t.id === "reaction" && Math.abs(got - left) < 2000, `остаток реакции ${got} мс, был ${left}`);
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Ручной приоритет переживает переоткрытие: priorityManual и уровень сохранены (ТЗ-13, §2.5)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const inc = await prNewTop();
        const low = prLevels()[prLevels().length - 1];
        await standClaim(stand, inc.guid);
        const res = await standAct(inc.guid, "change_priority", { priority: String(low), comment: "lower" });
        expect(res.status === 200, `смена приоритета: ${res.status} ${res.body && res.body.code}`);
        const closed = await standAct(inc.guid, "close", { resultId: "false_alarm", causeId: "animal" });
        expect(closed.status === 200, `закрыть: ${closed.status} ${closed.body && closed.body.code}`);
        const again = await standAct(inc.guid, "reopen", { comment: "again" });
        expect(again.status === 200, `переоткрыть: ${again.status} ${again.body && again.body.code}`);
        expect(again.body.incident.priority === low && again.body.incident.priorityManual === true, `после переоткрытия: ${again.body.incident.priority} ${again.body.incident.priorityManual}`);
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    // Пара новых пожаров самого срочного уровня одного сценария — объединение (§11.3)
    const prMergeTop = async () => {
      const all = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items;
      const top = all.find((e) => e.state === "new" && e.priority === prLevels()[0] && e.eventType.id === "fire");
      const pair = all.filter((e) => e.state === "new" && e.priority === top.priority && e.eventType.id === "fire" && e.scenarioTitle === top.scenarioTitle);
      expect(pair.length >= 2, "нет пары срочных пожаров одного сценария");
      const res = await stand.raw("POST", "/operator/incidents/merge", { incidentGuids: pair.slice(0, 2).map((e) => e.guid) });
      expect(res.status === 200, `объединение: ${res.status} ${res.body && res.body.code}`);
      return { primary: res.body.incident, linked: pair.slice(0, 2).find((e) => e.guid !== res.body.incident.guid) };
    };

    await step("Смена приоритета у привязанного — отказ: приоритет группы у основного (ТЗ-13, §11.4)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const { linked } = await prMergeTop();
        const res = await standAct(linked.guid, "change_priority", { priority: String(prLevels()[prLevels().length - 1]), comment: "lower" });
        expect(res.status === 409 && res.body.code === "TRANSITION_NOT_ALLOWED_FROM_STATE", `у привязанного: ${res.status} ${res.body && res.body.code}`);
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Понижение основного не делает срок группы позже срока строгого привязанного (ТЗ-13, §4 правило 8)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const { primary } = await prMergeTop();
        const was = await prCard(primary.guid);
        const res = await standAct(primary.guid, "change_priority", { priority: String(prLevels()[prLevels().length - 1]), comment: "lower" });
        expect(res.status === 200, `понизить основного: ${res.status} ${res.body && res.body.code}`);
        expect(res.body.incident.timer.dueAt === was.timer.dueAt, `срок группы ${was.timer.dueAt} → ${res.body.incident.timer.dueAt}`);
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    // Часы стенда вперёд шагами короче порога молчания, перед каждым — признак активности (§12.3)
    const prAdvance = async (sec) => {
      const stepSec = Math.max(1, window.IM_WORKFLOW.session.idleHoldSec - 1);
      for (let left = sec; left > 0; left -= stepSec) {
        await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        await stand.raw("POST", "/test/clock", { advanceSec: Math.min(left, stepSec) });
      }
    };
    const prMergeWith = async (second) => {
      const fires = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.filter((e) => e.state === "new" && e.eventType.id === "fire").sort((a, b) => b.priority - a.priority);
      const first = fires[0];
      const other = fires.find((e) => e !== first && e.scenarioTitle === first.scenarioTitle && second(e));
      expect(other, "нет второго пожара для группы");
      const res = await stand.raw("POST", "/operator/incidents/merge", { incidentGuids: [first.guid, other.guid] });
      expect(res.status === 200, `объединение: ${res.status}`);
      return res.body.incident;
    };

    await step("Основной с привязанным: отложили, вернули, сменили приоритет — срок группы не сжался и не стал «сейчас» (ТЗ-13, §4 правило 8)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const primary = await prMergeWith(() => true);
        const held = await standAct(primary.guid, "hold", { reasonId: "third_party", comment: "wait" });
        expect(held.status === 200, `отложить: ${held.status}`);
        await prAdvance(300);
        const back = await standAct(primary.guid, "resume", {});
        expect(back.status === 200, `возобновить: ${back.status}`);
        const was = await prCard(primary.guid);
        const res = await standAct(primary.guid, "change_priority", { priority: String(prLevels()[prLevels().length - 1]), comment: "lower" });
        expect(res.status === 200 && res.body.incident.timer.dueAt === was.timer.dueAt, `срок группы ${was.timer.dueAt} → ${res.body.incident && res.body.incident.timer.dueAt}`);
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Основной с менее строгим привязанным: понижение не продлевает срок группы (ТЗ-13, §4 правило 8)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const primary = await prMergeWith((e) => e.priority < prLevels()[0]);
        const was = await prCard(primary.guid);
        const res = await standAct(primary.guid, "change_priority", { priority: String(prLevels()[prLevels().length - 1]), comment: "lower" });
        expect(res.status === 200 && res.body.incident.timer.dueAt === was.timer.dueAt, `срок группы ${was.timer.dueAt} → ${res.body.incident && res.body.incident.timer.dueAt}`);
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Кнопка «Сменить приоритет» в карточке: форма с уровнем и причиной, запись в журнале карточки (ТЗ-13)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const inc = await prNewTop();
        await setFilter("open");
        const view = await buttonOnPages("view", inc.guid);
        expect(view, "у нового нет «Посмотреть»");
        await click(view);
        const b = button(root(), "change_priority");
        expect(b, "в карточке нет кнопки «Сменить приоритет»");
        await click(b);
        expect(!$("modalDialog").hidden, "форма смены приоритета не открылась");
        const sel = field("priority");
        const low = String(prLevels()[prLevels().length - 1]);
        expect(sel && [...sel.options].some((o) => o.value === low), "в форме нет уровней справочника");
        await setField("priority", low);
        field("comment").value = NOTE;
        await click($("dialogConfirm"));
        await wait(100);
        expect($("modalDialog").hidden, "форма не закрылась");
        const card = await prCard(inc.guid);
        expect(card.priority === Number(low), `приоритет ${card.priority}`);
        const e = card.journal.filter((j) => j.templateKey === "workflow.journal.priority_changed").pop();
        expect(e && root().textContent.includes(e.text), "журнал карточки не показывает смену приоритета");
        return e.text;
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await setFilter("open");
        await wait(100);
      }
    });

    /* ===== Окна плановых работ (ТЗ-21, §14.5, §14.12) ===== */

    // Пожар на датчике дыма 5 ТЦ — его ловит базовое правило «Пожарная тревога»; окно — через запросы окон
    const mwSmoke = "20000000-0002-4000-8000-000000000005";
    const mwCam = "20000000-0001-4000-8000-000000000031"; // «Зона ожидания» → «Приемная» → «1-й этаж»
    const mwFloor = "30000000-0000-4000-8000-000000000002";
    const mwEvent = (n, dev, type) => ({ eventTypeId: type || "fire", deviceIds: [dev || mwSmoke] });
    const mwIso = (ms) => new Date(ms).toISOString();
    const mwHour = 3600000;
    // Стенд с часами; ответ — «сейчас» стенда в мс
    async function mwSetup(extra) {
      const r = await standReset(Object.assign({ fixture: "demo" }, extra));
      return Date.parse(r.body.now);
    }
    const mwCreate = (spec) => stand.raw("POST", "/operator/maintenance-windows", Object.assign({ description: "selftest работы", timeZone: "UTC", recurrence: null }, spec));
    const mwFire = (n, dev, type) => stand.raw("POST", "/test/events", mwEvent(n, dev, type));
    const mwLowest = () => Math.min(...window.IM_FIXTURE.priorities.map((p) => p.value));

    await step("Окно работ при suppress: событие в окне не создаёт инцидент, итог — плановые работы со ссылкой на окно; другое устройство — как обычно (ТЗ-21)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const W = window.IM_WORKFLOW;
      expect(W.maintenance && W.maintenance.mode === "suppress", "в машине нет maintenance.mode = suppress по умолчанию");
      expect(W.intake && W.intake.windows === "windowsAfterWinners" && W.cel.definitions.windowsFor, "в intake машины нет отбора окон windowsAfterWinners");
      const sc = window.IM_OPENAPI.components.schemas;
      expect(sc.MaintenanceWindow && sc.EventExplanationRule.properties.verdict.enum.includes("maintenance"), "в контракте нет MaintenanceWindow или вердикта maintenance");
      try {
        const now = await mwSetup();
        const w = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        expect(w.status === 201 && w.body.id && w.body.status === "active", `окно не создано: ${w.status} ${JSON.stringify(w.body)}`);
        const r = await mwFire(1);
        expect(r.body.created === 0 && r.body.alarmNumber == null, `событие в окне создало ${r.body.created} инц.`);
        expect(r.body.maintenance && r.body.maintenance.windowId === w.body.id && r.body.maintenance.mode === "suppress", `итог события: ${JSON.stringify(r.body.maintenance)}`);
        const other = await mwFire(2, "20000000-0002-4000-8000-000000000001");
        expect(other.body.created >= 1 && !other.body.maintenance, `другое устройство: создано ${other.body.created}`);
        return `окно ${w.body.id}: подавлено; другое устройство — ${other.body.created} инц.`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Окно работ при mark: инцидент создан с флагом окна и низшим приоритетом справочника, priorityManual = false (ТЗ-21, ТЗ-13)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup({ workflowPatch: { maintenance: { mode: "mark" } } });
        const w = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        const r = await mwFire(3);
        expect(r.body.created >= 1, `при mark инцидент не создан: ${JSON.stringify(r.body)}`);
        const inc = r.body.incidents[0];
        expect(inc.maintenanceWindowId === w.body.id && inc.priority === mwLowest() && inc.priorityManual === false, `инцидент: окно ${inc.maintenanceWindowId}, приоритет ${inc.priority}, ручной ${inc.priorityManual}`);
        expect(r.body.maintenance && r.body.maintenance.mode === "mark", `итог события: ${JSON.stringify(r.body.maintenance)}`);
        return `${inc.number}: приоритет ${inc.priority}`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Граница окна — полуинтервал [начало, конец): ровно в конец — вне окна, ровно в начало — в окне (ТЗ-21)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        let now = await mwSetup();
        await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now) });
        const atEnd = await mwFire(4);
        expect(atEnd.body.created >= 1 && !atEnd.body.maintenance, `событие в конец окна подавлено: ${JSON.stringify(atEnd.body.maintenance)}`);
        now = await mwSetup();
        await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        const atStart = await mwFire(5);
        expect(atStart.body.created === 0 && atStart.body.maintenance, "событие в начало окна не подавлено");
        return "конец — вне, начало — в окне";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Окно на группу: устройство во вложенной группе — в окне (ТЗ-21)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup();
        const w = await mwCreate({ sourceGroupGuid: mwFloor, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        expect(w.status === 201, `окно на группу: ${w.status} ${JSON.stringify(w.body)}`);
        const r = await mwFire(6, mwCam);
        expect(r.body.created === 0 && r.body.maintenance && r.body.maintenance.windowId === w.body.id, `камера во вложенной группе: создано ${r.body.created}`);
        return "подгруппа — в окне";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Повтор по дням недели: окно сегодняшнего дня действует, окно других дней — нет (ТЗ-21)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup();
        const d = new Date(now);
        const iso = d.getUTCDay() || 7; // ISO: понедельник 1 … воскресенье 7
        const hm = (ms) => new Date(ms).toISOString().slice(11, 16);
        const rec = (days) => ({ days, startTime: hm(now - 30 * 60000), endTime: hm(now + 30 * 60000) });
        // Окно «сегодняшнего дня» — день его начала (§14.12): рядом с полночью (23:30–00:30 UTC) окно идёт через неё, и
        // сейчас — в окне, начатом вчера. Тест от времени суток не зависит: день окна, накрывающего now, считается по часам
        const { startTime, endTime } = rec([]);
        const own = endTime <= startTime && hm(now) < endTime ? (iso + 5) % 7 + 1 : iso;
        const series = { startsAt: mwIso(now), endsAt: mwIso(now + 30 * 24 * mwHour) };
        const other = await mwCreate(Object.assign({ deviceGuid: mwSmoke, recurrence: rec([1, 2, 3, 4, 5, 6, 7].filter((x) => x !== own)) }, series));
        expect(other.status === 201, `повтор не создан: ${other.status} ${JSON.stringify(other.body)}`);
        const miss = await mwFire(7);
        expect(miss.body.created >= 1 && !miss.body.maintenance, "окно других дней недели подавило событие");
        await mwCreate(Object.assign({ deviceGuid: mwSmoke, recurrence: rec([own]) }, series));
        const hit = await mwFire(8);
        expect(hit.body.created === 0 && hit.body.maintenance, "окно сегодняшнего дня не подавило событие");
        return `день ${own}: в окне`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Событие без правила-победителя в окне — не сработало, а не плановые работы (ТЗ-21, §14.5)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup({ fixturePatch: { rules: [] } });
        await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        const r = await mwFire(9);
        expect(r.body.created === 0 && !r.body.maintenance, `без правил итог: ${JSON.stringify(r.body.maintenance)}`);
        return "окно не названо";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Досрочное завершение: конец = сейчас, после него событие даёт инцидент; идущее окно — правится только конец и описание, удалить нельзя (ТЗ-21)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup();
        const w = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        const id = encodeURIComponent(w.body.id);
        const move = await stand.raw("PUT", `/operator/maintenance-windows/${id}`, Object.assign({}, w.body, { deviceGuid: "20000000-0002-4000-8000-000000000001" }));
        expect(move.status === 409 && move.body.code === "MAINTENANCE_WINDOW_ACTIVE", `смена устройства идущего окна: ${move.status} ${move.body && move.body.code}`);
        const del = await stand.raw("DELETE", `/operator/maintenance-windows/${id}`);
        expect(del.status === 409 && del.body.code === "MAINTENANCE_WINDOW_ACTIVE", `удаление идущего окна: ${del.status}`);
        const desc = await stand.raw("PUT", `/operator/maintenance-windows/${id}`, Object.assign({}, w.body, { description: "новое описание" }));
        expect(desc.status === 200 && desc.body.description === "новое описание", `правка описания: ${desc.status}`);
        const end = await stand.raw("POST", `/operator/maintenance-windows/${id}/end`, {});
        expect(end.status === 200 && Date.parse(end.body.endsAt) === now && end.body.status === "ended", `досрочно: ${end.status} ${JSON.stringify(end.body)}`);
        const r = await mwFire(10);
        expect(r.body.created >= 1 && !r.body.maintenance, "после досрочного завершения событие подавлено");
        const again = await stand.raw("POST", `/operator/maintenance-windows/${id}/end`, {});
        expect(again.status === 409 && again.body.code === "MAINTENANCE_WINDOW_ENDED", `завершить закончившееся: ${again.status}`);
        return "завершено, событие — инцидент";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Карточка показывает пересекающиеся окна; закрытие «Плановая проверка» хранит ссылку на окно, чужое окно — отказ 422 (ТЗ-21, §2.2)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup({ workflowPatch: { maintenance: { mode: "mark" }, limits: { maxActive: null } } });
        const w = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        const far = await mwCreate({ deviceGuid: "20000000-0002-4000-8000-000000000001", startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        const inc = (await mwFire(11)).body.incidents[0];
        const card = await prCard(inc.guid);
        expect((card.maintenanceWindows || []).map((x) => x.id).join() === w.body.id, `окна карточки: ${JSON.stringify(card.maintenanceWindows)}`);
        expect((await standAct(inc.guid, "claim", {}, "queue")).status === 200, "инцидент не взят");
        const bad = await standAct(inc.guid, "close", { resultId: "drill", maintenanceWindowId: far.body.id, comment: "работы" });
        expect(bad.status === 422, `чужое окно при закрытии: ${bad.status}`);
        const ok = await standAct(inc.guid, "close", { resultId: "drill", maintenanceWindowId: w.body.id, comment: "работы" });
        expect(ok.status === 200 && ok.body.incident.closeMaintenanceWindowId === w.body.id, `закрытие с окном: ${ok.status} ${ok.body.incident && ok.body.incident.closeMaintenanceWindowId}`);
        return `${inc.number}: закрыт с окном`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Без права maintenance:edit окно не создать — 403 PERMISSION_DENIED; список окон виден (ТЗ-21, §5)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const W = window.IM_WORKFLOW;
      expect(W.permissions.some((p) => p.key === "maintenance:edit"), "нет права maintenance:edit");
      try {
        const now = await mwSetup({ operatorPermissions: W.permissions.map((p) => p.key).filter((k) => k !== "maintenance:edit") });
        const r = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now + mwHour), endsAt: mwIso(now + 2 * mwHour) });
        expect(r.status === 403 && r.body.code === "PERMISSION_DENIED", `без права: ${r.status} ${r.body && r.body.code}`);
        const list = await stand.raw("GET", "/operator/maintenance-windows");
        expect(list.status === 200 && Array.isArray(list.body) && list.body.length >= 2, `список окон: ${list.status}`);
        return `окон в наборе: ${list.body.length}`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    // Экран «Смена и статистика» (§23): вкладка, блок «Сейчас», сортировка и фильтр
    await step("Смена и статистика (§23, план 90): вкладка рядом с очередью по праву supervisor:view; «Сейчас» — смена, сводка, все операторы, по умолчанию по «С какого времени» сверху новые, вышедшие свёрнуты, сортировка по щелчку, фильтр по дежурной группе; без права вкладки нет", async () => {
      const fx = window.IM_FIXTURE;
      const shown = () => [...$("shiftTable").querySelectorAll("tbody tr[data-shift-person]")];
      const people = () => shown().map((r) => r.dataset.shiftPerson);
      const until = async (cond, what) => {
        for (let i = 0; i < 40 && !cond(); i++) await wait(100);
        expect(cond(), what);
      };
      try {
        expect(!$("screenTabs").hidden, "вкладок «Очередь» и «Смена и статистика» нет при праве supervisor:view");
        await click($("tabShift"));
        await until(() => shown().length > 0, "таблица операторов не пришла");
        expect($("workspace").hidden && !$("shiftScreen").hidden, "экран смены не открылся вместо очереди");
        expect(/^смена \d\d:\d\d–\d\d:\d\d$/.test($("shiftSpan").textContent), `над таблицей — не смена: «${$("shiftSpan").textContent}»`);
        expect(/обновлено .* само раз в 30 с/.test($("shiftUpdated").textContent), `время обновления: «${$("shiftUpdated").textContent}»`);
        const sums = [...$("shiftSummary").querySelectorAll("[data-shift-sum]")].map((x) => x.dataset.shiftSum);
        expect(sums.join() === "present,not_ready,no_link,offline,unowned,overdue", `сводка: ${sums.join(", ")}`);
        // Все, кто может принять (решение 9): шесть на месте и на перерыве, вышедший Кузнецов — в свёрнутой строке
        const here = fx.people.operators.filter((o) => o.agentState !== "offline").map((o) => o.id);
        expect(people().slice().sort().join() === here.slice().sort().join(), `строки: ${people().join(", ")}`);
        const since = shown().map((r) => Date.parse(r.dataset.shiftSince));
        expect(since.every((v, i) => i === 0 || since[i - 1] >= v), "по умолчанию не по «С какого времени», сверху новые");
        const orlova = $("shiftTable").querySelector('tr[data-shift-person="orlova"]');
        expect(orlova.cells[1].textContent.trim() === "Перерыв" && orlova.cells[2].textContent.trim() === "Обед" && /· \d+ мин/.test(orlova.cells[3].textContent), `Орлова: «${orlova.textContent.replace(/\s+/g, " ").trim()}»`);
        const out = $("shiftTable").querySelector("tr.shift-out [data-shift-out]");
        expect(out && out.textContent.trim() === "Кузнецов И. П.", `свёрнутые вышедшие: «${out ? out.textContent.trim() : "нет строки"}»`);
        await click(out);
        expect(people().includes("kuznetsov") && people()[people().length - 1] === "kuznetsov", "вышедший не раскрылся в конце таблицы");
        // Сортировка: щелчок — по столбцу, повторный — обратно
        await click($("shiftTable").querySelector('[data-shift-sort="name"]'));
        const coll = new Intl.Collator("ru", { sensitivity: "base" });
        const names = () => shown().filter((r) => r.dataset.shiftState !== "offline").map((r) => r.cells[0].textContent.trim());
        const asc = names();
        expect(asc.every((v, i) => i === 0 || coll.compare(asc[i - 1], v) <= 0), `по имени: ${asc.join(", ")}`);
        await click($("shiftTable").querySelector('[data-shift-sort="name"]'));
        expect(names().join() === asc.slice().reverse().join(), `по имени обратно: ${names().join(", ")}`);
        expect(people()[people().length - 1] === "kuznetsov", "вышедший не остался в конце");
        // Между опросами раз в 5 с меняется только «сколько длится»: таблица та же, фокус на кнопке сортировки остаётся
        const sortBtn = $("shiftTable").querySelector('[data-shift-sort="name"]');
        const row = $("shiftTable").querySelector('tr[data-shift-person="orlova"]');
        expect(document.activeElement === sortBtn, "после сортировки фокус ушёл с кнопки столбца");
        await wait(5200);
        expect(row.isConnected && document.activeElement === sortBtn, "таблица перестроилась между опросами — фокус потерян");
        expect(/· \d+ мин/.test(row.cells[3].textContent), `«сколько длится» у Орловой: «${row.cells[3].textContent}»`);
        // Фильтр по дежурной группе — участники группы
        const select = $("shiftGroup");
        select.value = "grp-response";
        select.dispatchEvent(new Event("change"));
        await until(() => people().length === 2, `фильтр «Группа реагирования»: ${people().join(", ")}`);
        expect(people().sort().join() === "gusev,sidorov", `фильтр «Группа реагирования»: ${people().join(", ")}`);
        select.value = "";
        select.dispatchEvent(new Event("change"));
        await until(() => people().length > 2, "фильтр не снялся");
        await click($("screenTabs").querySelector('[data-screen="queue"]'));
        expect(!$("workspace").hidden && $("shiftScreen").hidden, "очередь не вернулась");
        // Без права — вкладок нет
        await standReset({ fixture: "demo", operatorPermissions: window.IM_WORKFLOW.permissions.map((p) => p.key).filter((k) => k !== "supervisor:view") });
        await until(() => $("screenTabs").hidden, "без права supervisor:view вкладки остались");
        expect($("navShift").hidden, "без права кнопка «Смена» на телефоне осталась");
        return `строк ${here.length}, сводка ${sums.length} чисел`;
      } finally {
        if (!$("shiftScreen").hidden) await click($("screenTabs").querySelector('[data-screen="queue"]'));
        await standReset({ fixture: "demo" });
        await wait(400);
        await setFilter("open");
      }
    });

    // Права аудита (§5, §12.4): экрана аудита в прототипе нет — проверка запросами
    await step("С одним правом audit:actions:view — журнал действий 200, журнал настроек и настройки 403; выгрузка — по audit:export (§5, §12.4)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const W = window.IM_WORKFLOW;
      const keys = W.permissions.map((p) => p.key);
      expect(["supervisor:view", "audit:actions:view", "audit:export"].every((k) => keys.includes(k)), `в машине нет прав старшего и аудита: ${keys.join(", ")}`);
      const code = async (path) => (await stand.raw("GET", path)).status;
      try {
        await standReset({ fixture: "demo", operatorPermissions: ["audit:actions:view"] });
        const got = {
          actions: await code("/operator/admin/audit/actions"),
          settings: await code("/operator/admin/audit/settings"),
          adminSettings: await code("/operator/admin/access-groups"),
          export: await code("/operator/admin/audit/actions/export"),
        };
        expect(got.actions === 200 && got.settings === 403 && got.adminSettings === 403 && got.export === 403, `с одним audit:actions:view: ${JSON.stringify(got)}`);
        await standReset({ fixture: "demo", operatorPermissions: ["audit:actions:view", "audit:export"] });
        const exp = await code("/operator/admin/audit/actions/export");
        expect(exp === 200, `выгрузка журнала действий с audit:export: ${exp}`);
        return `журнал действий 200, журнал настроек ${got.settings}, настройки ${got.adminSettings}, выгрузка без права ${got.export}, с правом ${exp}`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    // Идут плановые работы — пункт строки состояния поста (§22.4) и значок в дереве групп (ТЗ-21, §14.12, §19.1).
    // Полностью, со списком окон, — на вкладке «Система» колокольчика; в строке — если он самый серьёзный, иначе «и ещё N»
    const mwBanner = () => $("bellStates").querySelector('[data-post-state="maintenance"]');
    const mwShown = () => Boolean(mwBanner());
    const mwInLine = () => Boolean($("postStatus").querySelector('[data-post-state="maintenance"], .post-more'));
    async function mwUntil(cond, what) {
      for (let i = 0; i < 40 && !cond(); i++) await wait(100);
      expect(cond(), what);
    }
    const mwBadge = (id) => $("groupsList").querySelector(`[data-id="${id}"] > .node-content .tree-maint`);
    const mwShop = "30000000-0000-4000-8000-000000000023"; // «Магазин 1» → «1-й этаж» → «Торговый центр»
    const mwTcFloor = "30000000-0000-4000-8000-000000000022";

    await step("Плановые работы: без окна пункта нет; идёт окно — в строке поста (или «и ещё N»), полностью — объект, описание, конец и «тревоги не создаются», role=status (ТЗ-21, §22.4)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      expect(window.IM_OPENAPI.paths["/operator/maintenance-windows/current"], "в контракте нет GET /operator/maintenance-windows/current");
      try {
        if (mode() !== "queue") await click($("backToQueue"));
        const now = await mwSetup();
        await wait(100);
        expect($("postStatus") && !$("maintBanner"), "нет строки состояния поста (#postStatus) или осталась полоса над очередью (#maintBanner)");
        await mwUntil(() => !mwShown(), "пункт работ виден без идущего окна");
        const w = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour), description: "замена датчика" });
        expect(w.status === 201, `окно не создано: ${w.status}`);
        await mwUntil(mwShown, "пункт работ не появился при идущем окне");
        const text = mwBanner().textContent;
        expect($("postStatus").getAttribute("role") === "status", "у строки поста нет role=status");
        expect(/замена датчика/.test(text) && /не создаются/.test(text), `текст пункта: ${text}`);
        expect(mwInLine() && $("postStatus").closest(".topbar"), `в строке поста шапки нет работ и «и ещё N»: «${$("postStatus").textContent.trim()}»`);
        return text.replace(/\s+/g, " ").trim();
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Плановые работы при mark — «тревоги приходят с пометкой»; два окна — «N окон», на вкладке «Система» — список окон (ТЗ-21, §22.4)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup({ workflowPatch: { maintenance: { mode: "mark" } } });
        await wait(100);
        await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        await mwUntil(mwShown, "пункт работ не появился");
        expect(/с пометкой/.test(mwBanner().textContent), `текст режима mark: ${mwBanner().textContent}`);
        await mwCreate({ sourceGroupGuid: mwFloor, startsAt: mwIso(now), endsAt: mwIso(now + 2 * mwHour) });
        await mwUntil(() => /2 окна/.test(mwBanner().textContent), `два окна: ${mwBanner().textContent}`);
        expect(mwBanner().querySelectorAll(".maint-list li").length === 2, `на вкладке «Система» не два окна: ${mwBanner().textContent}`);
        return mwBanner().textContent.replace(/\s+/g, " ").trim();
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Пункт работ уходит из строки поста после досрочного завершения окна, в колокольчике — «Плановые работы закончились» (ТЗ-21, §22.4)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup();
        await wait(100);
        const w = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        await mwUntil(mwShown, "пункт работ не появился");
        const end = await stand.raw("POST", `/operator/maintenance-windows/${w.body.id}/end`, {});
        expect(end.status === 200, `досрочное завершение: ${end.status}`);
        await mwUntil(() => !mwShown(), "пункт работ не ушёл после досрочного завершения");
        const ended = noticeWith(/Плановые работы закончились/);
        expect(ended && ended.dataset.kind === "system", `в колокольчике нет записи «Система» о конце работ: ${noticeList()}`);
        return `ушёл; «${ended.textContent}»`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Значок работ в дереве: у группы окна и её подгруппы, с подсказкой; у устройства окна (ТЗ-21)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup();
        await wait(100);
        await mwCreate({ sourceGroupGuid: mwTcFloor, startsAt: mwIso(now), endsAt: mwIso(now + mwHour), description: "ремонт этажа" });
        await mwUntil(() => mwBadge(mwTcFloor), "нет значка у группы окна");
        expect(mwBadge(mwShop), "нет значка у подгруппы группы окна");
        expect(/ремонт этажа/.test(mwBadge(mwShop).title), `подсказка значка: ${mwBadge(mwShop).title}`);
        expect(!mwBadge("30000000-0000-4000-8000-000000000021"), "значок у родителя группы окна");
        return mwBadge(mwShop).title;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Окно на недоступное оператору устройство не видно: ни полосы, ни значка (ТЗ-21, §5)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup({ operatorRoles: ["Оператор ТЦ"] });
        await wait(100);
        const w = await mwCreate({ sourceGroupGuid: mwFloor, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        expect(w.status === 201, `окно: ${w.status}`);
        const cur = await stand.raw("GET", "/operator/maintenance-windows/current");
        expect(cur.status === 200 && cur.body.windows.length === 0, `идущие окна оператору ТЦ: ${JSON.stringify(cur.body)}`);
        await wait(500);
        expect(!mwShown() && !$("groupsList").querySelector(".tree-maint"), "окно чужого объекта видно");
        return "не видно";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Окно работ: правило «окно только при победителе» и режим — определения машины (ТЗ-21, ревью I-1)", async () => {
      const W = window.IM_WORKFLOW;
      const d = W.cel.definitions;
      expect(W.intake.windows === "windowsAfterWinners" && d.windowsAfterWinners && /windowsFor/.test(d.windowsAfterWinners.expr), "нет windowsAfterWinners в intake.windows");
      expect(W.intake.outcome === "maintenanceOutcome" && d.maintenanceOutcome && /maintenance\.mode/.test(d.maintenanceOutcome.expr), "режим окна — не определение машины");
      return "windowsAfterWinners, maintenanceOutcome";
    });

    await step("Окно работ: начало в прошлом — отказ STARTS_IN_PAST; у будущего начало переносится только в будущее (ТЗ-21, ревью I-2)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup();
        const past = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now - 10 * 60000), endsAt: mwIso(now + mwHour) });
        expect(past.status === 422 && past.body.code === "MAINTENANCE_WINDOW_STARTS_IN_PAST", `начало 10 мин назад: ${past.status} ${past.body && past.body.code}`);
        const skew = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now - 2 * 60000), endsAt: mwIso(now + mwHour) });
        expect(skew.status === 201, `начало 2 мин назад (допуск часов): ${skew.status}`);
        const fut = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now + mwHour), endsAt: mwIso(now + 2 * mwHour) });
        const back = await stand.raw("PUT", `/operator/maintenance-windows/${encodeURIComponent(fut.body.id)}`, Object.assign({}, fut.body, { startsAt: mwIso(now - 3 * mwHour) }));
        expect(back.status === 422 && back.body.code === "MAINTENANCE_WINDOW_STARTS_IN_PAST", `перенос начала будущего в прошлое: ${back.status}`);
        return "прошлое — отказ, допуск 5 мин";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Серия с повтором идёт с начала первого интервала до конца серии, и в промежутках: дни не меняются, удалить нельзя (ТЗ-21, ревью I-3)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup();
        const hm = (ms) => new Date(ms).toISOString().slice(11, 16);
        // Интервал — ближайшие 10 минут каждый день; создали за минуту до него: серия впереди
        const rec = { days: [1, 2, 3, 4, 5, 6, 7], startTime: hm(now + 60000), endTime: hm(now + 11 * 60000) };
        const w = await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + 10 * 24 * mwHour), recurrence: rec });
        expect(w.status === 201 && w.body.status === "planned", `до первого интервала: ${w.status} ${w.body.status}`);
        await stand.raw("POST", "/test/clock", { advanceSec: 3 * 3600 });
        const id = encodeURIComponent(w.body.id);
        const cur = (await stand.raw("GET", "/operator/maintenance-windows")).body.find((x) => x.id === w.body.id);
        expect(cur.status === "active", `в промежутке между интервалами: ${cur.status}`);
        const days = await stand.raw("PUT", `/operator/maintenance-windows/${id}`, Object.assign({}, cur, { recurrence: Object.assign({}, rec, { days: [1] }) }));
        expect(days.status === 409 && days.body.code === "MAINTENANCE_WINDOW_ACTIVE", `смена дней идущей серии: ${days.status}`);
        const del = await stand.raw("DELETE", `/operator/maintenance-windows/${id}`);
        expect(del.status === 409, `удаление идущей серии: ${del.status}`);
        return "серия идёт и между интервалами";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Окно без timeZone считается в UTC (ТЗ-21, ревью I-4а)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup();
        const w = await stand.raw("POST", "/operator/maintenance-windows", { deviceGuid: mwSmoke, startsAt: mwIso(now + mwHour), endsAt: mwIso(now + 2 * mwHour), description: "без пояса" });
        expect(w.status === 201 && w.body.timeZone === "UTC", `пояс: ${w.status} ${w.body.timeZone}`);
        return w.body.timeZone;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Форма закрытия: поле окна работ скрыто, если пересекающихся окон нет (ТЗ-21, ревью I-4б)", async () => {
      const f = window.IM_WORKFLOW.forms.find((x) => x.id === "close").fields.find((x) => x.name === "maintenanceWindowId");
      expect(f && /inMaintenance\(incident\)/.test(f.visibleExpr), `visibleExpr: ${f && f.visibleExpr}`);
      return f.visibleExpr;
    });

    await step("Повтор события, уже давшего инцидент, при suppress идёт в прежний инцидент; итог приёма хранится с событием (ТЗ-21, ревью I-4в, I-4г)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      try {
        const now = await mwSetup();
        const guid = "e0000000-0000-4000-8000-000000002101";
        const first = await stand.raw("POST", "/test/events", Object.assign(mwEvent(20), { eventGuid: guid }));
        expect(first.body.created >= 1, "первая доставка не дала инцидент");
        await mwCreate({ deviceGuid: mwSmoke, startsAt: mwIso(now), endsAt: mwIso(now + mwHour) });
        const again = await stand.raw("POST", "/test/events", Object.assign(mwEvent(20), { eventGuid: guid }));
        expect(again.body.created === 0 && again.body.maintenance === null && again.body.incidents.map((x) => x.guid).join() === first.body.incidents.map((x) => x.guid).join(), `повтор: ${JSON.stringify(again.body.maintenance)} ${again.body.incidents.length}`);
        const sc = window.IM_OPENAPI.components.schemas.EventExplanation.properties.maintenance;
        expect(/при приёме/.test(sc.description), "контракт: итог окна в объяснении — не на момент приёма");
        return "повтор — в прежний инцидент";
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Настройки: вкладка «Плановые работы» — режим и список окон набора (ТЗ-21)", async () => {
      const tab = window.IM_WORKFLOW.adminSettings.tabs.find((x) => x.id === "maintenance");
      expect(tab, "нет вкладки maintenance");
      try {
        await click($("adminBtn"));
        await wait(200);
        await click(document.querySelector('[data-admin-tab="maintenance"]'));
        await wait(100);
        const text = $("adminTable").textContent;
        const first = window.IM_FIXTURE.maintenanceWindows[0];
        expect(text.includes(first.description), "в таблице нет окна набора");
        return text.slice(0, 80);
      } finally {
        if (!$("modalAdmin").hidden) await click(document.querySelector('[data-close="modalAdmin"]'));
      }
    });

    await step("Ложная тревога у основного — уведомление адресату соседа привязанного (§6.1, §11.4, решение 2026-10-29)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Пожар INC-1847 привязан к INC-1851; его сосед медпункт INC-1853 — у меня в работе. INC-1851 закрывает Петрова «Ложной тревогой»
      await standReset({ fixture: "demo", workflowPatch: { limits: { maxActive: null } } });
      await wait(100);
      let toast = null;
      try {
        const [a, b, c] = ["INC-1851", "INC-1847", "INC-1853"].map(guidOf);
        const merged = await stand.raw("POST", "/operator/incidents/merge", { incidentGuids: [a, b] });
        expect(merged.status === 200, `INC-1851 и INC-1847 не взяты одним инцидентом: ${merged.status}`);
        expect((await standAct(c, "claim", {}, "queue")).status === 200, "INC-1853 не взят");
        expect((await standAct(a, "transfer", { targetId: "petrova", comment: "тест" })).status === 200, "INC-1851 не передан Петровой");
        expect((await petrovaAct(a, "accept")).status === 200, "Петрова не приняла INC-1851");
        const closed = await petrovaAct(a, "close", { resultId: "false_alarm", causeId: "animal", comment: "тест" });
        expect(closed.status === 200, `Петрова не закрыла INC-1851: ${closed.status}`);
        await wait(100);
        const label = window.IM_STRINGS.ru["workflow.catalog.close_result.false_alarm"];
        toast = noticeWith(new RegExp(`INC-1847 того же события закрыт: ${label}`));
        expect(toast, `нет уведомления о закрытом привязанном соседе: ${noticeList()}`);
      } finally {
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
      return toast.textContent;
    });

    await step("Массовый сбой на выборке без основного: основной — тот, что можно закрыть (§11.1, решение 2026-10-29)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Пожар INC-1847 (100) — у Петровой в работе, медпункт INC-1853 (75) — мой, отложен: закроется медпункт, пожар пропущен
      const incidents = JSON.parse(JSON.stringify(window.IM_FIXTURE.incidents));
      incidents.find((i) => i.number === "INC-1853").priority = 75;
      await standReset({ fixture: "demo", fixturePatch: { incidents }, workflowPatch: { limits: { maxActive: null } } });
      await wait(100);
      const state = async (number) => (await stand.raw("GET", `/operator/incidents/${encodeURIComponent(guidOf(number))}`)).body.state;
      async function tick(number) {
        const first = $("eventsPager").querySelector('[data-page="1"]');
        if (first && !first.disabled) await click(first);
        const row = await rowOnPages(guidOf(number));
        expect(row, `в «Открытых» нет ${number}`);
        await click(row.querySelector(`[data-check="${guidOf(number)}"]`));
      }
      let text = "";
      try {
        expect((await petrovaAct(guidOf("INC-1847"), "claim")).status === 200, "Петрова не взяла INC-1847");
        expect((await standAct(guidOf("INC-1853"), "claim", {}, "queue")).status === 200, "INC-1853 не взят");
        expect((await standAct(guidOf("INC-1853"), "hold", { reasonId: "third_party", comment: "тест" })).status === 200, "INC-1853 не отложен");
        if (mode() !== "queue") await click($("backToQueue"));
        await setFilter("open");
        for (const number of ["INC-1847", "INC-1853"]) await tick(number);
        const btn = $("selBar").querySelector('[data-sel-do="close"]');
        expect(btn && !off(btn), `«Закрыть без обработки» на панели выборки недоступна: ${btn ? btn.title : "нет кнопки"}`);
        await click(btn);
        expect(!$("modalDialog").hidden, "форма закрытия выборки не открылась");
        const note = $("dialogNote").textContent;
        expect(/1 из 2/.test(note), `пояснение формы: «${note}»`);
        await setField("resultId", "mass");
        await setField("causeId", window.IM_WORKFLOW.reasonCatalogs.mass_fault.items[0].id);
        await confirmDialog(NOTE);
        await wait(200);
        text = ($("toasts").lastElementChild || {}).textContent || "";
        expect(/Не закрыты: 1 — другой сценарий: INC-1847/.test(text), `уведомление: «${text}»`);
        const states = [await state("INC-1847"), await state("INC-1853")];
        expect(states.join(",") === "in_progress,closed", `состояния INC-1847, INC-1853: ${states.join(", ")}`);
      } finally {
        if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
        if (!$("clearSelectionBtn").disabled) await click($("clearSelectionBtn"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
      return text;
    });

    await step("Свой выход с инцидентами в работе и открытой карточкой — ни одного «карточка только для просмотра» (BUG-105)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Два инцидента в работе: лимит активных самопроверки (1) снят
      await standReset({ fixture: "demo", workflowPatch: { limits: { maxActive: null } } });
      await wait(100);
      try {
        await claimFromQueue(() => true);
        await claimFromQueue(() => true);
        expect(mode() === "work", "карточка взятого инцидента не открылась");
        await click($("signOutBtn"));
        await confirmDialog();
        await wait(100);
        expect(!$("signedOutBanner").hidden, "выход не выполнился");
        const extra = noticeWith(/карточка только для просмотра/) || toastWith(/карточка только для просмотра/);
        expect(!extra, `после своего выхода: «${extra && extra.textContent}»`);
        expect(!document.querySelector("[data-evicted]"), "после своего выхода — полоса «только просмотр»");
      } finally {
        if (!$("signedOutBanner").hidden) await click($("signInBtn"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Правила пояснения с номером основного — с текстом на случай скрытого основного (cardNotes, hiddenTextKey, §5)", async () => {
      const ru = window.IM_STRINGS.ru;
      const rules = window.IM_WORKFLOW.cardNotes.rules.filter((n) => String(ru[n.textKey]).includes("{primaryNumber}"));
      expect(rules.length, "нет ни одного правила с {primaryNumber}");
      rules.forEach((n) => {
        expect(n.hiddenTextKey, `у правила ${n.textKey} нет hiddenTextKey`);
        expect(ru[n.hiddenTextKey] !== undefined, `ключа ${n.hiddenTextKey} нет в каталоге`);
        expect(!ru[n.hiddenTextKey].includes("{primaryNumber}"), `в тексте ${n.hiddenTextKey} есть номер основного`);
      });
      return `${rules.length} правил`;
    });

    await step("На перерыве пояснение карточки адресованного мне не зовёт «примите» — только просмотр (cardNotes, BUG-97)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Свежий набор: INC-1843 ждёт моего принятия
      await standReset({ fixture: "demo" });
      await wait(100);
      if (mode() === "work") await click($("backToQueue"));
      await click($("breakBtn"));
      await confirmDialog();
      let note = "";
      try {
        await setFilter("inbox");
        const row = [...$("eventsList").querySelectorAll(".event")].find((r) => button(r, "view") || button(r, "open_card"));
        expect(row, "на перерыве в «Мне на принятие» нечего открыть");
        await click(button(row, "view") || button(row, "open_card"));
        expect(mode() === "work", "карточка не открылась");
        note = (root().querySelector(".work-note") || {}).textContent || "";
        expect(!/Примите/.test(note), `пояснение зовёт действовать: «${note}»`);
        expect(/перерыв/i.test(note), `пояснение не про перерыв: «${note}»`);
      } finally {
        if (mode() === "work") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
      return note;
    });

    await step("Отсчёт — по времени сервера, а не пульта: часы стенда ушли вперёд — в строке остаток, как у сервера (BUG-103)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
      // Часы стенда — на 40 с вперёд от пульта: без поправки отсчёт был бы на 40 с больше
      await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
      await stand.raw("POST", "/test/clock", { advanceSec: 40 });
      await wait(100);
      await setFilter("open");
      const sec = (s) => s.split(":").reduce((m, x) => m * 60 + Number(x), 0);
      const row = [...$("eventsList").querySelectorAll(".event")].find((r) => {
        const t = r.querySelector("[data-due] .sla-t");
        return t && sec(t.textContent) > 10;
      });
      expect(row, "нет строки с идущим отсчётом");
      const el = row.querySelector("[data-due]");
      const shown = sec(el.querySelector(".sla-t").textContent);
      // Таймер сервера — тот, чей срок у отсчёта: в строке их может быть два (закрытие и удержание)
      const inc = await stand.get(`/operator/incidents/${encodeURIComponent(row.dataset.id)}`);
      const server = [inc.timer, inc.holdTimer].find((x) => x && Date.parse(x.dueAt) === Number(el.dataset.due));
      expect(server, "у сервера нет таймера с таким сроком");
      const left = Math.floor(server.remainingMs / 1000);
      expect(Math.abs(shown - left) <= 3, `в строке ${shown} с, у сервера ${left} с`);
      return `в строке ${shown} с, у сервера ${left} с`;
    });

    await step("Устаревшая выборка: отмеченные ушли по эскалации — массовая передача их не уводит и называет причину (expected, BUG-84, RULE-142)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      await standReset({ fixture: "demo" });
      await wait(100);
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
      let text = "";
      try {
        const rows = [...$("eventsList").querySelectorAll(".event")].filter((r) => r.querySelector('[data-do="claim"]') && r.querySelector("[data-check]")).slice(0, 2);
        expect(rows.length === 2, "нет двух новых для выборки");
        const ids = rows.map((r) => r.dataset.id);
        // Строки после сброса стенда перерисовываются: отмечать — по свежей строке
        for (const g of ids) await click($("eventsList").querySelector(`[data-check="${g}"]`));
        await wait(200);
        expect(ids.every((g) => $("eventsList").querySelector(`[data-check="${g}"]`).checked), "отмечены не оба");
        // После отметки — автоэскалация: инциденты изменились
        for (let i = 0; i < 4; i++) {
          await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
          await stand.raw("POST", "/test/clock", { advanceSec: 240 });
        }
        await wait(100);
        const before = await Promise.all(ids.map((g) => stand.get(`/operator/incidents/${encodeURIComponent(g)}`)));
        await click($("selBar").querySelector('[data-sel-do="transfer"]'));
        expect(!$("modalDialog").hidden, "форма передачи выборки не открылась");
        await click($("dialogFields").querySelector('[data-target-input="targetId"]'));
        const pick = $("dialogFields").querySelector("[data-target-pick]");
        expect(pick, "в форме нет адресатов");
        await click(pick);
        await confirmDialog("тест");
        await wait(200);
        text = ($("toasts").lastElementChild || {}).textContent || "";
        const after0 = await Promise.all(ids.map((g) => stand.get(`/operator/incidents/${encodeURIComponent(g)}`)));
        expect(/Инцидент уже/.test(text), `уведомление: «${text}»; до: ${before.map((c) => c.owner && c.owner.id + "/" + c.version + "/" + c.state)}; после: ${after0.map((c) => c.owner && c.owner.id + "/" + c.version + "/" + c.state)}`);
        const after = await Promise.all(ids.map((g) => stand.get(`/operator/incidents/${encodeURIComponent(g)}`)));
        expect(after.every((c, i) => JSON.stringify(c.owner) === JSON.stringify(before[i].owner) && c.transferCount === before[i].transferCount), "изменённые после отметки переданы");
      } finally {
        if (!$("modalDialog").hidden) await click(document.querySelector('[data-close="modalDialog"]'));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
      return text;
    });

    await step("Выборка после изменения: отметил заново — действие проходит; после отказа «Инцидент уже …» — повтор проходит (BUG-106, RULE-142)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const card = (g) => stand.get(`/operator/incidents/${encodeURIComponent(g)}`);
      const tick = async (ids) => {
        for (const g of ids) await click($("eventsList").querySelector(`[data-check="${g}"]`));
        await wait(200);
        expect(ids.every((g) => $("eventsList").querySelector(`[data-check="${g}"]`).checked), "отмечены не оба");
      };
      // Автоэскалация: инциденты меняются (новая версия)
      const escalate = async () => {
        for (let i = 0; i < 4; i++) {
          await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
          await stand.raw("POST", "/test/clock", { advanceSec: 240 });
        }
        await wait(100);
      };
      const transfer = async () => {
        const before = new Set($("toasts").children);
        await click($("selBar").querySelector('[data-sel-do="transfer"]'));
        expect(!$("modalDialog").hidden, "форма передачи выборки не открылась");
        await click($("dialogFields").querySelector('[data-target-input="targetId"]'));
        const pick = $("dialogFields").querySelector("[data-target-pick]");
        expect(pick, "в форме нет адресатов");
        await click(pick);
        await confirmDialog("тест");
        await wait(200);
        return [...$("toasts").children].filter((x) => !before.has(x)).map((x) => x.textContent).join(" | ");
      };
      const out = [];
      try {
        for (const part of ["отметил заново", "повтор после отказа"]) {
          await standReset({ fixture: "demo" });
          await wait(100);
          if (mode() === "work") await click($("backToQueue"));
          await setFilter("open");
          const rows = [...$("eventsList").querySelectorAll(".event")].filter((r) => r.querySelector('[data-do="claim"]') && r.querySelector("[data-check]")).slice(0, 2);
          expect(rows.length === 2, "нет двух новых для выборки");
          const ids = rows.map((r) => r.dataset.id);
          await tick(ids);
          if (part === "отметил заново") {
            // Другой список и обратно — отметки сняты; инциденты изменились; отмечены снова
            await setFilter("all");
            await setFilter("open");
            expect(ids.every((g) => !$("eventsList").querySelector(`[data-check="${g}"]`).checked), "смена фильтра не сняла отметки");
            await escalate();
            await tick(ids);
          } else {
            await escalate();
            const first = await transfer();
            expect(/Инцидент уже/.test(first), `первое нажатие: «${first}»`);
          }
          const before = await Promise.all(ids.map(card));
          const text = await transfer();
          const after = await Promise.all(ids.map(card));
          expect(!/Инцидент уже/.test(text), `${part}: «${text}»`);
          expect(after.every((c, i) => c.transferCount === before[i].transferCount + 1), `${part}: переданы не оба — ${text}`);
          out.push(`${part}: ${text}`);
        }
      } finally {
        if (!$("modalDialog").hidden) await click(document.querySelector('[data-close="modalDialog"]'));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
      return out.join("; ");
    });

    await step("Опоздал (§14.1, §22.6, RULE-142): коллега взял, пока строка не обновилась, — «Уже взял <имя>», по потоку «Взять» гаснет; чужой комментарий при закрытии — «Пришло новое событие — проверьте»", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      await standReset({ fixture: "demo" });
      await wait(100);
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
      // Чтения интерфейса задержаны: событие потока пришло, а список и карточка ещё прежние — оператор жмёт по ним
      const get = stand.get;
      let release = () => {};
      const hold = () => {
        const gate = new Promise((resolve) => (release = resolve));
        stand.get = (path, params) => gate.then(() => get(path, params));
      };
      const free = async () => {
        stand.get = get;
        release();
        await wait(100);
      };
      const lastToast = () => ($("toasts").lastElementChild || {}).textContent || "";
      const petrova = (g, tr, formValues) => stand.raw("POST", `/test/operators/petrova/incidents/${encodeURIComponent(g)}/transitions/${tr}`, { formValues: formValues || {}, surface: "card" });
      const out = [];
      try {
        // У Петровой лимит активных — один, и он занят INC-1846: она возвращает его в очередь
        const busy = (window.IM_FIXTURE.incidents.find((i) => i.number === "INC-1846") || {}).guid;
        const back = await petrova(busy, "release", { comment: "back" });
        expect(back.status === 200, `Петрова не вернула INC-1846: ${back.status}`);
        await wait(100);
        const rows = [...$("eventsList").querySelectorAll(".event")].filter((r) => button(r, "claim")).map((r) => r.dataset.id);
        hold();
        // Первый новый, который Петрова может взять (доступ к объекту, лимит), второй — для закрытия
        let g = null;
        let refused = "";
        for (const id of rows) {
          const r = await petrova(id, "claim");
          if (r.status === 200) {
            g = id;
            break;
          }
          refused = `${r.status} ${(r.body && (r.body.message || r.body.code)) || ""}`;
        }
        const g2 = rows.find((id) => id !== g);
        expect(g && g2, `Петрова не взяла ни одного из ${rows.length}: ${refused}`);
        await wait(100);
        const b = button($("eventsList"), "claim", g);
        expect(b, "строка обновилась раньше нажатия");
        await click(b);
        const late = lastToast();
        expect(/Уже взял Петрова/.test(late), `опоздал: «${late}»`);
        await free();
        expect(!button($("eventsList"), "claim", g), "после потока у взятого коллегой осталась «Взять»");
        out.push(late);
        // Закрытие: после показа карточки Петрова оставила комментарий — закрытие останавливается
        await click(button($("eventsList"), "claim", g2));
        expect(mode() === "work", "карточка не открылась");
        hold();
        expect((await petrova(g2, "comment", { comment: "check camera 3" })).status === 200, "Петрова не оставила комментарий");
        await wait(100);
        await click(button(root(), "close"));
        await setField("resultId", "false_alarm");
        await setField("causeId", "animal");
        await confirmDialog(NOTE);
        const news = lastToast();
        expect(/Пришло новое событие/.test(news), `закрытие при чужом комментарии: «${news}»`);
        await free();
        expect((await get(`/operator/incidents/${encodeURIComponent(g2)}`)).state === "in_progress", "закрылся, не видя комментария");
        out.push(news);
      } finally {
        if (stand.get !== get) await free();
        if (!$("modalDialog").hidden) await click(document.querySelector('[data-close="modalDialog"]'));
        if (mode() === "work") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
      return out.join("; ");
    });

    await step("Опоздал с ответом на шаг (§14.1, §22.6, RULE-142): коллега перехватил, пока карточка не обновилась, — мягкое «Уже взял <имя>», а не ошибка", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      await standReset({ fixture: "demo" });
      await wait(100);
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
      const get = stand.get;
      let release = () => {};
      const hold = () => {
        const gate = new Promise((resolve) => (release = resolve));
        stand.get = (path, params) => gate.then(() => get(path, params));
      };
      const free = async () => {
        stand.get = get;
        release();
        await wait(100);
      };
      const lastToast = () => $("toasts").lastElementChild;
      const petrova = (g, tr, formValues) => stand.raw("POST", `/test/operators/petrova/incidents/${encodeURIComponent(g)}/transitions/${tr}`, { formValues: formValues || {}, surface: "card" });
      try {
        // Лимит активных Петровой занят INC-1846 — она возвращает его в очередь, чтобы перехватить
        const busy = (window.IM_FIXTURE.incidents.find((i) => i.number === "INC-1846") || {}).guid;
        expect((await petrova(busy, "release", { comment: "back" })).status === 200, "Петрова не вернула INC-1846");
        await wait(100);
        // Беру новый со сценарием: карточка на шаге, «Далее» доступна после ответа
        let g = null;
        for (const b of [...$("eventsList").querySelectorAll('[data-do="claim"]')].filter((x) => !off(x))) {
          const id = b.dataset.ev;
          await click(button($("eventsList"), "claim", id));
          await answerCurrentStep();
          if (mode() === "work" && $("stepNext") && !off($("stepNext"))) {
            g = id;
            break;
          }
          if (mode() === "work") await click($("backToQueue"));
        }
        expect(g, "не нашлось нового инцидента со сценарием, где доступна «Далее»");
        hold();
        const took = await petrova(g, "takeover");
        expect(took.status === 200, `Петрова не перехватила: ${took.status} ${(took.body && (took.body.message || took.body.code)) || ""}`);
        await wait(100);
        expect($("stepNext") && !off($("stepNext")), "карточка обновилась раньше нажатия");
        await click($("stepNext"));
        const late = lastToast();
        const text = (late && late.textContent) || "";
        expect(/Уже взял Петрова/.test(text), `опоздал с ответом: «${text}»`);
        expect(late.dataset.kind === "late", `уведомление «${text}» — ${late.dataset.kind}, а не мягкое «опоздал»`);
        return text;
      } finally {
        if (stand.get !== get) await free();
        if (mode() === "work") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("«Передать», когда передать некому, — бледная, по нажатию причина (BUG-85)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Всем коллегам — «Оператор ТЦ», в группах никого: у инцидента вне ТЦ принять некому
      const people = JSON.parse(JSON.stringify(window.IM_FIXTURE.people));
      people.operators.filter((o) => o.id !== window.IM_FIXTURE.operator).forEach((o) => (o.roles = ["Оператор ТЦ"]));
      people.dutyGroups.forEach((g) => (g.members = (g.members || []).filter((m) => m === window.IM_FIXTURE.operator)));
      await standReset({ fixture: "demo", fixturePatch: { people } });
      await wait(100);
      let why = "";
      try {
        if (mode() === "work") await click($("backToQueue"));
        await setFilter("open");
        const guid = (window.IM_FIXTURE.incidents.find((i) => i.number === "INC-1838") || {}).guid;
        const b = $("eventsList").querySelector(`[data-do="transfer"][data-ev="${guid}"]`);
        expect(b, "у INC-1838 нет кнопки «Передать»");
        expect(off(b) && !b.disabled, "«Передать» не бледная или не в фокусе");
        why = b.title;
        expect(/Передать некому/.test(why), `причина: «${why}»`);
        // Причина — среди уведомлений после нажатия, не обязательно последней: такт стенда раз в секунду может
        // следом вернуть в очередь чужие инциденты без доступа, и их оповещения придут позже причины
        const before = new Set($("toasts").children);
        const attached = b.isConnected;
        await click(b);
        expect($("modalDialog").hidden, "форма с пустым списком открылась");
        const added = [...$("toasts").children].filter((x) => !before.has(x));
        const shown = [...$("toasts").children].map((x) => `«${x.textContent}»`).join(", ") || "нет";
        expect(
          added.some((x) => x.textContent === why),
          `по нажатию — не причина; кнопка на странице: ${attached ? "да" : "нет"}, новых уведомлений: ${added.length}, уведомления: ${shown}`
        );
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
      }
      return why;
    });

    await step("Настройки: адресат уровня и получатель оповещений — вид и имя, не номер (BUG-124)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const me = (await stand.get("/operator/session")).operator;
      const other = (await stand.get("/operator/transfer-targets")).find((x) => x.kind !== "duty_group" && x.id !== me.guid);
      const group = (await stand.get("/operator/admin/duty-groups"))[0];
      const esc = window.IM_WORKFLOW.escalation;
      const levels = [
        { level: 1, targetKind: "user", target: me.guid, reactionSec: 120 },
        { level: 2, targetKind: "user", target: other.id, reactionSec: 90 },
        { level: 3, targetKind: "group", target: group.id, reactionSec: 90 },
        { level: 4, targetKind: "user", target: "gone-7", reactionSec: 90 },
      ];
      try {
        await standReset({ fixture: "demo", workflowPatch: { escalation: Object.assign({}, esc, { levels, maxLevel: 4 }), alerts: { targetKind: "user", target: me.guid } } });
        await wait(100);
        await click($("adminBtn"));
        await click($("adminTabs").querySelector('[data-admin-tab="timing"]'));
        await wait(200);
        const cell = (re) => {
          const row = [...$("adminTable").querySelectorAll("tr")].find((r) => r.cells.length === 2 && re.test(r.cells[0].textContent));
          return row ? row.cells[1].innerText : "";
        };
        const shown = cell(/^Уровни/);
        for (const want of [`пользователь ${me.name}`, `пользователь ${other.name}`, `группа ${group.name}`, "удалённый пользователь (gone-7)"])
          expect(shown.includes(want), `в «Уровнях» нет «${want}»: «${shown}»`);
        const alerts = cell(/^Получатель оповещений/).trim();
        expect(alerts === `пользователь ${me.name}`, `получатель оповещений: «${alerts}»`);
        // Списки групп и людей поста не пришли — ни группа, ни человек не «удалённые», а «группа (id)», «пользователь (id)»:
        // запросы интерфейса отказывают
        await click(document.querySelector('[data-close="modalAdmin"]'));
        const get = stand.get;
        const refused = ["/operator/admin/duty-groups", "/operator/admin/people"];
        stand.get = (path, ...rest) => (refused.includes(path) ? Promise.reject(new Error("отказ")) : get.call(stand, path, ...rest));
        try {
          await click($("adminBtn"));
          await click($("adminTabs").querySelector('[data-admin-tab="timing"]'));
          await wait(200);
        } finally {
          stand.get = get;
        }
        const blind = cell(/^Уровни/);
        expect(blind.includes(`группа (${group.id})`) && !/удалённая группа/.test(blind), `список групп не пришёл: «${blind}»`);
        expect(blind.includes("пользователь (gone-7)") && !/удалённый пользователь/.test(blind), `список людей не пришёл: «${blind}»`);
      } finally {
        if (!$("modalAdmin").hidden) await click(document.querySelector('[data-close="modalAdmin"]'));
        await standReset({ fixture: "demo" });
        await wait(100);
      }
    });

    await step("Порядок очереди: список — по умолчанию есть, администратор может запретить, выбор сохраняется (§7, BUG-34)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const select = $("queueSortSelect");
      expect(!select.hidden, "по умолчанию оператор может менять порядок — списка нет");
      try {
        // Администратор запретил: стенд подменяет схему, клиент перечитывает её по workflow.schema_published
        await standReset({ fixture: "demo", workflowPatch: { queueSort: { operatorMayChange: false } } });
        await wait(100);
        expect(select.hidden, "администратор запретил менять порядок — список остался");
        await standReset({ fixture: "demo" });
        await wait(100);
        expect(!select.hidden, "разрешили менять порядок — список не появился: схема не перечитана");
        const options = [...select.options].map((o) => o.value);
        expect(JSON.stringify(options) === JSON.stringify(window.IM_WORKFLOW.queueSort.options), `варианты не из схемы: ${options.join(", ")}`);
        const other = options.find((v) => v !== select.value);
        // Очередь после выбора — заново с сервера: считаем запросы интерфейса к очереди
        const get = stand.get;
        let asked = 0;
        stand.get = (path, ...rest) => ((asked += path === "/operator/incidents"), get.call(stand, path, ...rest));
        try {
          select.value = other;
          select.dispatchEvent(new Event("change"));
          await wait(100);
        } finally {
          stand.get = get;
        }
        expect((await stand.get("/operator/session")).preferences.queueSort === other, "выбор не сохранён в настройках оператора");
        expect(asked > 0, "после выбора очередь не перечитана");
        return `порядков: ${options.length}, выбран «${select.selectedOptions[0].textContent}»`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(100);
        expect(!select.hidden, "вернули исходную схему — список пропал");
      }
    });

    await step("Плашка сценария в очереди — у каждого события со сценарием, название без счёта шагов; нет названия — «Без названия» (§14.5)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const byGuid = Object.fromEntries((await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.map((e) => [e.guid, e]));
      await setFilter("all");
      const seen = [];
      for (let page = 1; page <= 20; page++) {
        const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
        if (page > 1 && (!nav || nav.disabled)) break;
        if (nav && page > 1) await click(nav);
        $("eventsList").querySelectorAll(".event").forEach((row) => {
          const chip = row.querySelector(".event-prog");
          const inc = byGuid[row.dataset.id];
          // Плашка — у каждого события со сценарием, есть ли уже ответы или нет
          if (inc.scenarioProgress.total) seen.push([chip ? chip.textContent.trim() : "(нет плашки)", inc.scenarioTitle || "Без названия"]);
        });
      }
      await setFilter("open");
      expect(seen.length, "в очереди нет событий со сценарием — плашку не проверить");
      const wrong = seen.filter(([shown, title]) => shown !== title);
      expect(!wrong.length, `плашка не название сценария: ${wrong.map(([a, b]) => `«${a}» вместо «${b}»`).join(", ")}`);
      // Нет названия — «Без названия»: стенд убирает его у сценария пожара (в Merge Patch null удаляет поле)
      if (mode() !== "queue") await click($("backToQueue"));
      const fireGuid = window.IM_FIXTURE.scenarios.keys.fire;
      const fireTitle = window.IM_FIXTURE.scenarios.rows.find((r) => r.guid === fireGuid).name;
      const rows = window.IM_FIXTURE.scenarios.rows.map((r) => (r.guid === fireGuid ? Object.assign({}, r, { name: null }) : r));
      await standReset({ fixture: "demo", fixturePatch: { scenarios: { rows } } });
      // Смена фильтра перечитывает очередь с сервера
      await setFilter("all");
      let untitled = 0;
      try {
        for (let page = 1; page <= 20; page++) {
          const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
          if (page > 1 && (!nav || nav.disabled)) break;
          if (nav && page > 1) await click(nav);
          $("eventsList").querySelectorAll(".event").forEach((row) => {
            const chip = row.querySelector(".event-prog");
            // Инциденты сценария пожара — по названию до правки; у соседа INC-1853 тип «пожар», а сценарий медпункта (ARCH-15)
            const before = byGuid[row.dataset.id];
            if (chip && before && before.scenarioTitle === fireTitle) untitled += chip.textContent.trim() === "Без названия" ? 1 : -1000;
          });
        }
      } finally {
        await standReset({ fixture: "demo" });
        await setFilter("open");
      }
      expect(untitled > 0, "у сценария без названия плашка не «Без названия»");
      return `плашек: ${seen.length}, например «${seen[0][0]}»; без названия — «Без названия»`;
    });

    await step("Одно слово — одно число: у «Очередь» и в нижнем меню — по фильтру, в строке состояния — «Открытых» (BUG-100)", async () => {
      if (mode() !== "queue") await click($("backToQueue"));
      await setFilter("mine");
      try {
        const head = $("eventsCount").textContent;
        const nav = $("navQueueCount").textContent;
        const status = $("statusQueue").textContent;
        expect(head === nav, `у «Очередь» ${head}, в нижнем меню ${nav}`);
        expect(/^Открытых: \d+/.test(status) && !/В очереди/.test(status), `строка состояния: «${status}»`);
        return `«Мои»: ${head}; ${status}`;
      } finally {
        await setFilter("open");
      }
    });

    await step("Лимиты без ограничения: строка состояния без «из N», в настройках — «без ограничения», выборка не обрезается (§10.2, §11, RULE-69)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      if (mode() !== "queue") await click($("backToQueue"));
      // Стенд снимает лимиты — клиент перечитывает схему по workflow.schema_published
      await standReset({ fixture: "demo", workflowPatch: { limits: { maxActive: null, maxOnHold: null, maxBulk: null } } });
      await wait(400);
      try {
        const status = $("statusQueue").textContent;
        expect(/у меня: \d+,/.test(status), `в строке состояния осталось «из N»: ${status}`);
        await click($("adminBtn"));
        await click($("adminTabs").querySelector('[data-admin-tab="operator"]'));
        await wait(200);
        // Строки раздела «Лимиты» — от его заголовка до следующего (план 77)
        const shown = [];
        for (let r = $("adminTable").querySelector('[data-admin-group="limits"]').nextElementSibling; r && !r.classList.contains("admin-group"); r = r.nextElementSibling) shown.push(r.cells[1].textContent.trim());
        await click(document.querySelector('[data-close="modalAdmin"]'));
        expect(shown.length === 3 && shown.every((v) => v === "без ограничения"), `в настройках: ${shown.join(", ")}`);
        await click($("selectAllBtn"));
        await wait(200);
        const toast = [...$("toasts").children].map((t) => t.textContent).reverse().find((t) => /Выбрано/.test(t)) || "";
        const n = Number((toast.match(/\d+/) || [0])[0]);
        expect(n > 10 && !/ из /.test(toast), `«Выбрать все» обрезано лимитом: ${toast}`);
        await click($("clearSelectionBtn"));
        return `${status}; настройки: ${shown.join(", ")}; ${toast}`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(400);
        expect(/ из /.test($("statusQueue").textContent), "лимиты вернули — «из N» не вернулось");
      }
    });

    await step("Другой справочник приоритетов — интерфейс перерисовывается без перезагрузки (§2.5, RULE-68)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const fx = JSON.parse(JSON.stringify(window.IM_FIXTURE));
      const old = fx.priorities.map((p) => p.value).sort((a, b) => b - a);
      const levels = [
        { value: 95, name: { ru: "Угроза", en: "Threat" }, color: "red" },
        { value: 80, name: { ru: "Повышенный", en: "Elevated" }, color: "red" },
        { value: 60, name: { ru: "Обычный", en: "Regular" }, color: "amber" },
        { value: 10, name: { ru: "Информация", en: "Info" }, color: "grey" },
      ];
      const remap = Object.fromEntries(old.map((v, i) => [v, levels[i].value]));
      fx.incidents.forEach((inc) => (inc.priority = remap[inc.priority]));
      const labels = () => [...$("eventsList").querySelectorAll(".event-pri")].map((el) => el.getAttribute("aria-label"));
      // Полоски — в очереди: в режиме карточки она скрыта и перерисуется при возврате
      if (mode() !== "queue") await click($("backToQueue"));
      const before = labels();
      // Справочник сменился — клиент получает reference.priorities_changed и перечитывает его
      await standReset({ fixture: "demo", fixturePatch: { priorities: levels, incidents: fx.incidents } });
      await wait(400);
      try {
        const names = levels.map((p) => `Приоритет: ${p.name.ru}`);
        const after = labels();
        expect(after.length && after.every((l) => names.includes(l)), `подписи полосок не из нового справочника: ${[...new Set(after)].join(", ")}`);
        const top = document.querySelector(".tree-ev.crit");
        expect(!top || !top.title || top.title.includes("«Угроза»"), `метка дерева не по самому срочному уровню нового справочника: ${top && top.title}`);
        return `было: ${[...new Set(before)].join(", ")}; стало: ${[...new Set(after)].join(", ")}`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(400);
        expect(labels().every((l) => before.includes(l)), "справочник вернули — подписи не вернулись");
      }
    });

    await step("Дерево групп: в группе все её устройства, счётчик — только у устройства-источника открытых инцидентов; камеры рядом без тревоги; у группы одно число — открытые инциденты; без них — приглушено (§19.1, RULE-85, RULE-86, BUG-64, RULE-92)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      if (mode() !== "queue") await click($("backToQueue"));
      // Конференц-зал: пожар от датчика дыма, камеры зала — рядом (INC-1838)
      const inc = window.IM_FIXTURE.incidents.find((i) => i.number === "INC-1838");
      const groupId = window.IM_FIXTURE.sourceGroups
        .flatMap(function all(g) {
          return [g].concat((g.groups || []).flatMap(all));
        })
        .find((g) => (g.devices || []).includes(inc.devices[0])).id;
      const find = (nodes) => nodes.reduce((hit, n) => hit || (n.guid === groupId ? n : find(n.children)), null);
      const node = find(await stand.get("/operator/reference/source-groups", { withCounters: "true" }));
      const li = $("groupsList").querySelector(`[data-id="${groupId}"]`);
      expect(node && li, "нет группы конференц-зала в дереве");
      const shown = [...li.querySelectorAll(':scope > ul > [data-type="device"]')];
      expect(shown.length === node.devices.length, `устройств в группе на экране ${shown.length}, у группы ${node.devices.length}`);
      node.devices.forEach((d) => {
        const el = shown.find((x) => x.dataset.id === d.guid);
        expect(el, `нет устройства «${d.name}» в группе`);
        const counter = el.querySelector(":scope > .node-content .tree-ev");
        expect(Boolean(counter) === (d.counters.open > 0), `«${d.name}»: счётчик ${counter ? counter.textContent : "нет"}, открытых ${d.counters.open}`);
      });
      const cameras = node.devices.filter((d) => inc.devices.slice(1).includes(d.guid));
      expect(cameras.length && cameras.every((d) => d.counters.open === 0), "камеры рядом с источником — с тревогой");
      // У группы одно число — открытые инциденты; без них — ничего, плашки «подгрупп / устройств» нет (BUG-64)
      const groups = (nodes) => nodes.flatMap((n) => [n].concat(groups(n.children || [])));
      expect(!$("groupsList").querySelector(".tree-badge"), "у группы снова плашка «подгрупп / устройств»");
      groups(await stand.get("/operator/reference/source-groups", { withCounters: "true" })).forEach((g) => {
        const content = $("groupsList").querySelector(`[data-id="${g.guid}"] > .node-content`);
        const numbers = [...content.children].filter((el) => !el.classList.contains("node-text") && /^\d/.test(el.textContent.trim()));
        const ok = g.counters.open > 0 ? numbers.length === 1 && numbers[0].textContent.trim() === String(g.counters.open) : numbers.length === 0;
        expect(ok, `«${g.name}»: на экране ${numbers.map((el) => el.textContent.trim()).join(" ") || "ничего"}, открытых ${g.counters.open}`);
        // Без открытых инцидентов — приглушён, путь к тревоге — нет (RULE-92)
        expect(content.parentElement.classList.contains("quiet") === !g.counters.open, `«${g.name}»: приглушён — ${content.parentElement.classList.contains("quiet")}, открытых ${g.counters.open}`);
      });
      node.devices.forEach((d) => {
        const el = shown.find((x) => x.dataset.id === d.guid);
        expect(el.classList.contains("quiet") === !d.counters.open, `«${d.name}»: приглушён — ${el.classList.contains("quiet")}, открытых ${d.counters.open}`);
      });
      // Приглушённое читается: цвет отличается от обычного, контраст не ниже 4,5:1 в обеих темах
      const original = document.documentElement.dataset.theme;
      try {
        for (const theme of ["light", "dark"]) {
          await setTheme(theme);
          const group = $("groupsList").querySelector(`[data-id="${groupId}"]`);
          const quietText = group.querySelector(":scope > ul > .tree-node.quiet > .node-content .node-text");
          const loudText = group.querySelector(":scope > .node-content .node-text");
          const r = contrast(quietText);
          expect(r >= 4.5, `${theme}: контраст приглушённого «${quietText.textContent}» — ${r.toFixed(2)}`);
          expect(getComputedStyle(quietText).color !== getComputedStyle(loudText).color, `${theme}: приглушённое того же цвета, что путь к тревоге`);
        }
      } finally {
        await setTheme(original);
      }
      return `устройств в группе: ${node.devices.length}, со счётчиком: ${node.devices.filter((d) => d.counters.open > 0).map((d) => d.name).join(", ")}`;
    });

    await step("Поиск в дереве без результатов — «Ничего не найдено», и когда группы раскрыты (BUG-92)", async () => {
      if (mode() !== "queue") await click($("backToQueue"));
      // Раскрыть все группы: их дети класса hidden не получают — считать надо то, что на экране
      if ($("groupsCollapseAll").textContent.includes("unfold_more")) await click($("groupsCollapseAll"));
      const search = $("groupSearch");
      search.value = "щщщщ";
      search.dispatchEvent(new Event("input", { bubbles: true }));
      await wait();
      try {
        const shown = [...$("groupsList").querySelectorAll(".tree-node")].filter((n) => n.dataset.id !== "all" && n.getClientRects().length > 0);
        expect(!shown.length, `на экране узлов: ${shown.length}`);
        expect(!$("groupsEmpty").hidden, "«Ничего не найдено» не показано");
      } finally {
        search.value = "";
        search.dispatchEvent(new Event("input", { bubbles: true }));
        await wait();
      }
      return $("groupsEmpty").textContent.trim() || "показано";
    });

    await step("Поиск в дереве: совпадение выделено, «Найдено: N»; ▲ ▼ и Enter — по найденным по кругу; ↓ из поиска — в дерево, ↑ ↓ — по узлам, Home и End — первый и последний, Enter — выбрать, Esc — очистить, выбранное остаётся видным; найденную группу → раскрывает целиком (§13, RULE-88, BUG-63, BUG-67)", async () => {
      if (mode() !== "queue") await click($("backToQueue"));
      const key = async (el, k) => {
        el.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true }));
        await wait();
      };
      const search = $("groupSearch");
      search.value = "конференц";
      search.dispatchEvent(new Event("input", { bubbles: true }));
      await wait();
      try {
        const marks = [...$("groupsList").querySelectorAll(".tree-node:not(.hidden) > .node-content mark")];
        expect(marks.length > 1 && marks.every((m) => m.textContent.toLowerCase() === "конференц"), `выделено: ${marks.map((m) => m.textContent).join(", ")}`);
        expect(!$("groupsFound").hidden && $("groupsFoundText").textContent === `Найдено: ${marks.length}`, `счётчик «${$("groupsFoundText").textContent}», выделено ${marks.length}`);
        // ▲ ▼ и Enter в поле — только по найденным, по кругу; текущее — с рамкой
        const n = marks.length;
        const at = () => [$("groupsHitPos").textContent, $("groupsList").querySelector(".hit-current").dataset.id];
        const hitId = (i) => marks[i].closest(".tree-node").dataset.id;
        expect(JSON.stringify(at()) === JSON.stringify([`1 / ${n}`, hitId(0)]), `сначала текущее — первое: ${at()}`);
        await click($("groupsHitNext"));
        expect(JSON.stringify(at()) === JSON.stringify([`2 / ${n}`, hitId(1)]), `▼ — ко второму: ${at()}`);
        await key(search, "Enter");
        expect(at()[0] === `3 / ${n}`, `Enter — к следующему: ${at()}`);
        search.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", shiftKey: true, bubbles: true }));
        await wait();
        expect(at()[0] === `2 / ${n}`, `Shift+Enter — к предыдущему: ${at()}`);
        await click($("groupsHitPrev"));
        await click($("groupsHitPrev"));
        expect(JSON.stringify(at()) === JSON.stringify([`${n} / ${n}`, hitId(n - 1)]), `▲ с первого — к последнему: ${at()}`);
        await click($("groupsHitNext"));
        expect(at()[0] === `1 / ${n}`, `▼ с последнего — к первому: ${at()}`);
        await key(search, "ArrowDown");
        const first = document.activeElement;
        expect(first.dataset.id === hitId(0), "↓ из поиска — не на текущее найденное");
        await key(first, "ArrowDown");
        const second = document.activeElement;
        expect(second.classList.contains("tree-node") && second !== first, "↓ в дереве не перешла к следующему узлу");
        await key(second, "ArrowUp");
        expect(document.activeElement === first, "↑ не вернула к прежнему узлу");
        // Home и End — первый и последний видимый узел (§13, PROC-27)
        const visible = () => [...$("groupsList").querySelectorAll(".tree-node")].filter((n) => n.getClientRects().length > 0);
        await key(first, "End");
        expect(document.activeElement === visible().pop(), "End — не на последний видимый узел");
        await key(document.activeElement, "Home");
        expect(document.activeElement === visible()[0] && document.activeElement.dataset.id === "all", "Home — не на первый узел");
        first.focus();
        const id = first.dataset.id;
        await key(first, "Enter");
        await wait(100);
        const active = $("groupsList").querySelector(".tree-node.active");
        expect(active && active.dataset.id === id, "Enter не выбрал узел");
        expect(document.activeElement && document.activeElement.dataset.id === id, "после выбора фокус ушёл из дерева");
        search.focus();
        await key(search, "Escape");
        expect(search.value === "" && $("groupsFound").hidden && !$("groupsList").querySelector("mark"), "Esc в поиске не очистил его");
        // Выбранное в поиске после очистки видно и в порядке Tab, даже если путь к нему был свёрнут (BUG-63).
        // Группа без инцидентов: путь к группе инцидента раскрывается и так — подсветкой выбранного в очереди
        if ($("groupsCollapseAll").textContent.includes("unfold_less")) await click($("groupsCollapseAll"));
        search.value = "Офис 2";
        search.dispatchEvent(new Event("input", { bubbles: true }));
        await wait();
        await key(search, "ArrowDown");
        const quiet = document.activeElement;
        expect(quiet.classList.contains("tree-node") && quiet.querySelector(":scope > .node-content .node-text").textContent === "Офис 2", "↓ из поиска — не на «Офис 2»");
        await key(quiet, "Enter");
        await wait(100);
        search.focus();
        await key(search, "Escape");
        const chosen = [...$("groupsList").querySelectorAll(".tree-node.active")].find((n) => n.getClientRects().length > 0);
        expect(chosen && chosen.dataset.id === quiet.dataset.id && chosen.tabIndex === 0, "после очистки поиска выбранный узел скрыт в свёрнутой группе или не в порядке Tab (BUG-63)");
        // Группа, найденная только по названию, — свёрнута; → раскрывает её, внутри — всё; ← сворачивает (BUG-67)
        if ($("groupsCollapseAll").textContent.includes("unfold_less")) await click($("groupsCollapseAll"));
        search.value = "Офис 1";
        search.dispatchEvent(new Event("input", { bubbles: true }));
        await wait();
        await key(search, "ArrowDown");
        const office = () => $("groupsList").querySelector(`[data-id="${document.activeElement.dataset.id}"]`);
        const inside = () => [...office().querySelectorAll(":scope > ul > .tree-node")].filter((n) => n.getClientRects().length > 0).length;
        expect(office().querySelector(":scope > .node-content .node-text").textContent === "Офис 1", "↓ из поиска — не на «Офис 1»");
        expect(!office().classList.contains("open") && office().getAttribute("aria-expanded") === "false", "найденная по названию группа раскрыта, а внутри пусто");
        await key(office(), "ArrowRight");
        const all = window.IM_FIXTURE.sourceGroups.flatMap(function walk(g) { return [g].concat((g.groups || []).flatMap(walk)); }).find((g) => g.name === "Офис 1");
        expect(office().classList.contains("open") && inside() === (all.groups || []).length + all.devices.length, `→ на найденной группе: внутри видно ${inside()}, у группы ${(all.groups || []).length + all.devices.length}`);
        await key(office(), "ArrowLeft");
        expect(!office().classList.contains("open") && inside() === 0, "← не свернула раскрытую в поиске группу");
        search.focus();
        await key(search, "Escape");
        // → раскрывает свёрнутую группу, ← — сворачивает; фокус остаётся на ней
        const closed = [...$("groupsList").querySelectorAll(".tree-node.has-children:not(.open)")].find((n) => n.getClientRects().length > 0);
        expect(closed, "нет свёрнутой группы");
        const node = () => $("groupsList").querySelector(`[data-id="${closed.dataset.id}"]`);
        closed.focus();
        await key(closed, "ArrowRight");
        expect(node().classList.contains("open") && node().getAttribute("aria-expanded") === "true" && document.activeElement === node(), "→ не раскрыла группу");
        await key(node(), "ArrowLeft");
        expect(!node().classList.contains("open") && document.activeElement === node(), "← не свернула группу");
        return `найдено ${marks.length}, выбран «${first.querySelector(".node-text").textContent}»`;
      } finally {
        if (search.value) {
          search.value = "";
          search.dispatchEvent(new Event("input", { bubbles: true }));
        }
        await click($("groupsList").querySelector('[data-id="all"] > .node-content'));
      }
    });

    await step("Выделить по фильтру → «Взять в работу»: пожары одним инцидентом, у основного «+N», привязанные в карточке; «Отсоединить» и «Отсоединить все» — события снова новые (§11)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      if (mode() !== "queue") await click($("backToQueue"));
      // Лимит активных свободен: свои в работе — в очередь
      const busy = (await stand.get("/operator/incidents", { filter: "mine", pageSize: 1000 })).items.filter((e) => e.state === "in_progress");
      if (busy.length) await stand.raw("POST", "/operator/incidents/transitions/release/bulk", { incidentGuids: busy.map((e) => e.guid), formValues: { comment: NOTE }, surface: "card" });
      await setFilter("open");
      await click($("groupsList").querySelector('.tree-all [data-filter="select"]'));
      await click($("groupingRows").querySelector('[data-ms-toggle="0:eventTypeIds"]'));
      const fire = [...$("groupingRows").querySelectorAll('[data-fkey="0:eventTypeIds"]')].find((x) => x.value === "fire");
      expect(fire, "в окне нет «Пожарная тревога»");
      await click(fire);
      await click($("groupingConfirm"));
      // Как над очередью — «Открытые»: новые и свои в работе или отложенные
      const fires = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.filter((e) => e.eventType.id === "fire");
      // Сосед INC-1853 — тоже «пожар», но сценарий медпункта (§14.5, ARCH-15): с ним «Взять в работу» недоступна —
      // как одно берутся инциденты одного сценария (§11.3). Оператор снимает с него отметку
      const fireTitle = window.IM_FIXTURE.scenarios.rows.find((r) => r.guid === window.IM_FIXTURE.scenarios.keys.fire).name;
      const others = fires.filter((e) => e.scenarioTitle !== fireTitle);
      const mixed = $("selBar").querySelector('[data-sel-do="merge"]');
      expect(!others.length || (mixed && off(mixed)), "«Взять в работу» доступна на выборке разных сценариев");
      for (const x of others) {
        let box = null;
        for (let page = 1; page <= 20 && !box; page++) {
          const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
          if (page > 1 && (!nav || nav.disabled)) break;
          if (nav) await click(nav);
          box = $("eventsList").querySelector(`[data-check="${x.guid}"]`);
        }
        expect(box, `у ${x.number} нет отметки в очереди`);
        await click(box);
      }
      const picked = fires.filter((e) => e.scenarioTitle === fireTitle).map((e) => e.guid);
      expect(!$("selBar").hidden && $("selBar").textContent.includes(`${picked.length}`), `панель выборки: «${$("selBar").textContent.trim()}»`);
      const take = $("selBar").querySelector('[data-sel-do="merge"]');
      expect(take && !off(take), `«Взять в работу» недоступна: ${take ? take.title : "нет кнопки"}`);
      await click(take);
      await wait();
      const lead = (await stand.get("/operator/incidents", { filter: "mine", pageSize: 1000 })).items.find((e) => e.state === "in_progress" && e.linkedCount);
      try {
        expect(lead && lead.linkedCount === picked.length - 1, `основной не взят или привязанных не ${picked.length - 1}`);
        // Карточка основного открылась сама — на его текущем шаге сценария
        expect(mode() === "work" && $("statusIncident").textContent.includes(lead.number), `карточка основного не открылась: «${$("statusIncident").textContent}»`);
        const card = await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}`);
        const at = card.scenario.path.lastIndexOf(card.scenario.cursorStepId) + 1;
        expect($("statusSteps").textContent.startsWith(`Шаг ${at} из`), `карточка не на шаге ${at}: «${$("statusSteps").textContent}»`);
        await click($("backToQueue"));
        await setFilter("mine");
        const row = $("eventsList").querySelector(`.event[data-id="${lead.guid}"]`);
        expect(row && row.querySelector(".chip.linked"), "у основного нет пометки «+N»");
        await click(row.querySelector('[data-do="open_card"], [data-do="resume"]'));
        expect(mode() === "work", "карточка основного не открылась из очереди");
        // Привязанные — на своей вкладке, не над сценарием; открываются и по пометке «+N» в заголовке
        expect(!root().querySelector("[data-detach]") && root().querySelector(".crumbs"), "привязанные видны на вкладке сценария");
        // Один ряд: «Назад», действия с инцидентом, «Далее». Нижний блок одинаков на обеих вкладках: место
        // «Назад» / «Далее» на вкладке привязанных занято, действия не прыгают
        const actsTop = () => {
          const bottom = root().querySelector(".work-bottom").getBoundingClientRect();
          const acts = root().querySelector(".work-acts").getBoundingClientRect();
          return `${Math.round(acts.left - bottom.left)}:${Math.round(acts.top - bottom.top)}/${Math.round(bottom.height)}`;
        };
        const box = (sel) => root().querySelector(sel).getBoundingClientRect();
        // «К очереди» слева, действия в середине, «Назад» и «Далее» рядом справа (RULE-89). Широкая карточка —
        // один ряд; узкая — действия строкой ниже, по центру
        const sameLine = (a, b) => Math.abs(box(a).top - box(b).top) < 8;
        const oneRow = sameLine(".work-acts", "#stepBack") && box(".work-acts").left > box("#backToQueue").right && box("#stepBack").left > box(".work-acts").right;
        const below = box(".work-acts").top >= box("#stepBack").bottom - 1;
        expect(oneRow || below, `действия ни между «К очереди» и «Назад», ни строкой ниже: действия ${Math.round(box(".work-acts").left)},${Math.round(box(".work-acts").top)}, «Назад» ${Math.round(box("#stepBack").left)},${Math.round(box("#stepBack").top)}, ряд ${Math.round(box(".scenario-actions").width)}`);
        expect(sameLine("#stepNext", "#stepBack") && box("#stepNext").left - box("#stepBack").right < 16 && box("#stepNext").left > box("#stepBack").left, "«Назад» не рядом слева от «Далее»");
        // «К очереди» — в той же строке, первой слева, в шапке её нет
        expect(sameLine("#backToQueue", "#stepBack") && box("#backToQueue").left < box("#stepBack").left, "«К очереди» не слева в нижнем ряду");
        expect(!document.querySelector(".work-h #backToQueue"), "«К очереди» осталась в шапке");
        const before = actsTop();
        await click($("workTitle").querySelector('.chip.linked[data-work-tab="linked"]'));
        expect(root().querySelector('.work-tab.on[data-work-tab="linked"]') && !root().querySelector(".crumbs"), "пометка «+N» не открыла вкладку привязанных");
        expect(actsTop() === before, `действия сдвинулись при переключении вкладок: ${before} → ${actsTop()}`);
        // Вкладки в карточке переключают сами, не только пометка в заголовке (PROC-34)
        await click(root().querySelector('.work-tab[data-work-tab="scenario"]'));
        expect(root().querySelector('.work-tab.on[data-work-tab="scenario"]') && root().querySelector(".crumbs"), "вкладка «Сценарий» не вернула шаги");
        await click(root().querySelector('.work-tab[data-work-tab="linked"]'));
        expect(root().querySelector('.work-tab.on[data-work-tab="linked"]') && !root().querySelector(".crumbs"), "вкладка «Привязанные инциденты» не открылась");
        // На вкладке привязанных «Назад» и «Далее» видны, но серые; «К очереди» доступна (RULE-89)
        const shown = (sel) => {
          const el = root().querySelector(sel);
          return el && el.getClientRects().length > 0 && getComputedStyle(el).visibility === "visible" ? el : null;
        };
        expect(shown("#stepBack") && off(shown("#stepBack")) && shown("#stepNext") && off(shown("#stepNext")), "на вкладке привязанных «Назад» / «Далее» не видны или доступны");
        expect(shown("#backToQueue") && !shown("#backToQueue").disabled, "на вкладке привязанных нет «К очереди»");
        // Узкая панель — как на телефоне 360 px (BUG-53): «Отсоединить» и «Отсоединить все» внутри панели, строки не шире её
        const lnk = root().querySelector(".lnk-panel");
        lnk.style.width = "300px";
        await wait();
        const edge = lnk.getBoundingClientRect();
        const outside = [...lnk.querySelectorAll("[data-detach], [data-detach-all]")].filter((x) => {
          const r = x.getBoundingClientRect();
          return r.left < edge.left - 1 || r.right > edge.right + 1;
        });
        const wide = [...lnk.querySelectorAll(".lnk-member, .lnk-head")].filter((x) => x.scrollWidth > x.clientWidth + 1);
        lnk.style.width = "";
        expect(!outside.length && !wide.length, `узкая панель: за краем — ${outside.map((x) => x.textContent.trim()).join(", ") || "ничего"}; шире панели — ${wide.length} строк`);
        // Срок у группы один — срок основного в заголовке; у привязанных своего отсчёта нет (§11.4, RULE-97)
        const leadCard = await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}`);
        const linkedPage = await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}/linked`, { pageSize: 10 });
        expect(linkedPage.items.every((x) => x.timer === null), `у привязанных свой срок в ответе: ${linkedPage.items.filter((x) => x.timer).map((x) => x.number).join(", ")}`);
        expect(!root().querySelector(".lnk-member [data-timer]") && !$("workTitle").querySelector(".lnk-due"), "у привязанных — свой отсчёт или «Срок привязанного» в заголовке");
        const leadTimer = $("workTitle").querySelector(`[data-timer="${lead.guid}"]`);
        expect(!leadCard.timer || (leadTimer && (!leadCard.timer.running || leadTimer.dataset.due === String(Date.parse(leadCard.timer.dueAt)))), "срок группы — срок основного — не виден в заголовке");
        const detach = root().querySelectorAll("[data-detach]");
        // Постранично, по 10 (LINKED_PAGE)
        expect(detach.length === Math.min(picked.length - 1, 10), `на вкладке привязанных ${detach.length}`);
        const gone = detach[0].dataset.detach;
        await click(detach[0]);
        await wait();
        const back = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.guid === gone);
        expect(back && back.state === "new", "отсоединённый не вернулся в очередь новым");
        // Уведомление называет состояние после «Отсоединить» — из машины, а не текстом интерфейса
        const told = [...$("toasts").children].map((x) => x.textContent).find((x) => /отсоединён/.test(x)) || "";
        const stateLabel = window.IM_STRINGS.ru[window.IM_WORKFLOW.states.find((x) => x.id === back.state).labelKey];
        expect(told.includes(`«${stateLabel}»`), `уведомление: «${told}»`);
        // «Отсоединить все» — остальные разом, список привязанных в карточке пропадает
        const all = root().querySelector("[data-detach-all]");
        expect(all && !off(all), "нет кнопки «Отсоединить все»");
        await click(all);
        await wait();
        const left = (await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}/linked`, { pageSize: 200 })).items.filter((x) => x.state === "linked");
        expect(!left.length && !root().querySelector("[data-detach]"), `после «Отсоединить все» привязанных ${left.length}`);
        expect(!root().querySelector(".work-tabs") && root().querySelector(".crumbs"), "привязанных нет — а вкладки остались или сценарий не вернулся");
        return `основной ${lead.number}, привязанных ${picked.length - 1}`;
      } finally {
        if (lead) {
          const rest = await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}/linked`, { pageSize: 200 });
          for (const x of rest.items.filter((e) => e.state === "linked")) await stand.raw("DELETE", `/operator/incidents/${encodeURIComponent(lead.guid)}/linked/${encodeURIComponent(x.guid)}`);
          await stand.raw("POST", "/operator/incidents/transitions/release/bulk", { incidentGuids: [lead.guid], formValues: { comment: NOTE }, surface: "card" });
        }
        if (mode() === "work") await click($("backToQueue"));
        await setFilter("open");
      }
    });

    await step("Форма действия на выборке — с вариантами очереди, даже когда отмеченных нет на странице (BUG-78)", async () => {
      if (mode() !== "queue") await click($("backToQueue"));
      const stand = window.IM_SELFTEST_API;
      // Два своих в работе — без лимита активных; после шага набор — как был
      await standReset({ fixture: "demo", workflowPatch: { limits: { maxActive: null } } });
      await wait(400);
      // Переход запросом API — с тем, что видно в карточке (§14.1, RULE-142)
      const act = async (g, id, formValues) => {
        const path = `/operator/incidents/${encodeURIComponent(g)}`;
        const seen = seenBody((await stand.raw("GET", path)).body);
        const res = await stand.raw("POST", `${path}/transitions/${id}`, Object.assign({ formValues, surface: "queue" }, seen));
        expect(res.status === 200, `${id} ${g}: ${res.status} ${JSON.stringify(res.body).slice(0, 200)}`);
      };
      try {
        await setFilter("open");
        const ids = [...$("eventsList").querySelectorAll('[data-do="claim"]')].filter((b) => !off(b)).slice(0, 2).map((b) => b.dataset.ev);
        expect(ids.length === 2, "на странице нет двух новых");
        for (const g of ids) await act(g, "claim", {});
        await setFilter("all");
        await setFilter("open");
        for (const g of ids) await click($("eventsList").querySelector(`[data-check="${g}"]`));
        const next = $("eventsPager").querySelector('[data-page="2"]');
        expect(next, "в «Открытых» одна страница");
        await click(next);
        expect(ids.every((g) => !$("eventsList").querySelector(`[data-check="${g}"]`)), "отмеченные — и на второй странице");
        const b = $("selBar").querySelector('[data-sel-do="close"]');
        expect(b && !off(b), "в панели выборки нет «Закрыть»");
        await click(b);
        const opts = [...field("resultId").querySelectorAll("option")].filter((o) => o.value && !o.disabled).map((o) => o.value);
        // В карточке своему в работе предложены и «Ложная тревога», и другие; из очереди — только «Массовый сбой»
        expect(opts.join(",") === "mass", `варианты результата: ${opts.join(", ")}`);
        return opts.join(", ");
      } finally {
        if (!$("modalDialog").hidden) document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
        await wait();
        if (!$("clearSelectionBtn").disabled) await click($("clearSelectionBtn"));
        await standReset({ fixture: "demo" });
        await wait(400);
        await setFilter("open");
      }
    });

    await step("Одно отмеченное не на странице — действие панели выборки выполняется, а не «конфликт версии»", async () => {
      if (mode() !== "queue") await click($("backToQueue"));
      const stand = window.IM_SELFTEST_API;
      let g = null;
      try {
        await setFilter("open");
        g = [...$("eventsList").querySelectorAll('[data-do="claim"]')].find((b) => !off(b)).dataset.ev;
        const path = `/operator/incidents/${encodeURIComponent(g)}`;
        const seen = seenBody((await stand.raw("GET", path)).body);
        const claimed = await stand.raw("POST", `${path}/transitions/claim`, Object.assign({ formValues: {}, surface: "queue" }, seen));
        expect(claimed.status === 200, `взять: ${claimed.status}`);
        await setFilter("all");
        await setFilter("open");
        await click($("eventsList").querySelector(`[data-check="${g}"]`));
        const next = $("eventsPager").querySelector('[data-page="2"]');
        expect(next, "в «Открытых» одна страница");
        await click(next);
        expect(!$("eventsList").querySelector(`[data-check="${g}"]`), "отмеченный — и на второй странице");
        const b = $("selBar").querySelector('[data-sel-do="hold"]');
        expect(b && !off(b), "в панели выборки нет «Отложить»");
        await click(b);
        await wait();
        await setField("reasonId", "third_party");
        await confirmDialog(NOTE);
        await wait();
        const now = (await stand.raw("GET", path)).body;
        expect(now.state === "on_hold", `состояние после «Отложить»: ${now.state}; ${[...$("toasts").children].map((x) => x.textContent).join(" | ")}`);
        return now.number;
      } finally {
        if (!$("modalDialog").hidden) document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
        await wait();
        if (!$("clearSelectionBtn").disabled) await click($("clearSelectionBtn"));
        await standReset({ fixture: "demo" });
        await wait(400);
        await setFilter("open");
      }
    });

    await step("Одно отмеченное не на странице, после отметки его отложили в другой вкладке — «Вернуть в очередь» панели не уводит его: сверяется снимок отметки; повтор после отказа проходит (§14.1, BUG-84, BUG-106, RULE-142)", async () => {
      if (mode() !== "queue") await click($("backToQueue"));
      const stand = window.IM_SELFTEST_API;
      let g = null;
      try {
        await setFilter("open");
        g = [...$("eventsList").querySelectorAll('[data-do="claim"]')].find((b) => !off(b)).dataset.ev;
        const path = `/operator/incidents/${encodeURIComponent(g)}`;
        const claimed = await stand.raw("POST", `${path}/transitions/claim`, Object.assign({ formValues: {}, surface: "queue" }, seenBody((await stand.raw("GET", path)).body)));
        expect(claimed.status === 200, `взять: ${claimed.status}`);
        await setFilter("all");
        await setFilter("open");
        await click($("eventsList").querySelector(`[data-check="${g}"]`));
        const next = $("eventsPager").querySelector('[data-page="2"]');
        expect(next, "в «Открытых» одна страница");
        await click(next);
        expect(!$("eventsList").querySelector(`[data-check="${g}"]`), "отмеченный — и на второй странице");
        // После отметки инцидент отложили в другой вкладке: карточка, прочитанная перед отправкой, — уже отложенная,
        // а «Вернуть в очередь» доступно и из «Отложен»
        const held = await stand.raw("POST", `${path}/transitions/hold`, Object.assign({ formValues: { reasonId: "third_party", comment: "тест" }, surface: "card" }, seenBody((await stand.raw("GET", path)).body)));
        expect(held.status === 200, `отложить в другой вкладке: ${held.status}`);
        await wait();
        const b = $("selBar").querySelector('[data-sel-do="release"]');
        expect(b && !off(b), "в панели выборки нет «Вернуть в очередь»");
        await click(b);
        await wait();
        if (!$("modalDialog").hidden) await confirmDialog(NOTE);
        await wait();
        const now = (await stand.raw("GET", path)).body;
        expect(now.state === "on_hold", `после «Вернуть в очередь» по устаревшей отметке: ${now.state}`);
        // Причину оператор увидел — повтор идёт по нынешнему снимку и проходит, а не снова 412 (BUG-106, RULE-142)
        const again = $("selBar").querySelector('[data-sel-do="release"]');
        expect(again && !off(again), "после отказа в панели выборки нет «Вернуть в очередь»");
        await click(again);
        await wait();
        if (!$("modalDialog").hidden) await confirmDialog(NOTE);
        await wait();
        const after = (await stand.raw("GET", path)).body;
        expect(after.state !== "on_hold", `повтор после отказа: ${after.state}; ${[...$("toasts").children].map((x) => x.textContent).join(" | ")}`);
        return now.number;
      } finally {
        if (!$("modalDialog").hidden) document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
        await wait();
        if (!$("clearSelectionBtn").disabled) await click($("clearSelectionBtn"));
        await standReset({ fixture: "demo" });
        await wait(400);
        await setFilter("open");
      }
    });

    await step("Отмеченное живёт в своём списке: другой узел дерева или фильтр — отметки сняты, листание страниц — нет", async () => {
      if (mode() !== "queue") await click($("backToQueue"));
      await setFilter("open");
      const picked = () => Number(($("selBar").textContent.match(/Отмечено: (\d+)/) || [0, 0])[1]);
      await click($("eventsList").querySelector("[data-check]"));
      expect(picked() === 1 && !$("selBar").hidden, "отметка не поставилась");
      const next = $("eventsPager").querySelector('[data-page="2"]');
      if (next) {
        await click(next);
        expect(picked() === 1, "листание сняло отметку");
        await click($("eventsPager").querySelector('[data-page="1"]'));
      }
      const node = [...$("groupsList").querySelectorAll(".tree-node .node-content")].find((n) => n.textContent.includes("Главный офис"));
      await click(node);
      expect($("selBar").hidden && $("clearSelectionBtn").disabled, "другой узел дерева — отметки не сняты");
      await click($("groupsList").querySelector(".tree-all .node-content"));
      await click($("eventsList").querySelector("[data-check]"));
      await setFilter("all");
      expect($("selBar").hidden, "другой фильтр — отметки не сняты");
      await setFilter("open");
      // «Выделить по фильтру» у другого узла: очередь переходит на этот узел — отмеченные на экране
      const office = [...$("groupsList").querySelectorAll(".tree-node")].find((n) => n.querySelector(".node-text") && n.querySelector(".node-text").textContent.includes("Главный офис"));
      await click(office.querySelector('[data-filter="select"]'));
      await click($("groupingConfirm"));
      const ticked = [...$("eventsList").querySelectorAll("[data-check]")].filter((c) => c.checked).length;
      const active = $("groupsList").querySelector(".tree-node.active .node-text");
      expect(active && active.textContent.includes("Главный офис"), `очередь не на узле окна: «${active ? active.textContent : "нет"}»`);
      expect(ticked === Math.min(picked(), $("eventsList").querySelectorAll(".event").length) && picked() > 0, `отмечено ${picked()}, на экране отмеченных ${ticked}`);
      await click($("clearSelectionBtn"));
      await click($("groupsList").querySelector(".tree-all .node-content"));
    });

    await step("Меню «Выделить» в шапке очереди: «Все в фильтре» и «По фильтру…» — окно для выбранного узла дерева", async () => {
      if (mode() !== "queue") await click($("backToQueue"));
      await setFilter("open");
      try {
        await click($("selectMenuBtn"));
        const pop = $("selectMenu").querySelector(".menu-pop");
        expect(!pop.hidden && $("selectAllBtn") && $("selectByFilterBtn"), "меню «Выделить» не открылось");
        await click($("selectByFilterBtn"));
        expect(pop.hidden, "меню не закрылось");
        expect(!$("modalGrouping").hidden, "окно «Выделить по фильтру» не открылось");
        const intro = $("groupingIntro").textContent;
        expect(intro.startsWith("«Все устройства»"), `окно не для выбранного узла: «${intro}»`);
        return intro;
      } finally {
        if (!$("modalGrouping").hidden) await click(document.querySelector('[data-close="modalGrouping"]'));
      }
    });

    await step("Выделить по фильтру с «Одинаковый сценарий»: сценарий по выбору, «Взять в работу» на выделенных доступна", async () => {
      if (mode() !== "queue") await click($("backToQueue"));
      await setFilter("open");
      try {
        await click($("groupsList").querySelector('.tree-all [data-filter="select"]'));
        const all = Number(($("groupingHint").textContent.match(/\d+/) || [0])[0]);
        await click($("groupingRows").querySelector("[data-same]"));
        await click($("groupingRows").querySelector('[data-ms-toggle="s:scenario"]'));
        const opts = [...$("groupingRows").querySelectorAll('[data-fkey="s:scenario"]')];
        expect(opts.length > 1, `сценариев в списке: ${opts.length}`);
        // Сценарий, где взять нечего, не выбрать — иначе «Выделить 0» и окно не закрыть
        const zero = opts.filter((o) => o.closest("label").querySelector("em").textContent === "0");
        expect(zero.every((o) => o.disabled), `сценарий с нулём можно выбрать: ${zero.map((o) => o.closest("label").textContent.trim()).join(", ")}`);
        const other = opts.find((o) => !o.checked && Number(o.closest("label").querySelector("em").textContent) > 1);
        expect(other, "нет другого сценария с двумя событиями и больше");
        const n = Number(other.closest("label").querySelector("em").textContent);
        const name = other.closest("label").querySelector("span").textContent;
        await click(other);
        const hint = $("groupingHint").textContent;
        expect(hint.startsWith(`Подходит: ${n}`) && n < all, `после выбора «${name}»: «${hint}», без галочки — ${all}`);
        await click($("groupingConfirm"));
        const take = $("selBar").querySelector('[data-sel-do="merge"]');
        expect($("selBar").textContent.includes(`Отмечено: ${n}`), `панель выборки: «${$("selBar").textContent.trim()}»`);
        expect(take && !off(take), `«Взять в работу» недоступна: ${take ? take.title : "нет кнопки"}`);
        return `${name}: ${n} из ${all}`;
      } finally {
        if (!$("modalGrouping").hidden) await click(document.querySelector('[data-close="modalGrouping"]'));
        if (!$("clearSelectionBtn").disabled) await click($("clearSelectionBtn"));
      }
    });

    await step("Привязанных много — на вкладке «Привязанные инциденты» постранично; поиск по номеру привязанного — строка основного и страница найденного; «Отсоединить все» — со всех страниц (§11)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Ещё четырнадцать пожаров рядом с INC-1847 — копии с другими номерами; у каждой своё событие и своя тревога (ARCH-15)
      const fx = window.IM_FIXTURE;
      const base = fx.incidents.find((i) => i.number === "INC-1847");
      const extra = Array.from({ length: 14 }, (_, k) => {
        const n = `99${String(k).padStart(2, "0")}`;
        return Object.assign(JSON.parse(JSON.stringify(base)), { guid: `10000000-0000-4000-8000-00000000${n}`, number: `INC-${n}`, eventGuid: `70000000-0000-4000-8000-00000000${n}`, alarmNumber: `INC-${n}` });
      });
      if (mode() !== "queue") await click($("backToQueue"));
      await standReset({ fixture: "demo", fixturePatch: { incidents: fx.incidents.concat(extra) } });
      await wait(400);
      try {
        const res = await stand.post("/operator/incidents/merge", { incidentGuids: [base.guid].concat(extra.map((e) => e.guid)) });
        const lead = res.incident;
        // Поиск по номеру привязанного: находит строку основного, открытая из неё карточка — на странице найденного
        const sought = (await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}/linked`, { pageSize: 200 })).items.pop();
        await setFilter("open");
        $("eventSearch").value = sought.number;
        $("eventSearch").dispatchEvent(new Event("input", { bubbles: true }));
        await wait(100);
        const hitRow = $("eventsList").querySelector(`.event[data-id="${lead.guid}"]`);
        const note = hitRow && hitRow.querySelector(".event-found");
        expect(note && note.textContent.includes(sought.number) && $("eventsList").querySelectorAll(".event").length === 1, `поиск ${sought.number}: «${note ? note.textContent : "нет строки основного"}»`);
        await click(hitRow.querySelector('[data-do="open_card"], [data-do="resume"]'));
        expect(mode() === "work", "карточка основного не открылась");
        const found = root().querySelector(".lnk-member.found .lnk-num");
        expect(root().querySelector('.work-tab.on[data-work-tab="linked"]') && found && found.textContent === sought.number, `из поиска — не на вкладке привязанных или ${sought.number} не подсвечен`);
        await click($("backToQueue"));
        $("eventSearch").value = "";
        $("eventSearch").dispatchEvent(new Event("input", { bubbles: true }));
        await wait(100);
        await setFilter("mine");
        await click($("eventsList").querySelector(`.event[data-id="${lead.guid}"] [data-do="open_card"], .event[data-id="${lead.guid}"] [data-do="resume"]`));
        expect(mode() === "work", "карточка основного не открылась");
        await click(root().querySelector('.work-tab[data-work-tab="linked"]'));
        // Та же карточка — на той странице, где оставили (на странице найденного): к первой
        const toFirst = root().querySelector('[data-lnk-page="1"]');
        if (toFirst && !toFirst.disabled) await click(toFirst);
        const rows = () => [...root().querySelectorAll(".lnk-member .lnk-num")].map((x) => x.textContent);
        const info = () => (root().querySelector(".lnk-pager .pager-info") || { textContent: "" }).textContent;
        const first = rows();
        expect(first.length === 10 && info() === "1–10 из 14", `первая страница: ${first.length} строк, «${info()}»`);
        await click(root().querySelector('[data-lnk-page="2"]'));
        const second = rows();
        expect(second.length === 4 && info() === "11–14 из 14" && !second.some((n) => first.includes(n)), `вторая страница: ${second.join(", ")}, «${info()}»`);
        await click(root().querySelector("[data-detach-all]"));
        await wait();
        const left = (await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}/linked`, { pageSize: 200 })).items.filter((x) => x.state === "linked");
        expect(!left.length && !root().querySelector(".lnk-panel"), `после «Отсоединить все» привязанных ${left.length}`);
        return `${first.join(", ")} | ${second.join(", ")}`;
      } finally {
        if (mode() === "work") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(400);
        await setFilter("open");
      }
    });

    /* Звук (§21, план 87б): без слуха. Вывод IMSound.output подменён записью { pattern, at, volume } на своих часах:
       запланированное вперёд слышно, когда часы до него дошли и его не остановили */
    const fakeSound = { rec: [], clock: 1000, ready: false };
    const soundOut = {
      ready: () => fakeSound.ready,
      unlock: () => ((fakeSound.ready = true), Promise.resolve(true)),
      now: () => fakeSound.clock,
      play(pattern, at, volume) {
        const r = { pattern, at, volume, stopped: false };
        fakeSound.rec.push(r);
        return r;
      },
      stop(r) {
        if (r && r.at > fakeSound.clock) r.stopped = true;
      },
    };
    const heard = (pattern) => fakeSound.rec.filter((r) => r.at <= fakeSound.clock && !r.stopped && (!pattern || r.pattern === pattern)).length;
    const soundAdvance = async (sec) => {
      fakeSound.clock += sec;
      window.dispatchEvent(new Event("im-sound-tick"));
      await wait();
    };
    // «Звук не включён», «Только важное» — пункты строки поста (§22.4)
    const soundLine = (kind) => document.querySelector(`#postStatus [data-sound-line="${kind}"]`);
    // Что-то звучит (§21.4): значок звука звенит, слева «Тихо»; звучащая строка — значок динамика (§22.3)
    const ringOn = () => $("soundBtn").dataset.ringing === "on";
    const ringGuid = () => (ringOn() ? $("soundBtn").dataset.soundGo : null);
    const quietBtn = () => ($("soundQuiet").hidden ? null : $("soundQuiet").querySelector("[data-sound-silence]"));
    const rowSoundOf = (guid) => document.querySelector(`#eventsList [data-id="${CSS.escape(guid)}"] [data-row-sound]`);
    // Меню звука — щелчком по значку; пока значок звенит, он ведёт к звучащему, поэтому сначала «Тихо» (§21.4)
    async function soundMenuOpen() {
      if (quietBtn()) await click(quietBtn());
      await click($("soundBtn"));
    }
    const DEV5 = "20000000-0002-4000-8000-000000000005";
    // Инцидент нужного приоритета от встроенного сервера: появление — событием потока incident.created
    async function soundIncident(priority) {
      const res = await window.IM_SELFTEST_API.raw("POST", "/test/incidents", { eventTypeId: "fire", deviceIds: [DEV5], priority });
      expect(res.status === 201, `инцидент приоритета ${priority}: ${res.status}`);
      await wait(150);
      return res.body;
    }
    const titleN = () => {
      const m = document.title.match(/^\((\d+)\) /);
      return m ? Number(m[1]) : 0;
    };
    const SOUND_FIRST = "Звук: до первого нажатия молчит и не стреляет накопленным; «Включить звук» — один проверочный сигнал (§21.5)";

    await step(SOUND_FIRST, async () => {
      expect(window.IMSound && window.IMSound.output && window.IMSound.decideSound, "sound.js и sound-synth.js не подключены");
      await standReset({ fixture: "demo", workflowPatch: { limits: { maxActive: null } } });
      await wait(400);
      window.IMSound.output = soundOut;
      window.dispatchEvent(new Event("im-sound-output"));
      await wait();
      expect(soundLine("off") && $("soundIcon").textContent === "🔇", `до нажатия: значок «${$("soundIcon").textContent}», строки «Звук не включён» ${soundLine("off") ? "есть" : "нет"}`);
      await soundIncident(100);
      expect(fakeSound.rec.length === 0, `до нажатия сыграно ${fakeSound.rec.length}`);
      // Как в браузере: сначала pointerdown (он сам включает звук), потом click по той же кнопке — проверочный сигнал
      // не должен потеряться из-за перерисовки строки между ними
      const enable = soundLine("off").querySelector("[data-sound-enable]");
      enable.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
      await wait();
      await click(enable);
      await wait();
      const now = fakeSound.rec.filter((r) => r.at <= fakeSound.clock);
      expect(now.length === 1 && now[0].pattern === window.IMSound.TEST_PATTERN, `после «Включить звук» сейчас: ${now.map((r) => r.pattern).join(", ") || "ничего"}`);
      expect(!soundLine("off") && $("soundIcon").textContent === "🔊", `после включения: значок «${$("soundIcon").textContent}»`);
      // «Звук не включён» длилось с входа — ни начала, ни конца в журнале (§22.4)
      const startedLater = [...$("bellList").querySelectorAll("[data-notice]")].some((li) => /Звук не включён/.test(li.textContent));
      expect(startedLater || !noticeWith(/Звук включён/), `конец состояния, длившегося с входа, — в журнале: ${noticeList()}`);
      return `проверочный — ${now[0].pattern}`;
    });

    await step("Звук: «Только важное — 5 мин» — значок 🔉, строка «до ЧЧ:ММ · Вернуть»; Высокий молчит, после «Вернуть» — звучит (§21.4)", async () => {
      await soundMenuOpen();
      const item = $("soundPop").querySelector("[data-sound-important]");
      expect(!$("soundPop").hidden && item, "меню звука не открылось");
      expect(item.textContent.includes(String(window.IM_WORKFLOW.sound.muteMinutes)), `пункт меню: «${item.textContent}»`);
      await click(item);
      const line = soundLine("important");
      expect($("soundIcon").textContent === "🔉" && line && /\d\d:\d\d/.test(line.textContent) && line.querySelector("[data-sound-back]"), `«Только важное»: значок «${$("soundIcon").textContent}», строка «${line ? line.textContent : "нет"}»`);
      const before = heard("double");
      await soundIncident(75);
      expect(heard("double") === before, "при «Только важное» Высокий прозвучал");
      await click(soundLine("important").querySelector("[data-sound-back]"));
      expect(!soundLine("important") && $("soundIcon").textContent === "🔊", "«Вернуть» не вернул звук");
      await soundIncident(75);
      expect(heard("double") === before + 1, `после «Вернуть» Высокий: ${heard("double") - before} сигналов`);
      return line.textContent.trim();
    }, SOUND_FIRST);

    // Строка состояния поста (§22.4): «Нет связи» — признак активности не дошёл; «Только важное» — из меню звука
    const postItem = () => $("postStatus").querySelector("[data-post-state]");
    const realPost = window.IM_SELFTEST_API.post;
    const heartbeatDown = (down) => {
      const api = window.IM_SELFTEST_API;
      api.post = down ? (path, body, headers) => (/\/session\/heartbeat$/.test(path) ? Promise.reject({ status: 0 }) : realPost(path, body, headers)) : realPost;
      window.IM_SELFTEST_UI.heartbeat();
      return wait();
    };
    async function onlyImportantOn() {
      await soundMenuOpen();
      await click($("soundPop").querySelector("[data-sound-important]"));
    }
    async function postCleanup() {
      await heartbeatDown(false);
      const back = document.querySelector("#postStatus [data-sound-back], #bellStates [data-sound-back]");
      if (back) await click(back);
      if (!$("bellPanel").hidden) await click($("bellClose"));
    }
    const POST_STEP = "Строка поста: два состояния — видно серьёзное и «и ещё 1»; щелчок — колокольчик на «Система» с обоими и их кнопками; открыл — 0, начало и конец — записи «Система» (§22.4, §22.5)";
    await step(POST_STEP, async () => {
      try {
        expect(!postItem(), `до начала в строке поста: «${$("postStatus").textContent.trim()}»`);
        await onlyImportantOn();
        expect(postItem() && postItem().dataset.postState === "only_important" && !$("postStatus").querySelector(".post-more"), `«Только важное» одно: «${$("postStatus").textContent.trim()}»`);
        await heartbeatDown(true);
        const text = $("postStatus").textContent.replace(/\s+/g, " ").trim();
        expect(postItem().dataset.postState === "connection" && /Нет связи с агентом/.test(text) && /и ещё 1/.test(text), `два состояния: «${text}»`);
        const unread = $("bellCount").hidden ? 0 : Number($("bellCount").textContent);
        expect(unread >= 2 && noticeWith(/Нет связи с агентом/) && noticeWith(/Только важное до/), `начала состояний в колокольчике: ${noticeList()}, непрочитанных ${unread}`);
        await click($("postStatus").querySelector("[data-post-open]"));
        const tab = $("bellTabs").querySelector('[aria-selected="true"]');
        expect(!$("bellPanel").hidden && tab && tab.dataset.bellTab === "system", `щелчок по строке: панель ${$("bellPanel").hidden ? "закрыта" : "открыта"}, вкладка ${tab && tab.dataset.bellTab}`);
        const states = [...$("bellStates").querySelectorAll("[data-post-state]")].map((x) => x.dataset.postState).join();
        expect(states === "connection,only_important" && $("bellStates").querySelector("[data-sound-back]"), `на «Система» идущие состояния: ${states}`);
        expect($("bellCount").hidden, `открыл — число не 0: ${$("bellCount").textContent}`);
        expect(noticeWith(/Нет связи с агентом/).classList.contains("unread"), "непрочитанное до открытия не выделено");
        // Кнопка пункта — и на вкладке «Система»: «Вернуть» снимает «Только важное», в журнале — конец
        await click($("bellStates").querySelector("[data-sound-back]"));
        const ended = noticeWith(/«Только важное» закончилось/);
        expect(ended && ended.dataset.kind === "system", `нет записи о конце «Только важного»: ${noticeList()}`);
        await heartbeatDown(false);
        expect(!postItem(), `после восстановления связи в строке: «${$("postStatus").textContent.trim()}»`);
        const back = noticeWith(/Связь восстановлена/);
        expect(back && back.dataset.kind === "system" && back.classList.contains("unread"), `нет записи «Связь восстановлена»: ${noticeList()}`);
        expect($("bellCount").hidden, "пришедшее при открытой панели — не прочитано");
        await click($("bellTabs").querySelector('[data-bell-tab="action"]'));
        expect(!noticeWith(/Связь восстановлена/), "на вкладке «Нужно действие» — записи «Система»");
        await click($("bellTabs").querySelector('[data-bell-tab="all"]'));
        await click($("bellClose"));
        expect($("bellPanel").hidden && !$("bellList").querySelector(".unread"), "после закрытия выделение осталось");
        return text;
      } finally {
        await postCleanup();
      }
    }, SOUND_FIRST);

    await step("Колокольчик: журнал в браузере — после перезагрузки записи на месте, ключ — организация и оператор, старше noticeKeepHours — выброшены, испорченный — пустой журнал (§22.5)", async () => {
      const ui = window.IM_SELFTEST_UI;
      const key = ui.noticeKey();
      const me = window.IM_SELFTEST_API && (await window.IM_SELFTEST_API.get("/operator/session")).operator.guid;
      expect(key === `im.notices.local.${me}`, `ключ журнала: ${key}`);
      const saved = localStorage.getItem(key);
      const list = JSON.parse(saved || "[]");
      expect(list.some((n) => n.text === "Связь восстановлена" && n.kind === "system"), `в браузере нет записей: ${(saved || "").slice(0, 200)}`);
      try {
        const old = Date.now() - (window.IM_WORKFLOW.display.noticeKeepHours + 1) * 3600e3;
        localStorage.setItem(key, JSON.stringify(list.concat([{ id: "old-1", at: old, text: "Запись старше срока <b>x</b>", kind: "info", read: false }])));
        ui.noticeReload();
        const all = [...$("bellList").querySelectorAll("[data-notice]")].map((li) => li.textContent);
        expect(all.some((x) => /Связь восстановлена/.test(x)), `после перезагрузки журнала записей нет: ${all.join(" | ")}`);
        expect(!all.some((x) => /старше срока/.test(x)), "запись старше noticeKeepHours осталась");
        // Имена в записи — текстом, не разметкой
        localStorage.setItem(key, JSON.stringify([{ id: "x-1", at: Date.now(), text: "Перехватил <img src=x onerror=alert(1)>", kind: "info", read: false }]));
        ui.noticeReload();
        const li = $("bellList").querySelector("[data-notice]");
        expect(li && !li.querySelector("img") && /<img/.test(li.textContent), "текст записи попал в разметку");
        expect($("bellCount").textContent === "1" && !$("bellCount").hidden, `число непрочитанных: ${$("bellCount").textContent}`);
        localStorage.setItem(key, "{испорчено");
        ui.noticeReload();
        expect($("bellCount").hidden && $("bellList").querySelector(".notice-empty"), "испорченный журнал — не пустой");
        // Другой оператор того же браузера свои записи не видит: ключ — свой
        expect(!localStorage.getItem(`im.notices.local.petrova`) || !/Связь восстановлена/.test(localStorage.getItem(`im.notices.local.petrova`)), "записи оператора под чужим ключом");
        return key;
      } finally {
        if (saved == null) localStorage.removeItem(key);
        else localStorage.setItem(key, saved);
        ui.noticeReload();
      }
    }, POST_STEP);

    await step("Шапка: строка поста, плашка итога и звенящий значок с «Тихо» не меняют её высоту на 1560, 1280 и 1024 px; на телефоне значок и «Тихо» — в первой строке, плашка — под шапкой; от пункта поста видны значок и кнопки, у плашки — «✕» (§21.4, §22.1, §22.4, §22.6)", async () => {
      // Разметка — с экрана: «Только важное» с «Вернуть»; два состояния («Нет связи» и «и ещё 1»); длинный текст работ;
      // звенит — значок звука красный, слева «Тихо»
      let oneHtml = "";
      let twoHtml = "";
      try {
        await onlyImportantOn();
        oneHtml = $("postStatus").innerHTML;
        await heartbeatDown(true);
        twoHtml = $("postStatus").innerHTML;
      } finally {
        await postCleanup();
      }
      expect(/data-sound-back/.test(oneHtml) && /и ещё 1/.test(twoHtml), `нет пунктов: ${oneHtml.slice(0, 80)} / ${twoHtml.slice(0, 80)}`);
      const longText = "Идут плановые работы: Камера 12 на складе готовой продукции — «замена датчика дыма в зоне погрузки», до 14:00.";
      const longErr = "Закрыто: 120. Не закрыты: 450 — другой сценарий: INC-26103, INC-26104 и ещё 448. Не выполнено: 3. INC-26110: Инцидент уже изменён";
      const errHtml = `<div class="toast error" data-kind="error" title="${longErr}"><span class="toast-text">${longErr}</span><span class="toast-more" data-toast-more="ещё 2"></span><button type="button" class="toast-close"></button></div>`;
      const bar = document.querySelector(".topbar").cloneNode(true);
      bar.querySelectorAll("[id]").forEach((el) => el.removeAttribute("id"));
      bar.querySelector(".post-status").setAttribute("hidden", "");
      bar.querySelector(".post-status").innerHTML = "";
      const base = location.href.replace(/[?#].*$/, "").replace(/[^/]*$/, "");
      // Шрифт значков в headless не грузится — значок рисуется словом («notifications»); ширина — как у шрифта, 24 px
      const icons = ".material-symbols-outlined { display: inline-block; width: 24px; overflow: hidden; white-space: nowrap; }";
      const out = [];
      for (const width of [1560, 1280, 1024, 360]) {
        const phone = width <= 600;
        const frame = document.createElement("iframe");
        frame.style.cssText = `position:fixed;left:-9999px;top:0;width:${width}px;height:300px;border:0`;
        const loaded = new Promise((resolve) => {
          frame.onload = resolve;
          setTimeout(resolve, 5000);
        });
        frame.srcdoc = `<!DOCTYPE html><html lang="ru" data-theme="${document.documentElement.dataset.theme}"><head><meta charset="UTF-8"><base href="${base}"><link rel="stylesheet" href="styles.css"><link rel="stylesheet" href="bridge.css"><style>${icons}</style></head><body><div class="app">${bar.outerHTML}</div></body></html>`;
        document.body.appendChild(frame);
        await loaded;
        try {
          const doc = frame.contentDocument;
          const top = doc.querySelector(".topbar");
          const ps = doc.querySelector(".post-status");
          const btn = doc.querySelector(".topbar-actions .sound-btn");
          const quiet = doc.querySelector(".sound-quiet");
          const bell = doc.querySelector(".bell-btn");
          const rect = (el) => el.getBoundingClientRect();
          const h = () => Math.round(rect(top).height * 10) / 10;
          const plaque = doc.querySelector(".toast-stack");
          const set = (post, long, ringOn, err) => {
            plaque.innerHTML = err ? errHtml : "";
            ps.innerHTML = post || "";
            ps.hidden = !post;
            if (post && long) ps.querySelector(".post-text").textContent = longText;
            btn.dataset.ringing = ringOn ? "on" : "off";
            quiet.innerHTML = ringOn ? '<button type="button" class="btn small outline" data-sound-silence>Тихо</button>' : "";
            quiet.hidden = !ringOn;
            window.IM_SELFTEST_UI.fitHead(doc);
            return h();
          };
          const inside = (el, box) => {
            const a = rect(el);
            const b = rect(box);
            return a.width > 0 && a.left >= b.left - 1 && a.right <= b.right + 1;
          };
          const empty = set("", false, false);
          const got = { one: set(oneHtml, false, false), two: set(twoHtml, false, false), long: set(twoHtml, true, false) };
          const bellAt = Math.round(rect(bell).left);
          for (const [name, html] of [["ring", ""], ["one+ring", oneHtml], ["two+ring", twoHtml]]) {
            got[name] = set(html, true, true);
            const q = quiet.querySelector("[data-sound-silence]");
            expect(rect(btn).width > 0 && rect(q).width > 0, `${width} px, ${name}: звенящий значок или «Тихо» не видны`);
            // «Тихо» — слева от значка, вплотную; колокольчик на месте (§21.4)
            expect(rect(q).right <= rect(btn).left + 1 && rect(btn).left - rect(q).right < 16, `${width} px, ${name}: «Тихо» не рядом со значком`);
            if (!phone) expect(Math.round(rect(bell).left) === bellAt, `${width} px, ${name}: колокольчик сдвинулся ${bellAt} → ${Math.round(rect(bell).left)}`);
            // На телефоне значок и «Тихо» — в первой строке, с колокольчиком
            const mid = (el) => (rect(el).top + rect(el).bottom) / 2;
            // На телефоне строка поста и значок меню звука — одной второй строкой (плашка итога между ними в разметке
            // её не разрывает, BUG-123)
            const bar2 = doc.querySelector(".sound-bar");
            if (phone && html && rect(bar2).width > 0) expect(Math.abs(mid(ps) - mid(bar2)) < 4, `${width} px, ${name}: строка поста и значок меню звука — не одной строкой`);
            if (phone) expect(Math.abs(mid(btn) - mid(bell)) < 4 && Math.abs(mid(q) - mid(bell)) < 4, `${width} px, ${name}: значок или «Тихо» не в первой строке (${Math.round(mid(btn))}, ${Math.round(mid(q))} при колокольчике ${Math.round(mid(bell))})`);
            if (html) {
              const item = ps.querySelector(".post-item");
              const icon = item.querySelector('[aria-hidden="true"]');
              expect(inside(icon, ps), `${width} px, ${name}: значок пункта обрезан`);
              item.querySelectorAll("button.btn, .post-more").forEach((b) => expect(inside(b, ps), `${width} px, ${name}: кнопка пункта «${b.textContent.trim()}» вне строки поста`));
              if (!phone) expect(rect(ps).right <= rect(doc.querySelector(".topbar-actions")).left + 1, `${width} px, ${name}: строка поста заходит на кнопки шапки`);
              expect(item.title.length > 0, `${width} px, ${name}: у пункта нет подсказки с полным текстом`);
            }
          }
          // Плашка итога (§22.6, BUG-123): длинная ошибка с «ещё N» при длинной строке поста и звоне — справа от строки
          // поста (узкое окно — под шапкой во всю ширину), одной строкой; «✕» и значок пункта поста на экране
          for (const [name, html, ringOn] of [["err", "", false], ["long+err", twoHtml, false], ["long+err+ring", twoHtml, true]]) {
            got[name] = set(html, true, ringOn, true);
            const pl = plaque.querySelector(".toast");
            const x = pl.querySelector(".toast-close");
            const more = pl.querySelector(".toast-more");
            expect(rect(pl).height <= 32, `${width} px, ${name}: плашка в ${Math.round(rect(pl).height)} px — не одной строкой`);
            expect(rect(x).width > 0 && rect(x).right <= width && inside(x, pl) && inside(more, pl), `${width} px, ${name}: «✕» или «ещё N» не на плашке`);
            if (html) expect(inside(ps.querySelector('.post-item [aria-hidden="true"]'), ps), `${width} px, ${name}: значок пункта поста обрезан`);
            if (width > 900) {
              expect(rect(pl).top >= rect(top).top && rect(pl).bottom <= rect(top).bottom, `${width} px, ${name}: плашка не в шапке`);
              expect(rect(pl).right <= rect(doc.querySelector(".topbar-actions")).left + 1, `${width} px, ${name}: плашка заходит на кнопки шапки`);
              if (html) expect(rect(pl).left >= rect(ps).right - 1, `${width} px, ${name}: плашка не справа от строки поста`);
            } else {
              expect(Math.abs(rect(pl).top - rect(top).bottom - 6) <= 1 && rect(pl).width >= width - 17, `${width} px, ${name}: плашка не под шапкой во всю ширину (${Math.round(rect(pl).top)}, ${Math.round(rect(pl).width)} px)`);
            }
          }
          // Высота шапки — та же при любом наборе; на телефоне — та же, что без звона, при той же строке поста
          if (!phone) {
            const bad = Object.entries(got).filter(([, v]) => Math.abs(v - empty) > 0.5);
            expect(empty > 0 && !bad.length, `${width} px: без пунктов ${empty} px, ${bad.map(([k, v]) => `${k} ${v} px`).join(", ")}`);
          } else {
            expect(Math.abs(got["two+ring"] - got.long) <= 0.5 && Math.abs(got.ring - empty) <= 0.5, `${width} px: высота шапки при звоне ${got.ring}/${got["two+ring"]} px, без — ${empty}/${got.long} px`);
          }
          // Ничего не уходит за правый край шапки
          const over = [...top.querySelectorAll("*")].filter((el) => el.getClientRects().length && rect(el).right > width + 1).map((el) => el.className || el.tagName);
          expect(!over.length, `${width} px: за краем шапки ${over.slice(0, 3).join(", ")}`);
          out.push(`${width}: ${empty} px`);
        } finally {
          frame.remove();
        }
      }
      return out.join("; ");
    }, POST_STEP);

    await step("Звук: Критический — сирена, повтор каждые 15 с, «Тихо» глушит (§21.2, §21.4)", async () => {
      const before = heard("siren");
      await soundIncident(100);
      expect(heard("siren") === before + 1, `новый Критический: сирен ${heard("siren") - before}`);
      const crit = window.IM_FIXTURE.priorities.find((p) => p.value === 100).name.ru;
      expect(ringOn() && quietBtn() && $("soundBtn").title.startsWith(`Звучит — ${crit}`), `значок: звенит ${ringOn()}, «Тихо» ${quietBtn() ? "есть" : "нет"}, подсказка «${$("soundBtn").title}»`);
      expect(!$("soundBar").textContent.includes("Звучит") && !document.querySelector(".topbar [data-sound-go]:not(#soundBtn)"), `в шапке осталась строка «Звучит»: ${$("soundBar").textContent}`);
      const inc = { guid: ringGuid() };
      const mark = rowSoundOf(inc.guid);
      expect(!$("eventsList").querySelector(`[data-id="${CSS.escape(inc.guid)}"]`) || (mark && mark.title === `Звучит — ${crit}`), `значок звучащей строки: ${mark ? mark.title : "нет"}`);
      await soundAdvance(45);
      expect(heard("siren") === before + 4, `за 45 с повторов ${heard("siren") - before - 1}, ждали 3`);
      // Щелчок по звенящему значку — к звучащему инциденту, не меню (§21.4)
      await click($("soundBtn"));
      await wait(200);
      const picked = $("eventsList").querySelector(".selected");
      expect($("soundPop").hidden && picked && picked.dataset.id === inc.guid, `щелчок по значку: меню ${$("soundPop").hidden ? "закрыто" : "открыто"}, выбран ${picked ? picked.dataset.id : "никто"}`);
      await click(quietBtn());
      expect(!ringOn() && !quietBtn() && !rowSoundOf(inc.guid), "после «Тихо» значок звенит или «Тихо» и значок строки остались");
      const all = heard();
      await soundAdvance(60);
      expect(heard() === all, `после «Тихо» за 60 с прозвучало ещё ${heard() - all}`);
      // Тихо — значок снова открывает меню
      await click($("soundBtn"));
      expect(!$("soundPop").hidden, "после «Тихо» значок не открывает меню");
      await click($("soundBtn"));
      // Переход прокрутил список к звучавшему — следующие шаги начинают с верха списка, как до перехода
      $("eventsList").scrollTop = 0;
      return $("soundIcon").textContent;
    }, SOUND_FIRST);

    await step("Звук: «лично вам» — передача коллегой звучит колоколом, «Принять» снимает повтор (§21.1, §21.2)", async () => {
      const stand = window.IM_SELFTEST_API;
      const inc = await soundIncident(50);
      const as = (tr, formValues, surface) => stand.raw("POST", `/test/operators/petrova/incidents/${encodeURIComponent(inc.guid)}/transitions/${tr}`, { formValues: formValues || {}, surface: surface || "card" });
      expect((await as("claim", {}, "queue")).status === 200, "Петрова не взяла");
      const before = heard("bell");
      const sent = await as("transfer", { targetId: "me", comment: NOTE });
      expect(sent.status === 200, `Петрова не передала мне: ${sent.status}`);
      await wait(200);
      expect(heard("bell") === before + 1, `передача мне: колоколов ${heard("bell") - before}`);
      // Строка блока «Мне на принятие» — со значком динамика «лично вам» (§22.3)
      const blockMark = document.querySelector(`#eventsList .inbox-block [data-id="${CSS.escape(inc.guid)}"] [data-row-sound]`);
      expect(blockMark && blockMark.title === "Звучит — лично вам", `значок строки блока: ${blockMark ? blockMark.title : "нет"}`);
      await setFilter("inbox");
      const b = await buttonOnPages("accept", inc.guid);
      expect(b, `${inc.number} нет в «Мне на принятие»`);
      await click(b);
      await wait(200);
      if (mode() === "work") await click($("backToQueue"));
      expect(ringGuid() !== inc.guid && !rowSoundOf(inc.guid), "после «Принять» звучит принятый");
      const bells = heard("bell");
      await soundAdvance(60);
      expect(heard("bell") === bells, `после «Принять» колоколов ещё ${heard("bell") - bells}`);
      await setFilter("open");
      return inc.number;
    }, SOUND_FIRST);

    await step("Звук: заголовок вкладки «(N) …» — непринятые Критические и «лично вам»; взял — число меньше (§21.6)", async () => {
      const n0 = titleN();
      const inc = await soundIncident(100);
      expect(titleN() === n0 + 1, `заголовок «${document.title}», до было ${n0}`);
      const b = await buttonOnPages("claim", inc.guid);
      expect(b, `у ${inc.number} нет «Взять»`);
      await click(b);
      await wait(200);
      if (mode() === "work") await click($("backToQueue"));
      expect(titleN() === n0, `после «Взять» заголовок «${document.title}», ждали ${n0}`);
      return document.title;
    }, SOUND_FIRST);

    await step("Звук: событие во время перечитывания очереди не теряется — взятый за это время Критический не повторяется (§21.1)", async () => {
      const stand = window.IM_SELFTEST_API;
      const n0 = titleN();
      const inc = await soundIncident(100);
      expect(titleN() === n0 + 1, `новый Критический: заголовок «${document.title}», до было ${n0}`);
      const card = await stand.raw("GET", `/operator/incidents/${encodeURIComponent(inc.guid)}`);
      // Ответ на перечитывание очереди задержан: очередь прочитана до взятия, а событие взятия приходит раньше ответа
      const get = stand.get;
      let release = null;
      const gate = new Promise((resolve) => (release = resolve));
      stand.get = (path, params) => {
        const res = get(path, params);
        return path === "/operator/incidents" && params && params.pageSize === 200 ? res.then((v) => gate.then(() => v)) : res;
      };
      try {
        window.dispatchEvent(new Event("im-sound-restore"));
        await wait(20);
        const took = await stand.raw("POST", `/operator/incidents/${encodeURIComponent(inc.guid)}/transitions/claim`, Object.assign({ formValues: {}, surface: "queue" }, seenBody(card.body)));
        expect(took.status === 200, `«Взять»: ${took.status}`);
        await wait(150);
      } finally {
        stand.get = get;
        release();
      }
      await wait(200);
      expect(titleN() === n0 && ringGuid() !== inc.guid, `после перечитывания: заголовок «${document.title}» (ждали ${n0}), звучит ${ringGuid()}`);
      return inc.number;
    }, SOUND_FIRST);

    await step("Звук: значок вкладки мигает, пока есть непринятые (§21.6)", async () => {
      const link = document.querySelector('link[rel="icon"]');
      expect(titleN() > 0, `непринятых нет: «${document.title}»`);
      expect(link && link.dataset.blink === "on", `значок вкладки: ${link ? link.dataset.blink : "нет"}`);
      const a = link.dataset.state;
      // Смену ждём опросом с пределом: период мигания 1 с, шаг ожидания и загрузка страницы его сдвигают
      let b = a;
      for (let waited = 0; waited < 2500 && b === a; waited += 100) {
        await wait(100);
        b = link.dataset.state;
      }
      expect(a !== b && [a, b].includes("alert"), `значок не мигает: ${a} → ${b}`);
      return `${a} → ${b}`;
    }, SOUND_FIRST);

    await step("Бледная строка: курсор над списком, инцидент выше закрыт — строка на месте, бледная, «Закрыт — Петрова М.», без состояния, меток, таймера и кнопок; курсор ушёл — строки нет (§22.1, BUG-121)", async () => {
      const stand = window.IM_SELFTEST_API;
      await standReset({ fixture: "demo", workflowPatch: { limits: { maxActive: null } } });
      await wait(400);
      if (mode() !== "queue") await click($("backToQueue"));
      await setFilter("open");
      const list = $("eventsList");
      const rows = () => [...list.querySelectorAll("article.event")];
      // Выше строки под курсором — новый инцидент с таймером реакции: его закроем
      const items = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items;
      const at = rows().findIndex((r, i) => i > 0 && i < rows().length - 1 && (items.find((e) => e.guid === r.dataset.id) || {}).state === "new");
      expect(at > 0, "в списке нет нового инцидента между строками");
      const target = rows()[at].dataset.id;
      const anchor = rows()[at + 1];
      expect(rows()[at].querySelector("[data-timer], .badge"), "у строки до закрытия нет состояния или таймера");
      anchor.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
      try {
        // Закрывает другой оператор: строка уходит по событию потока, причина — кто закрыл
        expect((await petrovaAct(target, "claim")).status === 200, "Петрова не взяла инцидент");
        const close = await petrovaAct(target, "close", { resultId: "false_alarm", causeId: "animal" });
        expect(close.status === 200, `закрытие Петровой: ${close.status} ${close.body && close.body.code}`);
        await wait(100);
        const row = list.querySelector(`[data-id="${CSS.escape(target)}"]`);
        expect(row && row.classList.contains("gone"), `закрытая строка выше курсора: ${row ? row.className : "нет"}`);
        const why = row.querySelector("[data-gone-why]");
        expect(why && why.textContent.trim() === "Закрыт — Петрова М.", `причина: «${why ? why.textContent.trim() : "нет"}»`);
        const stale = row.querySelectorAll(".badge, .chip.lvl, [data-timer], [data-due], .event-act, [data-row-sound], .event-open");
        expect(!stale.length, `на бледной строке устаревшее: ${[...stale].map((x) => x.className).join(", ")}`);
        const pick = row.querySelector("input.pick");
        expect(!pick || pick.disabled, "у бледной строки можно отметить флажок");
      } finally {
        list.dispatchEvent(new MouseEvent("mouseleave"));
      }
      await wait(200);
      expect(!list.querySelector(`[data-id="${CSS.escape(target)}"]`), "курсор ушёл, а закрытая строка осталась");
    });

    await step("Бледная строка: своё закрытие — «Закрыт вами»; строка блока «Мне на принятие», которую я отклонил, — «Ушёл из блока», без меток и таймера (§22.1, BUG-121)", async () => {
      const stand = window.IM_SELFTEST_API;
      await standReset({ fixture: "demo", workflowPatch: { limits: { maxActive: null } } });
      await wait(400);
      if (mode() !== "queue") await click($("backToQueue"));
      await setFilter("open");
      const list = $("eventsList");
      const rows = () => [...list.querySelectorAll("article.event")];
      const items = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items;
      const at = rows().findIndex((r, i) => i > 0 && i < rows().length - 1 && (items.find((e) => e.guid === r.dataset.id) || {}).state === "new");
      expect(at > 0, "в списке нет нового инцидента между строками");
      const target = rows()[at].dataset.id;
      rows()[at + 1].dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
      try {
        // Своё действие служебной операцией: поток о своём переходе очередь не перечитывает — перечитывает смена фильтра
        await standClaim(stand, target);
        const card = await stand.raw("GET", `/operator/incidents/${encodeURIComponent(target)}`);
        const close = await stand.raw("POST", `/operator/incidents/${encodeURIComponent(target)}/transitions/close`, Object.assign({ formValues: { resultId: "false_alarm", causeId: "animal" }, surface: "card" }, seenBody(card.body)));
        expect(close.status === 200, `своё закрытие: ${close.status} ${close.body && close.body.code}`);
        await wait(200);
        await setFilter("open");
        await wait(100);
        const row = list.querySelector(`[data-id="${CSS.escape(target)}"]`);
        const why = row && row.querySelector("[data-gone-why]");
        expect(row && row.classList.contains("gone") && why && why.textContent.trim() === "Закрыт вами", `своё закрытие: ${row ? row.className : "строки нет"}, «${why ? why.textContent.trim() : "нет"}»`);
      } finally {
        list.dispatchEvent(new MouseEvent("mouseleave"));
      }
      await wait(200);
      // Блок: курсор над ним держит весь блок; строку блока я отклонил — она ушла из блока (может быть ниже, в списке)
      const blockRow = list.querySelector(".inbox-row");
      expect(blockRow, "блок «Мне на принятие» пуст");
      const guid = blockRow.dataset.id;
      expect(blockRow.querySelector(".badge, [data-due]"), "у строки блока до ухода нет состояния или таймера");
      blockRow.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
      try {
        const card = await stand.raw("GET", `/operator/incidents/${encodeURIComponent(guid)}`);
        const rejected = await stand.raw("POST", `/operator/incidents/${encodeURIComponent(guid)}/transitions/reject`, Object.assign({ formValues: { comment: "тест" }, surface: "queue" }, seenBody(card.body)));
        expect(rejected.status === 200, `отклонить строку блока: ${rejected.status} ${rejected.body && rejected.body.code}`);
        await wait(200);
        await setFilter("open");
        await wait(100);
        const row = list.querySelector(`.inbox-row[data-id="${CSS.escape(guid)}"]`);
        const why = row && row.querySelector("[data-gone-why]");
        expect(row && row.classList.contains("gone") && why && why.textContent.trim() === "Ушёл из блока", `строка блока: ${row ? row.className : "нет"}, «${why ? why.textContent.trim() : "нет"}»`);
        const stale = row.querySelectorAll(".badge, .chip.lvl, [data-due], .event-act, [data-row-sound]");
        expect(!stale.length, `на бледной строке блока устаревшее: ${[...stale].map((x) => x.className).join(", ")}`);
      } finally {
        list.dispatchEvent(new MouseEvent("mouseleave"));
      }
    });

    await step("Новые строки: курсор над списком — новая строка не сдвигает список, «↑ 1 новый»; курсор ушёл — строка на месте и подсвечена (§22.1, §22.3)", async () => {
      // Демо-данные заново: Критические прошлых шагов заняли бы всю первую страницу
      await standReset({ fixture: "demo", workflowPatch: { limits: { maxActive: null } } });
      await wait(400);
      await setFilter("open");
      const list = $("eventsList");
      const rows = () => [...list.querySelectorAll("article.event")];
      const at = (el) => el.getBoundingClientRect().top - list.getBoundingClientRect().top + list.scrollTop;
      expect(rows().length >= 2, `в списке ${rows().length} строк`);
      // Курсор — над строкой ниже Критических: новый Критический сервер ставит выше неё
      const crit = (await window.IM_SELFTEST_API.get("/operator/reference/priorities")).find((p) => p.value === 100);
      const anchor = rows().find((x) => (x.querySelector(".pri-name") || {}).textContent !== crit.name.ru);
      expect(anchor, "в списке нет строки ниже Критических");
      const guid = anchor.dataset.id;
      const above = rows().slice(0, rows().indexOf(anchor) + 1).map((x) => x.dataset.id);
      const y = at(anchor);
      anchor.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
      let inc;
      try {
        inc = await soundIncident(100);
        await wait(150);
        const now = rows().map((x) => x.dataset.id);
        const row = list.querySelector(`[data-id="${CSS.escape(guid)}"]`);
        expect(now.slice(0, above.length).join() === above.join(), `строки выше курсора сдвинулись: ${now.slice(0, above.length).join()} вместо ${above.join()}`);
        expect(row && Math.abs(at(row) - y) < 1, `строка под курсором сдвинулась: ${row ? at(row) : "нет"} вместо ${y}`);
        const banner = document.querySelector("[data-new-rows]");
        expect(banner && /↑\s*1\s/.test(banner.textContent), `«↑ 1 новый»: ${banner ? banner.textContent : "нет"}`);
      } finally {
        list.dispatchEvent(new MouseEvent("mouseleave"));
      }
      await wait(200);
      const row = list.querySelector(`[data-id="${CSS.escape(inc.guid)}"]`);
      expect(row && !document.querySelector("[data-new-rows]"), `после ухода курсора: строки ${row ? "есть" : "нет"}, «↑ новых» ${document.querySelector("[data-new-rows]") ? "есть" : "нет"}`);
      // Подсветка — с того момента, как строка показалась в видимой части списка, а не с прихода (§22.3)
      const box = list.getBoundingClientRect();
      const r = row.getBoundingClientRect();
      if (r.bottom <= box.top || r.top >= box.bottom) {
        expect(!row.classList.contains("fresh"), "строка за прокруткой уже подсвечена");
        row.scrollIntoView({ block: "nearest" });
        // Событие прокрутки браузер шлёт в кадре отрисовки, а его в headless с виртуальным временем нет
        list.dispatchEvent(new Event("scroll"));
        await wait(100);
      }
      expect(list.querySelector(`[data-id="${CSS.escape(inc.guid)}"]`).classList.contains("fresh"), "новая строка не подсвечена");
      expect(ringOn() && rowSoundOf(inc.guid), "новый Критический на виду: значок не звенит или у строки нет значка динамика");
      await click(quietBtn());
      return `${inc.number} — над ${guid}`;
    }, SOUND_FIRST);

    // Набор — после шага выше (сброс там же): лишний сброс стоит секунд бюджета CI
    await step("«↑ N новых выше — показать» — своё место над списком: не перекрывает ни одной строки на широкой и узкой панели, компактная, по центру; путь курсора строка → блок → кнопка список не отпускает, щелчок — строки на местах (§22.1, §22.3, BUG-122)", async () => {
      if (quietBtn()) await click(quietBtn());
      const list = $("eventsList");
      const panel = list.closest("section");
      const rows = () => [...list.querySelectorAll("article.event, .inbox-row")];
      const crit = (await window.IM_SELFTEST_API.get("/operator/reference/priorities")).find((p) => p.value === 100);
      const anchor = [...list.querySelectorAll("article.event")].find((x) => (x.querySelector(".pri-name") || {}).textContent !== crit.name.ru);
      expect(anchor, "в списке нет строки ниже Критических");
      anchor.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
      // Видимая часть строки — внутри окна списка: строка, ушедшая прокруткой вверх, под кнопкой не считается
      const cross = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
      const seen = (el) => {
        const r = el.getBoundingClientRect(), v = list.getBoundingClientRect();
        const c = { left: Math.max(r.left, v.left), right: Math.min(r.right, v.right), top: Math.max(r.top, v.top), bottom: Math.min(r.bottom, v.bottom) };
        return c.right > c.left && c.bottom > c.top ? c : null;
      };
      const check = (where) => {
        const btn = document.querySelector("[data-new-rows]");
        expect(btn, `${where}: кнопки «↑ новых» нет`);
        const b = btn.getBoundingClientRect(), l = list.getBoundingClientRect();
        const hit = rows().filter((x) => { const c = seen(x); return c && cross(b, c); });
        expect(!hit.length, `${where}: кнопка перекрывает строки ${hit.map((x) => x.dataset.id || x.className).join(", ")}`);
        expect(b.width < l.width * 0.8, `${where}: кнопка во всю ширину — ${Math.round(b.width)} из ${Math.round(l.width)} px`);
        expect(Math.abs((b.left + b.right) / 2 - (l.left + l.right) / 2) < 3, `${where}: кнопка не по центру списка`);
        expect(b.right <= l.right + 1 && b.left >= l.left - 1, `${where}: кнопка за краем списка`);
        const st = $("newRows").getBoundingClientRect();
        expect(b.top >= st.top - 1 && b.bottom <= st.bottom + 1, `${where}: кнопка не помещается в свою полосу — ${Math.round(b.height)} px при полосе ${Math.round(st.height)}`);
      };
      const width = panel.style.width;
      let inc;
      try {
        // Путь к кнопке — через блок «Мне на принятие»: заморозка, начатая на строке списка, держится и над блоком
        const blockRow = list.querySelector(".inbox-block .inbox-row");
        expect(blockRow, "блок «Мне на принятие» пуст — путь через блок не проверить");
        blockRow.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
        inc = await soundIncident(100);
        await wait(150);
        const btn = document.querySelector("[data-new-rows]");
        expect(btn && !list.querySelector(`[data-id="${CSS.escape(inc.guid)}"]`), `курсор над блоком — список отпущен: «${btn ? btn.textContent.trim() : "кнопки нет"}», ${inc.number} ${list.querySelector(`[data-id="${CSS.escape(inc.guid)}"]`) ? "в списке" : "не в списке"}`);
        expect(/^↑ 1 новый выше — показать$/.test(btn.textContent.trim()), `текст кнопки: «${btn.textContent.trim()}»`);
        check("широкая");
        list.scrollTop = 60;
        await wait(50);
        check("широкая, список прокручен");
        list.scrollTop = 0;
        panel.style.width = "340px";
        await wait(50);
        check("узкая (340 px)");
        // С блока на кнопку — список не отпущен
        list.dispatchEvent(new MouseEvent("mouseleave", { relatedTarget: btn }));
        await wait(100);
        const still = document.querySelector("[data-new-rows]");
        expect(still && !list.querySelector(`[data-id="${CSS.escape(inc.guid)}"]`), `курсор перешёл на кнопку — список отпущен: кнопка ${still ? "есть" : "нет"}`);
        await click(still);
        await wait(150);
        expect(list.querySelector(`[data-id="${CSS.escape(inc.guid)}"]`) && !document.querySelector("[data-new-rows]"), "после щелчка по кнопке: новой строки нет или кнопка осталась");
        return `${inc.number}`;
      } finally {
        panel.style.width = width;
        list.dispatchEvent(new MouseEvent("mouseleave"));
        if (quietBtn()) await click(quietBtn());
      }
    }, SOUND_FIRST);

    await step("Скрыт фильтром: «Мои» + новый Критический — значок звенит, на кнопках только числа, без «+N»; щелчок по значку — строка видна (§22.3)", async () => {
      if (quietBtn()) await click(quietBtn());
      await setFilter("mine");
      const inc = await soundIncident(100);
      await wait(150);
      try {
        expect(ringGuid() === inc.guid && !$("eventsList").querySelector(`[data-id="${CSS.escape(inc.guid)}"]`), `звенит ${ringGuid()}, ждали ${inc.guid} скрытым`);
        const marks = [...$("stateButtons").querySelectorAll("button"), ...$("priorityButtons").querySelectorAll("button"), ...$("eventFilter").options].filter((b) => /\+\d/.test(b.textContent));
        expect(!marks.length, `«+N» на кнопках: ${marks.map((b) => b.textContent).join(", ")}`);
        await click($("soundBtn"));
        await wait(200);
        const row = $("eventsList").querySelector(`[data-id="${CSS.escape(inc.guid)}"]`);
        expect($("eventFilter").value === "open" && row && row.querySelector("[data-row-sound]"), `после щелчка по значку: состояние ${$("eventFilter").value}, строки ${row ? "есть" : "нет"}`);
        expect($("soundPop").hidden, "щелчок по звенящему значку открыл меню");
        return inc.number;
      } finally {
        if (quietBtn()) await click(quietBtn());
        await setFilter("open");
      }
    }, SOUND_FIRST);

    await step("Звук: громкость в меню не ниже порога схемы, «Проверить звук» играет с ней (§21.4)", async () => {
      const floor = window.IM_WORKFLOW.sound.volumeFloor;
      const was = window.IMSound.loadVolume();
      await soundMenuOpen();
      const range = $("soundVolume");
      expect(range && Number(range.min) === floor, `ползунок: ${range ? range.min : "нет"}`);
      try {
        range.value = "0";
        range.dispatchEvent(new Event("input", { bubbles: true }));
        expect(Number(range.value) >= floor && window.IMSound.loadVolume() >= floor, `громкость ниже порога: ${range.value}, сохранено ${window.IMSound.loadVolume()}`);
        const n = fakeSound.rec.length;
        await click($("soundPop").querySelector("[data-sound-test]"));
        const last = fakeSound.rec[fakeSound.rec.length - 1];
        expect(fakeSound.rec.length > n && last.pattern === window.IMSound.TEST_PATTERN && last.volume >= floor, `«Проверить звук»: ${last ? `${last.pattern} ${last.volume}%` : "нет"}`);
        return `${$("soundVolumeOut").textContent}, порог ${floor}%`;
      } finally {
        range.value = String(was);
        range.dispatchEvent(new Event("input", { bubbles: true }));
        document.body.click();
      }
    }, SOUND_FIRST);

    await step("Звук: вкладка «Звук» настроек — строки уровней справочника, ▶ «Прослушать» играет (§21.2, §20)", async () => {
      try {
        $("adminBtn").click();
        await wait(200);
        const tab = $("adminTabs").querySelector('[data-admin-tab="sound"]');
        expect(tab, "нет вкладки «Звук»");
        await click(tab);
        await wait(150);
        const levels = (await window.IM_SELFTEST_API.get("/operator/reference/priorities")).map((p) => String(p.value));
        const rows = [...$("adminTable").querySelectorAll("[data-sound-level]")].map((r) => r.dataset.soundLevel);
        expect(rows.length === levels.length && levels.every((l) => rows.includes(l)), `строки уровней: ${rows.join(", ")}; справочник: ${levels.join(", ")}`);
        const play = $("adminTable").querySelector("[data-sound-play]");
        expect(play, "нет ▶ «Прослушать»");
        const n = fakeSound.rec.length;
        await click(play);
        expect(fakeSound.rec.length === n + 1 && fakeSound.rec[n].pattern === play.dataset.soundPlay, `▶: ${fakeSound.rec.slice(n).map((r) => r.pattern).join(", ") || "ничего"}`);
        return `уровней ${rows.length}, ▶ ${play.dataset.soundPlay}`;
      } finally {
        if (!$("modalAdmin").hidden) document.querySelector('[data-close="modalAdmin"]').click();
        // Вывод — снова настоящий, стенд — как был
        window.IMSound.output = window.IMSound.webAudio();
        window.dispatchEvent(new Event("im-sound-output"));
        if (mode() !== "queue") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(100);
        await setFilter("open");
      }
    }, SOUND_FIRST);

    // Сброс стенда меняет данные — шаг в конце, чтобы не трогать шаги выше
    await step("Состояние системы без права: пункта настроек нет, запрос — 403 (§5, §20)", async () => {
      // Без права: раздела (и всей админки) нет, запрос — 403
      const stand = window.IM_SELFTEST_API;
      await standReset({ fixture: "demo", operatorPermissions: window.IM_WORKFLOW.permissions.map((p) => p.key).filter((k) => k !== "incident:schema:admin") });
      await wait(600);
      const denied = await stand.raw("GET", "/operator/admin/system-status");
      expect(denied.status === 403, `без права — ${denied.status}, а не 403`);
      expect($("adminBtn").hidden, "без права пункт настроек виден");
      await standReset({ fixture: "demo" });
      await wait(600);
      expect(!$("adminBtn").hidden, "право не вернулось");
    });

    await step("Ответы встроенного сервера соответствуют openapi.json", async () => {
      expect(window.IM_OPENAPI, "контракт openapi.js не подключён");
      const recorded = window.IM_RECORDED || [];
      expect(recorded.length, "встроенный сервер не записал ни одного ответа");
      const problems = IMContract.problems(window.IM_OPENAPI, recorded);
      expect(!problems.length, `расхождений ${problems.length}: ${problems.slice(0, 12).join("; ")}`);
      return `${recorded.length} ответов`;
    });


    report();
  }

  function report() {
    const failed = results.filter((r) => !r.ok).length;
    const skipped = results.filter((r) => r.skipped).length;
    const lines = results.map((r) => `${r.skipped ? "SKIP" : r.ok ? "PASS" : "FAIL"}  ${r.name}${r.note ? " — " + r.note : ""}`);
    // Сколько виртуального времени заняла самопроверка: бюджет в CI — 180 с; ближе 120 с — пора поднимать (PROC-31)
    const spent = Math.round(performance.now() / 1000);
    lines.push(`${spent > 120 ? "WARN" : "INFO"}  Время самопроверки: ${spent} с из 180 с бюджета CI${spent > 120 ? " — запас мал, поднимите --virtual-time-budget" : ""}`);
    const summary = failed
      ? `Самопроверка: ${failed} из ${results.length} не прошли${skipped ? `, ${skipped} пропущены` : ""}`
      : `Самопроверка: все ${results.length} проверок прошли`;
    document.documentElement.dataset.selftest = failed ? "fail" : "pass";
    lines.forEach((line) => console.log(`SELFTEST ${line}`));
    console.log(`SELFTEST ${summary}`);

    const box = document.createElement("section");
    box.id = "selftest-report";
    box.setAttribute("role", "status");
    box.style.cssText = [
      "position:fixed",
      "right:16px",
      "bottom:16px",
      "z-index:1000",
      "max-width:min(640px, calc(100vw - 32px))",
      "max-height:60vh",
      "overflow:auto",
      "padding:12px 16px",
      "border-radius:8px",
      "background:var(--panel)",
      "color:var(--text)",
      `border:2px solid ${failed ? "var(--crit)" : "var(--ok)"}`,
      "box-shadow:0 8px 32px rgba(0,0,0,.35)",
      "font:13px/1.45 var(--font, sans-serif)",
    ].join(";");
    const title = document.createElement("strong");
    title.textContent = summary;
    const log = document.createElement("pre");
    log.id = "selftest-log";
    log.style.cssText = "margin:8px 0 0;white-space:pre-wrap;font:12px/1.5 var(--mono, monospace)";
    log.textContent = lines.join("\n");
    const close = document.createElement("button");
    close.type = "button";
    close.className = "btn ghost small";
    close.textContent = "Скрыть";
    close.style.cssText = "float:right;margin-left:12px";
    close.addEventListener("click", () => box.remove());
    // Весь отчёт — в буфер обмена одной кнопкой: итог и строки, без выделения руками. Нет Clipboard API (страница
    // не в безопасном контексте) — через скрытое поле и execCommand
    const copy = document.createElement("button");
    copy.type = "button";
    copy.className = "btn ghost small";
    copy.id = "selftest-copy";
    copy.textContent = "Копировать";
    copy.style.cssText = "float:right;margin-left:12px";
    copy.addEventListener("click", async () => {
      const text = `${summary}\n${lines.join("\n")}`;
      let ok = false;
      try {
        await navigator.clipboard.writeText(text);
        ok = true;
      } catch (e) {
        const area = document.createElement("textarea");
        area.value = text;
        area.style.cssText = "position:fixed;opacity:0";
        box.appendChild(area);
        area.select();
        ok = document.execCommand("copy");
        area.remove();
      }
      copy.textContent = ok ? "Скопировано" : "Не скопировалось";
      setTimeout(() => (copy.textContent = "Копировать"), 2000);
    });
    box.append(close, copy, title, log);
    document.body.appendChild(box);
  }

  setTimeout(run, 300);
})();
