#!/usr/bin/env python3
"""witness.py -- the explicit divergent chain of the shipped ADDITIVE rules on a
SATISFIABLE two-constraint input, checked step by step against rules.py (mine, unverified)
and against the model.

    W2 = { p <- (e1, e2, (|k|)),  p <- (e2, (|k|)) }
    rho p = {k, m}, rho e2 = {m}, rho e1 = {}          (e1 is FORCED empty by W2)

Round 0:  split mint on p <- (e1, e2, k):      u1 <- (e1, e2),  p <- (u1, k)
Round n:  cancel  p <- (e2, k) vs p <- (u_n, k):   e2 <- (u_n)
          subst   e2 <- (u_n) into p <- (e1, e2, k): p <- (e1, u_n, k)
          split mint on p <- (e1, u_n, k):      u_{n+1} <- (e1, u_n),  p <- (u_{n+1}, k)
Every step adds a constraint that was not present; every conclusion holds in rho.
"""
import sys
from rules import *

p, e1, e2, k, m = 0, 1, 2, 100, 101

def run(rounds, rho_e2=frozenset({m})):
    A = mk(p, {e1, e2}, {k})
    B = mk(p, {e2}, {k})
    G = {A, B}
    rho = {p: frozenset({k}) | rho_e2, e1: frozenset(), e2: rho_e2}
    assert models(rho, G)
    fresh = Fresh(G)
    steps = 0
    # round 0
    assert A in split_mints(G, rho, fresh)
    u = fresh()
    new = apply_split(G, rho, A, u); check_new(G, rho, new, "round0 split"); G |= new; steps += 1
    groups = [frozenset({e1, e2})]
    for n in range(1, rounds + 1):
        Pu = mk(p, {u}, {k})
        assert Pu in G and B in G
        # CancelApp c=B d=Pu z=e2 : c.lhs=d.lhs, c.conc <= d.conc, vset c - vset d = {e2}
        assert B[2] <= Pu[2] and (B[1] - Pu[1]) == frozenset({e2})
        link = mk(e2, Pu[1] - B[1], Pu[2] - B[2])
        assert link == mk(e2, {u}, ()) and link in cancel(G)
        check_new(G, rho, {link}, f"round{n} cancel"); G.add(link); steps += 1
        # SubstApp c=A d=link : d.lhs = e2 in vset A
        assert link[0] in A[1]
        newA = mk(A[0], (A[1] - {link[0]}) | link[1], A[2] | link[2])
        assert newA == mk(p, {e1, u}, {k}) and newA in subst(G)
        check_new(G, rho, {newA}, f"round{n} subst"); G.add(newA); steps += 1
        # SplitApp on newA: conc != {}, |vset| = 2, not Named, fresh
        assert newA[2] and len(newA[1]) == 2 and not named(G, newA[1])
        assert newA in split_mints(G, rho, fresh)
        groups.append(newA[1])
        u2 = fresh()
        new = apply_split(G, rho, newA, u2); check_new(G, rho, new, f"round{n} split"); G |= new; steps += 1
        u = u2
    assert models(rho, G)
    assert len(set(groups)) == rounds + 1, "groups must be pairwise distinct"
    return steps, G, rho, groups

if __name__ == "__main__":
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 6
    steps, G, rho, groups = run(rounds)
    print(f"W2 with rho e2 = {{m}}: {rounds} rounds = {steps} productive DefaultSteps, "
          f"{len(G)} constraints, {len(all_vars(G))} variables, all modelled: {models(rho, G)}")
    print("split children of p, one per distinct group:")
    for g in groups:
        print("   ", sorted(g))
    print("ranks: rho p =", sorted(rho[p]), "; every u_i =", sorted(rho[max(all_vars(G))]),
          "; rho e1 =", sorted(rho[e1]))
    steps, G, rho, groups = run(rounds, rho_e2=frozenset())
    print(f"W2 with rho e2 = {{}} (everything empty): {steps} steps, modelled: {models(rho, G)}")
    print("final system (rounds=%d):" % rounds)
    for c in sorted(G):
        print("   ", show(c))
