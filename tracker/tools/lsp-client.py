#!/usr/bin/env python3
"""Scripted LSP client for the Ermine language server (roadmap 0.4).

Speaks Content-Length framing over the server's stdio in binary mode
(Content-Length counts bytes; never let text-mode IO near the stream),
runs the smoke scenario against the fixtures in tracker/lsp-tests/, and
prints repl-smoke-style "  PASS/FAIL  lsp (N checks)" lines.

Usage: lsp-client.py <java> <args...>   (the full server command line)
"""
import json
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE.parent / "lsp-tests"
LOG = os.environ.get("LSP_SMOKE_LOG", "/tmp/lsp-smoke.log")

checks = 0
failures = []


def check(name, cond, detail=""):
    global checks
    checks += 1
    if not cond:
        failures.append(name + ("" if not detail else ": " + detail))


class Client:
    def __init__(self, cmd):
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.next_id = 0
        self.seen = []  # notifications observed while waiting for something else

    def send(self, msg):
        body = json.dumps(msg).encode("utf-8")
        self.proc.stdin.write(b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
        self.proc.stdin.flush()

    def request(self, method, params):
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params})
        return self.next_id

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def read_message(self):
        length = None
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise EOFError("server closed stdout")
            if line in (b"\r\n", b"\n"):
                break
            if line.lower().startswith(b"content-length:"):
                length = int(line.split(b":", 1)[1].strip())
        if length is None:
            raise IOError("headers without Content-Length")
        body = b""
        while len(body) < length:
            chunk = self.proc.stdout.read(length - len(body))
            if not chunk:
                raise EOFError("server closed mid-body")
            body += chunk
        return json.loads(body.decode("utf-8"))

    def wait_for(self, pred, what):
        """Read until pred matches; anything else is stashed in self.seen."""
        for _ in range(50):
            msg = self.read_message()
            if pred(msg):
                return msg
            self.seen.append(msg)
        raise AssertionError("gave up waiting for " + what)

    def response(self, rid):
        return self.wait_for(lambda m: m.get("id") == rid, "response %d" % rid)

    def diagnostics_for(self, uri):
        m = self.wait_for(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == uri,
            "diagnostics for " + uri)
        return m["params"]["diagnostics"]


def uri(name):
    return (FIXTURES / name).as_uri()


def repo(rel):
    """A path in the repo, for opening files the resident session already
    holds (the stdlib closure)."""
    return HERE.parent.parent / rel


def main():
    client = Client(sys.argv[1:])

    r = client.response(client.request("initialize", {"capabilities": {}}))
    caps = r.get("result", {}).get("capabilities", {})
    check("initialize.definitionProvider", caps.get("definitionProvider") is True)
    check("initialize.hoverProvider", caps.get("hoverProvider") is True)
    sync = caps.get("textDocumentSync", {})
    # 5.3: TextDocumentSync FULL — didChange carries the whole document
    check("initialize.sync", sync.get("openClose") is True and sync.get("save") is True
          and sync.get("change") == 1, repr(sync))

    client.notify("initialized", {})
    ready = client.wait_for(
        lambda m: m.get("method") == "window/logMessage"
        and "ready" in m["params"]["message"], "readiness logMessage")
    check("boot.reports 129 modules", "129 modules" in ready["params"]["message"],
          ready["params"]["message"])

    def open_doc(name):
        client.notify("textDocument/didOpen", {"textDocument": {
            "uri": uri(name), "languageId": "ermine", "version": 1,
            "text": (FIXTURES / name).read_text()}})

    open_doc("Good.e")
    check("Good.e clean", client.diagnostics_for(uri("Good.e")) == [])

    open_doc("Bad.e")
    ds = client.diagnostics_for(uri("Bad.e"))
    check("Bad.e one diagnostic", len(ds) == 1, repr(ds))
    if len(ds) == 1:
        d = ds[0]
        check("Bad.e line", d["range"]["start"] == {"line": 3, "character": 0}, repr(d["range"]))
        check("Bad.e severity", d["severity"] == 1)
        check("Bad.e message", "failed to unify" in d["message"], d["message"])

    # didSave goes through the same check; use it for the parse error.
    client.notify("textDocument/didSave", {"textDocument": {"uri": uri("Ugly.e")}})
    ds = client.diagnostics_for(uri("Ugly.e"))
    check("Ugly.e one diagnostic", len(ds) == 1, repr(ds))
    if len(ds) == 1:
        d = ds[0]
        # 5.2 repaid the D3 coarsening: the position is the parser's own
        # again (`f = = 3`, the second `=`), not the statement start
        check("Ugly.e line", d["range"]["start"] == {"line": 2, "character": 4}, repr(d["range"]))
        check("Ugly.e message is an expectation", "expected" in d["message"], d["message"])
        check("Ugly.e message names a term", "term atom" in d["message"], d["message"])

    # --- 5.1: a file with TWO broken statements reports both, and its
    # healthy statements still navigate (the index is rebuilt from the
    # same tolerant parse, not left stale from the last clean save).
    open_doc("Broken.e")
    ds = client.diagnostics_for(uri("Broken.e"))
    check("Broken.e two diagnostics", len(ds) == 2, repr(ds))
    if len(ds) == 2:
        # 5.2: each lands on the offending token, not on its line's start
        check("Broken.e first at the second = of `bad1 = = 3`",
              ds[0]["range"]["start"] == {"line": 5, "character": 7}, repr(ds[0]["range"]))
        check("Broken.e second at the ) of `bad2 = ) 3`",
              ds[1]["range"]["start"] == {"line": 7, "character": 7}, repr(ds[1]["range"]))
        check("Broken.e both are syntax diagnostics",
              all("expected" in d["message"] for d in ds), repr(ds))
        check("Broken.e ranges are non-empty",
              all(d["range"]["end"]["character"] > d["range"]["start"]["character"]
                  for d in ds), repr(ds))

    # --- 5.2: an error on a CONTINUATION line is blamed there, not at
    # the statement's head, and the statements around it stay healthy.
    open_doc("Cont.e")
    ds = client.diagnostics_for(uri("Cont.e"))
    check("Cont.e one diagnostic", len(ds) == 1, repr(ds))
    if len(ds) == 1:
        d = ds[0]
        check("Cont.e blames the continuation line, not the head",
              d["range"]["start"] == {"line": 5, "character": 2}, repr(d["range"]))
        check("Cont.e message is an expectation", "expected" in d["message"], d["message"])

    # --- 5.2b: a statement that parses as a PREFIX of its extent and
    # leaves junk behind used to kill the whole module parse, so the file
    # got no per-statement diagnostics and no navigation at all.
    open_doc("Prefix.e")
    ds = client.diagnostics_for(uri("Prefix.e"))
    check("Prefix.e one diagnostic", len(ds) == 1, repr(ds))
    if len(ds) == 1:
        d = ds[0]
        check("Prefix.e blames the leftover, not the head",
              d["range"]["start"] == {"line": 7, "character": 2}, repr(d["range"]))
        check("Prefix.e message is an expectation", "expected" in d["message"], d["message"])

    # Sibling import: Sib.e imports Good.e from the fixtures directory.
    open_doc("Sib.e")
    check("Sib.e sibling import clean", client.diagnostics_for(uri("Sib.e")) == [])

    # A module the RESIDENT session already holds must still check clean.
    # Every module implicitly imports itself, so without scrubbing it out
    # of the check copy first, its own globals arrive as imports and every
    # top-level head draws "would shadow global definition".
    stdlib = repo("core/src/main/resources/modules/Bool.e")
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": stdlib.as_uri(), "languageId": "ermine", "version": 1,
        "text": stdlib.read_text()}})
    ds = client.diagnostics_for(stdlib.as_uri())
    check("an already-loaded stdlib module checks clean", ds == [], repr(ds[:2]))
    client.notify("textDocument/didClose", {"textDocument": {"uri": stdlib.as_uri()}})
    client.diagnostics_for(stdlib.as_uri())

    # --- go-to-definition (0.5) ---
    open_doc("Nav.e")
    check("Nav.e clean", client.diagnostics_for(uri("Nav.e")) == [])

    def definition(name, line, char):
        rid = client.request("textDocument/definition", {
            "textDocument": {"uri": uri(name)},
            "position": {"line": line, "character": char}})
        return client.response(rid).get("result")

    r = definition("Nav.e", 6, 6)  # "twice" in `use = twice answer`
    check("def twice -> its equation", r is not None
          and r["uri"] == uri("Nav.e")
          and r["range"]["start"] == {"line": 5, "character": 0}, repr(r))
    r = definition("Nav.e", 5, 10)  # body "x" in `twice x = x`
    check("def x -> pattern binder", r is not None
          and r["uri"] == uri("Nav.e")
          and r["range"]["start"] == {"line": 5, "character": 6}, repr(r))
    r = definition("Nav.e", 6, 12)  # "answer" imported from sibling Good.e
    check("def answer -> Good.e", r is not None
          and r["uri"] == uri("Good.e")
          and r["range"]["start"]["line"] == 2, repr(r))
    r = definition("Nav.e", 7, 12)  # "&&" imported from stdlib Bool
    check("def && -> Bool.e", r is not None
          and r["uri"].endswith("/Bool.e")
          and r["range"]["start"]["line"] in (6, 7), repr(r))
    check("def miss -> null", definition("Nav.e", 1, 0) is None)

    # 5.1: navigation on the HEALTHY statements of the broken file — a
    # same-file binder and a sibling-module global.
    r = definition("Broken.e", 6, 8)  # `good1` in `good2 = good1`
    check("broken file: def good1 -> its equation", r is not None
          and r["uri"] == uri("Broken.e")
          and r["range"]["start"] == {"line": 4, "character": 0}, repr(r))
    r = definition("Broken.e", 4, 8)  # `answer` in `good1 = answer`
    check("broken file: def answer -> Good.e", r is not None
          and r["uri"] == uri("Good.e")
          and r["range"]["start"]["line"] == 2, repr(r))
    r = definition("Cont.e", 7, 7)  # `answer` in `fine = answer`
    check("continuation-error file: def answer -> Good.e", r is not None
          and r["uri"] == uri("Good.e")
          and r["range"]["start"]["line"] == 2, repr(r))
    r = definition("Prefix.e", 9, 7)  # `answer` in `fine = answer`
    check("prefix-parse file: def answer -> Good.e", r is not None
          and r["uri"] == uri("Good.e")
          and r["range"]["start"]["line"] == 2, repr(r))

    # --- hover (0.6) ---
    def hover(name, line, char):
        rid = client.request("textDocument/hover", {
            "textDocument": {"uri": uri(name)},
            "position": {"line": line, "character": char}})
        return client.response(rid).get("result")

    r = hover("Nav.e", 6, 12)  # "answer"
    check("hover answer : Int", r is not None
          and "Good.answer" in r["contents"]["value"]
          and "Int" in r["contents"]["value"], repr(r))
    r = hover("Nav.e", 7, 12)  # "&&"
    check("hover && : Bool", r is not None
          and "Bool" in r["contents"]["value"], repr(r))
    r = hover("Nav.e", 6, 6)  # "twice", own top-level via the name bridge
    check("hover twice has arrow", r is not None
          and "->" in r["contents"]["value"], repr(r))

    # --- 4.3: renamer-table navigation (sig mentions, where-locals) ---
    r = definition("Nav.e", 8, 0)  # the SIG name `sq` jumps to its equation
    check("def sig sq -> its equation", r is not None
          and r["uri"] == uri("Nav.e")
          and r["range"]["start"] == {"line": 9, "character": 0}, repr(r))
    r = definition("Nav.e", 9, 5)  # `local1` body ref -> the where binder
    check("def where-local -> binder", r is not None
          and r["uri"] == uri("Nav.e")
          and r["range"]["start"] == {"line": 9, "character": 18}, repr(r))
    check("hover where-local -> null (perf ticket)", hover("Nav.e", 9, 5) is None)
    r = hover("Nav.e", 8, 0)  # sig mention hovers via the same binder
    check("hover sig sq : Int", r is not None
          and "Int" in r["contents"]["value"], repr(r))
    check("hover local x -> null", hover("Nav.e", 5, 10) is None)

    # --- S5 review Q-1: the editor must show the type the compiler PUBLISHES ---
    # `TolerantCheck.checkWith` is the editor's copy of the module's top-level
    # generalisation, and it passed `publishing = false` until this fix, so the C12
    # tautology deletion did not run here: hover answered
    # `(exists h t. r <- (t, h)) => Relation r -> Relation r` for `pos` while the
    # `.ei` the compiler writes for the same binding said `Relation r -> Relation r`.
    # `Tauto.e`'s three cases are a deleted one, a near miss that must survive, and a
    # real `Layout.Scan` re-export whose published type the sweep pins.
    open_doc("Tauto.e")
    # ONE call: `diagnostics_for` waits for a publish, so asking twice (e.g. once for
    # the condition and once for `check`'s eagerly-evaluated detail) blocks for ever.
    tauto_ds = client.diagnostics_for(uri("Tauto.e"))
    check("Tauto.e clean", tauto_ds == [], repr(tauto_ds))
    r = hover("Tauto.e", 8, 10)          # `pos`, C12's shape, INFERRED
    v = r["contents"]["value"] if r else ""
    check("hover pos has no vacuous row constraint (C12)",
          r is not None and "->" in v and "<-" not in v and "exists" not in v, repr(r))
    r = hover("Tauto.e", 13, 11)         # `conc`, a CONCRETE part: must survive
    v = r["contents"]["value"] if r else ""
    check("hover conc keeps its concrete-part constraint",
          r is not None and "<-" in v, repr(r))
    # the IMPORTED global itself: this one comes from the session's loaded
    # `Layout.Scan`, i.e. from the compiler's publishing path (or its `.ei`), so it is
    # the "hover agrees with the interface" half rather than the TolerantCheck half.
    r = hover("Tauto.e", 15, 12)         # `count_LS` in `tCount = count_LS`
    v = r["contents"]["value"] if r else ""
    check("hover Layout.Scan.count agrees with its .ei (no qualification)",
          r is not None and "Relation" in v and "<-" not in v and "exists" not in v,
          repr(r))

    # --- navigation for every kind of DECLARATION, not just equations ---
    # Fields, data constructors, foreign declarations, tables and types are
    # installed through Session.primOp/addCon rather than bound by the
    # renamer; until primOp kept the definition site they all answered null.
    open_doc("Decls.e")
    check("Decls.e clean", client.diagnostics_for(uri("Decls.e")) == [])

    r = definition("Decls.e", 16, 8)     # `fa` in `useFa = fa`
    check("def own field -> its declaration", r is not None
          and r["uri"] == uri("Decls.e")
          and r["range"]["start"] == {"line": 9, "character": 6}, repr(r))
    r = definition("Decls.e", 9, 6)      # the `fa` declaration head itself
    check("def field head -> itself", r is not None
          and r["range"]["start"] == {"line": 9, "character": 6}, repr(r))
    r = hover("Decls.e", 9, 6)
    check("hover field head has its type", r is not None
          and "Decls.fa" in r["contents"]["value"], repr(r))

    r = definition("Decls.e", 17, 12)    # `Circle` in `useCircle = Circle 1`
    check("def own constructor -> the data statement", r is not None
          and r["uri"] == uri("Decls.e")
          and r["range"]["start"] == {"line": 11, "character": 15}, repr(r))
    r = hover("Decls.e", 11, 15)         # the constructor at its declaration
    check("hover constructor head", r is not None
          and "Decls.Circle" in r["contents"]["value"], repr(r))

    r = definition("Decls.e", 18, 14)    # `Left`, a constructor from Either.e
    check("def imported constructor -> Either.e", r is not None
          and r["uri"].endswith("/Either.e"), repr(r))
    r = definition("Decls.e", 19, 13)    # `yyyymmdd`, a foreign function
    check("def foreign function -> Date.e", r is not None
          and r["uri"].endswith("/Date.e"), repr(r))

    r = definition("Decls.e", 20, 11)    # `Alias` in the signature
    check("def own type alias -> its statement", r is not None
          and r["uri"] == uri("Decls.e")
          and r["range"]["start"] == {"line": 13, "character": 5}, repr(r))
    r = definition("Decls.e", 22, 12)    # `Either` in the signature
    check("def imported type -> Either.e", r is not None
          and r["uri"].endswith("/Either.e"), repr(r))
    r = definition("Decls.e", 11, 5)     # the `Shape` head itself
    check("def type head -> itself", r is not None
          and r["range"]["start"] == {"line": 11, "character": 5}, repr(r))

    r = definition("Decls.e", 6, 9)      # `<+>` named in its fixity declaration
    check("def fixity mention -> the equation", r is not None
          and r["uri"] == uri("Decls.e")
          and r["range"]["start"] == {"line": 7, "character": 0}, repr(r))

    r = definition("Decls.e", 3, 8)      # `import Either`
    check("def import -> the module's file", r is not None
          and r["uri"].endswith("/Either.e")
          and r["range"]["start"] == {"line": 0, "character": 0}, repr(r))

    # A name that is genuinely undefined still says nothing.
    check("def unknown name -> null", definition("Decls.e", 0, 7) is None)
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Decls.e")}})
    client.diagnostics_for(uri("Decls.e"))

    # --- 5.4: tolerant type checking -----------------------------------
    # loadModule stops at the first Death; the editor checker reports
    # every independent problem.
    open_doc("TwoErr.e")
    ds = client.diagnostics_for(uri("TwoErr.e"))
    check("TwoErr.e publishes BOTH independent type errors", len(ds) == 2, repr(ds))
    if len(ds) == 2:
        check("TwoErr.e first error on its own binding",
              ds[0]["range"]["start"]["line"] == 3, repr(ds[0]["range"]))
        check("TwoErr.e second error on its own binding",
              ds[1]["range"]["start"]["line"] == 6, repr(ds[1]["range"]))
        check("TwoErr.e both are unification errors",
              all("failed to unify" in d["message"] for d in ds), repr(ds))

    # The healthy definitions of a BROKEN file are still type checked,
    # and the undefined-term cascade from the broken statement is gone.
    open_doc("Cascade.e")
    ds = client.diagnostics_for(uri("Cascade.e"))
    check("Cascade.e syntax error plus the healthy type error", len(ds) == 2, repr(ds))
    check("Cascade.e suppresses the undefined-term cascade",
          not any("undefined term" in d["message"] for d in ds), repr(ds))
    check("Cascade.e checks the healthy definition",
          any("failed to unify" in d["message"] and d["range"]["start"]["line"] == 6
              for d in ds), repr(ds))

    # What depends on a broken definition is reported unchecked —
    # transitively — never inferred against unconstrained metas.
    open_doc("Chain.e")
    ds = client.diagnostics_for(uri("Chain.e"))
    check("Chain.e one error and two unchecked", len(ds) == 3, repr(ds))
    if len(ds) == 3:
        check("Chain.e blames the broken definition",
              ds[0]["severity"] == 1 and ds[0]["range"]["start"]["line"] == 4, repr(ds[0]))
        check("Chain.e direct dependent is unchecked (information)",
              ds[1]["severity"] == 3 and "unchecked" in ds[1]["message"]
              and ds[1]["range"]["start"]["line"] == 5, repr(ds[1]))
        check("Chain.e TRANSITIVE dependent is unchecked too",
              ds[2]["severity"] == 3 and "unchecked" in ds[2]["message"]
              and ds[2]["range"]["start"]["line"] == 6, repr(ds[2]))

    # A syntax error NESTED in a where-block is blamed inside the block,
    # not at the statement head: the recovery re-parse commits its way in
    # (5.2).  This is the evidence for deferring 5.6 — the nested-extent
    # scanner it proposed would not improve this position.
    open_doc("Nested.e")
    ds = client.diagnostics_for(uri("Nested.e"))
    check("Nested.e two diagnostics", len(ds) == 2, repr(ds))
    if len(ds) == 2:
        check("Nested.e blames INSIDE the where-block",
              ds[0]["range"]["start"] == {"line": 5, "character": 16}, repr(ds[0]["range"]))
        check("Nested.e still type checks the healthy definition",
              "failed to unify" in ds[1]["message"]
              and ds[1]["range"]["start"]["line"] == 9, repr(ds[1]))
        check("Nested.e no undefined-term cascade from the broken block",
              not any("undefined term" in d["message"] for d in ds), repr(ds))


    # --- LSP-FFI: foreign bindings this JVM cannot resolve --------------
    # The server runs foreign-tolerant (Resident.boot): a `foreign`
    # declaration naming a class or member this JVM does not have is a
    # WARNING at that class or member, the binding is installed at its
    # declared type as a stub, and the rest of the module -- and every
    # dependent -- is checked normally.  A `foreign data` whose class is
    # missing is not a warning (the opaque type is fine) but is not silent
    # either: an Information note says so.  Batch loads keep dying; see
    # tracker/LSP-FFI-TOLERANCE.md.
    #
    # The `probejar.*` fixtures link against a jar built by
    # tracker/tools/build-probejar.sh from tracker/lsp-tests/jsrc: classes
    # that LOAD but whose supertype or member signatures name a class that
    # was deleted after compilation.  That is the shape of a stale jar of
    # the user's fork, and nothing a third-party library ships can silence
    # it.
    def ffi(name, expected, keep_open=False):
        """expected: [(severity, (line, char), (line, char), message substring)]"""
        open_doc(name)
        ds = client.diagnostics_for(uri(name))
        check(name + ": diagnostic count", len(ds) == len(expected), repr(ds))
        if len(ds) == len(expected):
            for i, (sev, start, end, sub) in enumerate(expected):
                d = ds[i]
                check("%s[%d]: severity %d" % (name, i, sev), d["severity"] == sev, repr(d))
                check("%s[%d]: span" % (name, i),
                      d["range"]["start"] == {"line": start[0], "character": start[1]}
                      and d["range"]["end"] == {"line": end[0], "character": end[1]},
                      repr(d["range"]))
                check("%s[%d]: message" % (name, i), sub in d["message"], d["message"])
        if not keep_open:
            client.notify("textDocument/didClose", {"textDocument": {"uri": uri(name)}})
            client.diagnostics_for(uri(name))

    # Tolerance must not INVENT warnings: the stdlib's own writer trait
    # is exactly the shape the fork's is, and every class it names is
    # here, so it stays clean.
    writer = repo("core/src/main/resources/modules/Layout/Writer.e")
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": writer.as_uri(), "languageId": "ermine", "version": 1,
        "text": writer.read_text()}})
    ds = client.diagnostics_for(writer.as_uri())
    check("a healthy foreign-heavy stdlib module stays clean", ds == [], repr(ds[:2]))
    client.notify("textDocument/didClose", {"textDocument": {"uri": writer.as_uri()}})
    client.diagnostics_for(writer.as_uri())

    # Every range below is the LITERAL and nothing more: `spanned` ends a
    # token where the next one starts, so these used to run one character
    # into the following space.

    # (1) the class is not on the classpath: warn on the CLASS NAME
    ffi("FfiClassMissing.e",
        [(2, (5, 11), (5, 55),
          "class missing: com.clarifi.reporting.writers.NoSuchWriter.render "
          "\u2014 java.lang.ClassNotFoundException")], keep_open=True)
    # (2) the class is here but will not LINK -- a NoClassDefFoundError,
    # an Error, which the old `catch { case e: Exception }` let escape
    # (it crashed the check outright, in both modes)
    ffi("FfiClassUnloadable.e",
        [(2, (9, 11), (9, 34), "class unloadable: probejar.PresentSuper.shout "
          "\u2014 java.lang.NoClassDefFoundError: probejar/Missing")])
    # (2') the same Error one layer down: the class LOADS, and `getMethod`
    # / `getField` / `getConstructor` throw while resolving the signature
    # classes of the members they search.  Until the fix round these three
    # unwound past TolerantCheck.guard and Diagnostics.run and the file
    # was published NOTHING.
    ffi("FfiMemberUnloadable.e",
        [(2, (9, 36), (9, 40), "member unloadable: probejar.PresentMember.ok(java.lang.String) "
          "\u2014 java.lang.NoClassDefFoundError: probejar/Missing")])
    ffi("FfiFieldUnloadable.e",
        [(2, (6, 32), (6, 36), "field unloadable: probejar.PresentField.OK "
          "\u2014 java.lang.NoClassDefFoundError: probejar/Missing")])
    ffi("FfiCtorUnloadable.e",
        [(2, (8, 14), (8, 16), "constructor unloadable: probejar.PresentCtor(java.lang.String) "
          "\u2014 java.lang.NoClassDefFoundError: probejar/Missing")])
    # (3) no such member: warn on the MEMBER string
    ffi("FfiMemberMissing.e",
        [(2, (4, 30), (4, 49), "member missing: java.lang.String.noSuchMethodAtAll")])
    # (4) the member exists at other arities -- said so, not "no such method"
    ffi("FfiArity.e",
        [(2, (4, 30), (4, 39), "arity mismatch (declared 2, the class has 1/3)")])
    # (5) the return type is not assignable to the declared codomain
    ffi("FfiReturn.e",
        [(2, (4, 9), (4, 17),
          "return type mismatch: java.lang.String.length "
          "\u2014 declared java.lang.String, found int")])
    # (6) `foreign value`: no such static field
    ffi("FfiFieldMissing.e",
        [(2, (4, 28), (4, 43), "field missing: java.lang.Integer.NO_SUCH_FIELD")])
    # (7) `foreign constructor` names no class and no member, so the
    # warning lands on the declared NAME
    ffi("FfiCtorMissing.e",
        [(2, (6, 14), (6, 16), "constructor missing: java.lang.String(java.lang.String, java.lang.String)")])
    # (8) `foreign subtype` over a foreign type with no backing class: the
    # claim is never checked against a class -- resolved or not -- so the
    # note says so, and the identity is installed anyway.  The `data` above
    # it contributes its own Information note.
    ffi("FfiSubtype.e",
        [(3, (6, 7), (6, 49), "opaque foreign type `Base#`"),
         (2, (7, 10), (7, 12),
          "foreign subtype `up` over an unresolved foreign class: "
          "com.clarifi.reporting.writers.NoSuchBase")])
    # (9) a `foreign data` of a missing class warns at the SITE that needs
    # the class -- here the receiver of a reflective method lookup -- and
    # names the class rather than reporting "no such method" on a sentinel
    ffi("FfiDataNeeded.e",
        [(3, (6, 7), (6, 51), "opaque foreign type `Opaque`"),
         (2, (7, 9), (7, 17),
          "unresolved foreign class: com.clarifi.reporting.writers.NoSuchOpaque "
          "(needed to resolve `render`)")])
    # ... and when NOTHING needs the class, the type is opaque and usable
    # and the module checks normally -- so this is Information, severity 3,
    # a hint and not a squiggle.  Not a warning, and not silence either:
    # silence would be indistinguishable from an intact FFI, which is the
    # one thing someone pointing this server at a fork must not get.
    ffi("FfiDataOpaque.e",
        [(3, (6, 7), (6, 51),
          "opaque foreign type `Opaque`: com.clarifi.reporting.writers.NoSuchOpaque "
          "is not on this JVM (class missing) \u2014 the type is usable")])

    # The fork's writer-trait shape end to end: the opaque writer notes
    # itself, its factory warns on its class, its method warns on its
    # member, and the Ermine code around them checks clean.
    ffi("FfiWriter.e",
        [(3, (8, 7), (8, 52), "opaque foreign type `Writer#`"),
         (2, (10, 11), (10, 59), "class missing: com.clarifi.reporting.writers.MissingCsvWriter.csvWriter"),
         (2, (13, 9), (13, 17),
          "unresolved foreign class: com.clarifi.reporting.writers.MissingWriter")])

    # A warning does not stop the rest of the module being checked: this
    # one carries an unrelated type error four lines below the block.
    ffi("FfiRollback.e",
        [(2, (7, 11), (7, 55), "class missing: com.clarifi.reporting.writers.NoSuchWriter.render"),
         (1, (10, 0), (10, 0), "failed to unify type Int with type String")])

    # A DEPENDENT of a stubbed module: the warning stays on the file that
    # declared it, and this one is clean.
    ffi("FfiUse.e", [], keep_open=True)
    # The stub is bound at its DECLARED type, so navigation and hover work
    # through it...
    r = definition("FfiUse.e", 7, 8)   # `render` in `greet = render "hello"`
    check("def stubbed foreign -> its declaration", r is not None
          and r["uri"] == uri("FfiClassMissing.e")
          and r["range"]["start"]["line"] == 5, repr(r))
    r = hover("FfiUse.e", 7, 8)
    check("hover stubbed foreign : String -> String", r is not None
          and "String -> String" in r["contents"]["value"], repr(r))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("FfiUse.e")}})
    client.diagnostics_for(uri("FfiUse.e"))
    # ... and misusing it is still ONE type error at the use site, not a
    # dead module.
    ffi("FfiUseBad.e", [(1, (7, 7), (7, 7), "failed to unify type String with type Int")])
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("FfiClassMissing.e")}})
    client.diagnostics_for(uri("FfiClassMissing.e"))

    # --- 5.3: didChange drives everything, with no save at all ---------
    def change(name, text, version):
        client.notify("textDocument/didChange", {
            "textDocument": {"uri": uri(name), "version": version},
            "contentChanges": [{"text": text}]})

    edit_src = (FIXTURES / "Edit.e").read_text()
    good_src = (FIXTURES / "Good.e").read_text()

    open_doc("Edit.e")
    check("Edit.e clean on open", client.diagnostics_for(uri("Edit.e")) == [])

    change("Edit.e", edit_src.replace("v = answer", "v = = answer"), 2)
    ds = client.diagnostics_for(uri("Edit.e"))
    check("Edit.e didChange reports without a save", len(ds) == 1, repr(ds))

    change("Edit.e", edit_src, 3)
    check("Edit.e didChange clears without a save",
          client.diagnostics_for(uri("Edit.e")) == [])
    check("Edit.e on disk untouched by the buffer edits",
          (FIXTURES / "Edit.e").read_text() == edit_src)

    # A definition that MOVES is found at its new position, still no save.
    r = definition("Edit.e", 5, 4)  # `v` in `w = v`
    check("def v -> line 4 before the edit", r is not None
          and r["range"]["start"] == {"line": 4, "character": 0}, repr(r))
    change("Edit.e", edit_src.replace("\nv = answer", "\n\nv = answer"), 4)
    check("Edit.e still clean after the insert",
          client.diagnostics_for(uri("Edit.e")) == [])
    r = definition("Edit.e", 6, 4)  # `v` in `w = v`, now one line down
    check("def v -> line 5 after the edit, no save", r is not None
          and r["range"]["start"] == {"line": 5, "character": 0}, repr(r))

    # 5.5: breaking an UPSTREAM definition must reach its dependents
    # through the per-SCC cache, not be masked by a stale entry.
    change("Edit.e", edit_src.replace("v = answer", "v = answer True"), 10)
    ds = client.diagnostics_for(uri("Edit.e"))
    check("breaking v reports it and unchecks w", len(ds) == 2, repr(ds))
    if len(ds) == 2:
        check("breaking v: the error is on v",
              ds[0]["severity"] == 1 and ds[0]["range"]["start"]["line"] == 4, repr(ds[0]))
        check("breaking v: w goes unchecked",
              ds[1]["severity"] == 3 and "unchecked" in ds[1]["message"], repr(ds[1]))
    change("Edit.e", edit_src, 11)
    check("fixing v clears both", client.diagnostics_for(uri("Edit.e")) == [])

    # A SIBLING's unsaved edit is seen by the importing file's next check:
    # move Good.answer down a line in ITS buffer and re-check Edit.e.
    change("Good.e", good_src.replace("\nanswer = 42", "\n\nanswer = 42"), 2)
    client.diagnostics_for(uri("Good.e"))
    change("Edit.e", edit_src, 5)
    check("Edit.e clean against the edited sibling",
          client.diagnostics_for(uri("Edit.e")) == [])
    r = definition("Edit.e", 4, 4)  # `answer`, imported from the Good.e BUFFER
    check("def answer -> the sibling buffer's new line", r is not None
          and r["uri"] == uri("Good.e")
          and r["range"]["start"]["line"] == 3, repr(r))
    change("Good.e", good_src, 3)
    client.diagnostics_for(uri("Good.e"))

    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Edit.e")}})
    check("Edit.e cleared on close", client.diagnostics_for(uri("Edit.e")) == [])

    # --- fast mode: skip the type check, keep everything the read gives -
    def set_fast(on):
        client.notify("workspace/didChangeConfiguration",
                      {"settings": {"ermine": {"fastMode": on}}})

    set_fast(True)
    client.notify("textDocument/didSave", {"textDocument": {"uri": uri("Bad.e")}})
    check("fast mode drops the type error", client.diagnostics_for(uri("Bad.e")) == [])
    client.notify("textDocument/didSave", {"textDocument": {"uri": uri("Ugly.e")}})
    ds = client.diagnostics_for(uri("Ugly.e"))
    check("fast mode KEEPS syntax diagnostics", len(ds) == 1, repr(ds))
    check("fast mode keeps their precise positions",
          len(ds) == 1 and ds[0]["range"]["start"] == {"line": 2, "character": 4}, repr(ds))
    # navigation is a read-phase product, so it survives fast mode
    r = definition("Nav.e", 6, 12)
    check("fast mode keeps go-to-definition", r is not None
          and r["uri"] == uri("Good.e"), repr(r))
    # ... including for names the SESSION would only know after a check:
    # a field or constructor of this module is placed from the surface tree.
    open_doc("Decls.e")
    client.diagnostics_for(uri("Decls.e"))
    r = definition("Decls.e", 16, 8)
    check("fast mode keeps own-field navigation", r is not None
          and r["range"]["start"] == {"line": 9, "character": 6}, repr(r))
    r = definition("Decls.e", 17, 12)
    check("fast mode keeps own-constructor navigation", r is not None
          and r["range"]["start"] == {"line": 11, "character": 15}, repr(r))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Decls.e")}})
    client.diagnostics_for(uri("Decls.e"))

    set_fast(False)
    client.notify("textDocument/didSave", {"textDocument": {"uri": uri("Bad.e")}})
    ds = client.diagnostics_for(uri("Bad.e"))
    check("leaving fast mode restores the type error", len(ds) == 1
          and "failed to unify" in ds[0]["message"], repr(ds))

    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Bad.e")}})
    check("Bad.e cleared on close", client.diagnostics_for(uri("Bad.e")) == [])

    # Checks must neither read nor write interface files (a stale .ei would
    # let type errors through unreported, and writebacks litter workspaces).
    check("no .ei droppings", not list(FIXTURES.glob("*.ei")),
          repr(list(FIXTURES.glob("*.ei"))))

    r = client.response(client.request("shutdown", None))
    check("shutdown null", r.get("result") is None and "error" not in r)
    client.notify("exit", {})
    check("exit code 0", client.proc.wait(timeout=30) == 0)

    if failures:
        print("  FAIL  lsp")
        for f in failures:
            print("      " + f)
        print("      server log: " + LOG)
        return 1
    print("  PASS  lsp (%d checks)" % checks)
    return 0


if __name__ == "__main__":
    sys.exit(main())
