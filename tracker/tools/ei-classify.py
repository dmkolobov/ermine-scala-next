#!/usr/bin/env python3
"""Classify the differences between two snapshots of published `.ei` interfaces.

    tracker/tools/ei-classify.py <dirA> <dirB>

Input: two directories of FLATTENED `.ei` files, as `tracker/tools/ei-diff.sh` writes
them (`<snap>/core_examples_Foo.ei`).  Each `.ei` is one `name : signature` per line.

Per binding present on both sides the verdict is one of

  identical              the signature strings are equal
  order-only             equal after sorting the binder list, the constraint list and
                         the right-hand side of every partition constraint -- no
                         renaming needed (this is the id-shift churn every flag that
                         changes minting produces)
  alpha-equivalent       equal under a BIJECTION of the bound type variables, found by
                         unifying the bodies token-wise and then matching the constraint
                         multisets with backtracking
  concrete->polymorphic  side B is quantified/constrained where side A was a concrete
                         row -- a WEAKER published type, the blocker
  polymorphic->concrete  the reverse -- a STRONGER published type, a note
  other                  none of the above; printed in full for hand classification

plus `only-in-A` / `only-in-B` for bindings and for whole interfaces.

The classification is the one `TICKET-substitution-gap.md` §4 used (its script lived in
session scratch and is gone); it is deliberately conservative -- anything it cannot prove
equivalent lands in `other` and gets printed.
"""
import sys, os, re, itertools
from collections import Counter

TOK = re.compile(r'\(\|[^|]*\|\)|[A-Za-z_][A-Za-z0-9_\'.]*|<-|->|=>|\S')

def read_ei(path):
    out = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.rstrip('\n')
        if not line.strip():
            continue
        # S5.2: an `.ei` opens with the solver-configuration key
        # (`-- ermine-interface <format>|<GenRules>`).  It is not a binding; it is
        # also not noise -- two sides with DIFFERENT keys are two configurations and
        # comparing them is the point -- so it is skipped here and reported by the
        # caller if it matters.  Without this it landed in `<<unparsed>>` as a LIST
        # and `classify` crashed on it.
        if line.startswith('-- ermine-interface '):
            out.setdefault('<<key>>', line[len('-- ermine-interface '):].strip())
            continue
        i = line.find(' : ')
        if i < 0:
            out.setdefault('<<unparsed>>', []).append(line)
            continue
        out[line[:i]] = line[i+3:]
    return out

def split_sig(sig):
    """-> (binders:list[str], constraints:list[str], body:str). Tolerant."""
    s = sig.strip()
    binders = []
    m = re.match(r'forall\s+(.*?)\.\s*(.*)$', s, re.S)
    if m:
        binders = re.findall(r'\([^)]*\)|[A-Za-z_][A-Za-z0-9_\']*', m.group(1))
        s = m.group(2)
    cons = []
    if s.startswith('('):
        depth = 0
        for i, ch in enumerate(s):
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    head, rest = s[:i+1], s[i+1:]
                    if rest.lstrip().startswith('=>'):
                        inner = head[1:-1].strip()
                        # the context may open with its own `exists <binders>.` prefix;
                        # it must go to the BINDER list, not glue itself to whichever
                        # constraint happens to be printed first (that alone made every
                        # constraint-order difference look like a real one)
                        me = re.match(r'exists\s+(.*?)\.\s*(.*)$', inner, re.S)
                        if me:
                            binders += re.findall(r'\([^)]*\)|[A-Za-z_][A-Za-z0-9_\']*',
                                                  me.group(1))
                            inner = me.group(2)
                        cons = split_top(inner)
                        s = rest.lstrip()[2:].strip()
                    break
    return binders, cons, s

def split_top(s):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch in '([':
            depth += 1
        elif ch in ')]':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip()); cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out

def binder_name(b):
    b = b.strip()
    if b.startswith('('):
        return b[1:].split(':')[0].strip()
    return b

CONCROW = re.compile(r'\(\|([^|]*)\|\)')

def norm_conc(s):
    """`(|b, a|)` and `(|a, b|)` are the same row: sort the labels inside."""
    return CONCROW.sub(lambda m: '(|' + ', '.join(sorted(x.strip() for x in m.group(1).split(',')
                                                         if x.strip())) + '|)', s)

def as_part(c):
    """`L <- (r1, .., rn)` -> ('part', L, [r1..rn]); anything else -> ('atom', c)"""
    c = norm_conc(c.strip())
    m = re.match(r'^(.*?)<-\s*\((.*)\)\s*$', c, re.S)
    if not m:
        return ('atom', c, None)
    return ('part', m.group(1).strip(), split_top(m.group(2)))

def norm_constraint(c):
    """canonical form used only for the cheap `order-only` test: labels inside a concrete
    row sorted, right-hand side sorted."""
    k, l, r = as_part(c)
    return l if k == 'atom' else l + ' <- (' + ', '.join(sorted(r)) + ')'

def all_bound(sig):
    """every name bound by a forall or an exists anywhere in the signature"""
    names = set()
    for m in re.finditer(r'\b(forall|exists)\s+(.*?)\.', sig, re.S):
        for b in re.findall(r'\([^)]*\)|[A-Za-z_][A-Za-z0-9_\']*', m.group(2)):
            names.add(binder_name(b))
    return names

def canon(sig):
    b, c, body = split_sig(sig)
    return (tuple(sorted(binder_name(x) for x in b)),
            tuple(sorted(norm_constraint(x) for x in c)), body.strip())

def toks(s):
    return TOK.findall(s)

def unify_tokens(ta, tb, bnda, bndb, sub):
    if len(ta) != len(tb):
        return False
    for x, y in zip(ta, tb):
        if x in bnda or y in bndb:
            if x not in bnda or y not in bndb:
                return False
            if sub.get(x, y) != y or {v: k for k, v in sub.items()}.get(y, x) != x:
                return False
            sub[x] = y
        elif x != y:
            return False
    return True

def match_items(la, lb, bnda, bndb, sub):
    """match two right-hand sides as MULTISETS under a growing bijection.  Sorting them
    first would be wrong: the sort is by the ORIGINAL names, and the bijection need not
    preserve that order -- which is exactly how `RunCalibration.scaledRuns` escaped an earlier
    version of this matcher."""
    if len(la) != len(lb):
        return None
    def go(i, sub, used):
        if i == len(la):
            return sub
        for j, y in enumerate(lb):
            if j in used:
                continue
            s2 = dict(sub)
            if unify_tokens(toks(la[i]), toks(y), bnda, bndb, s2):
                r = go(i + 1, s2, used | {j})
                if r is not None:
                    return r
        return None
    return go(0, sub, frozenset())

def match_constraint(a, b, bnda, bndb, sub):
    ka, la, ra = as_part(a)
    kb, lb, rb = as_part(b)
    if ka != kb:
        return None
    s2 = dict(sub)
    if not unify_tokens(toks(la), toks(lb), bnda, bndb, s2):
        return None
    if ka == 'atom':
        return s2
    return match_items(ra, rb, bnda, bndb, s2)

def alpha_eq(sa, sb):
    """bijection of bound names making the two signatures equal; returns sub or None"""
    ba, ca, bodya = split_sig(sa)
    bb, cb, bodyb = split_sig(sb)
    if len(ca) != len(cb) or len(ba) != len(bb):
        return None
    bnda, bndb = all_bound(sa), all_bound(sb)
    sub = {}
    if not unify_tokens(toks(norm_conc(bodya)), toks(norm_conc(bodyb)), bnda, bndb, sub):
        return None

    def go(i, sub, used):
        if i == len(ca):
            return sub
        for j, y in enumerate(cb):
            if j in used:
                continue
            s2 = match_constraint(ca[i], y, bnda, bndb, dict(sub))
            if s2 is not None:
                r = go(i + 1, s2, used | {j})
                if r is not None:
                    return r
        return None
    return go(0, sub, frozenset())

CONC = re.compile(r'\(\|')

def classify(sa, sb):
    if sa == sb:
        return 'identical', ''
    ka, kb = canon(sa), canon(sb)
    if ka == kb:
        return 'order-only', ''
    sub = alpha_eq(sa, sb)
    if sub is not None:
        return ('order-only', '') if all(k == v for k, v in sub.items()) else ('alpha-equivalent', '')
    qa = ('forall' in sa) or ('=>' in sa)
    qb = ('forall' in sb) or ('=>' in sb)
    if qb and not qa:
        return 'concrete->polymorphic', 'WEAKER on side B'
    if qa and not qb:
        return 'polymorphic->concrete', 'STRONGER on side B'
    na, nb = len(split_sig(sa)[1]), len(split_sig(sb)[1])
    if na != nb:
        return 'other', 'constraints %d -> %d' % (na, nb)
    return 'other', ''

def main(da, db):
    fa = {f for f in os.listdir(da) if f.endswith('.ei')}
    fb = {f for f in os.listdir(db) if f.endswith('.ei')}
    print('interfaces: A %d  B %d  only-in-A %s  only-in-B %s'
          % (len(fa), len(fb), sorted(fa - fb) or '-', sorted(fb - fa) or '-'))
    tally, differing_files, key_differs = Counter(), [], []
    for f in sorted(fa & fb):
        A, B = read_ei(os.path.join(da, f)), read_ei(os.path.join(db, f))
        rows = []
        for n in sorted(set(A) | set(B)):
            if n not in A:
                rows.append((n, 'only-in-B', '', '', B[n])); continue
            if n not in B:
                rows.append((n, 'only-in-A', '', A[n], '')); continue
            if n == '<<key>>':
                # S5 review Q-6: a differing KEY is expected in every flag A/B -- the
                # flag is IN the key -- so it must NOT put the file in
                # `differing_files`, or the headline reads "268 of 268 differ" for the
                # comparison this tool exists for.  Counted separately below.
                if A.get(n) != B.get(n):
                    key_differs.append(f)
                continue
            kind, note = classify(A[n], B[n])
            tally[kind] += 1
            if kind != 'identical':
                rows.append((n, kind, note, A[n], B[n]))
        if rows:
            differing_files.append(f)
            print('\n--- %s' % f)
            for n, kind, note, a, b in rows:
                print('  %-28s %-22s %s' % (n, kind, note))
                if kind in ('other', 'concrete->polymorphic', 'polymorphic->concrete',
                            'only-in-A', 'only-in-B'):
                    print('      A: %s' % a)
                    print('      B: %s' % b)
    print('\n== %d of %d interfaces differ' % (len(differing_files), len(fa & fb)))
    print('== bindings by verdict: %s' % dict(tally))
    if key_differs:
        ka = read_ei(os.path.join(da, key_differs[0])).get('<<key>>')
        kb = read_ei(os.path.join(db, key_differs[0])).get('<<key>>')
        print('== interface key differs on %d of %d files (expected in a flag A/B): '
              '%s -> %s' % (len(key_differs), len(fa & fb), ka, kb))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
