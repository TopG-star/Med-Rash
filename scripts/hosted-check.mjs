#!/usr/bin/env node

const requiredTables = [
  'quizzes',
  'questions',
  'attempts',
  'answers',
  'sessions',
  'users',
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

  console.log('[hosted-check] Hosted Supabase smoke checks passed.');
}

run().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`[hosted-check] FAILED: ${message}`);
  process.exit(1);
});
