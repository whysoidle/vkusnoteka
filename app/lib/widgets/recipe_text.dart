import 'package:flutter/material.dart';

/// Vertical swipes scroll the page; a long press still selects text for copying.
class RecipeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const RecipeText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) =>
      SelectionArea(child: Text(text, style: style));
}
