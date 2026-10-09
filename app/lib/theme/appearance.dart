import 'package:flutter/material.dart';

const accentColors = <String, (String, Color)>{
  'olive': ('Оливковый', Color(0xff526443)),
  'blue': ('Синий', Color(0xff315da8)),
  'purple': ('Фиолетовый', Color(0xff7952a3)),
  'rose': ('Розовый', Color(0xffad4965)),
  'orange': ('Оранжевый', Color(0xffb85c19)),
  'teal': ('Бирюзовый', Color(0xff007e80)),
  'green': ('Зелёный', Color(0xff278247)),
  'red': ('Красный', Color(0xffb63e3e)),
};

ColorScheme appColorScheme(
  String accent,
  Brightness brightness,
  ColorScheme? dynamicScheme,
) {
  if (accent == 'system' && dynamicScheme != null) return dynamicScheme;
  return ColorScheme.fromSeed(
    seedColor: (accentColors[accent] ?? accentColors['olive']!).$2,
    brightness: brightness,
  );
}

class RecipeScrollBehavior extends MaterialScrollBehavior {
  const RecipeScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final physics = super.getScrollPhysics(context);
    // Empty text fields must not capture the page's vertical drag gesture.
    if (context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return physics;
    }
    return AlwaysScrollableScrollPhysics(parent: physics);
  }

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => ScrollViewKeyboardDismissBehavior.onDrag;
}
