#!/usr/bin/env bash
# Netlify build script for the MedRash participant Flutter Web app.
#
# Netlify's default Linux build image does NOT ship Flutter, so this script
# downloads the SDK into the build cache the first time, then runs
# `flutter build web` with all required --dart-define flags wired from
# Netlify environment variables. Subsequent builds reuse the cached SDK.

set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.38.9}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_HOME="${NETLIFY_CACHE_DIR:-$HOME/.netlify-cache}/flutter-${FLUTTER_CHANNEL}-${FLUTTER_VERSION}"

echo "[build-web] Target: Flutter ${FLUTTER_VERSION} (${FLUTTER_CHANNEL})"
echo "[build-web] Cache dir: ${FLUTTER_HOME}"

if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
  echo "[build-web] Cache miss — downloading Flutter SDK..."
  mkdir -p "${FLUTTER_HOME}"
  ARCHIVE="/tmp/flutter_${FLUTTER_VERSION}.tar.xz"
  URL="https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_CHANNEL}/linux/flutter_linux_${FLUTTER_VERSION}-${FLUTTER_CHANNEL}.tar.xz"
  curl -fL --retry 3 -o "${ARCHIVE}" "${URL}"
  tar -xJf "${ARCHIVE}" -C "${FLUTTER_HOME}" --strip-components=1
  rm -f "${ARCHIVE}"
  echo "[build-web] Flutter SDK installed."
else
  echo "[build-web] Cache hit — reusing Flutter SDK."
fi

export PATH="${FLUTTER_HOME}/bin:${PATH}"

flutter --version
flutter config --no-analytics --no-cli-animations >/dev/null
flutter pub get

# Required env vars from Netlify UI. Failing loudly here beats producing
# a build that silently points at localhost.
: "${MEDRASH_FUNCTIONS_BASE_URL:?Set MEDRASH_FUNCTIONS_BASE_URL on the Netlify site (must end with a trailing slash, e.g. https://thriving-gingersnap-2f2932.netlify.app/.netlify/functions/)}"
: "${MEDRASH_TURNSTILE_SITE_KEY:?Set MEDRASH_TURNSTILE_SITE_KEY on the Netlify site (Cloudflare Turnstile site key for the invisible widget; required for /device-token bootstrap)}"

echo "[build-web] Functions base URL: ${MEDRASH_FUNCTIONS_BASE_URL}"
echo "[build-web] Turnstile site key length: ${#MEDRASH_TURNSTILE_SITE_KEY}"

# Slice B7 — telemetry env vars are optional. When SENTRY_DSN is empty the
# SDK skips init and the build still ships clean. Release defaults to the
# Netlify commit ref so each deploy lands as a distinct release in Sentry.
SENTRY_DSN="${SENTRY_DSN:-}"
SENTRY_RELEASE="${SENTRY_RELEASE:-${COMMIT_REF:-}}"
SENTRY_ENVIRONMENT="${SENTRY_ENVIRONMENT:-${CONTEXT:-production}}"
if [ -n "${SENTRY_DSN}" ]; then
  echo "[build-web] Sentry enabled (release=${SENTRY_RELEASE:-unset}, env=${SENTRY_ENVIRONMENT})"
else
  echo "[build-web] Sentry disabled (no SENTRY_DSN set)"
fi

# P7 — Navii avatars. Feature flag defaults to ON for deployed builds
# (every avatar surface short-circuits to a monogram when this is false,
# which is what produced the "no mascot" regression in prod). Override in
# the Netlify UI by setting MEDRASH_ENABLE_NAVII_AVATARS=false to roll
# back without a redeploy. MEDRASH_NAVII_VERSION participates in the
# avatar URL cache key (HttpNaviiSvgLoader appends &v=<version>); bump it
# whenever @usenavii/core is upgraded so devices fetch fresh SVGs.
MEDRASH_ENABLE_NAVII_AVATARS="${MEDRASH_ENABLE_NAVII_AVATARS:-true}"
MEDRASH_NAVII_VERSION="${MEDRASH_NAVII_VERSION:-0.7.0}"
echo "[build-web] Navii avatars: ${MEDRASH_ENABLE_NAVII_AVATARS} (version=${MEDRASH_NAVII_VERSION})"

flutter build web --release \
  --base-href=/ \
  --dart-define=MEDRASH_FUNCTIONS_BASE_URL="${MEDRASH_FUNCTIONS_BASE_URL}" \
  --dart-define=MEDRASH_TURNSTILE_SITE_KEY="${MEDRASH_TURNSTILE_SITE_KEY}" \
  --dart-define=MEDRASH_ENABLE_NAVII_AVATARS="${MEDRASH_ENABLE_NAVII_AVATARS}" \
  --dart-define=MEDRASH_NAVII_VERSION="${MEDRASH_NAVII_VERSION}" \
  --dart-define=SENTRY_DSN="${SENTRY_DSN}" \
  --dart-define=SENTRY_RELEASE="${SENTRY_RELEASE}" \
  --dart-define=SENTRY_ENVIRONMENT="${SENTRY_ENVIRONMENT}"

echo "[build-web] Web build complete → app/build/web/"
