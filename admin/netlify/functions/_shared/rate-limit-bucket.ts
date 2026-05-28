// Slice A2 phase 3b — in-memory token-bucket rate limiter for `/device-token`.
//
// Scope: per-function-instance only. Netlify warm instances are sticky
// enough that this catches single-source bursts (e.g. a buggy client
// retry loop, a scripted attacker on a single IP). It does NOT protect
// against a distributed botnet — that requires Upstash/Redis or
// Cloudflare WAF. Acceptable for the pilot's traffic envelope; revisit
// when we cross ~1k req/min/instance.
//
// Bucket key = `${remoteIp}::${deviceInstallId}`. Two different devices
// behind the same IP share neither bucket; one device hammering from
// rotating IPs gets one bucket per IP it shows up on (so rotation costs
// the attacker the full burst budget each hop, not nothing).
//
// Env:
//   MEDRASH_DEVICE_TOKEN_RATE_BURST       — max tokens in the bucket (default 5)
//   MEDRASH_DEVICE_TOKEN_RATE_REFILL_PER_MIN — tokens added per minute (default 10)
//   MEDRASH_DEVICE_TOKEN_RATE_DISABLED    — when "true"/"1", bypass entirely (smoke tests)

export type RateLimitResult = {
  allowed: boolean;
  retryAfterSeconds: number;
  remaining: number;
};

type Bucket = {
  tokens: number;
  lastRefillMs: number;
};

const BUCKETS = new Map<string, Bucket>();
const MAX_BUCKETS = 5000; // prevent unbounded growth from rotating keys

function readConfig(): { burst: number; refillPerMs: number; disabled: boolean } {
  const burstRaw = process.env.MEDRASH_DEVICE_TOKEN_RATE_BURST?.trim();
  const refillRaw =
    process.env.MEDRASH_DEVICE_TOKEN_RATE_REFILL_PER_MIN?.trim();
  const disabledRaw =
    process.env.MEDRASH_DEVICE_TOKEN_RATE_DISABLED?.trim().toLowerCase();
  const disabled = disabledRaw === "true" || disabledRaw === "1";
  const burst = Number.isFinite(Number(burstRaw)) && Number(burstRaw) > 0
    ? Number(burstRaw)
    : 5;
  const refillPerMin = Number.isFinite(Number(refillRaw)) && Number(refillRaw) > 0
    ? Number(refillRaw)
    : 10;
  return { burst, refillPerMs: refillPerMin / 60_000, disabled };
}

export type ConsumeOptions = {
  /** Override now (ms since epoch) for tests. Defaults to `Date.now()`. */
  nowMs?: number;
};

export function consume(
  key: string,
  options: ConsumeOptions = {},
): RateLimitResult {
  const { burst, refillPerMs, disabled } = readConfig();
  if (disabled) {
    return { allowed: true, retryAfterSeconds: 0, remaining: burst };
  }

  const now = options.nowMs ?? Date.now();
  let bucket = BUCKETS.get(key);
  if (!bucket) {
    if (BUCKETS.size >= MAX_BUCKETS) {
      // Evict the oldest bucket. Simplest cap: clear all when full.
      // Pilot scale never hits this; defense in depth.
      BUCKETS.clear();
    }
    bucket = { tokens: burst, lastRefillMs: now };
    BUCKETS.set(key, bucket);
  } else {
    const elapsedMs = Math.max(0, now - bucket.lastRefillMs);
    const refill = elapsedMs * refillPerMs;
    bucket.tokens = Math.min(burst, bucket.tokens + refill);
    bucket.lastRefillMs = now;
  }

  if (bucket.tokens >= 1) {
    bucket.tokens -= 1;
    return {
      allowed: true,
      retryAfterSeconds: 0,
      remaining: Math.floor(bucket.tokens),
    };
  }

  const shortfall = 1 - bucket.tokens;
  const waitMs = refillPerMs > 0 ? shortfall / refillPerMs : 60_000;
  return {
    allowed: false,
    retryAfterSeconds: Math.max(1, Math.ceil(waitMs / 1000)),
    remaining: 0,
  };
}

/** Test-only — clears the per-process bucket map. */
export function __resetBucketsForTests(): void {
  BUCKETS.clear();
}
