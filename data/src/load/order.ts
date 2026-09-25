// The FK load order: parents before children, computed from the contract's
// tables[].fks (Kahn's algorithm, ties broken by the contract's table order so
// the result is deterministic), and checked against the contract's loadOrder.

export interface FkTable { name: string; fks: { ref: string }[] }

export function fkOrder(tables: readonly FkTable[]): string[] {
  const names = tables.map((t) => t.name);
  const known = new Set(names);
  const deps = new Map<string, Set<string>>();
  for (const t of tables) {
    const d = new Set<string>();
    for (const fk of t.fks) {
      if (!known.has(fk.ref)) throw new Error(`${t.name}: foreign key to unknown table ${fk.ref}`);
      if (fk.ref !== t.name) d.add(fk.ref);      // a self-reference does not order tables
    }
    deps.set(t.name, d);
  }
  const done = new Set<string>(), out: string[] = [];
  while (out.length < names.length) {
    const next = names.find((n) => !done.has(n) && [...deps.get(n)!].every((p) => done.has(p)));
    if (next === undefined) {
      const left = names.filter((n) => !done.has(n));
      throw new Error(`foreign-key cycle among ${left.join(", ")}`);
    }
    done.add(next); out.push(next);
  }
  return out;
}

/** Every table appears after all the tables it references. */
export function respectsFks(order: readonly string[], tables: readonly FkTable[]): string | null {
  const pos = new Map(order.map((n, i) => [n, i]));
  for (const t of tables) {
    if (!pos.has(t.name)) return `${t.name} is missing from the order`;
    for (const fk of t.fks) if (fk.ref !== t.name && (pos.get(fk.ref) ?? Infinity) > pos.get(t.name)!) return `${t.name} comes before its parent ${fk.ref}`;
  }
  return null;
}
