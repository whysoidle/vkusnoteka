import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'desktop_swipe.dart';

/// Keep readable line lengths without leaving inert gutters beside the page.
class PageList extends StatelessWidget {
  final double maxWidth;
  final EdgeInsets padding;
  final List<Widget> children;
  final Key? listKey;
  const PageList({
    super.key,
    required this.maxWidth,
    required this.children,
    this.padding = const EdgeInsets.all(24),
    this.listKey,
  });

  @override
  Widget build(BuildContext context) {
    Widget list(EdgeInsets inset) => ListView(
      key: listKey,
      hitTestBehavior: HitTestBehavior.opaque,
      padding: inset,
      children: children,
    );
    if (!isDesktopNavigation(context)) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: list(padding),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = math.max(0.0, (constraints.maxWidth - maxWidth) / 2);
        return list(padding + EdgeInsets.symmetric(horizontal: gutter));
      },
    );
  }
}
