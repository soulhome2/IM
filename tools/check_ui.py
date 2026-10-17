#!/usr/bin/env python3
"""Проверка экрана прототипа (PROC-25): то, что видит оператор, а не логика.

Запуск: python3 tools/check_ui.py [--chrome путь] [--only часть-имени] [--shots папка]

Chrome без окна по протоколу DevTools — тот же, что у tools/shots.py. Основные экраны — очередь,
карточки, формы, выборка, привязанные, настройки, меню — в светлой и тёмной теме, на 1440×900 и
на телефоне 360×800. На каждом экране, только видимое:
- пустой текст: бейдж, кнопка, вкладка без текста и без подписи; подстановка, оставшаяся пустой
  («Отложен · »);
- контраст текста не ниже 4,5:1, крупного — 3:1 (WCAG), включая кнопки; недоступные не считаются;
- ширина: страница не шире экрана, кнопки и поля не за краем экрана и не за краем своей панели;
- тексты: нет ключей каталога workflow.… вместо текста, нет подсказок с клавишами — их нет (§13).

Логику проверяют самопроверка и тесты API; эта проверка — о том, как это выглядит и можно ли
до этого дотянуться. --shots папка — сохранить снимки экранов, чтобы посмотреть их глазами
(ревью, роли «дизайнер» и «UX»). В репозиторий снимки не пишутся.

Известные проблемы — в KNOWN с номером пункта плана: печатаются как ИЗВЕСТНО и проверку не
роняют. Исправили пункт — уберите его строку: известная проблема, которая не воспроизводится,
роняет проверку, чтобы список не устаревал.
"""

import argparse
import json
import os
import re
import shutil
import sys
import time
from pathlib import Path

import shots as S

DESKTOP = S.DESKTOP
PHONE = (360, 800)
CLAIM = ["#eventsList button[data-do=claim]"]

# Экран: имя и подготовка — щелчки и фильтры, как в tools/shots.py; уведомления убираются: они
# временные и перекрывают экран
SCREENS = [
    ("очередь", []),
    ("очередь «Чужие»", S.FOREIGN),
    ("очередь «Завершённые»", [("filter", "done")]),
    ("своя карточка", CLAIM),
    ("форма «Закрыть»", CLAIM + ["#scenarioRoot button[data-do=close]"]),
    ("форма «Отложить»", CLAIM + ["#scenarioRoot button[data-do=hold]"]),
    ("форма «Передать»", ["#eventsList button[data-do=transfer]", ".target-combo .mselect-input"]),
    ("чужая карточка", S.FOREIGN + ["#eventsList button[data-do=view]"]),
    ("закрытая карточка", [("filter", "done"), "#eventsList button[data-do=view]"]),
    ("панель выборки", S.TICK_THREE),
    ("поиск в дереве", [("groups", "конференц")]),
    ("окно «Выделить по фильтру»", ["#groupsList .tree-all [data-filter='select']"]),
    ("привязанные инциденты", S.MERGE_FIRES),
    ("настройки администратора", ["#userBtn", "#adminBtn"]),
    ("меню справки", ["#helpBtn"]),
    ("меню пользователя", ["#userBtn"]),
]

# Известные проблемы: пункт плана и как узнать его проблему. Исправили — уберите строку
KNOWN = [
    ("BUG-56", "приглушённый текст --faint и --muted светлой темы ниже 4,5:1", lambda p: p["kind"] == "контраст" and p.get("muted")),
]

# Проверки на открытом экране. Если открыто окно (.modal) — проверяется только оно: остальное под
# затемнением. Кадр камеры и план — картинки: их подписи поверх изображения здесь не считаются
CHECK = r"""(() => {
  // Мигание и переходы меняют прозрачность на время — меряем установившийся вид
  const still = document.createElement('style');
  still.textContent = '*, *::before, *::after { animation: none !important; transition: none !important; }';
  document.head.appendChild(still);
  document.body.offsetHeight;
  const out = [];
  const modal = document.querySelector('.modal:not([hidden])');
  const scope = modal || document.body;
  const vw = innerWidth;
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    for (let e = el; e; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.display === 'none' || cs.visibility === 'hidden' || Number(cs.opacity) === 0) return false;
    }
    return true;
  };
  const say = (el) => (el.id ? '#' + el.id : el.tagName.toLowerCase() + (el.classList[0] ? '.' + el.classList[0] : ''));
  const textOf = (el) => (el.textContent || '').replace(/\s+/g, ' ').trim();
  const add = (kind, el, detail, extra) => out.push(Object.assign({ kind, el: say(el), text: textOf(el).slice(0, 60) || el.getAttribute('aria-label') || el.title || '', detail }, extra));
  // Приглушённые цвета темы (--faint, --muted): текст этих цветов — отдельный пункт плана
  const tone = (v) => {
    const probe = document.createElement('span');
    probe.style.color = 'var(' + v + ')';
    document.body.appendChild(probe);
    const c = getComputedStyle(probe).color;
    probe.remove();
    return c;
  };
  const MUTED = [tone('--faint'), tone('--muted')];
  // Целиком за краем экрана — выдвижная панель в спрятанном положении (группы на телефоне): не видна
  const onScreen = (el) => { const r = el.getBoundingClientRect(); return r.right > 0 && r.left < vw; };
  const IMAGE = '#videoStage .cam, #mapRoot, svg';
  const all = [...scope.querySelectorAll('*')].filter((el) => visible(el) && onScreen(el));

  // Пустой текст и пустые подстановки
  all.filter((el) => el.matches('.badge, button, [role=tab], .chip, .menu-item')).forEach((el) => {
    const t = textOf(el);
    if (!t && !el.getAttribute('aria-label') && !el.title) add('пусто', el, 'нет текста и подписи');
    else if (/(^·|·$|· ·)/.test(t)) add('пусто', el, 'пустая подстановка: «' + t + '»');
  });

  // Контраст: элементы с собственным текстом
  const parse = (c) => {
    const n = (c.match(/[\d.]+/g) || []).map(Number);
    const k = c.startsWith('color(') ? 255 : 1;
    return { r: n[0] * k, g: n[1] * k, b: n[2] * k, a: n[3] == null ? 1 : n[3] };
  };
  const over = (top, base) => ({ r: top.r * top.a + base.r * (1 - top.a), g: top.g * top.a + base.g * (1 - top.a), b: top.b * top.a + base.b * (1 - top.a) });
  const lum = ({ r, g, b }) => {
    const f = (v) => ((v /= 255) <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const ratio = (el) => {
    const layers = [];
    let alpha = 1;
    for (let e = el; e; e = e.parentElement) {
      alpha *= Number(getComputedStyle(e).opacity);
      const c = parse(getComputedStyle(e).backgroundColor);
      if (c.a > 0) layers.push(c);
      if (c.a >= 1) break;
    }
    let bg = { r: 255, g: 255, b: 255 };
    layers.reverse().forEach((c) => (bg = over(c, bg)));
    const fgc = parse(getComputedStyle(el).color);
    const fg = over({ ...fgc, a: fgc.a * alpha }, bg);
    const [hi, lo] = [lum(fg), lum(bg)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  };
  all.forEach((el) => {
    const own = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
    if (!own || el.closest(IMAGE) || el.matches('input, textarea, select, option, .material-symbols-outlined')) return;
    if (el.closest(':disabled, [aria-disabled="true"]')) return;
    const cs = getComputedStyle(el);
    const size = parseFloat(cs.fontSize);
    const large = size >= 24 || (size >= 18.66 && Number(cs.fontWeight) >= 700);
    const r = ratio(el);
    if (r < (large ? 3 : 4.5)) add('контраст', el, r.toFixed(2) + ':1, нужно ' + (large ? '3' : '4,5'), { muted: MUTED.includes(cs.color) && document.documentElement.dataset.theme === 'light' });
  });

  // Ширина: страница и элементы управления — внутри экрана и внутри своей прокручиваемой панели
  if (document.documentElement.scrollWidth > vw + 1) out.push({ kind: 'ширина', el: 'html', text: '', detail: 'страница ' + document.documentElement.scrollWidth + ' px при экране ' + vw });
  all.filter((el) => el.matches('button, a[href], input, select, textarea, [role=tab]')).forEach((el) => {
    const r = el.getBoundingClientRect();
    if (r.right > vw + 1 || r.left < -1) return add('ширина', el, 'за краем экрана: ' + Math.round(r.left) + '…' + Math.round(r.right) + ' px из ' + vw);
    for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
      const ox = getComputedStyle(p).overflowX;
      if (ox === 'visible') continue;
      const pr = p.getBoundingClientRect();
      if (r.right > pr.right + 1 || r.left < pr.left - 1) add('ширина', el, 'за краем ' + say(p) + ': ' + Math.round(r.right) + ' px при правом крае ' + Math.round(pr.right));
      break;
    }
  });

  // Тексты: ключи каталога и подсказки с клавишами
  const KEY = /\bworkflow\.[a-z_]+\./;
  const HOTKEY = /\((?:[←→↑↓]|Esc|Enter|Tab|Ctrl|Alt|Shift|F\d+)[^)]*\)|\b(?:Ctrl|Alt|Shift)\s*\+/;
  all.forEach((el) => {
    const own = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join(' ');
    for (const s of [own, el.title || '', el.getAttribute('aria-label') || '', el.getAttribute('placeholder') || '']) {
      if (KEY.test(s)) add('ключ', el, 'ключ каталога вместо текста: «' + s.trim().slice(0, 60) + '»');
      if (HOTKEY.test(s)) add('клавиша', el, 'подсказка с клавишей, а горячих клавиш нет (§13): «' + s.trim().slice(0, 60) + '»');
    }
  });
  still.remove();
  return JSON.stringify(out);
})()"""


# Время и отсчёты на экране меняются от прогона к прогону: в сравнении проблем цифры не важны
def digits(s):
    return re.sub(r"\d+", "#", s)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--chrome", default=shutil.which("google-chrome") or shutil.which("chromium") or shutil.which("chromium-browser"))
    ap.add_argument("--only", default="", help="проверять только экраны, в имени которых есть эта строка")
    ap.add_argument("--shots", default="", help="папка для снимков экранов — посмотреть глазами")
    args = ap.parse_args()
    if not args.chrome:
        print("Не нашёл Chrome: укажите путь --chrome")
        return 1
    shots = Path(args.shots) if args.shots else None
    if shots:
        shots.mkdir(parents=True, exist_ok=True)
    b = S.Browser(args.chrome, ("--no-sandbox",) if os.environ.get("CI") else ())
    problems, broken = [], []
    try:
        for size in (DESKTOP, PHONE):
            for theme in ("light", "dark"):
                for name, prepare in SCREENS:
                    if args.only not in name:
                        continue
                    where = f"{name} · {theme} · {size[0]}"
                    try:
                        S.open_page(b, theme, size, size == PHONE)
                        for step in prepare:
                            S.prepare_step(b, step)
                        S.prepare_step(b, ("quiet", None))
                        time.sleep(0.3)
                        found = json.loads(b.eval(CHECK))
                    except RuntimeError as e:
                        broken.append(f"{where}: экран не открылся — {e}")
                        continue
                    for p in found:
                        p.update(screen=name, theme=theme, size=str(size[0]))
                    problems += found
                    if shots:
                        S.capture(b, shots / f"{name} · {theme} · {size[0]}.png".replace("/", "-"), None, 0, 0, size)
    finally:
        b.close()

    # Одна и та же проблема на нескольких экранах — одной строкой со списком мест
    grouped = {}
    for p in problems:
        key = (p["kind"], p["el"], digits(p["text"]), digits(p["detail"]))
        grouped.setdefault(key, []).append(f"{p['screen']} · {p['theme']} · {p['size']}")
    known_hits = {item: 0 for item, _, _ in KNOWN}
    failed = 0
    for (kind, el, text, detail), places in sorted(grouped.items()):
        sample = next(p for p in problems if (p["kind"], p["el"], digits(p["text"]), digits(p["detail"])) == (kind, el, text, detail))
        item = next((i for i, _, match in KNOWN if match(sample)), None)
        where = places[0] + (f" и ещё {len(places) - 1}" if len(places) > 1 else "")
        line = f"{kind}: {el} «{sample['text']}» — {sample['detail']} ({where})"
        if item:
            known_hits[item] += 1
            print(f"ИЗВЕСТНО {item}  {line}")
        else:
            failed += 1
            print(f"FAIL  {line}")
    for item, what, _ in KNOWN:
        if not known_hits[item] and not args.only:
            failed += 1
            print(f"FAIL  {item} ({what}) больше не воспроизводится — уберите его из KNOWN в tools/check_ui.py")
    for line in broken:
        failed += 1
        print(f"FAIL  {line}")
    print(f"Проблем на экране: {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
