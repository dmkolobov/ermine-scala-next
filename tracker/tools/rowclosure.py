#!/usr/bin/env python3
r"""rowclosure.py -- faithful additive-closure explorer for `Rowpartition.DefaultStep`.

    tracker/tools/rowclosure.py builtin gseed --rules gres # unsat: hits the mint cap (resolution alone)
    tracker/tools/rowclosure.py builtin crulew             # unsat: hits a cap
    tracker/tools/rowclosure.py builtin resseed            # satisfiable: fixpoint
    tracker/tools/rowclosure.py builtin twodecomp --strategy chase   # SATISFIABLE, diverges (see RESULT)
    tracker/tools/rowclosure.py run SEED.json [--split-key] [--mint-cap 400] [--con-cap 20000]
                                [--scala-dedup] [--strategy bfs|mintfirst|lazy|worklist|eager|dfs|random|chase] [--tail 60]
                                [--time-limit SEC] [--rules cse,splitreuse,cancel,subst,selfsubst,commonpart,split,gres]
    tracker/tools/rowclosure.py search --seeds 20000 [--rng 1] [--jobs 4] [--out DIR] [--json F]
    tracker/tools/rowclosure.py families [--max-size 6] [--family-reps 3] [--jobs 4] [--out DIR]

WHAT IT MODELS.  The shipped row-constraint rule set (`ermine.genRules=cut`,
`ermine.resGuard=true`) as the ADDITIVE step relation `Rowpartition.DefaultStep` of
tracker/lean/Rowpartition/DefaultDiverge.lean:

    DefaultStep = NonGenStep + SplitStep (mint) + GResStep (guarded resolution)

with every rule read off its Lean definition (the Lean is the authority):

  CutStep.reuse    (Cut.lean)            c1,c2 in G, c1.lhs != c2.lhs, |vset c1 & vset c2| >= 2,
                                          Names G z (vset c1 & vset c2)
                                          ==> reduce c1 S z, reduce c2 S z
                                          where reduce c S z = mk c.lhs ({z} | (vset c - S)) c.conc
  CutStep.fold     (Cut.lean)            same pair, vset c1 = S, c1.conc = {}  ==> reduce c2 S c1.lhs
  SplitReuseStep   (SplitNecessary.lean) c.conc != {}, |vset c| >= 2, Names G u (vset c)
                                          ==> mk c.lhs {u} c.conc
  SplitStep (MINT) (Cut.lean SplitApp)   c.conc != {}, |vset c| >= 2, not Named G (vset c), u fresh
                                          ==> mk u (vset c) {}, mk c.lhs {u} c.conc
  CancelStep       (SplitNecessary.lean) c.lhs = d.lhs, c.conc <= d.conc, vset c - vset d = {z}
                                          ==> mk z (vset d - vset c) (d.conc - c.conc)
  SubstStep        (SplitNecessary.lean) d.lhs in vset c
                                          ==> mk c.lhs ((vset c - {d.lhs}) | vset d) (c.conc | d.conc)
  SelfSubstStep    (SplitNecessary.lean) c.lhs in vset c, c.conc = {}, v in vset c, v != c.lhs
                                          ==> mk v {} {}
  CommonPartStep   (SplitNecessary.lean) c.lhs != d.lhs, vset c = vset d, c.conc = d.conc
                                          ==> mk c.lhs {d.lhs} {}
  GResStep.mint    (ResGuard.lean)       mk v {x} C, mk v {y} D in G, C-D != {}, D-C != {},
                                          not Resolved G v (C|D), z fresh
                                          ==> mk v {z} (C|D), mk x {z} (D-C), mk y {z} (C-D)
  GResStep.reuse   (ResGuard.lean)       same pair, mk v {z} (C|D) in G
                                          ==> mk x {z} (D-C), mk y {z} (C-D)

  Named G S      := exists d in G, vset d = S and d.conc = {}
  Names G z S    := exists d in G, d.lhs = z, vset d = S, d.conc = {}
  Resolved G v K := exists z, mk v {z} K in G

A constraint is (lhs, vset, conc), exactly the Lean's `mk lhs (vset : Finset Var) (conc :
Finset Label)`; a system is a set of them.  Internally vset and conc are integer BITMASKS
(variables and labels are small non-negative integers), which is only a representation of
the Finsets: no rule reads anything a Finset would not have.  Every rule is ADDITIVE: it
inserts its conclusions and never deletes.  Fresh ids come from a counter kept strictly
above every id in use, so `u not in allVars G` holds.  The guards Named / Resolved are
monotone, so a mint that is blocked stays blocked.

--split-key.  Replaces `splitConcrete`'s SYNTACTIC guard (mint unless something NAMES the
group, `Cut.SplitApp`) by the KEYED one of tracker/lean/Rowpartition/KeyedSplit.lean
(`KSplitApp`): mint unless something names `lhs \\ conc`, i.e. unless `lhs <- (z, conc)` is
already present; when it is, the reuse branch gives that existing `z` the new group as a
definition, `z <- (vset c)` (`KSplitReuseApp` / `kSplitReuseResult`).  Default OFF: without
the flag every rule is exactly the shipped one.  `keyed_terminates_of_satisfiable` says the
keyed closure of a SATISFIABLE seed is finite in every order, so a mint cap hit with
--split-key on a seed with a model contradicts the Lean and is a bug in one of the two.

--scala-dedup.  The Lean's substitution takes a Finset union, so a variable occurring in
both `vset c - {d.lhs}` and `vset d` silently collapses to one occurrence.  The Scala
(`RHS.merge`, Constraints.replace / substitute) drops it from the merged right-hand side
and emits `w <- ()` (Saturate.lean, `SatStep.dedup`).  With the flag the explorer ALSO emits
`mk w {} {}` for every such w; the Lean-shaped merged constraint is still emitted.

NOT MODELLED (on purpose; see Saturate.lean): makeEmpty's erasure, makeConcrete /
destructiveSub's absorption and deletions, rename/unify, and deletion in general.  The
real loop is therefore NOT a sub-relation of what this tool explores; this tool answers
only "does the ADDITIVE closure under DefaultStep stay finite on this seed, along the
strategy chosen".

MODEL HANDLING.  A seed may carry an assignment rho (var -> label set).  On every mint rho
is extended -- a split child u denotes the union of rho over its group, a resolution child
z denotes rho v - (C|D) -- and after every rule application every emitted constraint is
checked against the extended rho.  A violation is a bug in a rule implementation and aborts
the run (ModelViolation).  |rho v| is the variable's RANK; mint_rank_lt (ResGuardTerm.lean)
says a minted child's rank is strictly below its parent's, and the report prints the ranks
and the mint-parent tree so that can be seen.  Seeds without rho (the unsatisfiable
calibration objects) skip the checks.

DRIVER.  Breadth-first saturation in rounds, semi-naive: a round applies every rule to
every premise set with at least one premise NEW (added in the previous round) -- sound
because every rule is additive and the guards are monotone -- and inserts the conclusions.
Mints are applied one at a time with their guard RE-CHECKED against the current system, so
two premises with the same unnamed group in one round produce ONE name, as a sequential
chain of DefaultSteps would.  Strategies (the relation is nondeterministic; a fixpoint is a
proof for the run taken, not for every run):
    bfs        (default) a round's non-generative conclusions, then the round's mints
    mintfirst  the round's mints first (the mint-greedy adversary: a name a substitution
               would have produced is minted instead)
    lazy       the non-generative rules are saturated to a fixpoint before every mint round
    worklist   one constraint at a time (FIFO), every rule run against the whole system
               when the constraint is popped, its mints applied at the pop (the shape of
               the Scala incorporateAll loop, without its deletions)
    eager      worklist, and a split premise derived during a pop is minted BEFORE the
               pop's other conclusions are inserted (the most mint-greedy order at the
               granularity of one pop)
    dfs        eager with a LIFO worklist: the newest constraints (a mint's outputs and
               their consequences) are processed first -- the order that follows a chain
               of mints, and the one that finds the empty-name chains (see REPORT)
    random     eager with a uniformly random pop (--rng-seed); several runs sample orders
    chase      eager with a priority pop: first any queued constraint that is an unnamed
               split premise or a bare definition whose one-step substitution into a
               concrete-part constraint yields an UNNAMED group (the mechanism of
               obstruction (5): a name minted for one group re-enters another group)
The run stops at a FIXPOINT (a round adds nothing; the closure is then VERIFIED once more
with every rule run over the WHOLE system -- the self-check of the semi-naive indexing) or
at a CAP: --mint-cap bounds the number of MINTS (fresh variables), --con-cap the number of
constraints, --time-limit the seconds.  Hitting the mint cap with the constraint count
still growing is the non-termination signature this tool can produce; the constraint cap
means the finite closure over the current vocabulary is large, not that it is infinite.

SEED FORMAT (JSON):
    {"name": "...",                          # optional
     "rho":  {"0": [0, 1], "1": [], ...},    # optional; var -> list of labels
     "cons": [[lhs, [vars...], [labels...]], ...]}
Variables and labels are non-negative integers (labels < 60, variables unbounded).  Fresh
ids start above the largest variable in the seed.

REPORT.  Fixpoint or cap; numbers of constraints, variables, split mints, resolution
mints, rounds; the maximum number of children of any single parent (a split child's
parent is the lhs of the split premise, a resolution child's parent is the v of the
pair); for every split parent the number of distinct candidate GROUPS seen (vsets of
constraints with that lhs, nonempty conc and >= 2 variables); when a cap is hit, the last
--tail emitted constraints with provenance (rule, premises) and the mint-parent tree
(child <- parent, kind, rank child/parent, group or key).

RESULT (2026-09-03, scratchpad/satterm/explorer/REPORT.md).  The additive relation does NOT
terminate on every satisfiable input: the 2-constraint seed `builtin twodecomp`,
a <- (e, y, (|1|)), a <- (e, (|1|)) with rho a = {1} and rho e = rho y = {}, has an infinite
productive run of DefaultSteps (CancelStep -> SubstStep -> split mint, three steps per
level, one parent `a` acquiring infinitely many rank-0 split children, one per group
{u_n, y}).  The run is one legal ORDER of the relation (`--strategy chase` takes it; `bfs`
names the group first and reaches a fixpoint), and the real loop's deletions (rename of
`e <- (u)`, makeEmpty of `y <- ()`) cut it -- `bin/ermine` terminates on the seed.

SEARCH.  `search` runs random satisfiable seeds (k variables, m labels, n constraints;
rows built first, constraints only emitted when true under rho; empty rows, duplicate rows
and self-partitions `a <- (a, empties)` occur), `families` the structured families
(multi-decomposition, empties, resolution ladders, split chains, mixed, co-stars,
res-stars, join chains, overlap stars ported from gen-row-*.py / gen-res-star.py).  Both
record closure size and mint counts per seed (--json writes one JSON line per seed), print
the distribution, save every CANDIDATE (not a verified fixpoint -- mint cap, constraint
cap or time -- or mints > 5 x the seed size) as a seed file under --out, and re-run each
candidate at caps 50..--recheck-cap under all three strategies, reporting whether the
growth continues.  A search that finds nothing is evidence about the sizes it covered.
"""
import argparse
import itertools
import json
import os
import random
import sys
import time
from collections import defaultdict


# ----------------------------------------------------------------------------
# Bitmask Finsets
# ----------------------------------------------------------------------------

def popcount(m):
    return m.bit_count()


def bits(m):
    while m:
        b = m & -m
        yield b.bit_length() - 1
        m ^= b


def mask(xs):
    m = 0
    for x in xs:
        m |= 1 << x
    return m


def mk(lhs, vs, ks):
    """The Lean's `mk lhs vset conc`, as (lhs, vset-mask, conc-mask)."""
    return (int(lhs), mask(vs), mask(ks))


def fmt(c):
    vs = " ".join("v%d" % v for v in bits(c[1]))
    ks = ("(|%s|)" % ",".join(str(k) for k in bits(c[2]))) if c[2] else ""
    return "v%d <- (%s)" % (c[0], " ".join(x for x in (vs, ks) if x))


class ModelViolation(Exception):
    pass


class TimeUp(Exception):
    pass


def satisfied(rho, c):
    """Sat rho c: rho lhs = conc | U rho(vset), all parts pairwise disjoint."""
    acc = c[2]
    for v in bits(c[1]):
        r = rho[v]
        if acc & r:
            return False
        acc |= r
    return acc == rho[c[0]]


def sat_sets(rho, lhs, vs, ks):
    """The same, on the generators' set representation."""
    parts = [frozenset(ks)] + [rho[v] for v in vs]
    union = frozenset().union(*parts)
    return sum(len(p) for p in parts) == len(union) and union == rho[lhs]


# ----------------------------------------------------------------------------
# The system, with the indexes the rules need
# ----------------------------------------------------------------------------

class System:
    def __init__(self, rho=None, scala_dedup=False):
        self.cons = set()
        self.order = []                       # insertion order
        self.prov = {}                        # con -> (rule, premises)
        self.by_lhs = defaultdict(list)       # lhs -> [con]
        self.by_var = defaultdict(list)       # v -> [con : v in vset]
        self.by_vm = defaultdict(list)        # vset -> [con]
        self.names = {}                       # vset -> [lhs] with conc = {}   (Named / Names)
        self.unary = defaultdict(list)        # lhs -> [con : |vset| = 1]      (ResPair)
        self.unary_by_conc = defaultdict(dict)  # v -> {conc: [con : |vset| = 1]}
        self.resolved = {}                    # (v, conc) -> [z : mk v {z} conc in G]
        self.cse_part = {}                    # S -> {c : some CsePair (c, c') has shared set S}, S named
        self.rules = None                     # None = every rule; else a set of rule names
        self.rng_seed = 0                     # for the `random` strategy
        self.allvars = set()
        self.next_id = 0
        self.rho = dict(rho) if rho is not None else None    # v -> label mask
        self.scala_dedup = scala_dedup
        self.split_key = False                # --split-key: key the split guard on (lhs, conc)
        self.deadline = None
        self.n_tried = 0                      # add attempts, for the deadline check
        self.canonical = False                # sort each round's additions (differential testing)
        # mint bookkeeping
        self.mints = []                       # (kind, child, parent, group-or-key mask)
        self.parent = {}
        self.children = defaultdict(list)
        self.split_groups = defaultdict(set)  # lhs -> {vset}: candidate groups seen
        self.split_mints = 0
        self.res_mints = 0
        self.cap_hit = False

    def tick(self):
        if self.deadline is not None and time.time() > self.deadline:
            raise TimeUp()

    def fresh(self):
        u = self.next_id
        self.next_id += 1
        assert u not in self.allvars
        return u

    def add(self, c, rule, prem):
        self.n_tried += 1
        if (self.n_tried & 4095) == 0:
            self.tick()
        if c in self.cons:
            return False
        rho = self.rho
        if rho is not None:
            if c[0] not in rho:
                raise ModelViolation("v%d has no row (rule %s, %s)" % (c[0], rule, fmt(c)))
            for v in bits(c[1]):
                if v not in rho:
                    raise ModelViolation("v%d has no row (rule %s, %s)" % (v, rule, fmt(c)))
            if not satisfied(rho, c):
                raise ModelViolation("%s emits %s, false under rho; premises %s"
                                     % (rule, fmt(c), [fmt(p) for p in prem]))
        self.cons.add(c)
        self.order.append(c)
        self.prov[c] = (rule, tuple(prem))
        lhs, vm, cm = c
        self.by_lhs[lhs].append(c)
        for v in bits(vm):
            self.by_var[v].append(c)
        self.by_vm[vm].append(c)
        if cm == 0:
            self.names.setdefault(vm, []).append(lhs)
        n = popcount(vm)
        if n == 1:
            self.unary[lhs].append(c)
            self.unary_by_conc[lhs].setdefault(cm, []).append(c)
            self.resolved.setdefault((lhs, cm), []).append(vm.bit_length() - 1)
        if cm and n >= 2:
            self.split_groups[lhs].add(vm)
        self.allvars.add(lhs)
        if lhs >= self.next_id:
            self.next_id = lhs + 1
        for v in bits(vm):
            self.allvars.add(v)
            if v >= self.next_id:
                self.next_id = v + 1
        if (len(self.cons) & 63) == 0:
            self.tick()
        return True

    def named(self, S):
        return S in self.names

    def is_resolved(self, v, K):
        return (v, K) in self.resolved

    def split_open(self, c):
        """The split MINT guard.  Default: the SYNTACTIC guard of `Cut.SplitApp` -- nothing
        NAMES the group.  With --split-key: the KEYED guard of `KeyedSplit.KSplitApp`
        (tracker/lean/Rowpartition/KeyedSplit.lean) -- nothing names `lhs \\ conc`, i.e. no
        `lhs <- (z, conc)` is present."""
        lhs, vm, cm = c
        if self.split_key:
            return (lhs, cm) not in self.resolved
        return vm not in self.names

    def containing(self, S):
        """Constraints whose vset contains S (S nonempty)."""
        best = None
        for v in bits(S):
            l = self.by_var.get(v, ())
            if best is None or len(l) < len(best):
                best = l
        if not best:
            return ()
        return [c for c in best if (c[1] & S) == S]

    def named_subsets(self, vm):
        """The named sets S with S <= vm and |S| >= 2, each with its list of names."""
        n = popcount(vm)
        if n < 2:
            return ()
        out = []
        names = self.names
        if len(names) <= (1 << n):
            for S, zs in names.items():
                if (S & vm) == S and popcount(S) >= 2:
                    out.append((S, zs))
        else:
            sub = vm
            while sub:
                if popcount(sub) >= 2:
                    zs = names.get(sub)
                    if zs:
                        out.append((sub, zs))
                sub = (sub - 1) & vm
        return out


# ----------------------------------------------------------------------------
# Rules.  Each non-generative rule appends (rule, conclusions, premises) instances with
# at least one premise in `new` (a list; `newset` its set).  Mint rules return requests.
# ----------------------------------------------------------------------------

def reduce_(c, S, z):
    return (c[0], (c[1] & ~S) | (1 << z), c[2])


def rule_cse(G, new, newset, out):
    """CutStep.reuse / CutStep.fold.  A REUSE conclusion `reduce c S z` depends only on
    (c, S, z): c must belong to some CsePair with shared set S, and z must name S.  The
    explorer keeps, for every NAMED S, the set `G.cse_part[S]` of constraints known to
    belong to such a pair (each with a partner witness), and emits `reduce c S z` when
    c enters the set (for every name z of S) and when a new name z of S arrives (for
    every c in the set).  The set of conclusions is exactly the Lean's; only the
    enumeration of (pair, name) instances -- quadratic times the number of names -- is
    avoided.  FOLD is emitted explicitly for a bare c_1 (its other instances, with the
    name as c_1, coincide with reuse conclusions, since a bare `z <- S` is itself a
    partner of every constraint containing S with a different lhs)."""
    part = G.cse_part
    memo = {}                                   # containing(S), G fixed during enumeration

    def containing(S):
        r = memo.get(S)
        if r is None:
            r = memo[S] = G.containing(S)
        return r

    def mark(c, S, zs, partner):
        s = part.get(S)
        if s is None:
            s = part[S] = set()
        if c in s:
            return
        s.add(c)
        for z in zs:
            out.append(("cse.reuse", (reduce_(c, S, z),), (c, partner, (z, S, 0))))

    for c1 in new:
        l1, v1, k1 = c1
        if popcount(v1) < 2:
            continue
        G.tick()
        for S, zs in G.named_subsets(v1):
            partner = None
            s = part.get(S, ())
            for c2 in containing(S):
                if c2[0] != l1 and (v1 & c2[1]) == S:
                    if partner is None:
                        partner = c2
                    if c2 not in s:
                        mark(c2, S, zs, c1)
                        s = part[S]
            if partner is not None:
                mark(c1, S, zs, partner)
        if k1 == 0:
            for c2 in containing(v1):
                if c2[0] != l1:
                    out.append(("cse.fold", (reduce_(c2, v1, l1),), (c1, c2)))
    # a NEW NAME d = z <- S: every constraint already in a pair with shared set S gets the
    # new name; every constraint containing S with lhs != z is now paired with d itself
    for d in new:
        z, S, kd = d
        if kd != 0 or popcount(S) < 2:
            continue
        zs = G.names[S]
        s = part.get(S)
        if s:
            for c in list(s):
                out.append(("cse.reuse", (reduce_(c, S, z),), (c, d, d)))
        cands = containing(S)
        witness = None
        for c in cands:
            if c[0] != z:
                mark(c, S, zs, d)
                witness = c
        if witness is not None:
            mark(d, S, zs, witness)
            for c in cands:
                if c[0] == z and c != d and (S not in part or c not in part[S]):
                    for c2 in cands:
                        if c2[0] != z and (c[1] & c2[1]) == S:
                            mark(c, S, zs, c2)
                            break


def rule_split_reuse_keyed(G, new, newset, out):
    """The KEYED reuse branch (`KeyedSplit.KSplitReuseApp`): the key `(c.lhs, c.conc)` is
    already resolved by `c.lhs <- (z, c.conc)`, so the existing name `z` is given the new
    group as a definition, `z <- (vset c)`.  (The syntactic reuse emits `c.lhs <- (z, c.conc)`
    from a name for the GROUP; the keyed reuse emits the definition from a name for the
    KEY.  Both are entailed: `ksplit_reuse_sat`, `split_reuse_entails`.)"""
    for c in new:
        lhs, vm, cm = c
        if cm and popcount(vm) >= 2:
            for z in G.resolved.get((lhs, cm), ()):
                out.append(("split.reuse", ((z, vm, 0),), (c, (lhs, 1 << z, cm))))
    for d in new:
        lhs, dm, cm = d
        if cm == 0 or popcount(dm) != 1:
            continue
        z = dm.bit_length() - 1
        for c in G.by_lhs.get(lhs, ()):
            if c[2] == cm and popcount(c[1]) >= 2 and c not in newset:
                out.append(("split.reuse", ((z, c[1], 0),), (c, d)))


def rule_split_reuse(G, new, newset, out):
    if G.split_key:
        return rule_split_reuse_keyed(G, new, newset, out)
    for c in new:
        lhs, vm, cm = c
        if cm and popcount(vm) >= 2:
            for u in G.names.get(vm, ()):
                out.append(("split.reuse", ((lhs, 1 << u, cm),), (c, (u, vm, 0))))
    for d in new:
        u, vm, kd = d
        if kd != 0 or popcount(vm) < 2:
            continue
        for c in G.by_vm.get(vm, ()):
            if c[2] and c not in newset:
                out.append(("split.reuse", ((c[0], 1 << u, c[2]),), (c, d)))


def split_requests(G, new):
    if not enabled(G, "split"):
        return []
    return [c for c in new if c[2] and popcount(c[1]) >= 2 and G.split_open(c)]


def apply_split_mint(G, c):
    """SplitApp with the guard re-checked now; returns the list of added constraints."""
    lhs, vm, cm = c
    if not (c in G.cons and cm and popcount(vm) >= 2) or not G.split_open(c):
        return []
    u = G.fresh()
    if G.rho is not None:
        r = 0
        for v in bits(vm):
            r |= G.rho[v]
        G.rho[u] = r
    added = []
    for e in ((u, vm, 0), (lhs, 1 << u, cm)):
        if G.add(e, "split.mint", (c,)):
            added.append(e)
    G.split_mints += 1
    G.mints.append(("split", u, lhs, vm))
    G.parent[u] = lhs
    G.children[lhs].append(u)
    return added


def rule_cancel(G, new, newset, out):
    for e in new:
        G.tick()
        for f in G.by_lhs.get(e[0], ()):
            if f == e:
                continue
            for c, d in ((e, f), (f, e)):
                if c[2] & ~d[2]:
                    continue                      # c.conc must be <= d.conc
                diff = c[1] & ~d[1]
                if diff == 0 or (diff & (diff - 1)):
                    continue                      # exactly one leftover variable
                z = diff.bit_length() - 1
                out.append(("cancel", ((z, d[1] & ~c[1], d[2] & ~c[2]),), (c, d)))


def rule_subst(G, new, newset, out):
    dedup = G.scala_dedup

    def inst(c, d):
        rest = c[1] & ~(1 << d[0])
        concl = [(c[0], rest | d[1], c[2] | d[2])]
        if dedup:
            for w in bits(rest & d[1]):
                concl.append((w, 0, 0))
        out.append(("subst", tuple(concl), (c, d)))

    for c in new:
        G.tick()
        for v in bits(c[1]):
            for d in G.by_lhs.get(v, ()):
                inst(c, d)
    for d in new:
        G.tick()
        for c in G.by_var.get(d[0], ()):
            if c not in newset:
                inst(c, d)


def rule_self_subst(G, new, newset, out):
    for c in new:
        lhs, vm, cm = c
        if cm == 0 and (vm >> lhs) & 1:
            for v in bits(vm):
                if v != lhs:
                    out.append(("selfsubst", ((v, 0, 0),), (c,)))


def rule_common_part(G, new, newset, out):
    for c in new:
        for d in G.by_vm.get(c[1], ()):
            if d[0] != c[0] and d[2] == c[2]:
                out.append(("commonpart", ((c[0], 1 << d[0], 0),), (c, d)))
                out.append(("commonpart", ((d[0], 1 << c[0], 0),), (d, c)))


def rule_gres(G, new, newset, out, mints):
    """GResStep.reuse instances to `out`, GResStep.mint requests to `mints`.  Partners are
    enumerated by their concrete part (G.unary_by_conc), so a new resolvent costs
    O(#distinct concrete parts^2 + #conclusions) rather than O(#unary constraints^2)."""
    for c1 in new:
        v, xm, C = c1
        if popcount(xm) != 1:
            continue
        G.tick()
        x = xm.bit_length() - 1
        for D, bs in G.unary_by_conc.get(v, {}).items():
            if not (C & ~D) or not (D & ~C):
                continue
            K = C | D
            zs = G.resolved.get((v, K))
            if zs:
                for z in zs:
                    res = (v, 1 << z, K)
                    for b in bs:
                        out.append(("gres.reuse", ((x, 1 << z, D & ~C), (b[1].bit_length() - 1, 1 << z, C & ~D)), (c1, b, res)))
            else:
                b = bs[0]
                mints.append((c1, b, v, x, b[1].bit_length() - 1, C, D))
    # a NEW resolvent v <- (z, K) enables REUSE on every pair with C | D = K
    for e in new:
        v, zm, K = e
        if popcount(zm) != 1:
            continue
        G.tick()
        z = zm.bit_length() - 1
        groups = G.unary_by_conc.get(v, {})
        Cs = [C for C in groups if (C & ~K) == 0 and C != K]
        for C in Cs:
            for D in Cs:
                if (C | D) == K and (C & ~D) and (D & ~C):
                    for a in groups[C]:
                        if a == e:
                            continue
                        x = a[1].bit_length() - 1
                        for b in groups[D]:
                            if b == e:
                                continue
                            out.append(("gres.reuse", ((x, 1 << z, D & ~C), (b[1].bit_length() - 1, 1 << z, C & ~D)), (a, b, e)))


def apply_res_mint(G, req):
    a, b, v, x, y, C, D = req
    K = C | D
    if a not in G.cons or b not in G.cons or (v, K) in G.resolved:
        return []
    z = G.fresh()
    if G.rho is not None:
        G.rho[z] = G.rho[v] & ~K
    added = []
    for e in ((v, 1 << z, K), (x, 1 << z, D & ~C), (y, 1 << z, C & ~D)):
        if G.add(e, "gres.mint", (a, b)):
            added.append(e)
    G.res_mints += 1
    G.mints.append(("res", z, v, K))
    G.parent[z] = v
    G.children[v].append(z)
    return added


STRATEGIES = ("bfs", "mintfirst", "lazy", "worklist", "eager", "dfs", "random", "chase")
NONGEN_RULES = (("cse", rule_cse), ("splitreuse", rule_split_reuse), ("cancel", rule_cancel),
                ("subst", rule_subst), ("selfsubst", rule_self_subst), ("commonpart", rule_common_part))
ALL_RULES = tuple(n for n, _ in NONGEN_RULES) + ("split", "gres")


def enabled(G, name):
    return G.rules is None or name in G.rules


# ----------------------------------------------------------------------------
# Closure driver
# ----------------------------------------------------------------------------

class Result:
    pass


def nongen_round(G, new, newset):
    """Apply every non-generative rule (incl. gres.reuse) to premises touching `new`.
    Returns (added constraints, resolution mint requests)."""
    insts = []
    mint_reqs = []
    for name, rule in NONGEN_RULES:
        if enabled(G, name):
            rule(G, new, newset, insts)
            G.tick()
    if enabled(G, "gres"):
        rule_gres(G, new, newset, insts, mint_reqs)
    added = []
    add = G.add
    for (name, concl, prem) in insts:
        for e in concl:
            if add(e, name, prem):
                added.append(e)
    if G.canonical:
        added.sort()
        mint_reqs.sort()
    return added, mint_reqs


def apply_mints(G, split_reqs, res_reqs, mint_cap):
    added = []
    for c in split_reqs:
        if G.split_mints + G.res_mints >= mint_cap:
            if G.split_open(c) and c[2] and popcount(c[1]) >= 2:
                G.cap_hit = True
            continue
        added.extend(apply_split_mint(G, c))
    for req in res_reqs:
        if G.split_mints + G.res_mints >= mint_cap:
            if (req[2], req[5] | req[6]) not in G.resolved:
                G.cap_hit = True
            continue
        added.extend(apply_res_mint(G, req))
    return added


def is_split_premise(G, c):
    return c[2] != 0 and popcount(c[1]) >= 2 and G.split_open(c)


def worklist_closure(G, mint_cap, con_cap, eager, order="fifo", rng=None):
    """One constraint at a time (FIFO), every rule run against the whole current system
    when the constraint is popped; its split mint (if still unnamed) and the resolution
    mints it enables are applied at the pop.  With `eager`, a freshly derived split
    premise is minted BEFORE the other conclusions of the same pop are inserted -- the
    most mint-greedy order at the granularity of one pop (every order the driver takes is
    a sequential chain of DefaultSteps).  Returns (stopped, pops)."""
    from collections import deque
    queue = deque(G.order)
    hotq = deque()                            # chase: constraints classified hot when enqueued
    done = set()                              # chase: popped constraints (an item can sit in both deques)
    pops = 0

    def hot(c):
        """`chase` priority: c is an unnamed split premise, or a definition whose one-step
        substitution into some concrete-part constraint yields an unnamed group."""
        if is_split_premise(G, c):
            return True
        x, vm, cm = c
        if cm != 0:
            return False
        for d in G.by_var.get(x, ()):
            if d[2] != 0:
                grp = (d[1] & ~(1 << x)) | vm
                if popcount(grp) >= 2 and G.split_open((d[0], grp, d[2])):
                    return True
        return False

    while queue or hotq:
        if order == "lifo":
            c = queue.pop()
        elif order == "random":
            i = rng.randrange(len(queue))
            c = queue[i]
            del queue[i]
        elif order == "chase":
            c = None
            while hotq:
                e = hotq.popleft()
                if e in done:
                    continue
                if hot(e):
                    c = e
                    break
                queue.append(e)               # cooled down: back to FIFO
            if c is None:
                while queue:
                    c = queue.popleft()
                    if c not in done:
                        break
                    c = None
                if c is None:
                    break
            done.add(c)
        else:
            c = queue.popleft()
        pops += 1
        added = []
        if enabled(G, "split") and is_split_premise(G, c):
            if G.split_mints + G.res_mints >= mint_cap:
                G.cap_hit = True
                return "mint-cap", pops
            added.extend(apply_split_mint(G, c))
        insts = []
        mreqs = []
        cset = {c}
        for name, rule in NONGEN_RULES:
            if enabled(G, name):
                rule(G, [c], cset, insts)
        if enabled(G, "gres"):
            rule_gres(G, [c], cset, insts, mreqs)
        for req in mreqs:
            if (req[2], req[5] | req[6]) in G.resolved:
                continue
            if G.split_mints + G.res_mints >= mint_cap:
                G.cap_hit = True
                return "mint-cap", pops
            added.extend(apply_res_mint(G, req))
        if eager:
            rest = []
            for (name, concl, prem) in insts:
                for e in concl:
                    if e[2] != 0 and popcount(e[1]) >= 2:
                        if G.add(e, name, prem):
                            added.append(e)
                            if enabled(G, "split") and is_split_premise(G, e):
                                if G.split_mints + G.res_mints >= mint_cap:
                                    G.cap_hit = True
                                    return "mint-cap", pops
                                added.extend(apply_split_mint(G, e))
                    else:
                        rest.append((name, e, prem))
            for (name, e, prem) in rest:
                if G.add(e, name, prem):
                    added.append(e)
        else:
            for (name, concl, prem) in insts:
                for e in concl:
                    if G.add(e, name, prem):
                        added.append(e)
        queue.extend(added)
        if order == "chase":
            for e in added:
                if hot(e):
                    hotq.append(e)
        if len(G.cons) > con_cap:
            return "con-cap", pops
    return "fixpoint", pops


def closure(G, mint_cap=400, con_cap=20000, strategy="bfs", time_limit=None, verify=True):
    t0 = time.time()
    G.deadline = (t0 + time_limit) if time_limit else None
    r = Result()
    r.stopped = None
    new = sorted(G.order) if G.canonical else list(G.order)
    rounds = 0
    try:
        if strategy in ("worklist", "eager", "dfs", "random", "chase"):
            order = {"dfs": "lifo", "random": "random", "chase": "chase"}.get(strategy, "fifo")
            r.stopped, rounds = worklist_closure(G, mint_cap, con_cap, strategy != "worklist", order,
                                                 random.Random(G.rng_seed) if strategy == "random" else None)
        while r.stopped is None:
            rounds += 1
            newset = set(new)
            if strategy == "lazy":
                cur, curset = new, newset
                split_reqs, res_reqs = [], []
                while cur:
                    split_reqs.extend(split_requests(G, cur))
                    added, rr = nongen_round(G, cur, curset)
                    res_reqs.extend(rr)
                    cur, curset = added, set(added)
                    if len(G.cons) > con_cap:
                        break
                added_ng = []
                added_m = apply_mints(G, split_reqs, res_reqs, mint_cap)
            elif strategy == "mintfirst":
                split_reqs = split_requests(G, new)
                res_reqs = []
                if enabled(G, "gres"):
                    rule_gres(G, new, newset, [], res_reqs)
                added_m = apply_mints(G, split_reqs, res_reqs, mint_cap)
                added_ng, _ = nongen_round(G, new, newset)
            else:  # bfs
                split_reqs = split_requests(G, new)
                added_ng, res_reqs = nongen_round(G, new, newset)
                added_m = apply_mints(G, split_reqs, res_reqs, mint_cap)
            new = added_ng + added_m
            if G.canonical:
                new.sort()
            if G.cap_hit:
                r.stopped = "mint-cap"
                break
            if len(G.cons) > con_cap:
                r.stopped = "con-cap"
                break
            if not new:
                r.stopped = "fixpoint"
                break
    except TimeUp:
        r.stopped = "time"
    r.rounds = rounds
    r.seconds = time.time() - t0
    r.verified = None
    if r.stopped == "fixpoint" and verify:
        # every rule over the WHOLE system must add nothing and enable no mint
        G.deadline = None
        allc = list(G.order)
        added, mreqs = nongen_round(G, allc, set(allc))
        live_splits = split_requests(G, allc)
        live_res = [q for q in mreqs if (q[2], q[5] | q[6]) not in G.resolved]
        r.verified = (not added) and (not live_splits) and (not live_res)
        if not r.verified:
            r.stopped = "fixpoint-UNVERIFIED"
            r.verify_detail = (len(added), len(live_splits), len(live_res))
    return r


# ----------------------------------------------------------------------------
# Seeds
# ----------------------------------------------------------------------------

def load_seed(obj):
    rho = None
    if obj.get("rho") is not None:
        rho = {int(k): mask(v) for k, v in obj["rho"].items()}
    cons = [mk(a, vs, ks) for (a, vs, ks) in obj["cons"]]
    return obj.get("name", "seed"), rho, cons


def seed_obj(name, rho_sets, cons):
    """Generators' output (rho as sets, cons as (lhs, vars, labels)) -> JSON object."""
    return {"name": name,
            "rho": None if rho_sets is None else {str(v): sorted(r) for v, r in sorted(rho_sets.items())},
            "cons": [[a, sorted(vs), sorted(ks)] for (a, vs, ks) in cons]}


def build(rho, cons, scala_dedup=False, check=True, rules=None, rng_seed=0,
          split_key=False):
    G = System(rho, scala_dedup)
    G.rules = rules
    G.split_key = split_key
    G.rng_seed = rng_seed
    if rho is not None:
        for v in rho:
            G.allvars.add(v)
            if v >= G.next_id:
                G.next_id = v + 1
    for c in cons:
        if check and rho is not None and not satisfied(rho, c):
            raise ModelViolation("seed constraint %s is false under rho" % fmt(c))
        G.add(c, "seed", ())
    return G


BUILTIN = {
    # ResGuardDiverge.gSeed: unsatisfiable, guarded resolution diverges on it
    "gseed": {"name": "gSeed", "rho": None,
              "cons": [[0, [2], [1]], [0, [3], [2]], [1, [2], [3]], [1, [3], [4]]]},
    # DefaultDiverge.CRule.W: unsatisfiable, divergent, not refuted by the input label check
    "crulew": {"name": "CRule.W", "rho": None,
               "cons": [[0, [2], [1]], [1, [3], [4]],
                        [8, [0, 9], []], [8, [6, 7, 9], [2]], [3, [6, 7], []],
                        [10, [1, 11], []], [10, [4, 5, 11], [3]], [2, [4, 5], []]]},
    # Cut.resSeed: a <- (x,(|1|)), a <- (y,(|2|)); satisfiable with a={1,2}, x={2}, y={1}
    "resseed": {"name": "resSeed", "rho": {"0": [1, 2], "1": [2], "2": [1]},
                "cons": [[0, [1], [1]], [0, [2], [2]]]},
    # The SATISFIABLE witnesses (REPORT §3): a <- (e, y, (|1|)), a <- (e, (|1|)) with
    # rho a = {1}, rho e = rho y = {}.  `--strategy chase` diverges (Cancel -> Subst ->
    # split mint, three DefaultSteps per level); bfs reaches a 13-constraint fixpoint.
    "twodecomp": {"name": "twodecomp", "rho": {"0": [1], "1": [], "2": []},
                  "cons": [[0, [1, 2], [1]], [0, [1], [1]]]},
    # acyclic variant: a <- (e, y, (|1|)), a <- ((|1|)), y <- ()   (Cancel, CommonPart, Subst, mint)
    "emptypair": {"name": "emptypair", "rho": {"0": [1], "1": [], "2": []},
                  "cons": [[0, [1, 2], [1]], [0, [], [1]], [2, [], []]]},
    # self-partition variant: a <- (a, e), a <- (e2, (|1|))
    "selfloop": {"name": "selfloop", "rho": {"0": [1], "1": [], "2": []},
                 "cons": [[0, [0, 1], []], [0, [2], [1]]]},
    # two equal-row variables in a cycle: b <- (a, e), a <- (b), a <- (e2, (|1|))
    "copycycle": {"name": "copycycle", "rho": {"0": [1], "1": [1], "2": [], "3": []},
                  "cons": [[1, [2, 0], []], [0, [1], []], [0, [3], [1]]]},
}


# --- random satisfiable seeds --------------------------------------------------

def gen_random(rng, k, m, n, p_empty=0.25, p_dup=0.25, p_self=0.04, p_full_conc=0.08,
               no_empty=False):
    """k variables with rows in {0..m-1} (empty and duplicate rows with positive
    probability), then n distinct constraints true under rho: lhs a, concrete part
    K <= rho a (possibly empty, sometimes all of rho a), and a group of variables with
    pairwise disjoint rows partitioning rho a - K, plus empty-row variables added freely.
    With probability p_self a self-partition a <- (a, empties...) instead.  With
    `no_empty` every row is NONEMPTY (the ablation of REPORT §5: p_empty = 0 alone still
    draws an empty row with probability 0.45^m)."""
    labels = list(range(m))
    rho = {}
    rows = []
    for v in range(k):
        r = rng.random()
        if r < p_empty and not no_empty:
            row = frozenset()
        elif r < p_empty + p_dup and rows:
            row = rng.choice(rows)
        else:
            row = frozenset(l for l in labels if rng.random() < 0.55)
            while no_empty and not row:
                row = frozenset(l for l in labels if rng.random() < 0.55)
        rho[v] = row
        rows.append(row)
    cons = []
    seen = set()
    tries = 0
    while len(cons) < n and tries < 60 * n:
        tries += 1
        a = rng.randrange(k)
        R = rho[a]
        empties = [v for v in range(k) if v != a and not rho[v]]
        if rng.random() < p_self:
            group = [a] + [v for v in empties if rng.random() < 0.5]
            K = frozenset()
        else:
            if rng.random() < p_full_conc:
                K = R
            else:
                K = frozenset(l for l in R if rng.random() < 0.4)
            rest = R - K
            cands = [v for v in range(k) if v != a and rho[v] and rho[v] <= rest]
            rng.shuffle(cands)
            group = []
            remaining = set(rest)
            for v in cands:
                if rho[v] <= remaining:
                    group.append(v)
                    remaining -= rho[v]
            if remaining:
                continue
            for v in empties:
                if rng.random() < 0.35:
                    group.append(v)
        key = (a, frozenset(group), K)
        if key in seen:
            continue
        assert sat_sets(rho, a, group, K)
        seen.add(key)
        cons.append((a, sorted(group), sorted(K)))
    return rho, cons


# --- structured families -------------------------------------------------------

class Builder:
    """Helper for hand-built satisfiable seeds: variables named on demand, rows first."""

    def __init__(self, rng=None):
        self.rng = rng or random.Random(0)
        self.rho = {}
        self.cons = []
        self.seen = set()
        self.n = 0
        self.byrow = defaultdict(list)

    def var(self, row):
        v = self.n
        self.n += 1
        self.rho[v] = frozenset(row)
        self.byrow[frozenset(row)].append(v)
        return v

    def add(self, lhs, vs, ks=()):
        vs = list(vs)
        assert sat_sets(self.rho, lhs, vs, ks), (lhs, vs, ks)
        key = (lhs, frozenset(vs), frozenset(ks))
        if key not in self.seen:
            self.seen.add(key)
            self.cons.append((lhs, sorted(set(vs)), sorted(ks)))

    def partition(self, R, nblocks, reuse_p=0.5, exclude=()):
        """Split the label set R into nblocks random blocks; name each by an existing
        variable with that row (with probability reuse_p) or a fresh one."""
        R = sorted(R)
        self.rng.shuffle(R)
        if nblocks > len(R):
            nblocks = max(1, len(R))
        cuts = sorted(self.rng.sample(range(1, len(R)), nblocks - 1)) if nblocks > 1 and len(R) > 1 else []
        blocks = []
        prev = 0
        for cpos in cuts + [len(R)]:
            blocks.append(frozenset(R[prev:cpos]))
            prev = cpos
        out = []
        for b in blocks:
            existing = [v for v in self.byrow.get(b, []) if v not in exclude and v not in out]
            if existing and self.rng.random() < reuse_p:
                out.append(self.rng.choice(existing))
            else:
                out.append(self.var(b))
        return out


def fam_multidecomp(rng, m, d, nblocks=2):
    """(i) d different decompositions of one full-row variable, each with a concrete part;
    then decompositions of the parts."""
    B = Builder(rng)
    L = frozenset(range(m))
    a = B.var(L)
    for _ in range(d):
        K = frozenset(rng.sample(range(m), rng.randint(1, max(1, m - 2))))
        rest = L - K
        vs = B.partition(rest, min(nblocks, len(rest)), exclude=(a,)) if rest else []
        B.add(a, vs, K)
    for v in list(B.rho):
        if v != a and len(B.rho[v]) >= 2 and rng.random() < 0.6:
            K = frozenset(rng.sample(sorted(B.rho[v]), 1))
            rest = B.rho[v] - K
            vs = B.partition(rest, min(2, len(rest)), exclude=(v,))
            B.add(v, vs, K)
    return B.rho, B.cons


def fam_empties(rng, m, ne, extra=True):
    """(ii) a <- (e1..e_ne, K) with K = rho a; the empties made interchangeable through
    w <- (e_i, T) definitions; the empties defined by each other; a second decomposition
    of a with a nonempty concrete part carrying one empty each."""
    B = Builder(rng)
    L = frozenset(range(m))
    a = B.var(L)
    es = [B.var(()) for _ in range(ne)]
    B.add(a, es, L)
    T = B.var(frozenset(rng.sample(range(m), max(1, m // 2))))
    w = B.var(B.rho[T])
    for e in es:
        B.add(w, [e, T])
    if extra and ne >= 2:
        B.add(es[0], es[1:])
        B.add(es[1], [es[0]] + es[2:])
        K = frozenset(rng.sample(range(m), max(1, m - 1)))
        rest = L - K
        vs = B.partition(rest, 1, exclude=(a,)) if rest else []
        B.add(a, vs + es[:1], K)
        B.add(a, vs + es[1:2], K)
    return B.rho, B.cons


def fam_resladder(rng, m, depth, with_empties=True, with_decomp=True):
    """(iii) v <- (x, C), v <- (y, D), C, D incomparable, rho v = C | D so the resolvent
    is empty; stacked `depth` times (the next level lives on x) and combined with
    decompositions / empties; a wrapper t <- (v, u) with a concrete part on top."""
    B = Builder(rng)
    labels = list(range(m))
    prev = None
    for lvl in range(depth):
        if prev is None:
            ls = rng.sample(labels, min(m, 3))
            C = frozenset(ls[:2])
            D = frozenset(ls[1:])
            v = B.var(C | D)
        else:
            v = prev
            row = sorted(B.rho[v])
            if len(row) < 2:
                break
            ls = rng.sample(row, min(len(row), 3))
            C = frozenset(ls[:2]) if len(ls) >= 2 else frozenset(ls)
            D = frozenset(ls[1:])
            if not (C - D) or not (D - C):
                break
            if (C | D) != B.rho[v]:
                rem = B.rho[v] - (C | D)
                x = B.var(D - C)
                y = B.var(C - D)
                r1 = B.var(rem)
                r2 = B.var(rem)
                B.add(v, [x, r1], C)
                B.add(v, [y, r2], D)
                prev = x
                continue
        x = B.var(D - C)
        y = B.var(C - D)
        B.add(v, [x], C)
        B.add(v, [y], D)
        if with_empties:
            e1, e2 = B.var(()), B.var(())
            B.add(x, [e1, e2], D - C)
            B.add(y, [e1], C - D)
        if with_decomp and len(C | D) >= 2:
            K = frozenset([min(C | D)])
            rest = (C | D) - K
            vs = B.partition(rest, min(2, len(rest)), exclude=(v,))
            B.add(v, vs, K)
        prev = x
    if B.rho:
        v0 = 0
        others = frozenset(labels) - B.rho[v0]
        if others:
            u = B.var(others)
            t = B.var(frozenset(labels))
            K = frozenset([min(others)])
            u2 = B.var(others - K)
            B.add(t, [v0, u])
            B.add(t, [v0, u2], K)
    return B.rho, B.cons


def fam_chain(rng, depth, cross=True):
    """(iv) a_0 <- (a_1, b_1, K_1), a_1 <- (a_2, b_2, K_2), ...: every split name becomes
    a part of the constraint above it, which is itself a split premise; with `cross` a
    second decomposition of the top and a sibling definition of the bottom."""
    B = Builder(rng)
    m = 2 * depth + 1
    labels = list(range(m))
    rng.shuffle(labels)
    row = frozenset([labels[0]])
    a_prev = B.var(row)
    idx = 1
    chain = [a_prev]
    for i in range(depth):
        b = B.var(frozenset([labels[idx]]))
        K = frozenset([labels[idx + 1]])
        idx += 2
        row = row | B.rho[b] | K
        a = B.var(row)
        B.add(a, [a_prev, b], K)
        chain.append(a)
        a_prev = a
    if cross and depth >= 2:
        top = chain[-1]
        K = frozenset([labels[1]])
        rest = B.rho[top] - K
        vs = B.partition(rest, 2, exclude=(top,))
        B.add(top, vs, K)
        bot = chain[0]
        e = B.var(())
        B.add(bot, [e], B.rho[bot])
    return B.rho, B.cons


def fam_costar(rng, mvars, nconc=0):
    """(v) co-stars (gen-row-overlap.py): x_i <- (every b except b_i), the b's disjoint
    singletons.  With nconc > 0 a concrete part is added to nconc of them (split premises)."""
    B = Builder(rng)
    bs = [B.var(frozenset([i])) for i in range(mvars)]
    for i in range(mvars):
        group = [b for j, b in enumerate(bs) if j != i]
        if i < nconc:
            K = frozenset([mvars + i])
            x = B.var((frozenset(range(mvars)) - {i}) | K)
            B.add(x, group, K)
        else:
            x = B.var(frozenset(range(mvars)) - {i})
            B.add(x, group)
    return B.rho, B.cons


def fam_overlap(rng, n, shared):
    """(v) overlap stars (gen-row-overlap.py): x_i <- (b_i, c_0..c_{shared-1})."""
    B = Builder(rng)
    cs = [B.var(frozenset([j])) for j in range(shared)]
    for i in range(n):
        b = B.var(frozenset([shared + i]))
        x = B.var(frozenset(range(shared)) | {shared + i})
        B.add(x, [b] + cs)
    return B.rho, B.cons


def fam_resstar(rng, m):
    """(v) res-stars (gen-res-star.py): a <- (x_i, (|f_i|)), rho a = all, rho x_i = a - {f_i}."""
    B = Builder(rng)
    L = frozenset(range(m))
    a = B.var(L)
    for i in range(m):
        x = B.var(L - {i})
        B.add(a, [x], {i})
    return B.rho, B.cons


def fam_joinchain(rng, n):
    """(v) gen-row-stress: left-nested joins.  join a b c: a <- (d,e), b <- (e,f), c <- (d,e,f)."""
    B = Builder(rng)
    label = itertools.count()
    d = B.var([next(label)])
    e = B.var([next(label)])
    acc = B.var(B.rho[d] | B.rho[e])
    B.add(acc, [d, e])
    for i in range(1, n):
        row = sorted(B.rho[acc])
        rng.shuffle(row)
        cut = rng.randint(0, len(row))
        d2 = B.var(row[:cut])
        e2 = B.var(row[cut:])
        f = B.var([next(label)])
        ai = B.var(B.rho[e2] | B.rho[f])
        c = B.var(B.rho[acc] | B.rho[f])
        B.add(acc, [d2, e2])
        B.add(ai, [e2, f])
        B.add(c, [d2, e2, f])
        acc = c
    return B.rho, B.cons


def fam_mixed(rng, m, reps):
    """A random mixture: multi-decomp + res-ladder + empties on one variable pool."""
    B = Builder(rng)
    L = frozenset(range(m))
    a = B.var(L)
    es = [B.var(()) for _ in range(2)]
    for _ in range(reps):
        K = frozenset(rng.sample(range(m), rng.randint(1, max(1, m - 1))))
        rest = L - K
        vs = B.partition(rest, min(rng.randint(1, 3), max(1, len(rest))), exclude=(a,)) if rest else []
        if rng.random() < 0.5:
            vs = vs + [rng.choice(es)]
        B.add(a, vs, K)
    for _ in range(reps):
        ls = rng.sample(range(m), min(m, 3))
        C = frozenset(ls[:2])
        D = (L - C) | frozenset(ls[1:2])
        if not (C - D) or not (D - C):
            continue
        x = B.var(L - C)
        y = B.var(L - D)
        B.add(a, [x], C)
        B.add(a, [y], D)
        if rng.random() < 0.5 and len(B.rho[x]) >= 2:
            K2 = frozenset([min(B.rho[x])])
            vs = B.partition(B.rho[x] - K2, 2, exclude=(x,))
            B.add(x, vs + ([es[0]] if rng.random() < 0.5 else []), K2)
    T = B.var(frozenset(rng.sample(range(m), max(1, m // 2))))
    w = B.var(B.rho[T])
    for e in es:
        B.add(w, [e, T])
    return B.rho, B.cons


# ----------------------------------------------------------------------------
# Reporting
# ----------------------------------------------------------------------------

def summarize(G, r, nseed):
    maxchild = max((len(v) for v in G.children.values()), default=0)
    maxgroups = max((len(v) for v in G.split_groups.values()), default=0)
    d = {"stopped": r.stopped, "rounds": r.rounds, "seconds": round(r.seconds, 3),
         "cons": len(G.cons), "vars": len(G.allvars), "seed_cons": nseed,
         "mints": G.split_mints + G.res_mints, "split_mints": G.split_mints,
         "res_mints": G.res_mints, "max_children": maxchild, "max_groups": maxgroups,
         "verified": r.verified}
    if G.rho is not None and G.mints:
        # rank of every minted child, and of the children of the busiest parent
        hist = defaultdict(int)
        for kind, child, parent, key in G.mints:
            hist[popcount(G.rho[child])] += 1
        d["child_ranks"] = dict(sorted(hist.items()))
        p = max(G.children, key=lambda p: len(G.children[p]))
        d["busiest_parent"] = {"var": p, "rank": popcount(G.rho[p]), "children": len(G.children[p]),
                               "child_ranks": dict(sorted(((k, sum(1 for c in G.children[p] if popcount(G.rho[c]) == k))
                                                           for k in {popcount(G.rho[c]) for c in G.children[p]})))}
    return d


def fmt_vars(m):
    return "{%s}" % ",".join("v%d" % v for v in bits(m))


def fmt_labels(m):
    return "{%s}" % ",".join(str(k) for k in bits(m))


def print_report(G, r, nseed, tail=60, show_tree=True):
    s = summarize(G, r, nseed)
    print("== %s" % ("FIXPOINT (verified: %s)" % r.verified if r.stopped.startswith("fixpoint")
                     else "CAP HIT: %s" % r.stopped))
    print("   constraints %d (seed %d)  variables %d  rounds %d  time %.2fs"
          % (s["cons"], nseed, s["vars"], s["rounds"], s["seconds"]))
    print("   mints %d (split %d, resolution %d)  max children of one parent %d  max distinct groups at one lhs %d"
          % (s["mints"], s["split_mints"], s["res_mints"], s["max_children"], s["max_groups"]))
    if G.rho is not None:
        ranks = sorted(((popcount(G.rho[v]), v) for v in G.allvars), reverse=True)
        print("   ranks |rho v|: " + " ".join("v%d:%d" % (v, k) for k, v in ranks[:40])
              + (" ..." if len(ranks) > 40 else ""))
    splitkids = {m[1] for m in G.mints if m[0] == "split"}
    for p in sorted(G.children, key=lambda p: -len(G.children[p])):
        kids = G.children[p]
        sk = sum(1 for c in kids if c in splitkids)
        print("   parent v%d: %d children (%d split, %d res); split-candidate groups at v%d: %d"
              % (p, len(kids), sk, len(kids) - sk, p, len(G.split_groups.get(p, ()))))
    if r.stopped.startswith("fixpoint"):
        return s
    print("-- last %d emitted constraints (rule ; premises)" % tail)
    for c in G.order[-tail:]:
        rule, prem = G.prov[c]
        print("   %-40s  %-12s %s" % (fmt(c), rule, " | ".join(fmt(p) for p in prem)))
    if show_tree:
        print("-- mint-parent tree, last %d mints (child <- parent [kind, rank child/parent])" % tail)
        for kind, child, parent, key in G.mints[-tail:]:
            rk = ("%d/%d" % (popcount(G.rho[child]), popcount(G.rho[parent]))) if G.rho is not None else "?"
            keys = ("group %s" % fmt_vars(key)) if kind == "split" else ("key %s" % fmt_labels(key))
            print("   v%d <- v%d  [%s, %s] %s" % (child, parent, kind, rk, keys))
    return s


def run_seed(name, rho, cons, opts, verbose=True, mint_cap=None, time_limit=None, verify=True):
    G = build(rho, cons, scala_dedup=opts["scala_dedup"], rules=opts.get("rules"), rng_seed=opts.get("rng_seed", 0),
              split_key=opts.get("split_key", False))
    r = closure(G, mint_cap=mint_cap or opts["mint_cap"], con_cap=opts["con_cap"],
                strategy=opts["strategy"], time_limit=time_limit, verify=verify)
    if verbose:
        print("## %s: %d seed constraints, %d variables%s" % (name, len(cons), len(G.allvars) if rho is None else len(rho),
                                                              "" if rho is None else ", model given"))
        for c in cons:
            print("   %s" % fmt(c))
        print_report(G, r, len(cons), tail=opts["tail"])
    return G, r


# ----------------------------------------------------------------------------
# Search
# ----------------------------------------------------------------------------

def percentile(xs, p):
    if not xs:
        return 0
    xs = sorted(xs)
    i = min(len(xs) - 1, int(round(p * (len(xs) - 1))))
    return xs[i]


def _work(job):
    """Worker: (seed object, opts) -> {"name", "seed", "runs": {strategy: stats}}.
    Model violations are reported as a run with stopped = MODEL-VIOLATION."""
    obj, opts = job
    name, rho, cons = load_seed(obj)
    runs = {}
    for strategy in opts["strategies"]:
        o = dict(opts)
        if ":" in strategy:                   # e.g. random:3 -> third random order
            strategy, k = strategy.split(":")
            o["rng_seed"] = int(k)
            o["strategy"] = strategy
            strategy = "%s:%s" % (strategy, k)
        else:
            o["strategy"] = strategy
        try:
            G, r = run_seed(name, rho, cons, o, verbose=False, time_limit=opts["time_per_seed"])
        except ModelViolation as ex:
            runs[strategy] = {"stopped": "MODEL-VIOLATION", "error": str(ex), "cons": 0, "vars": 0,
                              "seed_cons": len(cons), "mints": 0, "split_mints": 0, "res_mints": 0,
                              "max_children": 0, "max_groups": 0, "rounds": 0, "seconds": 0, "verified": None}
            continue
        runs[strategy] = summarize(G, r, len(cons))
    return {"name": name, "seed": obj, "runs": runs}


def search_loop(seeds, args, opts, label):
    """seeds: iterable of seed objects.  Records stats, saves candidates."""
    os.makedirs(args.out, exist_ok=True)
    stats = []
    cands = []
    t0 = time.time()
    jobs = ((obj, opts) for obj in seeds if obj["cons"])
    if args.jobs > 1:
        from multiprocessing import Pool
        pool = Pool(args.jobs)
        it = pool.imap_unordered(_work, jobs, chunksize=8)
    else:
        pool = None
        it = map(_work, jobs)
    jf = open(args.json, "w") if args.json else None
    try:
        for i, rec in enumerate(it):
            obj = rec.pop("seed")
            for strategy, s in rec["runs"].items():
                if s["stopped"] == "MODEL-VIOLATION":
                    print("MODEL VIOLATION on %s [%s]: %s" % (rec["name"], strategy, s["error"]))
                    with open(os.path.join(args.out, "violation-%s.json" % rec["name"]), "w") as fh:
                        json.dump(obj, fh)
                    raise SystemExit(2)
            stats.append(rec)
            if jf:
                jf.write(json.dumps(rec) + "\n")
            is_cand = any((not s["stopped"].startswith("fixpoint")) or s["mints"] > 5 * s["seed_cons"]
                          for s in rec["runs"].values())
            if is_cand:
                path = os.path.join(args.out, "cand-%s.json" % rec["name"])
                with open(path, "w") as fh:
                    json.dump(obj, fh)
                cands.append((obj, rec, path))
            if args.progress and (i + 1) % args.progress == 0:
                print("  [%s] %d seeds, %.0fs, max cons %d, max mints %d, candidates %d"
                      % (label, i + 1, time.time() - t0,
                         max(s["cons"] for x in stats for s in x["runs"].values()),
                         max(s["mints"] for x in stats for s in x["runs"].values()), len(cands)), flush=True)
    finally:
        if pool:
            pool.terminate()
        if jf:
            jf.close()
    return stats, cands


def report_stats(recs, label):
    strategies = sorted({st for rec in recs for st in rec["runs"]})
    for st in strategies:
        stats = [dict(rec["runs"][st], name=rec["name"]) for rec in recs if st in rec["runs"]]
        report_stats_one(stats, "%s/%s" % (label, st))
    print("   seed sizes: %d seeds, constraints per seed max %d, mean %.1f"
          % (len(recs), max(len(r["seed_cons_list"]) if "seed_cons_list" in r else next(iter(r["runs"].values()))["seed_cons"] for r in recs),
             sum(next(iter(r["runs"].values()))["seed_cons"] for r in recs) / max(1, len(recs))))


def report_stats_one(stats, label):
    if not stats:
        print("%s: no seeds" % label)
        return
    cons = [s["cons"] for s in stats]
    mints = [s["mints"] for s in stats]
    ratio = [s["mints"] / max(1, s["seed_cons"]) for s in stats]
    fixed = sum(1 for s in stats if s["stopped"].startswith("fixpoint"))
    unver = sum(1 for s in stats if s["stopped"] == "fixpoint-UNVERIFIED")
    print("== %s: %d seeds; fixpoint %d (unverified %d), mint-cap %d, con-cap %d, time-limit %d"
          % (label, len(stats), fixed, unver,
             sum(1 for s in stats if s["stopped"] == "mint-cap"),
             sum(1 for s in stats if s["stopped"] == "con-cap"),
             sum(1 for s in stats if s["stopped"] == "time")))
    print("   closure size: max %d  p99 %d  p90 %d  median %d" % (max(cons), percentile(cons, .99), percentile(cons, .9), percentile(cons, .5)))
    print("   mints:        max %d  p99 %d  p90 %d  median %d" % (max(mints), percentile(mints, .99), percentile(mints, .9), percentile(mints, .5)))
    print("   mints/seed:   max %.2f  p99 %.2f" % (max(ratio), percentile(ratio, .99)))
    print("   max children of one parent: %d;  max distinct groups at one lhs: %d;  rounds max %d;  slowest %.2fs"
          % (max(s["max_children"] for s in stats), max(s["max_groups"] for s in stats),
             max(s["rounds"] for s in stats), max(s["seconds"] for s in stats)))
    top = sorted(stats, key=lambda s: (-s["mints"], -s["cons"]))[:8]
    print("   largest: " + "; ".join("%s cons=%d mints=%d(%ds/%dr) %s" % (s["name"], s["cons"], s["mints"], s["split_mints"], s["res_mints"], s["stopped"]) for s in top))


def growth_curve(rho, cons, opts, strategy, caps, con_cap, time_limit):
    curve = []
    for cap in caps:
        G2 = build(rho, cons, scala_dedup=opts["scala_dedup"], rules=opts.get("rules"),
                   split_key=opts.get("split_key", False))
        r2 = closure(G2, mint_cap=cap, con_cap=con_cap, strategy=strategy, time_limit=time_limit, verify=True)
        curve.append((cap, len(G2.cons), G2.split_mints + G2.res_mints, r2.stopped, r2.rounds, round(r2.seconds, 1)))
        if r2.stopped.startswith("fixpoint") or r2.stopped == "time":
            break
    if G2.rho is not None and G2.mints:
        curve.append(("children of busiest parent", summarize(G2, r2, len(cons))["busiest_parent"]))
    return curve


def _recheck_work(job):
    obj, strategy, opts, caps, con_cap, time_limit = job
    name, rho, cons = load_seed(obj)
    o = dict(opts)
    o["strategy"] = strategy
    curve = growth_curve(rho, cons, o, strategy, caps, con_cap, time_limit)
    return (name, strategy, curve)


def recheck_candidates(cands, args, opts):
    """Re-run every candidate at caps up to --recheck-cap under --recheck-strategies (in
    parallel), and print, per candidate and strategy, whether the growth stopped (fixpoint),
    was unresolved (time), or continued through the last cap (mint cap or constraint cap
    hit with the mint count still climbing)."""
    if not cands:
        print("== no candidates")
        return []
    strategies = args.recheck_strategies.split(",")
    if args.recheck_max and len(cands) > args.recheck_max:
        # keep every candidate that is not a fixpoint under the FIRST search strategy (the
        # rarer kind), then fill up in search order
        first = next(iter(cands[0][1]["runs"]))
        rare = [c for c in cands if not c[1]["runs"][first]["stopped"].startswith("fixpoint")]
        rest = [c for c in cands if c not in rare]
        chosen = (rare + rest)[:args.recheck_max]
        print("== %d candidates; re-checking %d of them (%d not a fixpoint under %s, then search order); the rest are listed above"
              % (len(cands), len(chosen), len(rare), first))
        cands = chosen
    caps = sorted(set(int(c) for c in args.recheck_caps.split(",")) | {args.recheck_cap})
    caps = [c for c in caps if c <= args.recheck_cap]
    con_cap = max(args.con_cap, 10 * args.recheck_cap)
    print("== re-running %d candidates at mint caps %s (constraint cap %d, %.0fs each) under %s"
          % (len(cands), caps, con_cap, args.recheck_time, "/".join(strategies)))
    jobs = [(obj, st, opts, caps, con_cap, args.recheck_time) for (obj, rec, path) in cands for st in strategies]
    if args.jobs > 1 and len(jobs) > 1:
        from multiprocessing import Pool
        pool = Pool(args.jobs)
        results = list(pool.imap(_recheck_work, jobs))
        pool.terminate()
    else:
        results = [_recheck_work(j) for j in jobs]
    by_name = defaultdict(dict)
    for name, st, curve in results:
        by_name[name][st] = curve
    out = []
    growing = []
    for (obj, rec, path) in cands:
        name = obj["name"]
        verdicts = {}
        for st in strategies:
            curve = by_name[name][st]
            last = curve[-1] if curve[-1][0] != "children of busiest parent" else curve[-2]
            if last[3].startswith("fixpoint"):
                verdict = "STOPS (fixpoint at %d mints, %d constraints)" % (last[2], last[1])
            elif last[3] == "time":
                verdict = "UNRESOLVED (time %.0fs at cap %d: %d constraints, %d mints)" % (args.recheck_time, last[0], last[1], last[2])
            else:
                verdict = "KEEPS GROWING through cap %d (%s at %d mints, %d constraints)" % (last[0], last[3], last[2], last[1])
            verdicts[st] = (verdict, curve)
            print("   %s [%s] %s: %s" % (name, st, os.path.basename(path), verdict))
            print("      curve (cap, cons, mints, stop, rounds, s): %s" % curve)
        out.append((name, path, verdicts))
        if any(v[0].startswith("KEEPS") for v in verdicts.values()):
            growing.append((obj, verdicts))
    print("== %d of %d candidates keep growing under some strategy" % (len(growing), len(cands)))
    for obj, verdicts in growing[:args.show_growing]:
        name, rho, cons = load_seed(obj)
        st = next(st for st, v in verdicts.items() if v[0].startswith("KEEPS"))
        o = dict(opts)
        o["strategy"] = st
        G3 = build(rho, cons, scala_dedup=opts["scala_dedup"], rules=opts.get("rules"),
                   split_key=opts.get("split_key", False))
        r3 = closure(G3, mint_cap=min(args.recheck_cap, 120), con_cap=con_cap, strategy=st, time_limit=args.recheck_time, verify=False)
        print("## %s under %s (mint cap 120):" % (name, st))
        for c in cons:
            print("   %s" % fmt(c))
        print_report(G3, r3, len(cons), tail=opts["tail"])
    return out


def random_seed_stream(args):
    rng = random.Random(args.rng)
    for i in range(args.seeds):
        k = rng.randint(args.k_min, args.k_max)
        m = rng.randint(args.m_min, args.m_max)
        n = rng.randint(args.n_min, args.n_max)
        rho, cons = gen_random(rng, k, m, n, p_empty=args.p_empty, p_dup=args.p_dup, p_self=args.p_self,
                               no_empty=args.no_empty)
        yield seed_obj("r%d-k%dm%dn%d" % (i, k, m, n), rho, cons)


def family_stream(args):
    rng = random.Random(args.rng)
    S = args.max_size
    reps = args.family_reps
    for rep in range(reps):
        for m in range(2, S + 1):
            for d in range(2, min(S, 5) + 1):
                for nb in (2, 3):
                    rho, cons = fam_multidecomp(rng, m, d, nb)
                    yield seed_obj("multidecomp-m%dd%db%d-%d" % (m, d, nb, rep), rho, cons)
        for m in range(1, S + 1):
            for ne in range(2, min(S, 4) + 1):
                rho, cons = fam_empties(rng, m, ne)
                yield seed_obj("empties-m%de%d-%d" % (m, ne, rep), rho, cons)
        for m in range(3, S + 2):
            for depth in range(1, 4):
                for we in (False, True):
                    for wd in (False, True):
                        rho, cons = fam_resladder(rng, m, depth, we, wd)
                        yield seed_obj("resladder-m%dd%d%s%s-%d" % (m, depth, "e" if we else "", "d" if wd else "", rep), rho, cons)
        for depth in range(1, S + 1):
            for cross in (False, True):
                rho, cons = fam_chain(rng, depth, cross)
                yield seed_obj("chain-d%d%s-%d" % (depth, "x" if cross else "", rep), rho, cons)
        for m in range(2, S + 2):
            for r2 in range(1, 4):
                rho, cons = fam_mixed(rng, m, r2)
                yield seed_obj("mixed-m%dr%d-%d" % (m, r2, rep), rho, cons)
    for mv in range(3, min(S, 6) + 1):
        for nc in range(0, mv + 1):
            rho, cons = fam_costar(rng, mv, nc)
            yield seed_obj("costar-m%dc%d" % (mv, nc), rho, cons)
    for n in range(2, min(S, 8) + 1):
        for shared in (1, 2, 3):
            rho, cons = fam_overlap(rng, n, shared)
            yield seed_obj("overlap-n%ds%d" % (n, shared), rho, cons)
    for m in range(2, min(S, 6) + 1):
        rho, cons = fam_resstar(rng, m)
        yield seed_obj("resstar-m%d" % m, rho, cons)
    for n in range(2, min(S, 6) + 1):
        rho, cons = fam_joinchain(rng, n)
        yield seed_obj("joinchain-n%d" % n, rho, cons)


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def add_common(ap):
    ap.add_argument("--mint-cap", type=int, default=400)
    ap.add_argument("--con-cap", type=int, default=20000)
    ap.add_argument("--scala-dedup", action="store_true")
    ap.add_argument("--split-key", action="store_true",
                    help="key splitConcrete's guard on (lhs, conc) instead of the group "
                         "(Rowpartition/KeyedSplit.lean); default off")
    ap.add_argument("--strategy", choices=STRATEGIES, default="bfs")
    ap.add_argument("--rng-seed", type=int, default=0, help="pop order for --strategy random")
    ap.add_argument("--tail", type=int, default=60)
    ap.add_argument("--rules", default=None,
                    help="comma-separated subset of %s (default: all)" % ",".join(ALL_RULES))


def opts_of(args):
    rules = None
    if args.rules:
        rules = set(args.rules.split(","))
        bad = rules - set(ALL_RULES)
        if bad:
            raise SystemExit("unknown rules: %s" % ",".join(sorted(bad)))
    return {"mint_cap": args.mint_cap, "con_cap": args.con_cap, "scala_dedup": args.scala_dedup,
            "split_key": getattr(args, "split_key", False),
            "strategy": args.strategy, "tail": args.tail, "rules": rules,
            "time_per_seed": getattr(args, "time_per_seed", None),
            "strategies": getattr(args, "strategies", "bfs").split(","),
            "rng_seed": getattr(args, "rng_seed", 0)}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("run", help="close one seed file")
    p.add_argument("seed")
    p.add_argument("--time-limit", type=float, default=None)
    add_common(p)

    p = sub.add_parser("builtin", help="close a built-in calibration object")
    p.add_argument("which", choices=sorted(BUILTIN))
    p.add_argument("--time-limit", type=float, default=None)
    add_common(p)

    for name in ("search", "families"):
        p = sub.add_parser(name)
        add_common(p)
        p.add_argument("--out", default="rowclosure-out")
        p.add_argument("--rng", type=int, default=1)
        p.add_argument("--jobs", type=int, default=4)
        p.add_argument("--recheck-cap", type=int, default=2000)
        p.add_argument("--recheck-caps", default="100,400", help="intermediate mint caps of the growth curve")
        p.add_argument("--recheck-time", type=float, default=30.0)
        p.add_argument("--recheck-strategies", default="bfs,chase,dfs,lazy")
        p.add_argument("--show-growing", type=int, default=6, help="print the pattern of this many growing candidates")
        p.add_argument("--recheck-max", type=int, default=200, help="re-check at most this many candidates (0 = all)")
        p.add_argument("--time-per-seed", type=float, default=30.0)
        p.add_argument("--progress", type=int, default=2000)
        p.add_argument("--json", default=None, help="write per-seed stats as JSON lines")
        p.add_argument("--strategies", default="bfs,chase",
                       help="comma-separated strategies every seed is closed under (default bfs,chase; random:K uses pop-order seed K)")
        if name == "search":
            p.add_argument("--seeds", type=int, default=20000)
            p.add_argument("--k-min", type=int, default=3)
            p.add_argument("--k-max", type=int, default=7)
            p.add_argument("--m-min", type=int, default=2)
            p.add_argument("--m-max", type=int, default=4)
            p.add_argument("--n-min", type=int, default=2)
            p.add_argument("--n-max", type=int, default=6)
            p.add_argument("--p-empty", type=float, default=0.25, help="probability that a row is empty")
            p.add_argument("--p-dup", type=float, default=0.25, help="probability that a row duplicates an earlier one")
            p.add_argument("--p-self", type=float, default=0.04, help="probability of a self-partition a <- (a, empties)")
            p.add_argument("--no-empty", action="store_true", help="every seed row nonempty (ablation; implies --p-empty 0)")
        else:
            p.add_argument("--max-size", type=int, default=6)
            p.add_argument("--family-reps", type=int, default=3)

    args = ap.parse_args(argv)
    opts = opts_of(args)

    if args.cmd in ("run", "builtin"):
        obj = BUILTIN[args.which] if args.cmd == "builtin" else json.load(open(args.seed))
        name, rho, cons = load_seed(obj)
        run_seed(name, rho, cons, opts, time_limit=args.time_limit)
        return

    label = args.cmd
    stream = random_seed_stream(args) if args.cmd == "search" else family_stream(args)
    t0 = time.time()
    stats, cands = search_loop(stream, args, opts, label)
    print("total %.0fs" % (time.time() - t0))
    report_stats(stats, label)
    print("== candidates (%d): %s" % (len(cands), ", ".join(c[1]["name"] for c in cands) or "none"))
    for (obj, rec, path) in cands:
        print("   %s: %s" % (rec["name"], "; ".join("%s: %s cons=%d mints=%d" % (st, s["stopped"], s["cons"], s["mints"])
                                                    for st, s in rec["runs"].items())))
    recheck_candidates(cands, args, opts)


if __name__ == "__main__":
    main()
