#!/usr/bin/env python3
"""table.py <tag>... : one row per run from runs/RUNS.tsv + runs/<tag>.tsv (module file name from runs/<tag>.file)"""
import sys, os, subprocess, json, collections
S = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, S)
from analyze import analyse
BOOT_SOLVE = 54199
runs = {}
for line in open(S + '/runs/RUNS.tsv'):
    p = line.rstrip('\n').split('\t')
    runs[p[0]] = p
def unattributed(trace, mod):
    n = 0; k = 0
    for line in open(trace, encoding='utf-8', errors='replace'):
        if not line.startswith('solve\t'): continue
        k += 1
        p = line.rstrip('\n').split('\t')
        if k > BOOT_SOLVE and mod not in p[2] and int(p[4]) > 0: n += 1
    return n, k - BOOT_SOLVE
hdr = ['tag','wall','wall-boot','mod_s','verdict','solves','w/parts','nParts','nSat','nDerived','Res(surv)','Split(surv)','Res learn-new','Split learn-new','MINT Res','MINT Split','MINT other','sat ids','sat new ids','steps','maxSolve nSat','maxSolve mints','unattr']
print('\t'.join(hdr))
for tag in sys.argv[1:]:
    if tag not in runs: print(tag, 'NOT RUN'); continue
    p = runs[tag]
    wall = float(p[1]); verdict = p[3]; boot = p[4].split('=')[1]; mods = p[5].split('=')[1]
    modfile = open(S + '/runs/' + tag + '.file').read().strip() if os.path.exists(S + '/runs/' + tag + '.file') else tag + '.e'
    r = analyse(S + '/runs/' + tag + '.tsv', modfile)
    t = r['totals']; br = r['byRule']; ln = r['learn_new']; m = r['mints']
    ua, post = unattributed(S + '/runs/' + tag + '.tsv', modfile)
    wb = ('%.2f' % (wall - float(boot))) if boot not in ('?','') else '?'
    row = [tag, '%.1f' % wall, wb, mods, verdict, t.get('solves',0), t.get('solves_with_parts',0), t.get('nParts',0), t.get('nSat',0), t.get('nDerived',0),
           br.get('Resolution',0), br.get('SplitConcrete',0), ln.get('Resolution',0), ln.get('SplitConcrete',0),
           m.get('Resolution',0), m.get('SplitConcrete',0), sum(v for k,v in m.items() if k not in ('Resolution','SplitConcrete')),
           r['sat_ids'], r['sat_new_ids'], t.get('steps',0), r['max_nSat'][0], r['max_mints'][0], '%d/%d' % (ua, post)]
    if 'tail_partial_segment' in r: row.append('TAIL:' + json.dumps(r['tail_partial_segment']))
    print('\t'.join(str(x) for x in row))
