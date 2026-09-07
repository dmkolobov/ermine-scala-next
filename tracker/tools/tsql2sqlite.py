#!/usr/bin/env python3
"""Rewrite the MS SQL that `dumpQuery (sqlServer ...)` emits into SQLite.

Only two constructs differ for the queries this corpus produces:

  1. table-value constructors --   (values (..),(..)) as lit([c1],[c2],...)
     become                        (select v as [c1], ... union all select ...) lit
  2. `[col]desc` / `[col]asc`  --  the emitter omits the space.

SQLite accepts [bracket] identifiers and supports OVER(...) since 3.25, so
everything else -- the window clauses this whole exercise is about -- passes
through untouched.
"""
import re, sys

def split_top(s, sep=','):
    out, depth, q, cur = [], 0, None, []
    for ch in s:
        if q:
            cur.append(ch)
            if ch == q: q = None
            continue
        if ch in "'\"": q = ch; cur.append(ch); continue
        if ch == '(': depth += 1
        elif ch == ')': depth -= 1
        if ch == sep and depth == 0:
            out.append(''.join(cur)); cur = []
        else:
            cur.append(ch)
    out.append(''.join(cur))
    return [x.strip() for x in out]

def match_paren(s, i):
    """i points at '('; return index of the matching ')'."""
    depth, q = 0, None
    while i < len(s):
        ch = s[i]
        if q:
            if ch == q: q = None
        elif ch in "'\"": q = ch
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0: return i
        i += 1
    raise ValueError('unbalanced')

def rewrite(sql):
    while True:
        m = re.search(r'\(values\s', sql, re.I)
        if not m: break
        o = m.start()
        c = match_paren(sql, o)
        body = sql[o+1:c]
        body = body[body.lower().index('values')+6:]
        tail = sql[c+1:]
        tm = re.match(r'\s*as\s+lit\s*\(', tail, re.I)
        if not tm:
            raise ValueError('values without `as lit(`: ' + tail[:60])
        co = c + 1 + tm.end() - 1
        cc = match_paren(sql, co)
        cols = split_top(sql[co+1:cc])
        tuples = split_top(body)
        selects = []
        for n, t in enumerate(tuples):
            t = t.strip()
            assert t.startswith('(') and t.endswith(')'), t
            vals = split_top(t[1:-1])
            if n == 0:
                selects.append('select ' + ', '.join(f'{v} as {c2}' for v, c2 in zip(vals, cols)))
            else:
                selects.append('select ' + ', '.join(vals))
        sql = sql[:o] + '(' + ' union all '.join(selects) + ') lit' + sql[cc+1:]
    sql = re.sub(r'\](desc|asc)\b', r'] \1', sql, flags=re.I)
    return sql

if __name__ == '__main__':
    print(rewrite(sys.stdin.read().strip()))
