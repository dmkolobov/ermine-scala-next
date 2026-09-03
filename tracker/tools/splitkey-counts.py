#!/usr/bin/env python3
r"""Count `splitConcrete`'s three branches in a `-Dermine.rowTrace` log.

    tracker/tools/splitkey-counts.py trace.tsv [--filter core/examples] [--tag NAME]

Instrument for `tracker/satterm/KEYED-SPLIT-STAGE2.md` (Stage 2 of the keyed split guard).
Segmentation is `keptdef-mints.py`'s: a segment is every record up to a `solve` record, and
belongs to the module iff the solve's `loc` contains `--filter`.  Requires
`-Dermine.loadInSeries=true`, or the records of concurrent solves interleave.

`splitConcrete` emits, per firing:

    syntactic reuse   ONE  record   `SplitConcrete: v <- (u, con)`      (con nonempty)
    MINT              TWO  records  `SplitConcrete: u <- (abs,)`        (con EMPTY)  +
                                    `SplitConcrete: v <- (u, con)`
    keyed reuse       ONE  record   `SplitKeyed:    w <- (abs,)`        (-Dermine.splitKey only)

so, over a segment,  mints = #(SplitConcrete with empty con),
                     syntactic reuses = #(SplitConcrete with nonempty con) - mints,
                     keyed reuses = #SplitKeyed.
Columns `*_new` count only records flagged `new` (the conclusion was not already present).
"""
import argparse, re, sys

PART = re.compile(r'^(?:([A-Za-z]+): )?\^[a-z()]+(\d+) <- \((.*)\)$')

def parse_part(s):
    m = PART.match(s.strip())
    if not m:
        return None
    prov, lhs, body = m.group(1), int(m.group(2)), m.group(3)
    absb, con = body.split(',', 1) if ',' in body else (body, '')
    return prov, lhs, absb.strip(), con.strip()

def segments(path):
    buf = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            rec = line.rstrip('\n').split('\t')
            if not rec or not rec[0]:
                continue
            buf.append(rec)
            if rec[0] == 'solve':
                yield (rec[2] if len(rec) > 2 else '?'), buf
                buf = []
    if buf:
        yield '?(unterminated)', buf

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('trace'); ap.add_argument('--filter', default=None)
    ap.add_argument('--tag', default=None)
    a = ap.parse_args()
    t = dict(solves=0, mint=0, mint_new=0, synreuse=0, synreuse_new=0,
             keyed=0, keyed_new=0, sc_nonbare=0, sc_nonbare_new=0, learn=0)
    locs = set()
    for loc, recs in segments(a.trace):
        if a.filter and a.filter not in loc:
            continue
        t['solves'] += 1
        locs.add(loc)
        for r in recs:
            if r[0] != 'learn' or len(r) < 4:
                continue
            t['learn'] += 1
            p = parse_part(r[3])
            if not p:
                continue
            prov, _, _, con = p
            new = (r[2] == 'new')
            if prov == 'SplitKeyed':
                t['keyed'] += 1; t['keyed_new'] += new
            elif prov == 'SplitConcrete':
                if con == '':
                    t['mint'] += 1; t['mint_new'] += new
                else:
                    t['sc_nonbare'] += 1; t['sc_nonbare_new'] += new
    t['synreuse'] = t['sc_nonbare'] - t['mint']
    t['synreuse_new'] = t['sc_nonbare_new'] - t['mint_new']
    tag = a.tag or a.trace
    print('%s\tsolves=%d\tlearn=%d\tmint=%d\tmint_new=%d\tsynreuse=%d\tkeyed=%d\tkeyed_new=%d\tlocs=%d'
          % (tag, t['solves'], t['learn'], t['mint'], t['mint_new'], t['synreuse'],
             t['keyed'], t['keyed_new'], len(locs)))

main()
