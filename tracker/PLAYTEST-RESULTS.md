# Playtest results: the Ermine preview in VS Code (0.1.14)

**Who fills this in:** you, while you run `tracker/WP-7-MANUAL-CHECKLIST.md`.
**Who reads it:** the orchestrator. I read this file and act on it — every
FAIL becomes a ticket or a fix, every SKIP becomes a decision about whether
we still need that step, and the five open questions at the top of the guide
(Q21, the restart default, the U7 `.gitignore` reading, the command's title,
the panel's U1-U7) get asked again with your answers in hand.

**Date run:** ______  **Extension:** 0.1.14 —
`editor/vscode/ermine-lang-0.1.14.vsix`, packaged 2026-09-23 by WP-10 stage 5
(size and file count in `tracker/PLAYTEST-SETUP.md` §3). **Not the
`ermine-lang-0.1.9.vsix` beside it**, which has no params command, no panel and
no writers. Or run from source (`code --extensionDevelopmentPath=editor/vscode`).
**VS Code:** ______  **OS:** ______  **Window:** single-root (if you ever added a
second folder, say so — three settings stop working and several Group C rows
become meaningless)

## How to fill it in

- **Result:** `PASS`, `FAIL`, or `SKIP`. Leave it blank if you did not reach the step.
- **What you saw:** ONE line. If it matched the guide exactly, `as written` is enough.
- **Notes:** anything else — a number you were asked to write down (C28), a
  decision you want to register (B16's U7 reading), a step that was awkward.
- **For every FAIL: paste the Ermine output channel's text** into a fenced block
  under the table, headed with the step id. The channel is **Ermine: Show
  Language Server Output**; select all of it and paste. Without that text a FAIL
  is usually not actionable.
- Steps marked OPTIONAL in the guide are fine to `SKIP`; say why in the notes.

---

## Group A — the core loop

| Step | Was | What it checks | Result | What you saw | Notes |
|---|---|---|---|---|---|
| **A1** | [§0] | Activate; the session boots (`Ermine session ready: …`) |  |  |  |
| **A2** | [1.1] | The file quick pick |  |  |  |
| **A3** | [1.2] | The binding quick pick, populated by type |  |  |  |
| **A4** | [1.3, 1.4] | The render: status bar, untitled tab, the answer (Q21's 500) |  |  |  |
| **A5** | [1.5] | Edit the report's file and save -> generation 2, in place |  |  |  |
| **A6** | [new] | Invalidation of an IMPORTING module (stdlib `Json.e`) |  |  |  |
| **A7** | [1.8] | Render Report to JSON re-renders into the same tab |  |  |  |
| **A8** | [1.7] | Under `target: json`: the JSON tab and NO panel |  |  |  |
| **A9** | [2.1] | Closing the tab does not resurrect it |  |  |  |
| **A10** | [2.2] | The pick is remembered per workspace |  |  |  |
| **A11** | [new] | The status bar's states and tooltips |  |  |  |
| **A12** | [1.9-1.12] | The Q11 placement-404 watcher: away, render, back |  |  |  |
| **A13** | [1.13] | A binding that does not exist: 404 with no `reason` |  |  |  |
| **A14** | [1.6] | Put the fixtures back |  |  |  |
| **A15** | [2.3] | OPTIONAL `ermine.preview.roots` validation |  |  |  |
| **A16** | [2.4] | OPTIONAL `ermine.maxHeap` floor and restart |  |  |  |
| **A17** | [2.5] | OPTIONAL `timeoutSeconds` type check |  |  |  |
| **A18** | [2.6] | OPTIONAL a file with no report-typed binding |  |  |  |

## Group B — params files

| Step | Was | What it checks | Result | What you saw | Notes |
|---|---|---|---|---|---|
| **B1** | [2.43, 2.33] | The first pick writes three files (Q21's 500 is a PASS) |  |  |  |
| **B2** | [2.44] | …and opens the params file without stealing focus |  |  |  |
| **B3** | [2.45, 2.45b] | One render per coalescing window; the second is not a question |  |  |  |
| **B4** | [2.49a] | Edit the dates -> a document (Q21) |  |  |  |
| **B5** | [2.47] | `$schema` not squiggled; a wrong key is (D1 go/no-go) |  |  |  |
| **B6** | [2.48] | Completion offers the keys and the enum values (D3 go/no-go) |  |  |  |
| **B7** | [2.50] | Editing the params TYPE updates the schema file (G17) |  |  |  |
| **B8** | [2.34] | Save the params file: ONE render, in place |  |  |  |
| **B9** | [2.35] | A change from OUTSIDE the editor (the surviving mutant) |  |  |  |
| **B10** | [new] | A reordered file renders the same document |  |  |  |
| **B11** | [2.36] | Invalid JSON refuses in the tab, renders nothing |  |  |  |
| **B12** | [2.37] | An empty file is not `{}` |  |  |  |
| **B13** | [2.38] | Delete the file: a 400 naming the key, said once |  |  |  |
| **B14** | [2.39] | A wrong key earns the server's own 400; no wedge |  |  |  |
| **B15** | [2.49] | A second pick never rewrites the params file |  |  |  |
| **B16** | [2.46] | `git status` shows the params file and NOT the schema (U7) |  |  |  |
| **B17** | [2.42] | A credential-looking key warns once, never blocks |  |  |  |
| **B18** | [2.40] | A report outside every workspace folder |  |  |  |
| **B19** | [2.52b] | OPTIONAL a symlink anywhere on the way refuses |  |  |  |
| **B20** | [2.51] | OPTIONAL a read-only workspace falls back to `{}` |  |  |  |
| **B21** | [new] | OPTIONAL WpInt: a params type that is NOT a JSON object (its sentence CHANGED in 0.1.10) |  |  |  |
| **B22** | [new] | `Ermine: Write Params Skeleton` asks in a MODAL; declining leaves the file |  |  |  |
| **B23** | [new] | …accepting replaces it, refreshes the schema, opens it, re-renders |  |  |  |
| **B24** | [new] | The command with NO params file: no dialog, a create |  |  |  |
| **B25** | [new] | The ORPHAN notice after renaming a binding, once per session |  |  |  |
| **B26** | [new] | The orphan notice's button writes for the CURRENT pick |  |  |  |
| **B27** | [new] | OPTIONAL WpEnum/WpMaybe/WpJson/WpUnit: each non-object root's sentence |  |  |  |

## Group C — the wedge guard and the restart

| Step | Was | What it checks | Result | What you saw | Notes |
|---|---|---|---|---|---|
| **C1** | [2.7-2.9] | Wedge it: banner, orange bar, watchdog answer |  |  |  |
| **C2** | [2.10] | A second render is refused immediately |  |  |  |
| **C3** | [2.13, 2.14] | The server dies and comes back, UNWEDGED pick |  |  |  |
| **C4** | [2.22] | A wedged server that dies by itself does NOT re-render (Q17) |  |  |  |
| **C5** | [2.15] | The Restart button: still no re-render, `held` |  |  |  |
| **C6** | [2.16] | The question, and exactly what it says |  |  |  |
| **C7** | [2.17] | Dismissal is never consent |  |  |  |
| **C8** | [2.19] | Render anyway renders, and wedges again |  |  |  |
| **C9** | [2.18] | Once per restart, never stacked |  |  |  |
| **C10** | [2.20] | Any `.e` save clears the hold; `.md` clears nothing |  |  |  |
| **C11** | [2.21] | With the mark cleared, a restart DOES re-render |  |  |  |
| **C12** | [2.41] | Changing what is SENT clears the hold |  |  |  |
| **C13** | [2.41b] | A re-format while held ASKS instead of rendering |  |  |  |
| **C14** | [2.41c] | Asked ONCE, not once per save |  |  |  |
| **C15** | [2.41d] | A roots change that changes nothing also asks |  |  |  |
| **C16** | [2.52] | A wedged report is never handed a schema request |  |  |  |
| **C17** | [2.23] | The mark survives a window reload, and says restored |  |  |  |
| **C18** | [2.24] | The mark is the CURRENT pick's only |  |  |  |
| **C19** | [2.26] | OPTIONAL `died-mid-render` (WpBlow, maxHeap 256m) — M1 |  |  |  |
| **C20** | [2.27] | OPTIONAL the `{stuck:false}` recovery clear (Q10) |  |  |  |
| **C21** | [2.28] | THE DEFAULT CHANGES NOTHING |  |  |  |
| **C22** | [2.29] | The feature: the automatic restart at the grace |  |  |  |
| **C23** | [2.30] | OPTIONAL a slow render is NOT killed |  |  |  |
| **C24** | [2.31] | Turning it off mid-grace disarms |  |  |  |
| **C25** | [2.31b] | Turning it ON while already wedged ARMS |  |  |  |
| **C26** | [2.31c] | OPTIONAL the floor defers and says so |  |  |  |
| **C27** | [2.32] | No double restart; the user's is never refused |  |  |  |
| **C28** | [2.32a] | The state log; what the FIRST client logs (write it down) |  |  |  |
| **C29** | [2.32b] | The stop that does not come back; two untested glue paths |  |  |  |
| **C30** | [new] | Exactly ONE `lsp.Main` after every restart |  |  |  |
| **C31** | [2.32c] | OPTIONAL restart during the first-run classpath warm-up |  |  |  |
| **C32** | [2.12, 2.25] | Put the settings back |  |  |  |

## Group E — the panel (set `ermine.preview.target` to `panel` first)

| Step | Was | What it checks | Result | What you saw | Notes |
|---|---|---|---|---|---|
| **E1** | [new] | The panel opens BESIDE; the cursor stays in your editor; no JSON tab |  |  |  |
| **E2** | [new] | `Doc.SalesReport` draws (the scorecard); no banner, no `preview panel: widget` line |  |  |  |
| **E3** | [new] | Console: no CSP refusal except at most `tmbllsprite.png`; list any other URL verbatim |  |  |  |
| **E4** | [new] | `400: the key "fromDy" is not allowed here ($.params.fromDy)`; document dimmed |  |  |  |
| **E5** | [new] | Hidden panel + wedge -> shown: the stuck banner. **F1: (a) posts reach a hidden webview / (b) they do not / (c) not determined** |  |  |  |
| **E6** | [new] | The panel's Restart button: restart, then HELD, no re-render; `WpInt.e` put back |  |  |  |
| **E7** | [new] | `bundle:watch` + a `scorecard.ts` edit: ONE reload line, the title changes, no restart |  |  |  |
| **E8** | [new] | Files deleted -> *not built* page; rebuilt -> back. **Folder deleted: (i) page flipped? (ii) rebuild noticed?** |  |  |  |
| **E9** | [new] | `table` draws through the writers' `runTabular`, three rows, no error box |  |  |  |
| **E10** | [new] | The `pieChart` (`Share of sales`) and the bar chart draw |  |  |  |
| **E11** | [new] | OPTIONAL, NO FIXTURE: a style-box click is inert (SKIP unless you wrote a report) |  |  |  |
| **E12** | [new] | Two commands, one panel; close it and re-run: a new one, never two |  |  |  |
| **E13** | [new] | `target: json` = tab only; `both` = tab then panel; `"tab"` refused once by name |  |  |  |
| **E14** | [new] | `writersPath` -> an empty folder: the writers banner, dimmed, legacy error boxes; `""` and a command put it right |  |  |  |

## Group D — not observable by any step (record as SKIP)

These are here so that nobody later mistakes silence for evidence. `SKIP` is
the right answer for all of them; the notes column is for anything you
happened to notice that bears on one.

| # | What cannot be told | Result | Notes |
|---|---|---|---|
| **D1** | `client.stop()` really killing a wedged server process | SKIP |  |
| **D2** | whether a fresh `LanguageClient` emits an initial `Stopped -> Starting` | SKIP |  |
| **D3** | whether `createFile(..., contents)` is an ATOMIC create | SKIP |  |
| **D4** | whether VS Code's `contents` option is honoured at all | SKIP |  |
| **D5** | whether `workspace.fs.createDirectory` really is recursive | SKIP |  |
| **D6** | whether the params file's creation fires `onDidCreate` | SKIP |  |
| **D7** | whether a new `.gitignore` reaches the SCM view without a refresh | SKIP |  |
| **D8** | that `workspace.fs.readFile` answers `FileNotFound` with that `code` | SKIP |  |
| **D9** | that `stat` answers a size, and the 1 MiB cap is checked before the read | SKIP |  |
| **D10** | that a params-file read can HANG (the 5-second bound) | SKIP |  |
| **D11** | cross-window `Memento` visibility of the wedge mark | SKIP |  |
| **D12** | whether VS Code re-reads a relative `$schema` file changed on disk (G17) | SKIP |  |
| **D13** | remote and virtual workspaces (out of scope, will not work) | SKIP |  |
| **D14** | a file outside the workspace changing; `workspace.fs` reports no links there | SKIP |  |
| **D15** | the surviving mutants, other than through B9 and C29 | SKIP |  |
| **D16** | `bin/ermine-serve` and non-VS-Code clients (Q18) | SKIP |  |
| **D17** | whether a MULTI-ROOT window really stops reading window-scoped settings | SKIP |  |
| **D18** | the `.vsix` ships no licence file (`package.json` points at a missing `../../LICENSE`) | SKIP |  |

---

## Output channel text for every FAIL

One block per failing step, headed with the step id. Delete the example.

### (example — delete)

```
preview: render 1 (generation 1; the report was picked; empty parameters)
Ermine session ready: 129 modules in 11.8s
```

---

## The five open questions, with room for your answer

| | Question | Your answer |
|---|---|---|
| **Q21** | The first pick of `Sales.report` answers a 500 with today's dates (A4, B1, B4). Options recorded neutrally in §13 of `tracker/JSON-WIDGET-PLAYGROUND.md`: **(a)** keep today's dates and accept the 500 until you edit them; **(b)** give `Sales.e`'s relations a header hint so an empty result encodes — which raises the wider question of whether ANY report returning no rows hitting this 500 is an engine limitation deserving its own ticket; **(c)** change the date rule itself |  |
| **Restart default** | `ermine.preview.restartAfterStuckSeconds` ships at `0` = never, only because this file had never been run. After C21–C28, should the default move, and to what? |  |
| **U7 `.gitignore`** | S3 writes only the self-contained `.ermine/preview/.gitignore` and this repository carries `**/.ermine/preview/**/*.schema.json` in its own root `.gitignore` (B16). The alternative — the extension OFFERING to add the line to YOUR root `.gitignore` — is named and not built. Which do you want? |  |
| **Q22 the command's title** | **Ermine: Render Report to JSON** renders into the PANEL under the default target (E12, E13). Keep the title, or rename it (e.g. **Ermine: Render Report**)? A rename changes the palette entry every checklist step names, so it was not done (the WP-10 S2 review's N4) |  |
| **Q23 the panel's U1-U7** | Seven design choices for the panel were TAKEN BY THE ORCHESTRATOR on the WP-10 design review's recommendations; **you were not asked any of them**: U1 a `target` setting, default `panel`, tab kept; U2 `retainContextWhenHidden` on plus a resync; U3 the bundle from the checkout, the writers from a setting with a sibling default; U4 Restart as the panel's only button; U5 no `blob:`; U6 deferred relations refused, not fetched (**taken on a premise that proved FALSE: see Q24**); U7 the extension's tests gate every commit. Which, if any, do you want changed? (E5 and E8 are the steps whose results bear most on U2 and U3) |  |
| **Q24 deferred relations and WP-10's done-when fixture** | U6 (refuse deferred relations, no fetch) was taken on the design review's F2, "the preview never mints a deferred token". **That is false**: `core/src/test/resources/doc/Sales.e:115` asks for `Deferred` itself, and the S1 capture of its render holds a token, so in the panel that table is an error box (E2). WP-10's done-when says "`Sales` renders inline", which Sales as written cannot meet. Options: **(a)** keep the refusal and make an inline fixture the done-when (`Doc/SalesReport.e`, E2/E9/E10); **(b)** a preview-side override that forces inline delivery, so Sales's deferred table arrives inline; **(c)** build the fetch message pair U6 deferred (the panel asks the extension, the extension asks the server); **(d)**, with any of these, register `heading`/`text` renderers so Sales's other two boxes draw. Which? |  |

## Anything else

Free text. What surprised you, what was tedious, what you would want the
preview to do that it does not.
