#!/usr/bin/env python3
"""experiments.py -- bounded additive closures (rules.py, mine, unverified).

1. the witness W2 under blind saturation (expect: mint cap hit, all mints split at p);
2. controls that must reach a fixpoint (Cut.resSeed; nonempty multi-decomposition seeds);
3. random SATISFIABLE seeds generated from a model: population A has every row nonempty,
   population B allows empty rows.  Records how many hit the mint cap, and for the capped
   ones whether the additive closure also derived `e <- ()` for some empty variable
   (i.e. whether the real loop's makeEmpty defence would have had its trigger).
"""
import random, sys
from rules import *
from collections import Counter

def report(name, res, rho0=None):
    status, G, rho, mints = res
    ch = children(mints)
    top = ch.most_common(1)[0] if ch else None
    empties_detected = None
    if rho is not None:
        emp = [v for v in all_vars(G) if rho[v] == frozenset()]
        emp_input = [v for v in emp if rho0 is not None and v in rho0]
        empties_detected = (len(emp_input), sum(1 for v in emp_input if mk(v, (), ()) in G))
    print(f"{name:34s} {status:9s} cons={len(G):5d} vars={len(all_vars(G)):4d} "
          f"mints={len(mints):3d} split={sum(1 for m in mints if m[0]=='split'):3d} "
          f"res={sum(1 for m in mints if m[0]=='res'):3d} maxchildren={top} "
          f"input-empties(detected)={empties_detected}")
    return status

def witness():
    p, e1, e2, k, m = 0, 1, 2, 100, 101
    G = {mk(p, {e1, e2}, {k}), mk(p, {e2}, {k})}
    rho = {p: frozenset({k, m}), e1: frozenset(), e2: frozenset({m})}
    return G, rho

def res_seed():
    G = {mk(0, {1}, {1}), mk(0, {2}, {2})}
    rho = {0: frozenset({1, 2, 3}), 1: frozenset({2, 3}), 2: frozenset({1, 3})}
    return G, rho

def nonempty_multi():
    # p = {1,2,3,4}; a={1},b={2},c={3},w={2,3}; several decompositions, all rows nonempty
    G = {mk(0, {1, 2, 3}, {4}), mk(0, {1, 4}, {4}), mk(5, {1, 2}, {9}), mk(0, {2, 3}, {1, 4}),
         mk(0, {1}, {2, 3, 4}), mk(0, {4}, {1, 4})}
    rho = {0: frozenset({1, 2, 3, 4}), 1: frozenset({1}), 2: frozenset({2}), 3: frozenset({3}),
           4: frozenset({2, 3}), 5: frozenset({1, 2, 9})}
    return G, rho

def random_seed(rng, nvars, nlabels, ncons, allow_empty):
    labels = list(range(100, 100 + nlabels))
    while True:
        rho = {}
        for v in range(nvars):
            if allow_empty and rng.random() < 0.35:
                rho[v] = frozenset()
            else:
                rho[v] = frozenset(l for l in labels if rng.random() < 0.5) or frozenset({rng.choice(labels)})
        G = set()
        tries = 0
        while len(G) < ncons and tries < 200:
            tries += 1
            v = rng.randrange(nvars)
            others = [u for u in range(nvars) if u != v and rho[u] <= rho[v]]
            rng.shuffle(others)
            grp, used = [], frozenset()
            for u in others:
                if not (rho[u] & used):
                    grp.append(u); used |= rho[u]
                if len(grp) >= rng.choice([1, 2, 2, 3]):
                    break
            conc = rho[v] - used
            if not grp and not conc:
                continue
            c = mk(v, grp, conc)
            if c not in G and not (len(grp) == 0):
                G.add(c)
        if len(G) >= 2 and models(rho, G):
            return G, rho

if __name__ == "__main__":
    print("== 1. witness under blind saturation")
    G, rho = witness()
    report("W2 (mint cap 30)", closure(G, rho, mint_cap=30, con_cap=4000), rho)
    print("== 2. controls")
    G, rho = res_seed();       report("Cut.resSeed", closure(G, rho, 30, 4000), rho)
    G, rho = nonempty_multi(); report("nonempty multi-decomposition", closure(G, rho, 30, 4000), rho)
    print("== 3. random satisfiable seeds")
    for allow_empty, label in [(False, "A all rows nonempty"), (True, "B empty rows allowed")]:
        rng = random.Random(7)
        n = int(sys.argv[1]) if len(sys.argv) > 1 else 150
        caps = 0; det = Counter()
        for i in range(n):
            G, rho = random_seed(rng, nvars=rng.choice([3, 4, 5]), nlabels=3, ncons=rng.choice([2, 3, 4]), allow_empty=allow_empty)
            res = closure(G, rho, mint_cap=25, con_cap=1500)
            status = res[0]
            if status == "cap":
                caps += 1
                emp = [v for v in rho if rho[v] == frozenset()]
                det[(len(emp) > 0, all(mk(v, (), ()) in res[1] for v in emp))] += 1
                if caps <= 3:
                    print(f"  capped seed #{i}:", "; ".join(show(c) for c in sorted(G)),
                          "| rho:", {v: sorted(r) for v, r in rho.items()})
        print(f"population {label}: {n} seeds, {caps} hit the mint cap; "
              f"(has-empty, all-empties-detected) among capped: {dict(det)}")
