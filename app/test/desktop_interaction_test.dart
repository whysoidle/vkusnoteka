import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/main.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/screens/chat.dart';
import 'package:recipe_vault/screens/cooking.dart';
import 'package:recipe_vault/screens/detail.dart';
import 'package:recipe_vault/screens/document_import.dart';
import 'package:recipe_vault/screens/editor.dart';
import 'package:recipe_vault/screens/search.dart';
import 'package:recipe_vault/screens/settings.dart';
import 'package:recipe_vault/theme/appearance.dart';
import 'package:recipe_vault/widgets/desktop_swipe.dart';
import 'package:recipe_vault/widgets/page_list.dart';
import 'package:recipe_vault/widgets/recipe_text.dart';
import 'ui_test.dart' as fixtures;

void main() {
  final desktop = TargetPlatformVariant({
    TargetPlatform.macOS,
    TargetPlatform.windows,
  });
  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> wheel(
    WidgetTester tester,
    Offset point,
    Offset delta, [
    int ms = 0,
  ]) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: point,
        scrollDelta: delta,
        kind: PointerDeviceKind.mouse,
        timeStamp: Duration(milliseconds: ms),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shortcut(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool alt = false,
  }) async {
    final modifier = alt
        ? LogicalKeyboardKey.altLeft
        : defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('desktop pages scroll over both empty gutters, text and gaps', (
    tester,
  ) async {
    size(tester, const Size(1280, 360));
    final controller = await fixtures.controller();
    final recipe = Recipe(
      id: 'long',
      title: 'Проверка',
      steps: [List.filled(50, 'Смешайте продукты.').join('\n')],
    );
    for (final page in [
      SettingsScreen(controller: controller),
      RecipeEditor(recipe: recipe),
      RecipeDetail(recipe: recipe, controller: controller),
      const DocumentImportScreen(),
      CookingScreen(recipe: recipe),
    ]) {
      await tester.pumpWidget(
        MaterialApp(scrollBehavior: const RecipeScrollBehavior(), home: page),
      );
      await tester.pumpAndSettle();
      final list = find
          .descendant(
            of: find.byType(PageList),
            matching: find.byType(ListView),
          )
          .first;
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: '${page.runtimeType} must overflow',
      );
      for (final x in [12.0, 1268.0, 280.0, 640.0]) {
        position.jumpTo(0);
        await tester.pump();
        await wheel(tester, Offset(x, 230), const Offset(0, 80));
        expect(
          position.pixels,
          greaterThan(0),
          reason: '${page.runtimeType} at x=$x',
        );
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets(
    'desktop gestures respect vertical scroll, nested filters and wheel momentum',
    (tester) async {
      size(tester, const Size(800, 600));
      var next = 0, previous = 0;
      final horizontal = ScrollController();
      addTearDown(horizontal.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopSwipe(
              onLeft: () => next++,
              onRight: () => previous++,
              child: ListView(
                children: [
                  DesktopSwipe(
                    blockNavigation: true,
                    child: SingleChildScrollView(
                      controller: horizontal,
                      scrollDirection: Axis.horizontal,
                      child: const SizedBox(
                        width: 2000,
                        height: 100,
                        child: Text('Фильтры'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 1600, child: Text('Содержимое')),
                ],
              ),
            ),
          ),
        ),
      );
      await wheel(tester, const Offset(400, 50), const Offset(150, 0));
      expect(horizontal.offset, 150);
      expect(next, 0);
      horizontal.jumpTo(horizontal.position.maxScrollExtent);
      await wheel(tester, const Offset(400, 50), const Offset(150, 0), 300);
      expect(next, 0, reason: 'Filter edge must not change the page');
      await wheel(tester, const Offset(400, 230), const Offset(2, 100));
      expect(next, 0);
      await wheel(tester, const Offset(400, 230), const Offset(120, 0), 1000);
      await wheel(tester, const Offset(400, 230), const Offset(200, 0), 1100);
      expect(next, 1, reason: 'Momentum must not navigate twice');
      await wheel(tester, const Offset(400, 230), const Offset(-120, 0), 2000);
      expect(previous, 1);
      await tester.dragFrom(const Offset(400, 230), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(next, 1);
      await tester.dragFrom(
        const Offset(400, 230),
        const Offset(-180, 0),
        kind: PointerDeviceKind.trackpad,
      );
      await tester.pumpAndSettle();
      expect(next, 2);
      await tester.dragFrom(const Offset(400, 230), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(previous, 2);
    },
    variant: desktop,
  );

  testWidgets(
    'mouse text selection stays available alongside swipe navigation',
    (tester) async {
      var changed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopSwipe(
              onLeft: () => changed = true,
              onRight: () => changed = true,
              child: const RecipeText(
                'Смешайте муку и молоко, затем добавьте яйцо.',
              ),
            ),
          ),
        ),
      );
      await tester.dragFrom(
        const Offset(15, 8),
        const Offset(250, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(changed, isFalse);
      expect(
        tester
            .state<SelectionAreaState>(find.byType(SelectionArea))
            .selectableRegion
            .contextMenuAnchors,
        isNotNull,
      );
    },
    variant: desktop,
  );

  testWidgets(
    'global shortcuts work from settings and preserve an editor under search',
    (tester) async {
      size(tester, const Size(1000, 720));
      final controller = await fixtures.controller();
      await tester.pumpWidget(RecipeVaultApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(
        defaultTargetPlatform == TargetPlatform.macOS
            ? find.widgetWithText(ListTile, 'Настройки')
            : find.byTooltip('Настройки'),
      );
      await tester.pumpAndSettle();
      await shortcut(
        tester,
        LogicalKeyboardKey.keyN,
        alt: defaultTargetPlatform == TargetPlatform.macOS,
      );
      expect(find.byType(RecipeEditor), findsOneWidget);
      final title = find.widgetWithText(TextFormField, 'Название блюда');
      await tester.enterText(title, 'Несохранённый рецепт');
      await shortcut(
        tester,
        LogicalKeyboardKey.keyF,
        alt: defaultTargetPlatform == TargetPlatform.macOS,
      );
      expect(find.byType(RecipeSearchScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'томатный');
      await tester.pumpAndSettle();
      expect(find.text('Томатный суп'), findsOneWidget);
      expect(find.text('Сырники с ягодами'), findsNothing);
      await shortcut(tester, LogicalKeyboardKey.keyF);
      expect(find.byType(RecipeSearchScreen), findsOneWidget);
      await tester.dragFrom(const Offset(100, 550), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(find.text('Несохранённый рецепт'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await shortcut(tester, LogicalKeyboardKey.keyF);
      expect(find.byType(RecipeSearchScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'home swipe keeps composer state and cooking swipe keeps timers',
    (tester) async {
      size(tester, const Size(1000, 720));
      final controller = await fixtures.controller();
      await tester.pumpWidget(RecipeVaultApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.dragFrom(
        const Offset(650, 650),
        const Offset(-180, 0),
        kind: PointerDeviceKind.trackpad,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen).hitTestable(), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Рецепт в чате');
      await tester.dragFrom(const Offset(650, 650), const Offset(180, 0));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(650, 650), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(find.text('Рецепт в чате'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: CookingScreen(
            recipe: Recipe(
              id: 'steps',
              title: 'Готовка',
              steps: ['Варите 5 минут.', 'Перемешайте.'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Таймер 5 мин'));
      await tester.pump();
      await tester.dragFrom(const Offset(650, 230), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(find.text('Шаг 2 из 2'), findsOneWidget);
      expect(find.text('Шаг 1'), findsOneWidget);
      await tester.dragFrom(const Offset(650, 230), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(find.text('Шаг 2 из 2'), findsOneWidget);
      await tester.dragFrom(const Offset(650, 230), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(find.text('Шаг 1 из 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    variant: desktop,
  );
}
