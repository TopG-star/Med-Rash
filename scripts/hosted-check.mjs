#!/usr/bin/env node

const requiredTables = [
  'quizzes',
  'questions',
  'attempts',
  'answers',
  'sessions',
  'users',
  'session_join_events',
];

function readEnv(name) {
  const value = process.env[name];
  return typeof value === 'string' ? value.trim() : '';
}

function ensureEnv(name) {
  const value = readEnv(name);
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

async function fetchWithTimeout(url, options, timeoutMs = 15000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...options,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function readErrorSnippet(response) {
  try {
    const text = await response.text();
    const trimmed = text.trim();
    if (!trimmed) {
      return 'empty error body';
    }
    return trimmed.slice(0, 280);
  } catch {
    return 'unable to read error body';
  }
}

async function runParticipantDeepLinkChecks() {
  // Optional smokes. Skip cleanly when the env var isn't set so the
  // existing Supabase-only invocation still works unchanged.
  const appBase = readEnv('MEDRASH_APP_PUBLIC_BASE_URL').replace(/\/+$/, '');
  const functionsBase = readEnv('MEDRASH_FUNCTIONS_BASE_URL').replace(/\/+$/, '');

  if (!appBase) {
    console.log(
      '[hosted-check] SKIP participant deep-link check (MEDRASH_APP_PUBLIC_BASE_URL not set).',
    );
  } else {
    // The participant app is a Flutter SPA. The Netlify rewrite
    // `/* -> /index.html (200)` is the single most failure-prone piece
    // of the deep-link contract: when it regresses, a cold visit to
    // `/session/<code>` 404s before Flutter ever boots and users
    // assume the QR is broken. Prove the shell is actually served at
    // both `/` and a representative deep path.
    const probes = [
      { label: 'root', url: `${appBase}/` },
      { label: 'deep-link /session/SMOKE', url: `${appBase}/session/SMOKE` },
    ];
    for (const probe of probes) {
      const response = await fetchWithTimeout(probe.url, {
        method: 'GET',
        headers: { Accept: 'text/html' },
      });
      if (!response.ok) {
        const snippet = await readErrorSnippet(response);
        throw new Error(
          `Participant ${probe.label} probe failed (${response.status} ${response.statusText}): ${snippet}`,
        );
      }
      const body = await response.text();
      if (!body.includes('flutter_bootstrap.js')) {
        throw new Error(
          `Participant ${probe.label} probe at ${probe.url} returned 200 but body did not contain 'flutter_bootstrap.js' (SPA fallback or wrong site?). First 280 chars: ${body.trim().slice(0, 280)}`,
        );
      }
      console.log(`[hosted-check] Participant ${probe.label} probe passed.`);
    }
  }

  if (!functionsBase) {
    console.log(
      '[hosted-check] SKIP functions health check (MEDRASH_FUNCTIONS_BASE_URL not set).',
    );
    return;
  }
  const healthUrl = `${functionsBase}/health`;
  // redirect: 'manual' so a stray middleware redirect (e.g. Next.js
  // matcher accidentally claiming /.netlify/functions/*) surfaces as a
  // 3xx with Location pointing at /login instead of silently following
  // through to an HTML page that masquerades as a 200 success.
  const healthResponse = await fetchWithTimeout(healthUrl, {
    method: 'GET',
    redirect: 'manual',
  });
  if (healthResponse.status >= 300 && healthResponse.status < 400) {
    const location = healthResponse.headers.get('location') ?? '(none)';
    throw new Error(
      `Functions health check at ${healthUrl} returned ${healthResponse.status} redirect to '${location}'. ` +
        `This usually means the admin Next.js middleware matcher is intercepting /.netlify/functions/* before Netlify can dispatch the function. ` +
        `Confirm admin/src/middleware.ts excludes \\\\.netlify/ from its matcher.`,
    );
  }
  if (!healthResponse.ok) {
    const snippet = await readErrorSnippet(healthResponse);
    throw new Error(
      `Functions health check failed at ${healthUrl} (${healthResponse.status} ${healthResponse.statusText}): ${snippet}`,
    );
  }
  const healthBody = await healthResponse.text();
  if (!healthBody.includes('"status":"ok"')) {
    throw new Error(
      `Functions health check at ${healthUrl} returned 200 but body did not contain '"status":"ok"'. First 280 chars: ${healthBody.trim().slice(0, 280)}`,
    );
  }
  console.log(`[hosted-check] Functions health check passed (${healthUrl}).`);
}

async function run() {
  const supabaseUrl = ensureEnv('SUPABASE_URL').replace(/\/+$/, '');
  const serviceRoleKey = ensureEnv('SUPABASE_SERVICE_ROLE_KEY');
  const restBase = `${supabaseUrl}/rest/v1`;

  const headers = {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    'Accept-Profile': 'app',
    'Content-Profile': 'app',
  };

  console.log('[hosted-check] Running connectivity check against app schema...');

  const connectivityUrl = `${restBase}/users?select=id&limit=1`;
  const connectivityResponse = await fetchWithTimeout(connectivityUrl, {
    method: 'GET',
    headers: {
      ...headers,
      Prefer: 'count=exact',
    },
  });

  if (!connectivityResponse.ok) {
    const snippet = await readErrorSnippet(connectivityResponse);
    throw new Error(
      `Connectivity check failed (${connectivityResponse.status} ${connectivityResponse.statusText}): ${snippet}`,
    );
  }

  const contentRange = connectivityResponse.headers.get('content-range') ?? 'unknown';
  console.log(`[hosted-check] Connectivity check passed (content-range: ${contentRange}).`);

  console.log('[hosted-check] Verifying required table presence...');
  for (const table of requiredTables) {
    const tableUrl = `${restBase}/${table}?select=id&limit=1`;
    const response = await fetchWithTimeout(tableUrl, {
      method: 'GET',
      headers,
    });

    if (!response.ok) {
      const snippet = await readErrorSnippet(response);
      throw new Error(
        `Schema check failed for table '${table}' (${response.status} ${response.statusText}): ${snippet}`,
      );
    }

    console.log(`[hosted-check] Table '${table}' reachable.`);
  }

  await runParticipantDeepLinkChecks();

  console.log('[hosted-check] Hosted Supabase smoke checks passed.');
}

run().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`[hosted-check] FAILED: ${message}`);
  process.exit(1);
});
