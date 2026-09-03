#!/usr/bin/env python3
"""fit.py 'N:v N:v ...'  -- growth diagnostics for a series: log-log slope (polynomial degree),
successive ratios (exponential base if constant), finite differences (constant k-th diff => degree k)."""
import sys, math
pairs = [(float(a), float(b)) for a, b in (x.split(':') for x in sys.argv[1].split())]
pairs.sort()
xs = [p[0] for p in pairs]; ys = [p[1] for p in pairs]
pos = [(x, y) for x, y in pairs if y > 0]
if len(pos) >= 2:
    lx = [math.log(x) for x, y in pos]; ly = [math.log(y) for x, y in pos]
    n = len(lx); mx = sum(lx)/n; my = sum(ly)/n
    slope = sum((a-mx)*(b-my) for a, b in zip(lx, ly)) / sum((a-mx)**2 for a in lx)
    # slope on the upper half only (asymptotic)
    h = pos[len(pos)//2:]
    if len(h) >= 2:
        lx2 = [math.log(x) for x, y in h]; ly2 = [math.log(y) for x, y in h]
        n2 = len(lx2); mx2 = sum(lx2)/n2; my2 = sum(ly2)/n2
        slope2 = sum((a-mx2)*(b-my2) for a, b in zip(lx2, ly2)) / sum((a-mx2)**2 for a in lx2)
    else: slope2 = float('nan')
    print("log-log slope (all): %.2f   (upper half): %.2f" % (slope, slope2))
    print("successive ratios:", ' '.join('%.2f' % (pos[i+1][1]/pos[i][1]) for i in range(len(pos)-1)))
d = ys[:]
for k in range(1, 4):
    d = [d[i+1]-d[i] for i in range(len(d)-1)]
    if not d: break
    print("diff^%d:" % k, ' '.join('%g' % v for v in d))
