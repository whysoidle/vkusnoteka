import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

bool isDesktopNavigation(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.macOS || TargetPlatform.windows => true,
      _ => false,
    };

/// Horizontal touch/trackpad navigation. Nested horizontal scrollables get
/// first refusal, and mouse text selection keeps its normal drag gesture.
class DesktopSwipe extends StatefulWidget {
  final Widget child;
  final VoidCallback? onLeft, onRight;
  final bool blockNavigation;
  const DesktopSwipe({
    super.key,
    required this.child,
    this.onLeft,
    this.onRight,
    this.blockNavigation = false,
  });

  @override
  State<DesktopSwipe> createState() => _DesktopSwipeState();
}

class _DesktopSwipeState extends State<DesktopSwipe> {
  double distance = 0, wheelDistance = 0;
  Duration? lastWheel;
  bool wheelHandled = false;

  void navigate(double delta) {
    if (widget.blockNavigation) return;
    if (delta < 0) {
      widget.onLeft?.call();
    } else {
      widget.onRight?.call();
    }
  }

  void pointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    if (delta.dx.abs() <= delta.dy.abs() * 1.5 || delta.dx == 0) return;
    if (!widget.blockNavigation &&
        (delta.dx > 0 && widget.onLeft == null ||
            delta.dx < 0 && widget.onRight == null)) {
      return;
    }
    // Children, such as category chips or a text field, may already own this
    // event. Never scroll those children and change the page simultaneously.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (widget.blockNavigation) return;
      if (lastWheel == null ||
          event.timeStamp - lastWheel! > const Duration(milliseconds: 250)) {
        wheelDistance = 0;
        wheelHandled = false;
      }
      lastWheel = event.timeStamp;
      wheelDistance -= delta.dx;
      if (!wheelHandled && wheelDistance.abs() >= 110) {
        wheelHandled = true;
        navigate(wheelDistance);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopNavigation(context)) return widget.child;
    return Listener(
      onPointerSignal: pointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
        onHorizontalDragStart: (_) => distance = 0,
        onHorizontalDragUpdate: (event) => distance += event.delta.dx,
        onHorizontalDragEnd: (_) {
          if (distance.abs() >= 72) navigate(distance);
          distance = 0;
        },
        onHorizontalDragCancel: () => distance = 0,
        child: widget.child,
      ),
    );
  }
}
