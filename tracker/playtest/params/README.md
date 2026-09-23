# Params files to copy, not to read in place

Nothing reads these where they are. They are the two hand-written params
files `tracker/WP-7-MANUAL-CHECKLIST.md` asks you to create, kept here so
you can copy them instead of retyping them. A report's parameters are read
from

    <workspace folder>/.ermine/preview/<Module>/<binding>.params.json

and from nowhere else.

| file | copy it to | used by |
|---|---|---|
| `Sales.report.params.json` | `.ermine/preview/Sales/report.params.json` in the worktree root | checklist section 2.33-2.39 and 2.42 (the S2 params-file steps) |
| `WpSpin.report.params.json` | `.ermine/preview/WpSpin/report.params.json` in the worktree root | checklist section 2.41 and 2.41b (the wedge question and the parameters) |

```sh
cd /home/dmitry/research/ermine/ermine-scala-wt-widget-preview
mkdir -p .ermine/preview/Sales .ermine/preview/WpSpin
cp tracker/playtest/params/Sales.report.params.json  .ermine/preview/Sales/report.params.json
cp tracker/playtest/params/WpSpin.report.params.json .ermine/preview/WpSpin/report.params.json
```

Two things to know before you do that.

1. **Section 2.43-2.52 need NO `.ermine` directory at all** -- they test the
   first pick WRITING one. Do the 2.33-2.42 steps first, then
   `rm -rf .ermine` before 2.43.
2. **A params file is NOT gitignored** (only `*.schema.json` under
   `.ermine/preview` is, by this repository's own `.gitignore`), so a copied
   one shows up in `git status`. Delete `.ermine` when you are done.

`Sales.report.params.json`'s `"$schema": "./report.schema.json"` points at a
file that section 2.43 writes and that does not exist yet. That is
deliberate: VS Code should complain that the schema cannot be resolved, and
the extension should strip the key before sending either way.
