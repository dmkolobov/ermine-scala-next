#!/usr/bin/env python3
"""The GATE G4 demo: one scripted run over every capability the Ermine
language server advertises, printing a readable request/response transcript.

This is not a test -- `tracker/tools/lsp-client.py` (lsp-smoke.sh) is the
regression harness, and it asserts far more than this does.  This script
exists so the roadmap's "Gate evidence" can point at a FILE showing the
server answering, in order, rather than reproducing protocol excerpts by hand:

    tracker/tools/lsp-demo.sh > tracker/lsp-tests/G4-demo.txt

Steps 1-11 are the G3 demo, unchanged.  Step 12 is the STAGE-4 section: it is
the only part that reads the SERVER'S OWN LOG (`-Dermine.lsp.log=`), because
what Stage 4 changed -- how much of the file is re-parsed, how much inference
is reused, and how long the quiet window is -- is reported there and nowhere
in the protocol.

Every request is timed (send -> response, client side, so the number includes
the framing).  Responses are trimmed to the part a reader needs; the full
traffic is in the server log named by ERMINE_LSP_LOG.

Usage: lsp-demo.py <java> <args...>   (the full server command line, as
lsp-smoke.sh builds it).
"""
import json
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE.parent / "lsp-tests"
ROOT = HERE.parent.parent
MODULES = ROOT / "core/src/main/resources/modules"
REPORT = MODULES / "Layout/Report.e"      # 1757 lines, the largest stdlib module
REPORT_LINE = 281                         # 1-based; perf-client.py's pinned edit site
REPORT_ANCHOR = "cellsA 0 "               # the digit right after this is what we cycle


def server_log():
    """The log the server was told to write, from its own command line."""
    for a in sys.argv[1:]:
        if a.startswith("-Dermine.lsp.log="):
            return pathlib.Path(a.split("=", 1)[1])
    return None


class LogTail:
    """The lines the server has written since the last look.  Step 12 only."""

    def __init__(self, path):
        self.path = path
        self.offset = path.stat().st_size if path and path.exists() else 0

    def since(self, *prefixes):
        if not self.path or not self.path.exists():
            return []
        with self.path.open("rb") as f:
            f.seek(self.offset)
            data = f.read()
            self.offset = f.tell()
        out = []
        for line in data.decode("utf-8", "replace").splitlines():
            body = line.split(" ", 1)[-1]        # drop the leading timestamp
            if any(body.startswith(x) for x in prefixes):
                out.append(body)
        return out


def uri(name):
    return (FIXTURES / name).as_uri()


def short(u):
    """A uri as a reader wants to see it: the path under the repo root."""
    p = u[len("file://"):] if u.startswith("file://") else u
    try:
        return str(pathlib.Path(p).relative_to(ROOT))
    except ValueError:
        return p


class Client:
    def __init__(self, cmd):
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.next_id = 0
        self.seen = []

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

    def wait_for(self, pred, what, limit=200):
        for _ in range(limit):
            msg = self.read_message()
            if pred(msg):
                return msg
            self.seen.append(msg)
        raise AssertionError("gave up waiting for " + what)

    def response(self, rid):
        return self.wait_for(lambda m: m.get("id") == rid, "response %d" % rid)

    def diagnostics_for(self, u):
        m = self.wait_for(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == u, "diagnostics for " + u)
        return m["params"]["diagnostics"]

    def warnings(self):
        ws = [m["params"] for m in self.seen if m.get("method") == "window/showMessage"]
        self.seen = []
        return ws


client = None
LOG = None


def head(n, title):
    print()
    print("=" * 78)
    print("%-3s %s" % (str(n) + ".", title))
    print("=" * 78)


def say(text=""):
    print(text)


def trim(x):
    """Params as a reader wants them: uris shortened to repo-relative paths,
    and a diagnostic in a codeAction context reduced to its position."""
    if isinstance(x, dict):
        if set(x) >= {"range", "message"}:
            r = x["range"]["start"]
            return "<diagnostic at %d:%d: %s>" % (r["line"], r["character"],
                                                  x["message"].splitlines()[0].split(": ")[-1])
        return {k: trim(v) for k, v in x.items()}
    if isinstance(x, list):
        return [trim(v) for v in x]
    if isinstance(x, str) and x.startswith("file://"):
        return short(x)
    return x


def ask(method, params, note=None):
    """One request, timed, with the params echoed compactly."""
    say("--> %s %s" % (method, json.dumps(trim(params), sort_keys=True)))
    t0 = time.perf_counter()
    r = client.response(client.request(method, params))
    ms = (time.perf_counter() - t0) * 1000.0
    if note:
        say("    (%s)" % note)
    return r.get("result", r.get("error")), ms, r


def pos(name, line, char):
    return {"textDocument": {"uri": uri(name)}, "position": {"line": line, "character": char}}


def open_doc(name, text=None, version=1):
    src = (FIXTURES / name).read_bytes().decode("utf-8") if text is None else text
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": uri(name), "languageId": "ermine", "version": version, "text": src}})
    return src


def change(name, text, version):
    change_uri(uri(name), text, version)


def change_uri(u, text, version):
    client.notify("textDocument/didChange", {
        "textDocument": {"uri": u, "version": version},
        "contentChanges": [{"text": text}]})


def wait_diags(name, label):
    t0 = time.perf_counter()
    ds = client.diagnostics_for(uri(name))
    ms = (time.perf_counter() - t0) * 1000.0
    say("<-- %.0f ms  textDocument/publishDiagnostics %s: %d diagnostic%s  (%s)"
        % (ms, name, len(ds), "" if len(ds) == 1 else "s", label))
    for d in ds:
        r = d["range"]
        say("      %d:%d-%d:%d  severity %d  %s"
            % (r["start"]["line"], r["start"]["character"],
               r["end"]["line"], r["end"]["character"], d["severity"],
               d["message"].splitlines()[0][:110]))
    return ds


def loc_line(l):
    r = l["range"]
    return "%s  %d:%d-%d:%d" % (short(l["uri"]), r["start"]["line"], r["start"]["character"],
                                r["end"]["line"], r["end"]["character"])


def apply_edits(text, edits, eol="\n"):
    """What a client does with a WorkspaceEdit: later positions first."""
    ls = text.split(eol)
    for e in sorted(edits, key=lambda e: (-e["range"]["start"]["line"],
                                          -e["range"]["start"]["character"])):
        a, b = e["range"]["start"], e["range"]["end"]
        ls[a["line"]:b["line"] + 1] = [ls[a["line"]][:a["character"]] + e["newText"]
                                       + ls[b["line"]][b["character"]:]]
    return eol.join(ls)


def main():
    global client, LOG
    LOG = LogTail(server_log())
    client = Client(sys.argv[1:])
    started = time.time()

    say("Ermine language server -- GATE G4 demo transcript")
    say("generated by tracker/tools/lsp-demo.sh (tracker/tools/lsp-demo.py)")
    say("fixtures: tracker/lsp-tests/;  positions are LSP (0-based)")

    # ---------------------------------------------------------------- 1
    head(1, "initialize -- what the server advertises")
    caps, ms, _ = ask("initialize", {"capabilities": {}})
    say("<-- %.0f ms" % ms)
    say("    serverInfo            %s" % json.dumps(caps["serverInfo"]))
    for k in sorted(caps["capabilities"]):
        say("    %-25s %s" % (k, json.dumps(caps["capabilities"][k])))
    say()
    say("    Every request below is answered from the tables the LAST CHECK built.")
    say("    No request runs a parse, an inference or a check (Stage-3 invariant).")

    say()
    say("--> initialized (notification) -- the resident session boots here")
    t0 = time.perf_counter()
    client.notify("initialized", {})
    ready = client.wait_for(
        lambda m: m.get("method") == "window/logMessage" and "ready" in m["params"]["message"],
        "readiness logMessage")
    boot_ms = (time.perf_counter() - t0) * 1000.0
    say("<-- %.1f s   window/logMessage: %s" % (boot_ms / 1000.0, ready["params"]["message"]))

    # ---------------------------------------------------------------- 2
    head(2, "didOpen a BROKEN file -> diagnostics (no save anywhere)")
    broken = open_doc("Broken.e")
    say("--> textDocument/didOpen  tracker/lsp-tests/Broken.e")
    say("    | " + "\n    | ".join(broken.rstrip("\n").split("\n")))
    wait_diags("Broken.e", "two unparseable statements; the healthy ones are still checked")

    # ---------------------------------------------------------------- 3
    head(3, "didChange the fix in -> the diagnostics clear (still no save)")
    fixed = broken.replace("bad1 = = 3", "bad1 = 3").replace("bad2 = ) 3", "bad2 = 3")
    change("Broken.e", fixed, 2)
    say("--> textDocument/didChange  version 2  (`bad1 = = 3` -> `bad1 = 3`,"
        " `bad2 = ) 3` -> `bad2 = 3`)")
    wait_diags("Broken.e", "clean")
    say("    Broken.e on disk is untouched: %s"
        % ((FIXTURES / "Broken.e").read_bytes().decode("utf-8") == broken))

    # ---------------------------------------------------------------- 4
    head(4, "textDocument/definition -- across files, from the buffer")
    r, ms, _ = ask("textDocument/definition", pos("Broken.e", 4, 8))
    say("<-- %.1f ms  %s        (`answer`, imported from Good.e)" % (ms, loc_line(r)))
    r, ms, _ = ask("textDocument/definition", pos("Broken.e", 2, 7))
    say("<-- %.1f ms  %s        (the module named by the import)" % (ms, loc_line(r)))

    # ---------------------------------------------------------------- 5
    head(5, "textDocument/hover -- a top level, a LOCAL binder, a type's kind")
    open_doc("Locals.e")
    wait_diags("Locals.e", "clean")

    def hover(name, line, char, what):
        r, ms, _ = ask("textDocument/hover", pos(name, line, char))
        body = "null" if r is None else r["contents"]["value"].strip().splitlines()[1]
        say("<-- %.1f ms  %-42s %s" % (ms, body, "(" + what + ")"))
        return body

    hover("Locals.e", 34, 0, "a TOP LEVEL: the generalized scheme")
    hover("Locals.e", 34, 6, "its first argument -- SAME letter supply")
    hover("Locals.e", 34, 8, "its second argument")
    hover("Locals.e", 10, 6, "a LET binder at its def-site")
    hover("Locals.e", 11, 5, "the same binder at a use")
    hover("Locals.e", 21, 8, "a polymorphic WHERE helper: no forall on a local")
    hover("Locals.e", 8, 11, "a TYPE name hovers with its KIND")
    hover("Locals.e", 26, 9, "a `case` binder -- the 6.2 residual, absent by mechanism")

    # ---------------------------------------------------------------- 6
    head(6, "textDocument/references and documentHighlight")
    refs_src = open_doc("Refs.e")
    wait_diags("Refs.e", "clean")
    open_doc("RefsSib.e")
    wait_diags("RefsSib.e", "clean")

    client.seen = []
    r, ms, _ = ask("textDocument/references",
                   dict(pos("Refs.e", 8, 6), context={"includeDeclaration": True}))
    say("<-- %.1f ms  %d locations -- a LOCAL: this file only" % (ms, len(r)))
    for l in r:
        say("      " + loc_line(l))
    say("    window/showMessage warnings: %d (a local needs no coverage warning)"
        % len(client.warnings()))

    client.seen = []
    r, ms, _ = ask("textDocument/references",
                   dict(pos("RefsSib.e", 4, 12), context={"includeDeclaration": True}))
    say("<-- %.1f ms  %d locations -- a GLOBAL: every OPEN buffer, def-site included"
        % (ms, len(r)))
    for l in r:
        say("      " + loc_line(l))
    for w in client.warnings():
        say("<-- window/showMessage type %d: %s" % (w["type"], w["message"]))

    r, ms, _ = ask("textDocument/documentHighlight", pos("Refs.e", 9, 14))
    say("<-- %.1f ms  %s" % (ms, ", ".join(
        "%d:%d-%d %s" % (h["range"]["start"]["line"], h["range"]["start"]["character"],
                         h["range"]["end"]["character"],
                         {1: "Text", 2: "Read", 3: "Write"}[h["kind"]]) for h in r)))

    # ---------------------------------------------------------------- 7
    head(7, "prepareRename + rename -- applied by the client, re-checked clean")
    r, ms, _ = ask("textDocument/prepareRename", pos("Refs.e", 9, 14))
    say("<-- %.1f ms  %s" % (ms, json.dumps(r, sort_keys=True)))
    r, ms, raw = ask("textDocument/rename",
                     dict(pos("Refs.e", 9, 14), newName="flagged"))
    say("<-- %.1f ms  WorkspaceEdit over %d file(s)" % (ms, len(r["changes"])))
    edits = r["changes"][uri("Refs.e")]
    for e in edits:
        say("      Refs.e %d:%d-%d -> %r" % (e["range"]["start"]["line"],
                                             e["range"]["start"]["character"],
                                             e["range"]["end"]["character"], e["newText"]))
    renamed = apply_edits(refs_src, edits)
    change("Refs.e", renamed, 2)
    say("--> textDocument/didChange  version 2  (the WorkspaceEdit applied by the client)")
    wait_diags("Refs.e", "the renamed buffer re-checks CLEAN")
    r, ms, _ = ask("textDocument/hover", pos("Refs.e", 8, 6))
    say("<-- %.1f ms  %s   (the renamed local keeps its type)"
        % (ms, r["contents"]["value"].strip().splitlines()[1]))
    change("Refs.e", refs_src, 3)
    say("--> textDocument/didChange  version 3  (reverted)")
    wait_diags("Refs.e", "clean again")
    say()
    say("    Two refusals, for contrast (Decision (d)) -- a CAPTURE, and an operator:")
    for new, what in (("shared", "the new name already resolves in this file"),
                      ("<+>", "an operator's spelling carries its fixity")):
        r, ms, raw = ask("textDocument/rename", dict(pos("Refs.e", 9, 14), newName=new))
        say("<-- %.1f ms  ResponseError %d: %s   (%s)"
            % (ms, raw["error"]["code"], raw["error"]["message"], what))
    say("    Every refusal is checked BEFORE any edit is built, so no partial edit")
    say("    exists on any path.")

    # ---------------------------------------------------------------- 8
    head(8, "textDocument/documentSymbol -- hierarchical, one symbol per GROUP")
    open_doc("Decls.e")
    wait_diags("Decls.e", "clean")
    r, ms, _ = ask("textDocument/documentSymbol", {"textDocument": {"uri": uri("Decls.e")}})
    say("<-- %.1f ms  %d top-level symbols" % (ms, len(r)))

    def show(syms, indent="      "):
        for s in syms:
            rr, sr = s["range"], s["selectionRange"]
            say("%s%-12s kind %-2d range %d:%d-%d:%d  sel %d:%d-%d%s"
                % (indent, s["name"], s["kind"], rr["start"]["line"], rr["start"]["character"],
                   rr["end"]["line"], rr["end"]["character"], sr["start"]["line"],
                   sr["start"]["character"], sr["end"]["character"],
                   ("  detail: " + s["detail"]) if s.get("detail") else ""))
            show(s.get("children", []), indent + "  ")
    show(r)

    # ---------------------------------------------------------------- 9
    head(9, "workspace/symbol -- open buffers plus the resident session")
    open_doc("Nav.e")
    wait_diags("Nav.e", "clean")
    for q, note in (("twice", "a top level of an OPEN buffer"),
                    ("SoftRelation", "a stdlib TYPE, in its SOURCE .e (Decision 5)"),
                    ("just", "a Scala-installed builtin has no source and is NOT listed")):
        r, ms, _ = ask("workspace/symbol", {"query": q})
        say("<-- %.1f ms  %d hit(s)%s   (%s)"
            % (ms, len(r), " [first query: the session name list is built here]"
               if q == "twice" else "", note))
        for s in r[:4]:
            say("      %-16s kind %-2d %-28s %s"
                % (s["name"], s["kind"], s.get("containerName", ""),
                   loc_line(s["location"])))
    say()
    say("    NOTE (ticket E9): a stdlib hit is reported in core/target/.../classes/modules,")
    say("    the copy `sbt core/copyResources` makes -- the resident session loads its 129")
    say("    modules from the classpath, so that is where its positions point.  Editing the")
    say("    file you land in there loses the edit at the next copyResources.")

    # --------------------------------------------------------------- 10
    head(10, "textDocument/completion -- from the last check's tables")
    open_doc("CompleteSib.e")
    wait_diags("CompleteSib.e", "clean")
    comp_src = open_doc("Complete.e")
    wait_diags("Complete.e", "clean")

    def complete(line, char, note, show_n=6):
        r, ms, _ = ask("textDocument/completion", pos("Complete.e", line, char))
        items = r["items"]
        say("<-- %.1f ms  %d item(s), isIncomplete=%s   (%s)"
            % (ms, len(items), r["isIncomplete"], note))
        for i in items[:show_n]:
            say("      %-18s kind %-2d sort %-14s %s"
                % (i["label"], i["kind"], i.get("sortText", ""), i.get("detail", "")))
        if len(items) > show_n:
            say("      ... %d more" % (len(items) - show_n))
        return r

    complete(10, 14, "a local ARGUMENT, offered inside its own equation, with its 6.2 type")
    complete(23, 28, "prefix `n` in `ranked`: the let binder ranks ABOVE the imported `not`")
    complete(3, 9, "MODULE context -- the line's first word is `import`")
    complete(25, 12, "inside a string: the answer is an empty list")

    # A QUALIFIED name: `Maybe.` is not imported here, so the item both
    # replaces the dotted span with the BARE name (a dotted reference does
    # not parse in this dialect) and adds the import line.
    qual = comp_src + "qual = Maybe.isJ\n"
    qline = len(comp_src.rstrip("\n").split("\n"))
    change("Complete.e", qual, 2)
    say("--> textDocument/didChange  version 2  (append `qual = Maybe.isJ`)")
    wait_diags("Complete.e", "the half-typed qualified name does not parse")
    r, ms, _ = ask("textDocument/completion", pos("Complete.e", qline, 16))
    say("<-- %.1f ms  %d item(s)   (QUALIFIED context after `Maybe.`)" % (ms, len(r["items"])))
    for i in r["items"][:3]:
        te = i.get("textEdit", {})
        say("      %-12s filterText %-18s textEdit %s -> %r"
            % (i["label"], i.get("filterText"),
               "%d:%d-%d" % (te["range"]["start"]["line"], te["range"]["start"]["character"],
                             te["range"]["end"]["character"]) if te else "-",
               te.get("newText")))
        for a in i.get("additionalTextEdits", []):
            say("        + additionalTextEdit %d:%d -> %r"
                % (a["range"]["start"]["line"], a["range"]["start"]["character"], a["newText"]))
    change("Complete.e", comp_src, 3)
    say("--> textDocument/didChange  version 3  (reverted)")
    wait_diags("Complete.e", "clean again")

    # --------------------------------------------------------------- 11
    head(11, "textDocument/codeAction -- add import, applied, diagnostic clears")
    open_doc("FixSib.e")
    wait_diags("FixSib.e", "clean")
    fix_src = open_doc("Fix.e")
    wait_diags("Fix.e", "clean")
    undef = fix_src + "undef = not True\n"
    tail = len(undef.rstrip("\n").split("\n")) - 1
    change("Fix.e", undef, 2)
    say("--> textDocument/didChange  version 2  (append `undef = not True` -- `not`"
        " is not in scope)")
    ds = wait_diags("Fix.e", "one undefined term")
    r, ms, _ = ask("textDocument/codeAction",
                   {"textDocument": {"uri": uri("Fix.e")},
                    "range": {"start": {"line": tail, "character": 0},
                              "end": {"line": tail, "character": 0}},
                    "context": {"diagnostics": ds}})
    say("<-- %.1f ms  %d action(s)" % (ms, len(r)))
    for a in r:
        e = list(a["edit"]["changes"].values())[0][0]
        say("      %-40s kind %-9s preferred=%s  edit %d:%d -> %r"
            % (a["title"], a["kind"], a.get("isPreferred", False),
               e["range"]["start"]["line"], e["range"]["start"]["character"], e["newText"]))
    chosen = [a for a in r if "Bool" in a["title"]][0]
    applied = apply_edits(undef, list(chosen["edit"]["changes"].values())[0])
    change("Fix.e", applied, 3)
    say("--> textDocument/didChange  version 3  (%r applied by the client)" % chosen["title"])
    wait_diags("Fix.e", "the applied import CLEARS the diagnostic")

    say()
    say("    And the other quick fix -- ADD TYPE SIGNATURE on an unsigned group:")
    change("Fix.e", fix_src, 4)
    wait_diags("Fix.e", "reverted")
    r, ms, _ = ask("textDocument/codeAction",
                   {"textDocument": {"uri": uri("Fix.e")},
                    "range": {"start": {"line": 9, "character": 0},
                              "end": {"line": 9, "character": 0}},
                    "context": {"diagnostics": []}})
    say("<-- %.1f ms  %d action(s)" % (ms, len(r)))
    for a in r:
        e = list(a["edit"]["changes"].values())[0][0]
        say("      %-40s kind %-9s  insert at %d:%d -> %r"
            % (a["title"], a["kind"], e["range"]["start"]["line"],
               e["range"]["start"]["character"], e["newText"]))
    sig = [a for a in r if a["kind"] == "quickfix"][0]
    change("Fix.e", apply_edits(fix_src, list(sig["edit"]["changes"].values())[0]), 5)
    say("--> textDocument/didChange  version 5  (%r applied)" % sig["title"])
    wait_diags("Fix.e", "the inserted signature re-checks CLEAN")

    # --------------------------------------------------------------- 12
    head(12, "STAGE 4 -- the read, and the wait  (items 7.1a/7.1b, 7.2, 7.4, 7.5)")
    say("The five things Stage 4 changed, on the file it was measured on.  The")
    say("`check:`, `debounce:` and `positions:` lines below are the SERVER'S OWN log")
    say("lines (the file named by -Dermine.lsp.log), quoted verbatim.")

    boot_positions = LOG.since("positions:")   # logged once at install, during boot

    rsrc = REPORT.read_bytes().decode("utf-8")
    reol = "\r\n" if "\r\n" in rsrc else "\n"
    rlines = rsrc.split(reol)
    assert REPORT_ANCHOR in rlines[REPORT_LINE - 1], "the pinned edit site moved"
    rver = [1]
    digit = [0]

    def report_text(prefix="", d=None):
        """The file with one digit of `emptyReport`'s body cycled, optionally
        with `prefix` (a blank line) inserted at the very top."""
        if d is None:
            digit[0] = (digit[0] + 1) % 10
            d = digit[0]
        i = rlines[REPORT_LINE - 1].index(REPORT_ANCHOR) + len(REPORT_ANCHOR)
        out = list(rlines)
        out[REPORT_LINE - 1] = out[REPORT_LINE - 1][:i] + str(d) + out[REPORT_LINE - 1][i + 1:]
        return prefix + reol.join(out)

    def report_check(label):
        """Wait for the diagnostics, then quote what the server logged."""
        t0 = time.perf_counter()
        ds = client.diagnostics_for(REPORT.as_uri())
        ms = (time.perf_counter() - t0) * 1000.0
        say("<-- %.2f s  publishDiagnostics Layout/Report.e: %d diagnostic(s)   (%s)"
            % (ms / 1000.0, len(ds), label))
        for line in LOG.since("debounce:", "check:"):
            say("      | " + line)
        return ms

    say()
    say("(a) COLD OPEN -- no cache to reuse, so the whole file is parsed (7.1b's cost)")
    say("--> textDocument/didOpen  core/src/main/resources/modules/Layout/Report.e"
        "  (%d lines, %d bytes)"
        % (len(rsrc.rstrip(reol).split(reol)), len(rsrc.encode("utf-8"))))
    client.notify("textDocument/didOpen", {"textDocument": {
        "uri": REPORT.as_uri(), "languageId": "ermine", "version": 1, "text": rsrc}})
    report_check("the first check of a freshly opened file")

    say()
    say("(b) ONE KEYSTROKE in a body line -- ONE statement re-parses (7.1a's mark,")
    say("    7.1b's surface cache), and the inference cache keeps its components")
    rver[0] += 1
    change_uri(REPORT.as_uri(), report_text(), rver[0])
    say("--> textDocument/didChange  version %d  (one digit inside `emptyReport`,"
        " line %d)" % (rver[0], REPORT_LINE))
    report_check("read 0.8 s -> 0.05 s; `surface N of 529` is the cache's own counter")

    say()
    say("(c) A BLANK LINE AT THE TOP -- every statement moves, and the INFERENCE")
    say("    cache SURVIVES it: item 7.2 took the absolute line out of the key, so")
    say("    a pure line shift went from 0 of 154 components reused to 115 of 154")
    rver[0] += 1
    change_uri(REPORT.as_uri(), report_text(prefix=reol, d=digit[0]), rver[0])
    say("--> textDocument/didChange  version %d  (a blank line inserted at line 1;"
        " the 529 statements all shift down by one)" % rver[0])
    report_check("7.2's cliff: 0 of 154 BEFORE the item, 115 of 154 after -- the\n       residue of 39 is the prime-suffixed/operator class of 7.2 \u00a71")

    say()
    say("(d) A BURST of five keystrokes 40 ms apart -- ONE check, and the window is")
    say("    the 7.4 policy's, clamp(150 ms, the document's median check, 300 ms)")
    burst = open_doc("Burst.e")
    wait_diags("Burst.e", "clean")
    LOG.since("check:", "debounce:")
    for k in range(5):
        change("Burst.e", burst.replace("y + 2", "y + %d" % (3 + k)), 2 + k)
        time.sleep(0.040)
    say("--> textDocument/didChange x5  versions 2..6, 40 ms apart")
    t0 = time.perf_counter()
    ds = client.diagnostics_for(uri("Burst.e"))
    say("<-- %.0f ms  publishDiagnostics Burst.e: %d diagnostic(s)"
        % ((time.perf_counter() - t0) * 1000.0, len(ds)))
    lines_seen = LOG.since("debounce:", "check:")
    for line in lines_seen:
        say("      | " + line)
    say("    checks for five keystrokes: %d   (the other four were coalesced)"
        % len([x for x in lines_seen if x.startswith("check:")]))
    say("    Report.e's window above is 300 ms -- the CEILING, because its median")
    say("    check is over 300 ms; Burst.e's is the 150 ms FLOOR.  Same rule.")

    say()
    say("(e) TICKET E8 -- a name behind a TAB.  A tab is one character and seven")
    say("    columns; before 7.5 every range on a tabbed line was seven characters")
    say("    to the right of the text it named.")
    open_doc("Tab.e")
    wait_diags("Tab.e", "the two E8 ranges are the operator at 24:6 (it was 24:13) and\n       the undefined term at 19:1 (it was 19:8) -- both behind tabs")
    r, ms, _ = ask("textDocument/hover", pos("Tab.e", 11, 1))
    say("<-- %.1f ms  %s   (the `go` binder at character 1, behind the tab)"
        % (ms, "null" if r is None else r["contents"]["value"].strip().splitlines()[1]))
    r, ms, _ = ask("textDocument/definition", pos("Tab.e", 10, 9))
    say("<-- %.1f ms  %s   (the use `go` -> its binder, on the tabbed line)"
        % (ms, loc_line(r)))
    r, ms, _ = ask("textDocument/prepareRename", pos("Tab.e", 11, 1))
    say("<-- %.1f ms  %s   (6.3 refused this outright: a name behind a tab was"
        " never exact)" % (ms, json.dumps(r, sort_keys=True)))

    say()
    say("(f) TICKET E9 -- a stdlib definition lands in the SOURCE tree, not in the")
    say("    build output the resident session actually loaded from.")
    for line in boot_positions:
        say("      | " + line)
    r, ms, _ = ask("textDocument/definition", pos("Nav.e", 7, 12))
    say("<-- %.1f ms  %s   (`&&`, a stdlib name)" % (ms, loc_line(r)))
    tgt = r["uri"][len("file://"):]
    say("    under core/src/main/resources/modules: %s"
        % str(pathlib.Path(tgt)).startswith(str(MODULES)))
    say("    in the build output (core/target/...): %s" % ("/target/" in r["uri"]))
    say("    the file the editor would open exists: %s" % pathlib.Path(tgt).is_file())

    # --------------------------------------------------------------- 13
    head(13, "shutdown / exit")
    r, ms, _ = ask("shutdown", {})
    say("<-- %.1f ms  %s" % (ms, json.dumps(r)))
    client.notify("exit", {})
    rc = client.proc.wait(timeout=20)
    say("    server exited with code %d" % rc)
    say()
    say("total transcript wall clock: %.1f s (of which the session boot is %.1f s)"
        % (time.time() - started, boot_ms / 1000.0))


if __name__ == "__main__":
    main()
