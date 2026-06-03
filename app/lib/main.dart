import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/config/app_config.dart';
import 'core/di/init_core.dart';
import 'core/observability/sentry_scrubber.dart';
import 'core/ui/arena_app.dart';

// Slice B7 — telemetry env vars are baked in at build time via
// --dart-define=SENTRY_DSN=... (see app/scripts/build-web.sh). When the DSN
// is empty the SDK is skipped entirely so dev builds and PR previews stay
// off the wire.
const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const String _sentryRelease = String.fromEnvironment('SENTRY_RELEASE');
const String _sentryEnv =
    String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: 'development');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // P0.3 — crash loud and early on a hosted build that's missing required
  // env vars instead of silently 5xx-ing on the first network call. Dev
  // builds keep the localhost defaults.
  AppConfig.validateOrThrow(_sentryEnv);
  // Path-based URLs on web so clean QR/deep links like /session/ABCD reach
  // go_router instead of being stripped by the default hash strategy.
  usePathUrlStrategy();
  await initCore();

  if (_sentryDsn.isEmpty) {
    runApp(const ArenaApp());
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.release = _sentryRelease.isEmpty ? null : _sentryRelease;
      options.environment = _sentryEnv;
      options.tracesSampleRate = 0.1;
      // Never let the SDK auto-attach IP, user agent, or request bodies.
      options.sendDefaultPii = false;
      // Defence-in-depth scrubber applied to every event.
      options.beforeSend = scrubEvent;
    },
    appRunner: () => runApp(const ArenaApp()),
  );
}