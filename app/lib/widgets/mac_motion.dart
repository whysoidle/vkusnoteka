import 'package:flutter/material.dart';
import '../theme/macos_glass.dart';

/// Resize from the current frame when the target changes. Unlike an implicit
/// size animation, this also finishes immediately if Reduce Motion turns on.
class MacAnimatedExtent extends StatefulWidget {
  final double value;
  final Widget child;
  final Widget Function(BuildContext, double, Widget) builder;
  const MacAnimatedExtent({
    super.key,
    required this.value,
    required this.child,
    required this.builder,
  });
  @override
  State<MacAnimatedExtent> createState() => _MacAnimatedExtentState();
}

class _MacAnimatedExtentState extends State<MacAnimatedExtent>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  late double from = widget.value, to = widget.value;
  double get current =>
      from + (to - from) * MacMotion.curve.transform(controller.value);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MacGlassPreferences.motionReduced(context)) controller.value = 1;
  }

  @override
  void didUpdateWidget(MacAnimatedExtent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    from = current;
    to = widget.value;
    if (MacGlassPreferences.motionReduced(context)) {
      controller.value = 1;
    } else {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (context, child) => widget.builder(context, current, child!),
  );
}

class MacAnimatedSize extends StatefulWidget {
  final Widget child;
  const MacAnimatedSize({super.key, required this.child});
  @override
  State<MacAnimatedSize> createState() => _MacAnimatedSizeState();
}

class _MacAnimatedSizeState extends State<MacAnimatedSize> {
  final contents = GlobalKey();
  @override
  Widget build(BuildContext context) {
    if (!isMac(context)) return widget.child;
    final child = KeyedSubtree(key: contents, child: widget.child);
    return MacGlassPreferences.motionReduced(context)
        ? child
        : AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: MacMotion.curve,
            alignment: Alignment.topCenter,
            child: child,
          );
  }
}

/// Pointer feedback without replacing the child's state or cached photographs.
class MacHoverFeedback extends StatefulWidget {
  final Widget child;
  final bool lift;
  const MacHoverFeedback({super.key, required this.child, this.lift = true});
  @override
  State<MacHoverFeedback> createState() => _MacHoverFeedbackState();
}

class _MacHoverFeedbackState extends State<MacHoverFeedback> {
  bool hover = false, pressed = false;
  @override
  Widget build(BuildContext context) {
    final reduced = MacGlassPreferences.motionReduced(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() {
        hover = false;
        pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => pressed = true),
        onPointerUp: (_) => setState(() => pressed = false),
        onPointerCancel: (_) => setState(() => pressed = false),
        child: AnimatedScale(
          duration: MacMotion.duration(context, 160),
          curve: MacMotion.curve,
          scale: reduced
              ? 1
              : (pressed ? .985 : (hover && widget.lift ? 1.008 : 1)),
          child: AnimatedContainer(
            duration: MacMotion.duration(context, 200),
            curve: MacMotion.curve,
            transform: Matrix4.translationValues(
              0,
              !reduced && hover && widget.lift && !pressed ? -2 : 0,
              0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: hover && widget.lift ? .09 : 0,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: RepaintBoundary(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Keep each pane mounted during tab changes, but hide focus, semantics and
/// pointer targets immediately when it starts fading out.
class MacPaneVisibility extends StatefulWidget {
  final bool visible;
  final Widget child;
  const MacPaneVisibility({
    super.key,
    required this.visible,
    required this.child,
  });
  @override
  State<MacPaneVisibility> createState() => _MacPaneVisibilityState();
}

class _MacPaneVisibilityState extends State<MacPaneVisibility>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: widget.visible ? 1 : 0,
  );
  late final progress = CurvedAnimation(
    parent: controller,
    curve: MacMotion.curve,
  );

  void updateVisibility() {
    if (MacGlassPreferences.motionReduced(context)) {
      controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    updateVisibility();
  }

  @override
  void didUpdateWidget(MacPaneVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) updateVisibility();
  }

  @override
  void dispose() {
    progress.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: RepaintBoundary(child: widget.child),
    builder: (context, child) => Offstage(
      offstage: controller.isDismissed,
      child: TickerMode(
        enabled: widget.visible || controller.isAnimating,
        child: ExcludeFocus(
          excluding: !widget.visible,
          child: ExcludeSemantics(
            excluding: !widget.visible,
            child: IgnorePointer(
              ignoring: !widget.visible,
              child: Opacity(opacity: progress.value, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}
