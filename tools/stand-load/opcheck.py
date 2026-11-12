#!/usr/bin/env python3
"""Проверка load-op-NN: вход, agent-state ready, права сессии, сколько инцидентов видно в очереди. python3 -I opcheck.py [с] [по]"""
import json, os, ssl, sys, urllib.request, urllib.error
CLOUD="https://axxonnet.test"; API=CLOUD+"/api/v1/im-backend"
CTX=ssl.create_default_context(cafile=os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")); CTX.verify_flags&=~ssl.VERIFY_X509_STRICT
def call(m,url,b=None,t=None):
    r=urllib.request.Request(url,data=json.dumps(b).encode() if b is not None else None,method=m); r.add_header("Content-Type","application/json")
    if t: r.add_header("Authorization","Bearer "+t)
    try:
        with urllib.request.urlopen(r,context=CTX,timeout=30) as x: raw=x.read(); return x.status,(json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e: return e.code,e.read()[:200]
a=int(sys.argv[1]) if len(sys.argv)>1 else 1; b=int(sys.argv[2]) if len(sys.argv)>2 else a
bad=0
for i in range(a,b+1):
    em="load-op-%02d@axxonnet.test"%i
    c,j=call("POST",CLOUD+"/api/v3/ac-backend/users/login",{"email":em,"password":"111111"})
    if c!=200: print(em,"вход",c,j); bad+=1; continue
    t=j["accessToken"]
    c1,_=call("PUT",API+"/operator/session/agent-state",{"agentState":"ready"},t)
    c2,s=call("GET",API+"/operator/session",t=t)
    c3,q=call("GET",API+"/operator/incidents?filter=open&pageSize=5",t=t)
    st=(s or {}).get("agentState") if c2==200 else None
    tot=(q or {}).get("total") if c3==200 and isinstance(q,dict) else q
    ok=c1==200 and st=="ready" and c3==200
    bad+= not ok
    print(em,"ready" if st=="ready" else ("agent-state %s/%s"%(c1,st)),"perms",len((s or {}).get("permissions",[])) if c2==200 else c2,"очередь",c3,"total",tot, "" if ok else "ПЛОХО")
print("плохих:",bad)
