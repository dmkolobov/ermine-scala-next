#!/usr/bin/env python3
"""Summarise a Scala 3 sbt compile log: one line per error, grouped by file."""
import sys, collections, re
log = open(sys.argv[1]).read().splitlines()
want = sys.argv[2] if len(sys.argv) > 2 else None
groups = collections.defaultdict(list)
for i, l in enumerate(log):
    if not l.startswith('[error] -- '): continue
    loc = l.split(': ', 1)[-1].strip()
    f = loc.split('/com/clarifi/reporting/')[-1] if '/com/clarifi/' in loc else loc.split('/scalaparsers/')[-1]
    path, line = f.rsplit(':', 2)[0], f.rsplit(':', 2)[1] if f.count(':') >= 2 else '?'
    src, expl = '', ''
    for j in range(i+1, min(i+14, len(log))):
        if '|' not in log[j]: break
        body = log[j].split('|', 1)[1]
        t = body.strip()
        if not t: continue
        if t.startswith('^'):
            for k in range(j+1, min(j+8, len(log))):
                if '|' not in log[k]: break
                b2 = log[k].split('|', 1)[1].strip()
                if b2 and not b2.startswith('^') and not b2.startswith('longer explanation'):
                    expl = b2; break
            break
        if not src: src = t
    groups[path].append((line, src, expl))
for f in sorted(groups, key=lambda k: -len(groups[k])):
    if want and want not in f: continue
    print(f'\n===== {f}  ({len(groups[f])}) =====')
    for line, src, expl in groups[f]:
        print(f'  {line}: {src[:100]}')
        print(f'      -> {expl[:110]}')
