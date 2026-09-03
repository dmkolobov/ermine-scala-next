import json
from rules import *
from experiments import witness, nonempty_multi
def dump(name, G, rho, fn):
    d = {"name": name, "rho": {str(v): sorted(r) for v, r in rho.items()},
         "cons": [[c[0], sorted(c[1]), sorted(c[2])] for c in sorted(G)]}
    json.dump(d, open(fn, "w"), indent=1); print(fn)
G, rho = witness(); dump("W2: p<-(e1,e2,k), p<-(e2,k); rho p={k,m} e2={m} e1={}", G, rho, "W2.json")
p,e1,e2,q,s,k = 0,1,2,3,4,100
H = {mk(p,{e1,e2},{k}), mk(q,{p,s},()), mk(q,{e2,s},{k})}
rho = {p:frozenset({k,101}), e1:frozenset(), e2:frozenset({101}), q:frozenset({k,101,102}), s:frozenset({102})}
assert models(rho,H); dump("H2: W2 with p<-(e2,k) hidden behind q<-(p,s), q<-(e2,s,k)", H, rho, "H2.json")
G, rho = nonempty_multi(); dump("NE6: all input rows nonempty; first mint is an EMPTY resolvent", G, rho, "NE6.json")
# z <- () derivable for the res-empty of NE6 under saturation?
st, Gs, rhos, mints = closure(G, rho, 30, 4000)
emp = [v for v in all_vars(Gs) if not rhos[v]]
print("NE6 saturation:", st, "mints", len(mints), "empties", emp, "detected:", [v for v in emp if mk(v,(),()) in Gs])
