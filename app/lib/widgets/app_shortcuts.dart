import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'desktop_swipe.dart';

class AppShortcuts extends StatelessWidget {
  final Widget child;
  final VoidCallback onNewRecipe, onSearch;
  const AppShortcuts({
    super.key,
    required this.child,
    required this.onNewRecipe,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    if (!isDesktopNavigation(context)) return child;
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyN,
          meta: mac,
          control: !mac,
          includeRepeats: false,
        ): onNewRecipe,
        SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: mac,
          control: !mac,
          includeRepeats: false,
        ): onSearch,
        if (mac) ...{
          const SingleActivator(
            LogicalKeyboardKey.keyN,
            alt: true,
            includeRepeats: false,
          ): onNewRecipe,
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            alt: true,
            includeRepeats: false,
          ): onSearch,
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
