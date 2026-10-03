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
  const key = async (k) => {
    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true }));
    await wait();
  };
  const row = (id) => $("eventsList").querySelector(`[data-id="${id}"]`);
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
    await click($("dialogConfirm"));
  }

  const PROBES = {
    async modalKey() {
      await setFilter("open");
      await key("?");
      await key("n");
      return [mode() === "work", "при открытой справке N взял инцидент: " + (mode() === "work")];
    },
    async selfTarget() {
      const id = await claimFirst();
      await click(anyBtn(root(), "transfer"));
      const target = field("targetId");
      const has = Boolean(target && target.querySelector('option[value="grp-leads"]'));
      if (has) target.value = "grp-leads";
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
    async autoEscalation() {
      await setFilter("open");
      const id = btn($("eventsList"), "claim").dataset.ev;
      await click(btn($("eventsList"), "transfer", id));
      field("targetId").value = "sidorov";
      await confirm("проба");
      await setFilter("foreign");
      await click(btn($("eventsList"), "open_readonly", id));
      const opened = mode() === "work";
      await wait(4000);
      const toasts = [...$("toasts").children].map((x) => x.textContent).join(" | ");
      const escalated = toasts.includes("Автоэскалация");
      return [opened && escalated && mode() === "work", `автоэскалация: ${escalated}, карточка открыта: ${mode() === "work"}`];
    },
    async groupTarget() {
      await setFilter("open");
      const id = btn($("eventsList"), "claim").dataset.ev;
      await click(btn($("eventsList"), "transfer", id));
      field("targetId").value = "sidorov";
      await confirm("проба");
      await wait(3500);
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
      await click(btn($("eventsList"), "reopen", "INC-1837"));
      await confirm("проба");
      const m = $("statusSla").textContent.match(/(\d+):(\d\d)/);
      const sec = m ? Number(m[1]) * 60 + Number(m[2]) : -1;
      return [sec > 0 && sec <= 60, "после переоткрытия: " + $("statusSla").textContent];
    },
    async exclude() {
      const sel = $("eventTypeFilter");
      let pair = null;
      for (const o of [...sel.options].filter((x) => x.value !== "all")) {
        sel.value = o.value;
        sel.dispatchEvent(new Event("change"));
        await wait();
        const ids = [...$("eventsList").querySelectorAll(".event")]
          .filter((r) => r.querySelector('[data-do="claim"]:not([aria-disabled="true"])'))
          .map((r) => r.dataset.id);
        if (ids.length >= 2) {
          pair = ids.slice(0, 2);
          break;
        }
      }
      await click($("eventsList").querySelector(`[data-check="${pair[0]}"]`));
      await click($("eventsList").querySelector(`[data-check="${pair[1]}"]`));
      await click(btn($("eventsList"), "claim", pair[0]));
      const b = root().querySelector("[data-exclude]");
      return [Boolean(b && !off(b)), "«Исключить из группы» активна: " + Boolean(b && !off(b))];
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
      return [Boolean(b), "второе «Взять» доступно: " + Boolean(b)];
    },
    async norm() {
      await setFilter("open");
      const t = row("INC-1847").querySelector(".sla-t").textContent;
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
    async hotkey() {
      await setFilter("open");
      await key("n");
      const afterN = mode();
      await key("m");
      return [afterN === "queue" && mode() === "work", `после N: ${afterN}, после M: ${mode()}`];
    },
    async filter() {
      await setFilter("mine");
      return [Boolean(row("INC-1837")), "закрытый свой INC-1837 во «Мои»: " + Boolean(row("INC-1837"))];
    },
    async badge() {
      await setFilter("open");
      const b = row("INC-1847").querySelector(".badge").textContent;
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
    async grouping() {
      await setFilter("open");
      const rows = [...$("eventsList").querySelectorAll(".event")].filter((r) => r.querySelector('[data-do="claim"]:not([aria-disabled="true"])'));
      const a = rows[0];
      const b = rows.find((r) => r.querySelector(".event-title strong").textContent !== a.querySelector(".event-title strong").textContent);
      // Список перерисовывается после каждой галочки: строки ищем заново по номеру
      await click($("eventsList").querySelector(`[data-check="${a.dataset.id}"]`));
      await click($("eventsList").querySelector(`[data-check="${b.dataset.id}"]`));
      await click(btn($("eventsList"), "claim", a.dataset.id));
      if (mode() === "work") await click($("backToQueue"));
      await setFilter("mine");
      const both = Boolean(row(a.dataset.id) && row(b.dataset.id));
      const toasts = [...$("toasts").children].map((x) => x.textContent).join(" | ");
      return [both, "разнотипные взяты группой: " + both + " · " + toasts];
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
      const has = Boolean(anyBtn($("eventsList"), "reopen", "INC-1837"));
      return [!has, "«Переоткрыть» у INC-1837 (закрыт 12 мин назад): " + has];
    },
    async escalation() {
      const id = await claimFirst();
      await click(anyBtn(root(), "transfer"));
      field("targetId").value = "sidorov";
      await confirm("проба");
      await setFilter("all");
      let r = row(id);
      for (let p = 2; !r && p <= 5; p++) {
        const nav = $("eventsPager").querySelector(`[data-page="${p}"]`);
        if (!nav) break;
        await click(nav);
        r = row(id);
      }
      const t = r.querySelector(".sla-t").textContent;
      return [t.startsWith("0:2") || t.startsWith("0:3"), "реакция после передачи: " + t];
    },
    async escape() {
      await claimFirst();
      await key("Escape");
      return [mode() === "work", "после Esc режим: " + mode()];
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
