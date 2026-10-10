import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/screens/detail.dart';
import 'package:recipe_vault/theme/appearance.dart';
import 'ui_test.dart' as fixtures;

void main() {
  testWidgets(
    'mixed quantity layouts keep package sizes and nutrition when servings change',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const original = [
        '800мл бульона',
        'Томаты 2 банки по 400 г',
        'Сливки 20% (100 мл)',
        'Мука 1½ стакана',
        'Яйца 1–2 шт.',
        'Масло половина пачки',
      ];
      const doubled = [
        '1600мл бульона',
        'Томаты 4 банки по 400 г',
        'Сливки 20% (200 мл)',
        'Мука 3 стакана',
        'Яйца 2–4 шт.',
        'Масло 1 пачки',
      ];
      const recipe = Recipe(
        id: 'mixed',
        title: 'Рецепт',
        servings: '2',
        ingredients: original,
      );
      final controller = await fixtures.controller();
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const RecipeScrollBehavior(),
          home: RecipeDetail(recipe: recipe, controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Больше порций'));
        await tester.pumpAndSettle();
      }
      for (final value in doubled) {
        expect(find.text(value), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Исходные порции'));
      await tester.pumpAndSettle();
      for (final value in original) {
        expect(find.text(value), findsOneWidget);
      }
      expect(recipe.ingredients, original);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );
  testWidgets(
    'comma ingredients scale from original values and reset on all platforms',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const original = [
        'Куриный бульон, 800 мл',
        'Кокосовые сливки, 400 мл',
        'Куркума, 8 г',
        'Смесь тандури-масала,  по вкусу',
        'Желтая паста карри , 20 г',
        'Чеснок, 1 головка',
        'Хумус, 160 г',
      ];
      const doubled = [
        'Куриный бульон, 1600 мл',
        'Кокосовые сливки, 800 мл',
        'Куркума, 16 г',
        'Смесь тандури-масала,  по вкусу',
        'Желтая паста карри , 40 г',
        'Чеснок, 2 головка',
        'Хумус, 320 г',
      ];
      const recipe = Recipe(
        id: 'comma-soup',
        title: 'Суп',
        servings: '2 порции',
        ingredients: original,
        draft: false,
      );
      final controller = await fixtures.controller();
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const RecipeScrollBehavior(),
          home: RecipeDetail(recipe: recipe, controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Больше порций'));
        await tester.pumpAndSettle();
      }
      for (final value in doubled) {
        expect(find.text(value), findsOneWidget);
      }
      // Returning from four to three servings must use 3/2 of the source,
      // rather than scale the already displayed doubled ingredients again.
      await tester.tap(find.byTooltip('Меньше порций'));
      await tester.pumpAndSettle();
      expect(find.text('Куриный бульон, 1200 мл'), findsOneWidget);
      expect(find.text('Чеснок, 1,5 головка'), findsOneWidget);
      expect(recipe.ingredients, original);
      await tester.tap(find.byTooltip('Исходные порции'));
      await tester.pumpAndSettle();
      for (final value in original) {
        expect(find.text(value), findsOneWidget);
      }
      expect(recipe.ingredients, original);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );
}
