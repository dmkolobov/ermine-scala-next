#!/usr/bin/env python3
"""THE EXPECTED-VERDICT ORACLE for the signature-entailment check (S2's decision procedure,
run on a warn-mode sweep's records).  Committed at S3 as the reference the shipped Scala
engine is differentially tested against (`TestSigEntailDiff`, design (e) 2a): this file and
`core/src/main/scala/.../SigEntail.scala` are two independent implementations of the same
judgement, and the test fails if they disagree on any signature of the corpus.

  ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" \
    tracker/tools/corpus-run.sh --batch /tmp/corpus-warn
  tracker/tools/sigcheck.py /tmp/corpus-warn                 # counts + the rejections
  tracker/tools/sigcheck.py /tmp/corpus-warn --tsv out.tsv   # one line per signature,
                                                             # for the Scala test resource

S3 additions to S2's scratch version: the ninth probe column (`ds`, the skolem-FREE half of
the residual) is read and passed to the closure of SIG-2-DESIGN.md (a3), and `--assert-qsat`
checks the design's claim that no corpus signature has a label class at which the GIVENS
have no model (the hypothesis the completeness half needs -- without it the per-label reading
is strictly stronger than the judgement and a verdict may not be claimed).

For every signature the probe reported a ROW obligation for, decide

    for every model rho of the row GIVENS there is a rho' agreeing with rho off F
    such that rho' models the row WANTEDS

by the per-label method of tracker/lean/Rowpartition/SigEntail.lean: one Boolean 2QBF per
label class (each literally mentioned label, plus ONE generic label for all the others),
using the one-hot propagation of Constraints.propagate and a search with a node budget.

R = every variable of the givens (skolems, dangling Bounds and the givens' own existential
witnesses -- rigid, SIG-2-DESIGN.md (a1)/(a3)); F = the variables of the wanteds that do not
occur in the givens.  Class constraints contribute nothing to the row theory and are dropped.
"""
import sys, os, re, collections, itertools

VAR  = re.compile(r'^([A-Za-z0-9_.\'\-]*)\^(\d+)([SAB]?)$')
CONC = re.compile(r'^\(\|(.*)\|\)$')
NODE_BUDGET  = 400000
MODEL_BUDGET = 20000

NAMES = {}                      # var id -> the name the probe printed, for readable dumps

def vn(i):
    n = NAMES.get(i, '')
    return ('%s^%d' % (n, i)) if n else str(i)

def _files(root):
    """S3b: a single FILE is accepted as well as a directory of sweep outputs."""
    if os.path.isfile(root): return [root]
    out = []
    for d, _, ns in os.walk(root):
        out += [os.path.join(d, n) for n in sorted(ns)
                if n.endswith('.out') or n.endswith('.log') or n.endswith('.txt')]
    return sorted(out)

def read(root):
    for f in _files(root):
        for line in open(f, errors='replace'):
            i = line.find('sigEntail\t')
            if i >= 0:                  # a logger stamp may precede the record
                c = line[i:].rstrip('\n').split('\t')
                if len(c) >= 8: yield c   # 8 columns + tid on stdout, 9 through RowTrace (S3 edit 10)

def parse_part(t):
    m = CONC.match(t)
    if m: return ('c', frozenset(x for x in m.group(1).split(',') if x))
    m = VAR.match(t)
    if m:
        i = int(m.group(2))
        if m.group(1): NAMES.setdefault(i, m.group(1))   # S3b: readable dumps
        return ('v', i, m.group(3))
    return None

def parse_constraints(t):
    """-> None (the model cannot state it) | a list of constraints.

    S3: `(||) <- (p1..pk)` -- the EMPTY row on the left -- is normalised to `pi <- ()` for
    every part, which is equivalent (a whole that is empty forces every part empty, and
    conversely) and is what the model can state.  269 of the corpus's `ds` constraints have
    this shape and two verdicts depend on them.

    A NON-EMPTY literal on the left, `(|K|) <- (p1..pk)`, is kept as it is: the constraint's
    first field is then the frozenset `K` instead of a variable id, and `Problem` turns it
    into a constant bit per label class.  The Scala engine instead mints a variable pinned
    to `K`.  The two are deliberately different routes to the same answer, so the
    differential test still compares two independent implementations."""
    if ' <- ' not in t: return None
    lhs, rhs = t.split(' <- ', 1)
    if not rhs.startswith('(') or not rhs.endswith(')'): return None
    l = parse_part(lhs)
    if l is None: return None
    if l[0] == 'c':
        parts = [parse_part(x) for x in rhs[1:-1].split(', ')]
        if any(p is None for p in parts): return None
        concs = [p[1] for p in parts if p[0] == 'c']
        if l[1] or any(concs):                   # a literal whole: kept, see above
            # (an EMPTY whole with a literal part is kept too: it is unsatisfiable at that
            # part's labels, and the engine decides it the same way)
            if len(concs) > 1: return None       # two literal parts: a drop, as in the engine
            return [(l[1], [p[1] for p in parts if p[0] == 'v'],
                     concs[0] if concs else frozenset(),
                     {p[1]: p[2] for p in parts if p[0] == 'v'})]
        return [(p[1], [], frozenset(), {p[1]: p[2]}) for p in parts if p[0] == 'v']
    c = parse_constraint(t)
    return None if c is None else [c]

def parse_constraint(t):
    if ' <- ' not in t: return None
    lhs, rhs = t.split(' <- ', 1)
    if not rhs.startswith('(') or not rhs.endswith(')'): return None
    l = parse_part(lhs)
    if l is None or l[0] != 'v': return None     # a concrete lhs: parse_constraints handles it
    parts = [parse_part(x) for x in rhs[1:-1].split(', ')]
    if any(p is None for p in parts): return None
    tags = {l[1]: l[2]}
    for p in parts:
        if p[0] == 'v': tags[p[1]] = p[2]
    return (l[1], [p[1] for p in parts if p[0] == 'v'],
            frozenset().union(*[p[1] for p in parts if p[0] == 'c']) if any(p[0]=='c' for p in parts) else frozenset(),
            tags)

def is_lit(lhs):
    """A literal whole: a frozenset of labels (in a parsed constraint) or, inside one label
    class, the constant bit `('lit', 0|1)`."""
    return isinstance(lhs, (frozenset, tuple))

class Problem:
    """One label class: constraints (lhs, vars, conc_bit).  A literal whole becomes the
    constant `('lit', bit)`: 1 if the class's label is in it, else 0."""
    def __init__(self, cs, label):
        def has(k): return 1 if (label is not None and label in k) else 0
        self.cs = [((('lit', has(c[0])) if is_lit(c[0]) else c[0]), c[1], has(c[2])) for c in cs]

def lhs_bit(lhs, bits):
    return lhs[1] if is_lit(lhs) else bits.get(lhs)

def propagate(cs, bits, queue, nodes):
    """3-valued one-hot propagation.  bits: dict var -> 0/1/None."""
    while queue:
        nodes[0] += 1
        if nodes[0] > NODE_BUDGET: return 'budget'
        lhs, vs, conc = queue.pop()
        ones = conc + sum(1 for v in vs if bits.get(v) == 1)
        unk  = [v for v in vs if bits.get(v) is None]
        if ones > 1: return False
        def setbit(v, x):
            if is_lit(v): return v[1] == x        # a literal whole is already decided
            if bits.get(v) is None:
                bits[v] = x
                for c in cs:
                    if c[0] == v or v in c[1]: queue.append(c)
                return True
            return bits[v] == x
        if ones == 1:
            if not setbit(lhs, 1): return False
            for v in unk:
                if not setbit(v, 0): return False
        elif lhs_bit(lhs, bits) == 0:
            if conc: return False
            for v in unk:
                if not setbit(v, 0): return False
        elif ones == 0 and not unk:
            if not setbit(lhs, 0): return False
        elif lhs_bit(lhs, bits) == 1 and ones == 0:
            if not unk: return False
            if len(unk) == 1 and not setbit(unk[0], 1): return False
    return True

def verify(cs, bits):
    for lhs, vs, conc in cs:
        ones = conc + sum(1 for v in vs if bits.get(v) == 1)
        if ones > 1: return False
        if (ones == 1) != (lhs_bit(lhs, bits) == 1): return False
    return True

def models(cs, vs, bits, nodes, out, limit):
    """Enumerate every total model over vs extending bits.  out: list of dicts."""
    if len(out) >= limit: return 'budget'
    b = dict(bits)
    r = propagate(cs, b, list(cs), nodes)
    if r == 'budget': return 'budget'
    if r is False: return True
    u = next((v for v in vs if b.get(v) is None), None)
    if u is None:
        if verify(cs, b): out.append(b)
        return True
    for x in (0, 1):
        bb = dict(b); bb[u] = x
        res = models(cs, vs, bb, nodes, out, limit)
        if res == 'budget': return 'budget'
    return True

def satisfiable(cs, vs, bits, nodes):
    b = dict(bits)
    r = propagate(cs, b, list(cs), nodes)
    if r == 'budget': return 'budget'
    if r is False: return False
    u = next((v for v in vs if b.get(v) is None), None)
    if u is None: return verify(cs, b)
    for x in (0, 1):
        bb = dict(b); bb[u] = x
        res = satisfiable(cs, vs, bb, nodes)
        if res == 'budget': return 'budget'
        if res: return True
    return False

def varsof(cs):
    s = set()
    for c in cs:
        if not is_lit(c[0]): s.add(c[0])
        s.update(c[1])
    return s

def tagsof(cs):
    t = {}
    for c in cs:
        if len(c) > 3: t.update(c[3])
    return t


def closeW(W, ps, F, qv=frozenset(), tags=None):
    """SIG-2-DESIGN (a3): close the obligation set under shared MINTED variables within `ps`.
    `ps` is `rs ++ ds`; before S3 the probe printed only `rs` and this was the identity.

    S3 (found by the Scala differential, `TestSigEntailDiff`): the closure is a FIXPOINT in
    `F` as well as in the constraint set.  A `ds` member pulled in can mention minted
    variables the original `rs` never did, and a second `ds` member sharing one of THOSE is
    just as much a constraint on the choice `W` is allowed to make -- the body's residual is
    one conjunction.  Closing with the `F` of `rs` alone (which is what this function did,
    and what produced the S2 design's numbers) is the weaker reading and differs on
    `Layout.Report.Relation.others`: with the fixpoint the refutation is found at the label
    class `cutoff` rather than at `cutoffChild`.  Same verdict, one class earlier."""
    sel = list(W); seen = {id(c) for c in sel}
    changed = True
    while changed:
        changed = False
        if tags is not None:
            F = {v for v in varsof(sel) - qv if tags.get(v, '') in ('A', '')}
        have = set()
        for c in sel: have |= ({c[0]} | set(c[1])) & F
        for c in ps:
            if id(c) in seen: continue
            if (({c[0]} | set(c[1])) & have):
                sel.append(c); seen.add(id(c)); changed = True
    return sel

COST = []

def decide(Q, W, DS=(), caveatQ=None, caveatW=None):
    """-> ('ACCEPT',None) | ('REJECT',(label, witness)) | ('NOVERDICT',why)

    `caveatQ`/`caveatW` carry S3's DROP POLICY (SigEntail.scala, design (e) 2b): a constraint
    the model cannot state is dropped by name, and the drop forbids one verdict -- a dropped
    GIVEN forbids REJECT (the real context may be stronger), a dropped OBLIGATION forbids
    ACCEPT (the real obligation set may be larger, and rejection is monotone in it)."""
    qv, wv = varsof(Q), varsof(W)
    tags = tagsof(Q); tags.update({k: v for k, v in tagsof(W).items() if k not in tags})
    # F: existential (solver-minted) variables of the WANTEDS -- tag `A` (Ambiguous, what
    # `unbindExists` mints) or bare `Free` -- that do NOT occur in the givens.  A skolem
    # (`S`) or a dangling `Bound` (`B`) is RIGID wherever it occurs, and a given's own
    # existential is rigid too (SIG-2-DESIGN.md (a1)/(a3)).
    F = {v for v in wv - qv if tags.get(v, '') in ('A', '')}
    W = closeW(W, list(W) + [d for d in DS if d not in W], F, qv, tags)
    wv = varsof(W)
    F = {v for v in wv - qv if tags.get(v, '') in ('A', '')}
    R = (qv | wv) - F
    labels = set()
    for c in Q + W:
        labels |= set(c[2])
        if is_lit(c[0]): labels |= set(c[0])
    classes = sorted(labels) + [None]
    tot = [0, 0, len(classes)]
    for lab in classes:
        pq, pw = Problem(Q, lab).cs, Problem(W, lab).cs
        nodes = [0]
        out = []
        res = models(pq, sorted(R), {}, nodes, out, MODEL_BUDGET)
        tot[0] += nodes[0]; tot[1] = max(tot[1], len(out))
        if res == 'budget':
            COST.append(tot); return ('NOVERDICT', 'outer budget at %s' % lab)
        seen = set()
        for m in out:
            key = tuple(sorted((v, m[v]) for v in (wv & R)))
            if key in seen: continue
            seen.add(key)
            frozen = {v: m[v] for v in (wv & R)}
            s = satisfiable(pw, sorted(wv), frozen, nodes)
            if s == 'budget': return ('NOVERDICT', 'inner budget at %s' % lab)
            if not s:
                tot[0] += nodes[0]; COST.append(tot)
                if caveatQ: return ('NOVERDICT', 'a given was dropped: %s' % caveatQ)
                return ('REJECT', (lab, dict(m)))
        tot[0] = nodes[0] + tot[0]
    COST.append(tot)
    if caveatW: return ('NOVERDICT', 'an obligation was dropped: %s' % caveatW)
    return ('ACCEPT', None)

def qsat(Q):
    """Design (a2): does every label class of the GIVENS have a model?  Completeness of the
    per-label reading needs it, so the oracle ASSERTS it rather than remarking on it."""
    labels = set()
    for c in Q:
        labels |= set(c[2])
        if is_lit(c[0]): labels |= set(c[0])
    for lab in sorted(labels) + [None]:
        pq = Problem(Q, lab).cs
        if satisfiable(pq, sorted(varsof(Q)), {}, [0]) is not True: return lab
    return None

root = sys.argv[1]
args = sys.argv[2:]
only = next((a for a in args if not a.startswith('--')), None)
tsv  = None
if '--tsv' in args: tsv = args[args.index('--tsv') + 1]
assert_qsat = '--assert-qsat' in args
ck = collections.defaultdict(lambda: {'W': [], 'Q': None, 'DS': [], 'bad': 0, 'pos': [],
                                     'cq': None, 'cw': None})
for c in read(root):
    _, mod, binding, pos, shape, lit, wanted, givens = c[:8]
    free = c[8] if len(c) > 8 else ''
    if ' <- ' not in wanted: continue
    key = (mod, binding, givens)
    ch = ck[key]
    ws = parse_constraints(wanted)
    if ws is None:
        ch['bad'] += 1
        ch['cw'] = ch['cw'] or ('an obligation the model cannot state: %s' % wanted)
    else:
        for w in ws:
            if w not in ch['W']: ch['W'].append(w); ch['pos'].append(pos)
    for d in free.split('; '):
        if ' <- ' not in d: continue
        dds = parse_constraints(d)
        if dds is None: ch['cw'] = ch['cw'] or ('a ds member the model cannot state: %s' % d)
        else:
            for dd in dds:
                if dd not in ch['DS']: ch['DS'].append(dd)
    if ch['Q'] is None:
        ch['Q'] = []
        for g in givens.split('; '):
            if not g: continue
            qsq = parse_constraints(g)
            # a given with no ' <- ' is a CLASS constraint: out of scope by design, not a
            # drop.  One that looks like a partition and does not parse IS a drop.
            if qsq is None:
                if ' <- ' in g:
                    ch['cq'] = ch['cq'] or ('a given the model cannot state: %s' % g)
            else:
                for q in qsq:
                    if q not in ch['Q']: ch['Q'].append(q)
        ch['Qtags'] = tagsof(ch['Q'])
unsat_q = []
best = {}
for (mod, binding, _), ch in ck.items():
    if not ch['W']: continue
    k = (mod, binding)
    if assert_qsat:
        bad = qsat(ch['Q'])
        if bad is not None: unsat_q.append((mod, binding, bad))
    v = decide(ch['Q'], ch['W'], ch['DS'], ch['cq'], ch['cw'])
    prev = best.get(k)
    # a signature is REJECTED if any of its id-universes rejects (they are alpha-variants)
    rank = {'REJECT': 2, 'NOVERDICT': 1, 'ACCEPT': 0}
    if prev is None or rank[v[0]] > rank[prev[0][0]]:
        best[k] = (v, ch)
cnt = collections.Counter(v[0][0] for v in best.values())
print("signatures decided: %d   %s" % (len(best), dict(cnt)))
if assert_qsat:
    print("signatures whose GIVENS have no model at some label class: %d %s"
          % (len(unsat_q), unsat_q if unsat_q else ''))
if '--records' in args:
    # the INPUT side of the Scala differential test: the probe's records, deduped, five
    # columns (module, binding, wanted, givens, ds).  The Scala test parses these with its
    # own reader and must reach the same verdict as `--tsv` says.
    out = args[args.index('--records') + 1]
    seen, n = set(), 0
    with open(out, 'w') as f:
        for c in read(root):
            _, mod, binding, pos, shape, lit, wanted, givens = c[:8]
            free = c[8] if len(c) > 8 else ''
            if ' <- ' not in wanted: continue
            line = "\t".join([mod, binding, wanted, givens, free])
            if line in seen: continue
            seen.add(line); f.write(line + "\n"); n += 1
    print("wrote %s (%d records)" % (out, n))
if tsv:
    # the EXPECTED side of the Scala differential test, one line per signature:
    #   verdict \t module \t binding \t label class ('*' = the generic class)
    with open(tsv, 'w') as f:
        for (mod, b), (v, ch) in sorted(best.items()):
            lab = '' if v[0] != 'REJECT' else ('*' if v[1][0] is None else v[1][0])
            f.write("\t".join([v[0], mod, b, lab]) + "\n")
    print("wrote %s (%d signatures)" % (tsv, len(best)))
if COST:
    ns = [c[0] for c in COST]; ms = [c[1] for c in COST]; cl = [c[2] for c in COST]
    ns.sort(); ms.sort()
    print("cost over %d decisions: propagation steps max %d median %d p90 %d; "
          "Q-models at one label max %d median %d; label classes max %d"
          % (len(COST), ns[-1], ns[len(ns)//2], ns[int(.9*len(ns))], ms[-1], ms[len(ms)//2], max(cl)))
print()
for (mod, b), (v, ch) in sorted(best.items()):
    if only and not re.search(only, mod + '.' + b): continue
    if v[0] == 'ACCEPT' and only is None: continue
    print("%-9s %s.%s" % (v[0], mod, b.split(':',1)[1]))
    if v[0] == 'REJECT':
        lab, m = v[1]
        print("    class: %s" % ('generic (a label mentioned nowhere)' if lab is None else lab))
        print("    witness (rows holding the label): %s"
              % sorted(vn(k) for k, x in m.items() if x == 1))
    if v[0] == 'NOVERDICT': print("    %s" % v[1])
    def show(cs):                                   # S3b: readable, with names
        def whole(l): return ('(|%s|)' % ','.join(sorted(l))) if is_lit(l) else vn(l)
        return ['%s <- (%s)' % (whole(c[0]), ', '.join([vn(x) for x in c[1]] +
                (['(|%s|)' % ','.join(sorted(c[2]))] if c[2] else []))) for c in cs]
    print("    Q: %s" % show(ch['Q']))
    print("    W: %s" % show(ch['W']))
    print("    ds: %s" % show(ch['DS']))
    tg = tagsof(ch['Q']); tg.update({k: v for k, v in tagsof(ch['W']).items() if k not in tg})
    qv, wv = varsof(ch['Q']), varsof(ch['W'])
    print("    F: %s   R: %s" % (sorted(vn(v) for v in wv - qv if tg.get(v,'') in ('A','')),
                                 sorted(vn(v) for v in (qv|wv) - {v for v in wv - qv if tg.get(v,'') in ('A','')})))
    print("    at: %s" % ' '.join(sorted(set(ch['pos']))))
    if ch['bad']: print("    unreadable wanteds: %d" % ch['bad'])
