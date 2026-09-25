// The SALES domain model (tracker/DB-PLAN.md §2 "Semantic realism",
// tracker/db/GENERATOR.md for every range and why).  A pure function of
// (seed, tier): every random draw comes from a named PCG32 stream
// (lib/pcg32.ts `stream`), and faker is reseeded per entity from one.
//
// Shape of the business: a company selling office furniture, lighting,
// outdoor gear and accessories, B2B and online, in the N largest markets
// (population x World Bank income factor) of a vendored country list.

import * as F from "@faker-js/faker";
import type { Faker } from "@faker-js/faker";
import { stream } from "../lib/pcg32.js";
import { Categorical, Dist, round } from "../lib/dist.js";
import { Day, dayOf, iso, parts } from "../lib/dates.js";
import type { Domain, Producer, Row, TierSpec } from "../model.js";
import countriesJson from "../reference/countries.json" with { type: "json" };
import catalogueJson from "../reference/catalogue.json" with { type: "json" };

// ---------------------------------------------------------------- reference

interface CountryRef { code: string; iso2: string; country: string; name: string; group: string; pop: number; income: string; locale: string }
interface CategoryRef { category: string; sub: [string, string][]; band: [number, number]; qtyMedian: number; qtySigma: number; costRatio: number; season: string }
interface ChannelRef { name: string; isDirect: string; promoRate: number; discountRate: number; discountMax: number }

const COUNTRIES = countriesJson.countries as CountryRef[];
const INCOME_FACTOR = countriesJson.incomeFactor as Record<string, number>;
const CATEGORIES = catalogueJson.categories as unknown as CategoryRef[];
const SERIES = catalogueJson.series as string[];
const VARIANTS = catalogueJson.nounVariants as string[];
const CHANNELS = catalogueJson.channels as ChannelRef[];
const CHANNEL_MIX = catalogueJson.channelMix as Record<string, number[]>;
const CAMPAIGNS = catalogueJson.campaigns as Record<string, string[]>;

export const GROUPS = ["EMEA", "APAC", "AMER"] as const;
export const PRICE_BANDS = ["low", "mid", "high", "premium"] as const;
const BAND_WEIGHTS = [0.35, 0.35, 0.2, 0.1];
export const TIERS_CUST = ["gold", "silver", "bronze"] as const;
const TIER_WEIGHTS = [0.1, 0.3, 0.6];
/** order frequency, quantity and lines-per-order factors per customer tier */
const TIER_FREQ: Record<string, number> = { gold: 6, silver: 2.5, bronze: 1 };
const TIER_QTY: Record<string, number> = { gold: 2, silver: 1.3, bronze: 1 };
const TIER_EXTRA_LINES: Record<string, number> = { gold: 2.2, silver: 1.3, bronze: 0.6 };

/** Mon..Sun: B2B ordering, weekends nearly empty (online keeps them above 0). */
export const WEEKDAY = [1.1, 1.2, 1.2, 1.15, 0.95, 0.25, 0.15];
/** Jan..Dec, the blended daily-volume curve; categories re-mix within a month. */
export const MONTH = [0.85, 0.9, 1.1, 0.95, 1.0, 1.1, 0.85, 0.8, 1.1, 1.05, 1.1, 1.0];
export const SEASON: Record<string, number[]> = {
  office: [0.9, 0.95, 1.1, 0.95, 1.0, 1.05, 0.85, 0.9, 1.15, 1.05, 1.05, 1.0],
  outdoor: [0.5, 0.6, 0.9, 1.2, 1.4, 1.5, 1.4, 1.1, 0.9, 0.7, 0.8, 0.9],
  flat: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.2, 1.2],
};
const ANNUAL_GROWTH = 0.08;
const QUARTER_END_PUSH = 1.2;   // the last 10 days of a quarter
const HOLIDAY = 0.1;            // Jan 1, Dec 24-26, Dec 31
const DAY_NOISE_SIGMA = 0.2;    // log-normal day-to-day noise
const MAX_QTY = 50;             // contract: quantity 1..50
const MAX_LINE = 50000;         // contract: lineAmount <= 50 000
const MAX_DISCOUNT = 0.3;       // contract: discountPct <= 0.3
const MAX_LINES = 8;            // contract: lineNo 1..8
const PRICE_SPREAD = 0.015;     // sd of the per-line price deviation from list
const PRICE_SPREAD_CAP = 0.04;

// ---------------------------------------------------------------- helpers

const fakerByLocale = new Map<string, Faker>();
function fakerFor(locale: string): Faker {
  let f = fakerByLocale.get(locale);
  if (!f) {
    const key = "faker" + locale.toUpperCase();
    const inst = (F as unknown as Record<string, Faker | undefined>)[key];
    if (!inst) throw new Error(`no faker locale ${locale} (${key})`);
    f = inst; fakerByLocale.set(locale, f);
  }
  return f;
}

/** Faker reseeded from a named PCG stream: the text of entity `i` depends on (seed, label, i) only. */
function seeded(seed: number, label: string, locale: string): Faker {
  const f = fakerFor(locale);
  const g = stream(seed, label);
  f.seed([g.nextU32(), g.nextU32()]);
  return f;
}

/** Largest-remainder allocation of `total` over `weights`, at least `min` each. */
export function allocate(total: number, weights: readonly number[], min = 0): number[] {
  const n = weights.length;
  const base = new Array<number>(n).fill(min);
  let rest = total - min * n;
  if (rest < 0) throw new Error(`allocate: ${total} < ${min} x ${n}`);
  const sum = weights.reduce((a, b) => a + b, 0);
  const exact = weights.map((w) => (w / sum) * rest);
  const floor = exact.map(Math.floor);
  const out = base.map((b, i) => b + (floor[i] as number));
  rest -= floor.reduce((a, b) => a + b, 0);
  const order = exact.map((e, i) => [e - (floor[i] as number), i] as const)
    .sort((a, b) => b[0] - a[0] || a[1] - b[1]);
  for (let k = 0; k < rest; k++) out[(order[k % n] as readonly [number, number])[1]]! += 1;
  return out;
}

/** Band edges of a category: its [lo, hi] cut into four log-equal slices. */
export function bandEdges(cat: CategoryRef, band: number): [number, number] {
  const [lo, hi] = cat.band;
  const r = Math.pow(hi / lo, 1 / 4);
  return [round(lo * Math.pow(r, band), 2), round(lo * Math.pow(r, band + 1), 2)];
}

export function categoryByName(name: string): CategoryRef | undefined { return CATEGORIES.find((c) => c.category === name); }

/** A retail price point inside [lo, hi]: x.99 under 100, x9.00 under 1000, x9 above. */
function pricePoint(x: number, lo: number, hi: number): number {
  const candidates = x < 100 ? [Math.floor(x) + 0.99, Math.floor(x) - 0.01, Math.round(x)]
    : x < 1000 ? [Math.floor(x / 10) * 10 + 9, Math.floor(x / 10) * 10 - 1, Math.round(x)]
    : [Math.floor(x / 10) * 10 + 9, Math.floor(x / 10) * 10 - 1, Math.round(x)];
  for (const c of candidates) if (c >= lo && c <= hi) return round(c, 2);
  return round(Math.min(hi, Math.max(lo, x)), 2);
}

// ---------------------------------------------------------------- entities

export interface Region { regionId: number; ref: CountryRef; weight: number }
export interface Product { productId: number; cat: CategoryRef; sub: string; band: number; listPrice: number; unitCost: number; popularity: number; row: Row }
interface Rep { repId: number; regionId: number; row: Row }
interface Customer { customerId: number; regionId: number; tier: string; signup: Day; repId: number; weight: number; row: Row }
interface Channel { channelId: number; ref: ChannelRef }

/** The N regions: the largest markets by population x income factor, every group present. */
export function pickRegions(n: number): Region[] {
  const scored = COUNTRIES.map((c) => ({ c, w: c.pop * (INCOME_FACTOR[c.income] ?? 0) }))
    .sort((a, b) => b.w - a.w || (a.c.code < b.c.code ? -1 : 1));
  const chosen = scored.slice(0, n);
  for (const g of GROUPS) {
    if (n >= GROUPS.length && !chosen.some((x) => x.c.group === g)) {
      const best = scored.find((x) => x.c.group === g)!;
      // drop the lightest region of the best-represented group
      const counts = new Map<string, number>();
      for (const x of chosen) counts.set(x.c.group, (counts.get(x.c.group) ?? 0) + 1);
      const big = [...counts.entries()].sort((a, b) => b[1] - a[1])[0]![0];
      const drop = chosen.map((x, i) => [x, i] as const).filter(([x]) => x.c.group === big).pop()!;
      chosen.splice(drop[1], 1, best);
    }
  }
  const total = chosen.reduce((a, x) => a + x.w, 0);
  // weights to 6 dp, the last one absorbing the rounding so they sum to exactly 1 (to 6 dp)
  const ws = chosen.map((x) => round(x.w / total, 6));
  const drift = round(1 - ws.reduce((a, b) => a + b, 0), 6);
  ws[0] = round((ws[0] as number) + drift, 6);
  return chosen.map((x, i) => ({ regionId: i + 1, ref: x.c, weight: ws[i] as number }));
}

// ---------------------------------------------------------------- the model

export interface SalesState {
  regions: Region[];
  products: Product[];
  /** sum of lineAmount per `${regionId}/${year}/${quarter}` */
  regionQuarter: Map<string, number>;
  factLines: number;
}

export function salesDomain(): Domain & { lastState?: SalesState } {
  const dom: Domain & { lastState?: SalesState } = {
    name: "sales",
    producers(seed: number, tier: TierSpec): Map<string, Producer> {
      const P = new Map<string, Producer>();
      const S = (label: string) => new Dist(stream(seed, `sales/${label}`));
      const n = (t: string) => {
        const v = tier.dimRows[t];
        if (v === undefined) throw new Error(`tier ${tier.name}: no row count for ${t}`);
        return v;
      };

      // ---- dim_region
      const regions = pickRegions(n("dim_region"));
      const regionCat = new Categorical(regions, regions.map((r) => r.weight));
      P.set("dim_region", () => regions.map((r) => ({
        regionId: r.regionId, regionCode: r.ref.code, regionName: r.ref.name, regionGroup: r.ref.group,
        countryName: r.ref.country, countryCode: r.ref.iso2, populationWeight: r.weight,
      })));

      // ---- dim_product
      const products: Product[] = [];
      {
        const d = S("dim_product");
        const nProducts = n("dim_product");
        const catCounts = allocate(nProducts, CATEGORIES.map(() => 1), 1);
        const used = new Set<string>();
        let id = 1;
        CATEGORIES.forEach((cat, ci) => {
          for (let k = 0; k < (catCounts[ci] as number); k++) {
            const [sub, noun] = cat.sub[k % cat.sub.length] as [string, string];
            let name = "";
            for (let tries = 0; ; tries++) {
              const series = d.pick(SERIES);
              const variant = tries < 3 ? d.pick(VARIANTS.slice(0, 1 + Math.min(VARIANTS.length - 1, Math.floor(nProducts / 150)))) : d.pick(VARIANTS);
              name = [series, noun, variant].filter((x) => x !== "").join(" ");
              if (!used.has(name.toLowerCase())) break;
              if (tries > 200) { name = `${name} ${id}`; break; }
            }
            used.add(name.toLowerCase());
            const band = new Categorical([0, 1, 2, 3], BAND_WEIGHTS).sample(d);
            const [blo, bhi] = bandEdges(cat, band);
            // log-uniform within the inner 90% of the band
            const x = Math.exp(Math.log(blo) + (Math.log(bhi) - Math.log(blo)) * d.uniform(0.05, 0.95));
            const listPrice = pricePoint(x, blo, bhi);
            const unitCost = round(Math.min(listPrice * 0.95, listPrice * cat.costRatio * d.uniform(0.9, 1.1)), 2);
            const popularity = d.lognormal(1, 0.9); // a heavy right tail: a few best-sellers
            const productId = id++;
            products.push({
              productId, cat, sub, band, listPrice, unitCost, popularity,
              row: {
                productId, sku: `SKU-${String(10000 + productId * 7 % 90000).padStart(5, "0")}`,
                productName: name, category: cat.category, subCategory: sub,
                priceBand: PRICE_BANDS[band] as string, listPrice, unitCost,
              },
            });
          }
        });
      }
      P.set("dim_product", () => products.map((p) => p.row));
      // one product mix per calendar month: popularity x the category's season
      const productMix = Array.from({ length: 12 }, (_, m) =>
        new Categorical(products, products.map((p) => p.popularity * (SEASON[p.cat.season]![m] as number))));

      // ---- dim_channel
      const channels: Channel[] = CHANNELS.slice(0, n("dim_channel")).map((ref, i) => ({ channelId: i + 1, ref }));
      if (channels.length === 0) throw new Error("no channels");
      P.set("dim_channel", () => channels.map((c) => ({ channelId: c.channelId, channelName: c.ref.name, isDirect: c.ref.isDirect })));
      const channelMix: Record<string, Categorical<Channel>> = {};
      for (const t of TIERS_CUST) channelMix[t] = new Categorical(channels, channels.map((_, i) => (CHANNEL_MIX[t]![i] as number) + 1e-9));

      // ---- dim_rep: at least one per region, the rest by sqrt(weight) (small markets are staffed thinly)
      const reps: Rep[] = [];
      const repsByRegion = new Map<number, Rep[]>();
      {
        const d = S("dim_rep");
        const perRegion = allocate(n("dim_rep"), regions.map((r) => Math.sqrt(r.weight)), 1);
        const lastHire = Math.min(tier.from, dayOf(2025, 12, 31));
        const firstHire = dayOf(2015, 1, 1);
        let id = 1;
        regions.forEach((r, ri) => {
          const list: Rep[] = [];
          for (let k = 0; k < (perRegion[ri] as number); k++) {
            const repId = id++;
            const f = seeded(seed, `sales/dim_rep/name/${repId}`, r.ref.locale);
            const repName = f.person.fullName();
            const team = k === 0 || d.bernoulli(0.6) ? "Field" : d.bernoulli(0.5) ? "Inside" : "Key Accounts";
            // tenure: exponential-ish, recent hires more common (attrition)
            const hire = Math.max(firstHire, lastHire - Math.floor(-Math.log(1 - d.g.nextFloat()) * 1400));
            const tenureYears = (tier.from - hire) / 365;
            // score rises with tenure, noisy; NULL for a new hire (< 180 days) or not yet reviewed (4%)
            const score = Math.round(Math.min(100, Math.max(0, d.normal(55 + 4 * Math.min(tenureYears, 6), 12))));
            const repScore = tier.from - hire < 180 || d.bernoulli(0.04) ? null : score;
            const rep: Rep = { repId, regionId: r.regionId, row: { repId, repName, regionId: r.regionId, repTeam: `${r.ref.name} ${team}`, hireDate: iso(hire), repScore } };
            list.push(rep); reps.push(rep);
          }
          repsByRegion.set(r.regionId, list);
        });
      }
      P.set("dim_rep", () => reps.map((r) => r.row));

      // ---- dim_customer: by region weight, at least 2 per region; tier mix gold/silver/bronze 10/30/60
      const customers: Customer[] = [];
      const custByRegion = new Map<number, Customer[]>();
      {
        const d = S("dim_customer");
        const perRegion = allocate(n("dim_customer"), regions.map((r) => r.weight), 2);
        const tierCat = new Categorical([...TIERS_CUST], TIER_WEIGHTS);
        const earliest = dayOf(2018, 1, 1);
        const used = new Set<string>();
        let id = 1;
        regions.forEach((r, ri) => {
          const list: Customer[] = [];
          const regionReps = repsByRegion.get(r.regionId)!;
          for (let k = 0; k < (perRegion[ri] as number); k++) {
            const customerId = id++;
            let name = "";
            for (let tries = 0; tries < 6; tries++) {
              const f = seeded(seed, `sales/dim_customer/name/${customerId}/${tries}`, r.ref.locale);
              name = f.company.name();
              if (!used.has(name.toLowerCase())) break;
            }
            if (used.has(name.toLowerCase())) name = `${name} (${customerId})`;
            used.add(name.toLowerCase());
            const tier_ = tierCat.sample(d);
            // 80% signed up before the tier range; 20% are acquired during it (never ordering before signup).
            // The first two customers of every region are long-standing, so every day has an eligible customer.
            const signup = k < 2 || d.bernoulli(0.8)
              ? earliest + d.int(0, tier.from - 1 - earliest)
              : tier.from + d.int(0, Math.max(0, tier.to - tier.from - 30));
            const rep = regionReps[d.int(0, regionReps.length - 1)] as Rep;
            const weight = (TIER_FREQ[tier_] as number) * d.lognormal(1, 0.6);
            const c: Customer = { customerId, regionId: r.regionId, tier: tier_, signup, repId: rep.repId, weight,
              row: { customerId, customerName: name, customerTier: tier_, regionId: r.regionId, signupDate: iso(signup) } };
            list.push(c); customers.push(c);
          }
          custByRegion.set(r.regionId, list);
        });
      }
      P.set("dim_customer", () => customers.map((c) => c.row));
      const custCat = new Map<number, Categorical<Customer>>();
      for (const [rid, list] of custByRegion) custCat.set(rid, new Categorical(list, list.map((c) => c.weight)));

      // ---- dim_date: every day of the tier range
      const WEEKDAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
      P.set("dim_date", function* () {
        for (let day = tier.from; day <= tier.to; day++) {
          const { y, m, dow } = parts(day);
          const q = Math.floor((m - 1) / 3) + 1;
          yield { day: iso(day), yearNo: y, quarterNo: q, monthNo: m, monthName: `${y}-${String(m).padStart(2, "0")}`,
            quarterName: `${y}-Q${q}`, weekdayNo: dow + 1, weekdayName: WEEKDAY_NAMES[dow] as string };
        }
      });

      // ---- fact_order_line
      const state: SalesState = { regions, products, regionQuarter: new Map(), factLines: 0 };
      dom.lastState = state;
      P.set("fact_order_line", function* () {
        const dDay = S("fact/day-shape");
        const dOrd = S("fact/order");
        const dLine = S("fact/line");
        // daily weights: weekday x month x quarter-end x holiday x trend x noise
        const days: Day[] = [];
        const w: number[] = [];
        for (let day = tier.from; day <= tier.to; day++) {
          const { m, d, dow } = parts(day);
          const qEnd = (m % 3 === 0) && d > (m === 3 || m === 12 ? 21 : 20);
          const holiday = (m === 1 && d === 1) || (m === 12 && (d >= 24 && d <= 26 || d === 31));
          const trend = Math.pow(1 + ANNUAL_GROWTH, (day - tier.from) / 365.25);
          days.push(day);
          w.push((WEEKDAY[dow] as number) * (MONTH[m - 1] as number) * (qEnd ? QUARTER_END_PUSH : 1) * (holiday ? HOLIDAY : 1) * trend * dDay.lognormal(1, DAY_NOISE_SIGMA));
        }
        const linesPerDay = allocate(tier.factRows, w, 0);
        let orderId = 0;
        // Each day gets its allocated line budget; an order that overruns it
        // borrows from the next day (the budget carries), so order sizes are
        // never cut by the day, and only the very last order of the range can
        // be shortened to land on exactly factRows lines.
        let budget = 0, left = tier.factRows;
        for (let di = 0; di < days.length; di++) {
          const day = days[di] as Day;
          const { y, m } = parts(day);
          const q = Math.floor((m - 1) / 3) + 1;
          const iday = iso(day);
          const mix = productMix[m - 1] as Categorical<Product>;
          budget += linesPerDay[di] as number;
          const lastDay = di === days.length - 1;
          while (left > 0 && (budget > 0 || lastDay)) {
            orderId++;
            const region = regionCat.sample(dOrd);
            let cust: Customer | undefined;
            for (let t = 0; t < 8 && !cust; t++) {
              const c = custCat.get(region.regionId)!.sample(dOrd);
              if (c.signup <= day) cust = c;
            }
            if (!cust) cust = custByRegion.get(region.regionId)!.find((c) => c.signup <= day) ?? custByRegion.get(region.regionId)![0]!;
            const channel = channelMix[cust.tier]!.sample(dOrd);
            const size = Math.min(left, MAX_LINES, products.length, 1 + dOrd.poisson(TIER_EXTRA_LINES[cust.tier] as number));
            const promo = dOrd.bernoulli(channel.ref.promoRate);
            const campaigns = CAMPAIGNS[String(q)] as string[];
            const promoCode = promo ? `${dOrd.pick(campaigns)}${String(y % 100).padStart(2, "0")}` : null;
            const promoPct = promo ? new Categorical([0.05, 0.1, 0.15], [0.5, 0.35, 0.15]).sample(dOrd) : 0;
            const negotiated = dOrd.bernoulli(channel.ref.discountRate);
            const seen = new Set<number>();
            for (let lineNo = 1; lineNo <= size; lineNo++) {
              let p = mix.sample(dLine);
              for (let t = 0; t < 20 && seen.has(p.productId); t++) p = mix.sample(dLine);
              if (seen.has(p.productId)) p = products.find((x) => !seen.has(x.productId))!;
              seen.add(p.productId);
              const [blo, bhi] = bandEdges(p.cat, p.band);
              const unitPrice = round(Math.min(bhi, Math.max(blo,
                p.listPrice * (1 + dLine.truncNormal(0, PRICE_SPREAD, -PRICE_SPREAD_CAP, PRICE_SPREAD_CAP)))), 2);
              const cap = Math.max(1, Math.min(MAX_QTY, Math.floor(MAX_LINE / unitPrice)));
              const quantity = Math.max(1, Math.min(cap, Math.round(dLine.lognormal(p.cat.qtyMedian * (TIER_QTY[cust.tier] as number), p.cat.qtySigma))));
              let disc = promoPct;
              if (negotiated) disc += Math.round(dLine.uniform(0.02, channel.ref.discountMax) / 0.005) * 0.005;
              if (quantity >= 20) disc += 0.02;
              const discountPct = round(Math.min(MAX_DISCOUNT, disc), 3);
              const lineAmount = round(quantity * unitPrice * (1 - discountPct), 2);
              const key = `${region.regionId}/${y}/${q}`;
              state.regionQuarter.set(key, (state.regionQuarter.get(key) ?? 0) + lineAmount);
              state.factLines++;
              yield {
                orderId, lineNo, orderDate: iday, regionId: region.regionId, customerId: cust.customerId,
                productId: p.productId, repId: cust.repId, channelId: channel.channelId,
                quantity, unitPrice, discountPct, lineAmount,
                promoCode: discountPct > 0 ? promoCode : null,
              };
            }
            budget -= size; left -= size;
          }
        }
      });

      // ---- fact_target: every region x quarter of the range, derived from that quarter's actuals
      const quarters: [number, number][] = [];
      for (let day = tier.from; day <= tier.to; day++) {
        const { y, m, d } = parts(day);
        if (d === 1 && (m - 1) % 3 === 0) quarters.push([y, Math.floor((m - 1) / 3) + 1]);
      }
      P.set("fact_target", () => {
        const d = S("fact_target");
        const out: Row[] = [];
        for (const r of regions) {
          const actuals = quarters.map(([y, q]) => state.regionQuarter.get(`${r.regionId}/${y}/${q}`) ?? 0);
          const mean = actuals.reduce((a, b) => a + b, 0) / Math.max(1, actuals.length);
          quarters.forEach(([y, q], i) => {
            const base = (actuals[i] as number) > 0 ? (actuals[i] as number) : Math.max(mean, 1000);
            // a plan is a round number: to the nearest 100 (nearest 10 under 10 000)
            const raw = base * d.uniform(0.9, 1.2);
            const step = raw < 10000 ? 10 : 100;
            out.push({ regionId: r.regionId, yearNo: y, quarterNo: q, targetAmount: round(Math.round(raw / step) * step, 2) });
          });
        }
        return out;
      });

      // ---- sales_report: per region group, the last full quarter in thousands and its change on the one before
      P.set("sales_report", () => {
        const last = quarters[quarters.length - 1]!, prev = quarters[quarters.length - 2] ?? last;
        return GROUPS.map((g) => {
          const sum = ([y, q]: [number, number]) => regions.filter((r) => r.ref.group === g)
            .reduce((a, r) => a + (state.regionQuarter.get(`${r.regionId}/${y}/${q}`) ?? 0), 0);
          const a = sum(last), b = sum(prev);
          return { srRegion: g, srSales: round(a / 1000, 2), srDelta: b > 0 ? round((a - b) / b, 3) : 0 };
        });
      });
      return P;
    },
  };
  return dom;
}
