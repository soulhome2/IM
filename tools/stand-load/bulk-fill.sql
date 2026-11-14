-- Нагрузочное наполнение imdb стенда: до 100 сценариев, 1 200 000 событий, 1 000 000 инцидентов (по одному на событие).
-- События — за последние 180 дней, по образцам уже принятых событий (источник, тип, raw_data).
-- Инциденты: 500 самых свежих — «new», остальные «closed» (ложная тревога), с записями журнала create и close.
-- status_guid нет (миграция 053, правка плана 86). Перед запуском — дамп в ~/Work/stand/backup/. Откат — восстановить дамп.
\set ON_ERROR_STOP on
\timing on

BEGIN;
-- 1. Сценарии: копии последних версий существующих до общего числа 100.
CREATE TEMP TABLE base_sc AS
  SELECT DISTINCT ON (s.guid) s.*, sc.customer_guid AS cust
  FROM scenarios s JOIN scenarios_customers sc ON sc.scenario_guid = s.guid
  WHERE NOT s.is_archived ORDER BY s.guid, s.version DESC;
CREATE TEMP TABLE new_sc AS
  SELECT md5(random()::text || clock_timestamp()::text)::uuid AS nguid, b.*, n
  FROM generate_series(1, 100 - (SELECT count(DISTINCT guid) FROM scenarios)) n
  JOIN LATERAL (SELECT * FROM base_sc ORDER BY guid OFFSET (n - 1) % (SELECT count(*) FROM base_sc) LIMIT 1) b ON true;
INSERT INTO scenario_definitions (guid, creator_user_id, created_at) SELECT nguid, updated_by_user_id, now() FROM new_sc;
INSERT INTO scenarios (guid, version, name, description, read_only, script, created_at, is_archived, updated_by_user_id, updated_at)
  SELECT nguid, 1, 'Нагрузка ' || lpad(n::text, 2, '0') || ': ' || name, description, false, script, now(), false, updated_by_user_id, now()
  FROM new_sc;
INSERT INTO scenarios_customers (guid, scenario_guid, customer_guid) SELECT md5(random()::text || clock_timestamp()::text)::uuid, nguid, cust FROM new_sc;
COMMIT;

-- 2. События.
CREATE TEMP TABLE tmpl AS
  SELECT row_number() OVER (ORDER BY guid) - 1 AS k, customer_guid, source_guid, source_type_guid, source_event_type_guid, raw_data
  FROM events WHERE deleted_at IS NULL;
CREATE TEMP TABLE sc_pick AS
  SELECT row_number() OVER (ORDER BY s.guid) - 1 AS k, s.guid, max(s.version) AS version
  FROM scenarios s WHERE NOT s.is_archived GROUP BY s.guid;
CREATE TEMP TABLE bulk AS
  SELECT md5(random()::text || clock_timestamp()::text)::uuid AS guid,
         now() - random() * interval '180 days' AS at,
         i <= 1000000 AS has_inc,
         (random() * 1e9)::bigint AS r
  FROM generate_series(1, 1200000) i;

INSERT INTO events (guid, created_at, raw_data, processed, customer_guid, source_guid, source_type_guid, source_event_type_guid, alarm_number, occurred_at)
  SELECT b.guid, b.at, t.raw_data, true, t.customer_guid, t.source_guid, t.source_type_guid, t.source_event_type_guid,
         1000000 + row_number() OVER (ORDER BY b.at), b.at
  FROM bulk b JOIN tmpl t ON t.k = b.r % (SELECT count(*) FROM tmpl);

-- 3. Инциденты.
CREATE TEMP TABLE inc AS
  SELECT md5(random()::text || clock_timestamp()::text)::uuid AS guid, b.guid AS event_guid, b.at, t.customer_guid, b.r,
         (SELECT last_number FROM incident_counters WHERE customer_guid = t.customer_guid)
           + row_number() OVER (PARTITION BY t.customer_guid ORDER BY b.at) AS number,
         row_number() OVER (ORDER BY b.at DESC) <= 500 AS fresh
  FROM bulk b JOIN tmpl t ON t.k = b.r % (SELECT count(*) FROM tmpl)
  WHERE b.has_inc;

INSERT INTO incidents (guid, name, customer_guid, created_at, updated_at, priority_guid, escalated, event_guid,
                       scenario_guid, scenario_version, number, version, state, owner, close_result_id, closed_by, closed_at, changed_at)
  SELECT i.guid, s.name, i.customer_guid, i.at, i.at + interval '1 minute',
         (ARRAY['01a18211-ddc3-7948-9e4c-807036f5446d','01a18211-ddb3-7948-9a98-33ca709c5022',
                '01a18211-ddcb-7948-b431-d4543b91a44e','01a18211-ddbc-7948-80b8-7be09f1427c9']::uuid[])[1 + i.r % 4],
         false, i.event_guid, p.guid, p.version, i.number,
         CASE WHEN i.fresh THEN 1 ELSE 3 END,
         CASE WHEN i.fresh THEN 'new' ELSE 'closed' END,
         CASE WHEN i.fresh THEN '' ELSE '2' END,
         CASE WHEN i.fresh THEN '' ELSE 'false_alarm' END,
         CASE WHEN i.fresh THEN '' ELSE '2' END,
         CASE WHEN i.fresh THEN NULL ELSE i.at + interval '1 minute' END,
         i.at + interval '1 minute'
  FROM inc i
  JOIN sc_pick p ON p.k = (i.r / 7) % (SELECT count(*) FROM sc_pick)
  JOIN scenarios s ON s.guid = p.guid AND s.version = p.version;

UPDATE incident_counters c SET last_number = m.n FROM (SELECT customer_guid, max(number) n FROM inc GROUP BY 1) m
  WHERE c.customer_guid = m.customer_guid;

-- 4. Журнал инцидента: создание у всех, закрытие у закрытых.
INSERT INTO incident_journal (guid, incident_guid, customer_guid, at, actor, transition, template_key, vars, kind)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, guid, customer_guid, at, 'dispatcher', 'create', 'workflow.journal.create', NULL, 'system' FROM inc;
INSERT INTO incident_journal (guid, incident_guid, customer_guid, at, actor, transition, template_key, vars, kind)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, guid, customer_guid, at + interval '1 minute', '2', 'close', 'workflow.journal.close',
         '{"comment": "нагрузка", "closeResultLabel": ["workflow.catalog.close_result.processed"], "escalationReason": ["workflow.escalation.reason"]}'::jsonb,
         'transition'
  FROM inc WHERE NOT fresh;

ANALYZE events; ANALYZE incidents; ANALYZE incident_journal; ANALYZE scenarios;
SELECT (SELECT count(DISTINCT guid) FROM scenarios) sc, (SELECT count(*) FROM events) ev, (SELECT count(*) FROM incidents) inc,
       (SELECT count(*) FROM incident_journal) jr, pg_size_pretty(pg_database_size('imdb')) size;
