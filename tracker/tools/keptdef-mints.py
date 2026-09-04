#!/usr/bin/env python3
r"""Do the definitions `destructiveSub` now KEEPS ever reach `splitConcrete` and mint?

Instrument for tracker/PROMPT-default-termination.md, Question 2.  Since a4b62c0
`destructiveSub` keeps, when a variable `u` is concretised, every definition of `u` with two
or more abstract parts ("keepDefs").  `TICKET-substitution-gap.md` §7 says the kept
definitions "re-enable only the reuse/fold branch of commonSubexpression and substitution,
which mint nothing".  `Rowpartition/KeepInert.lean` shows that is false for a kept
definition with a NONEMPTY concrete part: `u <- (x, y, (|K|))` is a `splitConcrete`
premise, and if `{x, y}` is unnamed it MINTS.  This script measures how often that shape
actually occurs in the compiler.

Reads a `-Dermine.rowTrace=<path>` log written with `-Dermine.loadInSeries=true` (so the
records of one `solve` are contiguous) and reports, per solve segment:

  * concretisations: `step ... concrete` records (a dequeue of `u <- (|F|)`, i.e. `makeConcrete`)
  * kept-definition dequeues: a later `step ... learn` record whose partition is
    `u <- (abs, con)` with `u` already concretised in this solve and |abs| >= 2.  These are
    split into STRICT -- the partition was an input (`inpart` record) or was learnt (`learn
    new`) BEFORE the concretisation, i.e. exactly what the OLD `destructiveSub` deleted from
    `incm` and the new one re-enqueues -- and DERIVED -- learnt after it, from a kept
    definition by substitution or CSE (it exists only because the definition was kept)
  * of those, how many carry a nonempty concrete part (the `splitConcrete` premise shape)
  * of those, how many are followed by a `learn ... new SplitConcrete: n <- (abs,)` -- a MINT
    (a fresh bare name for the group) -- or by a `SplitConcrete: u <- (n, con)` alone -- a
    syntactic REUSE -- or (added 2026-09-03 for Stage 3, `tracker/satterm/KEYED-LOOP-STAGE3.md`)
    by a `SplitKeyed: w <- (abs,)` -- a KEYED reuse, the branch `-Dermine.splitKey` opens,
    which is DEFAULT ON since commit 1e6f52b.  Before that flag every keyed reuse showed up
    in the `no splitConcrete derivation` bucket, so the three branch counts now add up.
    ADDED 2026-09-03 for Stage 5 (`tracker/satterm/KEYED-ROW-STAGE5.md`): a fourth reuse
    bucket, `SplitRow: w <- (abs,)`, the CONCRETE-ROW reuse `-Dermine.splitRow` opens.  It
    emits exactly the shape `SplitKeyed` does, so it is recognised the same way and, with
    the flag off, is simply never seen.  Also reported, per solve segment and independently
    of the kept-definition analysis, are the WHOLE-TRACE totals of the four split branches
    and of `resolution`'s two reuse branches, so one number per configuration says how often
    each new branch fired: `SplitConcrete` bare (a MINT), `SplitConcrete` non-bare,
    `SplitKeyed`, `SplitRow`, `Resolution`, `ResolutionRow`.

Usage:
    tracker/tools/keptdef-mints.py trace.tsv [--filter SUBSTR] [--show N]
      --filter  only count solve segments whose `loc` contains SUBSTR (e.g. `core/examples`
                or `modules/` for the stdlib)
      --show    print the first N kept-definition dequeues with their learn records
"""
import argparse
import re
import sys

VAR = re.compile(r'\^[a-z()]+(\d+)')          # ^free123, ^ambiguous(free)45
PART = re.compile(r'^(?:([A-Za-z]+): )?\^[a-z()]+(\d+) <- \((.*)\)$')


def parse_part(s):
    """'Prov: ^free1 <- (^free2 ^free3,l1 l2)' -> (prov, lhs, abs_ids(list), con(str))"""
    m = PART.match(s.strip())
    if not m:
        return None
    prov, lhs, body = m.group(1), int(m.group(2)), m.group(3)
    # body is a Scala tuple toString: "<abs vars joined by space>,<labels joined by space>"
    if ',' in body:
        absb, con = body.split(',', 1)
    else:
        absb, con = body, ''
    abs_ids = [int(x) for x in VAR.findall(absb)]
    return prov, lhs, abs_ids, con.strip()


def segments(path):
    """Yield (loc, records) per solve: every record up to and including its `solve` line."""
    buf = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            rec = line.rstrip('\n').split('\t')
            if not rec or not rec[0]:
                continue
            buf.append(rec)
            if rec[0] == 'solve':
                yield rec[2] if len(rec) > 2 else '?', buf
                buf = []
    if buf:
        yield '?(unterminated)', buf


INPART_VAR = re.compile(r'\^(\d+)')


def key_of_part(part):
    prov, lhs, abs_ids, con = part
    return (lhs, frozenset(abs_ids), frozenset(con.split()))


def key_of_inpart(rec):
    """inpart\tsite\tloc\ti\tprov\tlhs\tabs\tcon  (Subst.scala's `sp`): abs entries look like
    name^id, con is a comma-separated sorted label list."""
    if len(rec) < 8:
        return None
    lhs = INPART_VAR.search(rec[5]); abs_ids = INPART_VAR.findall(rec[6])
    if not lhs:
        return None
    con = frozenset(x for x in rec[7].split(',') if x)
    return (int(lhs.group(1)), frozenset(int(x) for x in abs_ids), con)


def analyse(path, flt=None, show=0):
    tot = dict(solves=0, concrete=0, kept=0, strict=0, derived=0, kept_conc=0, strict_conc=0,
               mint=0, strict_mint=0, reuse=0, keyed=0, row=0, neither=0,
               all_splitmint=0, all_splitreuse=0, all_keyed=0, all_row=0,
               all_res=0, all_resrow=0)
    mints_at = {}
    shown = 0
    for loc, recs in segments(path):
        if flt and flt not in loc:
            continue
        tot['solves'] += 1
        # whole-segment branch tallies, independent of the kept-definition analysis
        for r in recs:
            if r[0] == 'learn' and len(r) >= 4:
                lp = parse_part(r[3])
                if not lp:
                    continue
                prov, _lhs, _abs, con = lp
                if prov == 'SplitConcrete':
                    tot['all_splitmint' if con == '' else 'all_splitreuse'] += 1
                elif prov == 'SplitKeyed':
                    tot['all_keyed'] += 1
                elif prov == 'SplitRow':
                    tot['all_row'] += 1
                elif prov == 'Resolution':
                    tot['all_res'] += 1
                elif prov == 'ResolutionRow':
                    tot['all_resrow'] += 1
        inputs = set(k for k in (key_of_inpart(r) for r in recs if r[0] == 'inpart') if k)
        learned_before = set()          # keys learnt (`learn new`) so far in this segment
        concretised = {}                # u -> set of keys of u's definitions known at concretisation
        i = 0
        while i < len(recs):
            r = recs[i]
            if r[0] == 'learn' and len(r) >= 4 and r[2] == 'new':
                lp = parse_part(r[3])
                if lp:
                    learned_before.add(key_of_part(lp))
            if r[0] == 'step' and len(r) >= 4:
                branch, part = r[2], parse_part(r[3])
                if branch == 'concrete' and part:
                    u = part[1]
                    if u not in concretised:
                        concretised[u] = set(k for k in inputs | learned_before if k[0] == u)
                    tot['concrete'] += 1
                elif branch == 'learn' and part and part[1] in concretised and len(part[2]) >= 2:
                    tot['kept'] += 1
                    strict = key_of_part(part) in concretised[part[1]]
                    tot['strict' if strict else 'derived'] += 1
                    learns = []
                    j = i + 1
                    while j < len(recs) and recs[j][0] == 'learn':
                        if len(recs[j]) >= 4 and recs[j][2] == 'new':
                            lp = parse_part(recs[j][3])
                            if lp:
                                learned_before.add(key_of_part(lp))
                        learns.append(recs[j]); j += 1
                    has_conc = part[3] != ''
                    if has_conc:
                        tot['kept_conc'] += 1
                        if strict:
                            tot['strict_conc'] += 1
                        kind = 'neither'
                        for l in learns:
                            lp = parse_part(l[3]) if len(l) >= 4 else None
                            if lp and lp[0] == 'SplitKeyed' and lp[3] == '' \
                                    and set(lp[2]) == set(part[2]):
                                kind = 'keyed'; break
                            if lp and lp[0] == 'SplitRow' and lp[3] == '' \
                                    and set(lp[2]) == set(part[2]):
                                kind = 'row'; break
                            if lp and lp[0] == 'SplitConcrete':
                                if lp[3] == '' and set(lp[2]) == set(part[2]) and l[2] == 'new':
                                    kind = 'mint'; break
                                if lp[1] == part[1]:
                                    kind = 'reuse'
                        tot[kind] += 1
                        if kind == 'mint':
                            if strict:
                                tot['strict_mint'] += 1
                            mints_at[loc] = mints_at.get(loc, 0) + 1
                    if show and shown < show:
                        shown += 1
                        print(f"--- kept-definition dequeue ({'STRICT' if strict else 'derived'}) in {loc}: {r[3]}  (conc={'yes' if has_conc else 'no'})")
                        for l in learns:
                            print("      " + "\t".join(l[2:]))
                    i = j
                    continue
            i += 1
    return tot, mints_at


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('trace')
    ap.add_argument('--filter', default=None)
    ap.add_argument('--show', type=int, default=0)
    a = ap.parse_args()
    tot, mints_at = analyse(a.trace, a.filter, a.show)
    print(f"solve segments{' matching ' + repr(a.filter) if a.filter else ''}: {tot['solves']}")
    print(f"  makeConcrete steps (a variable made concrete):            {tot['concrete']}")
    print(f"  kept-definition dequeues (|abs|>=2, lhs already concrete): {tot['kept']}  (strict {tot['strict']}, derived-from-kept {tot['derived']})")
    print(f"    with a NONEMPTY concrete part (splitConcrete premise):   {tot['kept_conc']}  (strict {tot['strict_conc']})")
    print(f"      -> splitConcrete MINTED a fresh name:                   {tot['mint']}  (strict {tot['strict_mint']})")
    print(f"      -> splitConcrete REUSED an existing name:               {tot['reuse']}")
    print(f"      -> splitConcrete KEYED-REUSED an existing name:          {tot['keyed']}")
    print(f"      -> splitConcrete ROW-REUSED an existing name:            {tot['row']}")
    print(f"      -> no splitConcrete derivation:                         {tot['neither']}")
    print(f"  whole-trace branch tallies (learn records, same segments):")
    print(f"      SplitConcrete bare (a MINT) / non-bare:                  {tot['all_splitmint']} / {tot['all_splitreuse']}")
    print(f"      SplitKeyed / SplitRow:                                   {tot['all_keyed']} / {tot['all_row']}")
    print(f"      Resolution / ResolutionRow:                              {tot['all_res']} / {tot['all_resrow']}")
    if mints_at:
        print("  mints by solve location:")
        for k, v in sorted(mints_at.items(), key=lambda kv: -kv[1]):
            print(f"    {v:4d}  {k}")


if __name__ == '__main__':
    main()
