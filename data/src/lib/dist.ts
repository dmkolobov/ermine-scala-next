// Distribution helpers over a Pcg32 stream.  Every helper consumes a FIXED
// number of 32-bit draws for a given call (rejection loops aside), so a
// stream's sequence is a pure function of the calls made on it.
//
// Floating point: sqrt is IEEE-exact; log/exp/cos are V8's fdlibm port
// (ieee754::log etc.), identical on every platform V8 runs on.  Values that
// reach a CSV are rounded (money to cents, rates to 4 dp), which also absorbs
// any last-ulp difference.

import { Pcg32 } from "./pcg32.js";

export class Dist {
  constructor(readonly g: Pcg32) {}

  /** Uniform double in [lo, hi). */
  uniform(lo: number, hi: number): number { return lo + (hi - lo) * this.g.nextFloat(); }

  /** Uniform integer in [lo, hi] (inclusive). */
  int(lo: number, hi: number): number { return lo + this.g.bounded(hi - lo + 1); }

  /** True with probability p. */
  bernoulli(p: number): boolean { return this.g.nextFloat() < p; }

  /** Standard normal by Box-Muller (the cosine half; the sine half is dropped). */
  stdNormal(): number {
    const u1 = 1 - this.g.nextFloat(); // (0, 1]
    const u2 = this.g.nextFloat();
    return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  }

  normal(mean: number, sd: number): number { return mean + sd * this.stdNormal(); }

  /** Normal truncated to [lo, hi] by rejection (lo < mean < hi assumed). */
  truncNormal(mean: number, sd: number, lo: number, hi: number): number {
    for (let i = 0; i < 64; i++) {
      const x = this.normal(mean, sd);
      if (x >= lo && x <= hi) return x;
    }
    return Math.min(hi, Math.max(lo, mean));
  }

  /** Log-normal parameterised by its MEDIAN and the sd of the underlying normal. */
  lognormal(median: number, sigma: number): number { return median * Math.exp(sigma * this.stdNormal()); }

  /** Poisson (Knuth for small means, a rounded normal above 30). */
  poisson(mean: number): number {
    if (mean <= 0) return 0;
    if (mean > 30) return Math.max(0, Math.round(this.normal(mean, Math.sqrt(mean))));
    const L = Math.exp(-mean);
    let k = 0, p = 1;
    for (;;) { p *= this.g.nextFloat(); if (p <= L) return k; k++; }
  }

  /** Pick one element uniformly. */
  pick<T>(xs: readonly T[]): T {
    if (xs.length === 0) throw new Error("pick: empty");
    return xs[this.g.bounded(xs.length)] as T;
  }
}

/** Weighted categorical sampling by cumulative weights and binary search. */
export class Categorical<T> {
  private readonly cum: number[] = [];
  readonly total: number;
  constructor(readonly items: readonly T[], weights: readonly number[]) {
    if (items.length !== weights.length || items.length === 0) throw new Error("Categorical: bad lengths");
    let acc = 0;
    for (const w of weights) {
      if (!(w >= 0) || !Number.isFinite(w)) throw new Error(`Categorical: bad weight ${w}`);
      acc += w; this.cum.push(acc);
    }
    if (acc <= 0) throw new Error("Categorical: zero total weight");
    this.total = acc;
  }
  sample(d: Dist): T {
    const x = d.g.nextFloat() * this.total;
    let lo = 0, hi = this.cum.length - 1;
    while (lo < hi) { const mid = (lo + hi) >>> 1; if (x < (this.cum[mid] as number)) hi = mid; else lo = mid + 1; }
    return this.items[lo] as T;
  }
  /** The configured probability of item i. */
  p(i: number): number { return ((this.cum[i] as number) - (i === 0 ? 0 : (this.cum[i - 1] as number))) / this.total; }
}

/** Zipf-like weights 1/(k+1)^s for k = 0..n-1 (product popularity). */
export function zipfWeights(n: number, s: number): number[] {
  return Array.from({ length: n }, (_, k) => 1 / Math.pow(k + 1, s));
}

/** Round half away from zero to `dp` decimals, exact on the decimal string. */
export function round(x: number, dp: number): number {
  const f = Math.pow(10, dp);
  const r = Math.round(Math.abs(x) * f + 1e-9) / f;
  return x < 0 ? -r : r;
}
