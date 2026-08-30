#!/usr/bin/env python3
"""Append `.toMap` to a specific `mapValues(...)` call.

Scala 2.13 made `Map#mapValues` return a lazy `MapView` instead of a `Map`.
Sites that are *used* as a Map need forcing; sites that stay generic keep the
old lazy behaviour, so only the ones the compiler rejects are touched.

Usage: fix_mapvalues.py file.scala:LINE [file.scala:LINE ...]
"""
import sys

def force(path, lineno):
    raw = open(path, 'rb').read().decode('utf-8')
    crlf = '\r\n' in raw
    lines = raw.replace('\r\n', '\n').split('\n')
    i = lineno - 1
    idx = lines[i].find('mapValues')
    if idx < 0:
        return f'no mapValues on {path}:{lineno}'
    k = lines[i].find('(', idx)
    if k < 0:
        return f'no ( after mapValues on {path}:{lineno}'
    depth, j = 0, k
    while j < len(lines[i]):
        c = lines[i][j]
        if c == '(': depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0: break
        j += 1
    if depth != 0:
        return f'unbalanced on {path}:{lineno}'
    if lines[i][j+1:j+7] == '.toMap':
        return f'already forced {path}:{lineno}'
    lines[i] = lines[i][:j+1] + '.toMap' + lines[i][j+1:]
    out = '\n'.join(lines)
    open(path, 'wb').write((out.replace('\n', '\r\n') if crlf else out).encode('utf-8'))
    return f'ok {path}:{lineno}'

for a in sys.argv[1:]:
    p, n = a.rsplit(':', 1)
    print(force(p, int(n)))
