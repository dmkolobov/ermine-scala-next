#!/usr/bin/env python3
"""Rank gates by catches per machine-hour.  Inputs (this directory):
  costs.tsv        gate, seconds per run (measured, see measurements.tsv), source
  executions.tsv   gate, executions 2026-08-29..09-17 (Claude-session Bash calls; see invocations.txt)
  catches.tsv      the catch ledger (REAL-DEFECT / GATE-DEFECT, sure|unsure)
  suites.tsv       suite, seconds in one sbt session, targeted testOnly executions
score = sure catches + 0.5 x unsure catches (REAL-DEFECT and GATE-DEFECT alike), 2026 window only.
machine-hours = executions x seconds per run / 3600 (targeted suite runs add 5 s of sbt start each;
a full core/test run charges every suite its own seconds)."""
import csv, os, sys
D = os.path.dirname(os.path.abspath(__file__))
rd = lambda f: list(csv.DictReader(open(os.path.join(D, f)), delimiter="\t"))
score, real, gated, unsure = {}, {}, {}, {}
for c in rd("catches.tsv"):
    if not c["date"].startswith("2026"):
        continue
    w = 1.0 if c["sure"] == "yes" else 0.5
    g = c["gate"]
    score[g] = score.get(g, 0) + w
    key = real if c["class"] == "REAL-DEFECT" else gated
    key[g] = key.get(g, 0) + 1
    if c["sure"] != "yes":
        unsure[g] = unsure.get(g, 0) + 1
costs = {r["gate"]: r for r in rd("costs.tsv")}
execs = {r["gate"]: int(r["executions"]) for r in rd("executions.tsv")}
full_runs = execs.get("core/test (full)", 0)
# suites run in parallel inside one full core/test: 675.6 s of wall clock (measurements.tsv) for the
# 1,330 s the suites take one after another, so a full run charges each suite 675.6/1330 of its seconds
suite_rows = rd("suites.tsv")
scale = 675.6 / sum(float(s["seconds"]) for s in suite_rows)
rows = []
for g, c in costs.items():
    secs = float(c["seconds"]); n = execs.get(g, 0)
    rows.append((g, secs, n, n * secs / 3600, c["source"]))
for s in suite_rows:
    secs = float(s["seconds"]); n = int(s["targeted"])
    hours = (full_runs * secs * scale + n * (secs + 5)) / 3600
    rows.append((s["suite"], secs, n, hours, "per-suite sbt session; + %d full runs" % full_runs))
out = []
for g, secs, n, hours, src in rows:
    sc = score.get(g, 0.0)
    rate = sc / hours if hours > 0 else (float("inf") if sc else 0.0)
    out.append((rate, sc, g, secs, n, hours, real.get(g, 0), gated.get(g, 0), unsure.get(g, 0)))
out.sort(key=lambda r: (-r[0], -r[1], r[5]))
print("| rank | gate | seconds/run | runs | machine-hours | real | gate-defect | of which unsure | score | catches/hour |")
print("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|")
for i, (rate, sc, g, secs, n, hours, r, gd, u) in enumerate(out, 1):
    print("| %d | %s | %.1f | %d | %.2f | %d | %d | %d | %.1f | %s |" % (
        i, g, secs, n, hours, r, gd, u, sc, "%.2f" % rate if rate != float("inf") else "n/a"))
