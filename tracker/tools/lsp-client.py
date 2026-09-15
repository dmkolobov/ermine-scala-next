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
import re
import subprocess
import sys
import urllib.parse
import time

HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE.parent / "lsp-tests"
LOG = os.environ.get("LSP_SMOKE_LOG", "/tmp/lsp-smoke.log")

checks = 0
failures = []


def _query_ms(fn, *args):
    """One request's round trip in milliseconds (6.4: the workspace-symbol
    cost budget is measured, not asserted from the log)."""
    t0 = time.perf_counter()
    fn(*args)
    return (time.perf_counter() - t0) * 1000.0


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
    # 6.4: document symbols and workspace symbols.
    check("initialize.documentSymbolProvider",
          caps.get("documentSymbolProvider") is True)
    check("initialize.workspaceSymbolProvider",
          caps.get("workspaceSymbolProvider") is True)
    # 6.5: completion, with `.` as the one trigger character and no resolve.
    check("initialize.completionProvider",
          caps.get("completionProvider") ==
          {"triggerCharacters": ["."], "resolveProvider": False},
          repr(caps.get("completionProvider")))
    # 6.6: quick fixes, in the two kinds this server actually serves.
    check("initialize.codeActionProvider",
          caps.get("codeActionProvider") ==
          {"codeActionKinds": ["quickfix", "source"]},
          repr(caps.get("codeActionProvider")))
    sync = caps.get("textDocumentSync", {})
    # 5.3: TextDocumentSync FULL — didChange carries the whole document
    check("initialize.sync", sync.get("openClose") is True and sync.get("save") is True
          and sync.get("change") == 1, repr(sync))

    # 6.4.3: a request that arrives before the session exists answers at
    # once with an EMPTY LIST -- never null, never a wait.  Sent before
    # `initialized`, so the resident session has not begun to boot.
    rid = client.request("workspace/symbol", {"query": "not"})
    check("workspace/symbol before the session boots -> []",
          client.response(rid).get("result") == [])
    rid = client.request("textDocument/documentSymbol",
                         {"textDocument": {"uri": uri("Good.e")}})
    check("documentSymbol before any check -> []",
          client.response(rid).get("result") == [])
    # 6.5: the same rule for completion -- an empty list, never null, and
    # never a wait behind the ~13s boot.
    rid = client.request("textDocument/completion",
                         {"textDocument": {"uri": uri("Complete.e")},
                          "position": {"line": 10, "character": 14}})
    check("completion before the session boots -> []",
          client.response(rid).get("result") == [])
    # 6.6: and the same for a code action -- an EMPTY LIST, at once.
    rid = client.request("textDocument/codeAction",
                         {"textDocument": {"uri": uri("Fix.e")},
                          "range": {"start": {"line": 9, "character": 0},
                                    "end": {"line": 9, "character": 0}},
                          "context": {"diagnostics": []}})
    check("codeAction before the session boots -> []",
          client.response(rid).get("result") == [])

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
    # TREE-DISTINGUISHING since 7.5 (ticket E9): `endswith("/Bool.e")` was
    # true of the BUILD OUTPUT copy the session loads from and could not see
    # the bug; `/resources/modules/` is only true of the source tree.
    check("def && -> Bool.e", r is not None
          and r["uri"].endswith("/resources/modules/Bool.e")
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

    # --- ermine/schema (JSON API Stage 1b, tracker/JSON-API-DESIGN.md §3.5) ---
    def schema(params):
        rid = client.request("ermine/schema", params)
        return client.response(rid).get("result")

    r = schema({"module": "Ord", "type": "Ordering"})
    check("ermine/schema exports an enum from the resident session",
          r is not None and r.get("$id") == "ermine:Ord/Ordering"
          and r.get("$defs", {}).get("Ord.Ordering", {}).get("enum") == ["LT", "EQ", "GT"],
          repr(r))
    r = schema({"module": "Either", "name": "Either"})
    check("ermine/schema refuses an uninstantiated parameterised type",
          r is not None and "error" in r and "type arguments" in r["error"], repr(r))
    r = schema({"module": "Either", "type": "Either String Int"})
    check("ermine/schema exports an instantiation as a tagged union",
          r is not None
          and "oneOf" in r.get("$defs", {}).get("Either.Either_String_Int", {}),
          repr(r))
    r = schema({"type": "Ordering"})
    check("ermine/schema without a module is an error object",
          r is not None and "module" in r.get("error", ""), repr(r))

    r = definition("Decls.e", 18, 14)    # `Left`, a constructor from Either.e
    check("def imported constructor -> Either.e", r is not None
          and r["uri"].endswith("/resources/modules/Either.e"), repr(r))
    r = definition("Decls.e", 19, 13)    # `yyyymmdd`, a foreign function
    check("def foreign function -> Date.e", r is not None
          and r["uri"].endswith("/resources/modules/Date.e"), repr(r))

    r = definition("Decls.e", 20, 11)    # `Alias` in the signature
    check("def own type alias -> its statement", r is not None
          and r["uri"] == uri("Decls.e")
          and r["range"]["start"] == {"line": 13, "character": 5}, repr(r))
    r = definition("Decls.e", 22, 12)    # `Either` in the signature
    check("def imported type -> Either.e", r is not None
          and r["uri"].endswith("/resources/modules/Either.e"), repr(r))
    r = definition("Decls.e", 11, 5)     # the `Shape` head itself
    check("def type head -> itself", r is not None
          and r["range"]["start"] == {"line": 11, "character": 5}, repr(r))

    r = definition("Decls.e", 6, 9)      # `<+>` named in its fixity declaration
    check("def fixity mention -> the equation", r is not None
          and r["uri"] == uri("Decls.e")
          and r["range"]["start"] == {"line": 7, "character": 0}, repr(r))

    r = definition("Decls.e", 3, 8)      # `import Either`
    check("def import -> the module's file", r is not None
          and r["uri"].endswith("/resources/modules/Either.e")
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
    # ... and so does a signed LET binder (LET-1).  Until then the `let`
    # lowering dropped the signature, the binder was an ImplicitBinding,
    # and `headType` answered the INFERRED type -- which agreed here by
    # luck, so the fixture had no signed `let` at all and nothing pinned
    # Decision (a) for one.  The three positions are the signature, the
    # equation head and a use.
    check("hover signed let binder at its signature",
          hoverline("Locals.e", 38, 6) == "slet : Bool -> Bool", hoverline("Locals.e", 38, 6))
    check("hover signed let binder at its def-site",
          hoverline("Locals.e", 39, 6) == "slet : Bool -> Bool", hoverline("Locals.e", 39, 6))
    check("hover signed let binder at a use",
          hoverline("Locals.e", 40, 5) == "slet : Bool -> Bool", hoverline("Locals.e", 40, 5))
    # a polymorphic where-bound helper.  6.2c: a local head hovers the
    # SCHEME the checker published for it, quantifier and all -- the same
    # rendering a TOP-LEVEL head has always had (`Locals.konst` below).
    # Until 6.2c it hovered the pre-generalisation rho, `a -> a`, which is
    # also how a monotype in an unsolved meta prints.
    check("hover polymorphic where binder",
          hoverline("Locals.e", 21, 8) == "idy : forall a. a -> a", hoverline("Locals.e", 21, 8))
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
    # --- 6.2b: the pattern binders the arity split cannot reach ----------
    # The first two REPLACE 6.2's `hover case binder -> null` and
    # `hover case-bound use -> null`, which were written to fail the day
    # the `Subst` hook landed (6.2 review R-5).  Until it did, a `case`
    # binder, a lambda argument, a `do` binder and a var nested in a
    # constructor or tuple pattern all answered null, because
    # `Lower.pattern` throws the binder's meta away and
    # `inferPatternType` mints one nothing this side holds.  `SubstEnv.binderTypes` records it where it is minted
    # and keeps it substituted, so each answers its own type now -- at its
    # def-site AND at a use.
    check("hover case binder at its def-site",
          hoverline("Locals.e", 26, 9) == "r : Bool", hoverline("Locals.e", 26, 9))
    check("hover case binder at a use",
          hoverline("Locals.e", 26, 14) == "r : Bool", hoverline("Locals.e", 26, 14))
    # a LAMBDA argument
    check("hover lambda argument at its def-site",
          hoverline("Locals.e", 42, 12) == "m : Bool", hoverline("Locals.e", 42, 12))
    check("hover lambda argument at a use",
          hoverline("Locals.e", 42, 17) == "m : Bool", hoverline("Locals.e", 42, 17))
    # a var nested inside a CONSTRUCTOR pattern
    check("hover var nested in a ConP at its def-site",
          hoverline("Locals.e", 45, 9) == "inner : Bool", hoverline("Locals.e", 45, 9))
    check("hover var nested in a ConP at a use",
          hoverline("Locals.e", 45, 18) == "inner : Bool", hoverline("Locals.e", 45, 18))
    # ... and inside a TUPLE pattern, both components
    check("hover var nested in a tuple pattern",
          hoverline("Locals.e", 49, 3) == "tfst : Bool", hoverline("Locals.e", 49, 3))
    check("hover the tuple's second var at a use",
          hoverline("Locals.e", 49, 26) == "tsnd : Bool", hoverline("Locals.e", 49, 26))
    # an AS-pattern: the outer var is the whole pattern's type, the inner
    # var is the constructor field's
    check("hover as-pattern outer var",
          hoverline("Locals.e", 52, 2) == "whole : Shape", hoverline("Locals.e", 52, 2))
    check("hover as-pattern inner var at its def-site",
          hoverline("Locals.e", 52, 16) == "wrapped : Bool", hoverline("Locals.e", 52, 16))
    check("hover as-pattern inner var at a use",
          hoverline("Locals.e", 52, 28) == "wrapped : Bool", hoverline("Locals.e", 52, 28))
    # --- 6.2c: the local HEAD hovers what the checker PUBLISHED --------
    # Ticket E14.  `Subst.inferImplicitBindingTypes` binds Lower's meta to
    # the PRE-GENERALISATION rho, and the `generalize` that follows moves
    # the deferred constraints into the scheme and leaves the rho behind --
    # so a constrained local hovered `List a -> a -> a` while the checker
    # held `forall a. PrimitiveNum a => List a -> a -> a`, beside the
    # hook's `h : Int` in the same three lines.  The scheme is recorded
    # where it is published (`SubstEnv.headTypes`) and hover reads it.
    open_doc("Heads.e")
    heads_ds = client.diagnostics_for(uri("Heads.e"))
    check("Heads.e clean", heads_ds == [], repr(heads_ds))
    check("hover a CONSTRAINED local head at its def-site",
          hoverline("Heads.e", 9, 6) == "go : forall a. PrimitiveNum a => List a -> a -> a",
          hoverline("Heads.e", 9, 6))
    check("hover the same head at a use",
          hoverline("Heads.e", 11, 5) == "go : forall a. PrimitiveNum a => List a -> a -> a",
          hoverline("Heads.e", 11, 5))
    # the arity split inherits: the argument is peeled from the head's own
    # type and printed in the head's frame, so its letter is the head's
    check("hover its argument, in the head's frame",
          hoverline("Heads.e", 9, 16) == "acc : a", hoverline("Heads.e", 9, 16))
    # the hook's answers for the SAME let, which are the single instance
    # the body takes -- the second frame, left standing (6.2c follow-up 1)
    check("hover the hook's answer beside it",
          hoverline("Heads.e", 10, 10) == "h : Int", hoverline("Heads.e", 10, 10))
    # the controls: a head mentioning a variable the body fixes LATER
    # still shows the settled type, and a settled local is unchanged
    check("hover a head whose variable is fixed later",
          hoverline("Heads.e", 15, 6) == "gl : forall a. a -> (a, Int)",
          hoverline("Heads.e", 15, 6))
    check("hover a local whose type is settled outright",
          hoverline("Heads.e", 20, 6) == "zl : Int", hoverline("Heads.e", 20, 6))
    # Decision (a): a SIGNED local head still shows its declaration
    check("hover a signed local head",
          hoverline("Heads.e", 26, 6) == "sg : Int -> Int", hoverline("Heads.e", 26, 6))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Heads.e")}})
    client.diagnostics_for(uri("Heads.e"))

    # a `do` binder, which lowers to a lambda argument of `Syntax.Do.bind`
    open_doc("LocalsDo.e")
    do_ds = client.diagnostics_for(uri("LocalsDo.e"))
    check("LocalsDo.e clean", do_ds == [], repr(do_ds))
    check("hover do binder at its def-site",
          hoverline("LocalsDo.e", 6, 2) == "dres : Bool", hoverline("LocalsDo.e", 6, 2))
    check("hover do binder at a use",
          hoverline("LocalsDo.e", 7, 8) == "dres : Bool", hoverline("LocalsDo.e", 7, 8))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("LocalsDo.e")}})
    client.diagnostics_for(uri("LocalsDo.e"))

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

    # --- 6.4: document symbols and workspace symbols --------------------
    # Both answer from what the LAST CHECK stored: the hierarchical tree is
    # built on the check path from the surface statements and rendered here,
    # and the workspace list is the open documents' own declarations plus a
    # list of the resident session's globals built ONCE after boot.  No
    # parse, no check, no inference is reachable from either request.
    def doc_symbols(name):
        rid = client.request("textDocument/documentSymbol",
                             {"textDocument": {"uri": uri(name)}})
        return client.response(rid).get("result")

    def ws_symbols(query):
        rid = client.request("workspace/symbol", {"query": query})
        return client.response(rid).get("result")

    def tree(syms):
        """(name, kind, range, selectionRange, children) as plain tuples, so
        a change in ANY of them shows up as one diff."""
        return [(s["name"], s["kind"],
                 (s["range"]["start"]["line"], s["range"]["start"]["character"],
                  s["range"]["end"]["line"], s["range"]["end"]["character"]),
                 (s["selectionRange"]["start"]["line"],
                  s["selectionRange"]["start"]["character"],
                  s["selectionRange"]["end"]["character"]),
                 tree(s.get("children", [])))
                for s in syms]

    def detail_of(syms, name):
        for s in syms:
            if s["name"] == name:
                return s.get("detail")
            d = detail_of(s.get("children", []), name)
            if d is not None:
                return d
        return None

    open_doc("Decls.e")
    check("Decls.e clean for the symbol pin",
          client.diagnostics_for(uri("Decls.e")) == [])
    decls = doc_symbols("Decls.e")
    # THE PIN.  Imports first (Module), then the fixity's operator merged
    # into its equation, the two `field` names sharing their statement's
    # range, the data statement with its constructors as CHILDREN, the type
    # alias, and one symbol per term group -- `useAlias` and `useEither`
    # each spanning their signature AND their equation while selecting the
    # equation's head.
    check("Decls.e symbol tree", tree(decls) == [
        ("Prelude",   2, (2, 0, 2, 14), (2, 7, 14), []),
        ("Either",    2, (3, 0, 3, 13), (3, 7, 13), []),
        ("Date",      2, (4, 0, 4, 11), (4, 7, 11), []),
        ("<+>",      12, (7, 0, 7, 17), (7, 0, 5), []),
        ("fa",        8, (9, 0, 9, 18), (9, 6, 8), []),
        ("fb",        8, (9, 0, 9, 18), (9, 10, 12), []),
        ("Shape",    23, (11, 0, 11, 36), (11, 5, 10), [
            ("Circle", 9, (11, 15, 11, 24), (11, 15, 21), []),
            ("Square", 9, (11, 26, 11, 36), (11, 26, 32), [])]),
        ("Alias",     5, (13, 0, 13, 22), (13, 5, 10), []),
        ("useOp",    13, (15, 0, 15, 15), (15, 0, 5), []),
        ("useFa",    13, (16, 0, 16, 10), (16, 0, 5), []),
        ("useCircle", 13, (17, 0, 17, 20), (17, 0, 9), []),
        ("useImported", 13, (18, 0, 18, 20), (18, 0, 11), []),
        ("useForeign", 13, (19, 0, 19, 30), (19, 0, 10), []),
        ("useAlias", 13, (20, 0, 21, 19), (21, 0, 8), []),
        ("useEither", 13, (22, 0, 24, 0), (23, 0, 9), []),
    ], repr(tree(decls)))
    # `detail` is the CHECKED type, printed the way hover prints it, with
    # the fixity declaration folded in (a fixity is a property of the
    # operator's symbol, not a symbol of its own).
    check("detail: the operator's checked type and its fixity",
          detail_of(decls, "<+>") == "forall a. Num a => a -> a -> a  infixl 6",
          repr(detail_of(decls, "<+>")))
    check("detail: a constructor's type comes from the env",
          detail_of(decls, "Circle") == "forall a. a -> Shape a",
          repr(detail_of(decls, "Circle")))
    check("detail: a field's type", detail_of(decls, "fa") == "Field (|fa|) Int",
          repr(detail_of(decls, "fa")))
    check("no symbol carries an empty name",
          all(s[0] for s in tree(decls)))

    # A BROKEN file lists its healthy statements and says nothing about the
    # broken ones -- their diagnostic is the answer they get.
    open_doc("Broken.e")
    check("Broken.e still reports its two errors",
          len(client.diagnostics_for(uri("Broken.e"))) == 2)
    broken = doc_symbols("Broken.e")
    check("a broken file lists its healthy symbols only", tree(broken) == [
        ("Good",  2, (2, 0, 2, 11), (2, 7, 11), []),
        ("good1", 13, (4, 0, 4, 14), (4, 0, 5), []),
        ("good2", 13, (6, 0, 6, 13), (6, 0, 5), []),
        ("good3", 13, (8, 0, 9, 0), (8, 0, 5), []),
    ], repr(tree(broken)))
    check("no symbol for a broken statement",
          not [s for s in broken if s["name"].startswith("bad")], repr(broken))

    # Every OTHER statement kind, on a fixture that checks clean: an all-
    # nullary `data` is an Enum and one with fields a Struct, a `type` alias
    # and a `foreign data` are Classes, a `private` block is a Namespace
    # whose members are its children, and a `foreign` block is a Module.
    open_doc("Syms.e")
    check("Syms.e clean", client.diagnostics_for(uri("Syms.e")) == [])
    syms = doc_symbols("Syms.e")
    check("Syms.e symbol tree", tree(syms) == [
        ("Prelude",     2, (2, 0, 2, 14), (2, 7, 14), []),
        ("SymName",     5, (6, 0, 6, 28), (6, 5, 12), []),
        ("SymColor",   10, (8, 0, 8, 43), (8, 5, 13), [
            ("SymRed",   9, (8, 16, 8, 23), (8, 16, 22), []),
            ("SymGreen", 9, (8, 25, 8, 34), (8, 25, 33), []),
            ("SymBlue",  9, (8, 36, 8, 43), (8, 36, 43), [])]),
        ("SymBox",     23, (10, 0, 10, 24), (10, 5, 11), [
            ("SymBox",   9, (10, 16, 10, 24), (10, 16, 22), [])]),
        ("symLabel",    8, (12, 0, 12, 23), (12, 6, 14), []),
        ("symNullary", 13, (14, 0, 14, 14), (14, 0, 10), []),
        ("<^>",        12, (16, 0, 16, 17), (16, 0, 5), []),
        ("symBoth",    13, (18, 0, 19, 11), (19, 0, 7), []),
        ("symAlsoBoth", 13, (20, 0, 20, 15), (20, 0, 11), []),
        ("private",     3, (22, 0, 26, 0), (22, 0, 7), [
            ("symHelper", 12, (23, 2, 24, 21), (24, 2, 11), [])]),
        ("foreign",     2, (26, 0, 31, 0), (26, 0, 7), [
            ("SymFile",   5, (27, 2, 27, 29), (27, 22, 29), []),
            ("symFile#",  9, (28, 2, 28, 42), (28, 14, 22), []),
            ("symName#", 12, (29, 2, 29, 47), (29, 19, 27), [])]),
        ("private",     3, (31, 0, 33, 0), (31, 0, 7), [
            ("foreign",   2, (31, 0, 33, 0), (31, 0, 7), [
                ("symPath#", 12, (32, 2, 32, 47), (32, 19, 27), [])])]),
    ], repr(tree(syms)))
    check("a foreign declaration's detail names its Java class",
          detail_of(syms, "SymFile") == "java.io.File", repr(detail_of(syms, "SymFile")))
    # A signature and its equations are ONE symbol: the range covers both,
    # and the selection is the equation's head.  A sig that names two names
    # is in the range of whichever group its equation is ADJACENT to: the
    # range is the contiguous run of a group's own statements around its
    # selection, so `symAlsoBoth`, whose equation is one statement further
    # down, starts at its equation and the two do not straddle.
    check("a sig and its equation merge into one symbol",
          [s for s in syms if s["name"] == "symBoth"][0]["range"]["start"]["line"] == 18)

    # F1/F2: the range is the CONTIGUOUS RUN of a group's own statements
    # that holds its selection.  A block of signatures followed by a block
    # of equations therefore yields one symbol per equation line and no
    # straddling siblings; and a group whose equation is inside a `private`
    # block lives THERE, with its top-level signature outside its range,
    # instead of leaving an empty namespace beside a top-level symbol whose
    # name is inside it.
    open_doc("Scope.e")
    check("Scope.e clean", client.diagnostics_for(uri("Scope.e")) == [])
    scope = doc_symbols("Scope.e")
    check("Scope.e symbol tree", tree(scope) == [
        ("Prelude", 2, (2, 0, 2, 14), (2, 7, 14), []),
        ("stairA", 13, (6, 0, 6, 10), (6, 0, 6), []),
        ("stairB", 13, (7, 0, 7, 10), (7, 0, 6), []),
        ("private", 3, (11, 0, 14, 0), (11, 0, 7), [
            ("hidden", 13, (12, 2, 12, 12), (12, 2, 8), []),
            ("helper", 13, (13, 2, 13, 12), (13, 2, 8), [])]),
    ], repr(tree(scope)))

    def straddles(syms):
        """Sibling pairs that overlap without being identical, at any level.
        Ranges are half-open, so touching at one point is not an overlap;
        IDENTICAL ranges are the legitimate multi-name-statement case."""
        def span(x):
            return ((x["range"]["start"]["line"], x["range"]["start"]["character"]),
                    (x["range"]["end"]["line"], x["range"]["end"]["character"]))
        out = []
        for i, a in enumerate(syms):
            sa, ea = span(a)
            for b in syms[i + 1:]:
                sb, eb = span(b)
                if sa < eb and sb < ea and (sa, ea) != (sb, eb):
                    out.append((a["name"], b["name"]))
        for a in syms:
            out += straddles(a.get("children", []))
        return out

    for name, t in [("Scope.e", scope), ("Syms.e", syms), ("Decls.e", decls)]:
        check("no sibling ranges straddle in " + name, straddles(t) == [],
              repr(straddles(t)))

    open_doc("Nav.e")
    client.diagnostics_for(uri("Nav.e"))

    # --- workspace/symbol ----------------------------------------------
    r = ws_symbols("twice")
    check("workspace query finds a top level of an open buffer",
          len(r) == 1 and r[0]["name"] == "twice" and r[0]["kind"] == 12
          and r[0]["containerName"] == "Nav" and r[0]["location"]["uri"] == uri("Nav.e")
          and r[0]["location"]["range"]["start"] == {"line": 5, "character": 0},
          repr(r))

    # The session's own globals, found in their SOURCE .e files (Decision 5
    # keeps the resident session interface-free, so a stdlib Loc is a real
    # source position and never .ei text).
    r = ws_symbols("Relation")
    soft = [s for s in r if s["name"] == "SoftRelation" and s["kind"] == 23]
    check("a stdlib TYPE is found in its source .e", len(soft) == 1
          and soft[0]["location"]["uri"].endswith(
              "/resources/modules/Layout/Report/SoftRelation.e")
          and soft[0]["containerName"] == "Layout.Report.SoftRelation", repr(soft))
    rel = [s for s in r if s["name"] == "relation"]
    check("a stdlib TERM is found in its source .e", len(rel) == 1
          and rel[0]["location"]["uri"].endswith("/resources/modules/Relation.e")
          and rel[0]["containerName"] == "Relation" and rel[0]["kind"] == 12, repr(rel))
    # `Relation` the TYPE is a Scala-installed builtin (Type.scala's
    # relationT, Global("Builtin","Relation")) with Loc.builtin, so it has
    # no source and is NOT listed -- the same rule that drops `Just`.
    check("the builtin type `Relation` itself is not listed",
          not [s for s in r if s["name"] == "Relation"], repr(r))

    # Case-insensitive, and it reaches a type declared in a nested module.
    r = ws_symbols("sortorder")
    so = [s for s in r if s["name"] == "SortOrder"]
    check("a lower-case query finds an upper-case stdlib type", len(so) == 1
          and so[0]["kind"] == 23
          and so[0]["location"]["uri"].endswith(
              "/resources/modules/Relation/Sort.e"), repr(r))

    # A Scala-installed constructor has no source, so it is not a workspace
    # symbol; the SOURCE names that contain the same letters are.
    r = ws_symbols("just")
    check("the builtin constructor `Just` is NOT listed",
          not [s for s in r if s["name"] == "Just"], repr(r))
    check("but source names containing 'just' are",
          sorted(s["name"] for s in r) == ["getJust", "isJust"], repr(r))

    # Ranking: exact match, then prefix, then substring.
    r = ws_symbols("relation")
    names = [s["name"] for s in r]
    check("ranking: the exact match comes first", names[0] == "relation", repr(names))
    check("ranking: a prefix match beats a substring match",
          names.index("relationWithHeader") < names.index("fromRelation"), repr(names))

    # An open buffer's own declaration WINS over the session's copy of the
    # same module: deduped by (module, name).
    boolmod = repo("core/src/main/resources/modules/Bool.e")
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": boolmod.as_uri(), "languageId": "ermine", "version": 1,
        "text": boolmod.read_text()}})
    check("Bool.e clean for the dedupe check",
          client.diagnostics_for(boolmod.as_uri()) == [])
    # (`Relation.Predicate` defines a `not` of its own -- two modules, two
    # names, two entries; the dedupe key is (module, name), not the name.)
    r = [s for s in ws_symbols("not")
         if s["name"] == "not" and s["containerName"] == "Bool"]
    check("an open module is not listed twice", len(r) == 1
          and r[0]["location"]["uri"] == boolmod.as_uri(), repr(r))
    client.notify("textDocument/didClose",
                  {"textDocument": {"uri": boolmod.as_uri()}})
    client.diagnostics_for(boolmod.as_uri())

    # The EMPTY query is the open documents only: 2000 stdlib names are not
    # an answer to "show me everything".
    r = ws_symbols("")
    check("the empty query answers with the open buffers only",
          len(r) > 0 and not [s for s in r if "/modules/" in s["location"]["uri"]],
          repr([s["location"]["uri"] for s in r][:5]))
    # F4: a `private`/`database` block (Namespace 3) declares nothing, and
    # neither does an import or the `foreign` block (Module 2).  None of the
    # four is a workspace symbol -- `Syms.e` alone contributes two `private`
    # containers and a `foreign` one, and they used to leak.
    check("the empty query lists no container symbols",
          not [s for s in r if s["kind"] in (2, 3)], repr(r[:5]))
    check("but a declaration INSIDE a private block is listed",
          [s for s in r if s["name"] == "hidden" and s["containerName"] == "Scope"],
          repr([s["name"] for s in r]))

    # Capped at 200.
    check("results are capped at 200", len(ws_symbols("a")) == 200)

    # COST.  The session's name list is built once, after boot; a query is a
    # substring scan over it.  Take the best of five so a scheduling hiccup
    # cannot fail a bound that is about the ALGORITHM.
    best = min(_query_ms(ws_symbols, "relation") for _ in range(5))
    check("a workspace query is well under 50 ms (%.1f ms)" % best, best < 50.0)

    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Scope.e")}})
    client.diagnostics_for(uri("Scope.e"))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Syms.e")}})
    client.diagnostics_for(uri("Syms.e"))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Broken.e")}})
    client.diagnostics_for(uri("Broken.e"))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Decls.e")}})
    client.diagnostics_for(uri("Decls.e"))

    # --- 6.5: completion -----------------------------------------------
    # Every answer comes from the LAST CHECK'S TABLES (the renamer frames
    # `scopeAt` folds, 6.2's local types, 6.4's symbol tree, the
    # ModuleScope the check built) plus the CURRENT BUFFER TEXT, read
    # lexically on the request's own line for the word prefix and the
    # `import` / `Module.` / comment / string context.  No parse, no
    # check, no inference is reachable from the handler -- which is also
    # why a name typed since the last debounced check is NOT offered until
    # that check lands (the staleness pin at the end of this block).
    def complete(name, line, char):
        rid = client.request("textDocument/completion", {
            "textDocument": {"uri": uri(name)},
            "position": {"line": line, "character": char}})
        return client.response(rid).get("result")

    def labels(res):
        return [i["label"] for i in res["items"]]

    def one(res, label):
        for i in res["items"]:
            if i["label"] == label:
                return i
        return None

    def rank(res, label):
        for n, i in enumerate(res["items"]):
            if i["label"] == label:
                return n
        return -1

    open_doc("CompleteSib.e")
    check("CompleteSib.e clean", client.diagnostics_for(uri("CompleteSib.e")) == [])
    open_doc("Complete.e")
    check("Complete.e clean", client.diagnostics_for(uri("Complete.e")) == [])

    # (1) A LOCAL: an argument, offered inside its own equation with the
    # type 6.2's argument split gave it -- and offered NOWHERE else.
    r = complete("Complete.e", 10, 14)          # inside `arg` in `topFn arg = arg && True`
    check("completion: an argument is offered inside its equation",
          labels(r) == ["arg"], repr(labels(r)))
    check("completion: the argument's kind is Variable and its type is its detail",
          one(r, "arg") is not None and one(r, "arg")["kind"] == 6
          and one(r, "arg")["detail"] == "Bool", repr(one(r, "arg")))
    check("completion: a prefix-filtered answer is complete",
          r["isIncomplete"] is False)

    r = complete("Complete.e", 10, 11)          # empty prefix, same equation
    check("completion: an empty prefix answers locals + own only, isIncomplete",
          r["isIncomplete"] is True and "arg" in labels(r) and "topFn" in labels(r)
          and "not" not in labels(r), repr(labels(r)))
    check("completion: another equation's binders are not in scope",
          "helper" not in labels(r) and "inner" not in labels(r)
          and "h" not in labels(r), repr(labels(r)))

    # (2) A WHERE-BOUND name, in the body it scopes over and not outside.
    r = complete("Complete.e", 13, 10)          # inside `helper` in the where line
    check("completion: a where-bound is offered in its own block",
          labels(r) == ["helper"] and one(r, "helper")["detail"] == "Bool -> Bool",
          repr(r["items"]))
    r = complete("Complete.e", 13, 19)          # empty prefix inside the where body
    check("completion: the where body sees the where-bound, its argument and the equation's",
          "helper" in labels(r) and "h" in labels(r) and "b" in labels(r), repr(labels(r)))
    check("completion: the where body does NOT see another equation's argument",
          "arg" not in labels(r) and "inner" not in labels(r), repr(labels(r)))

    # (3) A LET-BOUND name, in its `in` and not outside the let.
    r = complete("Complete.e", 17, 7)           # `in inner`, prefix "in"
    check("completion: a let-bound is offered in the let body",
          "inner" in labels(r) and one(r, "inner")["detail"] == "Bool", repr(labels(r)))
    # ... and a KEYWORD with the same prefix, ranked below every name.
    check("completion: a keyword is offered and ranked last",
          one(r, "in") is not None and one(r, "in")["kind"] == 14
          and rank(r, "inner") < rank(r, "in"), repr(labels(r)))
    check("completion: the keyword tier is 3 in sortText",
          one(r, "in")["sortText"].startswith("3")
          and one(r, "inner")["sortText"].startswith("0"),
          repr([one(r, "in")["sortText"], one(r, "inner")["sortText"]]))
    r = complete("Complete.e", 17, 5)           # empty prefix in the let body
    check("completion: the let body sees the let-bound and the equation's argument",
          "inner" in labels(r) and "c" in labels(r), repr(labels(r)))
    check("completion: the let-bound does not escape its equation",
          "helper" not in labels(r) and "arg" not in labels(r), repr(labels(r)))

    # (4) AN OWN TOP-LEVEL, with the type the check gave it.
    r = complete("Complete.e", 21, 11)          # inside `topFn` in `useTop = topFn True`
    check("completion: an own top-level with its checked type",
          labels(r) == ["topFn"] and one(r, "topFn")["detail"] == "Bool -> Bool"
          and one(r, "topFn")["kind"] == 3, repr(r["items"]))

    # (5) AN OWN CONSTRUCTOR, from 6.4's symbol tree, ranked above the
    # imported names that share its prefix.
    r = complete("Complete.e", 5, 16)           # inside `Red` in the data statement
    check("completion: an own constructor with its type",
          one(r, "Red") is not None and one(r, "Red")["kind"] == 4
          and one(r, "Red")["detail"] == "Colour", repr(one(r, "Red")))
    check("completion: own outranks imported",
          rank(r, "Red") == 0 and rank(r, "Relation") > 0, repr(labels(r)))

    # (6) AN IMPORTED NAME with its type, and the ranking against a local
    # of the same prefix: the local first, the import after it.
    r = complete("Complete.e", 23, 28)          # inside `not` in `... in not n1`
    check("completion: an imported name with its type",
          one(r, "not") is not None and one(r, "not")["detail"] == "Bool -> Bool"
          and one(r, "not")["kind"] == 3, repr(one(r, "not")))
    check("completion: a local ranks above an imported name",
          rank(r, "n1") == 0 and rank(r, "n1") < rank(r, "not"), repr(labels(r)))
    check("completion: a case-insensitive match ranks below every exact one",
          rank(r, "Nil") > rank(r, "not")
          and one(r, "Nil")["sortText"].startswith("21"), repr(labels(r)))

    # (7) A SIBLING BUFFER'S EXPORT: CompleteSib is open and imported, and
    # its own `sibValue` is in this file's scope with its checked type.
    r = complete("Complete.e", 19, 12)          # inside `sibValue`
    check("completion: a sibling's export with its type",
          labels(r) == ["sibValue"] and one(r, "sibValue")["detail"] == "Bool",
          repr(r["items"]))

    # (8) A CURSOR IN A STRING answers nothing at all.
    r = complete("Complete.e", 25, 10)          # inside `msg = "not a name"`
    check("completion: a cursor inside a string literal answers []",
          r["items"] == [] and r["isIncomplete"] is False, repr(r))

    # (9) MODULE NAMES after `import`: the resident session's loaded
    # modules, the `.e` files under this file's module root, and the open
    # buffers' own modules.  Dotted, prefix-matched on the whole path.
    r = complete("CompleteSib.e", 3, 9)         # `import La|yout.Scan`
    check("completion: `import La` offers the Layout modules",
          "Layout" in labels(r) and "Layout.Scan" in labels(r)
          and one(r, "Layout")["kind"] == 9, repr(labels(r)[:6]))
    check("completion: `import La` offers modules only",
          all(x.startswith("La") for x in labels(r)) and "Bool" not in labels(r),
          repr(labels(r)[:6]))
    r = complete("CompleteSib.e", 3, 14)        # `import Layout.|Scan`
    check("completion: `import Layout.` offers the Layout.* modules",
          labels(r) and all(x.startswith("Layout.") for x in labels(r))
          and "Layout.Report" in labels(r), repr(labels(r)[:6]))
    # ... and with no prefix at all, every module the editor could name:
    # the ones this check loaded, the resident session's, and the `.e`
    # files under the module root (which is where these fixtures live).
    r = complete("CompleteSib.e", 3, 7)         # `import |Layout.Scan`
    check("completion: an empty module prefix offers the root's own files too",
          "Complete" in labels(r) and "CompleteSib" in labels(r)
          and "Prelude" in labels(r) and "Layout.Scan" in labels(r),
          repr(len(labels(r))))

    # (10) QUALIFIED `Module.`: the module's exports and nobody else's --
    # and, because a dotted reference does not parse in this grammar AT
    # ALL (`identTok` is tried before the dotted alternatives, so the `.`
    # is composition in every position: term, constructor and type alike),
    # every item carries a `textEdit` that replaces the whole
    # `Module.prefix` span with the BARE name, plus an
    # `additionalTextEdits` `import M using name` when M is not already
    # imported here.  The pins below APPLY the edits and re-check.
    #
    # The probe text is typed into the BUFFER, which is also the point:
    # the context comes from the current text, the items from the last
    # check's tables.
    def apply_edits(text, item):
        """The client's job: the textEdit, then the additionalTextEdits."""
        lines = text.split("\n")
        te = item["textEdit"]
        a, b = te["range"]["start"], te["range"]["end"]
        lines[a["line"]] = (lines[a["line"]][:a["character"]] + te["newText"]
                            + lines[b["line"]][b["character"]:])
        for extra in item.get("additionalTextEdits", []):
            lines.insert(extra["range"]["start"]["line"],
                         extra["newText"].rstrip("\r\n"))
        return "\n".join(lines)

    complete_src = (FIXTURES / "Complete.e").read_text()
    change("Complete.e", complete_src + "q = Bool.no\nz = Nope.no\n", 2)
    r = complete("Complete.e", 26, 11)          # `q = Bool.no|`
    check("completion: `Bool.` offers Bool's exports",
          "not" in labels(r) and one(r, "not")["detail"] == "Bool -> Bool",
          repr(labels(r)))
    check("completion: `Bool.` offers nothing from another module",
          "sibValue" not in labels(r) and "Red" not in labels(r)
          and "topFn" not in labels(r), repr(labels(r)))
    it = one(r, "not")
    check("completion: a qualified item replaces the whole `Module.prefix` span",
          it["textEdit"]["range"] == {"start": {"line": 26, "character": 4},
                                      "end": {"line": 26, "character": 11}}
          and it["textEdit"]["newText"] == "not", repr(it.get("textEdit")))
    check("completion: a qualified item filters on the DOTTED text the user typed",
          it.get("filterText") == "Bool.not", repr(it.get("filterText")))
    check("completion: no import is added for a module already imported",
          "additionalTextEdits" not in it, repr(it.get("additionalTextEdits")))
    r = complete("Complete.e", 27, 10)          # `z = Nope.n|o`
    check("completion: an unknown module answers []", r["items"] == [], repr(r))
    ds = client.diagnostics_for(uri("Complete.e"))
    check("Complete.e: a dotted reference does not parse in this grammar",
          any("unknown operator ." in d["message"] for d in ds), repr(ds))
    # APPLYING the edit gives code that parses and checks.
    change("Complete.e", apply_edits(complete_src + "q = Bool.no\n", it), 3)
    check("completion: the applied qualified edit checks clean",
          client.diagnostics_for(uri("Complete.e")) == [])

    # ... and for a module this file does NOT import, the item carries the
    # import line that makes its bare name resolve.
    change("Complete.e", complete_src + "q = Maybe.isJust\n", 4)
    r = complete("Complete.e", 26, 16)          # `q = Maybe.isJust|`
    it = one(r, "isJust")
    check("completion: `Maybe.` offers a module that is not imported here",
          it is not None and it["detail"] == "forall a. Maybe a -> Bool",
          repr(labels(r)))
    check("completion: an unimported module's item adds its import line",
          it.get("additionalTextEdits") == [{
              "range": {"start": {"line": 4, "character": 0},
                        "end": {"line": 4, "character": 0}},
              "newText": "import Maybe using isJust\n"}],
          repr(it.get("additionalTextEdits")))
    client.diagnostics_for(uri("Complete.e"))
    change("Complete.e", apply_edits(complete_src + "q = Maybe.isJust\n", it), 5)
    check("completion: the applied edits (name + import) check clean",
          client.diagnostics_for(uri("Complete.e")) == [])
    change("Complete.e", complete_src, 6)
    check("Complete.e clean again", client.diagnostics_for(uri("Complete.e")) == [])

    # (10b) A SPELLING THAT IS BOTH A TYPE AND A CONSTRUCTOR (review S-2).
    # The import edit rides on the item's namespace -- `using type Ring`
    # for the type, `using Ring` for the constructor -- so the two are NOT
    # collapsed into one item: an editor shows both, told apart by kind
    # and detail, and only one of them makes a TYPE position check.
    change("Complete.e", complete_src + "type QQ = Ring.Ring Int\n", 9)
    r = complete("Complete.e", 26, 19)          # `type QQ = Ring.Ring| Int`
    rings = [i for i in r["items"] if i["label"] == "Ring"]
    check("completion: a type and a constructor of one spelling are TWO items",
          sorted(i["kind"] for i in rings) == [4, 7], repr(rings))
    check("completion: each namespace carries its own import form",
          sorted(i["additionalTextEdits"][0]["newText"].strip() for i in rings)
          == ["import Ring using Ring", "import Ring using type Ring"], repr(rings))
    client.diagnostics_for(uri("Complete.e"))
    ty = [i for i in rings if i["kind"] == 7][0]
    tm = [i for i in rings if i["kind"] == 4][0]
    change("Complete.e", apply_edits(complete_src + "type QQ = Ring.Ring Int\n", ty), 10)
    check("completion: the TYPE item's edits check clean in a type position",
          client.diagnostics_for(uri("Complete.e")) == [])
    change("Complete.e", apply_edits(complete_src + "type QQ = Ring.Ring Int\n", tm), 11)
    check("completion: the CONSTRUCTOR item's import does not (why they are two)",
          len(client.diagnostics_for(uri("Complete.e"))) == 1)
    change("Complete.e", complete_src, 12)
    check("Complete.e clean after the Ring probe",
          client.diagnostics_for(uri("Complete.e")) == [])

    # (10c) AN ALIASED IMPORT (review S-1).  `import Bool as B` puts the
    # module's names in scope ONLY as `not_B`, and no import edit can help
    # (the module IS imported), so the item inserts the AFFIX form.
    open_doc("CompleteAlias.e")
    check("CompleteAlias.e clean", client.diagnostics_for(uri("CompleteAlias.e")) == [])
    alias_src = (FIXTURES / "CompleteAlias.e").read_text()
    change("CompleteAlias.e", alias_src + "q = Bool.no\n", 2)
    r = complete("CompleteAlias.e", 8, 11)      # `q = Bool.no|`
    it = one(r, "not")
    check("completion: an aliased module's item inserts the affix form",
          it is not None and it["textEdit"]["newText"] == "not_B"
          and "additionalTextEdits" not in it, repr(it))
    client.diagnostics_for(uri("CompleteAlias.e"))
    change("CompleteAlias.e", apply_edits(alias_src + "q = Bool.no\n", it), 3)
    check("completion: the affix insertion checks clean",
          client.diagnostics_for(uri("CompleteAlias.e")) == [])

    # (10d) THE `using`-LIST GAP, pinned rather than only stated (S-4):
    # `import Maybe using isJust` means `isNothing` does not resolve, and
    # this item never edits a list it did not write -- so the applied
    # completion leaves ONE diagnostic.  If 6.6 closes the gap, this check
    # is where it shows.
    change("CompleteAlias.e", alias_src + "z = Maybe.isNothing\n", 4)
    r = complete("CompleteAlias.e", 8, 19)      # `z = Maybe.isNothing|`
    it = one(r, "isNothing")
    check("completion: a module imported with a using list gets no import edit",
          it is not None and "additionalTextEdits" not in it, repr(it))
    client.diagnostics_for(uri("CompleteAlias.e"))
    change("CompleteAlias.e", apply_edits(alias_src + "z = Maybe.isNothing\n", it), 5)
    ds = client.diagnostics_for(uri("CompleteAlias.e"))
    check("completion: THE STATED GAP -- an existing `using` list is not extended",
          len(ds) == 1 and "undefined term" in ds[0]["message"], repr(ds))
    change("CompleteAlias.e", alias_src, 6)
    check("CompleteAlias.e clean again",
          client.diagnostics_for(uri("CompleteAlias.e")) == [])
    client.notify("textDocument/didClose",
                  {"textDocument": {"uri": uri("CompleteAlias.e")}})
    client.diagnostics_for(uri("CompleteAlias.e"))

    # (10a) A `do` BINDER is offered after its own bind statement and not
    # inside it -- the frame rule fix 7b made true (the corpus property is
    # the other pin).
    r = complete("CompleteSib.e", 11, 8)        # `  dy <- |fb`, empty prefix
    check("completion: a do binder is not in scope in its own rhs",
          "dx" in labels(r) and "dy" not in labels(r), repr(labels(r)))
    r = complete("CompleteSib.e", 12, 11)       # `  unit (f d|x dy)`
    check("completion: both do binders are in scope after their statements",
          "dx" in labels(r) and "dy" in labels(r), repr(labels(r)))
    r = complete("CompleteSib.e", 10, 8)        # `  dx <- |fa`, empty prefix
    check("completion: neither do binder is in scope in the FIRST rhs",
          "dx" not in labels(r) and "dy" not in labels(r)
          and "fa" in labels(r), repr(labels(r)))

    # (11) A BROKEN FILE completes from its healthy part.
    open_doc("LocalsBroken.e")
    check("LocalsBroken.e still reports its breakage",
          len(client.diagnostics_for(uri("LocalsBroken.e"))) > 0)
    r = complete("LocalsBroken.e", 4, 29)       # inside `ok` in the healthy let
    check("completion: a broken file completes from its healthy statement",
          "ok" in labels(r) and one(r, "ok")["kind"] == 6, repr(labels(r)))
    client.notify("textDocument/didClose",
                  {"textDocument": {"uri": uri("LocalsBroken.e")}})
    client.diagnostics_for(uri("LocalsBroken.e"))

    # (12) STALENESS, STATED AND PINNED (docs/lsp.md says the same):
    # a binder typed since the last check is not offered until that check
    # lands.  The request goes out immediately after the didChange, so it
    # is answered from the index the PREVIOUS check left; the debounce is
    # ~300ms and dispatch is single-threaded, so the check cannot have run.
    change("Complete.e", complete_src + "zzz = True\n", 13)
    r = complete("Complete.e", 26, 2)           # `zz|z = True`, before the check
    check("completion: a binder typed since the last check is NOT offered yet",
          "zzz" not in labels(r), repr(labels(r)))
    check("Complete.e clean with the new binding",
          client.diagnostics_for(uri("Complete.e")) == [])
    r = complete("Complete.e", 26, 2)           # after the check landed
    check("completion: it IS offered once the check lands",
          "zzz" in labels(r) and one(r, "zzz")["detail"] == "Bool", repr(labels(r)))
    change("Complete.e", complete_src, 14)
    check("Complete.e clean after the revert",
          client.diagnostics_for(uri("Complete.e")) == [])
    check("Complete.e on disk untouched by the buffer edits",
          (FIXTURES / "Complete.e").read_text() == complete_src)

    # (13) COST: the bar is 50 ms server-side; measure the round trip
    # instead, which contains it (best of five, so a scheduling hiccup
    # cannot fail a bound that is about the algorithm).
    ms = min(_query_ms(complete, "Complete.e", 23, 28) for _ in range(5))
    check("completion answers well under 50 ms", ms < 50.0, "%.1f ms" % ms)

    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Complete.e")}})
    client.diagnostics_for(uri("Complete.e"))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("CompleteSib.e")}})
    client.diagnostics_for(uri("CompleteSib.e"))

    # --- 6.6: quick fixes (textDocument/codeAction) ---------------------
    # A codeAction request fires on every cursor move, so it answers from
    # the LAST CHECK'S STORED RESULTS -- the diagnostics that check
    # published, still paired with the `Note` that produced them, plus the
    # surface tree and the inferred types on the index -- and the CURRENT
    # BUFFER TEXT, read lexically for the import statements and the line a
    # signature goes above.  Never a check (roadmap Decision (e)); the one
    # correctness measurement for the signature action is the 180-file
    # corpus sweep in TestTolerantCheck.
    def code_actions(name, line0, line1=None, only=None, diags=None):
        ctx = {"diagnostics": diags if diags is not None else []}
        if only is not None:
            ctx["only"] = only
        rid = client.request("textDocument/codeAction", {
            "textDocument": {"uri": uri(name)},
            "range": {"start": {"line": line0, "character": 0},
                      "end": {"line": line0 if line1 is None else line1, "character": 0}},
            "context": ctx})
        return client.response(rid).get("result")

    def titles(acts):
        return [a["title"] for a in acts]

    def act(acts, title):
        for a in acts:
            if a["title"] == title:
                return a
        return None

    def edits_of(a):
        # Tolerant of a missing action so ONE failed expectation reports as
        # one failed check rather than killing the run.
        if a is None:
            return []
        return list(a["edit"]["changes"].values())[0]

    def apply_ws(text, a, eol="\n"):
        """The client's job: apply a WorkspaceEdit's TextEdits to the buffer.
        Later positions first, so an earlier edit cannot move a later one."""
        if a is None:
            return text
        ls = text.split(eol)
        for e in sorted(edits_of(a), key=lambda e: (-e["range"]["start"]["line"],
                                                    -e["range"]["start"]["character"])):
            a0, b0 = e["range"]["start"], e["range"]["end"]
            head = ls[a0["line"]][:a0["character"]]
            tail = ls[b0["line"]][b0["character"]:]
            ls[a0["line"]:b0["line"] + 1] = [head + e["newText"] + tail]
        return eol.join(ls)

    def raw(name):
        """The fixture EXACTLY as it is on disk -- Python's text mode
        translates CRLF to LF, which would defeat the CRLF fixture."""
        return (FIXTURES / name).read_bytes().decode("utf-8")

    open_doc("FixSib.e")
    check("FixSib.e clean", client.diagnostics_for(uri("FixSib.e")) == [])
    open_doc("Fix.e")
    check("Fix.e clean", client.diagnostics_for(uri("Fix.e")) == [])
    fix_src = raw("Fix.e")
    tail = fix_src.count("\n")          # the index a line appended to the buffer takes

    # (1) ADD TYPE SIGNATURE for one unsigned group -- a `quickfix` with
    # NO diagnostic (that is the kind this server declares; a
    # `refactor.rewrite` would be outside `codeActionKinds`).
    r = code_actions("Fix.e", 9)                # `answer = 42`
    a = act(r, "add signature: answer : Int")
    check("codeAction: an unsigned binding offers its signature", a is not None, repr(titles(r)))
    check("codeAction: the signature action is a quickfix with no diagnostic",
          a is not None and a["kind"] == "quickfix" and "diagnostics" not in a
          and "isPreferred" not in a, repr(a))
    check("codeAction: the signature is inserted on the line ABOVE the equation",
          a is not None and edits_of(a) == [{
              "range": {"start": {"line": 9, "character": 0},
                        "end": {"line": 9, "character": 0}},
              "newText": "answer : Int\n"}], repr(a and edits_of(a)))
    change("Fix.e", apply_ws(fix_src, a), 2)
    check("codeAction: the applied signature re-checks clean",
          client.diagnostics_for(uri("Fix.e")) == [])
    check("codeAction: hover afterwards shows the same type",
          hoverline("Fix.e", 10, 1) == "Fix.answer : Int", repr(hoverline("Fix.e", 10, 1)))
    change("Fix.e", fix_src, 3)
    check("Fix.e clean again", client.diagnostics_for(uri("Fix.e")) == [])

    # (2) A SIGNED binding offers none.
    r = code_actions("Fix.e", 20)               # `signed = 7`
    check("codeAction: a signed binding offers no signature action",
          not any(t.startswith("add signature: signed") for t in titles(r)), repr(titles(r)))

    # (3) A group whose rendered type names a type this file does NOT
    # import is REFUSED, because the inserted line would not parse.
    # `peek m = isJust m` is `forall a. Maybe a -> Bool` and the file
    # imports neither `Maybe` nor `Bool` as a type.
    r = code_actions("Fix.e", 16)               # `peek = paint`
    check("codeAction: a signature naming an unimported type is not offered",
          not any(t.startswith("add signature: peek") for t in titles(r)), repr(titles(r)))

    # (4) "ADD ALL MISSING SIGNATURES", a `source` action over the file:
    # two insertions for the two offerable groups (peek is refused), sorted
    # by line DESCENDING so a sequential applier cannot drift.
    r = code_actions("Fix.e", 0)
    a = act(r, "add all missing signatures (2)")
    check("codeAction: the source action counts the groups it can serve",
          a is not None and a["kind"] == "source", repr(titles(r)))
    es = edits_of(a) if a else []
    check("codeAction: one insertion per group, later lines first",
          [e["range"]["start"]["line"] for e in es] == [11, 9], repr(es))
    check("codeAction: the second insertion is the polymorphic one",
          es and es[0]["newText"] == "pairUp : forall a. a -> (a, a)\n", repr(es and es[0]))
    change("Fix.e", apply_ws(fix_src, a), 4)
    check("codeAction: all the applied signatures re-check clean",
          client.diagnostics_for(uri("Fix.e")) == [])
    r = code_actions("Fix.e", 0)
    check("codeAction: with them applied the source action is gone",
          not any(t.startswith("add all") for t in titles(r)), repr(titles(r)))
    change("Fix.e", fix_src, 5)
    check("Fix.e clean after the revert", client.diagnostics_for(uri("Fix.e")) == [])

    # (5) ADD IMPORT on an undefined term.  `not` is defined by BOTH
    # `Bool` and `Relation.Predicate`, so the name offers TWO actions and
    # neither is preferred -- picking one of two modules for the user is
    # not a thing this server knows.
    change("Fix.e", fix_src + "undef = not True\n", 6)
    ds = client.diagnostics_for(uri("Fix.e"))
    check("Fix.e: an undefined term is one diagnostic",
          len(ds) == 1 and "undefined term" in ds[0]["message"], repr(ds))
    r = code_actions("Fix.e", tail)
    check("codeAction: a name two modules export offers two actions",
          sorted(t for t in titles(r) if t.startswith("import")) ==
          ["import Bool using not", "import Relation.Predicate using not"], repr(titles(r)))
    a = act(r, "import Bool using not")
    check("codeAction: the action carries the diagnostic it fixes",
          a is not None and a.get("diagnostics") == ds, repr(a and a.get("diagnostics")))
    check("codeAction: with two candidates neither is preferred",
          all("isPreferred" not in x for x in r if x["title"].startswith("import")), repr(r))
    check("codeAction: the import line goes after the LAST import",
          edits_of(a) == [{"range": {"start": {"line": 5, "character": 0},
                                     "end": {"line": 5, "character": 0}},
                           "newText": "import Bool using not\n"}], repr(edits_of(a)))
    change("Fix.e", apply_ws(fix_src + "undef = not True\n", a), 7)
    check("codeAction: the applied import clears the diagnostic",
          client.diagnostics_for(uri("Fix.e")) == [])

    # (6) THE OPEN SIBLING is a candidate module in its own right, and a
    # module already imported WITH A LIST is fixed by growing the list --
    # 6.5 left exactly that gap and pinned it; this closes it.
    change("Fix.e", fix_src + "two = catMaybes\n", 8)
    ds = client.diagnostics_for(uri("Fix.e"))
    r = code_actions("Fix.e", tail)
    check("codeAction: an open sibling that declares the name is a candidate",
          sorted(t for t in titles(r) if t.startswith(("import", "add catMaybes"))) ==
          ["add catMaybes to the Maybe import list", "import FixSib using catMaybes"],
          repr(titles(r)))
    a = act(r, "add catMaybes to the Maybe import list")
    check("codeAction: THE 6.5 GAP CLOSED -- the existing using list grows",
          edits_of(a) == [{"range": {"start": {"line": 2, "character": 25},
                                     "end": {"line": 2, "character": 25}},
                           "newText": "; catMaybes"}], repr(edits_of(a)))
    change("Fix.e", apply_ws(fix_src + "two = catMaybes\n", a), 9)
    check("codeAction: the grown list checks clean",
          client.diagnostics_for(uri("Fix.e")) == [])
    a = act(r, "import FixSib using catMaybes")
    change("Fix.e", apply_ws(fix_src + "two = catMaybes\n", a), 10)
    check("codeAction: the sibling's import checks clean too",
          client.diagnostics_for(uri("Fix.e")) == [])

    # (7) ONE candidate: the action IS preferred.
    change("Fix.e", fix_src + "grow = isNothing\n", 11)
    client.diagnostics_for(uri("Fix.e"))
    r = code_actions("Fix.e", tail)
    a = act(r, "add isNothing to the Maybe import list")
    check("codeAction: one candidate module, one preferred action",
          a is not None and a.get("isPreferred") is True, repr(titles(r)))
    change("Fix.e", apply_ws(fix_src + "grow = isNothing\n", a), 12)
    check("codeAction: `import Maybe using isJust; isNothing` checks clean",
          client.diagnostics_for(uri("Fix.e")) == [])

    # (8) A `hiding` LIST: the name is excluded, so the fix REMOVES it.
    # `import Function hiding id` with `id` its only item becomes an open
    # `import Function`.
    change("Fix.e", fix_src + "hid = id\n", 13)
    client.diagnostics_for(uri("Fix.e"))
    r = code_actions("Fix.e", tail)
    a = act(r, "stop hiding id from Function")
    check("codeAction: a hidden name is fixed by un-hiding it",
          a is not None and edits_of(a) == [{
              "range": {"start": {"line": 3, "character": 15},
                        "end": {"line": 3, "character": 25}},
              "newText": ""}], repr(titles(r)))
    change("Fix.e", apply_ws(fix_src + "hid = id\n", a), 14)
    check("codeAction: the un-hidden import checks clean",
          client.diagnostics_for(uri("Fix.e")) == [])
    change("Fix.e", fix_src, 15)
    check("Fix.e clean after every import probe",
          client.diagnostics_for(uri("Fix.e")) == [])

    # (9) `context.only` is honoured: a client asking for one kind gets
    # that kind and nothing else.
    r = code_actions("Fix.e", 9, only=["source"])
    check("codeAction: only=[source] answers the source action alone",
          titles(r) == ["add all missing signatures (2)"], repr(titles(r)))
    r = code_actions("Fix.e", 9, only=["quickfix"])
    check("codeAction: only=[quickfix] drops the source action",
          titles(r) == ["add signature: answer : Int"], repr(titles(r)))

    # (10) STALENESS IS REFUSED, not accepted (unlike every other request
    # in this server): a code action is an EDIT, and an edit at a line the
    # buffer no longer has is corruption.  The request goes out
    # immediately after a didChange, before the ~300ms debounce fires.
    change("Fix.e", "\n" + fix_src, 16)
    r = code_actions("Fix.e", 10)
    check("codeAction: [] while the index is older than the buffer", r == [], repr(r))
    check("Fix.e clean with the leading blank line",
          client.diagnostics_for(uri("Fix.e")) == [])
    r = code_actions("Fix.e", 10)
    check("codeAction: it answers again once the check lands",
          any(t.startswith("add signature: answer") for t in titles(r)), repr(titles(r)))
    change("Fix.e", fix_src, 17)
    client.diagnostics_for(uri("Fix.e"))

    # (11) CRLF END TO END.  142 of the 161 stdlib modules are CRLF; an
    # inserted line has to carry the buffer's own terminator.
    crlf_src = raw("FixCrlf.e")
    check("FixCrlf.e really is CRLF on disk", "\r\n" in crlf_src and "\n" not in crlf_src.replace("\r\n", ""))
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": uri("FixCrlf.e"), "languageId": "ermine", "version": 1, "text": crlf_src}})
    check("FixCrlf.e clean", client.diagnostics_for(uri("FixCrlf.e")) == [])
    r = code_actions("FixCrlf.e", 6)            # `crlfValue = 42`
    a = act(r, "add signature: crlfValue : Int")
    check("codeAction: a CRLF buffer's signature line ends CRLF",
          a is not None and edits_of(a)[0]["newText"] == "crlfValue : Int\r\n",
          repr(a and edits_of(a)))
    applied = apply_ws(crlf_src, a, "\r\n")
    check("codeAction: the applied CRLF buffer has no lone newline",
          "\n" not in applied.replace("\r\n", ""), repr(applied[:80]))
    change("FixCrlf.e", applied, 2)
    check("codeAction: the applied CRLF signature re-checks clean",
          client.diagnostics_for(uri("FixCrlf.e")) == [])
    crlf_tail = crlf_src.count("\n")
    change("FixCrlf.e", crlf_src + "undef = not True\r\n", 3)
    client.diagnostics_for(uri("FixCrlf.e"))
    r = code_actions("FixCrlf.e", crlf_tail)
    a = act(r, "import Bool using not")
    check("codeAction: a CRLF buffer's import line ends CRLF",
          a is not None and edits_of(a)[0]["newText"] == "import Bool using not\r\n",
          repr(a and edits_of(a)))
    change("FixCrlf.e", apply_ws(crlf_src + "undef = not True\r\n", a, "\r\n"), 4)
    check("codeAction: the applied CRLF import checks clean",
          client.diagnostics_for(uri("FixCrlf.e")) == [])
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("FixCrlf.e")}})
    client.diagnostics_for(uri("FixCrlf.e"))

    # (12) COST: a codeAction fires on every cursor move, so the round
    # trip is measured, not argued about (best of five).
    ms = min(_query_ms(code_actions, "Fix.e", 9) for _ in range(5))
    check("codeAction answers well under 50 ms", ms < 50.0, "%.1f ms" % ms)

    check("Fix.e on disk untouched by the buffer edits", raw("Fix.e") == fix_src)
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Fix.e")}})
    client.diagnostics_for(uri("Fix.e"))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("FixSib.e")}})
    client.diagnostics_for(uri("FixSib.e"))

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
    # 6.2b: the hook is armed inside `checkWith` and fast mode never calls
    # it, so a lambda argument and a `case` binder answer null there too.
    check("fast mode: hover on a lambda argument -> null",
          hover("Locals.e", 42, 12) is None)
    check("fast mode: hover on a case binder -> null",
          hover("Locals.e", 26, 9) is None)
    check("fast mode keeps the imported type's kind",
          hoverline("Locals.e", 8, 11) == "Builtin.Bool : *", hoverline("Locals.e", 8, 11))

    set_fast(False)
    client.notify("textDocument/didSave", {"textDocument": {"uri": uri("Bad.e")}})
    ds = client.diagnostics_for(uri("Bad.e"))
    check("leaving fast mode restores the type error", len(ds) == 1
          and "failed to unify" in ds[0]["message"], repr(ds))

    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Bad.e")}})
    check("Bad.e cleared on close", client.diagnostics_for(uri("Bad.e")) == [])

    # ---- 7.2: ANCHORED POSITIONS ----------------------------------------
    #
    # The inference cache is keyed on text with positions relative to each
    # group's own start line, so an edit that only SHIFTS lines keeps every
    # entry.  What this block pins is the other half: EVERY position that
    # escapes to the client is re-anchored.  Each route is asked once on
    # the pristine buffer and once after a didChange that inserts THREE
    # BLANK LINES AT THE TOP -- no save, so the file on disk still says the
    # old lines -- and every answer must have moved by exactly three.
    SHIFT = 3

    def bump(x, n=SHIFT):
        """A baseline answer, moved down n lines: tuples of
        (line, col, ...) or lists of them."""
        if isinstance(x, tuple):
            return (x[0] + n,) + x[1:]
        return [bump(y, n) for y in x]

    open_doc("Anchor.e")
    anchor_ds = client.diagnostics_for(uri("Anchor.e"))
    check("7.2 Anchor.e clean on open", anchor_ds == [], repr(anchor_ds))

    def loc3(r):
        """One Location as (line, startChar, endChar)."""
        if r is None:
            return None
        return (r["range"]["start"]["line"], r["range"]["start"]["character"],
                r["range"]["end"]["character"])

    def hl3(hs):
        return sorted((h["range"]["start"]["line"], h["range"]["start"]["character"],
                       h["range"]["end"]["character"]) for h in (hs or []))

    def ed3(es):
        return sorted((e["range"]["start"]["line"], e["range"]["start"]["character"],
                       e["range"]["end"]["character"], e["newText"]) for e in (es or []))

    def sym3(syms):
        out = []
        for s in (syms or []):
            out.append((s["name"], s["range"]["start"]["line"], s["range"]["end"]["line"],
                        s["selectionRange"]["start"]["line"]))
            out.extend(sym3(s.get("children", [])))
        return sorted(out)

    def sym_bump(xs, n=SHIFT):
        return sorted((a, b + n, c + n, d + n) for (a, b, c, d) in xs)

    # The six escape routes, on the pristine buffer.  Positions are 0-based
    # LSP; Anchor.e's source lines are one more.
    #   line 9  (0-based 8)  `  let flag = x && True`   -- the local's def-site
    #   line 10 (0-based 9)  `  in flag`                -- its use
    #   line 15 (0-based 14) `anchorUse b = anchorLet b`
    #   line 17 (0-based 16) `noSig b = b && True`      -- no signature
    base_hover_local = hoverline("Anchor.e", 9, 5)           # `flag` in `in flag`
    base_def_local   = loc3(definition("Anchor.e", 9, 5))    # -> its let binder
    base_hover_top   = hoverline("Anchor.e", 14, 14)         # `anchorLet` at a use
    base_def_top     = loc3(definition("Anchor.e", 14, 14))
    base_refs        = hl3(references("Anchor.e", 14, 14))
    base_high        = hl3(highlight("Anchor.e", 14, 14))
    base_rename      = ed3(rename("Anchor.e", 14, 14, "anchorLetted")
                           ["result"]["changes"][uri("Anchor.e")])
    base_syms        = sym3(doc_symbols("Anchor.e"))
    base_where       = hoverline("Anchor.e", 11, 16)         # `keep` in `= keep`
    # A LET local inside an UNSIGNED binding.  `anchorLet` carries a
    # signature, so it is an EXPLICIT binding and `checkWith` never caches
    # it -- its locals are recomputed on every check and would survive a
    # broken re-anchoring.  `anchorPlain` has no signature, so its
    # component IS cached, and this is the pin that bites (verified by
    # sabotaging `Anchors.absPos` with an off-by-one: this check and the
    # `where` one fail, the signed one does not).
    base_plain       = hoverline("Anchor.e", 18, 21)         # `inner` at its binder
    acts = code_actions("Anchor.e", 16, only=["quickfix", "source"])
    base_sig = [a for a in (acts or []) if a["title"].startswith("add signature: noSig")]
    base_sig_edit = ed3(list(base_sig[0]["edit"]["changes"].values())[0]) if base_sig else []

    check("7.2 baseline: hover on a LET local answers",
          base_hover_local is not None and "Bool" in base_hover_local,
          repr(base_hover_local))
    check("7.2 baseline: hover on a WHERE local answers",
          base_where is not None and "Bool" in base_where, repr(base_where))
    check("7.2 baseline: hover on a LET local of an UNSIGNED binding answers",
          base_plain is not None and "Bool" in base_plain, repr(base_plain))
    check("7.2 baseline: definition of a local is its binder",
          base_def_local is not None and base_def_local[0] == 8 and base_def_local[1] == 6,
          repr(base_def_local))
    check("7.2 baseline: references to a top level found", len(base_refs) >= 3,
          repr(base_refs))
    check("7.2 baseline: a rename edits every occurrence",
          len(base_rename) == len(base_refs), repr(base_rename))
    check("7.2 baseline: documentSymbol has the five declarations",
          len(base_syms) >= 5, repr(base_syms))
    check("7.2 baseline: the add-signature action is offered for noSig",
          len(base_sig_edit) == 1, repr(base_sig_edit))

    # THE EDIT: three blank lines at the top, as a didChange with NO SAVE.
    anchor_src = (FIXTURES / "Anchor.e").read_text()
    change("Anchor.e", ("\n" * SHIFT) + anchor_src, 2)
    ds = client.diagnostics_for(uri("Anchor.e"))
    check("7.2 the shifted buffer still checks clean", ds == [], repr(ds))

    check("7.2 hover on a LET local survives a line shift",
          hoverline("Anchor.e", 9 + SHIFT, 5) == base_hover_local,
          repr(hoverline("Anchor.e", 9 + SHIFT, 5)) + " want " + repr(base_hover_local))
    check("7.2 hover on a WHERE local survives a line shift",
          hoverline("Anchor.e", 11 + SHIFT, 16) == base_where,
          repr(hoverline("Anchor.e", 11 + SHIFT, 16)) + " want " + repr(base_where))
    check("7.2 hover on a LET local of an UNSIGNED binding survives a line shift",
          hoverline("Anchor.e", 18 + SHIFT, 21) == base_plain,
          repr(hoverline("Anchor.e", 18 + SHIFT, 21)) + " want " + repr(base_plain))
    check("7.2 hover on a top level survives a line shift",
          hoverline("Anchor.e", 14 + SHIFT, 14) == base_hover_top,
          repr(hoverline("Anchor.e", 14 + SHIFT, 14)))
    check("7.2 definition of a local is re-anchored",
          loc3(definition("Anchor.e", 9 + SHIFT, 5)) == bump(base_def_local),
          repr(loc3(definition("Anchor.e", 9 + SHIFT, 5))) + " want " +
          repr(bump(base_def_local)))
    check("7.2 definition of a top level is re-anchored",
          loc3(definition("Anchor.e", 14 + SHIFT, 14)) == bump(base_def_top),
          repr(loc3(definition("Anchor.e", 14 + SHIFT, 14))))
    check("7.2 references are re-anchored",
          hl3(references("Anchor.e", 14 + SHIFT, 14)) == bump(base_refs),
          repr(hl3(references("Anchor.e", 14 + SHIFT, 14))))
    check("7.2 highlight ranges are re-anchored",
          hl3(highlight("Anchor.e", 14 + SHIFT, 14)) == bump(base_high),
          repr(hl3(highlight("Anchor.e", 14 + SHIFT, 14))))
    check("7.2 rename edit ranges are re-anchored",
          ed3(rename("Anchor.e", 14 + SHIFT, 14, "anchorLetted")
              ["result"]["changes"][uri("Anchor.e")]) ==
          sorted((l + SHIFT, a, b, t) for (l, a, b, t) in base_rename),
          repr(ed3(rename("Anchor.e", 14 + SHIFT, 14, "anchorLetted")
                   ["result"]["changes"][uri("Anchor.e")])))
    check("7.2 documentSymbol ranges are re-anchored",
          sym3(doc_symbols("Anchor.e")) == sym_bump(base_syms),
          repr(sym3(doc_symbols("Anchor.e"))) + " want " + repr(sym_bump(base_syms)))
    acts2 = code_actions("Anchor.e", 16 + SHIFT, only=["quickfix", "source"])
    sig2 = [a for a in (acts2 or []) if a["title"].startswith("add signature: noSig")]
    sig2_edit = ed3(list(sig2[0]["edit"]["changes"].values())[0]) if sig2 else []
    check("7.2 the add-signature edit range is re-anchored",
          sig2_edit == sorted((l + SHIFT, a, b, t) for (l, a, b, t) in base_sig_edit),
          repr(sig2_edit) + " want " +
          repr(sorted((l + SHIFT, a, b, t) for (l, a, b, t) in base_sig_edit)))

    # And the REUSE COUNT itself, the acceptance number of item 7.2: the
    # shifted check must reuse, where before 7.2 it reused nothing at all.
    # Read from the server's own check line after shutdown, below.

    # ---- 7.1b: THE STATEMENT-EXTENT SURFACE CACHE, end to end.
    # The invariant is that a reused surface tree is what a fresh parse
    # would give, so the client's form of the corpus differential is: drive
    # a SEQUENCE of didChanges through one buffer -- a body edit, an edit
    # ABOVE it (every statement below shifts a line), a MERGE of two
    # statements and a SPLIT of one -- and then compare what the warm
    # server publishes against what a COLD open of the same final text
    # publishes.  The final text is deliberately broken, so the comparison
    # is not [] == [].
    splice_src = (FIXTURES / "Splice.e").read_text()
    open_doc("Splice.e")
    check("7.1b Splice.e clean on open",
          client.diagnostics_for(uri("Splice.e")) == [])

    s2 = splice_src.replace("where keep = b + 2", "where keep = b + 22")
    change("Splice.e", s2, 2)
    check("7.1b a body edit keeps the file clean",
          client.diagnostics_for(uri("Splice.e")) == [])

    s3 = s2.replace("import Prelude\n", "import Prelude\n\n")
    change("Splice.e", s3, 3)
    check("7.1b an edit ABOVE (a line shift) keeps the file clean",
          client.diagnostics_for(uri("Splice.e")) == [])

    s4 = s3.replace("\nspliceD x = x <^^> 4", "\n  spliceD x = x <^^> 4")
    change("Splice.e", s4, 4)
    ds_merge = client.diagnostics_for(uri("Splice.e"))

    s5 = s4.replace("  let flag = x + 1\n  in flag", "  let flag = x + 1\nin flag")
    change("Splice.e", s5, 5)
    ds_warm = client.diagnostics_for(uri("Splice.e"))
    check("7.1b the merge+split sequence reports something",
          len(ds_warm) > 0, repr(ds_warm))

    # the SAME text, on a server that has never seen it: didClose drops the
    # document and its caches, so the re-open is a cold read
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Splice.e")}})
    check("7.1b didClose clears the squiggles",
          client.diagnostics_for(uri("Splice.e")) == [])
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": uri("Splice.e"), "languageId": "ermine", "version": 1, "text": s5}})
    ds_cold = client.diagnostics_for(uri("Splice.e"))
    check("7.1b the spliced diagnostics are the cold ones, exactly",
          ds_warm == ds_cold,
          "warm " + repr(ds_warm) + "\ncold " + repr(ds_cold))
    check("7.1b the merge was reported too", len(ds_merge) > 0, repr(ds_merge))
    check("7.1b Splice.e on disk untouched by the buffer edits",
          (FIXTURES / "Splice.e").read_text() == splice_src)
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Splice.e")}})
    client.diagnostics_for(uri("Splice.e"))

    # ---- 7.4: THE ADAPTIVE DEBOUNCE, and the burst it exists to coalesce.
    # The window is clamp(150, median measured check time of THIS document,
    # 300) ms of quiet on the input stream, so the two things to pin through a
    # real server are (i) that a burst of keystrokes closer together than the
    # window still produces EXACTLY ONE check and one publish, at the small
    # file's window and at the large file's, and (ii) that what the server
    # logged as waited is what the policy says for the samples it had.
    burst_src = (FIXTURES / "Burst.e").read_text()
    open_doc("Burst.e")
    check("7.4 Burst.e clean on open", client.diagnostics_for(uri("Burst.e")) == [])

    def burst(name, text_of, n, gap, version0):
        """n didChanges `gap` seconds apart, sent without waiting for any
        publish, then the ONE publish they are expected to coalesce into."""
        for k in range(n):
            client.notify("textDocument/didChange", {
                "textDocument": {"uri": name, "version": version0 + k},
                "contentChanges": [{"text": text_of(k)}]})
            time.sleep(gap)
        return client.diagnostics_for(name)

    # Eight keystrokes 20 ms apart -- a fast typist is ~120-300 ms per
    # character, so 20 ms is well inside any window the policy can choose.
    ds = burst(uri("Burst.e"),
               lambda k: burst_src.replace("(y + 2)", "(y +" + " " * (k + 1) + "2)"),
               8, 0.020, 2)
    check("7.4 a burst of 8 keystrokes still publishes, and publishes clean",
          ds == [], repr(ds))
    # A SECOND burst, so that "one check per burst" is a rule and not an
    # artefact of there having been only one: it must produce exactly one more.
    ds = burst(uri("Burst.e"),
               lambda k: burst_src.replace("(y + 2)", "(y  +" + " " * (k + 1) + "2)"),
               8, 0.020, 10)
    check("7.4 a second burst of 8 keystrokes is exactly one more check",
          ds == [], repr(ds))
    # The same burst against the LARGEST stdlib module, whose check is ~0.6 s
    # and whose window is therefore the ceiling (300 ms) rather than the floor.
    report = repo("core/src/main/resources/modules/Layout/Report.e")
    report_uri = report.as_uri()
    report_src = report.read_bytes().decode("utf-8")   # CRLF: never text mode
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": report_uri, "languageId": "ermine", "version": 1,
        "text": report_src}})
    check("7.4 Layout/Report.e clean on open",
          client.diagnostics_for(report_uri) == [])
    ds = burst(report_uri,
               lambda k: report_src.replace("emptyReport = prefA [pixelsA 0 0, cellsA 0 0]",
                                            "emptyReport = prefA [pixelsA 0 0, cellsA 0" +
                                            " " * (k + 1) + "0]"),
               6, 0.020, 2)
    check("7.4 a burst on the largest module publishes, and publishes clean",
          ds == [], repr(ds[:2]))
    client.notify("textDocument/didClose", {"textDocument": {"uri": report_uri}})
    client.diagnostics_for(report_uri)
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Burst.e")}})
    client.diagnostics_for(uri("Burst.e"))
    check("7.4 Burst.e on disk untouched by the buffer edits",
          (FIXTURES / "Burst.e").read_text() == burst_src)

    # ---- 7.5, TICKET E8: THE BOUNDARY CONVERSION, parser column <-> LSP
    # character.  `scalaparsers.Pos.bump` sends a tab to the next tab stop
    # (column 1 -> column 8); LSP counts characters.  Until 7.5 the server
    # converted by +-1 in BOTH directions and in EVERY feature, so on a
    # tab-indented line a squiggle, a definition target, a hover hit-test, a
    # highlight and a symbol were all seven characters right of the text, and
    # 6.3 made rename REFUSE such a name rather than mis-edit it.  Tab.e is
    # the fixture; `core/examples/GridExample.e` is the corpus instance (6 of
    # 71,248 occurrences) and is pinned below as itself.
    open_doc("Tab.e")
    ds = client.diagnostics_for(uri("Tab.e"))
    check("7.5 Tab.e reports its four diagnostics", len(ds) == 4, repr(ds))

    def diag_with(ds, needle):
        for d in ds:
            if needle in d["message"]:
                return d
        return None

    d = diag_with(ds, "unknown operator <+>")
    # `\tTrue <+> False`: the operator is at CHARACTER 6 and at PARSER
    # COLUMN 13.  A structured READ diagnostic, so this is the `fromDiag`
    # path.
    check("7.5 a structured diagnostic on a tabbed line squiggles the text",
          d is not None and d["range"]["start"] == {"line": 24, "character": 6},
          repr(d and d["range"]))
    d = diag_with(ds, "undefined term")
    # A note with no span: its position is recovered from the report's own
    # `file:line:col:` prefix, which is a PARSER column (8) -- the
    # `fromReport` path, which converts too.
    check("7.5 a caret note on a tabbed line lands on the text",
          d is not None and d["range"]["start"] == {"line": 19, "character": 1},
          repr(d and d["range"]))

    # NAVIGATION at the REAL character column.
    r = definition("Tab.e", 10, 9)              # `go` in `tabbed = go where`
    check("7.5 def go -> its binder behind a tab", r is not None
          and r["uri"] == uri("Tab.e")
          and r["range"] == {"start": {"line": 11, "character": 1},
                             "end": {"line": 11, "character": 4}}, repr(r))
    r = definition("Tab.e", 11, 1)              # the binder itself, at character 1
    check("7.5 def at the character column of a tabbed binder hits", r is not None
          and r["range"]["start"] == {"line": 11, "character": 1}, repr(r))
    check("7.5 hover at the character column of a tabbed binder hits",
          hoverline("Tab.e", 11, 1) == "go : Bool", repr(hoverline("Tab.e", 11, 1)))
    # THE CONTROL, and it is the reviewer's own observation (6.3 review S5)
    # inverted: character 8 on `\tgo = True` is inside `True`, and it is
    # exactly the position that used to answer `go`.
    check("7.5 the old parser-column position no longer answers the name",
          definition("Tab.e", 11, 8) is None, repr(definition("Tab.e", 11, 8)))
    check("7.5 character 8 of that line is `True`, and says so",
          hoverline("Tab.e", 11, 8) == "Builtin.True : Bool",
          repr(hoverline("Tab.e", 11, 8)))
    check("7.5 the tab itself is not a name", definition("Tab.e", 11, 0) is None)

    # RENAME BEHIND A TAB, which 6.3 refused (-32803, `nameExtent` non-exact)
    # because the range would have been in the wrong units.  It is not a
    # refusal any more, and prepareRename says so before the user types.
    rid = client.request("textDocument/prepareRename", {
        "textDocument": {"uri": uri("Tab.e")}, "position": {"line": 11, "character": 1}})
    pr = client.response(rid).get("result")
    check("7.5 prepareRename behind a tab offers the name (6.3 refused it)",
          pr is not None and pr["placeholder"] == "go"
          and pr["range"]["start"] == {"line": 11, "character": 1}, repr(pr))
    rid = client.request("textDocument/rename", {
        "textDocument": {"uri": uri("Tab.e")}, "position": {"line": 11, "character": 1},
        "newName": "went"})
    rr = client.response(rid)
    es = list((rr.get("result") or {}).get("changes", {}).values())
    es = sorted(es[0], key=lambda e: e["range"]["start"]["line"]) if es else []
    check("7.5 rename behind a tab edits both sites, at their character columns",
          [(e["range"]["start"]["line"], e["range"]["start"]["character"],
            e["range"]["end"]["character"]) for e in es]
          == [(10, 9, 11), (11, 1, 3)], repr(rr.get("error") or es))

    # A DOCUMENT SYMBOL whose own line is untabbed still carries a child
    # range that crosses the tabbed one; the selection columns are the
    # untabbed ones and must not move.
    rid = client.request("textDocument/documentSymbol",
                         {"textDocument": {"uri": uri("Tab.e")}})
    syms = client.response(rid).get("result") or []
    tabbed_sym = [x for x in syms if x["name"] == "tabbed"]
    check("7.5 an untabbed symbol's columns are unchanged by the conversion",
          len(tabbed_sym) == 1
          and tabbed_sym[0]["selectionRange"]["start"] == {"line": 10, "character": 0},
          repr(tabbed_sym))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("Tab.e")}})
    client.diagnostics_for(uri("Tab.e"))

    # THE CORPUS INSTANCE, as itself: `core/examples/GridExample.e` indents
    # three lines with a tab, and each carries two `atomShown` occurrences --
    # the 6 the 6.3 extent property counts.  `\t[atomShown` puts the name at
    # CHARACTER 2 and at PARSER COLUMN 10.
    grid = repo("core/examples/GridExample.e")
    grid_uri = grid.as_uri()
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": grid_uri, "languageId": "ermine", "version": 1,
        "text": grid.read_bytes().decode("utf-8")}})
    check("7.5 GridExample.e checks clean",
          client.diagnostics_for(grid_uri) == [], repr(client.seen[-1:]))

    def grid_req(method, line, char, extra=None):
        p = {"textDocument": {"uri": grid_uri},
             "position": {"line": line, "character": char}}
        if extra:
            p.update(extra)
        return client.response(client.request(method, p)).get("result")

    r = grid_req("textDocument/definition", 64, 2)
    check("7.5 definition at the character column of a name behind a tab",
          r is not None and r["uri"].endswith("/modules/Layout/Report.e"), repr(r))
    h = grid_req("textDocument/hover", 64, 2)
    check("7.5 hover at the character column of a name behind a tab",
          h is not None and "Layout.Report.atomShown :" in h["contents"]["value"],
          repr(h))
    check("7.5 the `[` before it is not a name",
          grid_req("textDocument/definition", 64, 1) is None)
    r = grid_req("textDocument/references", 64, 2,
                 {"context": {"includeDeclaration": True}}) or []
    tabbed_hits = sorted((x["range"]["start"]["line"], x["range"]["start"]["character"])
                         for x in r if x["uri"] == grid_uri
                         and x["range"]["start"]["line"] in (64, 65, 66))
    check("7.5 all six tabbed occurrences are found at their character columns",
          tabbed_hits == [(64, 2), (64, 26), (65, 2), (65, 27), (66, 2), (66, 32)],
          repr(tabbed_hits))
    client.notify("textDocument/didClose", {"textDocument": {"uri": grid_uri}})
    client.diagnostics_for(grid_uri)

    # ---- 7.5, TICKET E9: A STDLIB TARGET OPENS THE SOURCE TREE.
    # The resident session loads its 129 modules from the classpath copy
    # (`core/target/<scala>/classes/modules`), so every stdlib `V.loc` names
    # that copy -- and a user who edits the file they land in loses the edit
    # at the next `copyResources`.  The mapping back is made at the LSP
    # boundary (`Definitions.location`) and derived from where the class
    # loader actually found `modules`, so no Scala version is spelled here
    # either.  EVERY pin below is tree-distinguishing: the `endswith` pins
    # this suite had before cannot see the bug at all.
    src_root = repo("core/src/main/resources/modules").as_uri()

    def in_source_tree(u):
        return u is not None and u.startswith(src_root) and "/target/" not in u

    r = definition("Nav.e", 7, 12)              # `&&`, from stdlib Bool
    check("7.5 a stdlib definition target is in the SOURCE tree",
          r is not None and in_source_tree(r["uri"]), repr(r))
    rid = client.request("textDocument/references", {
        "textDocument": {"uri": uri("Nav.e")}, "position": {"line": 7, "character": 12},
        "context": {"includeDeclaration": True}})
    rs = client.response(rid).get("result") or []
    # The set spans the OPEN buffers (several of them mention `&&`); the one
    # entry that is NOT in a buffer is the def-site `location` adds, and it
    # is the one this ticket is about.
    outside = [x for x in rs if "/modules/" in x["uri"] or "/target/" in x["uri"]]
    check("7.5 the def-site a references request adds is in the SOURCE tree",
          len(outside) == 1 and in_source_tree(outside[0]["uri"])
          and outside[0]["uri"].endswith("/resources/modules/Bool.e"), repr(outside))
    rid = client.request("workspace/symbol", {"query": "not"})
    ws = client.response(rid).get("result") or []
    ws_bool = [x for x in ws if x["containerName"] == "Bool" and x["name"] == "not"]
    check("7.5 a workspace symbol's location is in the SOURCE tree",
          len(ws_bool) == 1 and in_source_tree(ws_bool[0]["location"]["uri"]),
          repr(ws_bool))
    check("7.5 no workspace-symbol location is in the build output",
          all("/target/" not in x["location"]["uri"] for x in ws),
          repr([x["location"]["uri"] for x in ws if "/target/" in x["location"]["uri"]][:2]))
    # The file the server sends is the one the user would edit, and it is
    # really there.
    check("7.5 the rewritten target file exists on disk",
          pathlib.Path(urllib.parse.urlparse(ws_bool[0]["location"]["uri"]).path).is_file()
          if ws_bool else False)

    # ---- 7.5, TICKET E10(5): THE QUICK FIX SEES THROUGH THE FILE'S OWN
    # TYPE SYNONYMS.  `Syn.e` reaches `Widget` only through `type Widget =
    # Widget_W` over `import SynSrc as W`, so `ModuleScope.canonicalTypes`
    # holds `Widget_W` and the printer writes `Widget`: the add-signature
    # action used to refuse a signature the file can perfectly well write
    # (33 name occurrences over the corpus, 29 of them `Scan` in
    # `Layout/Scan.e`).
    open_doc("SynSrc.e")
    check("7.5 SynSrc.e clean", client.diagnostics_for(uri("SynSrc.e")) == [])
    open_doc("Syn.e")
    check("7.5 Syn.e clean", client.diagnostics_for(uri("Syn.e")) == [])
    syn_src = raw("Syn.e")
    r = code_actions("Syn.e", 14)               # `boxed = MkWidget_W`
    a = act(r, "add signature: boxed : Widget")
    check("7.5 a synonym-typed binding is offered its signature",
          a is not None, repr(titles(r)))
    check("7.5 the synonym signature goes above the equation",
          a is not None and edits_of(a) == [{
              "range": {"start": {"line": 14, "character": 0},
                        "end": {"line": 14, "character": 0}},
              "newText": "boxed : Widget\n"}], repr(a and edits_of(a)))
    change("Syn.e", apply_ws(syn_src, a), 2)
    check("7.5 the applied synonym signature re-checks clean",
          client.diagnostics_for(uri("Syn.e")) == [])
    change("Syn.e", syn_src, 3)
    check("7.5 Syn.e clean again", client.diagnostics_for(uri("Syn.e")) == [])
    # THE SOUNDNESS CONTROL.  `type Boxed a = Box_W a` says how to write
    # `Box x`; it does NOT make the bare constructor `Box` writable, so
    # `wrapped : Box Widget` stays refused.  Only a NULLARY synonym of a
    # bare constructor is published, and this is the half that must not be.
    r = code_actions("Syn.e", 16)               # `wrapped = MkBox_W MkWidget_W`
    check("7.5 a PARAMETERISED synonym licenses no bare spelling",
          not any(t.startswith("add signature: wrapped") for t in titles(r)),
          repr(titles(r)))

    # ---- 7.5, TICKET E7 (the half that is shippable): AN UNDEFINED TYPE IS
    # WITHHELD WHILE AN IMPORT FAILED, the same rule 6.1(b) applies to
    # undefined TERMS and for the same reason -- a module that did not load
    # contributes no type names either, so "undefined type" is a consequence
    # of the import failure rather than a second thing to fix.  The note
    # cannot carry a `spelling` (`assertTypeClosed` dies once with every free
    # type variable joined into one report), so it carries a FLAG set where it
    # is built -- never a match on its text.  The OPERATOR half of E7 is
    # deferred; the ticket says why.
    open_doc("BadTy.e")
    ds = client.diagnostics_for(uri("BadTy.e"))
    check("7.5 a failed import is the only diagnostic, not the type it would supply",
          len(ds) == 1 and "import NoSuchTypeModule failed" in ds[0]["message"], repr(ds))
    check("7.5 no undefined-type cascade from a failed import",
          not any("undefined type" in d["message"] for d in ds), repr(ds))
    # THE CONTROL, and it is what keeps this from being a filter that deletes
    # the note outright: with NO import failing, an undefined type is a real
    # error and is still reported, at the name.
    open_doc("UndefTy.e")
    ds = client.diagnostics_for(uri("UndefTy.e"))
    check("7.5 with no failed import an undefined type is still reported",
          len(ds) == 1 and "undefined type" in ds[0]["message"]
          and ds[0]["range"]["start"] == {"line": 7, "character": 8}, repr(ds))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("BadTy.e")}})
    client.diagnostics_for(uri("BadTy.e"))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("UndefTy.e")}})
    client.diagnostics_for(uri("UndefTy.e"))

    # ---- SIG-3: the signature-entailment check is REPORTED IN THE EDITOR.
    # `TolerantCheck` reaches `Subst.subsumeType` through its own
    # `typeCheckExplicitBinding` call, inside `guard(Error)`, so the diagnostic
    # arrives as an ordinary Error note with no editor-specific code -- and it
    # must, or a file `bin/ermine` refuses would look clean in the IDE.  The
    # fixture carries the defect and its honest twin, so this pins both halves:
    # the position (the `!` that generated the obligation, not the signature and
    # not the stdlib's `!`), the two-location message, and the SILENCE on the
    # control.
    open_doc("SigEntail.e")
    ds = client.diagnostics_for(uri("SigEntail.e"))
    if os.environ.get("ERMINE_SIGENTAIL", "error") == "off":
        # the ESCAPE HATCH, over the wire: with the check off the file is clean, which is
        # exactly the pre-S3 editor behaviour this fixture would have had.
        check("SIG-3 under `off` the same file is clean", ds == [], repr(ds))
    else:
        check("SIG-3 the too-weak signature is one diagnostic",
              len(ds) == 1, repr(ds))
        check("SIG-3 the diagnostic is the entailment message",
              len(ds) == 1 and
              "the signature does not entail this row constraint" in ds[0]["message"],
              repr(ds[:1]))
        check("SIG-3 the diagnostic carries the second location",
              len(ds) == 1 and "declared at" in ds[0]["message"], repr(ds[:1]))
        check("SIG-3 the diagnostic is an error (severity 1)",
              len(ds) == 1 and ds[0].get("severity") == 1, repr(ds[:1]))
        # `tooWeak r = r ! health` is line 19 (0-based 18); the obligation is generated
        # by the `!`, which is where the editor must put the squiggle -- and the SECONDARY
        # location is the signature line above it (0-based 17), not the equation.
        check("SIG-3 the diagnostic sits on the body's `!`, in this file",
              len(ds) == 1 and ds[0]["range"]["start"]["line"] == 18, repr(ds[:1]))
        check("SIG-3 the second location is the signature line, not the equation",
              len(ds) == 1 and "SigEntail.e:18:11" in ds[0]["message"], repr(ds[:1]))
    client.notify("textDocument/didClose", {"textDocument": {"uri": uri("SigEntail.e")}})
    client.diagnostics_for(uri("SigEntail.e"))

    # Checks must neither read nor write interface files (a stale .ei would
    # let type errors through unreported, and writebacks litter workspaces).
    check("no .ei droppings", not list(FIXTURES.glob("*.ei")),
          repr(list(FIXTURES.glob("*.ei"))))

    r = client.response(client.request("shutdown", None))
    check("shutdown null", r.get("result") is None and "error" not in r)
    client.notify("exit", {})
    check("exit code 0", client.proc.wait(timeout=30) == 0)

    # ---- 7.0: the phase timers are PROPERTY-GATED, both directions.
    # The run that just finished ran the SHIPPED configuration -- no
    # -Dermine.lsp.phases -- so its log must carry no timing line at all.
    # Then one short run WITH the property, which must produce one line per
    # check, on the LOG and never on stdout (Decision 4: stdout is the
    # protocol channel, and a stray write there would have broken framing
    # before this client could report it).
    log1 = pathlib.Path(LOG).read_text(errors="replace")
    check("no phases line without -Dermine.lsp.phases",
          "phases:" not in log1)
    # 7.2's ACCEPTANCE NUMBER, from the server's own check line: the first
    # Anchor check is the cold didOpen and reuses nothing; the second is the
    # same text with three blank lines at the top, and before 7.2 it reused
    # nothing either (every key carried an absolute start line).  Now it
    # must reuse every component it has.
    anchor_runs = re.findall(
        r"check: Anchor read [0-9.]+s, typecheck [0-9.]+s "
        r"\(reused (\d+) of (\d+) components\)", log1)
    check("7.2 two Anchor checks in the log", len(anchor_runs) >= 2, repr(anchor_runs))
    if len(anchor_runs) >= 2:
        check("7.2 the cold open reuses nothing", anchor_runs[0][0] == "0",
              repr(anchor_runs[0]))
        check("7.2 the line-shifted check reuses every component",
              int(anchor_runs[1][0]) > 0 and anchor_runs[1][0] == anchor_runs[1][1],
              repr(anchor_runs[1]))
    # 7.1b's own acceptance number, from the same log: every check reports
    # what the surface cache did, the cold ones reuse NOTHING, and the
    # keystroke ones reuse all but the edited statement and the one before
    # it (the statement before an edit always misses -- its parse examines
    # its successor's first byte, LSP4-7.1a-MARK.md §5).
    splice_runs = re.findall(
        r"check: Splice read [0-9.,]+s, typecheck [0-9.,]+s "
        r"\(reused \d+ of \d+ components\), surface (\d+) of (\d+) statements", log1)
    check("7.1b every Splice check reports the surface reuse", len(splice_runs) >= 6,
          repr(splice_runs))
    if len(splice_runs) >= 6:
        check("7.1b the cold open reuses no statement", splice_runs[0][0] == "0",
              repr(splice_runs[0]))
        check("7.1b a body edit reuses all but the edited statement and its predecessor",
              int(splice_runs[1][0]) >= int(splice_runs[1][1]) - 2 and
              int(splice_runs[1][0]) > 0, repr(splice_runs[1]))
        check("7.1b an edit above reuses across the line shift",
              int(splice_runs[2][0]) > 0, repr(splice_runs[2]))
        check("7.1b the re-open after didClose is cold again",
              splice_runs[-1][0] == "0", repr(splice_runs[-1]))
    check("7.1b no check reuses more statements than the file has",
          all(int(h) <= int(n) for h, n in splice_runs), repr(splice_runs))
    # 7.4's acceptance, from the server's own log.
    # (a) THE BURST PIN: the eight keystrokes 20 ms apart produced exactly ONE
    #     check of Burst.e beyond the didOpen -- one check, one publish, since
    #     every `check:` line has a `diagnostics:` publish line of its own.
    burst_checks = re.findall(r"check: Burst read ", log1)
    burst_pubs = re.findall(r"diagnostics: (didOpen|didChange) Burst\.e -> ", log1)
    check("7.4 sixteen keystrokes in two bursts produce exactly two checks",
          len(burst_checks) == 3, repr(burst_checks) + " (one didOpen + two bursts)")
    check("7.4 one check, one publish",
          burst_pubs == ["didOpen", "didChange", "didChange"], repr(burst_pubs))
    burst_waits = re.findall(r"debounce: Burst\.e waited (\d+)ms "
                             r"\(median (\d+)ms of (\d+) checks, policy (\d+)ms\)", log1)
    check("7.4 each burst waited exactly one window", len(burst_waits) == 2,
          repr(burst_waits))
    check("7.4 a small file's window is the FLOOR, 150 ms",
          len(burst_waits) == 2 and burst_waits[-1][0] == "150"
          and int(burst_waits[-1][1]) < 150, repr(burst_waits))
    # The same for the largest module, whose window must be the CEILING.
    rep_checks = re.findall(r"check: Layout\.Report read ", log1)
    rep_waits = re.findall(r"debounce: Report\.e waited (\d+)ms "
                           r"\(median (\d+)ms of (\d+) checks, policy (\d+)ms\)", log1)
    check("7.4 a burst on the largest module is also exactly one check",
          len(rep_checks) == 2, repr(rep_checks))
    check("7.4 the largest module waits the CEILING, 300 ms",
          len(rep_waits) == 1 and rep_waits[0][0] == "300"
          and int(rep_waits[0][1]) > 300, repr(rep_waits))
    # (b) THE POLICY, on every debounced check in the whole run: what was
    #     waited is what clamp(150, median, 300) says for the samples the
    #     server had, and the median is over at most five of them.
    policy_rows = re.findall(r"debounce: \S+ waited (\d+)ms \(median (\d+)ms of "
                             r"(\d+) checks, policy (\d+)ms\)", log1)
    check("7.4 every debounced check logged its policy", len(policy_rows) >= 3,
          repr(policy_rows[:3]))
    # `waited <= policy`, not `==`: the loop has ONE quiet window and the queue
    # can hold more than one document, so `Diagnostics.quiet()` waits the
    # MINIMUM of the queued documents' windows and then runs their checks back
    # to back.  A document whose own policy is 300 ms can therefore legitimately
    # be checked after a 150 ms wait, because a cheaper sibling was owed a check
    # too.  What must always hold is that nothing waits LONGER than its policy
    # asked, and that the policy is the clamp of the median the server reports.
    bad = [r for r in policy_rows
           if not (int(r[0]) <= int(r[3])
                   and int(r[3]) == min(300, max(150, int(r[1])))
                   and 1 <= int(r[2]) <= 5)]
    check("7.4 waited <= policy == clamp(150, median, 300) on every debounced "
          "check, over at most 5 samples", bad == [], repr(bad[:3]))
    log2 = LOG + ".phases"
    pathlib.Path(log2).write_text("")
    cmd2 = [(("-Dermine.lsp.log=" + log2) if a.startswith("-Dermine.lsp.log=") else a)
            for a in sys.argv[1:]]
    cmd2.insert(1, "-Dermine.lsp.phases=true")
    c2 = Client(cmd2)
    # 7.4: the same short run pins the debounce through the new
    # initializationOption, which is what perf-bench.sh uses to keep measuring
    # against a KNOWN window now that the shipped one is derived from the
    # measured check time.
    c2.response(c2.request("initialize", {"capabilities": {},
                                          "initializationOptions": {"debounce": 250}}))
    c2.notify("initialized", {})
    c2.wait_for(lambda m: m.get("method") == "window/logMessage"
                and "ready" in m["params"]["message"], "readiness logMessage")
    c2.notify("textDocument/didOpen", {"textDocument": {
        "uri": uri("Good.e"), "languageId": "ermine", "version": 1,
        "text": (FIXTURES / "Good.e").read_text()}})
    c2.diagnostics_for(uri("Good.e"))
    good_src = (FIXTURES / "Good.e").read_text()
    c2.notify("textDocument/didChange", {
        "textDocument": {"uri": uri("Good.e"), "version": 2},
        "contentChanges": [{"text": good_src.replace("answer = 42", "answer =  42")}]})
    c2.diagnostics_for(uri("Good.e"))
    c2.response(c2.request("shutdown", None))
    c2.notify("exit", {})
    c2.proc.wait(timeout=30)
    text2 = pathlib.Path(log2).read_text(errors="replace")
    check("the phases line appears with -Dermine.lsp.phases",
          re.search(r"phases: .*\bparse=[0-9.]+ .*\bcheck\.total=[0-9.]+", text2)
          is not None,
          repr([l for l in text2.splitlines() if "phases:" in l][:1]))
    check("7.4 initializationOptions.debounce pins the window",
          "debounce PINNED at 250ms" in text2,
          repr([l for l in text2.splitlines() if "debounce" in l][:2]))
    pinned = re.findall(r"debounce: Good\.e waited (\d+)ms \(median \d+ms of \d+ "
                        r"checks, policy (\d+)ms, PINNED at (\d+)ms\)", text2)
    check("7.4 a pinned window is what the loop waits, whatever the policy says",
          len(pinned) == 1 and pinned[0][0] == "250" and pinned[0][2] == "250"
          and 150 <= int(pinned[0][1]) <= 300, repr(pinned))

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
