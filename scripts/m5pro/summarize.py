#!/usr/bin/env python3
"""summarize.py PREFIX...: compact tables from the abtest records $M5PRO_OUT/PREFIX*.txt (their '# summary' block).
For every record: config, median MC/s, range, ratio to c0, the other processes' CPU / GPU (median), verdict; then the
best config. `tiled`: adds best tiled over best fused. `threads`: one line per model with the rate at every count."""
import sys, os, re, glob
O = os.environ.get('M5PRO_OUT', '.')
def read(path):
    rows = []; on = False
    for l in open(path):
        if l.startswith('# summary'): on = True; continue
        m = re.match(r'^c(\d+) (\S+)\s+([\d.]+) \[([\d.]+)-([\d.]+)\]\s+x([\d.]+) \[[\d.]+-[\d.]+\]\s+others (\d+)%/(\d+)%\s+(\S+)', l)
        if on and m:
            cfg = m.group(2).replace('@multithreaded', '').replace('OPENEMS_', '')
            rows.append(dict(cfg=cfg, med=float(m.group(3)), lo=float(m.group(4)), hi=float(m.group(5)), ratio=float(m.group(6)),
                             cpu=int(m.group(7)), gpu=int(m.group(8)), verdict=m.group(9)))
    return rows
for pre in sys.argv[1:]:
    files = sorted(glob.glob(os.path.join(O, pre + '*.txt')))
    for f in files:
        r = read(f)
        if not r: continue
        name = os.path.basename(f)[:-4]
        notid = [x['cfg'] for x in r if not x['verdict'].startswith('identical') and 'tolerant' not in x['verdict'] and 'metal' not in x['cfg']]
        print('== %s   others cpu max %d %%, median %d %%%s' % (name, max(x['cpu'] for x in r), sorted(x['cpu'] for x in r)[len(r)//2],
              '   NOT IDENTICAL: ' + ', '.join(notid) if notid else ''))
        if pre.startswith('threads'):
            print('   ' + '  '.join('%s:%d' % (x['cfg'].split(':')[1], round(x['med'])) for x in r))
            b = max(r, key=lambda x: x['med']); print('   best: %s at %.0f MC/s; auto (:0) %.0f' % (b['cfg'], b['med'], r[-1]['med']))
            continue
        for x in r:
            print('   %-46s %7.0f [%5.0f-%5.0f]  x%.3f  others %3d%%/%d%%  %s' % (x['cfg'][:46], x['med'], x['lo'], x['hi'], x['ratio'], x['cpu'], x['gpu'], x['verdict'][:22]))
        if pre.startswith('tiled'):
            fused = [x for x in r if 'TBLOCK' not in x['cfg']]; tiled = [x for x in r if 'TBLOCK' in x['cfg']]
            bf = max(fused, key=lambda x: x['med']); bt = max(tiled, key=lambda x: x['med'])
            print('   best fused %s %.0f | best tiled %s %.0f | tiled/fused x%.2f' % (bf['cfg'], bf['med'], bt['cfg'], bt['med'], bt['med']/bf['med']))
