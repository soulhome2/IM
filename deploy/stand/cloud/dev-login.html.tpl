<!doctype html>
<!-- Только для локального стенда axxonnet.test: автоматический вход тестовым пользователем.
     Кладётся в tools/compose/ui (каталог в .gitignore облака) скриптом ~/Work/stand/ensure-dev-login.sh.
     Параметр ?to=/путь — куда перейти после входа (по умолчанию /). -->
<meta charset="utf-8">
<title>Вход на стенд</title>
<body style="font:16px sans-serif;padding:2em">
<p id="msg">Вход как test@axxonnet.test…</p>
<script>
(async () => {
  const msg = document.getElementById('msg');
  const to = new URLSearchParams(location.search).get('to') || '/';
  try {
    const r = await fetch('/api/v3/ac-backend/users/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: '__EMAIL__', password: '__PASSWORD__' }),
    });
    if (!r.ok) throw new Error('HTTP ' + r.status + ' ' + (await r.text()));
    const t = await r.json();
    sessionStorage.removeItem('accessToken');
    sessionStorage.removeItem('refreshToken');
    localStorage.setItem('accessToken', t.accessToken);
    localStorage.setItem('refreshToken', t.refreshToken);
    localStorage.setItem('isSocialAuth', '0');
    location.replace(to.startsWith('/') ? to : '/');
  } catch (e) {
    msg.textContent = 'Не удалось войти: ' + e.message + '. Пользователь заведён? Запустите ~/Work/stand/ensure-dev-login.sh';
  }
})();
</script>
