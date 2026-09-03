#!/usr/bin/env python3
"""rules.py -- MY OWN (unverified) implementation of Rowpartition.DefaultStep, used only to
check the constructions in ANALYSIS.md.  Each rule is transcribed from its Lean definition
(the Lean is the authority):

  CutStep.reuse/fold   Cut.lean:149        SplitReuseStep  SplitNecessary.lean:115
  SplitStep (mint)     Cut.lean:1009/1026  CancelStep      SplitNecessary.lean:287
  SubstStep            SplitNecessary.lean:388             SelfSubstStep :497
  CommonPartStep       SplitNecessary.lean:553             GResStep        ResGuard.lean:127

A constraint is (lhs, frozenset vars, frozenset conc) = `mk lhs vset conc`.  A system is a
set of them.  Every rule is additive.  A model rho (dict var -> frozenset of labels) is
extended at every mint by the FORCED value (split child = union of its group, resolution
child = rho v - (C|D)) and every emitted constraint is checked against it.
"""
from itertools import combinations

def mk(lhs, vs, conc=()):
    return (lhs, frozenset(vs), frozenset(conc))

def show(c):
    lhs, vs, conc = c
    parts = [str(v) for v in sorted(vs)]
    if conc:
        parts.append("(|" + ",".join(str(k) for k in sorted(conc)) + "|)")
    return f"{lhs} <- ({', '.join(parts)})"

def sat(rho, c):
    lhs, vs, conc = c
    rows = [conc] + [rho[v] for v in vs]
    u = frozenset().union(*rows)
    if rho[lhs] != u:
        return False
    for a, b in combinations(rows, 2):
        if a & b:
            return False
    return True

def models(rho, G):
    return all(sat(rho, c) for c in G)

def all_vars(G):
    s = set()
    for lhs, vs, _ in G:
        s.add(lhs); s |= vs
    return s

def named(G, S):
    return any(vs == S and not conc for (_, vs, conc) in G)

def names(G, z, S):
    return any(lhs == z and vs == S and not conc for (lhs, vs, conc) in G)

def resolved(G, v, K):
    return any(lhs == v and len(vs) == 1 and conc == K for (lhs, vs, conc) in G)

# ---- non-generative rules: each returns the set of conclusions it can add to G ----

def reduce_(c, S, z):
    lhs, vs, conc = c
    return mk(lhs, (vs - S) | {z}, conc)

def cse_reuse(G):
    out = set()
    L = list(G)
    for c1 in L:
        for c2 in L:
            if c1[0] == c2[0]:
                continue
            S = c1[1] & c2[1]
            if len(S) < 2:
                continue
            for (lhs, vs, conc) in G:           # Names G z S
                if vs == S and not conc:
                    z = lhs
                    out.add(reduce_(c1, S, z)); out.add(reduce_(c2, S, z))
    return out

def cse_fold(G):
    out = set()
    L = list(G)
    for c1 in L:
        for c2 in L:
            if c1[0] == c2[0]:
                continue
            S = c1[1] & c2[1]
            if len(S) < 2 or c1[1] != S or c1[2]:
                continue
            out.add(reduce_(c2, S, c1[0]))
    return out

def split_reuse(G):
    out = set()
    for c in G:
        lhs, vs, conc = c
        if not conc or len(vs) < 2:
            continue
        for (u, vs2, conc2) in G:
            if vs2 == vs and not conc2:
                out.add(mk(lhs, {u}, conc))
    return out

def cancel(G):
    out = set()
    L = list(G)
    for c in L:
        for d in L:
            if c is d or c[0] != d[0]:
                continue
            if not (c[2] <= d[2]):
                continue
            lone = c[1] - d[1]
            if len(lone) != 1:
                continue
            (z,) = tuple(lone)
            out.add(mk(z, d[1] - c[1], d[2] - c[2]))
    return out

def subst(G):
    out = set()
    L = list(G)
    for c in L:
        for d in L:
            if d[0] in c[1]:
                out.add(mk(c[0], (c[1] - {d[0]}) | d[1], c[2] | d[2]))
    return out

def self_subst(G):
    out = set()
    for c in G:
        lhs, vs, conc = c
        if lhs in vs and not conc:
            for v in vs:
                if v != lhs:
                    out.add(mk(v, (), ()))
    return out

def common_part(G):
    out = set()
    L = list(G)
    for c in L:
        for d in L:
            if c[0] != d[0] and c[1] == d[1] and c[2] == d[2]:
                out.add(mk(c[0], {d[0]}, ()))
    return out

def gres_reuse(G):
    out = set()
    L = [c for c in G if len(c[1]) == 1]
    for c in L:
        for d in L:
            if c is d or c[0] != d[0]:
                continue
            v = c[0]; (x,) = tuple(c[1]); (y,) = tuple(d[1]); C = c[2]; D = d[2]
            if not (C - D) or not (D - C):
                continue
            for (lhs, vs, conc) in G:
                if lhs == v and len(vs) == 1 and conc == C | D:
                    (z,) = tuple(vs)
                    out.add(mk(x, {z}, D - C)); out.add(mk(y, {z}, C - D))
    return out

NONGEN = [cse_reuse, cse_fold, split_reuse, cancel, subst, self_subst, common_part, gres_reuse]

# ---- minting rules: return list of (premise description, conclusions, child, forced row) ----

def split_mints(G, rho, fresh):
    """SplitApp premises in G; the mint is applied one at a time by the caller."""
    outs = []
    for c in G:
        lhs, vs, conc = c
        if conc and len(vs) >= 2 and not named(G, vs):
            outs.append(c)
    return outs

def apply_split(G, rho, c, u):
    lhs, vs, conc = c
    assert u not in all_vars(G)
    assert not named(G, vs) and conc and len(vs) >= 2 and c in G
    new = {mk(u, vs, ()), mk(lhs, {u}, conc)}
    if rho is not None:
        rho[u] = frozenset().union(*[rho[v] for v in vs])
    return new

def res_mints(G):
    outs = []
    L = [c for c in G if len(c[1]) == 1]
    for c in L:
        for d in L:
            if c is d or c[0] != d[0]:
                continue
            v = c[0]; (x,) = tuple(c[1]); (y,) = tuple(d[1]); C = c[2]; D = d[2]
            if (C - D) and (D - C) and not resolved(G, v, C | D):
                outs.append((v, x, y, C, D))
    return outs

def apply_res(G, rho, pair, z):
    v, x, y, C, D = pair
    assert z not in all_vars(G)
    assert mk(v, {x}, C) in G and mk(v, {y}, D) in G and not resolved(G, v, C | D)
    new = {mk(v, {z}, C | D), mk(x, {z}, D - C), mk(y, {z}, C - D)}
    if rho is not None:
        rho[z] = rho[v] - (C | D)
    return new

class Fresh:
    def __init__(self, G):
        self.n = max(all_vars(G)) + 1
    def __call__(self):
        self.n += 1
        return self.n - 1

def check_new(G, rho, new, what):
    """every conclusion must be sound in rho and must be NEW (productive step)."""
    for c in new:
        if rho is not None and not sat(rho, c):
            raise AssertionError(f"MODEL VIOLATION at {what}: {show(c)}")
    if not (new - G):
        raise AssertionError(f"UNPRODUCTIVE step at {what}")

def closure(G0, rho, mint_cap=50, con_cap=5000, verbose=False):
    """Breadth-first additive closure: saturate the non-generative rules, then apply ONE
    split mint (guard re-checked) or one resolution mint, repeat.  Returns
    (status, G, rho, mints) where status is 'fixpoint' or 'cap'."""
    G = set(G0)
    rho = dict(rho) if rho is not None else None
    if rho is not None:
        assert models(rho, G), "seed is not modelled by rho"
    fresh = Fresh(G)
    mints = []
    while True:
        # non-generative saturation
        changed = True
        while changed:
            changed = False
            for r in NONGEN:
                new = r(G) - G
                if new:
                    if rho is not None:
                        for c in new:
                            assert sat(rho, c), f"MODEL VIOLATION {r.__name__}: {show(c)}"
                    G |= new
                    changed = True
            if len(G) > con_cap:
                return ("cap", G, rho, mints)
        # one mint
        sm = split_mints(G, rho, fresh)
        rm = res_mints(G)
        if not sm and not rm:
            return ("fixpoint", G, rho, mints)
        if sm:
            c = sorted(sm)[0]
            u = fresh()
            G |= apply_split(G, rho, c, u)
            mints.append(("split", c[0], u, c))
            if verbose:
                print(f"  split mint {u} <- {sorted(c[1])} from {show(c)}")
        else:
            pair = sorted(rm)[0]
            z = fresh()
            G |= apply_res(G, rho, pair, z)
            mints.append(("res", pair[0], z, pair))
            if verbose:
                print(f"  res mint {z} at {pair[0]} key {sorted(pair[3] | pair[4])}")
        if len(mints) >= mint_cap:
            return ("cap", G, rho, mints)

def children(mints):
    from collections import Counter
    return Counter((kind, p) for (kind, p, _, _) in mints)
