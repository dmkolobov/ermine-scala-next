#!/usr/bin/env python3
r"""Summarise a `-Dermine.rowTrace=<path>` log, and diff two of them.

    ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.rowTrace=/tmp/t-off.tsv" \
      bin/ermine core/examples/Sample.e < /dev/null
    tracker/tools/rowtrace-summary.py /tmp/t-off.tsv
    tracker/tools/rowtrace-summary.py /tmp/t-off.tsv /tmp/t-on.tsv     # side by side

RECORD FORMAT (RowTrace.scala):
    solve   site loc nIn nParts nSat nDerived concrete arities byRule
    concr   site loc var fields prov
    splice  site loc var nAbs con prov changed hlhs hdis hdup

WHAT IT REPORTS.

* the §7.9 population figures: solve calls, calls carrying a row constraint, input
  partitions, saturated partitions, derived partitions, and the per-rule breakdown.
  This is how you measure what `-Dermine.resGuard=true` costs and buys: `resolution`
  derivations and total saturated size are the two numbers that must move.

* DROPPED SPLICES.  HISTORICAL, AND NOT THE DEFECT -- read this before quoting it.
  This counter was written to a pre-proof framing of item 8b ("two partitions on one
  ambiguous variable, the second silently a no-op").  `Rowpartition.dropped_loses_nothing`
  then showed the dropped partition is HARMLESS: its hypotheses about the second partition
  are literally unused in the proof.  What breaks conservativity is `hlhs`, counted under
  NON-CONSERVATIVE below.  Measured over the example corpus the two disagree by two orders
  of magnitude -- 150 dropped against 21141 non-conservative out of 23410 splices -- so a
  zero here means very little.  Kept only because it is cheap and occasionally diagnostic.
  The original framing:  `Subst.reduce`'s second case
  folds over the SATURATED set and rewrites the INPUT constraint list; it never appends.
  So when the saturated set holds two partitions with the same left-hand side `v`, the
  first splice removes every right-hand occurrence of `v` and the second necessarily
  changes nothing -- and the fact it carried is retained NOWHERE in the emitted
  residual.  In the log that shape is: two or more `splice` records with the same
  (site, loc, var), the first with `changed=true` and a later one with `changed=false`.
  A nonzero count here is NOT the measured form of "the published signature is weaker
  than the constraints the user wrote" -- that is the NON-CONSERVATIVE count.

  A `changed=false` record with no preceding `changed=true` for the same variable is a
  different (harmless) thing: the variable did not occur in the emitted list at all.

* NON-CONSERVATIVE SPLICES, which is the sharper form of the same question and the one
  `-Dermine.spliceGuard=true` acts on.  `hlhs`/`hdis`/`hdup` are the three side conditions
  of `Rowpartition.splice_entails_iff`; when any fails, the splice is still SOUND but need
  not be CONSERVATIVE, and the published residual may stop entailing a consequence of the
  input (`Rowpartition.Splice.DroppedPartition.dropped_can_lose`).  `hlhs` is the one the
  known counterexample violates.

NOTE ON POPULATION.  Measure this over `core/examples`, not over a stdlib boot.  Ticket
§7.9: ZERO of 383 stdlib solve inputs carry a concrete label, against 39% in the examples.
The stdlib is not a weak corpus for this question, it is structurally incapable of
exhibiting it.
"""
import argparse
import collections
import sys


def load(path):
    solves, concrs, splices = [], [], []
    with open(path) as f:
        for raw in f:
            p = raw.rstrip("\n").split("\t")
            if not p:
                continue
            if p[0] == "solve" and len(p) >= 10:
                solves.append(dict(site=p[1], loc=p[2], nIn=int(p[3]), nParts=int(p[4]),
                                   nSat=int(p[5]), nDerived=int(p[6]), concrete=p[7],
                                   arities=p[8], byRule=p[9]))
            elif p[0] == "concr" and len(p) >= 6:
                concrs.append(dict(site=p[1], loc=p[2], var=p[3], fields=int(p[4]), prov=p[5]))
            elif p[0] == "splice" and len(p) >= 8:
                splices.append(dict(site=p[1], loc=p[2], var=p[3], nAbs=int(p[4]),
                                    con=int(p[5]), prov=p[6], changed=p[7] == "true",
                                    # the three conditions of Rowpartition.splice_entails_iff,
                                    # emitted from 2026-09-01 whether or not -Dermine.spliceGuard
                                    # is on; absent in older traces
                                    hlhs=(p[8] == "true") if len(p) > 8 else None,
                                    hdis=(p[9] == "true") if len(p) > 9 else None,
                                    hdup=(p[10] == "true") if len(p) > 10 else None))
    return solves, concrs, splices


def summarise(path):
    solves, concrs, splices = load(path)
    nontrivial = [s for s in solves if s["nParts"] > 0]
    grew = [s for s in nontrivial if s["nSat"] > s["nParts"]]

    byrule = collections.Counter()
    for s in solves:
        if s["byRule"] == "-":
            continue
        for kv in s["byRule"].split(","):
            k, _, n = kv.rpartition(":")
            byrule[k] += int(n)

    # ticket item 8b: a splice that changed nothing AFTER an effective splice on the
    # same variable at the same site is a partition whose information was dropped.
    seen_effective = set()
    dropped = []
    for r in splices:
        key = (r["site"], r["loc"], r["var"])
        if r["changed"]:
            seen_effective.add(key)
        elif key in seen_effective:
            dropped.append(r)

    spliced_prov = collections.Counter(r["prov"] for r in splices if r["changed"])
    # item 8b: a splice that is NOT conservative -- one of the three side conditions of
    # Rowpartition.splice_entails_iff fails, so the residual may lose a consequence of the
    # input.  `-Dermine.spliceGuard=true` skips exactly these.
    unsafe = [r for r in splices if r["hlhs"] is not None
              and not (r["hlhs"] and r["hdis"] and r["hdup"])]
    unsafe_eff = [r for r in unsafe if r["changed"]]
    no_hlhs = [r for r in splices if r["hlhs"] is False]

    return dict(
        path=path,
        solve_calls=len(solves),
        with_constraints=len(nontrivial),
        saturation_grew=len(grew),
        in_parts=sum(s["nParts"] for s in solves),
        sat_parts=sum(s["nSat"] for s in solves),
        derived=sum(s["nDerived"] for s in solves),
        byrule=byrule,
        splices=len(splices),
        splices_effective=sum(1 for r in splices if r["changed"]),
        splices_derived=sum(1 for r in splices if r["changed"] and r["prov"] != "INPUT"),
        splice_prov=spliced_prov,
        dropped=dropped,
        unsafe=unsafe,
        unsafe_eff=unsafe_eff,
        no_hlhs=no_hlhs,
        concrs=len(concrs),
    )


def show(a, b=None):
    for side in (a, b) if b else (a,):
        side["unsafe_n"] = len(side["unsafe"])
        side["unsafe_eff_n"] = len(side["unsafe_eff"])
        side["no_hlhs_n"] = len(side["no_hlhs"])

    def row(label, ka, kb=None):
        if b is None:
            print("  %-34s %10s" % (label, ka))
        else:
            mark = "" if str(ka) == str(kb) else "   <-- CHANGED"
            print("  %-34s %10s %10s%s" % (label, ka, kb, mark))

    print("== %s%s" % (a["path"], "" if b is None else "   vs   " + b["path"]))
    keys = [("solve calls", "solve_calls"),
            ("... carrying a row constraint", "with_constraints"),
            ("... where saturation grew", "saturation_grew"),
            ("input partitions", "in_parts"),
            ("saturated partitions", "sat_parts"),
            ("derived partitions", "derived"),
            ("concrete instantiations", "concrs"),
            ("splice firings", "splices"),
            ("... that changed the output", "splices_effective"),
            ("... splicing a DERIVED partition", "splices_derived"),
            ("DROPPED splices (item 8b)", None),
            ("NON-CONSERVATIVE splices (8b)", "unsafe_n"),
            ("... of those, effective", "unsafe_eff_n"),
            ("... failing hlhs specifically", "no_hlhs_n")]
    for label, k in keys:
        if k is None:
            row(label, len(a["dropped"]), None if b is None else len(b["dropped"]))
        else:
            row(label, a[k], None if b is None else b[k])

    rules = sorted(set(a["byrule"]) | (set(b["byrule"]) if b else set()))
    print("  derived by rule:")
    for r in rules:
        row("    " + r, a["byrule"][r], None if b is None else b["byrule"][r])

    provs = sorted(set(a["splice_prov"]) | (set(b["splice_prov"]) if b else set()))
    print("  effective splices by provenance:")
    for r in provs:
        row("    " + r, a["splice_prov"][r], None if b is None else b["splice_prov"][r])

    for side in (a, b) if b else (a,):
        if side["dropped"]:
            print("  dropped splices in %s (up to 20):" % side["path"])
            for r in side["dropped"][:20]:
                print("    %s  %s  var=%s prov=%s nAbs=%d con=%d"
                      % (r["site"], r["loc"], r["var"], r["prov"], r["nAbs"], r["con"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("other", nargs="?")
    args = ap.parse_args()
    a = summarise(args.trace)
    b = summarise(args.other) if args.other else None
    show(a, b)
    return 0


if __name__ == "__main__":
    sys.exit(main())
