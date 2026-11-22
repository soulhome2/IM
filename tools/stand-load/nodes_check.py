#!/usr/bin/env python3
"""План 99, 7б: после прогона — на каждом узле напрямую: «Состояние системы» (расхождения среза, индексы) и счётчики test@ и load-op-01.
  python3 -I nodes_check.py <порт> [<порт> …]"""
import sys, json
sys.argv = [sys.argv[0], "0", "0", "/tmp/x", "только=none"] + sys.argv[1:]
ports = [int(p) for p in sys.argv[5:]]
src = open(__file__.replace("nodes_check.py", "cross_node.py")).read().split("ADMIN = cloud_login")[0]
exec(src)
ADMIN = cloud_login("test@axxonnet.test", test_pass()); OP = cloud_login("load-op-01@axxonnet.test", "111111")
for p in ports:
    n = Node(p, str(p))
    c, st, ms, _ = n.call("GET", "/operator/admin/system-status", ADMIN)
    srv = (st or {}).get("server", {}); db = (st or {}).get("database", {})
    print(p, "status", c, "liveSliceMismatches", srv.get("liveSliceMismatches"), "workflowVersion", srv.get("workflowVersion"),
          "counters test@", counters(n, ADMIN), "load-op-01", counters(n, OP))
