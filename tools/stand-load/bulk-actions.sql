-- Дозаливка журнала действий операторов к нагрузочным инцидентам (bulk-fill.sql): у каждого закрытого —
-- «взял в работу» (через 20 с после создания) и «закрыл» (через минуту), операторы 1 и 2 поровну.
\set ON_ERROR_STOP on
\timing on
CREATE TEMP TABLE src AS
  SELECT i.guid, i.customer_guid, i.number, i.created_at, (i.number % 2 + 1)::text AS person
  FROM incident_journal j JOIN incidents i ON i.guid = j.incident_guid
  WHERE j.transition = 'close' AND j.vars->>'comment' = 'нагрузка';
INSERT INTO operator_actions (guid, customer_guid, person_id, at, kind, incident_guid, transition, key, vars, actor_kind, incident_number)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, customer_guid, person, created_at + interval '20 seconds',
         'transition', guid, 'claim', 'workflow.journal.claim',
         '{"comment": "", "previousOwnerName": ["workflow.label.unassigned"]}'::jsonb, 'person', number
  FROM src;
INSERT INTO operator_actions (guid, customer_guid, person_id, at, kind, incident_guid, transition, key, vars, actor_kind, incident_number)
  SELECT md5(random()::text || clock_timestamp()::text)::uuid, customer_guid, person, created_at + interval '1 minute',
         'transition', guid, 'close', 'workflow.journal.close',
         '{"comment": "нагрузка", "closeResultLabel": ["workflow.catalog.close_result.processed"]}'::jsonb, 'person', number
  FROM src;
UPDATE incidents i SET owner = s.person, closed_by = s.person FROM src s WHERE i.guid = s.guid AND i.owner <> s.person;
ANALYZE operator_actions;
SELECT count(*) AS actions, pg_size_pretty(pg_database_size('imdb')) AS size FROM operator_actions;
