#!/usr/bin/env python3
"""Bucket JFR execution samples by compiler phase and by hot leaf (P2).

   tracker/tools/jfr-buckets.py /tmp/perf-bench/batch.jfr
   tracker/tools/jfr-buckets.py /tmp/perf-bench/editor.jfr --top 25

Takes a .jfr recording (it shells out to `jfr print` itself) or an already
dumped text file.  Prints three tables: thread distribution, PHASE attribution,
and LEAF attribution.  Percentages are of total execution samples.

WHY THE ATTRIBUTION WORKS THE WAY IT DOES.  The phases NEST -- a session drives
a read, a read drives the parser, and inference runs after both -- so a sample's
phase is the INNERMOST frame that matches a phase rule, not the outermost.
Attributing to the outermost match would bucket every sample in the process as
"session", since Console.main is at the bottom of every batch stack.

Shared utility classes (Type, Kind, Vars, Name, Pretty) are deliberately NOT
phase rules.  They are called from several phases, so making them one would
steal samples from whichever phase actually drove the work.  They show up in
the LEAF table instead, which is where "what is hot" belongs.

Two JFR facts worth keeping (both are in tracker/TICKET-perf-type-inference.md
because both cost a wasted measurement once): `jfr print` truncates stacks to
FIVE frames unless you pass --stack-depth, and the recording itself needs
-XX:FlightRecorderOptions=stackdepth=512 or scalaz's trampolines blow past the
64-frame default.  perf-bench.sh's PERF_JVM_PROPS hook is how you pass those.
"""
import argparse
import collections
import os
import pathlib
import re
import subprocess
import sys

# Innermost match wins.  Order matters only where one rule's classes sit inside
# another's package (extents before the general surface/parsing rule).
PHASE_RULES = [
    # Constraint solving is split OUT of inference deliberately: folded in, it
    # is invisible, and "how much of inference is row-constraint solving" is a
    # standing question about this language.  Ordered first so a stack that
    # reaches the solver is attributed to it rather than to its Subst caller.
    ("constraint solving", r"ermine\.Constraints\$|ermine\.Subst\$NormalPart"),
    ("inference",    r"ermine\.Subst\$|ermine\.session\.TolerantCheck\$"),
    ("lower",        r"ermine\.rename\.(Lower|TyLower)\$"),
    ("reassoc",      r"ermine\.rename\.Reassoc\$"),
    ("rename",       r"ermine\.rename\.Renamer\$"),
    ("extent scan",  r"ermine\.surface\.StatementExtents\$"),
    ("parse",        r"ermine\.parsing\.|ermine\.surface\.|scalaparsers\."),
    ("read driver",  r"ermine\.rename\.(NewPipeline|ModuleScope)\$"),
    ("eval",         r"ermine\.Runtime|ermine\.Eval"),
    ("session/lsp",  r"ermine\.session\.|ermine\.lsp\."),
]
PHASES = [(name, re.compile(pat)) for name, pat in PHASE_RULES]
OURS = re.compile(r"^(com\.clarifi\.reporting\.ermine|scalaparsers)")

# Families group the LEAF frames into the units an optimization would actually
# attack, so a roadmap item can quote one number instead of adding up a table.
# Matched against `pkg.Class.method`, first match wins.
# NOTE the leading `\.` on the Vars rule.  Without it, `Vars\$\$anon` also
# matches HasTypeVars$$anon$6.sub and HasKindVars$$anon$3.sub as SUBSTRINGS,
# filing substitution samples under free-variable collection -- which inflated
# ftv from 34% to 45% the first time this table was printed.
FAMILY_RULES = [
    ("free-variable collection", r"\.(vars|allVars)$|\.Vars\$\$anon\$\d+\."),
    ("substitution application", r"\.(sub|subst)$|\.replaceCons$"),
    ("parser failure merging",   r"^scalaparsers\.Fail"),
    ("parser trampoline",        r"^scalaparsers\."),
    ("extent scan",              r"\.StatementExtents\$\."),
    # Split so the solver's own cost is legible when it IS hot: on an
    # adversarial input it is 98% of samples, and reading that as "other"
    # would waste the measurement.
    ("row-constraint queue",     r"\.Constraints\$(Q|RHS)"),
    ("row-constraint rules",     r"\.Constraints\$"),
    ("grammar (ermine parsers)", r"\.ermine\.(parsing|surface)\."),
]
FAMILIES = [(name, re.compile(pat)) for name, pat in FAMILY_RULES]


def samples(path):
    """Yield (thread, thread_id, [frames innermost-first]) per execution sample."""
    text = pathlib.Path(path).read_text(errors="replace")
    cur = thread = tid = None
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("jdk.ExecutionSample"):
            cur, thread, tid = [], None, None
        elif cur is None:
            continue
        elif s.startswith("sampledThread"):
            thread = s.split('"')[1] if '"' in s else "?"
            m = re.search(r"javaThreadId = (\d+)", s)
            tid = m.group(1) if m else "?"
        elif s == "}":
            if cur:
                yield thread, tid, cur
            cur = None
        elif s.startswith(("startTime", "state", "stackTrace")):
            continue
        elif s and s != "]":
            cur.append(s)


def frame_name(f):
    """`pkg.Class.method(Args) line: 12` -> `pkg.Class.method`."""
    return f.split("(")[0].strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("recording", help=".jfr recording or a dumped text file")
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--label", default=None)
    a = ap.parse_args()

    path = a.recording
    if path.endswith(".jfr"):
        jh = os.environ.get("JAVA_HOME",
                            os.path.expanduser("~/.local/ermine-toolchain/jdk-21.0.12.1+1"))
        out = path + ".samples.txt"
        with open(out, "wb") as fh:
            rc = subprocess.call([jh + "/bin/jfr", "print", "--stack-depth", "500",
                                  "--events", "jdk.ExecutionSample", path], stdout=fh)
        if rc != 0:
            print("FAIL: jfr print exited %d" % rc, file=sys.stderr)
            return 1
        path = out

    rows = list(samples(path))
    n = len(rows)
    if n == 0:
        print("FAIL: no jdk.ExecutionSample events in " + path, file=sys.stderr)
        return 1

    print("== %s: %d execution samples ==" % (a.label or a.recording, n))

    threads = collections.Counter("%s#%s" % (t, i) for t, i, _ in rows)
    print("\n-- threads --")
    for k, v in threads.most_common(8):
        print("  %5.1f%%  %6d  %s" % (100.0 * v / n, v, k))
    if len(threads) > 8:
        print("  %5.1f%%  %6d  (%d further threads)"
              % (100.0 * sum(v for _, v in threads.most_common()[8:]) / n,
                 sum(v for _, v in threads.most_common()[8:]), len(threads) - 8))

    phase = collections.Counter()
    for _, _, frames in rows:
        for f in frames:                      # innermost first
            hit = next((name for name, rx in PHASES if rx.search(f)), None)
            if hit:
                phase[hit] += 1
                break
        else:
            phase["<no ermine frame>"] += 1
    print("\n-- phase (innermost matching frame) --")
    for k, v in phase.most_common():
        print("  %5.1f%%  %6d  %s" % (100.0 * v / n, v, k))

    leaf = collections.Counter()
    for _, _, frames in rows:
        for f in frames:
            if OURS.match(f):
                leaf[frame_name(f)] += 1
                break
        else:
            leaf["<no ermine frame>"] += 1
    print("\n-- hot leaves (innermost ermine/scalaparsers frame) --")
    for k, v in leaf.most_common(a.top):
        print("  %5.1f%%  %6d  %s" % (100.0 * v / n, v, k))

    family = collections.Counter()
    for name, v in leaf.items():
        hit = next((f for f, rx in FAMILIES if rx.search(name)), "other")
        family[hit] += v
    print("\n-- leaf families (what an optimization would attack) --")
    for k, v in family.most_common():
        print("  %5.1f%%  %6d  %s" % (100.0 * v / n, v, k))
    return 0


if __name__ == "__main__":
    sys.exit(main())
