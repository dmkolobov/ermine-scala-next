#!/usr/bin/env python3
"""Check ermine.tmLanguage.json without VS Code.

A small TextMate tokenizer: a stack of contexts, `begin` pushes, `end` pops,
patterns tried in order within the active context. That is enough to model the
parts of the grammar that actually matter here — comments, strings and import
lines are all begin/end rules whose whole point is that they change what the
patterns underneath them mean.

Python's `re` is not Oniguruma, but the grammar deliberately sticks to the
subset they share (character classes, lookaround, alternation), so a compile
failure or a wrong scope here is a real one.

    python3 editor/vscode/test/grammar-test.py

Exits non-zero on any failure.
"""

import json
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
GRAMMAR = HERE.parent / "syntaxes" / "ermine.tmLanguage.json"
REPO_ROOT = HERE.parents[2]

g = json.load(open(GRAMMAR))
repo = g["repository"]

failures = []


def fail(msg):
    failures.append(msg)
    print("  FAIL " + msg)


# --------------------------------------------------------------- tokenizer

def resolve(items):
    """Flatten #include one level into concrete rule dicts, in order."""
    out = []
    for item in items:
        if "include" in item:
            node = repo[item["include"].lstrip("#")]
            if "match" in node or "begin" in node:
                out.append(node)
            else:
                out.extend(resolve(node.get("patterns", [])))
        else:
            out.append(item)
    return out


def scope_of(rule, group_index):
    """The scope a rule assigns to a given capture group (0 = whole match)."""
    if group_index == 0 and "name" in rule:
        return rule["name"]
    caps = rule.get("captures") or rule.get("beginCaptures") or {}
    entry = caps.get(str(group_index))
    return entry.get("name") if entry else rule.get("name")


def tokenize(line, stack=None):
    """[(start, end, scope)] for one line, plus the context stack after it."""
    stack = list(stack) if stack else [{"patterns": resolve(g["patterns"])}]
    tokens, pos = [], 0
    guard = 0
    while pos < len(line):
        guard += 1
        if guard > 5000:
            raise RuntimeError("tokenizer failed to advance — a rule matches empty")
        top = stack[-1]

        # An active begin/end context tries its own end first.
        if "endRx" in top:
            m = top["endRx"].match(line, pos)
            if m and m.end() > m.start():
                tokens.append((m.start(), m.end(), top.get("scope")))
                pos = m.end()
                stack.pop()
                continue

        best = None
        for rule in top["patterns"]:
            key = "match" if "match" in rule else "begin"
            rx = rule.setdefault("_rx_" + key, re.compile(rule[key]))
            m = rx.match(line, pos)
            if m and m.end() > m.start():
                best = (rule, key, m)
                break

        if best is None:
            # Inside a begin/end region everything unclaimed carries that
            # region's scope — that is what makes a string a string.
            if top.get("scope"):
                tokens.append((pos, pos + 1, top["scope"]))
            pos += 1  # otherwise unstyled: ordinary identifiers, whitespace
            continue

        rule, key, m = best
        # Split into per-capture scopes ONLY when the rule declares captures;
        # a rule with a plain `name` scopes its whole match, groups or not.
        caps = rule.get("captures") or rule.get("beginCaptures")
        emitted = False
        if caps:
            for gi in range(1, (m.re.groups or 0) + 1):
                if m.group(gi) is not None and m.start(gi) < m.end(gi):
                    sc = scope_of(rule, gi)
                    if sc:
                        tokens.append((m.start(gi), m.end(gi), sc))
                        emitted = True
        if not emitted:
            tokens.append((m.start(), m.end(), scope_of(rule, 0)))
        pos = m.end()

        if key == "begin":
            stack.append({
                "patterns": resolve(rule.get("patterns", [])),
                "endRx": re.compile(rule["end"]),
                "scope": rule.get("name"),
            })

    # A context whose `end` is `$` closes at end of line. Without this the
    # import rule stays on the stack forever and every later line is
    # tokenized inside it — which is exactly what hid the char literals.
    while len(stack) > 1 and stack[-1].get("endRx") is not None:
        m = stack[-1]["endRx"].match(line, len(line))
        if m is None:
            break
        stack.pop()
    return tokens, stack


def scope_at(line, col, stack=None):
    tokens, _ = tokenize(line, stack)
    for start, end, scope in tokens:
        if start <= col < end:
            return scope
    return None


# ------------------------------------------------------------------ checks

print("1. every regex compiles, and none matches empty")
count = 0
def walk(node):
    global count
    if isinstance(node, dict):
        for k, v in node.items():
            if k in ("match", "begin", "end") and isinstance(v, str):
                count += 1
                try:
                    c = re.compile(v)
                except re.error as e:
                    fail("regex %r does not compile: %s" % (v[:60], e))
                    continue
                if k == "match" and c.match("") is not None:
                    fail("regex %r matches empty — would hang the tokenizer" % v[:60])
            else:
                walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)
walk(g)
print("   %d regexes checked" % count)

print("2. lexer rules that differ from Haskell intuition")
CASES = [
    # (line, column, expected scope or None for unstyled)
    ("x --> y", 2, "comment.line.double-dash.ermine"),          # -- is unconditional
    ("f = x -- trailing", 6, "comment.line.double-dash.ermine"),
    ("foo' = 1", 0, "entity.name.function.ermine"),             # ' is a tail char
    ("v = 'a'", 4, "string.quoted.single.ermine"),
    ("v = a ' b", 6, "keyword.operator.ermine"),                # lone ' is an operator
    ("v = x ++_L y", 6, "keyword.operator.ermine"),             # _Module affix is in the lexeme
    ("prj# x", 0, "keyword.other.type.ermine"),                 # keyword ending in #
    ("v = @2014/1/31", 4, "constant.other.date.ermine"),
    ("v = 42L", 4, "constant.numeric.integer.ermine"),
    ("v = 3.5F", 4, "constant.numeric.float.ermine"),
    ("v = x -> y", 6, "keyword.operator.reserved.ermine"),
]
for line, col, want in CASES:
    got = scope_at(line, col)
    if got != want:
        fail("%r col %d -> %s (wanted %s)" % (line, col, got, want))
print("   %d cases" % len(CASES))

print("3. keyword prefixes inside longer identifiers must not false-match")
for word in ["constraints", "letter", "inx", "dataSet", "doThing", "ofType",
             "typeOf", "classy", "instanceOf", "wheresoever"]:
    line = "%s = 1" % word
    got = scope_at(line, 0)
    if got != "entity.name.function.ermine":
        fail("%r col 0 -> %s (a keyword leaked into an identifier)" % (line, got))
print("   10 identifiers")

print("4. comments and strings do not leak into each other")
NEST = [
    ('v = "-- not a comment"', 8, "string.quoted.double.ermine"),
    ('v = "{- nor this"', 8, "string.quoted.double.ermine"),
    ('-- a comment with "quotes"', 20, "comment.line.double-dash.ermine"),
    ("{- block {- nested -} still -}", 12, "comment.block.ermine"),
]
for line, col, want in NEST:
    got = scope_at(line, col)
    if got != want:
        fail("%r col %d -> %s (wanted %s)" % (line, col, got, want))
print("   %d cases" % len(NEST))

print("5. real corpus lines, in context")
CORPUS = [
    # verbatim from the stdlib; (line, col, expected)
    ("import List.NonEmpty using (:|) ; type NonEmpty", 21, "keyword.control.import.ermine"),
    ("import Relation.Op hiding {empty_Bracket; cons_Bracket}", 7, "entity.name.namespace.ermine"),
    ("import Record hiding (++)", 14, "keyword.control.import.ermine"),
    ("import Native.List using {type List# ; fromList#}", 26, "keyword.control.import.ermine"),
    ("module Layout.Report.Keyed.Syntax where", 7, "entity.name.namespace.ermine"),
    ("data D = MkD", 0, "storage.type.ermine"),
    ("infixr 5 ++", 0, "storage.modifier.fixity.ermine"),
]
for line, col, want in CORPUS:
    got = scope_at(line, col)
    if got != want:
        fail("%r col %d -> %s (wanted %s)" % (line, col, got, want))
print("   %d cases" % len(CORPUS))

print("6. `if` is a function, not a keyword; `'` and ` are operators")
NONKEYWORD = [
    ("v = if c a b", 4, None),              # Bool.e:23 defines `if` as a function
    ("if : Bool -> a -> a -> a", 0, "entity.name.function.ermine"),
    ("v = a ' b", 6, "keyword.operator.ermine"),      # Function.e: infixl 0 '
    ("v = a ` b", 6, "keyword.operator.ermine"),      # Function.e: infixl 0 `
]
for line, col, want in NONKEYWORD:
    got = scope_at(line, col)
    if got != want:
        fail("%r col %d -> %s (wanted %s)" % (line, col, got, want))
print("   %d cases" % len(NONKEYWORD))

print("7. the apostrophe operator is not eaten by the char-literal rule")
# `'` is infixl 0 in Function.e with ~1165 raw uses; a char rule that spans
# would swallow whole expressions. Count what the grammar calls a char literal
# across the corpus and check it against the ones that really are.
import collections
files_ = sorted(
    list((REPO_ROOT / "core/src/main/resources/modules").rglob("*.e"))
    + list((REPO_ROOT / "core/examples").rglob("*.e"))
)
charlits = collections.Counter()
for f in files_:
    stack = None
    for line in f.read_text(encoding="utf-8", errors="replace").split("\n"):
        toks, stack = tokenize(line, stack)
        for a, b, sc in toks:
            if sc == "string.quoted.single.ermine":
                charlits[line[a:b]] += 1
total = sum(charlits.values())
print("   %d char literals across the corpus: %s"
      % (total, dict(charlits.most_common(8))))
# every one must be exactly 3 or 4 characters — 'x' or '\\x'
bad_lits = [t for t in charlits if not (len(t) in (3, 4) and t[0] == "'" and t[-1] == "'")]
if bad_lits:
    fail("char-literal rule matched something that is not a char literal: %r" % bad_lits[:5])

print("8. identifier start rules, and control escapes")
IDENT = [
    ("foo = 1", 0, "entity.name.function.ermine"),
    # `_x` cannot be an identifier at all (letter >> identTail), so nothing
    # should claim it as a definition name
    ("_x = 1", 0, None),
    ("f x = x + 1 + _", 14, None),        # bare _ is a hole, not a name
    ('v = "a\\^Ab"', 6, "constant.character.escape.control.ermine"),
]
for line, col, want in IDENT:
    got = scope_at(line, col)
    if got != want:
        fail("%r col %d -> %s (wanted %s)" % (line, col, got, want))
print("   %d cases" % len(IDENT))

print("9. the whole corpus tokenizes without stalling")
files = sorted(
    list((REPO_ROOT / "core/src/main/resources/modules").rglob("*.e"))
    + list((REPO_ROOT / "core/examples").rglob("*.e"))
)
lines = 0
if not files:
    fail("no corpus files found under %s" % REPO_ROOT)
for f in files:
    stack = None
    for line in f.read_text(encoding="utf-8", errors="replace").split("\n"):
        lines += 1
        try:
            _, stack = tokenize(line, stack)
        except RuntimeError as e:
            fail("%s: %s\n    %r" % (f.name, e, line[:70]))
            stack = None
            break
print("   %d files, %d lines" % (len(files), lines))

print()
if failures:
    print("FAILED — %d problem(s)" % len(failures))
    sys.exit(1)
print("PASS — grammar checks out")
