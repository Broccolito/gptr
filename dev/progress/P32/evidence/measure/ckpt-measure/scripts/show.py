import json,sys
for path in sys.argv[1:]:
  print('#####', path.split('/')[-1])
  for line in open(path):
    d=json.loads(line)
    lab=d.get('label')
    if lab=='__final__': print('FINAL disk',d['disk'],'rss',d['max_rss_gb'],'setting',d['checkpoint_setting']); continue
    print('==',d.get('request'),lab,'outer',d.get('outer_s'),'req',d.get('request_s'),'err',d.get('error'),'rss',round(d.get('rss_gb',0),2))
    if lab!='__request__':
      da=d.get('disk_after',{}); db=d.get('disk_before',{})
      print('   disk delta:', {k:(da[k][0]-db[k][0], da[k][1]-db[k][1]) for k in da})
    ph=d.get('phases',{})
    for k,v in sorted(ph.items(), key=lambda kv:-kv[1]['s']):
      if v['s']>=0.01 or ('@' not in k and v['s']>=0.005): print('   %-50s %8.3f n=%d'%(k,v['s'],v['n']))
