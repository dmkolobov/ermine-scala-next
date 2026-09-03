#!/usr/bin/env python3
"""dump.py <trace.tsv> <module-file-basename> [N=60] [--segment k]
Prints the first N step/learn records of the module's LARGEST solve segment (by step count),
or of segment k (0-based among the module's constrained segments), with the solve record."""
import sys, re
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from analyze import segments
trace, mod = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 and not sys.argv[3].startswith('--') else 60
k = int(sys.argv[sys.argv.index('--segment') + 1]) if '--segment' in sys.argv else None
segs = []
for seg in segments(trace):
    solve = seg[-1] if seg[-1][0] == 'solve' else None
    if solve is None:
        if mod in ''.join(p[0] for p in seg) or True:
            segs.append(('TAIL', seg))
        continue
    if mod in solve[2] and int(solve[4]) > 0:
        segs.append((solve, seg))
if not segs:
    print('no constrained segment for', mod); sys.exit(0)
if k is None:
    solve, seg = max(segs, key=lambda s: sum(1 for p in s[1] if p[0] == 'step'))
else:
    solve, seg = segs[k]
print('SOLVE:', '\t'.join(solve) if solve != 'TAIL' else 'TAIL (unterminated segment)')
sl = [p for p in seg if p[0] in ('step', 'learn')]
print('step/learn records in segment: %d (showing first %d)' % (len(sl), N))
short = lambda s: re.sub(r'/tmp/\S*/measure/', '', s)
for p in sl[:N]:
    print('  ' + short('\t'.join(p)))
inp = [p for p in seg if p[0].startswith('inpart')]
print('inputs (%d):' % len(inp))
for p in inp: print('  ' + '\t'.join(p[3:]))
