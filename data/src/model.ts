// What a domain model hands the emitter: for every base table, a PRODUCER of
// rows (records keyed by the contract's column names).  Producers are called
// in the contract's loadOrder, one at a time, so a fact table can be streamed
// (tier l is 2 M lines) and a table derived from it (targets, marts) can be
// computed from aggregates the fact producer left behind.

import type { Cell } from "./lib/csv.js";
import type { Day } from "./lib/dates.js";

export type Row = Record<string, Cell>;
export type Producer = () => Iterable<Row>;

export interface TierSpec {
  /** xs, s, m, l, or the nearest named tier when --rows overrides */
  name: string;
  /** number of FACT rows to generate (exact) */
  factRows: number;
  /** row count per dimension table, from the contract's tables[].rows[tier] */
  dimRows: Record<string, number>;
  /** the calendar range of the tier, inclusive */
  from: Day;
  to: Day;
}

export interface Domain {
  name: string;
  producers(seed: number, tier: TierSpec): Map<string, Producer>;
}
