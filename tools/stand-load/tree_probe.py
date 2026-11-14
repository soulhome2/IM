import sys,time,statistics
sys.argv=["x","1","1","1","probe-tree"]
sys.path.insert(0, "/home/slava/Work/stand/load")
import load_ops as L
res={}
L.log=lambda rec,f=None: res.setdefault(rec.get('op'),[]).append(rec.get('ms'))
op=L.Op(1)
op.login()
for _ in range(30):
    op.call("GET","/operator/reference/source-groups?withCounters=true",op="tree")
    op.call("GET","/operator/reference/source-groups?withCounters=false",op="tree0")
    op.call("GET","/operator/session",op="session")
for k,v in res.items():
    if k!='login': print(k, 'median', statistics.median(v), 'min', min(v))
