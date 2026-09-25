// PCG32 (PCG-XSH-RR 64/32), M. E. O'Neill, "PCG: A Family of Simple Fast
// Space-Efficient Statistically Good Algorithms for Random Number Generation"
// (2014), https://www.pcg-random.org/ -- the `pcg32_random_r` /
// `pcg32_srandom_r` pair of the minimal C implementation, re-implemented here
// with the 64-bit state held as two unsigned 32-bit halves so that no BigInt
// is on the hot path.  Integer-only: the stream of 32-bit outputs is the same
// on every platform and every node version.
//
// Test vector (the reference `pcg32-demo`, seeded with initstate = 42,
// initseq = 54): 0xa15c02b7 0x7b47f409 0xba1d3330 0x83d2f293 0xbfa4784b
// 0xcbed606e -- pinned in test/pcg32.test.ts, and cross-checked there against
// a BigInt transcription of the C code.

// multiplier 6364136223846793005 = 0x5851F42D_4C957F2D
const MUL_HI = 0x5851f42d;
const MUL_LO = 0x4c957f2d;

/** The full 64-bit product of two unsigned 32-bit numbers, as [hi, lo]. */
function mul32(a: number, b: number): [number, number] {
  const a0 = a & 0xffff, a1 = a >>> 16, b0 = b & 0xffff, b1 = b >>> 16;
  const p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
  const mid = (p00 >>> 16) + (p01 & 0xffff) + (p10 & 0xffff);
  const lo = (((mid & 0xffff) << 16) | (p00 & 0xffff)) >>> 0;
  const hi = (p11 + (p01 >>> 16) + (p10 >>> 16) + Math.floor(mid / 65536)) >>> 0;
  return [hi, lo];
}

export class Pcg32 {
  private sh = 0; private sl = 0; // state
  private ih = 0; private il = 1; // increment (always odd)

  /** `pcg32_srandom_r(initstate, initseq)`; both are 64-bit values. */
  constructor(initstate: bigint, initseq: bigint) {
    const M = (1n << 64n) - 1n;
    const inc = ((initseq & M) << 1n | 1n) & M;
    this.ih = Number(inc >> 32n) >>> 0;
    this.il = Number(inc & 0xffffffffn) >>> 0;
    this.sh = 0; this.sl = 0;
    this.step();
    const s = initstate & M;
    const add = (Number(s >> 32n) >>> 0);
    const addl = (Number(s & 0xffffffffn) >>> 0);
    const lo = (this.sl + addl) >>> 0;
    const carry = lo < this.sl ? 1 : 0;
    this.sh = (this.sh + add + carry) >>> 0;
    this.sl = lo;
    this.step();
  }

  private step(): void {
    const [ph, pl] = mul32(this.sl, MUL_LO);
    const hi = (ph + Math.imul(this.sh, MUL_LO) + Math.imul(this.sl, MUL_HI)) >>> 0;
    const lo = (pl + this.il) >>> 0;
    const carry = lo < pl ? 1 : 0;
    this.sh = (hi + this.ih + carry) >>> 0;
    this.sl = lo;
  }

  /** The next uniformly distributed unsigned 32-bit integer. */
  nextU32(): number {
    const h = this.sh, l = this.sl;
    this.step();
    const xh = (h ^ (h >>> 18)) >>> 0;
    const xl = (l ^ ((l >>> 18) | (h << 14))) >>> 0;
    const xs = ((xl >>> 27) | (xh << 5)) >>> 0;
    const rot = h >>> 27;
    return ((xs >>> rot) | (xs << ((32 - rot) & 31))) >>> 0;
  }

  /** `pcg32_boundedrand_r`: uniform in [0, bound), no modulo bias. */
  bounded(bound: number): number {
    if (!(bound >= 1 && bound <= 0x100000000 && Number.isInteger(bound))) {
      throw new RangeError(`bounded: bad bound ${bound}`);
    }
    if (bound === 0x100000000) return this.nextU32();
    const threshold = (0x100000000 - bound) % bound;
    for (;;) {
      const r = this.nextU32();
      if (r >= threshold) return r % bound;
    }
  }

  /** A double in [0, 1) with 53 random bits (two outputs). */
  nextFloat(): number {
    const a = this.nextU32() >>> 5, b = this.nextU32() >>> 6;
    return (a * 67108864 + b) / 9007199254740992;
  }
}

/** FNV-1a, 64-bit, over the UTF-8 bytes of `s`: names a PCG stream. */
export function fnv1a64(s: string): bigint {
  let h = 0xcbf29ce484222325n;
  for (const byte of Buffer.from(s, "utf8")) {
    h ^= BigInt(byte);
    h = (h * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return h;
}

/**
 * A named, independent stream: PCG32 seeded with the run's seed and a stream
 * selector hashed from `label` (e.g. "sales/fact_order_line/quantity").  Two
 * labels never share draws, so adding a column or a table never shifts the
 * values of another.
 */
export function stream(seed: number | bigint, label: string): Pcg32 {
  return new Pcg32(BigInt(seed), fnv1a64(label));
}
