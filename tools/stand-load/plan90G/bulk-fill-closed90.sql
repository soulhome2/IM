-- План 90, часть Г: наполнение imdb стенда до ~1 млн ЗАКРЫТЫХ инцидентов за последние 89 дней для замера блока
-- «За период». Отличия от bulk-fill.sql:
--   * все новые инциденты закрыты, время — равномерно за последние 89 дней (срок хранения поста 90 дней,
--     удаление по сроку их не тронет), событий ровно по одному на инцидент;
--   * правдоподобные accepted_at / accepted_by / accepted_group / last_assigned_group / no_reaction, результаты и причины
--     закрытия, операторы (closed_by — 1, 2, 4…43: test@, второй, load-op-001…040), нарушения норм, окна работ;
--   * открытые инциденты, накопленные прошлыми прогонами (~148 тыс.), закрываются тем же порядком: иначе очередь при
--     100 операторах несравнима со ступенью 100 плана 86 (там база начиналась с ~500 инцидентов).
-- * устройства — только те, что видит test@ по правилам доступа (49 из 198 на стенде).
-- Перед запуском — дамп в ~/Work/stand/backup/. Откат — восстановить дамп. Сервер и эмулятор агента остановить.
--   psql -v n=850000 < bulk-fill-closed90.sql
\set ON_ERROR_STOP on
\timing on

BEGIN;
-- Устройства, которые видит группа пользователей 1 (test@, «Администраторы»): правила доступа по группам устройств с
-- вложенными. Иначе старший видит меньше половины наполнения (на стенде много устройств вне правил).
CREATE TEMP TABLE vis AS
  WITH RECURSIVE d(g) AS (SELECT source_group_guid FROM access_rules WHERE deleted_at IS NULL AND external_user_group_id = 1
                            AND source_group_guid IS NOT NULL
                          UNION SELECT sg.guid FROM source_groups sg JOIN d ON sg.parent_guid = d.g)
  SELECT DISTINCT m.source_guid FROM source_group_memberships m JOIN d ON m.group_guid = d.g;
CREATE TEMP TABLE tmpl AS
  SELECT row_number() OVER (ORDER BY guid) - 1 AS k, customer_guid, source_guid, source_type_guid, source_event_type_guid, raw_data
  FROM (SELECT DISTINCT ON (source_guid, source_event_type_guid) * FROM events WHERE deleted_at IS NULL
          AND source_guid IN (SELECT source_guid FROM vis)
        ORDER BY source_guid, source_event_type_guid, created_at DESC) e;
CREATE TEMP TABLE sc_pick AS
  SELECT row_number() OVER (ORDER BY s.guid) - 1 AS k, s.guid, max(s.version) AS version
  FROM scenarios s WHERE NOT s.is_archived GROUP BY s.guid;

-- Случайные величины одного инцидента. at — появление, не позже 3 ч назад (закрытие — до «сейчас»).
CREATE TEMP TABLE bulk AS
  SELECT md5(random()::text || clock_timestamp()::text)::uuid AS guid,
         now() - interval '3 hours' - random() * (interval '89 days' - interval '3 hours') AS at,
         (random() * 1e9)::bigint AS r, random() AS u_acc, random() AS u_react, random() AS u_res, random() AS u_grp,
         random() AS u_br, random() AS u_mw, random() AS u_cause
  FROM generate_series(1, :n) i;

INSERT INTO events (guid, created_at, raw_data, processed, customer_guid, source_guid, source_type_guid, source_event_type_guid, alarm_number, occurred_at)
  SELECT b.guid, b.at, t.raw_data, true, t.customer_guid, t.source_guid, t.source_type_guid, t.source_event_type_guid,
         (SELECT coalesce(max(alarm_number), 0) FROM events) + row_number() OVER (ORDER BY b.at), b.at
  FROM bulk b JOIN tmpl t ON t.k = b.r % (SELECT count(*) FROM tmpl);

-- Итог закрытия: обработан 40 %, ложная 30 %, массовый 15 %, дубль 7 %, учения 4 %, невозможно 4 %.
CREATE TEMP TABLE inc AS
  SELECT md5(random()::text || clock_timestamp()::text)::uuid AS guid, b.guid AS event_guid, b.at, t.customer_guid, b.r,
         (SELECT last_number FROM incident_counters WHERE customer_guid = t.customer_guid)
           + row_number() OVER (PARTITION BY t.customer_guid ORDER BY b.at) AS number,
         b.u_acc < 0.8 AS accepted,
         b.at + (5 + 595 * b.u_react ^ 3) * interval '1 second' AS acc_at,
         (60 + 7140 * b.u_res ^ 3) * interval '1 second' AS work,
         CASE WHEN b.u_grp < 0.80 THEN 'grp-01a1aae6-cbe6-74a4-8693-8456bb7e91e1'
              WHEN b.u_grp < 0.95 THEN 'grp-01a1bb5c-0a91-7f9b-b0a8-196a6cc43137' ELSE '' END AS grp,
         CASE WHEN b.r % 42 = 0 THEN '1' WHEN b.r % 42 = 1 THEN '2' ELSE (b.r % 42 + 2)::text END AS who,
         CASE WHEN (b.r / 42) % 100 < 40 THEN 'processed' WHEN (b.r / 42) % 100 < 70 THEN 'false_alarm'
              WHEN (b.r / 42) % 100 < 85 THEN 'mass' WHEN (b.r / 42) % 100 < 92 THEN 'duplicate'
              WHEN (b.r / 42) % 100 < 96 THEN 'drill' ELSE 'impossible' END AS result,
         b.u_cause, b.u_br, b.u_mw
  FROM bulk b JOIN tmpl t ON t.k = b.r % (SELECT count(*) FROM tmpl);

INSERT INTO incidents (guid, name, customer_guid, created_at, updated_at, priority_guid, escalated, event_guid, event_occurred_at,
                       scenario_guid, scenario_version, number, version, state, owner, close_result_id, close_cause_id,
                       close_cause_label, closed_by, closed_at, changed_at, accepted_at, accepted_by, no_reaction,
                       accepted_group, last_assigned_group, sla_breached, breaches, maintenance_window_id)
  SELECT i.guid, s.name, i.customer_guid, i.at, c.closed_at,
         (ARRAY['01a18211-ddc3-7948-9e4c-807036f5446d','01a18211-ddb3-7948-9a98-33ca709c5022',
                '01a18211-ddcb-7948-b431-d4543b91a44e','01a18211-ddbc-7948-80b8-7be09f1427c9']::uuid[])[1 + i.r % 4],
         false, i.event_guid, i.at, p.guid, p.version, i.number, 4, 'closed', i.who, i.result,
         x.cause, x.label, i.who, c.closed_at, c.closed_at,
         CASE WHEN i.accepted THEN i.acc_at END, CASE WHEN i.accepted THEN i.who END, NOT i.accepted,
         i.grp, i.grp,
         i.u_br < 0.25,
         CASE WHEN i.u_br < 0.20 THEN jsonb_build_array(jsonb_build_object('at', (extract(epoch FROM i.at) * 1000)::bigint + 300000, 'kind', 'reaction', 'owner', ''))
              WHEN i.u_br < 0.24 THEN jsonb_build_array(jsonb_build_object('at', (extract(epoch FROM i.at) * 1000)::bigint + 300000, 'kind', 'reaction', 'owner', ''),
                                                        jsonb_build_object('at', (extract(epoch FROM i.at) * 1000)::bigint + 3600000, 'kind', 'resolution', 'owner', i.who))
              WHEN i.u_br < 0.25 THEN jsonb_build_array(jsonb_build_object('at', (extract(epoch FROM i.at) * 1000)::bigint + 1800000, 'kind', 'hold', 'owner', i.who))
              ELSE '[]'::jsonb END,
         CASE WHEN i.u_mw < 0.02 THEN '01a1dd2a-4bdd-7b09-b596-9acfec3e0489' ELSE '' END
  FROM inc i
  CROSS JOIN LATERAL (SELECT least(now() - interval '1 minute', coalesce(CASE WHEN i.accepted THEN i.acc_at END, i.at) + i.work) AS closed_at) c
  CROSS JOIN LATERAL (SELECT
         CASE WHEN i.result = 'false_alarm' THEN (ARRAY['animal','equipment','other','weather'])[1 + floor(i.u_cause * 4)::int]
              WHEN i.result = 'mass' THEN (ARRAY['known','mass_fault','power'])[1 + floor(i.u_cause * 3)::int] ELSE '' END AS cause,
         CASE WHEN i.result = 'false_alarm' THEN (ARRAY['Животные, насекомые','Неисправность устройства','Другое (нужен комментарий)','Погода, природные явления'])[1 + floor(i.u_cause * 4)::int]
              WHEN i.result = 'mass' THEN (ARRAY['Известная неисправность, работы ведутся','Массовый сбой оборудования','Отключение электричества на площадке'])[1 + floor(i.u_cause * 3)::int]
              ELSE '' END AS label) x
  JOIN sc_pick p ON p.k = (i.r / 7) % (SELECT count(*) FROM sc_pick)
  JOIN scenarios s ON s.guid = p.guid AND s.version = p.version;

UPDATE incident_counters c SET last_number = m.n FROM (SELECT customer_guid, max(number) n FROM inc GROUP BY 1) m
  WHERE c.customer_guid = m.customer_guid;

INSERT INTO incident_journal (guid, incident_guid, customer_guid, at, actor, transition, template_key, vars, kind)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, guid, customer_guid, at, 'dispatcher', 'create', 'workflow.journal.create', NULL, 'system' FROM inc;
INSERT INTO incident_journal (guid, incident_guid, customer_guid, at, actor, transition, template_key, vars, kind)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, guid, customer_guid, acc_at, who, 'claim', 'workflow.journal.claim', '{"comment": ""}'::jsonb, 'transition'
  FROM inc WHERE accepted;
INSERT INTO incident_journal (guid, incident_guid, customer_guid, at, actor, transition, template_key, vars, kind)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, i.guid, i.customer_guid, x.closed_at, x.closed_by, 'close', 'workflow.journal.close',
         '{"comment": "нагрузка"}'::jsonb, 'transition'
  FROM inc i JOIN incidents x ON x.guid = i.guid;
COMMIT;

-- Открытые от прошлых прогонов — закрыть тем же порядком (время закрытия — после появления, не позже «сейчас»).
BEGIN;
CREATE TEMP TABLE op AS
  SELECT guid, customer_guid, created_at, (random() * 1e9)::bigint AS r, random() AS u_acc, random() AS u_react,
         random() AS u_res, random() AS u_grp, random() AS u_cause, accepted_at AS was_acc, accepted_by AS was_by,
         accepted_group AS was_grp
  FROM incidents WHERE state <> 'closed' AND deleted_at IS NULL;
CREATE TEMP TABLE op2 AS
  SELECT o.*, c.acc, c.who, c.result, least(now() - interval '1 minute', coalesce(c.acc, o.created_at) + (60 + 7140 * o.u_res ^ 3) * interval '1 second') AS closed_at
  FROM op o CROSS JOIN LATERAL (SELECT
         coalesce(o.was_acc, CASE WHEN o.u_acc < 0.8 THEN least(now() - interval '2 minutes', o.created_at + (5 + 595 * o.u_react ^ 3) * interval '1 second') END) AS acc,
         CASE WHEN o.r % 42 = 0 THEN '1' WHEN o.r % 42 = 1 THEN '2' ELSE (o.r % 42 + 2)::text END AS who,
         CASE WHEN (o.r / 42) % 100 < 40 THEN 'processed' WHEN (o.r / 42) % 100 < 70 THEN 'false_alarm'
              WHEN (o.r / 42) % 100 < 85 THEN 'mass' WHEN (o.r / 42) % 100 < 92 THEN 'duplicate'
              WHEN (o.r / 42) % 100 < 96 THEN 'drill' ELSE 'impossible' END AS result) c;
UPDATE incidents i SET state = 'closed', owner = o.who, close_result_id = o.result,
       close_cause_id = CASE WHEN o.result = 'false_alarm' THEN (ARRAY['animal','equipment','other','weather'])[1 + floor(o.u_cause * 4)::int]
                             WHEN o.result = 'mass' THEN (ARRAY['known','mass_fault','power'])[1 + floor(o.u_cause * 3)::int] ELSE '' END,
       close_cause_label = CASE WHEN o.result = 'false_alarm' THEN (ARRAY['Животные, насекомые','Неисправность устройства','Другое (нужен комментарий)','Погода, природные явления'])[1 + floor(o.u_cause * 4)::int]
                                WHEN o.result = 'mass' THEN (ARRAY['Известная неисправность, работы ведутся','Массовый сбой оборудования','Отключение электричества на площадке'])[1 + floor(o.u_cause * 3)::int]
                                ELSE '' END,
       closed_by = o.who, closed_at = o.closed_at, changed_at = o.closed_at, updated_at = o.closed_at, version = i.version + 1,
       accepted_at = o.acc, accepted_by = CASE WHEN o.acc IS NULL THEN NULL ELSE coalesce(o.was_by, o.who) END, no_reaction = o.acc IS NULL,
       accepted_group = coalesce(nullif(o.was_grp, ''), CASE WHEN o.u_grp < 0.80 THEN 'grp-01a1aae6-cbe6-74a4-8693-8456bb7e91e1'
                                                              WHEN o.u_grp < 0.95 THEN 'grp-01a1bb5c-0a91-7f9b-b0a8-196a6cc43137' ELSE '' END),
       last_assigned_group = coalesce(nullif(i.last_assigned_group, ''), nullif(o.was_grp, ''), CASE WHEN o.u_grp < 0.80 THEN 'grp-01a1aae6-cbe6-74a4-8693-8456bb7e91e1'
                                                              WHEN o.u_grp < 0.95 THEN 'grp-01a1bb5c-0a91-7f9b-b0a8-196a6cc43137' ELSE '' END),
       timers = '{}'::jsonb
  FROM op2 o WHERE i.guid = o.guid;
INSERT INTO incident_journal (guid, incident_guid, customer_guid, at, actor, transition, template_key, vars, kind)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, guid, customer_guid, closed_at, who, 'close', 'workflow.journal.close',
         '{"comment": "нагрузка"}'::jsonb, 'transition'
  FROM op2;
COMMIT;

ANALYZE events; ANALYZE incidents; ANALYZE incident_journal;
SELECT (SELECT count(*) FROM events) ev, (SELECT count(*) FROM incidents) inc,
       (SELECT count(*) FILTER (WHERE state = 'closed') FROM incidents) closed,
       (SELECT count(*) FILTER (WHERE state <> 'closed') FROM incidents) live,
       (SELECT count(*) FROM incident_journal) jr, pg_size_pretty(pg_database_size('imdb')) size;
