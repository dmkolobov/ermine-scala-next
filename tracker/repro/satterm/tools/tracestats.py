#!/usr/bin/env python3
# Per-site branch statistics over a -Dermine.rowTrace TSV written by SatTermRepro sweep (one site per base).
#   tools/tracestats.py <trace.tsv> <nVars>      nVars = 3 (W2) | 5 (H2) | 6 (NE6): Supply starts at base+nVars
import sys, re, collections
path, nvars = sys.argv[1], int(sys.argv[2])
idre = re.compile(r'\^[a-z()]+(\d+)')
steps = collections.defaultdict(list); ids = collections.defaultdict(set); mintrules = collections.defaultdict(collections.Counter)
for ln in open(path):
    f = ln.rstrip('\n').split('\t')
    if f[0] == 'step': steps[f[1]].append(f[2].split(':')[0])
    if f[0] in ('step','learn'):
        rec = f[3] if f[0]=='step' else f[3]
        for m in idre.finditer(rec): ids[f[1]].add(int(m.group(1)))
    if f[0] == 'learn' and f[2] == 'new':
        rule = f[3].split(':')[0]
        base = int(f[1].split('@')[1]); lo = base + nvars
        for m in idre.finditer(f[3]):
            if int(m.group(1)) >= lo and f[3].split(' <- ')[0].split(': ')[1] == m.group(0): mintrules[f[1]][rule] += 1   # fresh id on the LHS of a new learned partition = its defining mint
kinds = collections.Counter(); seq = collections.Counter(); mints = collections.Counter(); unify_sites = 0; empty_sites = 0; nsteps = []
for site, br in steps.items():
    base = int(site.split('@')[1]); lo = base + nvars
    fresh = sorted(i for i in ids[site] if i >= lo)
    mints[len(fresh)] += 1
    c = collections.Counter(br); kinds.update(c)
    if 'unify' in c: unify_sites += 1
    if 'empty' in c: empty_sites += 1
    seq[' '.join(k+('' if c[k]==1 else 'x%d'%c[k]) for k in ['learn','empty','unify','common','concrete'] if c[k])] += 1
    nsteps.append(len(br))
n = len(steps)
print("sites=%d steps: min=%d median=%d max=%d  branch totals: %s" % (n, min(nsteps), sorted(nsteps)[n//2], max(nsteps), ' '.join('%s=%d'%kv for kv in sorted(kinds.items()))))
print("sites with a unify step: %d/%d   sites with an empty step: %d/%d" % (unify_sites, n, empty_sites, n))
print("fresh ids appearing in step/learn records (= mints that entered the queue) per site: " + ' '.join('%d:x%d'%kv for kv in sorted(mints.items())))
print("branch-kind multiset per site (kind xcount):")
for k, v in seq.most_common(): print("   x%-3d %s" % (v, k))
