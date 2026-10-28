/* Пробы мутационной проверки (tools/check_mutations.py).
   Каждая проба через интерфейс проверяет, что прототип ведёт себя так, как требует
   ИЗМЕНЁННАЯ машина состояний. На исходной машине проба должна падать: так видно,
   что правило живёт только в машине, а не продублировано в коде прототипа.
   Запуск: index.html?probe=<имя>. Результат — <pre id="probe">PASS|FAIL …</pre>. */
(() => {
  const name = new URLSearchParams(location.search).get("probe");
  if (!name) return;
  const $ = (id) => document.getElementById(id);
  const wait = (ms = 80) => new Promise((r) => setTimeout(r, ms));
  const click = async (el) => {
    el.click();
    await wait();
  };
  const setFilter = async (v) => {
    $("eventFilter").value = v;
    $("eventFilter").dispatchEvent(new Event("change"));
    await wait();
  };
  const off = (b) => b.disabled || b.getAttribute("aria-disabled") === "true";
  const btn = (scope, id, ev) =>
    [...scope.querySelectorAll(`[data-do="${id}"]`)].find((b) => !off(b) && (!ev || b.dataset.ev === ev)) || null;
  const anyBtn = (scope, id, ev) => [...scope.querySelectorAll(`[data-do="${id}"]`)].find((b) => !ev || b.dataset.ev === ev) || null;
  const field = (n) => $("dialogFields").querySelector(`[data-field="${n}"]`);
  const mode = () => $("workspace").dataset.mode;
  const root = () => $("scenarioRoot");
  const row = (id) => $("eventsList").querySelector(`[data-id="${id}"]`);
  // Инцидент по номеру из эталонного набора: guid — UUID, на экране — номер
  const guidOf = (number) => (window.IM_FIXTURE.incidents.find((i) => i.number === number) || {}).guid;
  // Срок по нормативу в заголовке карточки — data-due отсчёта инцидента
  const headDue = (guid) => Number(($("workTitle").querySelector(`[data-timer="${guid}"]`) || { dataset: {} }).dataset.due) || null;
  const fx = (guid) => window.IM_FIXTURE.incidents.find((i) => i.guid === guid) || {};
  // Два новых одного сценария в очереди: самый срочный и самый спокойный
  async function deadlinePair() {
    await setFilter("open");
    const ids = [...$("eventsList").querySelectorAll('[data-do="claim"]')].filter((b) => !off(b)).map((b) => b.dataset.ev);
    const byScenario = {};
    ids.forEach((id) => (byScenario[fx(id).scenarioGuid] = (byScenario[fx(id).scenarioGuid] || []).concat(id)));
    const group = Object.values(byScenario).sort((a, b) => b.length - a.length)[0].sort((a, b) => fx(b).priority - fx(a).priority);
    return { urgent: group[0], calm: group[group.length - 1] };
  }
  async function claimCard(guid) {
    await setFilter("open");
    await click(btn($("eventsList"), "claim", guid));
  }
  async function takeAndHold(guid) {
    await claimCard(guid);
    await click(anyBtn(root(), "hold"));
    await confirm();
    if (mode() === "work") await click($("backToQueue"));
  }
  // «Взять в работу» на выборке из своих: основной выбирает сервер
  async function mergeMine(guids) {
    await setFilter("mine");
    for (const g of guids) await click($("eventsList").querySelector(`[data-check="${g}"]`));
    await click($("selBar").querySelector('[data-sel-do="merge"]'));
  }
  async function claimFirst() {
    await setFilter("open");
    const b = btn($("eventsList"), "claim");
    const id = b.dataset.ev;
    await click(b);
    return id;
  }
  async function confirm(text) {
    const c = field("comment");
    if (text && c) c.value = text;
    // Причина удержания пуста, пока оператор не выберет (RULE-110): проба выбирает первую
    const reason = field("reasonId");
    if (reason && !reason.value) {
      const first = [...reason.options].find((o) => o.value && !o.disabled);
      if (first) reason.value = first.value;
    }
    await click($("dialogConfirm"));
  }

  const PROBES = {
    async groupBadge() {
      await setFilter("inbox");
      const badge = row(guidOf("INC-1836")) && row(guidOf("INC-1836")).querySelector(".badge");
      const text = badge ? badge.textContent : "";
      return [text.includes("Группе на принятие"), "бейдж INC-1836: " + text];
    },
    // Переданное моей группе: на панели выборки — «Перехватить» рядом с «Принять» (BUG-55)
    async takeoverTarget() {
      await setFilter("inbox");
      const r = row(guidOf("INC-1836"));
      if (!r) return [false, "нет INC-1836 в «Мне на принятие»"];
      await click(r.querySelector("[data-check]"));
      await wait(300);
      const take = $("selBar").querySelector('[data-sel-do="takeover"]');
      return [Boolean(take) && !off(take), "«Перехватить» на панели выборки: " + (take ? (off(take) ? "бледная" : "доступна") : "нет")];
    },
    // Переданное мне лично: в строке нет «Открыть» — посмотреть можно только приняв (BUG-60)
    async readonlyTarget() {
      await setFilter("inbox");
      const r = row(guidOf("INC-1843"));
      if (!r) return [false, "нет INC-1843 в «Мне на принятие»"];
      const has = Boolean(r.querySelector('[data-do="view"]'));
      return [!has, "«Открыть» у INC-1843: " + (has ? "есть" : "нет")];
    },
    // Новый: у строки нет значка «Посмотреть» — заглянуть можно только взяв (RULE-80, RULE-81)
    async viewNew() {
      await setFilter("open");
      const r = row(guidOf("INC-1838"));
      if (!r) return [false, "нет INC-1838 в «Открытых»"];
      const has = Boolean(r.querySelector('[data-do="view"]'));
      return [!has, "«Посмотреть» у нового INC-1838: " + (has ? "есть" : "нет")];
    },
    // Передача нового коллеге: в строке появилась пометка уровня — передача расходует цепочку (RULE-76)
    async transferLevel() {
      await setFilter("open");
      const b = btn($("eventsList"), "transfer");
      const id = b.dataset.ev;
      await click(b);
      field("targetId").value = "sidorov";
      await confirm("проба");
      await wait(300);
      const r = row(id);
      const lvl = r && r.querySelector(".chip.lvl");
      return [Boolean(lvl), "пометка уровня после передачи: " + (lvl ? lvl.textContent : "нет")];
    },
    // «Передать» нового через несколько секунд: отсчёт реакции снова полный (RULE-76, RULE-84 — ifStopped)
    async transferRestarts() {
      await setFilter("open");
      const id = guidOf("INC-1838");
      if (!row(id) || !btn($("eventsList"), "transfer", id)) return [false, "нет «Передать» у нового INC-1838"];
      const before = row(id).querySelector(".sla-t").textContent;
      await wait(4000);
      await click(btn($("eventsList"), "transfer", id));
      field("targetId").value = "sidorov";
      await confirm("проба");
      await wait(300);
      await setFilter("all");
      let r = row(id);
      for (let p = 2; !r && p <= 5; p++) {
        const nav = $("eventsPager").querySelector(`[data-page="${p}"]`);
        if (!nav) break;
        await click(nav);
        r = row(id);
      }
      const after = r ? r.querySelector(".sla-t").textContent : "строки нет";
      const sec = (t) => t.split(":").reduce((m, x) => m * 60 + Number(x), 0);
      return [sec(after) >= sec(before), `реакция до «Передать» ${before}, после ${after}`];
    },
    // «Отклонить» через несколько секунд после появления: отсчёт реакции снова полный (RULE-82)
    async rejectRestarts() {
      await setFilter("inbox");
      const id = guidOf("INC-1843");
      const before = row(id).querySelector(".sla-t").textContent;
      await wait(4000);
      await click(btn($("eventsList"), "reject", id));
      await confirm("проба");
      await setFilter("all");
      let r = row(id);
      for (let p = 2; !r && p <= 5; p++) {
        const nav = $("eventsPager").querySelector(`[data-page="${p}"]`);
        if (!nav) break;
        await click(nav);
        r = row(id);
      }
      const after = r ? r.querySelector(".sla-t").textContent : "строки нет";
      const sec = (t) => t.split(":").reduce((m, x) => m * 60 + Number(x), 0);
      return [sec(after) >= sec(before), `реакция до «Отклонить» ${before}, после ${after}`];
    },
    async transferEmpty() {
      await setFilter("open");
      await click(btn($("eventsList"), "transfer"));
      const value = field("targetId").value;
      return [value !== "", "адресат в форме выбран заранее: «" + value + "»"];
    },
    // Результат «Итога» — признак finish машины: в форме «Закрыть» без обработки его нет
    async close_finish() {
      await claimFirst();
      await click(anyBtn(root(), "close"));
      const ids = [...field("resultId").querySelectorAll("option")].map((o) => o.value).filter(Boolean);
      return [ids.length > 0 && !ids.includes("false_alarm"), "варианты формы «Закрыть»: " + ids.join(", ")];
    },
    // Варианты поля — optionExpr машины, и сервер проверяет присланное по нему же (ARCH-09): системная причина
    // доступна в форме — «Отложить» с ней выполняется
    async holdSystemReason() {
      const id = await claimFirst();
      await click(anyBtn(root(), "hold"));
      const sel = field("reasonId");
      const has = [...sel.querySelectorAll("option")].some((o) => o.value === "break");
      if (has) {
        sel.value = "break";
        sel.dispatchEvent(new Event("change"));
      }
      await confirm("проба");
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("mine");
      const item = window.IM_WORKFLOW.reasonCatalogs.hold.items.find((i) => i.id === "break");
      const badge = row(id) && row(id).querySelector(".badge");
      const text = badge ? badge.textContent : "";
      return [has && text.includes(window.IM_STRINGS.ru[item.labelKey]), "«Перерыв» в форме: " + has + ", бейдж: " + text];
    },
    async closeEmpty() {
      await claimFirst();
      await click(anyBtn(root(), "close"));
      const value = field("resultId").value;
      return [value !== "", "результат в форме выбран заранее: «" + value + "»"];
    },
    async selfTarget() {
      const id = await claimFirst();
      await click(anyBtn(root(), "transfer"));
      // «Кому передать» — поле с поиском: открыть список и выбрать вариант
      const input = $("dialogFields").querySelector('[data-target-input="targetId"]');
      if (input) await click(input);
      const pick = $("dialogFields").querySelector('[data-target-pick="grp-leads"]');
      const has = Boolean(pick);
      if (has) await click(pick);
      await confirm("проба");
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("inbox");
      const accept = btn($("eventsList"), "accept", id);
      return [has && Boolean(accept), "своя группа в адресатах: " + has + ", можно принять: " + Boolean(accept)];
    },
    async ceiling() {
      await setFilter("open");
      await wait(3500);
      await setFilter("open");
      const breached = [...$("eventsList").querySelectorAll(".event")].filter(
        (r) => r.querySelector('[data-do="claim"]') && r.querySelector(".breached")
      ).length;
      return [breached > 0, "новых с нарушением реакции: " + breached];
    },
    async holdBreach() {
      const id = await claimFirst();
      await click(anyBtn(root(), "hold"));
      await confirm();
      await wait(3500);
      await setFilter("mine");
      const chip = row(id) && row(id).querySelector(".breached");
      return [Boolean(chip), "отметка нарушения у отложенного: " + Boolean(chip)];
    },
    async atomic() {
      const id = await claimFirst();
      await click(anyBtn(root(), "hold"));
      await confirm();
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("mine");
      const stillWorking = Boolean(btn($("eventsList"), "open_card", id));
      const toasts = [...$("toasts").children].map((x) => x.textContent).join(" | ");
      return [stillWorking && toasts.includes("Переход не выполнен"), `остался «В работе»: ${stillWorking}; ${toasts.slice(-80)}`];
    },
    // Новый открыт на просмотр — его реакция истекает, автоэскалация; карточка остаётся открытой
    async autoEscalation() {
      await setFilter("open");
      const id = btn($("eventsList"), "claim").dataset.ev;
      await click(btn($("eventsList"), "view", id));
      const opened = mode() === "work";
      await wait(4500);
      const toasts = [...$("toasts").children].map((x) => x.textContent).join(" | ");
      const escalated = toasts.includes("Автоэскалация");
      return [opened && escalated && mode() === "work", `автоэскалация: ${escalated}, карточка открыта: ${mode() === "work"}`];
    },
    // Новый не взяли: ступень 1 — Петрова, ступень 2 — моя группа; принимаю и он мой
    async groupTarget() {
      await setFilter("open");
      const id = btn($("eventsList"), "claim").dataset.ev;
      await wait(6000);
      await setFilter("inbox");
      const accept = btn($("eventsList"), "accept", id);
      if (accept) await click(accept);
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("mine");
      const mine = Boolean(btn($("eventsList"), "open_card", id));
      return [Boolean(accept) && mine, `на принятие группе: ${Boolean(accept)}, после «Принять» мой: ${mine}`];
    },
    async breach() {
      const id = await claimFirst();
      await click($("backToQueue"));
      await wait(3500);
      await setFilter("mine");
      const chip = row(id) && row(id).querySelector("[data-timer], .event-sla");
      const breached = Boolean(chip && chip.classList.contains("breached"));
      return [breached, "отметка нарушения у взятого инцидента: " + breached];
    },
    async reopenNorm() {
      await setFilter("done");
      await click(btn($("eventsList"), "reopen", guidOf("INC-1837")));
      await confirm("проба");
      const m = $("statusSla").textContent.match(/(\d+):(\d\d)/);
      const sec = m ? Number(m[1]) * 60 + Number(m[2]) : -1;
      return [sec > 0 && sec <= 60, "после переоткрытия: " + $("statusSla").textContent];
    },
    async empty() {
      const counts = [];
      for (const f of ["open", "mine", "inbox", "done", "all"]) {
        await setFilter(f);
        counts.push(`${f}: ${$("eventsList").querySelectorAll("[data-do]").length}`);
      }
      const card = root().querySelectorAll("[data-do]").length;
      const total = counts.reduce((n, c) => n + Number(c.split(": ")[1]), 0) + card;
      return [total === 0, `кнопок действий — ${counts.join(", ")}, в карточке: ${card}`];
    },
    async label() {
      await setFilter("open");
      const b = btn($("eventsList"), "claim");
      return [b && b.textContent.trim() === "Забрать", b && b.textContent.trim()];
    },
    async from() {
      await claimFirst();
      return [!anyBtn(root(), "hold"), "кнопка «Отложить» в карточке: " + Boolean(anyBtn(root(), "hold"))];
    },
    async limit() {
      await claimFirst();
      await click($("backToQueue"));
      await setFilter("open");
      const b = btn($("eventsList"), "claim");
      return [!b, "второе «Взять» доступно: " + Boolean(b)];
    },
    async norm() {
      await setFilter("open");
      const t = row(guidOf("INC-1847")).querySelector(".sla-t").textContent;
      return [t.startsWith("9:") || t.startsWith("10:"), "реакция INC-1847: " + t];
    },
    async surfaces() {
      const id = await claimFirst();
      await click($("backToQueue"));
      await setFilter("mine");
      await click(btn($("eventsList"), "close", id));
      const has = Boolean(field("resultId") && field("resultId").querySelector('option[value="false_alarm"]'));
      return [has, "в очереди предложена «Ложная тревога»: " + has];
    },
    async filter() {
      await setFilter("mine");
      return [Boolean(row(guidOf("INC-1837"))), "закрытый свой INC-1837 во «Мои»: " + Boolean(row(guidOf("INC-1837")))];
    },
    async badge() {
      await setFilter("open");
      const b = row(guidOf("INC-1847")).querySelector(".badge").textContent;
      return [b === "Свежее", "бейдж: " + b];
    },
    async form() {
      const id = await claimFirst();
      await click(anyBtn(root(), "release"));
      await click($("dialogConfirm"));
      await setFilter("open");
      const r = row(id);
      return [$("modalDialog").hidden && r && r.textContent.includes("Новое"), "вернули без причины: " + $("modalDialog").hidden];
    },
    async catalog() {
      await claimFirst();
      await click(anyBtn(root(), "hold"));
      const has = Boolean(field("reasonId").querySelector('option[value="probe"]'));
      return [has, "новая причина удержания в форме: " + has];
    },
    // «Взять в работу» на выборке (§11): два новых одного типа — связанное из списков пропадает
    async merge_hides() {
      await setFilter("open");
      const rows = [...$("eventsList").querySelectorAll(".event")].filter((r) => r.querySelector('[data-do="claim"]'));
      const typeOf = (r) => r.querySelector(".event-title strong").textContent;
      const pair = rows.filter((r) => rows.filter((x) => typeOf(x) === typeOf(r)).length >= 2);
      const ids = pair.filter((r) => typeOf(r) === typeOf(pair[0])).slice(0, 2).map((r) => r.dataset.id);
      for (const id of ids) await click($("eventsList").querySelector(`[data-check="${id}"]`));
      await click($("selBar").querySelector('[data-sel-do="merge"]'));
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("all");
      const both = ids.every((id) => $("eventsList").querySelector(`.event[data-id="${id}"]`));
      return [both, "после «Объединить» оба в «Открытых»: " + both];
    },
    // Два основных со связанными — «Взять в работу» как одно: связанные прежнего основного переходят к новому
    // (эффект перехода объединения). Пары: INC-1851 + INC-1847 (основной 1851) и INC-1838 + INC-1842 (основной 1838);
    // затем 1851 + 1838 — основной старший 1838, у него трое связанных
    async merge_relink() {
      const tick = async (number) => {
        for (let page = 1; page <= 6; page++) {
          const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
          if (page > 1 && (!nav || nav.disabled)) break;
          if (nav) await click(nav);
          const box = $("eventsList").querySelector(`[data-check="${guidOf(number)}"]`);
          if (box) return click(box);
        }
      };
      const take = async (filter, numbers) => {
        await setFilter(filter);
        for (const n of numbers) await tick(n);
        await click($("selBar").querySelector('[data-sel-do="merge"]'));
        if (mode() === "work") await click($("backToQueue"));
      };
      await take("open", ["INC-1851", "INC-1847"]);
      await take("open", ["INC-1838", "INC-1842"]);
      await setFilter("mine");
      for (const n of ["INC-1851", "INC-1838"]) await tick(n);
      await click($("selBar").querySelector('[data-sel-do="merge"]'));
      const n = Number((root().querySelector(".work-tab-n") || { textContent: "0" }).textContent);
      return [n === 2, "связанных у нового основного: " + n];
    },
    // Ответы связанного — основному (эффект перехода объединения). INC-1847 и INC-1838 — оба в работе,
    // основной — старший INC-1838; шаг «visual» отвечен только в INC-1847 (ответ уходит по «Далее»)
    // Срок группы (RULE-97): самый срочный и самый спокойный новые одного сценария; срок основного — из заголовка карточки
    async merge_no_tighten() {
      const { urgent, calm } = await deadlinePair();
      await takeAndHold(urgent);
      await claimCard(calm);
      const own = headDue(calm);
      await click($("backToQueue"));
      await mergeMine([urgent, calm]);
      const after = headDue(calm);
      return [Boolean(own) && after === own, `срок основного до объединения ${own}, после ${after}`];
    },
    // Отсоединённый — с остатком срока группы (copyPrimaryDeadline), а не со своим прежним
    async detach_own_deadline() {
      const { urgent, calm } = await deadlinePair();
      await takeAndHold(calm);
      await claimCard(urgent);
      const group = headDue(urgent);
      await click($("backToQueue"));
      await mergeMine([urgent, calm]);
      await click($("workTitle").querySelector('.chip.linked[data-work-tab="linked"]'));
      await click(root().querySelector(`[data-detach="${calm}"]`));
      if (mode() === "work") await click($("backToQueue"));
      await claimCard(calm);
      const own = headDue(calm);
      return [Boolean(group && own) && own > group + 60000, `срок группы ${group}, у отсоединённого ${own}`];
    },
    async merge_answers() {
      for (const number of ["INC-1847", "INC-1838"]) {
        await setFilter("open");
        await click(btn($("eventsList"), "claim", guidOf(number)));
        if (number === "INC-1847") {
          await click(root().querySelector('[data-confirm="visual"]'));
          await click($("stepNext"));
        }
        await click($("backToQueue"));
      }
      await setFilter("mine");
      for (const number of ["INC-1847", "INC-1838"]) await click($("eventsList").querySelector(`[data-check="${guidOf(number)}"]`));
      await click($("selBar").querySelector('[data-sel-do="merge"]'));
      // Перенесённый ответ — шаг пути с ответом; прохождение основного идёт дальше по нему
      const done = Boolean(root().querySelector(".crumb.done"));
      return [!done, "у основного шаг «visual» отвечен: " + done];
    },
    // Основной при «Взять в работу» на выборке — mergePrimary машины: самый срочный из двух новых
    async merge_primary() {
      const { urgent, calm } = await deadlinePair();
      if (!(fx(urgent).priority > fx(calm).priority)) return [false, "в паре одинаковая срочность"];
      for (const g of [urgent, calm]) await click($("eventsList").querySelector(`[data-check="${g}"]`));
      await click($("selBar").querySelector('[data-sel-do="merge"]'));
      const title = $("workTitle").textContent;
      return [mode() === "work" && title.includes(fx(calm).number), `карточка основного: ${title.trim().slice(0, 60)}`];
    },
    // Минимум выборки — bulk.minItems машины: «Передать» на двух отмеченных новых
    async bulk_min() {
      await setFilter("open");
      const ids = [...$("eventsList").querySelectorAll('[data-do="claim"]')].filter((b) => !off(b)).slice(0, 2).map((b) => b.dataset.ev);
      for (const id of ids) await click($("eventsList").querySelector(`[data-check="${id}"]`));
      const b = $("selBar").querySelector('[data-sel-do="transfer"]');
      return [ids.length === 2 && Boolean(b) && off(b), `«Передать» на двух: ${b ? (off(b) ? "недоступна" : "доступна") : "нет кнопки"}`];
    },
    // «Взять в работу» на выборке: куда дальше — ui.navigate объединения в машине
    async merge_nav() {
      await setFilter("open");
      const rows = [...$("eventsList").querySelectorAll(".event")].filter((r) => r.querySelector('[data-do="claim"]'));
      const typeOf = (r) => r.querySelector(".event-title strong").textContent;
      const pair = rows.filter((r) => rows.filter((x) => typeOf(x) === typeOf(r)).length >= 2);
      const ids = pair.filter((r) => typeOf(r) === typeOf(pair[0])).slice(0, 2).map((r) => r.dataset.id);
      for (const id of ids) await click($("eventsList").querySelector(`[data-check="${id}"]`));
      await click($("selBar").querySelector('[data-sel-do="merge"]'));
      return [ids.length === 2 && mode() === "queue", `после «Взять в работу» режим: ${mode()}`];
    },
    // Чужое в работе (INC-1846, Петрова, «Проникновение») с новым того же сценария (INC-1839) —
    // «Взять в работу» в панели выборки
    async merge_foreign() {
      await setFilter("open");
      const find = async (number) => {
        for (let page = 1; page <= 6; page++) {
          const nav = $("eventsPager").querySelector(`[data-page="${page}"]`);
          if (page > 1 && (!nav || nav.disabled)) break;
          if (nav) await click(nav);
          const row = [...$("eventsList").querySelectorAll(".event")].find((r) => r.querySelector(".event-sub").textContent.includes(number));
          if (row) return row;
        }
        return null;
      };
      for (const number of ["INC-1846", "INC-1839"]) {
        const row = await find(number);
        if (!row) return [false, `нет ${number} в очереди`];
        await click($("eventsList").querySelector(`[data-check="${row.dataset.id}"]`));
      }
      const b = $("selBar").querySelector('[data-sel-do="merge"]');
      const on = Boolean(b && b.getAttribute("aria-disabled") !== "true");
      return [on, "«Взять в работу» с чужим доступна: " + on];
    },
    // «Переоткрыть» ставит курсор сценария на текущий шаг прохождения (setCursor, §14.5): ответили на шаг 1,
    // вернулись к нему «Назад» и закрыли — после переоткрытия карточка на шаге 2
    async reopen_cursor() {
      const id = await claimFirst();
      await click(root().querySelector("[data-confirm]"));
      await click($("stepNext"));
      await click($("stepBack"));
      await click(anyBtn(root(), "close"));
      field("resultId").value = "false_alarm";
      field("resultId").dispatchEvent(new Event("change", { bubbles: true }));
      await wait();
      await confirm("проба");
      await setFilter("done");
      await click(btn($("eventsList"), "reopen", id));
      await confirm("проба");
      const text = $("statusSteps").textContent;
      return [!/^Шаг 2 /.test(text), "после переоткрытия: " + text];
    },
    async scenario() {
      await claimFirst();
      const editable = Boolean(root().querySelector("#stepNext.primary, .btn.primary#stepNext"));
      return [!editable, "сценарий можно править: " + editable];
    },
    async permission() {
      await setFilter("open");
      const fresh = [...$("eventsList").querySelectorAll(".event")].filter((r) => r.querySelector('[data-do="claim"]'));
      const has = fresh.some((r) => r.querySelector('[data-do="transfer"]'));
      return [fresh.length > 0 && !has, `«Передать» у новых (${fresh.length}): ` + has];
    },
    async reopen() {
      await setFilter("done");
      const has = Boolean(anyBtn($("eventsList"), "reopen", guidOf("INC-1837")));
      return [!has, "«Переоткрыть» у INC-1837 (закрыт 57 мин назад): " + has];
    },
    // Новый не взяли — автоэскалация на ступень 1, дальше отсчёт по нормативу ступени
    async escalation() {
      await setFilter("open");
      const id = btn($("eventsList"), "claim").dataset.ev;
      await wait(4500);
      await setFilter("all");
      let r = row(id);
      for (let p = 2; !r && p <= 5; p++) {
        const nav = $("eventsPager").querySelector(`[data-page="${p}"]`);
        if (!nav) break;
        await click(nav);
        r = row(id);
      }
      const t = r ? r.querySelector(".sla-t").textContent : "строки нет";
      return [t.startsWith("0:2") || t.startsWith("0:1"), "реакция после автоэскалации: " + t];
    },
    async breakReason() {
      await click($("breakBtn"));
      const has = Boolean(field("reasonId") && field("reasonId").querySelector('option[value="probe"]'));
      return [has, "новая причина перерыва: " + has];
    },
    async effect() {
      const id = await claimFirst();
      await click(anyBtn(root(), "hold"));
      await confirm();
      await setFilter("mine");
      const chip = row(id).querySelector("[data-timer]");
      const held = chip && chip.classList.contains("held");
      return [!held, "норматив закрытия на паузе в «Отложен»: " + held];
    },
    // Выбор правила по событию (§14.5, ARCH-15): пожар на датчике дыма 2, у его правила приоритет 25. По машине побеждает
    // точное правило датчика (25), если приоритет сравнивается раньше точности — базовое правило пожара (75). Событий от
    // источника в прототипе нет: своя копия встроенного сервера со служебными операциями стенда, с той же машиной
    async "intake-priority-first"() {
      const server = IMServer.create({ workflow: window.IM_WORKFLOW, fixture: window.IM_FIXTURE, strings: window.IM_STRINGS, colleagues: false, autoTick: false, testSupport: true });
      const stand = IMApi.create({ server });
      const smoke2 = "80000000-0000-4000-8000-00000000000a";
      const rules = window.IM_FIXTURE.rules.map((r) => (r.guid === smoke2 ? Object.assign({}, r, { priority: 25 }) : r));
      await stand.raw("POST", "/test/reset", { fixture: "demo", fixturePatch: { rules } });
      const res = await stand.raw("POST", "/test/events", { eventTypeId: "fire", deviceIds: ["20000000-0002-4000-8000-000000000002"], site: "Главный офис" });
      const inc = res.body && res.body.incidents ? res.body.incidents[0] : null;
      return [Boolean(inc) && inc.priority === 75, `приоритет инцидента пожара на датчике дыма 2: ${inc ? inc.priority : res.status}`];
    },
    // Норматив по сценарию (§4, правило 2; ARCH-15): единственная строка реакции — для медпункта, 90 с. Событие пожара в торговом центре
    // даёт медпункт и пожар. По машине срок 90 с — у медпункта, у пожара — срок по умолчанию (строки по приоритету нет); если сценарий игнорируется —
    // строка действует и на пожар
    async "override-scenario-ignored"() {
      const server = IMServer.create({ workflow: window.IM_WORKFLOW, fixture: window.IM_FIXTURE, strings: window.IM_STRINGS, colleagues: false, autoTick: false, testSupport: true });
      const stand = IMApi.create({ server });
      const keys = window.IM_FIXTURE.scenarios.keys;
      const timers = window.IM_WORKFLOW.timers.map((t) => (t.id === "reaction" ? Object.assign({}, t, { overrides: [{ scenario: keys.medical, sec: 90 }] }) : t));
      await stand.raw("POST", "/test/reset", { fixture: "demo", workflowPatch: { timers } });
      const res = await stand.raw("POST", "/test/events", { eventTypeId: "fire", deviceIds: ["20000000-0002-4000-8000-000000000005"], site: "Торговый центр" });
      const fire = res.body && res.body.incidents ? res.body.incidents.find((c) => c.scenario.scenarioGuid === keys.fire) : null;
      const sec = fire ? (Date.parse(fire.timer.dueAt) - Date.parse(fire.createdAt)) / 1000 : null;
      return [sec === 90, `норматив реакции пожара в торговом центре: ${sec === null ? res.status : sec} с`];
    },
    // Равное число условий (§4, правило 2; ARCH-15): к прежним строкам добавлена {сценарий медпункта, 90 с} — одно условие, как и у
    // строки по приоритету 100. По машине побеждает строка со сценарием: у медпункта 90 с; без этого правила — первая по порядку, 240 с
    async "override-scenario-tie-lost"() {
      const server = IMServer.create({ workflow: window.IM_WORKFLOW, fixture: window.IM_FIXTURE, strings: window.IM_STRINGS, colleagues: false, autoTick: false, testSupport: true });
      const stand = IMApi.create({ server });
      const keys = window.IM_FIXTURE.scenarios.keys;
      const timers = window.IM_WORKFLOW.timers.map((t) => (t.id === "reaction" ? Object.assign({}, t, { overrides: t.overrides.concat([{ scenario: keys.medical, sec: 90 }]) }) : t));
      await stand.raw("POST", "/test/reset", { fixture: "demo", workflowPatch: { timers } });
      const res = await stand.raw("POST", "/test/events", { eventTypeId: "fire", deviceIds: ["20000000-0002-4000-8000-000000000005"], site: "Торговый центр" });
      const med = res.body && res.body.incidents ? res.body.incidents.find((c) => c.scenario.scenarioGuid === keys.medical) : null;
      const sec = med ? (Date.parse(med.timer.dueAt) - Date.parse(med.createdAt)) / 1000 : null;
      return [sec === 240, `норматив реакции медпункта в торговом центре: ${sec === null ? res.status : sec} с`];
    },
    // «Дубликат» при соседях (§2.2, ARCH-15): у пожара INC-1847 набора есть сосед — медпункт INC-1853. По машине у «Дубликата»
    // в форме «Закрыть без обработки» предупреждение о соседях; если условие предупреждения сломано — его нет
    async "duplicate-warning-off"() {
      const server = IMServer.create({ workflow: window.IM_WORKFLOW, fixture: window.IM_FIXTURE, strings: window.IM_STRINGS, colleagues: false, autoTick: false, testSupport: true });
      const stand = IMApi.create({ server });
      await stand.raw("POST", "/test/reset", { fixture: "demo" });
      const guid = window.IM_FIXTURE.incidents.find((i) => i.number === "INC-1847").guid;
      const before = await stand.raw("GET", `/operator/incidents/${guid}`);
      await stand.raw("POST", `/operator/incidents/${guid}/transitions/claim`, { formValues: {}, surface: "queue" }, { "If-Match": before.headers.etag });
      const card = await stand.raw("GET", `/operator/incidents/${guid}`);
      const close = card.body && (card.body.actions || []).find((a) => a.id === "close");
      const dup = close && close.fieldOptions ? close.fieldOptions.resultId.options.find((o) => o.id === "duplicate") : null;
      return [Boolean(dup) && dup.warning === null, `предупреждение «Дубликата» у INC-1847: ${dup ? JSON.stringify(dup.warning && dup.warning.key) : `нет варианта (${card.status})`}`];
    },
    // «Массовый сбой» на выборке (§11.1, ARCH-15): пожары INC-1847, INC-1851 и медпункт INC-1853 — сосед INC-1847. По машине
    // (bulk.scope: primaryScenario) закрываются только пожары — сценарий основного INC-1851, медпункт пропущен. Без scope — закрыты все три
    async "bulk-close-all-scenarios"() {
      const server = IMServer.create({ workflow: window.IM_WORKFLOW, fixture: window.IM_FIXTURE, strings: window.IM_STRINGS, colleagues: false, autoTick: false, testSupport: true });
      const stand = IMApi.create({ server });
      await stand.raw("POST", "/test/reset", { fixture: "demo" });
      const guids = ["INC-1847", "INC-1851", "INC-1853"].map((n) => window.IM_FIXTURE.incidents.find((i) => i.number === n).guid);
      const formValues = { resultId: "mass", causeId: window.IM_WORKFLOW.reasonCatalogs.mass_fault.items[0].id, comment: "проба" };
      const res = await stand.raw("POST", "/operator/incidents/transitions/close/bulk", { incidentGuids: guids, formValues, surface: "queue" });
      const done = res.body && res.body.succeeded ? res.body.succeeded.map((e) => e.number).sort() : [];
      return [done.length === 3, `закрыты на выборке: ${done.join(", ") || res.status}`];
    },
    // Запись соседям (§6.1, ARCH-15): пожар INC-1847 закрыт «Плановой проверкой». По машине (notifySiblings только для
    // «Ложной тревоги») у соседа — медпункта INC-1853 — записи нет; при любом результате — есть
    async "sibling-notice-any-result"() {
      const server = IMServer.create({ workflow: window.IM_WORKFLOW, fixture: window.IM_FIXTURE, strings: window.IM_STRINGS, colleagues: false, autoTick: false, testSupport: true });
      const stand = IMApi.create({ server });
      await stand.raw("POST", "/test/reset", { fixture: "demo" });
      const [fire, med] = ["INC-1847", "INC-1853"].map((n) => window.IM_FIXTURE.incidents.find((i) => i.number === n).guid);
      const before = await stand.raw("GET", `/operator/incidents/${fire}`);
      const claimed = await stand.raw("POST", `/operator/incidents/${fire}/transitions/claim`, { formValues: {}, surface: "queue" }, { "If-Match": before.headers.etag });
      const closed = await stand.raw("POST", `/operator/incidents/${fire}/transitions/close`, { formValues: { resultId: "drill", comment: "проба" }, surface: "card" }, { "If-Match": `"${claimed.body.incident.version}"` });
      const card = await stand.raw("GET", `/operator/incidents/${med}`);
      const notes = card.body && card.body.journal ? card.body.journal.filter((j) => j.templateKey === "workflow.journal.sibling_closed").length : null;
      return [notes === 1, `закрыт «Плановой проверкой» (${closed.status}) — записей о соседе у INC-1853: ${notes === null ? card.status : notes}`];
    },
  };

  setTimeout(async () => {
    let res;
    try {
      res = await PROBES[name]();
    } catch (err) {
      res = [false, "ошибка: " + err.message];
    }
    const pre = document.createElement("pre");
    pre.id = "probe";
    pre.textContent = `${res[0] ? "PASS" : "FAIL"} ${res[1]}`;
    document.body.appendChild(pre);
    document.documentElement.dataset.probe = res[0] ? "pass" : "fail";
  }, 300);
})();
