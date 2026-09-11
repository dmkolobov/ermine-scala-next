# Brief: LSP Stage 4, item 7.4 — adaptive debounce, derived from the measured check time (ADOPTION: changes shipped behaviour)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (7.1b is
committed: the read on Layout/Report.e is ~0.05 s warm and the round trip ~0.90 s, of which the fixed 300 ms debounce
is now a third). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed. ONE JVM at a time, no background JVMs, no lingering polling shells when you stop. No commits. Do not
touch `tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause (`find`). Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/7.4/`.
Item of record: `tracker/LSP-ROADMAP.md` § "Stage 4", item **7.4** and Decision (e); the STAGE-4 INVARIANTS (no
request-path work; batch frozen — this item touches only `lsp/Diagnostics.scala`'s scheduling and `Resident`'s
timing); `tracker/loopmodel/STAGE4-PRIOR-ART.md` §5(f) (clangd's `DebouncePolicy{Min=50 ms, Max=500 ms,
RebuildRatio=1}` and its rationale); `tracker/PERF-ROADMAP.md` P6; the 7.0 and 7.1b reports for the measured check
times (Report.e: check ≈ 0.55 s warm after 7.1b — read 0.05 + typecheck 0.50; a 44-line file: check ≈ 31 ms, so its
0.33 s round trip is 90% debounce); `tracker/GATE-POLICY.md` (adoption: interleaved A/B; Tier 2 by the reviewer).

WHAT THE DEBOUNCE IS FOR, so the policy is argued rather than copied: it coalesces a burst of keystrokes into one
check (the input stream quiet for D ms), and it must not let checks pile up when a check costs more than the typing
interval. Today D = 300 ms fixed (`Diagnostics.DebounceMillis`), the versioned drop already discards a superseded
check. A small file waits 300 ms for a 31 ms check; a large one waits 300 ms for a 550 ms check.

## What to build
7.4.1 THE POLICY as a stated function: `D = clamp(Min, ratio × C, Max)` where C is a rolling MEDIAN of the last N
      measured check times FOR THAT DOCUMENT (the per-uri check cost is already logged by `Diagnostics.run`; keep the
      last N in `Documents.Doc`), with first-check behaviour stated (no history → Max? or the previous fixed 300?).
      ARGUE the constants from the tables, do not copy clangd's: Min bounded below by the human burst interval you
      choose (keystrokes ~50-150 ms apart while typing — cite what you assume) so a burst still coalesces; Max
      bounded by what a user tolerates as "stale squiggles" (the old 300 was that ceiling; is 500 justified now that
      the check is 0.55 s on the worst file?); ratio 1 means "wait as long as the last check took" — argue whether
      ratio < 1 is right when the versioned drop already protects against pile-up. SHOW the function's output at the
      measured check times: 31 ms (small file), ~550 ms (Report.e warm), ~1.1 s (Report.e cold / an operator edit
      after 7.2), and a hypothetical 3 s file.
7.4.2 NO OSCILLATION: the rolling median must not flip D between two checks' worth of jitter (state the window N and
      show D over the 15-round `perf-client.py` sequence is monotone-then-flat, not sawtooth); a cold check (first
      open, or a 7.2 scope-key drop) must not permanently inflate D — say how the median forgets it.
7.4.3 THE BURST PIN: a test (JVM-local, driving `Diagnostics.install`'s queue with a fake clock or the real `onIdle`
      path through the scripted client) that N keystrokes 20 ms apart produce EXACTLY ONE check and one publish, at
      D_small and at D_large; and that a keystroke arriving during a check produces exactly one more check (the
      versioned drop still holds).
7.4.4 THE A/B (adoption gate), interleaved before/after/before/after at load < 1.3: (a) Report.e round trip
      (`perf-client.py -k 15`; the debounce segment is reported separately — the read/typecheck must be unchanged, the
      debounce moves from 300 to D_large; say the pooled Δ); (b) a SMALL file (`Control/Monad/Reader.e`, 44 lines):
      its round trip must fall from ~0.33 s toward Min + 31 ms — the whole point; (c) a MEDIUM file (~400 lines; pick
      one and say which). The acceptance is the small-file number; the large file must not get worse.
7.4.5 docs/lsp.md: the rule as a function, the constants, the reason, and the measured round trips for the three
      files; the Latency table's "0.30 debounce" row replaced. `ermine.debounce` settings knob? — only if trivial
      (an initializationOption to pin a fixed D for reproducibility of perf-bench: `perf-bench.sh` MUST keep
      measuring with a KNOWN debounce or its numbers stop being comparable across the roadmap — decide: either the
      bench pins D=300 via the option, or it reports the debounce segment separately, which it already does; say
      which and make the bench's before/after numbers comparable).
7.4.6 GATES: Tier 0 (`core/compile core/copyResources`; `TestLoopTrace` 720/720; `corpus-run.sh --batch <outdir>`
      85/69/0 over 154; `repl-smoke.sh` 8/66 goldens unmodified; `lsp-smoke.sh` at the current count + yours — the
      burst pin through the client, and a check that the debounce segment in the log follows the policy; boot 129;
      `.ei` 0 by `find`); the targeted suites (`*TestEditorBuffers *TestTolerantCheck *TestSurfaceCache`); strict path
      untouched; `git diff --stat` == `--stat -w --histogram`; line endings. Tier 2 is the reviewer's.
7.4.7 REPORT `tracker/loopmodel/LSP4-7.4-DEBOUNCE.md`: the policy and its argued constants; the function's output
      table; the oscillation evidence; the burst pin; the three-file A/B; the bench-comparability decision; the docs
      diff; every gate number. Outcomes GREEN / PARTIAL. No silent weakening; STOP after the report — a reviewer
      re-runs the A/B and Tier 2 once.
