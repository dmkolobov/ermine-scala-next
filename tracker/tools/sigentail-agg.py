#!/usr/bin/env python3
"""Aggregate the `sigEntail` probe records of a corpus sweep (stage S1 of
tracker/SIG-ENTAIL-PLAN.md).

    tracker/tools/sigentail-agg.py <outdir-or-file> [...]          # summary
    tracker/tools/sigentail-agg.py --list nolit-row <outdir> ...   # one line per hit
    tracker/tools/sigentail-agg.py --tsv <outdir> ...              # the deduped table

A record is

    sigEntail \\t module \\t kind:binding \\t file:line:col \\t shape \\t lit|nolit
              \\t wanted \\t givens \\t thread

written by `SigEntail.probe` under `-Dermine.sigEntail=warn`.  The STDLIB BOOT runs inside
every per-file invocation, so the same stdlib obligation appears once per corpus file; the
identity used for deduplication is everything but the variable IDS and the thread column,
because two JVMs number their variables from their own `Supply`.  That identity is what
"unique hit" means in every count below.

`shape` comes from the compiler (SigEntail.shapeOf).  `other` is split here into
`other-class` (a class constraint over a skolem -- not a row obligation, and reported
separately because S1's subject is the row hole) and `other-row` (a row partition that is
none of the three row shapes), on whether the wanted contains the partition arrow.
"""
import sys, os, re, collections

VAR = re.compile(r'\^\d+')
PART = re.compile(r'^(.*?) <- \((.*)\)$')

def norm(s):
    """Canonicalise a rendered constraint for DEDUPLICATION.

    Three things vary between two JVMs that check the same signature and must not
    make one obligation look like two: the variable IDS (each run draws its own from
    its `Supply`), the ORDER OF THE PARTS inside a partition (`Part.apply` fixes
    none), and the ORDER OF THE GIVENS (`Exists.apply` does `p.toSet.toList`, whose
    order follows the hashes, which follow the ids).  So: drop the ids, keep the name
    and the flavour tag, and sort both lists.  Two distinct variables that share a
    name and a flavour are conflated -- rare inside one signature, and it can only
    merge hits, never split them."""
    return '; '.join(sorted(_part(x) for x in VAR.sub('^', s).split('; ')))

def _part(w):
    m = PART.match(w)
    return w if not m else m.group(1) + ' <- (' + ', '.join(sorted(m.group(2).split(', '))) + ')'

def kindof(shape, wanted):
    if shape != 'other':
        return shape
    return 'other-row' if ' <- ' in wanted else 'other-class'

def read(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            for n in sorted(os.listdir(p)):
                if n.endswith('.out') or n.endswith('.log'):
                    files.append(os.path.join(p, n))
        else:
            files.append(p)
    seen = {}
    raw = 0
    for f in files:
        with open(f, errors='replace') as fh:
            for line in fh:
                if not line.startswith('sigEntail\t'):
                    continue
                c = line.rstrip('\n').split('\t')
                if len(c) < 8:
                    continue
                raw += 1
                mod, binding, pos, shape, lit, wanted, givens = c[1], c[2], c[3], c[4], c[5], c[6], c[7]
                key = (mod, binding, pos, shape, lit, norm(wanted), norm(givens))
                if key not in seen:
                    seen[key] = (mod, binding, pos, kindof(shape, wanted), lit, wanted, givens,
                                 os.path.basename(f))
    return raw, list(seen.values())

def main():
    args = sys.argv[1:]
    mode, want = 'summary', None
    if args and args[0] == '--list':
        mode, want, args = 'list', args[1], args[2:]
    elif args and args[0] == '--tsv':
        mode, args = 'tsv', args[1:]
    if not args:
        print(__doc__); sys.exit(2)
    raw, hits = read(args)

    if mode == 'tsv':
        for h in sorted(hits):
            print('\t'.join(h[:7]))
        return
    if mode == 'list':
        sel = [h for h in sorted(hits)
               if want == 'all'
               or h[3] == want
               or (want == 'nolit-row' and h[4] == 'nolit' and ' <- ' in h[5])
               or (want == 'nolit' and h[4] == 'nolit')]
        for h in sel:
            print('%s\t%s\t%s\t%s\t%s\t%s' % (h[0], h[1], h[2], h[3], h[4], h[5]))
        print('# %d of %d unique hits' % (len(sel), len(hits)), file=sys.stderr)
        return

    byshape = collections.Counter(h[3] for h in hits)
    bylit = collections.Counter((h[3], h[4]) for h in hits)
    bymod = collections.Counter(h[0] for h in hits)
    rows = [h for h in hits if ' <- ' in h[5]]
    print('records read           %d' % raw)
    print('unique hits            %d' % len(hits))
    print('  row obligations      %d   (of which nolit %d)'
          % (len(rows), sum(1 for h in rows if h[4] == 'nolit')))
    print('  class constraints    %d   (of which nolit %d)'
          % (len(hits) - len(rows),
             sum(1 for h in hits if ' <- ' not in h[5] and h[4] == 'nolit')))
    print()
    print('%-16s %7s %7s %7s' % ('shape', 'hits', 'lit', 'nolit'))
    for s in sorted(byshape):
        print('%-16s %7d %7d %7d' % (s, byshape[s], bylit[(s, 'lit')], bylit[(s, 'nolit')]))
    print()
    print('%-28s %6s %6s' % ('module', 'hits', 'nolit'))
    nolitmod = collections.Counter(h[0] for h in hits if h[4] == 'nolit')
    for m, n in bymod.most_common():
        print('%-28s %6d %6d' % (m, n, nolitmod[m]))

main()
