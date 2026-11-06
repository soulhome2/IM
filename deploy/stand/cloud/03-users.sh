#!/usr/bin/env bash
# Облако, шаг 3. Пользователь стенда TEST_EMAIL в группе cloud-admin (прямо в базе облака) и страница входа без пароля.
# Запускать после make deploy, очистки томов и новой распаковки интерфейса. Повторный запуск безопасен.
source "$(dirname "$0")/lib.sh"
check_pass_file
[ -n "$(db_container)" ] || die "ac_db не запущен — сначала 02-build-deploy.sh"

say "Пользователь $TEST_EMAIL"
if [ "$(echo "select count(*) from users where email='$TEST_EMAIL'" | psql_root)" = 0 ]; then
  python3 - "$TEST_EMAIL" "$TEST_PASS_FILE" <<'PY' | psql_root
import hashlib, secrets, sys
email = sys.argv[1]; pwd = open(sys.argv[2], encoding="utf-8").read().rstrip("\n")
salt = secrets.token_urlsafe(24)
h = hashlib.sha512((salt + pwd).encode()).hexdigest()   # как hashPasswordWithSalt облака
print(f"""BEGIN;
WITH r AS (INSERT INTO users (create_time,name,surname,password,email,salt,an_password,locale)
  VALUES (now(),'Тест','Оператор','{h}','{email}','{salt}','{secrets.token_hex(8)}','ru') RETURNING id),
n AS (INSERT INTO user_nodes(path,name,user_id) SELECT ('1.u'||id::text)::ltree,'{email}',id FROM r RETURNING user_id)
INSERT INTO users_user_groups(user_id,user_group_id) SELECT user_id,1 FROM n;
COMMIT;""")
PY
  echo "  заведён (группа cloud-admin)"
else echo "  уже есть"; fi

if [ "${DEV_LOGIN:-1}" = 1 ]; then
  say "Страница входа без пароля (только для локального стенда!)"
  python3 - "$CLOUD_KIT/dev-login.html.tpl" "$CLOUD_DIR/tools/compose/ui/dev-login.html" "$TEST_EMAIL" "$TEST_PASS_FILE" <<'PY'
import json, sys
tpl, out, email, pf = sys.argv[1:5]
pwd = open(pf, encoding="utf-8").read().rstrip("\n")
s = open(tpl, encoding="utf-8").read()
s = s.replace("'__EMAIL__'", json.dumps(email)).replace("'__PASSWORD__'", json.dumps(pwd))
open(out, "w", encoding="utf-8").write(s)
PY
  echo "  $CLOUD/dev-login.html  (?to=/путь — куда перейти после входа)"
fi

login && echo "Проверка входа: OK"
