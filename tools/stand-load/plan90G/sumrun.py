import json,sys,statistics
def pct(a,p):
    a=sorted(a); 
    if not a: return None
    k=(len(a)-1)*p; f=int(k); c=min(f+1,len(a)-1); return round(a[f]+(a[c]-a[f])*(k-f))
for d in sys.argv[1:]:
    s=json.load(open(f'{d}-p0/summary.json'))
    print(d, 'req',s['requests'],'5xx/net',s['errors_5xx_net'],'4xx unexp',s['err_4xx_unexpected'],'trans',s.get('transitions_ok'))
    ops=s['ops']; allp=[]
    for k in sorted(ops):
        o=ops[k]
        if k.startswith(('queue','tree','card','counters','heartbeat')) or k in ('claim','close','take','action'):
            pass
        print('  %-18s n=%-6s p50=%-7s p95=%-7s p99=%-7s codes=%s'%(k,o['n'],o['p50'],o['p95'],o.get('p99'),o['codes']))
    r=[json.loads(l) for l in open(f'{d}/res.jsonl')]
    print('  srv_cpu med',statistics.median(x['srv_cpu'] for x in r),'db_cpu med',statistics.median(float(x['db_cpu'].rstrip('%')) for x in r),'rss max',max(x['srv_rss_mb'] for x in r),'live end',r[-1]['live'],'load1 med',statistics.median(x['load1'] for x in r))
    n=[json.loads(l) for l in open(f'{d}/now.jsonl')]
    print('  now n',len(n),'p50',pct([x['ms'] for x in n],.5),'p95',pct([x['ms'] for x in n],.95),'max',max(x['ms'] for x in n),'codes',{c:sum(1 for x in n if x['code']==c) for c in set(x['code'] for x in n)})
    import glob
    for f in sorted(glob.glob(f'{d}/sup*.jsonl')):
        u=[json.loads(l) for l in open(f)]
        print('  ',f.split('/')[-1],'n',len(u),'p50',pct([x['ms'] for x in u],.5),'p95',pct([x['ms'] for x in u],.95),'max',max(x['ms'] for x in u),'codes',{str(c):sum(1 for x in u if x['code']==c) for c in set(x['code'] for x in u)})
