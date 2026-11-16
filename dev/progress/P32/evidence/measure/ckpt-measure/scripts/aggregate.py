#!/usr/bin/env python3
# Medians over repetitions: per (scenario, params without ckpt/rep, label) the outer time and the
# checkpoint phases with checkpointing on, and the outer time with it off. Writes a CSV and prints.
import json, sys, glob, statistics as stt, csv, os

KEYS = ['mcp_serve_exec', 'mcp_serve_gate', 'mcp_serve_r', 'checkpoint_before', 'checkpoint_after',
        'ckpt_objects_before', 'ckpt_objects_after', 'ckpt_files_before', 'ckpt_files_after',
        'ckpt_state_before', 'ckpt_state_after', 'env_snapshot', 'env_snap_size@env_snapshot',
        'ckpt_files_sync', 'ckpt_scan_run', 'ckpt_files_step', 'ckpt_unshared_bytes',
        'ckpt_write_image', 'ckpt_capture_disk', 'ckpt_capture', 'ckpt_preimage_modes',
        'ckpt_settle', 'run_append_custom', 'ckpt_on_agent_end', 'ckpt_objects_budget',
        'ckpt_spill', 'ckpt_gc', 'env_snap_size@-', 'env_snap_size@mcp_serve_exec',
        'env_snap_size@mcp_serve_gate']
rows = {}
for path in sys.argv[2:]:
    for line in open(path):
        d = json.loads(line)
        if d['label'] == '__final__':
            continue
        kv = dict(d['kv'])
        if kv.get('prof') == '1' or kv.get('trace') == '0':
            continue
        ck = kv.pop('ckpt')
        for k in ('rep', 'trace', 'prof'):
            kv.pop(k, None)
        key = (d['scenario'], json.dumps(kv, sort_keys=True), d.get('request'), d['label'])
        r = rows.setdefault(key, {'on': [], 'off': []})
        t = d.get('outer_s') if d.get('outer_s') is not None else d.get('request_s')
        phd = d['phases'] if isinstance(d['phases'], dict) else {}
        ph = {k: phd.get(k, {'s': 0})['s'] for k in KEYS}
        disk = None
        if 'disk_before' in d:
            disk = {k: d['disk_after'][k][1] - d['disk_before'][k][1] for k in d['disk_after']}
        r.setdefault(ck, []).append({'t': t, 'ph': ph, 'disk': disk, 'rss': d.get('rss_gb')})
out = []
for key in sorted(rows, key=lambda k: (k[0], k[1], k[2] or 0)):
    r = rows[key]
    on, off = r.get('on', []), r.get('off', [])
    rec = {'scenario': key[0], 'params': key[1], 'request': key[2], 'label': key[3],
           'n_on': len(on), 'n_off': len(off),
           'outer_on_med': stt.median([x['t'] for x in on]) if on else None,
           'outer_on_all': ';'.join('%.3f' % x['t'] for x in on),
           'outer_off_med': stt.median([x['t'] for x in off]) if off else None,
           'outer_off_all': ';'.join('%.3f' % x['t'] for x in off)}
    for k in KEYS:
        rec[k] = stt.median([x['ph'][k] for x in on]) if on else None
    if on and on[0]['disk'] is not None:
        for dk in on[0]['disk']:
            rec['disk_' + dk] = stt.median([x['disk'][dk] for x in on])
    rec['rss_on_max'] = max([x['rss'] or 0 for x in on]) if on else None
    rec['rss_off_max'] = max([x['rss'] or 0 for x in off]) if off else None
    out.append(rec)
fields = []
for rec in out:
    for k in rec:
        if k not in fields:
            fields.append(k)
with open(sys.argv[1], 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for rec in out:
        w.writerow(rec)
show = ['outer_on_med', 'outer_off_med', 'checkpoint_before', 'checkpoint_after', 'ckpt_objects_before',
        'ckpt_objects_after', 'ckpt_files_before', 'ckpt_files_after', 'env_snapshot', 'ckpt_scan_run',
        'ckpt_unshared_bytes', 'ckpt_write_image', 'ckpt_on_agent_end', 'mcp_serve_r']
short = ['on', 'off', 'ck_bef', 'ck_aft', 'obj_b', 'obj_a', 'fil_b', 'fil_a', 'snap', 'scan', 'unsh',
         'wimg', 'a_end', 'r']
last = None
for rec in out:
    p = (rec['scenario'], rec['params'])
    if p != last:
        print('\n##', rec['scenario'], rec['params'], 'n_on=%d n_off=%d' % (rec['n_on'], rec['n_off']))
        print('%-3s %-18s ' % ('rq', 'label') + ' '.join('%7s' % s for s in short))
        last = p
    print('%-3s %-18s ' % (rec['request'], rec['label'][:18]) +
          ' '.join('%7.3f' % rec[k] if rec[k] is not None else '%7s' % '-' for k in show))
