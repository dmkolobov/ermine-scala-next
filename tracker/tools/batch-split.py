#!/usr/bin/env python3
r"""Split ONE batch `bin/ermine` output into the per-file `.out` files the verdict tools read.

    tracker/tools/batch-split.py <combined.log> <outdir> <file1.e> <file2.e> ...

WHY.  Since the loader's order computation was made iterative (`StreamTUtils`,
TICKET-editor-and-solver-followups.md item 4) a whole corpus can be loaded in ONE JVM, which
pays the ~11 s stdlib boot once instead of once per file.  `corpus-verdicts.py` and every
comparison built on it read a DIRECTORY of `<name>.out` files, one per corpus file, so a
batch run is split back into that shape here.

HOW.  `Console.loadArgs` loads the files in command-line order, and each load ends with
exactly one terminator line -- `Importing module 'X'` on success, `Unable to load module
from '<path>'` on failure (the path was added with the batch mode; before that the failure
line named nothing, which is why a batch could not be attributed).  So the boot preamble is
everything up to and including the `Loaded N modules` line, and the i-th segment after it
belongs to the i-th file.  The boot preamble is copied into every per-file output, so a
split file looks like a per-file run.

The split is CHECKED, not assumed: the number of terminators must equal the number of files,
and every failure line that names a path must name the file the position says it is.  A
mismatch is an error, not a silent misattribution -- a batch that dies partway (a panic, a
StackOverflow, a timeout) trips it.
"""
import pathlib
import re
import sys

# "Loaded 129 modules (11.9 seconds)", or "Loaded two modules (...)" under
# -Dermine.loadInSeries=true, where `ordinal` spells small counts as words
BOOT = re.compile(r"Loaded \S+ modules? \(")
TERM = re.compile(r"^(Importing module '|Unable to load module)")
FAILED_AT = re.compile(r"^Unable to load module from '([^']+)'")


def main(argv):
    if len(argv) < 4:
        print(__doc__.strip())
        return 2
    log, outdir, files = pathlib.Path(argv[1]), pathlib.Path(argv[2]), argv[3:]
    # split on "\n" only: the boot's progress bar is one physical line full of
    # carriage returns and str.splitlines() would shred it
    lines = log.read_text(errors="replace").split("\n")

    boot_end = -1
    for i, l in enumerate(lines):
        if BOOT.search(l):
            boot_end = i
            break
    if boot_end < 0:
        print("batch-split: no 'Loaded N modules' line in %s -- the boot did not finish" % log)
        return 1
    preamble = lines[: boot_end + 1]

    terms = [i for i, l in enumerate(lines) if i > boot_end and TERM.match(l)]
    if len(terms) != len(files):
        print("batch-split: %d terminator lines for %d files in %s -- the batch did not "
              "finish (the tail of it is below)" % (len(terms), len(files), log))
        for l in lines[terms[-1] if terms else boot_end:][:20]:
            print("    " + l)
        return 1

    outdir.mkdir(parents=True, exist_ok=True)
    start = boot_end + 1
    for f, end in zip(files, terms):
        m = FAILED_AT.match(lines[end])
        if m and m.group(1) != f:
            print("batch-split: segment %d ends with a failure naming %r, expected %r"
                  % (files.index(f), m.group(1), f))
            return 1
        name = f.split("core/examples/", 1)[-1].replace("/", "_")
        (outdir / (name + ".out")).write_text(
            "\n".join(preamble + lines[start : end + 1]) + "\n")
        start = end + 1
    print("batch-split: wrote %d per-file outputs to %s" % (len(files), outdir))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
