#!/usr/bin/env python3
"""DB stage 2e: check every `file:line` cite in tracker/db/DOGFOOD.md and in checklist
group F against the quote it backs.

A cite is a code span `path:N` or `path:N-M`, where the path has a '/' or starts with
scripts/. Its QUOTE is the nearest code span BEFORE it, with at most 40 characters and no
backtick between the two (so "`quote` (`path:N`)" and "`quote`,\n  `path:N`" both pair).
The cite passes when the quote occurs in the cited line, or in the joined range.

usage: dogfood-citecheck.py [--fill] [WORKTREE]
  --fill  rewrite `path:?` cites to the ONE line that holds the quote (refuses when the
          quote is on no line or on several lines); then check as usual.
exit: 0 every cite has a quote and every quote is on its line; 1 otherwise; 2 usage."""
import pathlib, re, sys

args = [a for a in sys.argv[1:] if a != "--fill"]
FILL = "--fill" in sys.argv[1:]
if len(args) > 1:
    print(__doc__); sys.exit(2)
WT = pathlib.Path(args[0] if args else pathlib.Path(__file__).resolve().parents[2]).resolve()
DOCS = [("tracker/db/DOGFOOD.md", None, None),
        ("tracker/WP-7-MANUAL-CHECKLIST.md", "## Group F — the database", "## Group D — the honest leftovers")]

SPAN = re.compile(r"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)")
CITE = re.compile(r"^(?P<file>(?:[A-Za-z0-9_.@-]+/)+[A-Za-z0-9_.@-]+\.[A-Za-z0-9]+|scripts/[A-Za-z0-9_.-]+):(?P<a>\d+|\?)(?:-(?P<b>\d+))?$")

def spans(text):
    for m in SPAN.finditer(text):
        body = m.group(2)
        if len(m.group(1)) > 1 and body.startswith(" ") and body.endswith(" ") and body.strip():
            body = body[1:-1]
        yield m.start(), m.end(), body

cache = {}
def lines_of(f):
    if f not in cache:
        p = WT / f
        cache[f] = p.read_bytes().decode("utf-8", "replace").split("\n") if p.is_file() else None
    return cache[f]

total = bad = 0
for doc, start, end in DOCS:
    path = WT / doc
    text = path.read_text(encoding="utf-8")
    if start and start not in text:
        print("NO-SECTION", doc, "|", start); bad += 1; continue
    lo = text.index(start) if start else 0
    hi = text.index(end, lo) if end else len(text)
    sec = text[lo:hi]
    found = list(spans(sec))
    edits = []
    for i, (s, e, body) in enumerate(found):
        m = CITE.match(body)
        if not m:
            continue
        total += 1
        f, a, b = m.group("file"), m.group("a"), m.group("b")
        quote = None
        if i > 0:
            ps, pe, pbody = found[i - 1]
            gap = sec[pe:s]
            if len(gap) <= 40 and "`" not in gap and not CITE.match(pbody):
                quote = pbody
        where = f"{doc}: {body}"
        if quote is None:
            print("NO-QUOTE", where); bad += 1; continue
        ls = lines_of(f)
        if ls is None:
            print("NO-FILE ", where); bad += 1; continue
        if a == "?":
            hits = [n + 1 for n, l in enumerate(ls) if quote in l]
            if FILL and len(hits) == 1:
                edits.append((s, e, f"`{f}:{hits[0]}`"))
                print("FILLED  ", f"{f}:{hits[0]}", "|", quote[:70]); continue
            print("UNFILLED", where, "| hits", hits[:5], "|", quote[:70]); bad += 1; continue
        a = int(a); b2 = int(b) if b else a
        seg = "\n".join(ls[a - 1:b2]) if 1 <= a <= b2 <= len(ls) else ""
        if quote in seg:
            print("OK      ", f"{f}:{a}" + (f"-{b2}" if b else ""), "|", quote[:70])
        else:
            now = [n + 1 for n, l in enumerate(ls) if quote in l]
            print("MISS    ", f"{f}:{a}" + (f"-{b2}" if b else ""), "| now at", now[:5], "|", quote[:70]); bad += 1
    if edits:
        for s, e, rep in sorted(edits, reverse=True):
            sec = sec[:s] + rep + sec[e:]
        path.write_text(text[:lo] + sec + text[hi:], encoding="utf-8")
print(f"{total} citations, {total - bad} OK, {bad} bad")
sys.exit(1 if bad else 0)
