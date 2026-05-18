import 'package:flutter/material.dart';

import 'core/di/init_core.dart';
import 'core/ui/arena_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initCore();
  runApp(const ArenaApp());
}