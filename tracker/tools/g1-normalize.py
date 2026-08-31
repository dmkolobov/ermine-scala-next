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
        # a browse ENTRY is "name : type"; the pretty-printer wraps long
        # types onto continuation lines (indented OR at column 0), so
        # anything not shaped like an entry start is a continuation
        is_entry = re.match(r'^\S+ : ', line) is not None
        if not is_entry and browse:
            browse[-1] += ' ' + line.strip()
        else:
            browse.append(line)
if not browse:
    sys.exit('g1-normalize: no browse output found — transcript format changed?')

def canon_exists(line):
    """Sort binders and atoms inside every (exists <binders>. <atoms>)
    block: the solver emits residual constraints in draw order, which is
    not semantics (the .ei alpha-eq comparator is the authority)."""
    out, i = [], 0
    while True:
        j = line.find('(exists ', i)
        if j < 0:
            out.append(line[i:]); break
        out.append(line[i:j])
        depth, k = 0, j
        while k < len(line):
            if line[k] == '(': depth += 1
            elif line[k] == ')':
                depth -= 1
                if depth == 0: break
            k += 1
        body = line[j + len('(exists '):k]
        # split binders from atoms at the first top-level '. '
        d, dot = 0, -1
        for x, ch in enumerate(body):
            if ch == '(': d += 1
            elif ch == ')': d -= 1
            elif ch == '.' and d == 0 and x + 1 < len(body) and body[x+1] == ' ':
                dot = x; break
        if dot < 0:
            out.append(line[j:k+1]); i = k + 1; continue
        binders, atoms = body[:dot], body[dot+2:]
        bs = re.findall(r'\([^()]*\)|\S+', binders)
        d, cur, ats = 0, '', []
        for ch in atoms:
            if ch == '(': d += 1
            elif ch == ')': d -= 1
            if ch == ',' and d == 0:
                ats.append(cur.strip()); cur = ''
            else:
                cur += ch
        if cur.strip(): ats.append(cur.strip())
        out.append('(exists ' + ' '.join(sorted(bs)) + '. ' + ', '.join(sorted(canon_exists(a) for a in ats)) + ')')
        i = k + 1
    return ''.join(out)

browse = [canon_exists(l) for l in browse]
browse.sort()
with open(f'{outdir}/browse.txt', 'w') as f:
    f.write('\n'.join(browse) + '\n')
print(f'normalized: {len(browse)} browse lines')
