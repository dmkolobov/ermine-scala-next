import Rowpartition
open Lean Elab Command

run_cmd do
  let env ← getEnv
  let mut total := 0
  let mut bad : Array (Name × Name) := #[]
  for (name, info) in env.constants.toList do
    if (`Rowpartition).isPrefixOf name && !name.isInternal && info.isTheorem then
      total := total + 1
      let axs ← liftCoreM <| Lean.collectAxioms name
      for a in axs do
        unless a == ``propext || a == ``Classical.choice || a == ``Quot.sound do
          bad := bad.push (name, a)
  logInfo s!"Rowpartition theorems audited: {total}; declarations using a non-standard axiom: {bad.size}"
  for (n, a) in bad do logInfo s!"  OFFENDER {n} uses {a}"
