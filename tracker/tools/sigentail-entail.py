#!/usr/bin/env python3
"""TRIAGE AID for the sigEntail survey (stage S1 of tracker/SIG-ENTAIL-PLAN.md).

    tracker/tools/sigentail-entail.py <outdir>      # prints the groups it could not settle

A little ATOM solver over the `sigEntail` records, to split the non-literal ROW
obligations into ENTAILED / REFUTED / UNSURE without doing three hundred of them by hand.
It is NOT a gate and NOT the entailment check S2 designs: it is deliberately incomplete,
and everything it leaves UNSURE was read by hand against the source for
tracker/loopmodel/SIG-1-SURVEY.md.

Model: the givens decompose each partitioned variable into ATOMS (a variable that is
never a left-hand side).  Two atoms are KNOWN-DISJOINT when they sit in different parts
of some given partition.  A wanted `X <- (q1..qn)` splits its parts into KNOWN (rigid,
or existentials the givens already fix) and FREE (an `A` variable the givens never
mention -- the solver's own minted remainder, which we may choose).

  ENTAILED  the known parts are pairwise known-disjoint and inside X, and either they
            exhaust X or a free part is there to take the remainder.
  REFUTED    a known part is NOT inside X, or X is exhausted and a known part is left
            over.  Both are witnessed by a model of the givens, so this is a real hole.
  UNSURE     two known parts are not KNOWN-disjoint (disjointness might still follow by
            a chain the atom reading does not see), or the arithmetic did not close.

Free variables are shared between the wanteds of one signature, so a free part that is
FORCED (it is the only free part of its wanted) is solved and substituted everywhere,
to a fixpoint, before anything is judged.

KNOWN LIMITATIONS, both of which only move a hit into the hand-checked bucket:
  * a left-hand side with SEVERAL given partitions is decomposed by the first one only;
  * disjointness is never derived by a chain, only read off one given partition.
"""
import re,sys,os,collections
VAR=re.compile(r'\^\d+'); PART=re.compile(r'^(.*?) <- \((.*)\)$')
def _sortpart(w):
    m=PART.match(w)
    return w if not m else m.group(1)+' <- ('+', '.join(sorted(m.group(2).split(', ')))+')'
def norm(s): return '; '.join(sorted(_sortpart(x) for x in VAR.sub('^',s).split('; ')))

def read(paths):
    files=[]
    for p in paths:
        if os.path.isdir(p): files+=[os.path.join(p,n) for n in sorted(os.listdir(p)) if n.endswith('.out')]
        else: files.append(p)
    seen=set(); groups=collections.OrderedDict()
    for f in files:
        for line in open(f,errors='replace'):
            if not line.startswith('sigEntail\t'): continue
            c=line.rstrip('\n').split('\t')
            if len(c)<8: continue
            mod,bind,pos,shape,lit,w,g=c[1],c[2],c[3],c[4],c[5],c[6],c[7]
            if ' <- ' not in w: continue
            k=(mod,bind,pos,norm(w),norm(g))
            if k in seen: continue
            seen.add(k)
            groups.setdefault((mod,bind,norm(g)),[]).append((pos,shape,lit,w,g))
    return groups

def solve(items):
    g=items[0][4]
    gparts=[PART.match(x) for x in g.split('; ')]
    given=[(m.group(1), m.group(2).split(', ')) for m in gparts if m]
    gvars=set(re.findall(r'[A-Za-z_\'`\.\|\(\)]*\^\d+[SAB]?', g))
    lhsmap=collections.defaultdict(list)
    for l,ps in given: lhsmap[l].append(ps)
    def atoms(t, seen=()):
        if t.startswith('(|'):                       # a concrete label set is an atom
            return frozenset([t])
        if t in lhsmap and t not in seen:
            out=set()
            for ps in lhsmap[t][:1]:
                for p in ps: out |= atoms(p, seen+(t,))
            return frozenset(out)
        return frozenset([t])
    disj=set()
    for l,ps in given:
        for i in range(len(ps)):
            for j in range(i+1,len(ps)):
                for a in atoms(ps[i]):
                    for b in atoms(ps[j]):
                        disj.add((a,b)); disj.add((b,a))
    # FREE = an A-variable the givens never mention
    def isfree(t): return t.endswith('A') and t not in gvars
    sol={}                                           # free var -> frozenset of atoms
    def av(t):
        if isfree(t): return sol.get(t)
        return atoms(t)
    for _ in range(6):
        changed=False
        for pos,shape,lit,w,_g in items:
            m=PART.match(w)
            if not m: continue
            X=av(m.group(1)); parts=m.group(2).split(', ')
            if X is None: continue
            vals=[av(p) for p in parts]
            unk=[p for p,v in zip(parts,vals) if v is None]
            if len(unk)==1:
                known=frozenset().union(*[v for v in vals if v is not None]) if any(v is not None for v in vals) else frozenset()
                rem=X-known
                if sol.get(unk[0])!=rem: sol[unk[0]]=rem; changed=True
        if not changed: break
    out=[]
    for pos,shape,lit,w,_g in items:
        if lit=='lit': out.append(('a',w,pos)); continue
        m=PART.match(w)
        if not m: out.append(('UNSURE',w,pos)); continue
        Xt=m.group(1); parts=m.group(2).split(', ')
        X=av(Xt); vals=[av(p) for p in parts]
        if any(v is None for v in vals) or X is None:
            # several unforced free parts (or a free whole): take one arrangement
            known=frozenset().union(*[v for v in vals if v is not None]) if any(v is not None for v in vals) else frozenset()
            if X is None:
                kp=[ (p,v) for p,v in zip(parts,vals) if v is not None ]
                bad=[(a,b) for i in range(len(kp)) for j in range(i+1,len(kp)) for a in kp[i][1] for b in kp[j][1] if (a,b) not in disj]
                out.append((('b' if not bad else 'UNSURE'),w,pos)); continue
            out.append((('b' if known<=X else 'REFUTED'),w,pos)); continue
        kp=list(zip(parts,vals))
        bad=[(a,b) for i in range(len(kp)) for j in range(i+1,len(kp)) for a in kp[i][1] for b in kp[j][1] if (a,b) not in disj and a!=b]
        union=frozenset().union(*[v for _,v in kp]) if kp else frozenset()
        if bad: out.append(('UNSURE',w,pos))
        elif union==X: out.append(('b',w,pos))
        elif not (union<=X): out.append(('REFUTED',w,pos))
        else: out.append(('UNSURE',w,pos))
    return out

groups=read(sys.argv[1:])
tot=collections.Counter(); bad=collections.OrderedDict()
for k,items in groups.items():
    res=solve(items)
    for t,w,pos in res: tot[t]+=1
    if any(t in ('REFUTED','UNSURE') for t,_,_ in res): bad[k]=(items,res)
for (mod,bind,gn),(items,res) in bad.items():
    print('### %s . %s' % (mod,bind))
    print('    givens: %s' % items[0][4])
    for t,w,pos in res:
        print('    %-8s %-58s %s' % (t,w,pos.split('modules/')[-1].split('core/examples/')[-1]))
    print()
print('groups=%d %s' % (len(groups),dict(tot)), file=sys.stderr)
