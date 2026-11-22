#!/bin/bash
# снимок pg_stat_statements по запросам про группы раз в 10 с (последний = итог прогона)
O=$1; while true; do
docker exec 375f9250b4b1 psql -U postgres imdb -Atc "select calls||'|'||round(total_time::numeric)||'|'||round((total_time/calls)::numeric,2)||'|'||left(regexp_replace(query,'\s+',' ','g'),110) from pg_stat_statements where query ilike '%source_group%' and query not ilike '%rules AS%' and calls>3 order by calls desc limit 14" > $O.tmp 2>/dev/null && [ -s $O.tmp ] && mv $O.tmp $O
sleep 10; done
