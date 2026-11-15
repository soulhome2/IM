/* Звук оператора — функция решения «звучать или нет» (правила §21, план 87б). Чистые функции над данными, без DOM
   и без звука: сам звук (AudioContext, рецепты по id из sound.patterns) — в интерфейсе. Конфигуратор повторяет то же
   в src/operator/sound/decide.ts; обе реализации проходят векторы Specification/Workflow_machine/fixtures/sound-vectors.json
   (node tools/sound_vectors.mjs --check).

   Что звучит, решается только по полям события и инцидента из контракта (§14.10, §21.7): stateCategory, ownership,
   addressee, maintenanceWindowId, payload.state.from/to (только «равно / не равно»), payload.addressedToMe, actor.id.
   Имён состояний и переходов здесь нет.

   SoundState = { sounding: Sounding[], attention: guid[] }
     sounding  — что повторяется до взятия сейчас (снимает «Тихо», перерыв, взятие);
     attention — непринятые инциденты, которые повторяются до взятия: по приоритету в «Новом» без адресата и «лично вам»
                 (число в заголовке вкладки, §21.6). Зеркало очереди: от «Тихо», состояния оператора и автора события
                 не зависит, меняется, когда инцидент перестал или начал подходить.
   Sounding = { guid, number, kind: 'priority'|'personal'|'alert', priority, cue: SoundCue, since } */
(() => {
  const LEVEL_KEY = /^(0|[1-9][0-9]?|100)$/;
  const UNTIL = "until_taken";

  // Звук по числу уровня: своя строка или ближайшая ниже; ниже самой низкой — null (§21.2)
  function cueForPriority(byPriority, level) {
    let best = null;
    let bestKey = -1;
    for (const key of Object.keys(byPriority || {})) {
      if (!LEVEL_KEY.test(key)) continue;
      const n = Number(key);
      if (n <= level && n > bestKey && byPriority[key]) {
        best = byPriority[key];
        bestKey = n;
      }
    }
    return best;
  }

  const quiet = (inc) => inc.maintenanceWindowId != null || inc.stateCategory === "linked";
  const pending = (inc) => inc.stateCategory === "pending";
  const priorityCue = (inc, settings) => cueForPriority(settings.byPriority, inc.priority);
  // Подходит ли инцидент под свой вид — пока подходит, повтор держится (§21.2, «Повтор снимается»)
  function fits(kind, inc, settings) {
    if (!inc || quiet(inc) || !pending(inc)) return false;
    if (kind === "personal") return inc.ownership === "target";
    if (kind === "priority") {
      const cue = priorityCue(inc, settings);
      return inc.addressee == null && !!cue && cue.repeat === UNTIL;
    }
    return false;
  }
  // Непринятый, который повторяется до взятия: «лично вам» или по приоритету
  const awaits = (inc, settings) => (settings.personal.repeat === UNTIL && fits("personal", inc, settings)) || fits("priority", inc, settings);

  // Слышит ли оператор звук этого вида сейчас (§21.3, §21.4)
  function hears(kind, cue, priority, ctx) {
    const st = ctx.agentState;
    if (st !== "ready" && st !== "busy") return false;
    if (st === "busy") {
      const b = ctx.settings.busyHears;
      if (kind === "priority" && (b.minPriority == null || priority < b.minPriority)) return false;
      if (kind === "personal" && !b.personal) return false;
      if (kind === "alert" && !b.alert) return false;
    }
    if (ctx.onlyImportantUntil != null && ctx.now < ctx.onlyImportantUntil) {
      if (kind === "alert") return false;
      if (kind === "priority" && cue.repeat !== UNTIL) return false;
    }
    return true;
  }

  const sounding = (inc, kind, cue, now) => ({ guid: inc.guid, number: inc.number, kind, priority: inc.priority, cue, since: now });
  const filterHeard = (state, ctx) => ({ sounding: state.sounding.filter((s) => hears(s.kind, s.cue, s.priority, ctx)), attention: state.attention });

  // Вид события: что звучит (шаг 3 порядка решения); null — не звучит
  function classify(event, settings) {
    const inc = event.incident;
    if (!inc || quiet(inc)) return null;
    const p = event.payload || {};
    if (event.type === "incident.alert") return { kind: "alert", cue: settings.alert };
    if (event.type !== "incident.created" && event.type !== "incident.transitioned") return null;
    if (!pending(inc)) return null;
    const personal = event.type === "incident.created" ? inc.ownership === "target" : p.addressedToMe === true && inc.ownership === "target";
    if (personal) return { kind: "personal", cue: settings.personal };
    const back = event.type === "incident.created" || (p.state && p.state.from !== p.state.to);
    if (back && inc.addressee == null) {
      const cue = priorityCue(inc, settings);
      return cue ? { kind: "priority", cue } : null;
    }
    return null;
  }

  function decideSound(state, event, ctx) {
    const settings = ctx.settings;
    let snd = state.sounding.slice();
    let att = state.attention.slice();
    const inc = event.incident || null;
    // 1. Снятие: событие касается инцидента — проверить, подходит ли он ещё
    if (event.type === "incident.access_lost" || (inc == null && event.incidentGuid)) {
      const number = event.payload && event.payload.number;
      const gone = new Set(snd.filter((s) => s.guid === event.incidentGuid || (number && s.number === number)).map((s) => s.guid));
      if (event.incidentGuid) gone.add(event.incidentGuid);
      snd = snd.filter((s) => !gone.has(s.guid));
      att = att.filter((g) => !gone.has(g));
    } else if (inc) {
      snd = snd.filter((s) => s.guid !== inc.guid || fits(s.kind, inc, settings));
      const has = att.includes(inc.guid);
      const now = awaits(inc, settings);
      if (has && !now) att = att.filter((g) => g !== inc.guid);
      else if (!has && now) att.push(inc.guid);
    }
    let play = null;
    const actorId = event.actor && event.actor.id;
    // 2. Своё не звучит; 3. вид события; 4. кто слышит; 5. звук
    const c = actorId != null && actorId === ctx.meGuid ? null : classify(event, settings);
    if (c && c.cue.repeat !== "none" && hears(c.kind, c.cue, inc.priority, ctx)) {
      play = sounding(inc, c.kind, c.cue, ctx.now);
      if (c.kind !== "alert" && c.cue.repeat === UNTIL) {
        const i = snd.findIndex((s) => s.guid === inc.guid);
        if (i >= 0) snd[i] = play;
        else snd.push(play);
      }
    }
    return { state: filterHeard({ sounding: snd, attention: att }, ctx), play };
  }

  // «Тихо»: звучащее молкнет, внимание остаётся (§21.4)
  const silence = (state) => ({ sounding: [], attention: state.attention.slice() });

  // Сменилось состояние оператора или «Только важное»: звучит только то, что он теперь слышит. Вернулся — снятое
  // не возобновляется до нового события или перечитывания очереди
  const applyCtx = (state, ctx) => filterHeard({ sounding: state.sounding.slice(), attention: state.attention.slice() }, ctx);

  // Перечитанная очередь (загрузка, переподключение, stream.reset, §21.1): повторяющиеся до взятия возобновляются без
  // залпа — play нет, первый сигнал по расписанию повтора (planRepeats); «один раз» задним числом не играет
  function restoreSound(queue, ctx) {
    const settings = ctx.settings;
    const snd = [];
    const att = [];
    for (const inc of queue || []) {
      if (!awaits(inc, settings)) continue;
      att.push(inc.guid);
      const kind = settings.personal.repeat === UNTIL && fits("personal", inc, settings) ? "personal" : "priority";
      const cue = kind === "personal" ? settings.personal : priorityCue(inc, settings);
      if (hears(kind, cue, inc.priority, ctx)) snd.push(sounding(inc, kind, cue, ctx.now));
    }
    return { sounding: snd, attention: att };
  }

  // Кому звучать повтором: наибольший приоритет; при равном — «лично вам»; дальше — кто раньше зазвучал (§21.2)
  function topSounding(state) {
    let top = null;
    for (const s of state.sounding) {
      if (
        !top ||
        s.priority > top.priority ||
        (s.priority === top.priority && s.kind === "personal" && top.kind !== "personal") ||
        (s.priority === top.priority && (s.kind === "personal") === (top.kind === "personal") && s.since < top.since)
      )
        top = s;
    }
    return top;
  }

  // Моменты повтора на часах AudioContext: шаг repeatSec, первый — через шаг после start, на horizonSec вперёд
  function planRepeats(top, startCtxTime, horizonSec = 120) {
    if (!top || top.cue.repeat !== UNTIL || !(top.cue.repeatSec > 0)) return [];
    const out = [];
    for (let k = 1; k * top.cue.repeatSec <= horizonSec; k++) out.push(startCtxTime + k * top.cue.repeatSec);
    return out;
  }

  window.IMSound = { cueForPriority, decideSound, silence, applyCtx, restoreSound, topSounding, planRepeats };
})();
