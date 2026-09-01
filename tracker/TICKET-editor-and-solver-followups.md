# Follow-ups from the row-constraint and editor work (2026-09-01)

Everything below is OPEN. Context, evidence and reproduction commands live in
`tracker/ROW-CONSTRAINT-STATE.md` (read its "Traps" section first — it will save
real time) and `tracker/TICKET-row-constraint-decision.md`.

Landed on `scala3-migration` in `03a288d..606f6ae`: `cut` and the per-concrete-label
refutation check adopted as compiler defaults, three example corpora, the Lean
development, and three LSP fixes.

## 1. Label-check diagnostics blame the module, not the call site

`Subst.solve` searches the input constraints for a `Part` mentioning the offending
field and dies at its location, restricted to the file being compiled. When the
offending constraint is not in that file the blame falls back to the module header
and the user learns only the field name.

Cases: `core/examples/incomplete/witness03_grounded_call.e` and
`unsound03_inferred_headers.e`. Both are correctly REJECTED; only the location is
poor. The right blame is the call site that made the set unsatisfiable, which is
what the older "Fields appear twice" path achieves by failing during unification.

## 2. `bin/ermine` cannot resolve a module hierarchy; the editor now can

`lsp/Resident.scala` (commit `793ae57`) resolves sibling imports against the module
hierarchy root. The CLI has no equivalent, so

    bin/ermine core/examples/Ai/ClinicalTrial.e

still reports `Module not found: 'Ai.Common'` unless `Common.e` is passed first.
The editor and the CLI should agree.

## 3. `Constraints.disjunction sound` has been failing for a long time

Its generator discards every case: "Gave up after only 0 passed tests. 501 tests
were discarded." It is the one failure in `core/test`'s 903/904 and predates all of
this work. Fix the generator or retire the property — a permanently red test
teaches everyone to ignore the suite.

## 4. The module loader StackOverflows on batch loads

`StreamTUtils.chop`, in the loader's StateT stream chain, overflows after roughly
two modules of `core/examples/incomplete/` in one `bin/ermine` invocation.
PRE-EXISTING: reproduces identically with `-Dermine.genRules=all
-Dermine.labelCheck=false`. `postOrder` builds its result by left-nested lazy
`Stream` append, which is quadratic and deeply recursive.

Consequence worth knowing: **never compare two corpora by batch-loading them.**
Both runs die partway and the counts are partial; that invalidated one comparison
in this work before it was caught. Compare per-file.

## 5. Audit `checkFile`'s environment handling generally

Two bugs were found there in one session, both in code whose comments described
behaviour it did not implement:

- sibling imports resolved against the file's own directory rather than the module
  hierarchy root (`793ae57`);
- the module's own BUILTINS were scrubbed away, because `Lib` installs them under
  the module they belong to and the scrub went by module name alone (`8c7b952`).
  `Session.reloadChangedModules` had always guarded this with
  `|| builtinEnv.contains(...)`; `checkFile` claimed to scrub "the way :reload's
  scrubber does" and did not.

The remaining scrubbed tables and the `fastMode` path deserve the same scrutiny.

## 6. Hover on declaration sites

Uses of `field` and `foreign` names hover (`73b4600`); the declaration heads do
not, because the renamer emits occurrences for references, not for declaration
heads.

**Warning, tried and reverted.** Making `collectHeads` bind foreign names BROKE
THE COMPILER: `Native/Throwable.e` began reporting `undefined type` and the stdlib
stopped loading. The change was two cases in `walkHeads` plus a `bindForeign`
helper, excluding `SForeignData` because it binds a type. Why binding a foreign
TERM name corrupts TYPE resolution is not understood. Understand that before
retrying — it points at something real in the renamer's namespace model.

## 7. Hover on local binders — "all values should be hoverable"

`Definitions.index` returns `None` for any binder whose kind is not `TopLevel`,
commented `local binder types: perf-ticket territory`. Local inferred types are not
retained anywhere the editor path can see them, so this is a design change with a
measured cost, not a patch. It is the remaining gap against the stated goal that
every value be hoverable.

## 8. Row-solver work not finished

- The label check reads the INPUT partitions. Running it on the saturated set would
  be strictly stronger (`Rowpartition.forced_mono`), but only once every saturation
  rule is known sound or conservative — and `Rules.lean` shows rule 6's documented
  form is not. Settling that would buy more refutations.
- The interaction with `reduce`'s second case is unexamined.
- `cut` removes the measured cliff but is NOT a termination proof: `Cut.lean` shows
  the cut rule set still does not terminate, the remaining obstruction being
  `resolution`, which mints unconditionally.
