# Собирает тексты запросов очереди сервера (queue_queries.go, access_queries.go) с параметрами оператора load-op (группа 2)
# и печатает SQL для EXPLAIN (ANALYZE, BUFFERS). Только чтение.
import sys
CUST="019bbe9b-b1b8-7817-ade7-d283887bb551"
RULES="""rules AS (
  SELECT ar.guid, ar.source_guid, ar.source_type_guid, ar.source_event_type_guid, ar.source_group_guid, ar.external_user_group_id
  FROM access_rules ar WHERE ar.deleted_at IS NULL AND ar.customer_guid = '%s' AND ar.external_user_group_id = ANY ('{2}')
),
closure AS (
  WITH RECURSIVE t(a, d) AS (SELECT guid, guid FROM source_groups WHERE customer_guid = '%s'
    UNION ALL SELECT t.a, g.guid FROM t JOIN source_groups g ON g.parent_guid = t.d)
  SELECT a AS ancestor_guid, d AS descendant_guid FROM t
),
rule_sources AS (
  SELECT r.guid AS rule_guid, sgm.source_guid FROM rules r JOIN closure c ON c.ancestor_guid = r.source_group_guid
  JOIN source_group_memberships sgm ON sgm.group_guid = c.descendant_guid
)""" % (CUST, CUST)
MATCH="""(ar.source_guid IS NULL OR ar.source_guid = e.source_guid)
 AND (ar.source_type_guid IS NULL OR ar.source_type_guid = e.source_type_guid)
 AND (ar.source_group_guid IS NULL OR (ar.guid, e.source_guid) IN (SELECT rs.rule_guid, rs.source_guid FROM rule_sources rs))
 AND (ar.source_event_type_guid IS NULL OR ar.source_event_type_guid = e.source_event_type_guid)
 AND (ar.source_guid IS NOT NULL OR ar.source_type_guid IS NOT NULL OR ar.source_event_type_guid IS NOT NULL OR ar.source_group_guid IS NOT NULL)"""
C4="'%s'" % CUST
def counters(cond="", joins=""):
    return f"""WITH {RULES}
SELECT e.state, e.owner, e.assignment_group, sum(e.count)::bigint AS count FROM (
 SELECT ev.source_guid, ev.source_type_guid, ev.source_event_type_guid, i.state, i.owner, i.assignment_group, count(*) AS count
 FROM incidents i JOIN events ev ON ev.guid = i.event_guid AND ev.deleted_at IS NULL {joins}
 WHERE i.deleted_at IS NULL AND i.customer_guid = {C4} AND i.state <> 'closed' {cond}
 GROUP BY 1,2,3,4,5,6
 UNION ALL
 SELECT ev.source_guid, ev.source_type_guid, ev.source_event_type_guid, i.state, i.owner, i.assignment_group, sum(i.count)
 FROM (SELECT q.*, 'closed'::text AS state FROM (
   SELECT customer_guid, owner, assignment_group, source_guid, source_type_guid, source_event_type_guid, scenario_guid, priority_guid, count FROM queue_closed_counts
   UNION ALL SELECT customer_guid, owner, assignment_group, source_guid, source_type_guid, source_event_type_guid, scenario_guid, priority_guid, delta FROM queue_closed_deltas) q) i
 CROSS JOIN LATERAL (SELECT i.source_guid, i.source_type_guid, i.source_event_type_guid) ev
 WHERE i.customer_guid = {C4} {cond}
 GROUP BY 1,2,3,4,5,6 HAVING sum(i.count) <> 0
) e WHERE EXISTS (SELECT 1 FROM rules ar WHERE {MATCH})
GROUP BY 1,2,3"""
SEARCH="""('inc-' || CASE WHEN i.number < 1000 THEN lpad(i.number::text, 4, '0') ELSE i.number::text END
 || ' inc-' || CASE WHEN coalesce(ev.alarm_number, i.number) < 1000 THEN lpad(coalesce(ev.alarm_number, i.number)::text, 4, '0') ELSE coalesce(ev.alarm_number, i.number)::text END
 || ' ' || lower(CASE WHEN t.deleted_at IS NULL THEN t.name ELSE t.uid END)) LIKE (SELECT lower('%стекл%'::text))"""
def search_counters():
    return f"""WITH {RULES}
SELECT e.state, e.owner, e.assignment_group, sum(e.count)::bigint AS count FROM (
 SELECT ev.source_guid, ev.source_type_guid, ev.source_event_type_guid, i.state, i.owner, i.assignment_group, count(*) AS count
 FROM incidents i JOIN events ev ON ev.guid = i.event_guid AND ev.deleted_at IS NULL JOIN source_event_types t ON t.guid = ev.source_event_type_guid
 WHERE i.deleted_at IS NULL AND i.customer_guid = {C4} AND i.state <> ALL ('{{closed}}'::text[]) AND ({SEARCH})
 GROUP BY 1,2,3,4,5,6) e WHERE EXISTS (SELECT 1 FROM rules ar WHERE {MATCH})
GROUP BY 1,2,3"""
def page(order, chosen_states="'new','pending_acceptance','in_progress','on_hold'"):
    return f"""WITH {RULES},
chosen AS (SELECT DISTINCT state, owner, assignment_group FROM incidents WHERE deleted_at IS NULL AND customer_guid = {C4} AND state IN ({chosen_states}))
SELECT i.guid FROM incidents i
 JOIN events ev ON ev.guid = i.event_guid AND ev.deleted_at IS NULL
 JOIN priorities p ON p.guid = i.priority_guid
 WHERE i.deleted_at IS NULL AND i.customer_guid = {C4} AND i.state = ANY ('{{new,pending_acceptance,in_progress,on_hold}}'::text[])
  AND (i.state, i.owner, i.assignment_group) IN (SELECT c.state, c.owner, c.assignment_group FROM chosen c)
  AND EXISTS (SELECT 1 FROM rules ar, (SELECT ev.source_guid, ev.source_type_guid, ev.source_event_type_guid) e WHERE {MATCH})
 ORDER BY {order}, i.number LIMIT 50 OFFSET 0"""
which=sys.argv[1]
q={"counters":counters(),"search":search_counters(),
   "page_prio_oldest":page("p.value DESC, ev.occurred_at ASC"),
   "page_reaction":page("CASE WHEN (i.timers->'reaction'->>'due')::bigint <> 0 AND (i.timers->'reaction'->>'fired')::bigint IS DISTINCT FROM (i.timers->'reaction'->>'due')::bigint THEN 0 ELSE 1 END ASC, CASE WHEN (i.timers->'reaction'->>'due')::bigint <> 0 AND (i.timers->'reaction'->>'fired')::bigint IS DISTINCT FROM (i.timers->'reaction'->>'due')::bigint THEN (i.timers->'reaction'->>'due')::bigint ELSE extract(epoch FROM ev.occurred_at) * 1000 END ASC")}[which]
print("EXPLAIN (ANALYZE, BUFFERS) " + q + ";")
