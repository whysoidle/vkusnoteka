import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool isMac(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.macOS;

/// System accessibility preferences also govern the Flutter glass panels.
class MacGlassEnvironment extends StatefulWidget {
  final Widget child;
  const MacGlassEnvironment({super.key, required this.child});
  @override
  State<MacGlassEnvironment> createState() => _MacGlassEnvironmentState();
}

class _MacGlassEnvironmentState extends State<MacGlassEnvironment> {
  static const channel = MethodChannel('recipe_vault/appearance');
  bool reduceTransparency = false;
  bool reduceMotion = false;
  Brightness? nativeBrightness;
  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'accessibilityChanged') update(call.arguments);
    });
    channel
        .invokeMethod<Object>('preferences')
        .then(update)
        .catchError((Object _) {});
  }

  void update(Object? value) {
    if (!mounted) return;
    if (value is Map) {
      setState(() {
        reduceTransparency = value['reduceTransparency'] == true;
        reduceMotion = value['reduceMotion'] == true;
      });
    } else if (value is bool) {
      setState(() => reduceTransparency = value);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness == nativeBrightness) return;
    nativeBrightness = brightness;
    channel
        .invokeMethod<void>('setBrightness', brightness.name)
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MacGlassPreferences(
    reduceTransparency: reduceTransparency,
    reduceMotion: reduceMotion,
    child: widget.child,
  );
}

class MacGlassPreferences extends InheritedWidget {
  final bool reduceTransparency;
  final bool reduceMotion;
  const MacGlassPreferences({
    super.key,
    required this.reduceTransparency,
    this.reduceMotion = false,
    required super.child,
  });
  static bool reduced(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MacGlassPreferences>()
          ?.reduceTransparency ??
      false;
  static bool motionReduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      (context
              .dependOnInheritedWidgetOfExactType<MacGlassPreferences>()
              ?.reduceMotion ??
          false);
  @override
  bool updateShouldNotify(MacGlassPreferences oldWidget) =>
      oldWidget.reduceTransparency != reduceTransparency ||
      oldWidget.reduceMotion != reduceMotion;
}

abstract final class MacMotion {
  static const curve = Cubic(.22, 1, .36, 1);
  static Duration duration(BuildContext context, [int milliseconds = 260]) =>
      MacGlassPreferences.motionReduced(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
}

/// Only navigation panes blur the backdrop; scrolling cards use tinted fills.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final dark = c.brightness == Brightness.dark;
    final reduced = MacGlassPreferences.reduced(context);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        // Low-alpha gradients quantize into visible diagonal bands. Keep
        // the large glass fill uniform; only the narrow rim has a highlight.
        color: reduced
            ? c.surfaceContainer
            : c.surface.withValues(alpha: dark ? .28 : .24),
      ),
      child: Padding(padding: padding, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: reduced
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .2 : .07),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .12 : .025),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          foregroundPainter: reduced
              ? null
              : _GlassEdge(radius: radius, dark: dark),
          child: reduced
              ? surface
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  // Replace the sampled transparent backdrop instead of
                  // compositing it over the original, still-sharp content.
                  blendMode: BlendMode.src,
                  child: surface,
                ),
        ),
      ),
    );
  }
}

/// A narrow specular rim separates the glass from the backdrop without
/// covering text or adding a blur pass for every element.
class _GlassEdge extends CustomPainter {
  final double radius;
  final bool dark;
  const _GlassEdge({required this.radius, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(.6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: dark ? .5 : .9),
          Colors.white.withValues(alpha: dark ? .1 : .24),
          Colors.white.withValues(alpha: dark ? .03 : .08),
          Colors.white.withValues(alpha: dark ? .26 : .54),
        ],
        stops: const [0, .3, .7, 1],
      ).createShader(bounds);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds,
        Radius.circular((radius - .6).clamp(0, double.infinity)),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GlassEdge oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.dark != dark;
}

class MacWindowBackground extends StatelessWidget {
  final Widget child;
  const MacWindowBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final reduced = MacGlassPreferences.reduced(context);
    final dark = c.brightness == Brightness.dark;
    return ColoredBox(
      color: c.surface.withValues(alpha: reduced ? 1 : (dark ? .26 : .18)),
      // Reserve the native draggable titlebar and traffic lights on every route.
      child: Padding(padding: const EdgeInsets.only(top: 38), child: child),
    );
  }
}

ThemeData macTheme(ThemeData base) {
  final c = base.colorScheme;
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        ...base.pageTransitionsTheme.builders,
        TargetPlatform.macOS: const MacPageTransitionsBuilder(),
      },
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: c.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: c.surfaceContainerLow.withValues(
        alpha: c.brightness == Brightness.dark ? .58 : .66,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: Colors.white.withValues(
            alpha: c.brightness == Brightness.dark ? .16 : .72,
          ),
        ),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: c.surfaceContainerHighest.withValues(alpha: .48),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: c.surfaceContainerLow.withValues(alpha: .46),
    ),
  );
}

/// Replace the route immediately. An opaque first frame hides the outgoing
/// page, then the temporary cover fades to reveal the native window material.
class MacPageTransitionsBuilder extends PageTransitionsBuilder {
  const MacPageTransitionsBuilder();
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => route.isFirst
      ? child
      : MacPageEntrance(key: ValueKey(route), child: child);
}

class MacPageEntrance extends StatefulWidget {
  final Widget child;
  const MacPageEntrance({super.key, required this.child});
  @override
  State<MacPageEntrance> createState() => _MacPageEntranceState();
}

class _MacPageEntranceState extends State<MacPageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final CurvedAnimation progress = CurvedAnimation(
    parent: controller,
    curve: MacMotion.curve,
  );
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MacGlassPreferences.motionReduced(context)) {
      controller.value = 1;
      started = true;
    } else if (!started) {
      started = true;
      controller.forward();
    }
  }

  @override
  void dispose() {
    progress.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    child: RepaintBoundary(child: widget.child),
    builder: (context, child) => ColoredBox(
      color: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 1 - progress.value),
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - progress.value)),
        child: Opacity(opacity: progress.value, child: child),
      ),
    ),
  );
}
