/-
# Replaying a compiler trace: `looptrace --replay`

Stage L2 of `tracker/LOOP-MODEL-PLAN.md`.  L1 ran the model on `json:` seeds built by
`tracker/repro/satterm/SatTermRepro.scala`.  L2 runs it on EVERY `Subst.solve` the compiler
performs while it loads the corpus, by reading back the compiler's own
`-Dermine.rowTrace` file.

What a replay needs beyond the records L1 had, and where it now comes from
(`RowTrace.scala`'s FORMAT block has the field lists):

* the `Supply`'s next id at the start of the solve -- `sin`.  The queue is ordered by
  `rhs.hashCode`, `V.hashCode` IS the id, so a mint at the wrong id reorders the queue;
* every input variable's `VarType` -- `svar`.  `Partition.toString` prints
  `ty.toString.toLowerCase`, and in real code `ty` is `Free`, `Skolem`, `Bound`,
  `Unspecified` or `Ambiguous(_)` with no relation to the id.  This is L1 review F7;
* every label's `Name` -- `slbl`.  `Name.hashCode` is `(2, module, string, fixity.con)`,
  which decides the `Set` iteration order and hence the queue order and the printed rows;
* the constraint list in the order `PQueue.build` receives it, with each element's
  `hashCode` and its `equals` class -- `scon`.  `Exists.apply` puts that list through
  `p.toSet.toList` before `aux` sees it, so an element the solver never inspects (a class
  constraint, say) can still move the ones it does.

The parser is deliberately total: a record it cannot make sense of makes the SEGMENT
unreplayable and is reported, never silently dropped.
-/
import Rowpartition.Loop.Seed

namespace Rowpartition.Loop

/-! ## 1. Small parsers -/

/-- A decimal Java `int`, possibly negative, as its bit pattern. -/
def parseI32 (s : String) : Option I32 :=
  match s.toInt? with
  | none => none
  | some i => some (UInt32.ofNat (((i % 4294967296) + 4294967296) % 4294967296).toNat)

/-- Split on a one-character separator. -/
def splitOn1 (sep : Char) (s : String) : List String :=
  s.splitOn (String.singleton sep)

/-! ## 2. One solve's replay input -/

/-- Everything the four replay records carry about ONE `Subst.solve`. -/
structure Segment where
  /-- `RowTrace.site`, the record's second column. -/
  site : String := "?"
  /-- `RowTrace.clean(l.toString)`, the third column. -/
  loc : String := "-"
  /-- The `Supply`'s `lo` and `hi` when the solve started, and the GLOBAL block counter and
  block size, which is what `Supply.fresh` reaches for when the block runs out. -/
  suLo : Nat := 0
  suHi : Nat := 0
  suBlk : Nat := 0
  suBsz : Nat := 1024
  /-- `cs.flatMap(_.rowConstraints).length`, the number of `in` records the compiler wrote:
  a cross-check that the `part` items really are the row constraints. -/
  nRows : Nat := 0
  /-- `cs.length`, for a consistency check against the `scon` records. -/
  nCs : Nat := 0
  /-- The label table, index 0 first.  This one is built FORWARDS, unlike the other three:
  `parseTerm` indexes into it while the `scon` records are still being read, so it has to be
  in its final order before `finish` runs. -/
  labels : List Lbl := []
  /-- `(id, ty, name)` per input variable. -/
  vars : List (Nat × String × String) := []
  /-- The constraint list, in the list's own order. -/
  cons : List CsItem := []
  /-- Each `scon`'s recorded `hashCode`, for the cross-check against the model's own. -/
  recHash : List I32 := []
  /-- Each `scon`'s recorded `eqid`: the index of the first element of the list it is
  `equals` to.  For an `other` item this IS the model's notion of equality; for a `part` the
  model computes `IPart.eqv` itself and this is a cross-check. -/
  recEqid : List Nat := []
  /-- Whether every `scon` was a `part`. -/
  allParts : Bool := true
  /-- S2: the `senv` records — the `SubstEnv` binding of each variable the input mentions,
  which `Subst.solve` does NOT apply to its input (S1 review Z-6).  Only ever nonempty in a
  trace taken with `-Dermine.rowSound.decide`; the layer-(iii) decision is about the input
  TOGETHER with these facts, so a replay that could not see them could not reproduce a
  flags-ON trace.  Accumulated reversed, like `vars`. -/
  envs : List (Nat × ITerm) := []
  /-- Parse or consistency failures; a nonempty list makes the segment unreplayable. -/
  errs : List String := []

namespace Segment

/-- Reverse the accumulated lists once the segment is complete. -/
def finish (g : Segment) : Segment :=
  { g with vars := g.vars.reverse, cons := g.cons.reverse,
           recHash := g.recHash.reverse, recEqid := g.recEqid.reverse,
           envs := g.envs.reverse, errs := g.errs.reverse }

def err (g : Segment) (m : String) : Segment := { g with errs := m :: g.errs }

/-- `Names` for this segment: the `svar` table, and `suLo` for the mint fallback. -/
def names (g : Segment) : Names :=
  { named := g.vars.filterMap (fun (i, _, n) => if n.isEmpty then none else some (i, n)),
    tys := g.vars.map (fun (i, t, _) => (i, t)),
    supplyLo := g.suLo }

/-- The `Supply` this solve started with. -/
def sup (g : Segment) : Sup :=
  { lo := g.suLo, hi := g.suHi, blk := g.suBlk, bsz := g.suBsz }

/-- The environment facts as PARTITIONS, which is how `S2-DESIGN.md` §3 defines them:
`v := ((|fs|))` is `v <- ((|fs|))` and `v := u` is the link `v <- (u)`.  A binding that is
not row-shaped (`otherT`) is DROPPED — the decision then runs on a sub-system, which keeps
its refutations sound and is exactly what the compiler's `opaque` counter records. -/
def envFacts (g : Segment) : List LPart :=
  g.envs.filterMap (fun (v, t) =>
    match t with
    | .varT u => some ⟨v, RHS.ofAbstr (SSet.ofList [u]), none⟩
    | .concRho fs => some ⟨v, RHS.ofConcr fs, none⟩
    | .conT l => some ⟨v, RHS.ofConcr (SSet.ofList [l]), none⟩
    | .otherT _ => none)

/-- Bindings the model had to drop because they are not row-shaped. -/
def envOpaque (g : Segment) : Nat :=
  (g.envs.filter (fun p => match p.2 with | .otherT _ => true | _ => false)).length

end Segment

/-! ## 3. Parsing the records -/

/-- One term of an `scon` payload. -/
def parseTerm (labels : List Lbl) (t : String) : Except String ITerm :=
  match t.toList with
  | [] => .error "empty term"
  | c :: cs =>
    let body := String.ofList cs
    if c == 'v' then
      match body.toNat? with
      | some v => .ok (.varT v)
      | none => .error ("bad variable term " ++ t)
    else if c == 'c' || c == 'C' then
      -- `C` is a `ConcreteRho` whose field set is an `immutable.HashSet`, `c` a `SetN`.
      -- A `SetN` iterates in insertion order and a `HashSet` in CHAMP order, and the two
      -- differ under any later `+`, so the REPRESENTATION is recorded, not inferred from
      -- the size: a set of four or fewer that was derived from a bigger one is still a
      -- `HashSet` (`SSet`'s `hashed` flag, `HashSet.scala:603`).
      let idxs := (splitOn1 ',' body).filter (fun x => !x.isEmpty)
      let ls := idxs.map (fun x => (x.toNat?).bind (fun i => labels[i]?))
      if ls.all Option.isSome then
        .ok (.concRho ⟨c == 'C', ls.filterMap id⟩)
      else .error ("bad label index in " ++ t)
    else if c == 'k' then
      match (body.toNat?).bind (fun i => labels[i]?) with
      | some l => .ok (.conT l)
      | none => .error ("bad Con label index in " ++ t)
    else if c == 'o' then
      match parseI32 body with
      | some h => .ok (.otherT h)
      | none => .error ("bad foreign-term hash in " ++ t)
    else .error ("unknown term tag in " ++ t)

/-- Fold one record into the segment under construction. -/
def addRecord (g : Segment) (f : List String) : Segment :=
  match f with
  | "slbl" :: _ :: _ :: idx :: kind :: con :: m :: str :: _ =>
    match idx.toNat?, con.toNat? with
    | some i, some k =>
      if i == g.labels.length then
        { g with labels := g.labels ++
                   [{ n := i, glob := kind == "G", mod := m, str := str, con := k }] }
      else g.err ("slbl out of order: " ++ idx)
    | _, _ => g.err ("bad slbl: " ++ idx ++ " " ++ con)
  | "svar" :: _ :: _ :: idS :: ty :: rest =>
    match idS.toNat? with
    | some i => { g with vars := (i, ty, rest.headD "") :: g.vars }
    | none => g.err ("bad svar id: " ++ idS)
  | "scon" :: _ :: _ :: iS :: eS :: hS :: kind :: rest =>
    match iS.toNat?, eS.toNat?, parseI32 hS with
    | some i, some e, some h =>
      if i != g.cons.length then g.err ("scon out of order: " ++ iS) else
      if kind == "part" then
        -- The payload is `lhs|rhs1|rhs2|...`; a `Part` whose right-hand side is the EMPTY
        -- list therefore ends in a trailing separator, and no term is ever the empty
        -- string, so dropping empties is exactly "one term per field".  (Found by the
        -- random-systems sweep: `rowclosure.py` generates `a <- ()` constraints, which the
        -- corpus happens never to write.)
        let terms := (splitOn1 '|' (rest.headD "")).filter (fun x => !x.isEmpty)
        let parsed := terms.map (parseTerm g.labels)
        match parsed with
        | [] => g.err "empty part payload"
        | lhs :: rhs =>
          match lhs with
          | .error m => g.err m
          | .ok lt =>
            if rhs.any (fun r => match r with | .error _ => true | .ok _ => false) then
              g.err ("bad rhs term in scon " ++ iS)
            else
              let rts := rhs.filterMap (fun r => match r with | .ok x => some x | .error _ => none)
              { g with cons := CsItem.part ⟨lt, rts⟩ :: g.cons, recHash := h :: g.recHash,
                       recEqid := e :: g.recEqid }
      else
        { g with cons := CsItem.other h e :: g.cons, recHash := h :: g.recHash,
                 recEqid := e :: g.recEqid, allParts := false }
    | _, _, _ => g.err ("bad scon: " ++ iS)
  | "senv" :: _ :: _ :: vS :: payload :: _ =>
    -- `senv site loc v<id> <term>`: the term language is `scon`'s, and every label it can
    -- mention is already in `g.labels` (`RowTrace.solveInput` renders the facts before it
    -- writes the tables, so `term` has numbered them).
    match (if vS.startsWith "v" then (vS.drop 1).toNat? else none),
          parseTerm g.labels payload with
    | some v, .ok t => { g with envs := (v, t) :: g.envs }
    | _, _ => g.err ("bad senv: " ++ vS ++ " " ++ payload)
  | _ => g

/-- `sin`: start a fresh segment. -/
def startSegment (f : List String) : Segment :=
  match f with
  | "sin" :: site :: loc :: lo :: hi :: n :: rest =>
    let g : Segment := { site := site, loc := loc }
    let g := match lo.toNat?, hi.toNat?, n.toNat? with
      | some a, some b, some c => { g with suLo := a, suHi := b, nCs := c }
      | _, _, _ => g.err "bad sin"
    match rest with
    | blk :: bsz :: nr :: _ =>
      match blk.toNat?, bsz.toNat?, nr.toNat? with
      | some a, some b, some c => { g with suBlk := a, suBsz := b, nRows := c }
      | _, _, _ => g.err "bad sin block fields"
    | _ => g.err "sin has no block fields (trace predates the L2 RowTrace)"
  | _ => ({ } : Segment).err "bad sin"

/-- Split a whole trace file into solve segments at its `sin` records. -/
def parseSegments (lines : List String) : List Segment :=
  let step := fun (acc : List Segment) (ln : String) =>
    let f := ln.splitOn "\t"
    match f.head? with
    | some "sin" => startSegment f :: acc
    | some "slbl" | some "svar" | some "scon" | some "senv" =>
      match acc with
      | [] => acc
      | g :: rest => addRecord g f :: rest
    | _ => acc
  (lines.foldl step []).reverse.map Segment.finish

/-! ## 4. Replaying one segment -/

/-- The model's answer for one segment: the records, and the cross-checks. -/
structure ReplayOut where
  records : List String
  /-- `scon`s whose `hashCode` the model computes differently from the compiler's. -/
  hashDiffs : Nat
  /-- `scon`s whose `equals` CLASS the model computes differently: the index of the first
  earlier element the model calls equal, against the compiler's `eqid`. -/
  eqDiffs : Nat
  verdict : String
  message : String

/-- Run the model on one segment.  Returns `none` when the segment cannot be replayed, with
the reason. -/
def replay (fl : Flags) (fuel : Nat) (g : Segment) : Except String ReplayOut :=
  if !g.errs.isEmpty then .error (String.intercalate "; " g.errs)
  else if g.cons.length != g.nCs then
    .error ("scon count " ++ toString g.cons.length ++ " != nCs " ++ toString g.nCs)
  else if (g.cons.filterMap CsItem.part?).length != g.nRows then
    -- `in` records are `cs.flatMap(_.rowConstraints)`; when that is not the `part` items the
    -- model cannot generate them, so the segment is reported rather than mis-diffed.
    .error ("rowConstraints " ++ toString g.nRows ++ " != part items " ++
            toString (g.cons.filterMap CsItem.part?).length)
  else
    let hashDiffs :=
      ((g.cons.zip g.recHash).filter (fun (c, h) => c.hshOf != h)).length
    -- the model's own `equals` class of each element, against the compiler's `eqid`
    let idx := withIndex g.cons
    let eqDiffs :=
      ((idx.zip g.recEqid).filter (fun ((c, i), e) =>
        let first := (idx.findSome? (fun (d, j) => if CsItem.eqv d c then some j else none)).getD i
        first != e)).length
    let out := solveSeed fl g.site g.loc g.cons g.names g.sup fuel g.envFacts
    .ok { records := out.records, hashDiffs := hashDiffs, eqDiffs := eqDiffs,
          verdict := out.verdict, message := out.message }

end Rowpartition.Loop
