# Ticket: replace the letrec shadow-rewrite with a real renamer pass

Status: open · Filed: 2026-08-30 · Prior work: scoping fix + adversarial review, same date

## Background

The scoping fix (see tracker/05-findings.md addendum) lets binders shadow
imports and enclosing binders. References parsed BEFORE a shadowing let/where
binding (earlier siblings; a where clause's body) are repaired afterwards by
substituting outer variable -> block variable over the block (`LocalBlocks`
in parsing/TermNameParsers.scala, applied in TermParsers.let and
StatementParsers.termStatement).

An adversarial review found the rewrite unsound when the shadowed variable is
in scope under MORE THAN ONE name (module-affixed import aliases, re-exports):
the substitution is by variable identity, so it captured references made
through the other names. Current resolution — after the review — is C#-style
refusal (checkShadows): the rewrite map is first restricted to variables that
actually occur in the rewritten material, and if such a variable was in scope
under several names when the block opened, the block is rejected with
"would capture references to X, which is in scope under multiple names".
Alias counting must use the block's OPEN-time snapshots (openCanonicals/
openTerms) — the live canonicalTerms already carries the block's own override
of the shadowed name.

This is sound but rejects programs Haskell accepts (a shadowed name's early
reference simply means the block's binding there, aliases unaffected).

## The proper fix

A renamer for binding blocks: collect the block's binder names BEFORE
resolving its right-hand sides, so every occurrence resolves per-name against
the correct environment and no post-hoc substitution exists. The obstacle is
that resolution is fused into parsing because operator FIXITY drives the
grammar (shunting-yard in TermParsers/PatternParsers), and a block may bind
operators whose fixity affects how sibling rhss parse. Options to explore:
pre-scan statement heads within the laidout block (binder names are the
tokens before '=' / ':' at statement start); or split resolution out of
parsing entirely (big — see docs/ and the parse-time globalization in
ParseState.importing).

## If an LSP is ever on the roadmap, this ticket is Stage 1 of it

A language server needs the renamer's byproducts as first-class data:
occurrence -> binder tables with spans (goto-def, references, rename — rename
also needs the SURFACE name of each occurrence, which the fused design
discards), and scope-at-position (completion). In that case: skip the block
re-parse variant entirely, and design the surface AST for the LSP from the
start — spans on every node, error/hole nodes in the tree — since Stage 2 is
error-tolerant parsing feeding the same AST (scalaparsers halts at the first
committed error, unusable mid-keystroke). A useful Stage 0 exists without any
of this: a resident-session diagnostics-on-save server; note termDef already
relocates each V to its definition site and Var nodes carry occurrence locs,
so best-effort goto-def is extractable from the typed AST today. Interactive
type-at-point makes TICKET-perf-type-inference.md a latency prerequisite.

## Also in scope / known remnants

- `vars` and `sub` for Remember were fixed (Term.scala) because checkShadows'
  occurrence filter depends on `vars` completeness; if new Term forms are
  added, both must cover them or the filter under-counts.
- `:`-operator binders that resolve to an imported global are refused in
  localTermDef (data constructors); ones with their own local fixity
  declaration still bind (pre-fix parity).
- Unfixed review leftovers (all low/medium, unverified): bindingName
  duplicates localName's fixity table (fold into one when touching either);
  localName/localTermName appear dead; do-notation binder and class-body
  no-shadow rules have no direct test; binder-site ambiguity is asymmetric
  (ident binders shadow ambiguous imports, bare-operator binders fail); a
  fixity redeclared by a block binder only groups uses textually after it.
- Review artifacts: workflow wf_c34ccf47-ae4 journal (session dir) has all 19
  findings + verdicts with reproductions.

## Baselines

sbt core/test: 762 props, 761 pass (Constraints.disjunction sound is the
pre-existing failure). tracker/tools/repl-smoke.sh: 3/3 suites.
TestScopes.scala holds 28 scoping properties incl. alias refusal, ?[...]
rebinding, constructor-op refusal, nested blocks.
