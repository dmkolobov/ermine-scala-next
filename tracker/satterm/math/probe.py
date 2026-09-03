import random
from rules import *
from experiments import nonempty_multi
G, rho = nonempty_multi()
rng = random.Random(5)
G = set(G); rho = dict(rho); fresh = Fresh(G); mints = 0; steps = 0
while steps < 3000 and mints < 40:
    sm = split_mints(G, rho, fresh); rm = res_mints(G)
    if sm or rm:
        if sm and (not rm or rng.random() < 0.5):
            c = rng.choice(sorted(sm)); u = fresh(); new = apply_split(G, rho, c, u)
            print(f"split u{u} <- {sorted(c[1])} at parent {c[0]} from {show(c)}   rank(child)={len(rho[u])} rank(parent)={len(rho[c[0]])} rows child={sorted(rho[u])}")
        else:
            pair = rng.choice(sorted(rm)); z = fresh(); new = apply_res(G, rho, pair, z)
            print(f"res z{z} at parent {pair[0]} key {sorted(pair[3]|pair[4])} rank(child)={len(rho[z])} row={sorted(rho[z])}")
        for c in new: assert sat(rho, c), show(c)
        G |= new; mints += 1; steps += 1; continue
    avail = set()
    for r in NONGEN: avail |= (r(G) - G)
    if not avail: print("fixpoint"); break
    c = rng.choice(sorted(avail)); assert sat(rho, c), show(c); G.add(c); steps += 1
print("empties among vars:", [v for v in all_vars(G) if not rho[v]])
