// План 99, задача 7: tests/api.html с периодической записью журнала (если страница не завершилась — видно, где встала).
//   node apitest-progress.mjs <api> <page> <файл журнала> <минут>
import puppeteer from 'puppeteer-core';
import { writeFileSync } from 'node:fs';
const [api, page0, out, minutes] = process.argv.slice(2);
const browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome', headless: true,
  userDataDir: process.env.CHROME_PROFILE || '/tmp/claude-1000/api-progress', args: ['--no-first-run', '--disable-gpu'], protocolTimeout: 60 * 60 * 1000 });
const page = await browser.newPage();
const url = new URL(page0); url.searchParams.set('api', api);
await page.goto(url.href, { waitUntil: 'load' });
const t0 = Date.now(); let last = '';
while (Date.now() - t0 < Number(minutes) * 60000) {
  const st = await page.evaluate(() => ({ done: document.documentElement.dataset.apitest || '', log: (document.getElementById('apitest-log') || {}).textContent || '', sum: (document.getElementById('apitest-summary') || {}).textContent || '' }));
  if (st.log !== last) { writeFileSync(out, `# ${new Date().toISOString()} ${st.sum}\n` + st.log); last = st.log; }
  if (st.done) { console.log('готово: ' + st.done + ' ' + st.sum); break; }
  await new Promise((r) => setTimeout(r, 15000));
}
console.log('итог: ' + (last.split('\n').length) + ' строк журнала; ' + Math.round((Date.now() - t0) / 1000) + ' с');
await browser.close();
