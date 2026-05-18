import 'package:flutter/material.dart';

import '../di/get_it.dart';
import '../infra/overlay_manager.dart';

mixin OperationRunnerState<T extends StatefulWidget> on State<T> {
  Future<void> runOperation(Future<void> Function() operation) async {
    final OverlayController overlayController = getIt<OverlayController>();
    overlayController.show();
    try {
      await operation();
    } finally {
      overlayController.hide();
    }
  }
}