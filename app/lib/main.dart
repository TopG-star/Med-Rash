import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/di/init_core.dart';
import 'core/ui/arena_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Path-based URLs on web so clean QR/deep links like /session/ABCD reach
  // go_router instead of being stripped by the default hash strategy.
  usePathUrlStrategy();
  await initCore();
  runApp(const ArenaApp());
}