import 'package:flutter/material.dart';

class OverlayController {
  final ValueNotifier<bool> isBusy = ValueNotifier<bool>(false);

  void show() => isBusy.value = true;

  void hide() => isBusy.value = false;
}

class OverlayManager extends StatelessWidget {
  const OverlayManager({super.key, required this.child, required this.controller});

  final Widget child;
  final OverlayController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.isBusy,
      builder: (BuildContext context, bool isBusy, Widget? _) {
        return Stack(
          children: <Widget>[
            child,
            if (isBusy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.15),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }
}