#!/usr/bin/env python3
"""Rewrite Scala 2 procedure syntax `def f(..) { .. }` to `def f(..): Unit = { .. }`.

Only touches a `def` whose signature is followed directly by `{` with no
return type and no `=`. Handles multi-line parameter lists, type parameters,
multiple parameter lists, and defs with no parameter list at all.
"""
import re, sys

DEF = re.compile(r'^(\s*)((?:(?:override|final|private|protected|implicit|lazy|abstract|sealed|@\w+)\s+)*)def\s+([A-Za-z_$][A-Za-z0-9_$]*|[^\s(\[]+)')

def transform(text):
    lines = text.split('\n')
    out = list(lines)
    changed = 0
    i = 0
    while i < len(lines):
        m = DEF.match(lines[i])
        if not m:
            i += 1
            continue
        # Walk forward from the end of the def name, tracking bracket depth,
        # until depth is 0 and we hit a '{', '=', ':' or end of the signature.
        depth = 0
        j, k = i, m.end()
        found = None            # (line_idx, col) of the '{' that opens the body
        instr = False
        while j < len(lines):
            line = lines[j]
            while k < len(line):
                c = line[k]
                if instr:
                    if c == '\\': k += 2; continue
                    if c == '"': instr = False
                    k += 1; continue
                if c == '"': instr = True; k += 1; continue
                if c == '/' and k + 1 < len(line) and line[k+1] == '/':
                    k = len(line); break
                if c in '([': depth += 1
                elif c in ')]': depth -= 1
                elif depth == 0:
                    if c == '{':
                        found = (j, k)
                        break
                    if c in '=:':
                        found = None
                        break
                    if not c.isspace():
                        # something else on the signature line (e.g. `def x_=`)
                        found = None
                        break
                k += 1
            if found is not None or (k < len(line) and not line[k:k+1].isspace() and depth == 0 and found is None and k < len(line)):
                break
            if found is None and depth == 0 and k >= len(line):
                # signature ended with balanced brackets but nothing after it:
                # keep scanning onto the next line
                if j + 1 < len(lines) and lines[j+1].strip():
                    j += 1; k = 0; continue
                break
            if depth != 0:
                j += 1; k = 0; continue
            break
        if found:
            lj, lk = found
            head = out[lj][:lk].rstrip()
            out[lj] = head + ': Unit = ' + out[lj][lk:]
            changed += 1
            i = lj + 1
        else:
            i += 1
    return '\n'.join(out), changed

if __name__ == '__main__':
    total = 0
    for path in sys.argv[1:]:
        src = open(path).read()
        new, n = transform(src)
        if n:
            open(path, 'w').write(new)
            total += n
            print(f'{n:3d}  {path}')
    print(f'--- {total} procedure defs rewritten')
