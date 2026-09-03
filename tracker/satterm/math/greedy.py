#!/usr/bin/env python3
"""greedy.py -- explore CHAINS (not saturations): at each step, if a mint is available apply
one (random), otherwise add ONE random non-generative conclusion.  Hitting the mint cap
means a chain with that many mints was found; a fixpoint means this random chain died.
Run many trials per seed.  rules.py is mine and unverified."""
import random, sys
from rules import *
from experiments import witness, res_seed, nonempty_multi, random_seed
from collections import Counter

def greedy_chain(G0, rho0, rng, mint_cap=12, step_cap=600):
    G = set(G0); rho = dict(rho0); fresh = Fresh(G); mints = 0; steps = 0
    while steps < step_cap:
        sm = split_mints(G, rho, fresh); rm = res_mints(G)
        if sm or rm:
            if sm and (not rm or rng.random() < 0.5):
                c = rng.choice(sorted(sm)); u = fresh()
                new = apply_split(G, rho, c, u)
            else:
                pair = rng.choice(sorted(rm)); z = fresh()
                new = apply_res(G, rho, pair, z)
            for c in new: assert sat(rho, c), show(c)
            G |= new; mints += 1; steps += 1
            if mints >= mint_cap:
                return "cap", mints, len(G)
            continue
        avail = set()
        for r in NONGEN:
            avail |= (r(G) - G)
        if not avail:
            return "fixpoint", mints, len(G)
        c = rng.choice(sorted(avail)); assert sat(rho, c), show(c)
        G.add(c); steps += 1
    return "stepcap", mints, len(G)

if __name__ == "__main__":
    trials = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    nseeds = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    rng = random.Random(3)
    for name, (G, rho) in [("W2", witness()), ("resSeed", res_seed()), ("nonempty multi", nonempty_multi())]:
        cnt = Counter(); mx = 0
        for t in range(trials):
            st, m, n = greedy_chain(G, rho, rng); cnt[st] += 1; mx = max(mx, m)
        print(f"{name:20s} trials={trials} {dict(cnt)} max mints={mx}")
    for allow_empty, label in [(False, "A nonempty"), (True, "B empties")]:
        rng2 = random.Random(11); capped_seeds = 0; examples = []
        for i in range(nseeds):
            G, rho = random_seed(rng2, nvars=rng2.choice([3, 4, 5]), nlabels=3, ncons=rng2.choice([2, 3, 4]), allow_empty=allow_empty)
            hit = False
            for t in range(trials):
                st, m, n = greedy_chain(G, rho, rng, mint_cap=10, step_cap=400)
                if st == "cap":
                    hit = True; break
            if hit:
                capped_seeds += 1
                if len(examples) < 3:
                    examples.append(("; ".join(show(c) for c in sorted(G)), {v: sorted(r) for v, r in rho.items()}))
        print(f"population {label}: {capped_seeds}/{nseeds} seeds admit a chain with 25 mints ({trials} random chains each)")
        for e in examples:
            print("   e.g.", e[0], "| rho", e[1])
