#!/usr/bin/env python3
"""analyze.py <trace.tsv> <module-file-basename> [--per-solve] [--json]

Segments a -Dermine.rowTrace log by `solve` record (a segment = every step/learn/in/ex/inpart/sat
record since the previous `solve`), keeps the segments whose solve `loc` names the module file,
and reports:
  solves          number of solve records for the module (any), and those with nParts>0
  inparts/sat/derived   sums of the solve record's nParts, nSat, nDerived (surviving, post-expand)
  byRule          sums of the solve record's byRule field (surviving derived partitions by rule)
  learn firings   `learn` records by provenance, new vs seen (derivations actually fired)
  steps           `step` records (dequeues of incorporateAll), by branch
  MINTS           fresh ids: an id first appearing in a `learn` record (not in in/ex/inpart records
                  and not in any earlier step/learn record of the segment), attributed to the
                  provenance of the record that introduced it
  ids in sat      distinct variable ids in the module's `sat` records; and those not among inputs
  per-solve max   largest nSat and largest mint count, with their loc
"""
import re, sys, json, collections

ID = re.compile(r'\^[a-z()]*(\d+)')
PROV = re.compile(r'^([A-Za-z]+): ')

def segments(path):
    buf = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            p = line.rstrip('\n').split('\t')
            if not p or not p[0]:
                continue
            buf.append(p)
            if p[0] == 'solve':
                yield buf
                buf = []
    if buf:
        yield buf  # trailing, no solve record (a timeout mid-solve)

def analyse(path, modname, per_solve=False):
    tot = collections.Counter()
    byrule = collections.Counter()
    learn_new = collections.Counter(); learn_seen = collections.Counter()
    steps = collections.Counter()
    mints = collections.Counter()
    sat_ids = set(); sat_new_ids = set()
    maxsat = (0, None); maxmint = (0, None); maxsteps = (0, None)
    rows = []
    tail = None
    for seg in segments(path):
        solve = seg[-1] if seg[-1][0] == 'solve' else None
        if solve is None:
            # trailing partial segment (timeout): only count if it belongs to the module
            # -- we cannot know its loc; keep it aside and report its size
            tail = seg
            continue
        loc = solve[2]
        if modname not in loc:
            continue
        nIn, nParts, nSat, nDer = int(solve[3]), int(solve[4]), int(solve[5]), int(solve[6])
        tot['solves'] += 1
        if nParts > 0: tot['solves_with_parts'] += 1
        tot['nIn'] += nIn; tot['nParts'] += nParts; tot['nSat'] += nSat; tot['nDerived'] += nDer
        br = collections.Counter()
        if solve[9] != '-':
            for kv in solve[9].split(','):
                k, _, n = kv.rpartition(':'); br[k] += int(n)
        byrule.update(br)
        # inputs
        seen = set()
        for p in seg:
            t = p[0]
            if t.startswith('inpart') or t.startswith('ex') or t.startswith('in'):
                for x in p[1:]:
                    seen.update(ID.findall(x))
        segmints = collections.Counter(); nsteps = 0
        # `learnPartitions` returns a Set that is logged in arbitrary order, so within one batch of
        # consecutive `learn` records a fresh id can be printed in a CSE/Substitution record before the
        # Resolution/SplitConcrete record that minted it.  Re-order each batch: minting provenances first.
        PRIO = {'SplitConcrete': 0, 'Resolution': 0, 'CommonSubexpressionMint': 0}
        ordered = []; batch = []
        def flush():
            batch.sort(key=lambda p: PRIO.get((PROV.match(p[3]).group(1) if PROV.match(p[3]) else ''), 1))
            ordered.extend(batch); batch.clear()
        for p in seg:
            if p[0] == 'learn': batch.append(p)
            else: flush(); ordered.append(p)
        flush()
        for p in ordered:
            t = p[0]
            if t == 'step':
                nsteps += 1
                steps[p[2].split(':')[0]] += 1
                seen.update(ID.findall(p[3]))
            elif t == 'learn':
                m = PROV.match(p[3]); prov = m.group(1) if m else 'INPUT'
                (learn_new if p[2] == 'new' else learn_seen)[prov] += 1
                ids = set(ID.findall(p[3]))
                fresh = ids - seen
                if fresh:
                    segmints[prov] += len(fresh)
                seen |= ids
            elif t.startswith('sat'):
                ids = set(ID.findall(p[5])) | set(ID.findall(p[6]))
                sat_ids |= ids
        # inputs of this segment for sat_new
        inp = set()
        for p in seg:
            if p[0].startswith('inpart') or p[0].startswith('ex') or p[0].startswith('in'):
                for x in p[1:]: inp.update(ID.findall(x))
        for p in seg:
            if p[0].startswith('sat'):
                ids = set(ID.findall(p[5])) | set(ID.findall(p[6]))
                sat_new_ids |= (ids - inp)
        mints.update(segmints)
        nm = sum(segmints.values())
        tot['steps'] += nsteps
        if nSat > maxsat[0]: maxsat = (nSat, loc)
        if nm > maxmint[0]: maxmint = (nm, loc)
        if nsteps > maxsteps[0]: maxsteps = (nsteps, loc)
        rows.append(dict(site=solve[1], loc=loc, nIn=nIn, nParts=nParts, nSat=nSat, nDerived=nDer,
                         byRule=dict(br), steps=nsteps, mints=dict(segmints)))
    out = dict(module=modname, totals=dict(tot), byRule=dict(byrule), learn_new=dict(learn_new),
               learn_seen=dict(learn_seen), steps_by_branch=dict(steps), mints=dict(mints),
               mints_total=sum(mints.values()), sat_ids=len(sat_ids), sat_new_ids=len(sat_new_ids),
               max_nSat=maxsat, max_mints=maxmint, max_steps=maxsteps)
    if tail:
        tc = collections.Counter(p[0] if p[0] in ('step','learn') else p[0].rstrip('0123456789') for p in tail)
        tl = collections.Counter(); tm = collections.Counter(); seen=set()
        for p in tail:
            if p[0]=='learn':
                m = PROV.match(p[3]); prov = m.group(1) if m else 'INPUT'
                tl[prov] += 1
                ids=set(ID.findall(p[3])); fr=ids-seen
                if fr: tm[prov]+=len(fr)
                seen|=ids
            elif p[0]=='step':
                seen.update(ID.findall(p[3]))
        out['tail_partial_segment'] = dict(records=dict(tc), learn_by_prov=dict(tl), fresh_ids_by_prov_approx=dict(tm))
    if per_solve:
        out['per_solve'] = rows
    return out

if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    r = analyse(args[0], args[1], '--per-solve' in sys.argv)
    if '--json' in sys.argv:
        print(json.dumps(r, indent=1))
    else:
        t = r['totals']
        print("module %s: solves=%d (with parts %d) nParts=%d nSat=%d nDerived=%d steps=%d" % (
            r['module'], t.get('solves',0), t.get('solves_with_parts',0), t.get('nParts',0), t.get('nSat',0), t.get('nDerived',0), t.get('steps',0)))
        print("  byRule(surviving): %s" % r['byRule'])
        print("  learn new: %s" % r['learn_new']); print("  learn seen: %s" % r['learn_seen'])
        print("  steps by branch: %s" % r['steps_by_branch'])
        print("  MINTS (fresh ids in learn): %s total=%d" % (r['mints'], r['mints_total']))
        print("  distinct ids in sat: %d, of which not inputs: %d" % (r['sat_ids'], r['sat_new_ids']))
        print("  max per solve: nSat=%s mints=%s steps=%s" % (r['max_nSat'], r['max_mints'], r['max_steps']))
        if 'tail_partial_segment' in r: print("  TAIL (unterminated segment): %s" % r['tail_partial_segment'])
        if '--per-solve' in sys.argv:
            for row in r['per_solve']:
                if row['nParts'] > 0: print("   ", row)
