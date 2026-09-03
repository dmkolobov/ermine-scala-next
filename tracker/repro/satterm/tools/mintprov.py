#!/usr/bin/env python3
# Attribute every fresh id in a -Dermine.rowTrace TSV to the rule that defined it (SplitConcrete LHS / Resolution RHS).
#   tools/mintprov.py <trace.tsv> <nVars>
import sys, re, collections
path, nvars = sys.argv[1], int(sys.argv[2])
idre = re.compile(r'\^[a-z()]+(\d+)')
defs = collections.defaultdict(dict)   # site -> fresh id -> defining rule
for ln in open(path):
    f = ln.rstrip('\n').split('\t')
    if f[0] != 'learn': continue
    site = f[1]; base = int(site.split('@')[1]); lo = base + nvars
    rec = f[3]; rule = rec.split(':')[0] if ': ' in rec else 'INPUT'
    lhs = rec.split(' <- ')[0].split(': ')[-1]
    m = idre.match(lhs)
    if rule == 'SplitConcrete' and m and int(m.group(1)) >= lo:      # u <- (group): the split mint's definition
        defs[site].setdefault(int(m.group(1)), 'SplitConcrete')
    if rule == 'Resolution':                                          # v <- (z, K): the resolvent z is fresh
        for mm in idre.finditer(rec.split(' <- ')[1]):
            if int(mm.group(1)) >= lo: defs[site].setdefault(int(mm.group(1)), 'Resolution')
# every fresh id mentioned anywhere must be one of those
allfresh = collections.defaultdict(set)
for ln in open(path):
    f = ln.rstrip('\n').split('\t')
    if f[0] not in ('step','learn'): continue
    site = f[1]; base = int(site.split('@')[1]); lo = base + nvars
    for m in idre.finditer(f[3]):
        if int(m.group(1)) >= lo: allfresh[site].add(int(m.group(1)))
unattributed = sum(len(allfresh[s] - set(defs[s])) for s in allfresh)
hist = collections.Counter(); tot = collections.Counter(); splits = []
for site in allfresh:
    c = collections.Counter(defs[site].values()); tot.update(c); splits.append(c['SplitConcrete'])
    hist['split=%d res=%d' % (c['SplitConcrete'], c['Resolution'])] += 1
splits.sort()
print("sites=%d  minted ids: %s  unattributed=%d  split mints per site: min=%d median=%d max=%d" % (len(allfresh), dict(tot), unattributed, splits[0], splits[len(splits)//2], splits[-1]))
for k, v in sorted(hist.items(), key=lambda kv: -kv[1]): print("   x%-3d %s" % (v, k))
