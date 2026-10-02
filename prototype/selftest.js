/* Самопроверка прототипа. Запуск: открыть index.html?selftest.
   Проходит основные переходы через интерфейс, как оператор, и показывает отчёт.
   Без параметра ничего не делает. После прогона демо-данные в этой вкладке
   изменены — для чистого прототипа перезагрузите страницу без ?selftest.
   Для CI: на <html> ставится data-selftest="pass" или "fail", текст отчёта — в #selftest-log. */
(() => {
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

  // Первая доступная кнопка перехода; ev — номер инцидента, если важен конкретный
  function button(scope, id, ev) {
    const list = [...scope.querySelectorAll(`[data-do="${id}"]`)];
    return list.find((b) => !b.disabled && (!ev || b.dataset.ev === ev)) || null;
  }

  async function click(el) {
    el.click();
    await wait();
  }

  async function confirmDialog(text) {
    expect(!$("modalDialog").hidden, "форма перехода не открылась");
    if (text && !$("dialogTextField").hidden) $("dialogText").value = text;
    await click($("dialogConfirm"));
  }

  // Остаток норматива закрытия в строке состояния карточки, в секундах
  function resolutionLeft() {
    const m = $("statusSla").textContent.match(/(\d+):(\d\d)/);
    return m ? Number(m[1]) * 60 + Number(m[2]) : null;
  }

  async function openOwn(id) {
    if (mode() === "work") return;
    await setFilter("mine");
    const b = button($("eventsList"), "continueOwn", id) || button($("eventsList"), "resume", id);
    expect(b, `${id} нет среди своих инцидентов`);
    await click(b);
    expect(mode() === "work", `карточка ${id} не открылась`);
  }

  async function step(name, fn) {
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
    if (!$("modalDialog").hidden) document.querySelector('[data-close="modalDialog"]').click();
    await wait();
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
    const view = button($("eventsList"), "viewDone");
    if (view) {
      await click(view);
      findRussian().forEach((s) => leftovers.add(s));
      await click($("backToQueue"));
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

    await step("Взять новое событие", async () => {
      await setFilter("open");
      const b = button($("eventsList"), "claim");
      expect(b, "нет доступной кнопки «Взять»");
      closedId = b.dataset.ev;
      await click(b);
      expect(mode() === "work", "карточка не открылась");
      return closedId;
    });

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
    });

    await step("Закрыть инцидент по сценарию", async () => {
      await openOwn(closedId);
      for (let i = 0; i < 10; i++) {
        // Кнопка в конце сценария, а не «Закрыть» в панели действий
        const close = root().querySelector('.scenario-actions [data-do="close"]');
        if (close) {
          await click(close);
          expect($("dialogSelect").value === "processed", `результат по умолчанию «${$("dialogSelect").value}», а не «Обработан»`);
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

    await step("Отложить", async () => {
      await openOwn(workId);
      const b = button(root(), "hold");
      expect(b, "в карточке нет кнопки «Отложить»");
      await click(b);
      await confirmDialog();
      expect(mode() === "queue", "после «Отложить» карточка не закрылась");
    });

    await step("Возобновить", async () => {
      await setFilter("mine");
      const b = button($("eventsList"), "resume", workId);
      expect(b, `у ${workId} нет кнопки «Возобновить»`);
      await click(b);
      expect(mode() === "work", "карточка не открылась");
    });

    await step("Передать", async () => {
      await openOwn(workId);
      const b = button(root(), "transfer");
      expect(b, "в карточке нет кнопки «Передать»");
      await click(b);
      await confirmDialog("самопроверка");
      expect(mode() === "queue", "после «Передать» карточка не закрылась");
    });

    await step("Принять адресованную передачу", async () => {
      await setFilter("inbox");
      const b = button($("eventsList"), "accept");
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
      expect(acceptedId, "нечего возвращать: «Принять» не сработал");
      await openOwn(acceptedId);
      const b = button(root(), "release");
      expect(b, "в карточке нет кнопки «Вернуть в очередь»");
      await click(b);
      await confirmDialog("самопроверка");
      expect(mode() === "queue", "после возврата карточка не закрылась");
    });

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
    });

    await step("Закрыть с результатом «Ложная тревога» без сценария", async () => {
      expect(acceptedId, "нечего закрывать: «Принять» не сработал");
      await openOwn(acceptedId);
      const b = button(root(), "close");
      expect(b, "в карточке нет кнопки «Закрыть»");
      await click(b);
      // «Обработан» доступен, только если сценарий заполнен; у принятого инцидента он может быть уже заполнен
      const processed = $("dialogSelect").querySelector('option[value="processed"]');
      expect(processed, "в форме нет результата «Обработан»");
      $("dialogSelect").value = "false_alarm";
      $("dialogSelect").dispatchEvent(new Event("change"));
      await click($("dialogConfirm"));
      expect(!$("modalDialog").hidden, "закрылось без обязательного комментария");
      await confirmDialog("самопроверка");
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
    });

    await step("Закрыть без обработки из очереди", async () => {
      await setFilter("open");
      const b = [...$("eventsList").querySelectorAll('[data-do="closeUnprocessed"]')].find((x) => {
        const row = x.closest(".event");
        return !x.disabled && row && row.querySelector('[data-do="claim"]');
      });
      expect(b, "у новых событий нет кнопки «Закрыть»");
      const id = b.dataset.ev;
      await click(b);
      await confirmDialog("самопроверка");
      await setFilter("open");
      expect(!$("eventsList").querySelector(`[data-id="${id}"]`), `${id} остался среди открытых`);
      return id;
    });

    await step("Перерыв и возврат на смену", async () => {
      await click($("breakBtn"));
      expect(!$("breakBanner").hidden, "плашка перерыва не появилась");
      await click($("breakBtn"));
      expect($("breakBanner").hidden, "плашка перерыва не исчезла");
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

    await step("Перевод на английский", () => checkLanguage("en"));
    await step("Перевод на испанский", () => checkLanguage("es"));

    report();
  }

  function report() {
    const failed = results.filter((r) => !r.ok).length;
    const lines = results.map((r) => `${r.ok ? "PASS" : "FAIL"}  ${r.name}${r.note ? " — " + r.note : ""}`);
    const summary = failed
      ? `Самопроверка: ${failed} из ${results.length} не прошли`
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
