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

  async function step(name, fn, after) {
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
  function findRussian() {
    const cyr = /[Ѐ-ӿ]/;
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

  async function run() {
    let closedId = null;
    let workId = null;
    let acceptedId = null;
    let acceptedLeft = null;
    let freshId = null;
    let groupPair = [];

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

    await step("Передать; себя и своей группы нет среди адресатов", async () => {
      await openOwn(workId);
      const b = button(root(), "transfer");
      expect(b, "в карточке нет кнопки «Передать»");
      await click(b);
      const offered = [...field("targetId").options].map((o) => o.value);
      const self = offered.filter((id) => id === "me" || id === "grp-leads");
      expect(!self.length, `среди адресатов есть сам оператор или его группа: ${self.join(", ")}`);
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

    await step("Esc в своей карточке возвращает к очереди, инцидент остаётся в работе", async () => {
      await openOwn(freshId);
      await pressKey("Escape");
      expect(mode() === "queue", "Esc не вернул к очереди");
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
    }, "Esc в своей карточке возвращает к очереди, инцидент остаётся в работе");

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

    await step("Обработать как одно: два однотипных берутся вместе", async () => {
      await setFilter("open");
      // Тип, у которого на первой странице есть два новых события: перебираем фильтр по типу
      const select = $("eventTypeFilter");
      let pair = null;
      for (const opt of [...select.options].filter((o) => o.value !== "all")) {
        select.value = opt.value;
        select.dispatchEvent(new Event("change"));
        await wait();
        const ids = [...$("eventsList").querySelectorAll(".event")]
          .filter((r) => r.querySelector('[data-do="claim"]:not([aria-disabled="true"])'))
          .map((r) => r.dataset.id);
        if (ids.length >= 2) {
          pair = ids.slice(0, 2);
          break;
        }
      }
      expect(pair, "нет типа событий с двумя новыми");
      const [a, b] = pair;
      groupPair = pair;
      await click($("eventsList").querySelector(`[data-check="${a}"]`));
      await click($("eventsList").querySelector(`[data-check="${b}"]`));
      await click(button($("eventsList"), "claim", a));
      select.value = "all";
      select.dispatchEvent(new Event("change"));
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("mine");
      const both = [a, b].every((id) => $("eventsList").querySelector(`[data-id="${id}"]`));
      expect(both, `в работу ушли не оба: ${a}, ${b}`);
      return `${a} + ${b}`;
    });

    // При лимите активных 1 исключение сделало бы две единицы в работе (RULE-13). Путь, где
    // исключение проходит, проверяет мутация exclude в tools/check_mutations.py
    await step("Исключить из группы нельзя, если превысится лимит активных", async () => {
      await openOwn(groupPair[0]);
      const b = root().querySelector("[data-exclude]");
      expect(b, "в карточке группы нет кнопки «Исключить из группы»");
      expect(off(b), "кнопка активна, хотя лимит активных превысится");
      expect((b.title || "").includes("Лимит активных"), `нет подсказки о лимите: «${b.title}»`);
      await click($("backToQueue"));
      return groupPair[0];
    }, "Обработать как одно: два однотипных берутся вместе");

    await step("Фильтр по типу устройства поверх группы", async () => {
      await setFilter("all");
      const select = $("deviceTypeFilter");
      const total = $("eventsList").querySelectorAll(".event").length;
      select.value = "fire-detector";
      select.dispatchEvent(new Event("change"));
      await wait();
      const rows = [...$("eventsList").querySelectorAll(".event")];
      const stray = rows.filter((r) => !r.textContent.includes("Пожарная тревога"));
      select.value = "all";
      select.dispatchEvent(new Event("change"));
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
      const select = $("eventTypeFilter");
      const opt = [...select.options].find((o) => o.value !== "all");
      expect(opt, "в фильтре нет ни одного типа события");
      const before = $("eventsList").querySelectorAll(".event").length;
      select.value = opt.value;
      select.dispatchEvent(new Event("change"));
      await wait();
      const rows = [...$("eventsList").querySelectorAll(".event")];
      const stray = rows.filter((r) => !r.textContent.includes(opt.textContent));
      select.value = "all";
      select.dispatchEvent(new Event("change"));
      await setFilter("open");
      expect(rows.length, `по типу «${opt.textContent}» ничего не нашлось`);
      expect(!stray.length, `в выборке «${opt.textContent}» есть события другого типа: ${stray.length}`);
      return `${opt.textContent}: ${rows.length} из ${before}`;
    });

    await step("Перерыв и возврат с перерыва", async () => {
      await click($("breakBtn"));
      expect(field("reasonId"), "перерыв не спросил причину");
      await confirmDialog();
      expect(!$("breakBanner").hidden, "плашка перерыва не появилась");
      await click($("breakReturn"));
      expect($("breakBanner").hidden, "кнопка на плашке не вернула с перерыва");
    });

    await step("Настройки администратора: вкладки из машины, значения и данные МИ (§20)", async () => {
      expect(!$("adminBtn").hidden, "пункта «Настройки администратора» нет в меню");
      await click($("adminBtn"));
      expect(!$("modalAdmin").hidden, "экран настроек не открылся");
      const tabs = [...$("adminTabs").querySelectorAll("[data-admin-tab]")];
      expect(tabs.length === window.IM_WORKFLOW.adminSettings.tabs.length, `вкладок ${tabs.length}, в машине ${window.IM_WORKFLOW.adminSettings.tabs.length}`);
      await click($("adminTabs").querySelector('[data-admin-tab="limits"]'));
      const row = [...$("adminTable").querySelectorAll("tr")].find((r) => /В работе одновременно/.test(r.textContent));
      expect(row && row.cells[1].textContent.trim() === String(window.IM_WORKFLOW.limits.maxActive), "лимит активных не показан или не совпадает с машиной");
      await click($("adminTabs").querySelector('[data-admin-tab="duty_groups"]'));
      expect(/Старшие операторы/.test($("adminTable").textContent), "дежурных групп из запроса нет");
      await click(document.querySelector('[data-close="modalAdmin"]'));
      expect($("modalAdmin").hidden, "экран настроек не закрылся");
    });

    await step("Выход из МИ: подтверждение, дальше только просмотр, вход (§12.1)", async () => {
      await setFilter("open");
      await click($("signOutBtn"));
      expect(!$("modalDialog").hidden && /вернутся в очередь/.test($("dialogNote").textContent), "выход не спросил подтверждения");
      await confirmDialog();
      expect(!$("signedOutBanner").hidden, "плашка «Вы вышли» не появилась");
      expect($("dutyBadge").textContent === "Вышел", `в шапке «${$("dutyBadge").textContent}» вместо «Вышел»`);
      const claims = [...$("eventsList").querySelectorAll('[data-do="claim"]')];
      expect(claims.length && claims.every(off), "после выхода «Взять» доступно");
      await click($("signInBtn"));
      expect($("signedOutBanner").hidden, "кнопка «Войти» не вернула в МИ");
      expect([...$("eventsList").querySelectorAll('[data-do="claim"]')].some((b) => !off(b)), "после входа «Взять» недоступно");
    });

    await step("Смешанная выборка: «Взять» у отмеченных недоступно с объяснением", async () => {
      await setFilter("open");
      const rows = [...$("eventsList").querySelectorAll(".event")].filter((r) => r.querySelector('[data-do="claim"]'));
      const a = rows[0];
      const typeOf = (r) => r.querySelector(".event-title strong").textContent;
      const b = rows.find((r) => typeOf(r) !== typeOf(a));
      expect(a && b, "нет двух новых событий разного типа");
      const ids = [a.dataset.id, b.dataset.id];
      for (const id of ids) await click($("eventsList").querySelector(`[data-check="${id}"]`));
      const claim = $("eventsList").querySelector(`[data-do="claim"][data-ev="${ids[0]}"]`);
      const blocked = claim && off(claim) && /выборки/.test(claim.title);
      await click($("clearSelectionBtn"));
      expect(blocked, `«Взять» на смешанной выборке: ${claim ? claim.title : "нет кнопки"}`);
      return ids.join(" + ");
    });

    await step("Shift+A выбирает однотипные, Shift+D снимает выделение", async () => {
      await setFilter("open");
      // «Снять» доступна, только когда выборка не пуста — на любой странице очереди
      const picked = () => !$("clearSelectionBtn").disabled;
      await pressKey("A", { shiftKey: true });
      const after = picked();
      const last = $("toasts").lastElementChild;
      await pressKey("D", { shiftKey: true });
      expect(after, "Shift+A ничего не выбрал");
      expect(!picked(), "Shift+D не снял выделение");
      await pressKey("A", { ctrlKey: true });
      expect(!picked(), "Ctrl+A перехвачен прототипом");
      return last ? last.textContent : "";
    });

    await step("Горячие клавиши не работают при открытой справке", async () => {
      await setFilter("open");
      await pressKey("?");
      expect(!$("modalHotkeys").hidden, "справка по ? не открылась");
      await pressKey("n");
      const taken = mode() === "work";
      await pressKey("?");
      expect(!taken, "N взял инцидент за окном справки");
      expect($("modalHotkeys").hidden, "? не закрыл справку");
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
        setTimeout(() => resolve(null), 5000);
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

    await step("Цвет полоски у каждого приоритета", async () => {
      await setFilter("all");
      const missing = new Set();
      for (let page = 1; page <= 20; page++) {
        const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
        if (page > 1 && (!nav || nav.disabled)) break;
        if (nav && page > 1) await click(nav);
        $("eventsList").querySelectorAll(".event-pri").forEach((el) => {
          const bg = getComputedStyle(el).backgroundColor;
          if (bg === "transparent" || bg === "rgba(0, 0, 0, 0)") missing.add(el.className.replace("event-pri", "").trim());
        });
      }
      await setFilter("open");
      expect(!missing.size, `нет цвета у приоритета: ${[...missing].join(", ")}`);
    });

    await step("Ответы встроенного сервера соответствуют openapi.json", async () => {
      expect(window.IM_OPENAPI, "контракт openapi.js не подключён");
      const recorded = window.IM_RECORDED || [];
      expect(recorded.length, "встроенный сервер не записал ни одного ответа");
      const problems = IMContract.problems(window.IM_OPENAPI, recorded);
      expect(!problems.length, `расхождений ${problems.length}: ${problems.slice(0, 12).join("; ")}`);
      return `${recorded.length} ответов`;
    });

    await step("Перевод на английский", () => checkLanguage("en"));
    await step("Перевод на испанский", () => checkLanguage("es"));

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
