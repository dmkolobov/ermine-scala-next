#!/usr/bin/env python3
"""Extract normalized browse.txt from an oracle transcript (G1 harness,
tracker/LSP-ROADMAP.md item 1.1).

The REPL does not echo piped commands: '>> ' is printed as a prompt and
glues to the first output line of the command's response, so sections are
positional.  With ':browse' then ':quit' piped, everything from the first
'>> ' to the end is browse output.  Progress-bar redraws are \r-separated
on one line: keep only the text after the last \r."""
import re, sys

raw, outdir = sys.argv[1], sys.argv[2]
NOISE = re.compile(r'^(Loaded \d+ modules|Importing module|Loading )')

browse, seen_prompt = [], False
with open(raw, encoding='utf-8', errors='replace') as f:
    for line in f:
        line = line.rstrip('\n').split('\r')[-1]
        if line.startswith('>> '):
            seen_prompt = True
            line = line[3:]
        if not (seen_prompt and line.strip()) or NOISE.match(line):
            continue
        if line[0].isspace() and browse:
            # long types wrap onto indented continuation lines: rejoin so
            # sorting compares whole entries, not fragments
            browse[-1] += ' ' + line.strip()
        else:
            browse.append(line)
if not browse:
    sys.exit('g1-normalize: no browse output found — transcript format changed?')
browse.sort()
with open(f'{outdir}/browse.txt', 'w') as f:
    f.write('\n'.join(browse) + '\n')
print(f'normalized: {len(browse)} browse lines')
