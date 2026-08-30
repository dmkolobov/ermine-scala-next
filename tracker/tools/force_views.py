#!/usr/bin/env python3
"""Force lazy 2.13 collection views back to strict Maps at flagged sites.

Scala 2.13 made `Map#mapValues` and `Map#filterKeys` return a lazy `MapView`.
Sites the compiler rejects need `.toMap`; sites that stay generic keep the old
behaviour, so this is driven by the error log rather than applied blanket.

Usage: force_views.py <sbt-compile-log>
"""
import re, sys, collections

log = open(sys.argv[1]).read().splitlines()
targets = collections.defaultdict(set)
for i, l in enumerate(log):
    if not l.startswith('[error] -- '): continue
    loc = l.split(': ', 1)[-1].strip()
    if '/com/clarifi/' not in loc: continue
    body = '\n'.join(log[i+1:i+14])
    if 'MapView' not in body: continue
    path, line = loc.rsplit(':', 3)[0], int(loc.rsplit(':', 3)[1])
    targets[path].add(line)

CALL = re.compile(r'\.(mapValues|filterKeys)\s*\(')
for path, lines in sorted(targets.items()):
    raw = open(path, 'rb').read().decode('utf-8')
    crlf = '\r\n' in raw
    src = raw.replace('\r\n', '\n').split('\n')
    done = []
    for n in sorted(lines):
        line = src[n-1]
        m = CALL.search(line)
        if not m:
            print(f'  SKIP (not a plain call) {path}:{n}: {line.strip()[:70]}')
            continue
        depth, j = 0, m.end() - 1
        while j < len(line):
            if line[j] == '(': depth += 1
            elif line[j] == ')':
                depth -= 1
                if depth == 0: break
            j += 1
        if depth != 0:
            print(f'  SKIP (unbalanced) {path}:{n}')
            continue
        if line[j+1:j+7] == '.toMap':
            continue
        src[n-1] = line[:j+1] + '.toMap' + line[j+1:]
        done.append(n)
    if done:
        out = '\n'.join(src)
        open(path, 'wb').write((out.replace('\n', '\r\n') if crlf else out).encode('utf-8'))
        print(f'  {path.split("/")[-1]}: forced lines {done}')
