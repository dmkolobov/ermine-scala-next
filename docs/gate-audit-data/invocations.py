#!/usr/bin/env python3
"""Count how many times each gate was EXECUTED in Claude sessions on this project (Bash tool calls,
main + subagents), 2026-08-29..2026-09-17.  A mention inside a heredoc, a grep pattern, an echo or a
cat of a brief is not an execution: heredoc bodies are removed and the tool must appear in command
position (line start, or after ; && || | ( ` $( nohup timeout N bash sh env VAR=...)."""
import json, re, sys, collections
rows = [json.loads(l) for l in open(sys.argv[1])]
POS = r"(?:^|[;&|(`]\s*|\$\(\s*|\bnohup\s+|\btimeout\s+(?:-\S+\s+)*\S+\s+|\b(?:bash|sh|env|time|exec)\s+(?:-\S+\s+)*|\b[A-Z_][A-Z0-9_]*=\S*\s+)"
GATES = {
  "compile":          POS + r"sbt\b[^\n]*core/compile",
  "core/test (full)": POS + r"sbt\b[^\n]*\bcore/test\b(?!Only|:|/)",
  "testOnly (any)":   POS + r"sbt\b[^\n]*core/testOnly",
  "TestLoopTrace":    POS + r"sbt\b[^\n]*testOnly[^\n]*TestLoopTrace",
  "corpus-run":       POS + r"(?:\S*/)?corpus-run\.sh\b",
  "repl-smoke":       POS + r"(?:\S*/)?repl-smoke\.sh\b",
  "lsp-smoke":        POS + r"(?:\S*/)?lsp-smoke\.sh\b",
  "looptrace-corpus": POS + r"(?:\S*/)?looptrace-corpus\.sh\b",
  "trace-ab":         POS + r"python3\s+(?:\S*/)?trace-ab\.py\b",
  "ei-diff":          POS + r"(?:\S*/)?ei-diff\.sh\b",
  "g1-validate":      POS + r"(?:\S*/)?g1-validate\.sh\b",
  "perf-bench":       POS + r"(?:\S*/)?perf-bench\.sh\b",
  "lake build":       POS + r"lake\s+build\b",
  "Audit.lean":       POS + r"lake\s+env\s+lean\s+(?:\S*/)?Audit\.lean",
  "sql-render":       POS + r"(?:\S*/)?sql-render\.sh\b",
  "keptdef/splitkey": POS + r"(?:\S*/)?(?:keptdef|splitkey)-sweep\.sh\b",
}
def strip_heredocs(cmd):
    return re.sub(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\s*(?=\n|$)", "<<HEREDOC\n", cmd, flags=re.S)
suite_re = re.compile(r"testOnly\s+([^'\"\n;&|]+)")
count = collections.Counter(); sessions = collections.defaultdict(set); suites = collections.Counter()
for r in rows:
    ts = r.get("ts") or ""
    if not ("2026-08-29" <= ts[:10] <= "2026-09-17"): continue
    c = strip_heredocs(r["cmd"])
    for g, p in GATES.items():
        n = len(re.findall(p, c, re.M))
        if n:
            count[g] += n; sessions[g].add(r["file"].split("/")[0])
    for line in c.split("\n"):
        if re.search(POS + r"sbt\b", line):
            for m in re.finditer(r"core/testOnly\s+((?:[*\w.]+\s*)+)", line):
                for pat in m.group(1).split():
                    suites[pat.strip("*").split(".")[-1]] += 1
for g in GATES:
    print("%-18s %5d executions in %2d sessions" % (g, count[g], len(sessions[g])))
print("\ntestOnly targets (suite name fragments):")
for k, v in suites.most_common():
    if k: print("  %-28s %d" % (k, v))
