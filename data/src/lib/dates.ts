// Calendar dates as integer DAY NUMBERS (days since 1970-01-01, UTC), so no
// time zone ever enters: the MSSQL scanner reads `date` in GMT (DB-PLAN §1).

export type Day = number;

export function dayOf(y: number, m: number, d: number): Day { return Math.round(Date.UTC(y, m - 1, d) / 86400000); }

export function parts(day: Day): { y: number; m: number; d: number; dow: number } {
  const t = new Date(day * 86400000);
  // dow: 0 = Monday .. 6 = Sunday (ISO)
  return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate(), dow: (t.getUTCDay() + 6) % 7 };
}

export function iso(day: Day): string {
  const { y, m, d } = parts(day);
  return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

export function parseIso(s: string): Day {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) throw new Error(`not an ISO date: ${s}`);
  return dayOf(Number(m[1]), Number(m[2]), Number(m[3]));
}

/** ISO 8601 week number. */
export function isoWeek(day: Day): number {
  const { dow } = parts(day);
  const thursday = day - dow + 3;
  const { y } = parts(thursday);
  return Math.floor((thursday - dayOf(y, 1, 1)) / 7) + 1;
}

export function daysInRange(from: Day, to: Day): Day[] {
  const out: Day[] = [];
  for (let d = from; d <= to; d++) out.push(d);
  return out;
}
