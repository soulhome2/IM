#!/usr/bin/env python3
"""Снимки экрана прототипа для дизайнера (DOC-40): prototype/shots/*.png.

Запуск: python3 tools/shots.py [--chrome путь] [--only часть-имени]

Chrome без окна, управление по протоколу DevTools: наведение и нажатие — настоящими событиями
мыши, как у человека, поэтому видны :hover и :active. Нужен только Chrome или Chromium;
Node, Playwright и дизайн-кит не нужны. Каждый снимок — с чистой загрузки страницы: нажатие
не отпускается, и действие под кнопкой не выполняется.

Что снимается: главный экран (restyled-*), состояния кнопок и элементов (state-*) — тот же набор,
что раньше снимал скрипт кита, — и экраны после переделок: форма «Передать» с полем «Кому
передать», панель выборки, вкладка «Привязанные инциденты», телефон с кнопкой «Фильтры».
Снимки оригинала до restyle (original-*) не трогаются.
"""

import argparse
import base64
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "prototype" / "shots"
PAGE = (ROOT / "prototype" / "index.html").as_uri()
DESKTOP = (1440, 900)
PHONE = (390, 844)


class WebSocket:
    """Клиент WebSocket ровно настолько, насколько нужен протоколу DevTools: текстовые кадры JSON."""

    def __init__(self, url):
        u = urllib.parse.urlparse(url)
        self.sock = socket.create_connection((u.hostname, u.port), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            (
                f"GET {u.path} HTTP/1.1\r\nHost: {u.hostname}:{u.port}\r\nUpgrade: websocket\r\n"
                f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
            ).encode()
        )
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(1)
            if not chunk:
                raise RuntimeError("DevTools закрыл соединение при рукопожатии")
            head += chunk
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise RuntimeError(f"DevTools не принял WebSocket: {head[:80]!r}")

    def _read(self, n):
        data = b""
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise RuntimeError("DevTools закрыл соединение")
            data += chunk
        return data

    def send(self, obj):
        payload = json.dumps(obj).encode()
        n = len(payload)
        if n < 126:
            head = struct.pack("!BB", 0x81, 0x80 | n)
        elif n < 65536:
            head = struct.pack("!BBH", 0x81, 0x80 | 126, n)
        else:
            head = struct.pack("!BBQ", 0x81, 0x80 | 127, n)
        mask = os.urandom(4)
        self.sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def recv(self):
        message = b""
        while True:
            b1, b2 = self._read(2)
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack("!H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack("!Q", self._read(8))[0]
            message += self._read(n)
            if b1 & 0x80:
                return json.loads(message)


class Browser:
    def __init__(self, chrome, extra=()):
        # extra — ключи Chrome сверх обычных, например --no-sandbox на CI (tools/check_ui.py)
        self.dir = tempfile.mkdtemp(prefix="im-shots-")
        self.proc = subprocess.Popen(
            [chrome, "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check", "--hide-scrollbars",
             "--allow-file-access-from-files", "--remote-debugging-port=0", f"--user-data-dir={self.dir}", *extra, "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        port_file = Path(self.dir) / "DevToolsActivePort"
        for _ in range(100):
            if port_file.exists() and port_file.read_text().strip():
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("Chrome не открыл порт DevTools")
        port = port_file.read_text().split()[0]
        pages = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
        self.ws = WebSocket(next(p for p in pages if p["type"] == "page")["webSocketDebuggerUrl"])
        self.seq = 0
        self.events = []
        self.call("Page.enable")

    def call(self, method, **params):
        self.seq += 1
        self.ws.send({"id": self.seq, "method": method, "params": params})
        while True:
            msg = self.ws.recv()
            if msg.get("id") == self.seq:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})
            self.events.append(msg.get("method"))

    def wait_event(self, name, timeout=30):
        end = time.time() + timeout
        while time.time() < end:
            if name in self.events:
                self.events.remove(name)
                return
            self.events.append(self.ws.recv().get("method"))
        raise RuntimeError(f"не дождался {name}")

    def eval(self, expr):
        r = self.call("Runtime.evaluate", expression=expr, awaitPromise=True, returnByValue=True)
        if "exceptionDetails" in r:
            raise RuntimeError(f"ошибка в странице: {r['exceptionDetails'].get('text')} — {expr[:80]}")
        return r["result"].get("value")

    def wait_for(self, expr, timeout=15):
        end = time.time() + timeout
        while time.time() < end:
            if self.eval(expr):
                return
            time.sleep(0.1)
        raise RuntimeError(f"не дождался: {expr}")

    def close(self):
        self.proc.terminate()
        try:
            self.proc.wait(5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        shutil.rmtree(self.dir, ignore_errors=True)


def find(selector):
    return f"document.querySelector({json.dumps(selector)})"


def open_page(b, theme, size, mobile):
    w, h = size
    b.call("Emulation.setDeviceMetricsOverride", width=w, height=h, deviceScaleFactor=1, mobile=mobile)
    b.events.clear()
    b.call("Page.navigate", url=PAGE)
    b.wait_event("Page.loadEventFired")
    b.eval(f"localStorage.setItem('im-theme', {json.dumps(theme)})")
    b.events.clear()
    b.call("Page.reload", ignoreCache=True)
    b.wait_event("Page.loadEventFired")
    b.wait_for("!!document.querySelector('#eventsList .event')")
    b.eval("document.fonts.ready.then(() => true)")
    time.sleep(0.4)


def rect(b, selector):
    r = b.eval(
        f"(() => {{ const e = {find(selector)}; if (!e) return null; e.scrollIntoView({{ block: 'nearest' }});"
        " const r = e.getBoundingClientRect(); return [r.x, r.y, r.width, r.height]; })()"
    )
    if not r or r[2] == 0 or r[3] == 0:
        raise RuntimeError(f"на экране нет {selector}")
    return r


def mouse(b, kind, selector):
    x, y, w, h = rect(b, selector)
    cx, cy = x + w / 2, y + h / 2
    b.call("Input.dispatchMouseEvent", type="mouseMoved", x=cx, y=cy)
    if kind == "press":
        b.call("Input.dispatchMouseEvent", type="mousePressed", x=cx, y=cy, button="left", clickCount=1)
    time.sleep(0.25)


def prepare_step(b, step):
    # Подготовка экрана: селектор — щелчок из страницы (так не мешают перекрытия и прокрутка),
    # («filter», id) — фильтр очереди из машины, как его выбирает оператор; («quiet», —) — убрать
    # всплывающие уведомления: на снимке экрана они закрывают то, ради чего снимок; («groups», запрос) — поиск
    # в дереве групп, текущее найденное — второе (панель групп открывается, если скрыта, как на телефоне)
    if isinstance(step, tuple):
        kind, value = step
        if kind == "quiet":
            b.eval("document.getElementById('toasts').replaceChildren()")
            return
        if kind == "groups":
            b.eval(
                "(() => { if (document.getElementById('workspace').dataset.groups !== 'on') document.getElementById('toggleGroups').click();"
                " const s = document.getElementById('groupSearch'); s.value = " + json.dumps(value) + ";"
                " s.dispatchEvent(new Event('input', { bubbles: true })); document.getElementById('groupsHitNext').click(); })()"
            )
            time.sleep(0.4)
            return
        b.eval(
            "(() => { const s = document.getElementById('eventFilter'); s.value = " + json.dumps(value) + ";"
            " s.dispatchEvent(new Event('change', { bubbles: true })); })()"
        )
        time.sleep(0.6)
        return
    b.wait_for(f"!!{find(step)}")
    click(b, step)


def click(b, selector):
    if not b.eval(f"(() => {{ const e = {find(selector)}; if (!e) return false; e.click(); return true; }})()"):
        raise RuntimeError(f"нечего нажать: {selector}")
    time.sleep(0.4)


def capture(b, path, clip=None, pad=0, below=0, size=DESKTOP):
    params = {"format": "png"}
    if clip:
        x, y, w, h = rect(b, clip)
        x0, y0 = max(0, x - pad), max(0, y - pad)
        x1, y1 = min(size[0], x + w + pad), min(size[1], y + h + pad + below)
        params["clip"] = {"x": x0, "y": y0, "width": x1 - x0, "height": y1 - y0, "scale": 1}
    data = b.call("Page.captureScreenshot", **params)["data"]
    path.write_bytes(base64.b64decode(data))


# Подготовка экранов (селекторы — те же, что в самопроверке). Чужие — на первой странице «Чужих»
FOREIGN = [("filter", "foreign")]
TICK_THREE = [f"#eventsList .event:nth-child({i}) [data-check]" for i in (1, 2, 3)]
MERGE_FIRES = [
    "#groupsList .tree-all [data-filter='select']",
    "#groupingRows [data-ms-toggle='0:eventTypeIds']",
    "#groupingRows [data-fkey='0:eventTypeIds'][value='fire']",
    "#groupingConfirm",
    "#selBar [data-sel-do='merge']",
    "[data-work-tab='linked']",
    ("quiet", None),
]

# имя, размер, телефон, подготовка (щелчки), состояние мыши (hover/press, селектор), область, отступ, ниже
SHOTS = [
    ("restyled", DESKTOP, False, [], None, None, 0, 0),
    ("state-primary-hover", DESKTOP, False, [], ("hover", "#eventsList button[data-do=claim]"), "#eventsList button[data-do=claim]", 8, 0),
    ("state-primary-pressed", DESKTOP, False, [], ("press", "#eventsList button[data-do=claim]"), "#eventsList button[data-do=claim]", 8, 0),
    ("state-warn-hover", DESKTOP, False, [], ("hover", "#eventsList button[data-do=transfer]"), "#eventsList button[data-do=transfer]", 8, 0),
    ("state-warn-pressed", DESKTOP, False, [], ("press", "#eventsList button[data-do=transfer]"), "#eventsList button[data-do=transfer]", 8, 0),
    ("state-outline-hover", DESKTOP, False, [], ("hover", "#eventsList button[data-do=close]"), "#eventsList button[data-do=close]", 8, 0),
    ("state-outline-pressed", DESKTOP, False, [], ("press", "#eventsList button[data-do=close]"), "#eventsList button[data-do=close]", 8, 0),
    ("state-toggle-rest", DESKTOP, False, [], None, "#toggleGroups", 8, 0),
    ("state-toggle-hover", DESKTOP, False, [], ("hover", "#toggleGroups"), "#toggleGroups", 8, 0),
    ("state-toggle-pressed", DESKTOP, False, [], ("press", "#toggleGroups"), "#toggleGroups", 8, 0),
    ("state-theme-hover", DESKTOP, False, [], ("hover", "#themeToggle"), "#themeToggle", 8, 0),
    ("state-card-hover", DESKTOP, False, [], ("hover", "#eventsList .event"), "#eventsList .event", 8, 0),
    ("state-card-hover-btn", DESKTOP, False, [], ("hover", "#eventsList .event .btn.primary"), "#eventsList .event", 8, 0),
    ("state-brand", DESKTOP, False, [], None, ".brand", 8, 0),
    ("state-badge-foreign", DESKTOP, False, FOREIGN, None, "#eventsList .badge.foreign", 10, 0),
    ("state-seg", DESKTOP, False, [], None, ".seg", 8, 0),
    ("state-select-open", DESKTOP, False, ["#selectMenuBtn"], None, "#panelEvents .panel-h", 0, 100),
    ("state-dialog-transfer", DESKTOP, False, ["#eventsList button[data-do=transfer]", ".target-combo .mselect-input"], None, ".modal-card", 12, 0),
    ("screen-selection", DESKTOP, False, TICK_THREE, None, "#panelEvents", 0, 0),
    ("screen-linked", DESKTOP, False, MERGE_FIRES, None, None, 0, 0),
    ("phone", PHONE, True, [], None, None, 0, 0),
    ("phone-filters", PHONE, True, ["#eventsMoreBtn"], None, None, 0, 0),
]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--chrome", default=shutil.which("google-chrome") or shutil.which("chromium") or shutil.which("chromium-browser"))
    ap.add_argument("--only", default="", help="снимать только снимки, в имени которых есть эта строка")
    args = ap.parse_args()
    if not args.chrome:
        print("Не нашёл Chrome: укажите путь --chrome")
        return 1
    b = Browser(args.chrome)
    failed = 0
    try:
        for theme in ("dark", "light"):
            for name, size, phone, prepare, pointer, clip, pad, below in SHOTS:
                file = OUT / f"{name}-{theme}.png"
                if args.only not in file.name:
                    continue
                try:
                    open_page(b, theme, size, phone)
                    for step in prepare:
                        prepare_step(b, step)
                    if pointer:
                        mouse(b, *pointer)
                    capture(b, file, clip, pad, below, size)
                    print(f"OK    {file.name}")
                except RuntimeError as e:
                    failed += 1
                    print(f"FAIL  {file.name}: {e}")
    finally:
        b.close()
    print(f"Не снято: {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
