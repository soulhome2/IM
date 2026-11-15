/* Звук оператора — синтез и вывод (правила §21, план 87б). Решение «звучать или нет» — в sound.js (IMSound.decideSound
   и др.); здесь только как звучит: рецепты пяти встроенных звуков (id — sound.patterns машины), вывод через Web Audio,
   громкость рабочего места. Рецепты — те же, что в конфигураторе (src/shared/sound/synth.ts): прототип и продукт звучат
   одинаково. Звуки различаются ритмом, а не только высотой (IEC 60601-1-8).

   IMSound.output — адаптер вывода: { ready(), unlock(), now(), play(pattern, at, volume) → handle, stop(handle) }.
   now() и at — часы вывода в секундах (у Web Audio — AudioContext.currentTime): повтор планируется на них заранее,
   а не setTimeout, — так он держится и в свёрнутой вкладке. Самопроверка подменяет адаптер записью { pattern, at }
   и своими часами. До разблокировки (первое нажатие на странице) ready() — false: ничего не играет. */
(() => {
  const S = window.IMSound;

  const series = (count, step, make) => Array.from({ length: count }, (_, i) => make(i, i * step));
  // Тон: at — сдвиг от начала звука, dur — длина, freq → freqEnd — качание, env: pluck — затухает сразу, flat — держится
  const PATTERNS = {
    // Частая серия коротких качаний вверх и вниз — самое срочное
    siren: series(7, 0.3, (i, at) => ({ at, dur: 0.28, freq: i % 2 === 0 ? 600 : 1100, freqEnd: i % 2 === 0 ? 1100 : 600, type: "sawtooth", env: "flat" })),
    // Серия коротких высоких писков
    alarm: series(8, 0.25, (_i, at) => ({ at, dur: 0.12, freq: 1800, type: "square", env: "flat" })),
    // Два сигнала, второй выше
    double: [
      { at: 0, dur: 0.18, freq: 880, type: "sine", env: "flat" },
      { at: 0.3, dur: 0.18, freq: 1175, type: "sine", env: "flat" },
    ],
    // Колокол: удар с долгим затуханием
    bell: [{ at: 0, dur: 2, freq: 1320, type: "triangle", env: "pluck" }],
    // Один низкий мягкий тон
    soft: [{ at: 0, dur: 0.4, freq: 440, type: "sine", env: "flat" }],
  };
  // Проверочный сигнал при включении и «Проверить звук» (§21.4)
  const TEST_PATTERN = "double";

  const ATTACK = 0.01;
  const RELEASE = 0.03;
  const SILENT = 0.0001;

  // Звук на часах контекста с момента at; пик — volume / 100. Возвращает генераторы — их можно остановить раньше
  function playPattern(ctx, id, at, volume) {
    const recipe = PATTERNS[id];
    if (!recipe) return [];
    const peak = Math.min(100, Math.max(0, Number.isFinite(volume) ? volume : 0)) / 100;
    return recipe.map((tone) => {
      const t0 = at + tone.at;
      const t1 = t0 + tone.dur;
      const osc = ctx.createOscillator();
      const amp = ctx.createGain();
      osc.type = tone.type;
      osc.frequency.setValueAtTime(tone.freq, t0);
      if (tone.freqEnd !== undefined) osc.frequency.linearRampToValueAtTime(tone.freqEnd, t1);
      amp.gain.setValueAtTime(SILENT, t0);
      amp.gain.linearRampToValueAtTime(peak, t0 + ATTACK);
      if (tone.env === "pluck") amp.gain.exponentialRampToValueAtTime(SILENT, t1);
      else {
        amp.gain.setValueAtTime(peak, Math.max(t0 + ATTACK, t1 - RELEASE));
        amp.gain.linearRampToValueAtTime(0, t1);
      }
      osc.connect(amp);
      amp.connect(ctx.destination);
      osc.onended = () => {
        osc.disconnect();
        amp.disconnect();
      };
      osc.start(t0);
      osc.stop(t1);
      return osc;
    });
  }

  // Вывод через Web Audio. Контекст создаётся при разблокировке: браузер не играет, пока на странице ничего не нажато
  function webAudio() {
    const AC = window.AudioContext || window.webkitAudioContext;
    let ctx = null;
    return {
      ready: () => Boolean(ctx && ctx.state === "running"),
      unlock() {
        if (!AC) return Promise.resolve(false);
        if (!ctx) ctx = new AC();
        return ctx
          .resume()
          .then(() => ctx.state === "running")
          .catch(() => false);
      },
      now: () => (ctx ? ctx.currentTime : 0),
      play: (pattern, at, volume) => (ctx ? playPattern(ctx, pattern, at, volume) : []),
      // Запланированное вперёд — остановить и отсоединить (снятие, «Тихо», перерыв, выход)
      stop(handle) {
        (handle || []).forEach((osc) => {
          try {
            osc.onended = null;
            osc.stop(0);
            osc.disconnect();
          } catch (e) {
            /* уже остановлен */
          }
        });
      },
    };
  }

  // Громкость рабочего места: выбор оператора, но не ниже порога схемы (§21.4). Помнит браузер, не сервер
  const VOLUME_KEY = "im-sound-volume";
  const DEFAULT_VOLUME = 80;
  const effectiveVolume = (choice, floor) => Math.max(Number(floor) || 0, Math.min(100, Number.isFinite(choice) ? choice : DEFAULT_VOLUME));
  function loadVolume() {
    try {
      const v = Number(localStorage.getItem(VOLUME_KEY));
      return localStorage.getItem(VOLUME_KEY) != null && Number.isFinite(v) ? v : DEFAULT_VOLUME;
    } catch (e) {
      return DEFAULT_VOLUME;
    }
  }
  function saveVolume(v) {
    try {
      localStorage.setItem(VOLUME_KEY, String(v));
    } catch (e) {
      /* хранилище недоступно — громкость до перезагрузки */
    }
  }

  Object.assign(S, { PATTERNS, TEST_PATTERN, playPattern, webAudio, output: webAudio(), effectiveVolume, loadVolume, saveVolume });
})();
