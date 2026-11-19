// Стенд: собранный конфигуратор и экран оператора (npm run build) вместо Vite dev, порт 5173 — nginx шлёт /im/ сюда.
// Сборка лежит в $STAND_DIR/im-dist (по умолчанию ~/Work/stand/im-dist).
// Обновить: cd $IM_CONFIGURATOR_REPO && npm run build && rsync -a --delete dist/ $STAND_DIR/im-dist/
import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path'; import os from 'node:os';
const root = path.join(process.env.STAND_DIR || path.join(os.homedir(), 'Work', 'stand'), 'im-dist');
const types = { '.js':'text/javascript', '.css':'text/css', '.html':'text/html; charset=utf-8', '.svg':'image/svg+xml', '.woff2':'font/woff2', '.woff':'font/woff', '.json':'application/json', '.png':'image/png' };
http.createServer((req, res) => {
  let p = decodeURIComponent((req.url || '/').split('?')[0]);
  if (!p.startsWith('/im/')) { res.writeHead(404); return res.end(); }
  p = p.slice(4);
  let file = path.join(root, p);
  if (!file.startsWith(root)) { res.writeHead(403); return res.end(); }
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    if (path.extname(p)) { res.writeHead(404); return res.end(); }
    file = path.join(root, p.startsWith('operator/') || p === 'operator' ? 'operator/index.html' : 'index.html');
  }
  const asset = p.startsWith('assets/');
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream',
    'Cache-Control': asset ? 'public, max-age=31536000, immutable' : 'no-cache' });
  fs.createReadStream(file).pipe(res);
}).listen(5173, '0.0.0.0', () => console.log('im-dist на 5173'));
