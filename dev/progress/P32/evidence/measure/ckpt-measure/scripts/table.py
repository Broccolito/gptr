import json,sys,glob
keys=['mcp_serve_exec','mcp_serve_gate','mcp_serve_r','checkpoint_before','checkpoint_after','ckpt_objects_before','ckpt_objects_after','ckpt_files_before','ckpt_files_after','ckpt_state_before','ckpt_state_after','env_snapshot','ckpt_files_sync','ckpt_scan_run','ckpt_unshared_bytes','ckpt_write_image','ckpt_on_agent_end','ckpt_gc']
short=['exec','gate','r','ck_bef','ck_aft','obj_bef','obj_aft','fil_bef','fil_aft','st_bef','st_aft','envsnap','fsync','scan','unshar','wimg','agent_end','gc']
for path in sys.argv[1:]:
  print('#####', path.split('/')[-1])
  print('%-18s %7s '%('label','outer')+' '.join('%7s'%k for k in short))
  for line in open(path):
    d=json.loads(line)
    if d['label']=='__final__': print('   final disk', d['disk']); continue
    ph=d['phases']
    print('%-18s %7.3f '%(d['label'][:18], d.get('outer_s') or d.get('request_s'))+' '.join('%7.3f'%ph.get(k,{'s':0})['s'] for k in keys))
