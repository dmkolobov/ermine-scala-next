#!/usr/bin/env python3
"""Mutation operators for scripts/mutate-and-verify.sh.

    scripts/mutate.py candidates --gate G --seed S [--classes obo,swap,guard,mapord] GLOB...
        one JSON object per line: {"id","gate","class","file","line","before","after"},
        shuffled deterministically by (seed, gate, class)
    scripts/mutate.py apply '<json>'     rewrite one line in place (byte-wise: CRLF kept)
    scripts/mutate.py check '<json>'     exit 0 if the file still holds the unmutated line

Four bug classes, each a single-line textual edit that keeps the program type-correct in the
common case (a mutant that does not compile is "stillborn" and the harness tries the next site):

  obo     off-by-one        `<` <-> `<=`, `>` <-> `>=`, `+ 1` / `- 1` dropped
  swap    swapped operands  `a - b` -> `b - a` (also `/`, `%`, `++`, `:::`, `diff`),
                            `a < b` -> `b < a` for identifier operands
  guard   removed guard     `case p if c =>` -> `case p =>`; `if (c) throw|sys.error|return|Left(`
                            -> `if (false) ...`; `.filter(p)` / `.filterNot(p)` dropped;
                            `require(c)` -> `()`
  mapord  reordered keys    first two `k -> v` entries of a one-line Map/ListMap literal swapped;
                            `.sortBy(f)` / `.sortWith(f)` / `.sorted` -> reversed order

Comment lines and text inside string literals are never mutated.
"""
import fnmatch
import glob
import hashlib
import json
import os
import random
import re
import subprocess
import sys

CLASSES = ["obo", "swap", "guard", "mapord"]
IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
KEYWORDS = {"case", "if", "else", "val", "var", "def", "new", "return", "match", "yield", "then",
            "do", "for", "while", "with", "extends", "type", "import", "true", "false", "null",
            "this", "super", "object", "class", "trait", "override", "private", "protected",
            "implicit", "lazy", "final", "sealed", "abstract", "given", "using", "try", "catch",
            "finally", "throw", "forSome", "package", "export", "enum", "inline", "_"}


def string_spans(line):
    """(start, end) spans of "..." and '.' literals, so edits never land inside them."""
    spans, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c == '"':
            if line.startswith('"""', i):
                j = line.find('"""', i + 3)
                j = n if j < 0 else j + 3
            else:
                j = i + 1
                while j < n and line[j] != '"':
                    j += 2 if line[j] == "\\" else 1
                j = min(n, j + 1)
            spans.append((i, j)); i = j
        elif c == "'" and i + 2 < n and (line[i + 2] == "'" or (line[i + 1] == "\\" and i + 3 < n and line[i + 3] == "'")):
            j = i + (4 if line[i + 1] == "\\" else 3)
            spans.append((i, j)); i = j
        elif line.startswith("//", i):
            spans.append((i, n)); break
        else:
            i += 1
    return spans


def outside(spans, a, b):
    return all(b <= s or a >= e for s, e in spans)


def balanced(line, open_idx):
    """index just past the parenthesis matching line[open_idx] == '(' (or -1)."""
    depth = 0
    for k in range(open_idx, len(line)):
        if line[k] == "(":
            depth += 1
        elif line[k] == ")":
            depth -= 1
            if depth == 0:
                return k + 1
    return -1


def top_level_split(s, sep=","):
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append(cur); cur = ""
        else:
            cur += ch
    parts.append(cur)
    return parts


def mutants(line):
    """yield (class, mutated_line) for one source line."""
    stripped = line.strip()
    if not stripped or stripped.startswith(("//", "*", "/*", "import ", "package ")):
        return
    spans = string_spans(line)

    # obo ------------------------------------------------------------------------------------
    for m in re.finditer(r"(?<=[\w)\]]) (<=|>=|<|>) (?=[\w(!-])", line):
        if not outside(spans, m.start(), m.end()):
            continue
        op = m.group(1)
        new = {"<": "<=", "<=": "<", ">": ">=", ">=": ">"}[op]
        yield "obo", line[:m.start(1)] + new + line[m.end(1):]
    for m in re.finditer(r"(?<=[\w)\]]) ([+-]) 1(?![\w.])", line):
        if outside(spans, m.start(), m.end()):
            yield "obo", line[:m.start()] + line[m.end():]

    # swap -----------------------------------------------------------------------------------
    for m in re.finditer(r"(?<![\w.])(%s) (-|/|%%|\+\+|:::|diff) (%s)(?![\w(\[.])" % (IDENT, IDENT), line):
        a, op, b = m.group(1), m.group(2), m.group(3)
        if a in KEYWORDS or b in KEYWORDS or a == b or not outside(spans, m.start(), m.end()):
            continue
        yield "swap", line[:m.start()] + "%s %s %s" % (b, op, a) + line[m.end():]
    for m in re.finditer(r"(?<![\w.])(%s) (<|>|<=|>=) (%s)(?![\w(\[.])" % (IDENT, IDENT), line):
        a, op, b = m.group(1), m.group(2), m.group(3)
        if a in KEYWORDS or b in KEYWORDS or a == b or not outside(spans, m.start(), m.end()):
            continue
        yield "swap", line[:m.start()] + "%s %s %s" % (b, op, a) + line[m.end():]

    # guard ----------------------------------------------------------------------------------
    m = re.match(r"^(\s*case\b.*?)\s+if\s+(.+?)\s*=>", line)
    if m and outside(spans, m.start(2), m.end(2)) and "=>" not in m.group(2):
        yield "guard", m.group(1) + " =>" + line[m.end():]
    for m in re.finditer(r"\bif\s*\(", line):
        close = balanced(line, m.end() - 1)
        if close < 0 or not outside(spans, m.start(), close):
            continue
        rest = line[close:].lstrip()
        if re.match(r"(throw\b|sys\.error\(|return\b|Left\(|die\(|abort\()", rest):
            yield "guard", line[:m.start()] + "if (false)" + line[close:]
    for m in re.finditer(r"\.(filter|filterNot|withFilter)\(", line):
        close = balanced(line, m.end() - 1)
        if close > 0 and outside(spans, m.start(), close):
            yield "guard", line[:m.start()] + line[close:]
    for m in re.finditer(r"(?<![\w.])require\(", line):
        close = balanced(line, m.end() - 1)
        if close > 0 and outside(spans, m.start(), close):
            yield "guard", line[:m.start()] + "()" + line[close:]

    # mapord ---------------------------------------------------------------------------------
    for m in re.finditer(r"\b(Map|ListMap|LinkedHashMap|SortedMap|TreeMap|HashMap|VectorMap)(\[[^\]]*\])?\(", line):
        close = balanced(line, m.end() - 1)
        if close < 0 or not outside(spans, m.start(), close):
            continue
        inner = line[m.end():close - 1]
        parts = top_level_split(inner)
        if len(parts) >= 2 and all("->" in p for p in parts[:2]):
            lead0 = parts[0][: len(parts[0]) - len(parts[0].lstrip())]
            lead1 = parts[1][: len(parts[1]) - len(parts[1].lstrip())]
            swapped = [lead0 + parts[1].strip(), lead1 + parts[0].strip()] + parts[2:]
            if len(parts[1].rstrip()) != len(parts[1]):
                swapped[1] = swapped[1] + parts[1][len(parts[1].rstrip()):]
            yield "mapord", line[:m.end()] + ",".join(swapped) + line[close - 1:]
    for m in re.finditer(r"\.(sortBy|sortWith)\(", line):
        close = balanced(line, m.end() - 1)
        if close > 0 and outside(spans, m.start(), close) and not line[close:].startswith(".reverse"):
            yield "mapord", line[:close] + ".reverse" + line[close:]
    for m in re.finditer(r"\.sorted\b(?!\.reverse)(?!\()", line):
        if outside(spans, m.start(), m.end()):
            yield "mapord", line[:m.end()] + ".reverse" + line[m.end():]


def repo_root():
    return subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()


def expand(globs):
    root = repo_root()
    files = set()
    for g in globs:
        for f in glob.glob(os.path.join(root, g), recursive=True):
            if f.endswith(".scala") and os.path.isfile(f):
                files.add(os.path.relpath(f, root))
    return sorted(files)


def candidates(gate, seed, classes, globs):
    root = repo_root()
    by_class = {c: [] for c in classes}
    for rel in expand(globs):
        raw = open(os.path.join(root, rel), "rb").read()
        in_block = False
        for no, bline in enumerate(raw.split(b"\n"), 1):
            line = bline.rstrip(b"\r").decode("utf-8", "replace")
            s = line.strip()
            if in_block:
                if "*/" in s:
                    in_block = False
                continue
            if s.startswith("/*") and "*/" not in s:
                in_block = True
                continue
            seen = set()
            for cls, after in mutants(line):
                if cls not in by_class or after == line or after in seen:
                    continue
                seen.add(after)
                h = hashlib.sha1(("%s:%d:%s:%s" % (rel, no, cls, after)).encode()).hexdigest()[:10]
                by_class[cls].append({"id": "%s-%s" % (cls, h), "gate": gate, "class": cls,
                                      "file": rel, "line": no, "before": line, "after": after})
    for cls in classes:
        rnd = random.Random("%s:%s:%s" % (seed, gate, cls))
        rnd.shuffle(by_class[cls])
    # interleave classes so a caller taking the first k per class sees every class early
    for cls in classes:
        for c in by_class[cls]:
            print(json.dumps(c))


def rewrite(m, to_after):
    root = repo_root()
    path = os.path.join(root, m["file"])
    raw = open(path, "rb").read()
    lines = raw.split(b"\n")
    i = m["line"] - 1
    cur = lines[i]
    cr = cur.endswith(b"\r")
    text = cur.rstrip(b"\r").decode("utf-8", "replace")
    want, put = (m["before"], m["after"]) if to_after else (m["after"], m["before"])
    if text != want:
        sys.exit("line %s:%d does not hold the expected text" % (m["file"], m["line"]))
    lines[i] = put.encode("utf-8") + (b"\r" if cr else b"")
    open(path, "wb").write(b"\n".join(lines))


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__); return 0
    cmd = sys.argv[1]
    if cmd == "candidates":
        args = sys.argv[2:]; gate = None; seed = "0"; classes = CLASSES; globs = []
        while args:
            a = args.pop(0)
            if a == "--gate": gate = args.pop(0)
            elif a == "--seed": seed = args.pop(0)
            elif a == "--classes": classes = args.pop(0).split(",")
            else: globs.append(a)
        if not gate or not globs or any(c not in CLASSES for c in classes):
            print(__doc__, file=sys.stderr); return 2
        candidates(gate, seed, classes, globs); return 0
    if cmd == "apply":
        rewrite(json.loads(sys.argv[2]), True); return 0
    if cmd == "check":
        m = json.loads(sys.argv[2])
        raw = open(os.path.join(repo_root(), m["file"]), "rb").read().split(b"\n")
        return 0 if raw[m["line"] - 1].rstrip(b"\r").decode("utf-8", "replace") == m["before"] else 1
    print(__doc__, file=sys.stderr); return 2


if __name__ == "__main__":
    sys.exit(main())
