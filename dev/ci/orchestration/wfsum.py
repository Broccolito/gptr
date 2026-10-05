import json,sys
d=json.load(open(sys.argv[1]))
res=d.get('result')
if isinstance(res,str):
    try: res=json.loads(res)
    except Exception: pass
print('keys',list(d.keys()))
for l in d.get('logs',[]): print('LOG',l)
if isinstance(res,list):
    for r in res:
        print('==',r.get('task'),r.get('status'),r.get('sha'),'pushed' if r.get('pushed') else '', r.get('stage',''))
        for h in r.get('history',[]):
            print('   r%s %s serious=%s minor=%s fixed=%s'%(h.get('round'),h.get('verdict'),h.get('serious'),h.get('minor'),h.get('fixed')))
        if r.get('status')!='committed':
            print('   BLOCKER:',str(r.get('blocker'))[:3000])
            print('   FINDINGS:',json.dumps(r.get('lastFindings'))[:3000])
        if r.get('note'): print('   note:',r['note'][:400])
