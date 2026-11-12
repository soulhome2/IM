-- Одна часть увеличения imdb стенда в 10 раз (2026-11-10): запускать 9 раз. За раз — 970 000 событий и 770 000
-- инцидентов (по одному на событие, как в bulk-fill.sql), из них 710 свежих — «new», остальные «closed» с журналом
-- create и close. Время — за последние 85 дней: удаление по сроку (closedIncidentsDays = 90) их не тронет.
-- status_guid нет (миграция 053). Перед запуском — дамп в ~/Work/stand/backup/. Откат — восстановить дамп.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE tmpl AS
  SELECT row_number() OVER (ORDER BY guid) - 1 AS k, customer_guid, source_guid, source_type_guid, source_event_type_guid, raw_data
  FROM (SELECT * FROM events WHERE deleted_at IS NULL ORDER BY created_at LIMIT 5000) e;
CREATE TEMP TABLE sc_pick AS
  SELECT row_number() OVER (ORDER BY s.guid) - 1 AS k, s.guid, max(s.version) AS version
  FROM scenarios s WHERE NOT s.is_archived GROUP BY s.guid;
CREATE TEMP TABLE bulk AS
  SELECT md5(random()::text || clock_timestamp()::text)::uuid AS guid,
         now() - random() * interval '85 days' AS at,
         i <= 770000 AS has_inc,
         (random() * 1e9)::bigint AS r
  FROM generate_series(1, 970000) i;
INSERT INTO events (guid, created_at, raw_data, processed, customer_guid, source_guid, source_type_guid, source_event_type_guid, alarm_number, occurred_at)
  SELECT b.guid, b.at, t.raw_data, true, t.customer_guid, t.source_guid, t.source_type_guid, t.source_event_type_guid,
         (SELECT coalesce(max(alarm_number), 0) FROM events) + row_number() OVER (ORDER BY b.at), b.at
  FROM bulk b JOIN tmpl t ON t.k = b.r % (SELECT count(*) FROM tmpl);
CREATE TEMP TABLE inc AS
  SELECT md5(random()::text || clock_timestamp()::text)::uuid AS guid, b.guid AS event_guid, b.at, t.customer_guid, b.r,
         (SELECT last_number FROM incident_counters WHERE customer_guid = t.customer_guid)
           + row_number() OVER (PARTITION BY t.customer_guid ORDER BY b.at) AS number,
         row_number() OVER (ORDER BY b.at DESC) <= 710 AS fresh
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
INSERT INTO incident_journal (guid, incident_guid, customer_guid, at, actor, transition, template_key, vars, kind)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, guid, customer_guid, at, 'dispatcher', 'create', 'workflow.journal.create', NULL, 'system' FROM inc;
INSERT INTO incident_journal (guid, incident_guid, customer_guid, at, actor, transition, template_key, vars, kind)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, guid, customer_guid, at + interval '1 minute', '2', 'close', 'workflow.journal.close',
         '{"comment": "нагрузка", "closeResultLabel": ["workflow.catalog.close_result.processed"], "escalationReason": ["workflow.escalation.reason"]}'::jsonb,
         'transition'
  FROM inc WHERE NOT fresh;
COMMIT;
