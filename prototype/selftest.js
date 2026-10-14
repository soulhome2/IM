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
  // Страница, открытая самопроверкой в узкой рамке: сообщает, шире ли она экрана
  if (new URLSearchParams(location.search).has("widthcheck")) {
    window.addEventListener("load", () =>
      setTimeout(() => {
        const wide = [...document.querySelectorAll("body *")]
          .filter((el) => el.getBoundingClientRect().right > innerWidth + 1)
          .slice(0, 3)
          .map((el) => el.id || el.className);
        parent.postMessage({ widthcheck: true, width: innerWidth, scroll: document.documentElement.scrollWidth, wide }, "*");
      }, 300)
    );
    return;
  }
  if (!new URLSearchParams(location.search).has("selftest")) return;

  const $ = (id) => document.getElementById(id);
  const errors = [];
  window.addEventListener("error", (e) => errors.push(e.message || "ошибка JS"));

  const results = [];
  const wait = (ms = 80) => new Promise((resolve) => setTimeout(resolve, ms));
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
  async function step(name, fn, after) {
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
  }

  // Шаги сценария: подтвердить, выбрать вариант, перейти «Далее»
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
      el.closest("[data-i18n-skip], script, style, #selftest-report, #toasts") ||
      (el.closest("#modalDialog") && $("modalDialog").hidden) ||
      (el.closest("#adminTable, #adminTabs, #adminNote") && $("modalAdmin").hidden) ||
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
    const view = button($("eventsList"), "open_done");
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
      return closedId;
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
        const items = [...document.querySelectorAll(".log li")].map((li) => li.textContent);
        expect(items.length, "в карточке нет журнала");
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
        expect($("stepNext") && !$("stepNext").disabled, "кнопка «Далее» недоступна");
        await click($("stepNext"));
      }
      throw new Error("в сценарии не нашлось шага с вариантами");
    }, "Взять новое событие");

    await step("Запустить макрос из сценария", async () => {
      await openOwn(closedId);
      for (let i = 0; i < 8; i++) {
        const macro = root().querySelector("[data-macro]");
        if (macro) {
          const name = macro.dataset.macro;
          await click(macro);
          const after = root().querySelector(`[data-macro="${name}"]`);
          expect(after && after.classList.contains("ok"), `макрос «${name}» не отмечен запущенным`);
          return name;
        }
        await answerCurrentStep();
        const next = $("stepNext");
        expect(next && !next.disabled, "до шага с макросами не дойти");
        await click(next);
      }
      throw new Error("в сценарии нет шага с макросами");
    }, "Ответ с вариантами сохраняется после «Далее»");

    await step("Закрыть инцидент по сценарию", async () => {
      await openOwn(closedId);
      for (let i = 0; i < 10; i++) {
        // Кнопка в конце сценария, а не «Закрыть» в панели действий
        const close = root().querySelector('.scenario-actions [data-do="close"]');
        if (close) {
          await click(close);
          expect(field("resultId").value === "processed", `результат по умолчанию «${field("resultId").value}», а не «Обработан»`);
          await confirmDialog();
          expect(mode() === "queue", "после закрытия карточка не закрылась");
          return closedId;
        }
        await answerCurrentStep();
        const next = $("stepNext");
        expect(next && !next.disabled, "сценарий не проходится до конца");
        await click(next);
      }
      throw new Error("кнопка «Закрыть инцидент» так и не появилась");
    }, "Запустить макрос из сценария");

    let foreignTransferred = null;
    await step("Передать чужой инцидент", async () => {
      await setFilter("foreign");
      const rows = [...$("eventsList").querySelectorAll(".event")].filter(
        (r) => r.querySelector('[data-do="open_readonly"]') && r.querySelector('[data-do="transfer"]:not([aria-disabled="true"])')
      );
      expect(rows.length, "нет чужих инцидентов, которые можно передать");
      foreignTransferred = rows[0].dataset.id;
      await click(button($("eventsList"), "transfer", foreignTransferred));
      await confirmDialog(NOTE);
      await setFilter("all");
      const row = await rowOnPages(foreignTransferred);
      expect(row && row.textContent.includes("Ожидает принятия"), `${foreignTransferred} не ожидает принятия после передачи`);
      return foreignTransferred;
    });

    await step("Перехватить чужой инцидент", async () => {
      await setFilter("foreign");
      const row = [...$("eventsList").querySelectorAll(".event")].find(
        (r) => r.dataset.id !== foreignTransferred && r.querySelector('[data-do="open_readonly"]') && r.textContent.includes("Закрытие")
      );
      expect(row, "нет чужого инцидента в работе");
      const id = row.dataset.id;
      await click(button($("eventsList"), "open_readonly", id));
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

    await step("Отложить", async () => {
      await openOwn(workId);
      const b = button(root(), "hold");
      expect(b, "в карточке нет кнопки «Отложить»");
      await click(b);
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
    }, "Отложить");

    await step("Передать: поле с поиском по подстроке; «На месте», потом «Нет на месте» с причиной; себя и своей группы нет", async () => {
      await openOwn(workId);
      const b = button(root(), "transfer");
      expect(b, "в карточке нет кнопки «Передать»");
      await click(b);
      const input = () => $("dialogFields").querySelector('[data-target-input="targetId"]');
      const menu = () => $("dialogFields").querySelector('[data-target-combo="targetId"] .mselect-menu');
      expect(input(), "«Кому передать» — не поле с поиском");
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
      const items = [...menu().children];
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
      // Esc закрывает список, а не форму; выбор — щелчком
      input().dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
      await wait();
      expect(!menu() && !$("modalDialog").hidden, "Esc закрыл форму, а не только список");
      await click(input());
      await click(menu().querySelector('[data-target-pick="petrova"]'));
      expect(!menu() && field("targetId").value === "petrova", "Петрова не выбрана");
      expect(input().placeholder === "Петрова М.", `в поле «${input().placeholder}»`);
      await confirmDialog(NOTE);
      expect(mode() === "queue", "после «Передать» карточка не закрылась");
    }, "Возобновить");

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
      expect(text.includes("ур. 1"), "после «Отклонить» не сохранился уровень эскалации");
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
      // «Обработан» доступен, только если сценарий заполнен; у принятого инцидента он может быть уже заполнен
      const processed = field("resultId").querySelector('option[value="processed"]');
      expect(processed, "в форме нет результата «Обработан»");
      await setField("resultId", "false_alarm");
      await click($("dialogConfirm"));
      expect(!$("modalDialog").hidden, "закрылось без обязательного комментария");
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

    await step("«Обработан» недоступен, пока сценарий не заполнен", async () => {
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
      expect(processed && processed.disabled, "«Обработан» доступен при пустом сценарии");
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
    }, "«Обработан» недоступен, пока сценарий не заполнен");

    await step("Перерыв с открытой карточкой: инцидент отложен, карточка — просмотр", async () => {
      await openOwn(freshId);
      await click($("breakBtn"));
      await confirmDialog();
      // Карточка не закрывается, а становится просмотром (§9, §14.8): править отложенный нельзя
      expect(mode() === "work", "на перерыве карточка закрылась, а должна стать просмотром");
      expect(!root().querySelector("#stepNext:not([disabled])"), "на перерыве сценарий можно править");
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
      }
    });

    await step("Перерыв и возврат с перерыва", async () => {
      await click($("breakBtn"));
      expect(field("reasonId"), "перерыв не спросил причину");
      await confirmDialog();
      expect(!$("breakBanner").hidden, "плашка перерыва не появилась");
      await click($("breakReturn"));
      expect($("breakBanner").hidden, "кнопка на плашке не вернула с перерыва");
    });

    await step("Меню справки: ссылки из справочника, ссылка площадки — только при её инциденте (§7, RULE-49)", async () => {
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("open");
      // Строки одиночных событий: у строки группы события могут быть с разных площадок
      const rows = [...$("eventsList").querySelectorAll(".event:not(.event-group)")];
      const mall = rows.find((r) => /Торговый центр/.test(r.textContent));
      const other = rows.find((r) => !/Торговый центр/.test(r.textContent));
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
      const evac = window.IM_FIXTURE.helpLinks.find((l) => l.site === "Торговый центр").title;
      const common = window.IM_FIXTURE.helpLinks.find((l) => !l.site).title;
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
      await click($("adminTabs").querySelector('[data-admin-tab="limits"]'));
      const row = [...$("adminTable").querySelectorAll("tr")].find((r) => /В работе одновременно/.test(r.textContent));
      // Стенд самопроверки задал лимит 1 (standReset): экран показывает действующую схему
      expect(row && row.cells[1].textContent.trim() === "1", "лимит активных не показан или не совпадает со схемой");
      // Значения перечня — подписями из машины, а не машинным словом (BUG-26)
      await click($("adminTabs").querySelector('[data-admin-tab="escalation"]'));
      const overdue = [...$("adminTable").querySelectorAll("tr")].find((r) => /Просрочка закрытия/.test(r.textContent));
      // Значение перечня в машине — ключ каталога строк (§14.9): ждём его русскую строку
      const key = window.IM_WORKFLOW.adminSettings.tabs.find((x) => x.id === "escalation").items.find((i) => i.path === "escalation.onResolutionOverdue").values[window.IM_WORKFLOW.escalation.onResolutionOverdue];
      const expected = window.IM_STRINGS.ru[key];
      expect(overdue && overdue.cells[1].textContent.trim() === expected, `«Просрочка закрытия»: «${overdue && overdue.cells[1].textContent.trim()}» вместо «${expected}»`);
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

    // Взять новое в работу служебным запросом стенда — с версией записи, как клиент
    async function standClaim(stand, guid) {
      const card = await stand.raw("GET", `/operator/incidents/${encodeURIComponent(guid)}`);
      const res = await stand.raw("POST", `/operator/incidents/${encodeURIComponent(guid)}/transitions/claim`, { formValues: {}, surface: "queue" }, { "If-Match": card.headers.ETag || card.headers.etag });
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
        expect(await tickFirst((r) => r.querySelector('[data-do="open_readonly"]')), "нет чужих инцидентов в работе");
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
        const mall = (r) => r.querySelector(".event-sub").textContent.includes("Торговый центр");
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

    await step("На телефоне 360 пикселей страница не шире экрана", async () => {
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
      return `${r.scroll} из ${r.width}`;
    });

    await step("Контраст отсчётов, бейджей и уровня не ниже 4,5:1 в обеих темах", async () => {
      const original = document.documentElement.dataset.theme;
      const low = new Set();
      for (const theme of ["light", "dark"]) {
        await setTheme(theme);
        await setFilter("all");
        for (let page = 1; page <= 20; page++) {
          const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
          if (page > 1 && (!nav || nav.disabled)) break;
          if (nav && page > 1) await click(nav);
          $("eventsList").querySelectorAll(".event-sla, .badge, .chip.lvl").forEach((el) => {
            const r = contrast(el);
            if (r < 4.5) low.add(`${theme} ${el.className}: ${r.toFixed(2)}`);
          });
        }
      }
      await setTheme(original);
      await setFilter("open");
      expect(!low.size, `низкий контраст: ${[...low].join("; ")}`);
    });

    await step("Время событий в очереди не позже текущего", async () => {
      const toSec = (s) => s.split(":").reduce((acc, part) => acc * 60 + Number(part), 0);
      const now = new Date();
      const nowSec = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
      // В первые минуты после полуночи демо-время законно уходит во вчерашний день
      if (nowSec < 3600) return "проверка пропущена около полуночи";
      await setFilter("all");
      const late = [...$("eventsList").querySelectorAll(".event time")]
        .map((el) => el.textContent.trim())
        .filter((s) => /^\d\d:\d\d:\d\d$/.test(s) && toSec(s) > nowSec + 5);
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
      const number = await claimFromQueue((r) => !/Торговый центр/.test(r.textContent));
      expect(mode() === "work", "карточка взятого инцидента не открылась");
      await stand.raw("PUT", "/test/operators/me/roles", { roles: ["Оператор ТЦ"] });
      await wait(300);
      const toast = toastWith(/вам больше не доступен/);
      try {
        expect(toast && toast.textContent.includes(number), `нет уведомления о потере доступа к ${number}`);
        expect(mode() === "queue", "карточка недоступного инцидента не закрылась");
      } finally {
        await stand.raw("PUT", "/test/operators/me/roles", { roles: ["Оператор"] });
        await wait(200);
      }
      return toast.textContent;
    });

    await step("Алерт получателю: уведомление о нарушении норматива закрытия (§9, RULE-43)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const number = await claimFromQueue(() => true);
      let toast = null;
      // Часы шагами короче порога «нет связи», перед каждым — признак активности
      for (let i = 0; i < 12 && !toast; i++) {
        await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
        await stand.raw("POST", "/test/clock", { advanceSec: 240 });
        await wait(150);
        toast = toastWith(new RegExp(`Алерт: ${number} — Норматив закрытия нарушен`));
      }
      expect(toast, `нет уведомления об алерте по ${number}`);
      return toast.textContent;
    });

    await step("Уведомление о переходе — из машины: появился инцидент, автоэскалация (§9, RULE-60, BUG-32)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const fire = (await stand.get("/operator/incidents", { filter: "all", pageSize: 1000 })).items.find((e) => e.eventType.id === "fire");
      const source = (await stand.get(`/operator/incidents/${encodeURIComponent(fire.guid)}`)).source.guid;
      const top = Math.max(...window.IM_FIXTURE.priorities.map((p) => p.value));
      const created = await stand.raw("POST", "/test/incidents", { eventTypeId: "fire", priority: top, deviceIds: [source], site: fire.site, location: "selftest" });
      expect(created.status === 201, `инцидент не появился: ${created.status}`);
      const number = created.body.number;
      const norm = window.IM_WORKFLOW.timers.find((t) => t.id === "reaction").overrides.find((o) => o.priority === top).sec;
      await stand.raw("POST", "/operator/session/heartbeat", { openIncidentGuid: null });
      const grace = (window.IM_WORKFLOW.invariants.manualWinsOverTimer || {}).graceSec || 0;
      await stand.raw("POST", "/test/clock", { advanceSec: norm + grace + 1 });
      await wait(200);
      const toast = toastWith(new RegExp(`Автоэскалация ${number} → `));
      expect(toast, `нет уведомления об автоэскалации ${number}`);
      return toast.textContent;
    });

    await step("Порядок очереди: список — только если администратор разрешил, выбор сохраняется (§7, BUG-34)", async () => {
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      const select = $("queueSortSelect");
      expect(select.hidden, "список порядков виден без разрешения администратора");
      // Администратор разрешил: стенд подменяет схему, клиент перечитывает её по workflow.schema_published
      await standReset({ fixture: "demo", workflowPatch: { queueSort: { operatorMayChange: true } } });
      await wait(300);
      try {
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
          await wait(300);
        } finally {
          stand.get = get;
        }
        expect((await stand.get("/operator/session")).preferences.queueSort === other, "выбор не сохранён в настройках оператора");
        expect(asked > 0, "после выбора очередь не перечитана");
        return `порядков: ${options.length}, выбран «${select.selectedOptions[0].textContent}»`;
      } finally {
        await standReset({ fixture: "demo" });
        await wait(300);
        expect(select.hidden, "разрешение сняли — список не скрылся");
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
      await standReset({ fixture: "demo", fixturePatch: { scenarios: { fire: { title: null } } } });
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
            if (chip && /Пожар/.test(row.querySelector(".event-title").textContent)) untitled += chip.textContent.trim() === "Без названия" ? 1 : -1000;
          });
        }
      } finally {
        await standReset({ fixture: "demo" });
        await setFilter("open");
      }
      expect(untitled > 0, "у сценария без названия плашка не «Без названия»");
      return `плашек: ${seen.length}, например «${seen[0][0]}»; без названия — «Без названия»`;
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
        await click($("adminTabs").querySelector('[data-admin-tab="limits"]'));
        const shown = [...$("adminTable").querySelectorAll("tbody tr")].map((r) => r.cells[1].textContent.trim());
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

    await step("Выделить по фильтру → «Взять в работу»: пожары одним инцидентом, у основного «+N», связанные в карточке; «Отсоединить» и «Отсоединить все» — события снова новые (§11)", async () => {
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
      const picked = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.filter((e) => e.eventType.id === "fire").map((e) => e.guid);
      expect(!$("selBar").hidden && $("selBar").textContent.includes(`${picked.length}`), `панель выборки: «${$("selBar").textContent.trim()}»`);
      const take = $("selBar").querySelector('[data-sel-do="merge"]');
      expect(take && !off(take), `«Взять в работу» недоступна: ${take ? take.title : "нет кнопки"}`);
      await click(take);
      await wait();
      const lead = (await stand.get("/operator/incidents", { filter: "mine", pageSize: 1000 })).items.find((e) => e.state === "in_progress" && e.linkedCount);
      try {
        expect(lead && lead.linkedCount === picked.length - 1, `основной не взят или связанных не ${picked.length - 1}`);
        // Карточка основного открылась сама — на его текущем шаге сценария
        expect(mode() === "work" && $("statusIncident").textContent.includes(lead.number), `карточка основного не открылась: «${$("statusIncident").textContent}»`);
        const card = await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}`);
        const at = card.scenario.steps.findIndex((x) => x.id === card.scenario.cursorStepId) + 1;
        expect($("statusSteps").textContent.startsWith(`Шаг ${at} из`), `карточка не на шаге ${at}: «${$("statusSteps").textContent}»`);
        await click($("backToQueue"));
        await setFilter("mine");
        const row = $("eventsList").querySelector(`.event[data-id="${lead.guid}"]`);
        expect(row && row.querySelector(".chip.linked"), "у основного нет пометки «+N»");
        await click(row.querySelector('[data-do="open_card"], [data-do="resume"]'));
        expect(mode() === "work", "карточка основного не открылась из очереди");
        // Связанные — на своей вкладке, не над сценарием; открываются и по пометке «+N» в заголовке
        expect(!root().querySelector("[data-detach]") && root().querySelector(".crumbs"), "связанные видны на вкладке сценария");
        // Один ряд: «Назад», действия с инцидентом, «Далее». Нижний блок одинаков на обеих вкладках: место
        // «Назад» / «Далее» на вкладке привязанных занято, действия не прыгают
        const actsTop = () => {
          const bottom = root().querySelector(".work-bottom").getBoundingClientRect();
          const acts = root().querySelector(".work-acts").getBoundingClientRect();
          return `${Math.round(acts.left - bottom.left)}:${Math.round(acts.top - bottom.top)}/${Math.round(bottom.height)}`;
        };
        const box = (sel) => root().querySelector(sel).getBoundingClientRect();
        expect(Math.abs(box(".work-acts").top - box("#stepBack").top) < 8 && box(".work-acts").left > box("#stepBack").left, "действия не в одном ряду с «Назад» / «Далее»");
        const before = actsTop();
        await click(root().querySelector('.chip.linked[data-work-tab="linked"]'));
        expect(root().querySelector('.work-tab.on[data-work-tab="linked"]') && !root().querySelector(".crumbs"), "пометка «+N» не открыла вкладку привязанных");
        expect(actsTop() === before, `действия сдвинулись при переключении вкладок: ${before} → ${actsTop()}`);
        // Срок привязанного виден: у кого норматив закрытия идёт — отсчёт; в заголовке — «Срок привязанного», если раньше своего
        const leadCard = await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}`);
        const linkedPage = await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}/linked`, { pageSize: 10 });
        const running = linkedPage.items.filter((x) => x.timer && x.timer.running).length;
        expect(root().querySelectorAll(".lnk-member .lnk-sla[data-due]").length === running, `отсчётов у привязанных ${root().querySelectorAll(".lnk-member .lnk-sla[data-due]").length}, а идёт норматив у ${running}`);
        const earlier = Boolean(leadCard.linkedDueAt) && (!leadCard.timer || !leadCard.timer.running || Date.parse(leadCard.linkedDueAt) < Date.parse(leadCard.timer.dueAt));
        expect(Boolean(root().querySelector(".lnk-due")) === earlier, `«Срок привязанного» в заголовке: ${Boolean(root().querySelector(".lnk-due"))}, а должен быть ${earlier}`);
        const detach = root().querySelectorAll("[data-detach]");
        // Постранично, по 10 (LINKED_PAGE)
        expect(detach.length === Math.min(picked.length - 1, 10), `на вкладке связанных ${detach.length}`);
        const gone = detach[0].dataset.detach;
        await click(detach[0]);
        await wait();
        const back = (await stand.get("/operator/incidents", { filter: "open", pageSize: 1000 })).items.find((e) => e.guid === gone);
        expect(back && back.state === "new", "отсоединённый не вернулся в очередь новым");
        // «Отсоединить все» — остальные разом, список связанных в карточке пропадает
        const all = root().querySelector("[data-detach-all]");
        expect(all && !off(all), "нет кнопки «Отсоединить все»");
        await click(all);
        await wait();
        const left = (await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}/linked`, { pageSize: 200 })).items.filter((x) => x.state === "linked");
        expect(!left.length && !root().querySelector("[data-detach]"), `после «Отсоединить все» связанных ${left.length}`);
        expect(!root().querySelector(".work-tabs") && root().querySelector(".crumbs"), "связанных нет — а вкладки остались или сценарий не вернулся");
        return `основной ${lead.number}, связанных ${picked.length - 1}`;
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
        expect(intro.startsWith("«Все события»"), `окно не для выбранного узла: «${intro}»`);
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

    await step("Связанных много — на вкладке «Привязанные инциденты» постранично; поиск по номеру связанного — строка основного и страница найденного; «Отсоединить все» — со всех страниц (§11)", async () => {
      const stand = window.IM_SELFTEST_API;
      expect(stand, "нет служебных операций стенда в режиме самопроверки");
      // Ещё девять пожаров рядом с INC-1847 — копии с другими номерами
      const fx = window.IM_FIXTURE;
      const base = fx.incidents.find((i) => i.number === "INC-1847");
      const extra = Array.from({ length: 14 }, (_, k) =>
        Object.assign(JSON.parse(JSON.stringify(base)), { guid: `10000000-0000-4000-8000-0000000099${String(k).padStart(2, "0")}`, number: `INC-99${String(k).padStart(2, "0")}` })
      );
      if (mode() !== "queue") await click($("backToQueue"));
      await standReset({ fixture: "demo", fixturePatch: { incidents: fx.incidents.concat(extra) } });
      await wait(400);
      try {
        const res = await stand.post("/operator/incidents/merge", { incidentGuids: [base.guid].concat(extra.map((e) => e.guid)) });
        const lead = res.incident;
        // Поиск по номеру связанного: находит строку основного, открытая из неё карточка — на странице найденного
        const sought = (await stand.get(`/operator/incidents/${encodeURIComponent(lead.guid)}/linked`, { pageSize: 200 })).items.pop();
        await setFilter("open");
        $("eventSearch").value = sought.number;
        $("eventSearch").dispatchEvent(new Event("input", { bubbles: true }));
        await wait(300);
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
        await wait(300);
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
        expect(!left.length && !root().querySelector(".lnk-panel"), `после «Отсоединить все» связанных ${left.length}`);
        return `${first.join(", ")} | ${second.join(", ")}`;
      } finally {
        if (mode() === "work") await click($("backToQueue"));
        await standReset({ fixture: "demo" });
        await wait(400);
        await setFilter("open");
      }
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
    box.append(close, title, log);
    document.body.appendChild(box);
  }

  setTimeout(run, 300);
})();
