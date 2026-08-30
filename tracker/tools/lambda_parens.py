#!/usr/bin/env python3
"""Parenthesise typed lambda parameters: `{ x: T => ... }` -> `{ (x: T) => ... }`.

Scala 3 requires the parentheses. Only rewrites a single typed parameter that
directly follows `{` or `(`, which is the shape scalacheck's `forAll` uses.
"""
import re, sys

# `{ name: Type =>`  (Type may contain [], (), commas, dots, spaces)
PAT = re.compile(r'([{(]\s*)([A-Za-z_$][A-Za-z0-9_$]*)\s*:\s*([^={}()]*?(?:\[[^\]]*\])?[^={}()]*?)\s*=>')

def fix(line):
    def repl(m):
        open_, name, ty = m.group(1), m.group(2), m.group(3).strip()
        if not ty or ty.endswith(','):
            return m.group(0)
        return f'{open_}({name}: {ty}) =>'
    return PAT.sub(repl, line)

total = 0
for path in sys.argv[1:]:
    raw = open(path, 'rb').read().decode('utf-8')
    crlf = '\r\n' in raw
    lines = raw.replace('\r\n', '\n').split('\n')
    n = 0
    for i, l in enumerate(lines):
        new = fix(l)
        if new != l:
            lines[i] = new
            n += 1
    if n:
        out = '\n'.join(lines)
        open(path, 'wb').write((out.replace('\n', '\r\n') if crlf else out).encode('utf-8'))
        print(f'{n:3d}  {path.split("/")[-1]}')
        total += n
print(f'--- {total} typed lambda params parenthesised')
