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
