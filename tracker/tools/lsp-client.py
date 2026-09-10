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
    # 6.3: references, document highlight and rename, all answered from
    # the index the last check built.
    check("initialize.referencesProvider", caps.get("referencesProvider") is True)
    check("initialize.documentHighlightProvider",
          caps.get("documentHighlightProvider") is True)
    check("initialize.renameProvider with prepare",
          caps.get("renameProvider") == {"prepareProvider": True},
          repr(caps.get("renameProvider")))
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
    # 6.2: the where-local answers its type now, at its use and at its
    # def-site.  Before 6.2 both were null ("perf-ticket territory").
    r = hover("Nav.e", 9, 5)             # `local1` in `sq = local1`
    check("hover where-local : Int", r is not None
          and r["contents"]["value"].strip().splitlines()[1] == "local1 : Int", repr(r))
    r = hover("Nav.e", 9, 18)            # its def-site in the where block
    check("hover where-local at its def-site", r is not None
          and r["contents"]["value"].strip().splitlines()[1] == "local1 : Int", repr(r))
    r = hover("Nav.e", 8, 0)  # sig mention hovers via the same binder
    check("hover sig sq : Int", r is not None
          and "Int" in r["contents"]["value"], repr(r))
    # An equation's ARGUMENT: not from its own meta (Lower drops that into
    # an `Annot`) but from `twice`'s own type, split by its arity --
    # tracker/loopmodel/LSP3-6.2-LOCALS.md.
    r = hover("Nav.e", 5, 10)
    check("hover arg x : a (from the head's arity)", r is not None
          and r["contents"]["value"].strip().splitlines()[1] == "x : a", repr(r))

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

    # --- 6.1(b): an import that will not load ---------------------------
    # Until this item the first failing import threw out of checkFile and
    # became ONE diagnostic at 0:0 -- the second failing import, and every
    # healthy definition in the file, went unreported.  Now each failure
    # squiggles the MODULE NAME in its own import statement, carrying the
    # loader's own report (which names the import's file and position),
    # and the file is checked anyway.
    open_doc("BadImport.e")
    ds = client.diagnostics_for(uri("BadImport.e"))
    check("BadImport.e one diagnostic per failing import, plus its own type error",
          len(ds) == 3, repr(ds))
    if len(ds) == 3:
        # `import NoSuchModule`, line 3: the module name, columns 8-19
        check("BadImport.e missing module squiggles its name",
              ds[0]["severity"] == 1
              and ds[0]["range"]["start"] == {"line": 2, "character": 7}
              and ds[0]["range"]["end"] == {"line": 2, "character": 19}, repr(ds[0]["range"]))
        check("BadImport.e missing module names the module",
              "import NoSuchModule failed" in ds[0]["message"]
              and "Module not found: 'NoSuchModule'" in ds[0]["message"], ds[0]["message"])
        # `import BadSib`, line 4: the module name, columns 8-13
        check("BadImport.e unloadable sibling squiggles its name",
              ds[1]["severity"] == 1
              and ds[1]["range"]["start"] == {"line": 3, "character": 7}
              and ds[1]["range"]["end"] == {"line": 3, "character": 13}, repr(ds[1]["range"]))
        check("BadImport.e unloadable sibling keeps the loader's file:line",
              "import BadSib failed" in ds[1]["message"]
              and "BadSib.e:5:" in ds[1]["message"], ds[1]["message"])
    # THE RULE (6.1(b) step 2): while an import has failed, the names it
    # would have provided are not reported as undefined terms, and nothing
    # is reported unchecked on their account -- `use = sibAnswer` is silent.
    check("BadImport.e suppresses the undefined-term cascade",
          not any("undefined term" in d["message"] for d in ds), repr(ds))
    check("BadImport.e suppresses the unchecked cascade",
          not any("unchecked" in d["message"] for d in ds), repr(ds))
    # ... and the roadmap's own tick condition, pinned POSITIVELY: the
    # file's OTHER diagnostics still publish.  `bad : Int` / `bad = "no"`
    # is a definition that has nothing to do with either import, and a
    # filter that dropped every Error note would leave the two import
    # failures behind and pass every check above.
    check("BadImport.e still publishes its own type error",
          any("failed to unify" in d["message"] and d["range"]["start"]["line"] == 13
              for d in ds), repr(ds))
    # ... and the file is still checked and indexed: its own healthy
    # definition navigates and hovers.
    r = definition("BadImport.e", 8, 9)   # `own` in `useOwn = own`
    check("BadImport.e healthy definition still navigates", r is not None
          and r["uri"] == uri("BadImport.e")
          and r["range"]["start"] == {"line": 6, "character": 0}, repr(r))
    r = hover("BadImport.e", 8, 9)
    check("BadImport.e healthy definition still hovers", r is not None
          and "Int" in r["contents"]["value"], repr(r))

    # Fixing the sibling in ITS buffer clears the second import
    # diagnostic on the next check of BadImport.e -- no save anywhere.
    open_doc("BadSib.e")
    ds = client.diagnostics_for(uri("BadSib.e"))
    check("BadSib.e reports its own syntax error", len(ds) == 1
          and ds[0]["range"]["start"] == {"line": 4, "character": 9}, repr(ds))
    bad_sib_src = (FIXTURES / "BadSib.e").read_text()

    def edit(name, text, version):
        """didChange with the whole document (TextDocumentSync FULL)."""
        client.notify("textDocument/didChange", {
            "textDocument": {"uri": uri(name), "version": version},
            "contentChanges": [{"text": text}]})

    edit("BadSib.e", bad_sib_src.replace("broken = = 3", "broken = 3"), 2)
    check("BadSib.e clean once fixed in the buffer",
          client.diagnostics_for(uri("BadSib.e")) == [])
    client.notify("textDocument/didSave", {"textDocument": {"uri": uri("BadImport.e")}})
    ds = client.diagnostics_for(uri("BadImport.e"))
    check("BadImport.e loses the sibling diagnostic and keeps the rest", len(ds) == 2, repr(ds))
    if len(ds) == 2:
        check("BadImport.e remaining import diagnostic is the missing module",
              "NoSuchModule" in ds[0]["message"], ds[0]["message"])
        check("BadImport.e still publishes its own type error after the sibling is fixed",
              "failed to unify" in ds[1]["message"], ds[1]["message"])
    edit("BadSib.e", bad_sib_src, 3)
    client.diagnostics_for(uri("BadSib.e"))
    check("BadSib.e on disk untouched by the buffer edits",
          (FIXTURES / "BadSib.e").read_text() == bad_sib_src)
    for name in ("BadImport.e", "BadSib.e"):
        client.notify("textDocument/didClose", {"textDocument": {"uri": uri(name)}})
        client.diagnostics_for(uri(name))

    # 6.1(c): an import list naming something the module does not export
    # is the editor's own check (batch gets it from Dep.checkNames), and it
    # used to render at the module header -- line 1, column 1, which is LSP
    # 0:0.  The name is in the import list and the read knows its span.
    open_doc("BadReq.e")
    ds = client.diagnostics_for(uri("BadReq.e"))
    check("BadReq.e one diagnostic", len(ds) == 1, repr(ds))
    if len(ds) == 1:
        # `import Bool using { nosuchname }`, line 3: the NAME.  The end
        # runs to where the next token starts, as every surface span does.
        check("BadReq.e squiggles the name in the import list, not the header",
              ds[0]["severity"] == 1
              and ds[0]["range"]["start"] == {"line": 2, "character": 20}
              and ds[0]["range"]["end"] == {"line": 2, "character": 31}, repr(ds[0]["range"]))
        check("BadReq.e says what is missing",
              ds[0]["message"] == "Module 'Bool' does not export term 'nosuchname'.",
              ds[0]["message"])
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("BadReq.e")}})
    client.diagnostics_for(uri("BadReq.e"))

    # A header that will not parse is the one unrecoverable Death that is
    # genuinely about THIS file: it keeps its own position (6.1(b) step 3).
    open_doc("BadHeader.e")
    ds = client.diagnostics_for(uri("BadHeader.e"))
    check("BadHeader.e one diagnostic", len(ds) == 1, repr(ds))
    if len(ds) == 1:
        check("BadHeader.e is positioned in this file, not at 0:0",
              ds[0]["range"]["start"] == {"line": 0, "character": 17}
              and ds[0]["range"]["end"] == {"line": 0, "character": 17}, repr(ds[0]["range"]))
        check("BadHeader.e says what the header wanted",
              "where" in ds[0]["message"], ds[0]["message"])
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("BadHeader.e")}})
    client.diagnostics_for(uri("BadHeader.e"))


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

    # --- 6.2: types at every binder the check can reach, kinds on type
    # names.  A local's type comes from `TolerantCheck.Result.locals`,
    # joined to the occurrence by the renamer binder's DEF-SITE; a type
    # name's kind comes from its `Con`'s kind schema.  What is NOT here
    # is as pinned as what is: an unsigned pattern binder (arg, case,
    # do) answers null, by the mechanism the report names.
    def hoverline(name, line, char):
        """The `spelling : type` line inside the fenced hover block."""
        r = hover(name, line, char)
        if r is None:
            return None
        return r["contents"]["value"].strip().splitlines()[1]

    open_doc("Locals.e")
    locals_ds = client.diagnostics_for(uri("Locals.e"))
    check("Locals.e clean", locals_ds == [], repr(locals_ds))

    # a LET binder, at its def-site and at a use
    check("hover let binder at its def-site",
          hoverline("Locals.e", 10, 6) == "flag : Bool", hoverline("Locals.e", 10, 6))
    check("hover let binder at a use",
          hoverline("Locals.e", 11, 5) == "flag : Bool", hoverline("Locals.e", 11, 5))
    # a WHERE binder, at its def-site and at a use
    check("hover where binder at its def-site",
          hoverline("Locals.e", 14, 8) == "keep : Bool", hoverline("Locals.e", 14, 8))
    check("hover where binder at a use",
          hoverline("Locals.e", 13, 15) == "keep : Bool", hoverline("Locals.e", 13, 15))
    # a SIGNED where binder shows AS DECLARED (Decision a)
    check("hover signed where binder",
          hoverline("Locals.e", 18, 8) == "strict : Bool -> Bool", hoverline("Locals.e", 18, 8))
    check("hover signed where binder at its signature",
          hoverline("Locals.e", 17, 8) == "strict : Bool -> Bool", hoverline("Locals.e", 17, 8))
    # a polymorphic where-bound helper: the metas its component
    # generalised render as type VARIABLES, no `forall` on a local
    check("hover polymorphic where binder",
          hoverline("Locals.e", 21, 8) == "idy : a -> a", hoverline("Locals.e", 21, 8))
    # an EQUATION's arguments, recovered from the head's own type
    check("hover equation arg at its def-site",
          hoverline("Locals.e", 23, 9) == "p : Bool", hoverline("Locals.e", 23, 9))
    check("hover equation arg at a use",
          hoverline("Locals.e", 23, 15) == "p : Bool", hoverline("Locals.e", 23, 15))
    # ... and their LETTERS agree with the binding's own hover: `konst`
    # is `forall a b. a -> b -> a`, so its arguments are `a` and `b` --
    # never `a` and `a`, which two independent renderings would give.
    check("hover konst's own type",
          hoverline("Locals.e", 34, 0) == "Locals.konst : forall a b. a -> b -> a",
          hoverline("Locals.e", 34, 0))
    check("hover konst's first argument agrees with it",
          hoverline("Locals.e", 34, 6) == "k : a", hoverline("Locals.e", 34, 6))
    check("hover konst's second argument agrees with it",
          hoverline("Locals.e", 34, 8) == "j : b", hoverline("Locals.e", 34, 8))
    # the pattern binders the split cannot reach, absent BY MECHANISM
    check("hover case binder -> null", hover("Locals.e", 26, 9) is None)
    check("hover case-bound use -> null", hover("Locals.e", 26, 14) is None)

    # TYPE NAMES hover with their KIND: imported, own `data`, own alias.
    check("hover imported type Bool : *",
          hoverline("Locals.e", 8, 11) == "Builtin.Bool : *", hoverline("Locals.e", 8, 11))
    check("hover own data type at its head",
          hoverline("Locals.e", 4, 5) == "Locals.Shape : *", hoverline("Locals.e", 4, 5))
    check("hover own type alias has an arrow kind",
          hoverline("Locals.e", 6, 5) == "Locals.Boxed : * -> *", hoverline("Locals.e", 6, 5))
    # a MENTION of an own type resolves to its TyDef binder, and must
    # agree with the declaration head about the kind
    check("hover own data type at a mention",
          hoverline("Locals.e", 31, 18) == "Locals.Shape : *", hoverline("Locals.e", 31, 18))

    # A local whose definition MOVES answers at its new position, and the
    # position it left answers null.
    locals_src = (FIXTURES / "Locals.e").read_text()
    check("hover last local before the edit",
          hoverline("Locals.e", 29, 17) == "tail1 : Bool", hoverline("Locals.e", 29, 17))
    change("Locals.e", locals_src.replace("\nlastLocal", "\n\nlastLocal"), 2)
    check("Locals.e still clean after the insert",
          client.diagnostics_for(uri("Locals.e")) == [])
    check("hover last local at its NEW line",
          hoverline("Locals.e", 30, 17) == "tail1 : Bool", hoverline("Locals.e", 30, 17))
    check("hover last local at its OLD line -> null", hover("Locals.e", 29, 17) is None)
    change("Locals.e", locals_src, 3)
    check("Locals.e clean again", client.diagnostics_for(uri("Locals.e")) == [])

    # A BROKEN file: the healthy statement's local still hovers, and a
    # local of a component that DIED answers null (nothing typed it).
    open_doc("LocalsBroken.e")
    broken_ds = client.diagnostics_for(uri("LocalsBroken.e"))
    check("LocalsBroken.e reports its two failures", len(broken_ds) == 2, repr(broken_ds))
    check("hover a local in the healthy statement of a broken file",
          hoverline("LocalsBroken.e", 4, 15) == "ok : Bool",
          hoverline("LocalsBroken.e", 4, 15))
    check("hover a local of a component that died -> null",
          hover("LocalsBroken.e", 8, 12) is None)
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("LocalsBroken.e")}})
    client.diagnostics_for(uri("LocalsBroken.e"))

    # --- 6.3: references, document highlight, rename -------------------
    # Every answer below comes from the STORED index and renamer tables of
    # the last check: no parse, no rename pass, no inference on a request
    # path (the Stage-3 invariant).  What "the set" is depends on the key:
    # a LOCAL key is a binder id and means this document only; a GLOBAL key
    # is a canonical Global and spans the open buffers, def-site included.
    def references(name, line, char, include=True):
        rid = client.request("textDocument/references", {
            "textDocument": {"uri": uri(name)},
            "position": {"line": line, "character": char},
            "context": {"includeDeclaration": include}})
        return client.response(rid).get("result")

    def highlight(name, line, char):
        rid = client.request("textDocument/documentHighlight", {
            "textDocument": {"uri": uri(name)},
            "position": {"line": line, "character": char}})
        return client.response(rid).get("result")

    def prepare_rename(name, line, char):
        rid = client.request("textDocument/prepareRename", {
            "textDocument": {"uri": uri(name)},
            "position": {"line": line, "character": char}})
        return client.response(rid).get("result")

    def rename(name, line, char, new):
        rid = client.request("textDocument/rename", {
            "textDocument": {"uri": uri(name)},
            "position": {"line": line, "character": char},
            "newName": new})
        return client.response(rid)

    def spans(locs):
        """Locations as (file, line, startChar, endChar), the compact form."""
        return [(l["uri"].rsplit("/", 1)[1], l["range"]["start"]["line"],
                 l["range"]["start"]["character"], l["range"]["end"]["character"])
                for l in locs]

    def kinds(hs):
        return [(h["range"]["start"]["line"], h["range"]["start"]["character"],
                 h["range"]["end"]["character"], h["kind"]) for h in hs]

    def edits_of(result, name):
        return result["result"]["changes"].get(uri(name), [])

    def warnings():
        """The window/showMessage warnings stashed since the last call."""
        ws = [m["params"] for m in client.seen
              if m.get("method") == "window/showMessage"]
        client.seen = []
        return ws

    def apply_edits(text, edits):
        """Apply single-line TextEdits, last first so earlier ones keep their
        positions -- what a client does with a WorkspaceEdit."""
        lines = text.split("\n")
        for e in sorted(edits, key=lambda e: (e["range"]["start"]["line"],
                                              e["range"]["start"]["character"]),
                        reverse=True):
            ln = e["range"]["start"]["line"]
            a = e["range"]["start"]["character"]
            b = e["range"]["end"]["character"]
            lines[ln] = lines[ln][:a] + e["newText"] + lines[ln][b:]
        return "\n".join(lines)

    open_doc("Refs.e")
    check("Refs.e clean", client.diagnostics_for(uri("Refs.e")) == [])
    open_doc("RefsSib.e")
    check("RefsSib.e clean", client.diagnostics_for(uri("RefsSib.e")) == [])

    # A LOCAL: `mine`, a let binder with three uses on the line below.  The
    # def-site is in the set because the index carries it as an occurrence
    # of its own (6.3.1) -- a pattern binder is not an occurrence at all.
    mine_all = [("Refs.e", 8, 6, 10), ("Refs.e", 9, 5, 9),
                ("Refs.e", 9, 14, 18), ("Refs.e", 9, 22, 26)]
    client.seen = []
    r = references("Refs.e", 8, 6)
    check("references on a local: def + 3 uses, exact ranges",
          spans(r) == mine_all, repr(spans(r)))
    check("references on a local sends NO coverage warning", warnings() == [])
    r = references("Refs.e", 9, 14, include=False)
    check("references on a local without the declaration: 3 uses",
          spans(r) == mine_all[1:], repr(spans(r)))
    r = references("Refs.e", 9, 22)
    check("references from a use answers the same set as from the def-site",
          spans(r) == mine_all, repr(spans(r)))

    hs = highlight("Refs.e", 9, 14)
    check("highlight a local: one Write at the def-site, three Reads",
          kinds(hs) == [(8, 6, 10, 3), (9, 5, 9, 2), (9, 14, 18, 2), (9, 22, 26, 2)],
          repr(kinds(hs)))

    check("prepareRename on a local: its range and its spelling",
          prepare_rename("Refs.e", 9, 14) ==
          {"range": {"start": {"line": 9, "character": 14},
                     "end": {"line": 9, "character": 18}},
           "placeholder": "mine"},
          repr(prepare_rename("Refs.e", 9, 14)))

    # A GLOBAL: `shared`, defined in Refs.e and imported by RefsSib.e.  The
    # set spans both OPEN buffers -- signature mention, equation head, use,
    # the `import Refs using shared` list entry, and the sibling's two uses.
    shared_all = [("Refs.e", 4, 0, 6), ("Refs.e", 5, 0, 6), ("Refs.e", 11, 8, 14),
                  ("RefsSib.e", 2, 18, 24), ("RefsSib.e", 4, 12, 18),
                  ("RefsSib.e", 5, 13, 19)]
    client.seen = []
    r = references("RefsSib.e", 4, 12)
    check("references on a top-level from the importing sibling: both files",
          spans(r) == shared_all, repr(spans(r)))
    check("references on a top-level: 3 in the defining file, 3 in the importer",
          len([x for x in spans(r) if x[0] == "Refs.e"]) == 3
          and len([x for x in spans(r) if x[0] == "RefsSib.e"]) == 3, repr(spans(r)))
    ws = warnings()
    check("the coverage warning arrives, once, as a Warning",
          len(ws) == 1 and ws[0]["type"] == 2
          and ws[0]["message"].startswith("Ermine: references searched in ")
          and ws[0]["message"].endswith("unopened importers are not searched"), repr(ws))
    r = references("Refs.e", 5, 0)
    check("references from the defining file answers the same set",
          spans(r) == shared_all, repr(spans(r)))
    warnings()
    r = references("Refs.e", 5, 0, include=False)
    check("references on a top-level without the declaration drops the head",
          spans(r) == [x for x in shared_all if x != ("Refs.e", 5, 0, 6)], repr(spans(r)))
    warnings()

    # Highlight is per-document by definition, so it stays inside Refs.e and
    # sends no warning.  The def-site of a sig+equations group is the LAST
    # equation (the renamer's rule), so the signature mention reads as a use.
    hs = highlight("Refs.e", 11, 8)
    check("highlight a top-level: this file only, Write at the equation head",
          kinds(hs) == [(4, 0, 6, 2), (5, 0, 6, 3), (11, 8, 14, 2)], repr(kinds(hs)))
    check("highlight sends no coverage warning", warnings() == [])

    # RENAME a local: an edit at every site, none anywhere else.  Then APPLY
    # them the way a client would and feed the result back: the file must
    # re-check clean and the renamed local must hover with the same type.
    check("hover the local before the rename",
          hoverline("Refs.e", 8, 6) == "mine : Bool", hoverline("Refs.e", 8, 6))
    client.seen = []
    r = rename("Refs.e", 9, 14, "flagged")
    check("rename a local: one file touched", "error" not in r
          and list(r["result"]["changes"].keys()) == [uri("Refs.e")], repr(r))
    es = edits_of(r, "Refs.e")
    check("rename a local: an edit at every site and nowhere else",
          [(e["range"]["start"]["line"], e["range"]["start"]["character"],
            e["range"]["end"]["character"]) for e in es]
          == [x[1:] for x in mine_all], repr(es))
    check("rename a local: every edit carries the new name",
          all(e["newText"] == "flagged" for e in es), repr(es))
    check("rename a local sends no coverage warning", warnings() == [])

    refs_src = (FIXTURES / "Refs.e").read_text()
    change("Refs.e", apply_edits(refs_src, es), 2)
    check("the renamed file re-checks clean",
          client.diagnostics_for(uri("Refs.e")) == [])
    check("the renamed local hovers with the same type",
          hoverline("Refs.e", 8, 6) == "flagged : Bool", hoverline("Refs.e", 8, 6))
    check("the old name is gone from the buffer the edits produced",
          "mine" not in apply_edits(refs_src, es))
    change("Refs.e", refs_src, 3)
    check("Refs.e clean again after the revert",
          client.diagnostics_for(uri("Refs.e")) == [])

    # THE REFUSALS (Decision d).  Each is a ResponseError with a message a
    # person can act on, and none of them is ever a partial edit.
    def refusal(what, name, line, char, new, code):
        r = rename(name, line, char, new)
        check("rename refused: " + what,
              "result" not in r and r.get("error", {}).get("code") == code,
              repr(r.get("error")))
        return r.get("error", {}).get("message", "")

    m = refusal("a capturing name (bound where the local is used)",
                "Refs.e", 9, 14, "b", -32803)
    check("the capture refusal names the new name", "'b' is already bound" in m, m)
    m = refusal("a name that is already a top level of the module",
                "Refs.e", 9, 14, "shared", -32803)
    check("the top-level clash refusal names it", "'shared' is already" in m, m)
    m = refusal("a wrong-case name (a term must stay lower-case)",
                "Refs.e", 9, 14, "Mine", -32602)
    check("the case refusal says which case", "lower-case" in m, m)
    m = refusal("renaming TO an operator", "Refs.e", 9, 14, "&&&", -32602)
    check("the operator refusal names the spelling", "'&&&'" in m, m)
    m = refusal("renaming FROM an operator", "Refs.e", 5, 13, "andy", -32602)
    check("the operator refusal explains why", "fixity" in m, m)
    m = refusal("a name defined in a file that is not open (a stdlib name)",
                "Refs.e", 5, 16, "Yes", -32803)
    check("the unopened-def-site refusal says so",
          "not open" in m, m)
    warnings()

    check("prepareRename on an operator -> null", prepare_rename("Refs.e", 5, 13) is None)
    check("prepareRename off a name -> null", prepare_rename("Refs.e", 6, 0) is None)

    # RENAME a top level across two open buffers: edits in both, the
    # `import Refs using shared` mention included, plus the warning.
    client.seen = []
    r = rename("Refs.e", 5, 0, "combined")
    check("rename a top-level: both buffers are edited", "error" not in r
          and sorted(r["result"]["changes"].keys())
              == sorted([uri("Refs.e"), uri("RefsSib.e")]), repr(r))
    es_home = edits_of(r, "Refs.e")
    es_sib = edits_of(r, "RefsSib.e")
    check("rename a top-level: three edits in the defining file",
          [(e["range"]["start"]["line"], e["range"]["start"]["character"]) for e in es_home]
          == [(4, 0), (5, 0), (11, 8)], repr(es_home))
    check("rename a top-level: three edits in the importer",
          [(e["range"]["start"]["line"], e["range"]["start"]["character"]) for e in es_sib]
          == [(2, 18), (4, 12), (5, 13)], repr(es_sib))
    check("rename a top-level edits the import list mention",
          es_sib[0]["range"]["end"]["character"] == 24
          and es_sib[0]["newText"] == "combined", repr(es_sib[0]))
    ws = warnings()
    check("rename a global sends the coverage warning too",
          len(ws) == 1 and ws[0]["type"] == 2
          and "unopened importers are not searched" in ws[0]["message"], repr(ws))

    # STALE INDEX (Decision d): a keystroke arrives, the debounced check has
    # not run, and the index describes text that is gone.  Refuse -- never a
    # partial or misplaced edit.
    change("Refs.e", refs_src.replace("quiet =", "quiet2 ="), 4)
    r = rename("Refs.e", 9, 14, "flagged")
    check("rename on a stale index -> check pending",
          "result" not in r and r.get("error", {}).get("code") == -32803
          and "check pending" in r.get("error", {}).get("message", ""),
          repr(r.get("error")))
    check("the pending check then runs and the file is clean",
          client.diagnostics_for(uri("Refs.e")) == [])
    r = rename("Refs.e", 9, 14, "flagged")
    check("the same rename succeeds once the check has caught up",
          "error" not in r and len(edits_of(r, "Refs.e")) == 4, repr(r))
    change("Refs.e", refs_src, 5)
    check("Refs.e clean after the second revert",
          client.diagnostics_for(uri("Refs.e")) == [])
    warnings()

    # --- 6.3 fix round: the review's three holes ----------------------
    # R2 — a backtick LITERAL identifier spells `wide` and is written
    # ``wide``: eight characters, starting two before the spelling.
    # Measured from the SOURCE now, and refused for rename rather than
    # re-wrapped (whether the NEW name needs backticks is a grammar
    # question, and the literal form carries its own escapes).
    open_doc("Lit.e")
    check("Lit.e clean", client.diagnostics_for(uri("Lit.e")) == [])
    r = references("Lit.e", 4, 2)
    check("references on a ``literal`` name cover the WHOLE token",
          spans(r) == [("Lit.e", 4, 0, 8), ("Lit.e", 6, 10, 18)], repr(spans(r)))
    hs = highlight("Lit.e", 6, 12)
    check("highlight a ``literal`` name: Write at the def, Read at the use",
          kinds(hs) == [(4, 0, 8, 3), (6, 10, 18, 2)], repr(kinds(hs)))
    check("prepareRename on a ``literal`` name -> null",
          prepare_rename("Lit.e", 6, 12) is None)
    r = rename("Lit.e", 6, 12, "narrow")
    check("rename a ``literal`` name is REFUSED, not mis-measured",
          "result" not in r and r.get("error", {}).get("code") == -32803
          and "not its spelling" in r.get("error", {}).get("message", ""),
          repr(r.get("error")))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Lit.e")}})
    client.diagnostics_for(uri("Lit.e"))

    # R1 — a RE-EXPORT used to split the key: `Prelude` exports `Bool`, so
    # a use of `not` reached through `Prelude` arrived as `Prelude.not`
    # while `Bool.e`'s own binder keyed on `Bool.not`.  Renaming from
    # either end silently broke the other.  The key is canonicalised to
    # the DEFINING module now, so both ends see one name.
    boolmod = repo("core/src/main/resources/modules/Bool.e")
    bool_uri = boolmod.as_uri()
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": bool_uri, "languageId": "ermine", "version": 1,
        "text": boolmod.read_text()}})
    check("Bool.e clean on open", client.diagnostics_for(bool_uri) == [])
    open_doc("RefsPre.e")
    check("RefsPre.e (import Prelude) clean",
          client.diagnostics_for(uri("RefsPre.e")) == [])

    not_all = [("Bool.e", 18, 0, 3), ("Bool.e", 19, 0, 3), ("Bool.e", 20, 0, 3),
               ("RefsPre.e", 4, 10, 13)]
    r = references("RefsPre.e", 4, 10)
    check("references across a re-export, from the importer: both files",
          spans(r) == not_all, repr(spans(r)))
    warnings()
    # Bool.e is not in the fixtures directory, so it needs its own uri.
    rid = client.request("textDocument/references", {
        "textDocument": {"uri": bool_uri}, "position": {"line": 20, "character": 0},
        "context": {"includeDeclaration": True}})
    r = client.response(rid).get("result")
    check("references across a re-export, from the DEFINING module: both files",
          spans(r) == not_all, repr(spans(r)))
    warnings()

    def rename_at(u, line, char, new):
        rid = client.request("textDocument/rename", {
            "textDocument": {"uri": u}, "position": {"line": line, "character": char},
            "newName": new})
        return client.response(rid)

    r = rename_at(bool_uri, 20, 0, "nope")
    check("rename across a re-export from the defining module edits BOTH",
          "error" not in r
          and sorted(k.rsplit("/", 1)[1] for k in r["result"]["changes"])
              == ["Bool.e", "RefsPre.e"], repr(r.get("error") or r["result"]["changes"].keys()))
    from_def = r.get("result", {}).get("changes")
    r = rename_at(uri("RefsPre.e"), 4, 10, "nope")
    check("rename across a re-export from the IMPORTER is not refused as "
          "'defined in a file that is not open'",
          "error" not in r, repr(r.get("error")))
    check("both directions produce the same edit", from_def == r.get("result", {}).get("changes"),
          repr(from_def))
    warnings()
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("RefsPre.e")}})
    client.diagnostics_for(uri("RefsPre.e"))
    client.notify("textDocument/didClose", {"textDocument": {"uri": bool_uri}})
    client.diagnostics_for(bool_uri)
    check("Bool.e on disk untouched by the rename", boolmod.read_text().count("not ") > 0
          and "nope" not in boolmod.read_text())

    # R3 — the stale-index refusal used to look only at documents that
    # already had a hit, so a sibling edited since its last check but not
    # YET mentioning the name was neither refused nor edited.  Every open
    # document is version-checked for a GLOBAL rename now; a local still
    # checks only its own.
    r = rename("Refs.e", 13, 0, "apex")
    check("rename a top-level nothing else mentions: one edit",
          "error" not in r and edits_of(r, "Refs.e")
             == [{"range": {"start": {"line": 13, "character": 0},
                            "end": {"line": 13, "character": 8}},
                  "newText": "apex"}], repr(r))
    warnings()
    sib_src = (FIXTURES / "RefsSib.e").read_text()
    change("RefsSib.e", sib_src + "\nuseTop = True\n", 7)
    r = rename("Refs.e", 13, 0, "apex")
    check("a global rename is refused while ANY open buffer is stale",
          "result" not in r and r.get("error", {}).get("code") == -32803
          and "check pending" in r.get("error", {}).get("message", ""),
          repr(r.get("error")))
    check("the refusal names the stale sibling, not the file being renamed",
          "RefsSib.e" in r.get("error", {}).get("message", ""),
          r.get("error", {}).get("message", ""))
    # ... and a LOCAL rename is NOT blocked by it: a local cannot leave
    # its own file, so a stale sibling can hold no mention of it.
    r = rename("Refs.e", 9, 14, "flagged")
    check("a local rename is not blocked by a stale sibling",
          "error" not in r and len(edits_of(r, "Refs.e")) == 4, repr(r.get("error")))
    client.diagnostics_for(uri("RefsSib.e"))
    change("RefsSib.e", sib_src, 8)
    check("RefsSib.e clean after the revert",
          client.diagnostics_for(uri("RefsSib.e")) == [])
    r = rename("Refs.e", 13, 0, "apex")
    check("the global rename succeeds once every buffer has caught up",
          "error" not in r and len(edits_of(r, "Refs.e")) == 1, repr(r.get("error")))
    warnings()

    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("RefsSib.e")}})
    client.diagnostics_for(uri("RefsSib.e"))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Refs.e")}})
    client.diagnostics_for(uri("Refs.e"))

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
    # 6.2: a local's type is a product of the CHECK, so in fast mode the
    # same hover that answered `flag : Bool` answers null -- nothing
    # computes it.  A type name's KIND comes from the session's `Con`
    # table, so an IMPORTED one still answers; this module's own types
    # are installed by the check, so they do not.
    client.notify("textDocument/didSave", {"textDocument": {"uri": uri("Locals.e")}})
    client.diagnostics_for(uri("Locals.e"))
    check("fast mode: hover on a local -> null", hover("Locals.e", 10, 6) is None)
    check("fast mode keeps the imported type's kind",
          hoverline("Locals.e", 8, 11) == "Builtin.Bool : *", hoverline("Locals.e", 8, 11))

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
