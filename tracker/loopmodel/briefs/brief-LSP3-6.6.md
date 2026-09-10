# Brief: LSP Stage 3, item 6.6 — quick fixes: add import, add type signature (textDocument/codeAction)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (6.5 is
committed). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs. No commits. Do not touch
`tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.6/`.
Item of record: `tracker/LSP-ROADMAP.md` § Stage 3, item **6.6**, with the STAGE-3 INVARIANTS and Decision (e);
gates `tracker/GATE-POLICY.md`. Read the 6.1 report (`Note.spelling`, the import-failure rule) and the 6.5 report
(the kept per-document `ModuleScope`, the module-name sources) — both feed this item.

HARD RULES: a `codeAction` request fires on every cursor move — it answers from the last check's stored results and
the current buffer text, never a check (Decision e: the signature fix is offered WITHOUT server-side re-checking;
its correctness is measured ONCE by the sweep in 6.6.4). Batch frozen. Single-threaded dispatch. Edits are
`WorkspaceEdit`s on the requesting document only.

## What to do

6.6.1 STORE what the actions need: per document, the published diagnostics with their SOURCE (the `Note`/`Diag` that
      produced each — at least the undefined-term notes with `spelling`, and the exact `range` published) and the
      surface tree (already kept since 6.4). A `codeAction` request carries `range` and `context.diagnostics`
      (what the client shows there) — match by range/message against the stored list rather than trusting the
      client's copy alone; say how.
6.6.2 ADD IMPORT (`kind: "quickfix"`, `diagnostics: [the note]`, `isPreferred` when there is exactly one candidate).
      On an undefined-term note with `spelling = s`: candidates = (a) resident-session modules exporting `s` —
      `env.termNames` keys with `g.string == s`, mapped through `termNameOrigins` so an alias re-export and its
      origin count once (list the origin module; say the rule) — and (b) open sibling documents whose
      `moduleTerms` contain `s`. One action per candidate module M, titled `import M (s)`, whose edit is: if M is
      already imported with an explicit list `import M (a, b)` → insert `, s` before the closing paren (handle
      `using` lists and `as` aliases: an `import M as A (..)` list edit is the same; an `import M using {...}`?
      check the grammar — if s is excluded by `using`, the fix is to REMOVE it from the using list or skip; state
      the rule); if M is imported open (`import M`) → no action needed (then why is s undefined? — it is not from M;
      skip M); if M is not imported → insert `import M (s)` on its own line after the LAST import (after the header
      line when there are none), matching the file's line ending (CRLF-safe: `tracker/` memory says python mangles
      them; here it is Scala — read the buffer's first line ending and reuse it). Operators: `import M ((+))` form —
      check `SImport` grammar for how operators are listed and do it right or refuse for operators (say which).
      Type names (`undefined type` notes, no spelling today — 6.1's E7): out of scope unless a spelling is cheap to
      carry; say.
6.6.3 ADD TYPE SIGNATURE (`kind: "quickfix"` with no diagnostic — or `"refactor.rewrite"`; pick, state): for an
      implicit top-level binding whose GROUP has no `SSigStatement` (surface tree, top level and inside
      `private`/`database` blocks) and whose `TolerantCheck.types` entry exists: an action titled `add signature: f :
      <type>` inserting `f : <rendered type>` on the line above the first equation of the group, at the same
      indentation as that equation, followed by the file's line ending. Rendering: the SAME printer hover uses
      (`Pretty.prettyType(t, -1)`), fully qualified names as hover shows them (if hover shows `Bool` unqualified
      and the file imports Bool, fine; if the rendered type names a module the file does NOT import, the signature
      will not parse — detect that by checking every constructor name in the rendered type against the file's
      scope (the kept `ModuleScope.canonicalTypes`) and either qualify it or REFUSE to offer with the reason in
      the report's failure table). Also a `source`-kind action "add all missing signatures" for the whole file
      (one WorkspaceEdit with every insertion, sorted by line, descending so offsets stay valid — or use ranges,
      which the client applies atomically; say). Operators: `(+) : ...` form; nullary equations fine.
6.6.4 THE SWEEP (Decision e — the ONE correctness measurement): a scratch program (Scala test-scope main or a
      `TestTolerantCheck` property that is NOT part of the shipped suite unless it is fast — say) that, for every
      file of the 180 corpus (stdlib + `core/examples`): runs the tolerant check, renders the add-signature edit for
      EVERY unsigned top-level group, applies all of them to a COPY of the text (in memory), re-runs the tolerant
      read+check on the copy, and classifies: CLEAN (zero diagnostics and notes, and the checked types of every
      group are alpha-equivalent to the originals — use the `.ei` alpha-eq comparator from `tools/G1Compare` or
      compare rendered types after normalisation; say which), PARSE-FAIL (the inserted line does not parse — the
      renderer emitted something the grammar does not read: which construct?), TYPE-FAIL (parses but the declared
      type is rejected or changes another group's type — the kind-meta rendering entropy from G1 is the known
      candidate; row constraints another), SKIPPED (refused to offer, with the reason). Report the table: files,
      groups, insertions, CLEAN, PARSE-FAIL by construct, TYPE-FAIL by construct, SKIPPED by reason; list every
      failing shape with one example rendering each. SHIP BAR: ≥ 95% of insertions CLEAN; below it, the action is
      still shipped only for the constructs that are clean (a syntactic filter on the rendered type — say which)
      and the report says so. The failing shapes become ticket text (draft it) for the printer.
6.6.5 Capability: `codeActionProvider: { codeActionKinds: ["quickfix", "source"] }`; `lsp-client.py` asserts it.
      During boot: `[]`.
6.6.6 TESTS. lsp-smoke, fixture `tracker/lsp-tests/Fix.e` (+ a sibling exporting a name): an undefined `not`
      offers `import Bool (not)`; the client APPLIES the edit, sends the result as didChange, and the diagnostic
      clears on the next publish; a name exported by two modules offers two actions (both titles asserted); a name
      exported by the open sibling offers the sibling's module; an existing `import M (a)` list grows to `(a, s)`;
      an unsigned binding offers `add signature: f : <type>` and applying it re-checks clean (assert zero
      diagnostics) and hover on `f` afterwards shows the same type; a signed binding offers no signature action;
      "add all missing signatures" inserts N lines for N unsigned groups and re-checks clean; a request during boot
      answers `[]`. `TestTolerantCheck`/a new suite: the two edit builders as pure functions — import insertion
      point (no imports / after last import / into an existing list / CRLF file), signature insertion (indentation,
      operator name, inside a private block). Count grows from 6.5's figure.
6.6.7 GATES (Tier 0 + targeted): compile+copyResources; `TestLoopTrace` 720/720; `sbt 'core/testOnly
      *TestTolerantCheck *TestTolerantRead *TestEditorBuffers'` green with counts; `corpus-run.sh --batch <outdir>`
      85 / 69 / 0 over 154; `repl-smoke.sh` 8 groups / 66 checks, goldens unmodified; `lsp-smoke.sh` (6.5's count +
      yours); boot 129; Report.e check time unmoved (one pair).
6.6.8 REPORT `tracker/loopmodel/LSP3-6.6-QUICKFIX.md`: the import-edit rules (every case), the signature-edit rules,
      the SWEEP TABLE with the failing shapes and the ship-bar verdict, the printer ticket draft, the diff summary,
      every gate number. Outcomes GREEN (≥ 95% clean, both actions) / GREEN-FILTERED (below the bar, filtered
      constructs listed) / PARTIAL. No silent weakening; STOP after the report — a reviewer re-runs the gates and
      the sweep once.
