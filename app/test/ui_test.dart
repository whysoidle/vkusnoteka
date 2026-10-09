import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/main.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/screens/editor.dart';
import 'package:recipe_vault/screens/detail.dart';
import 'package:recipe_vault/services/app_controller.dart';
import 'package:recipe_vault/services/storage.dart';

const samples = [
  Recipe(
    id: '1',
    title: 'Сырники с ягодами',
    category: 'Завтраки',
    time: '20 мин',
    servings: '2 порции',
    ingredients: ['Творог — 400 г', 'Яйцо — 1 шт.', 'Мука — 3 ст. л.'],
    steps: ['Смешайте ингредиенты.', 'Обжарьте с двух сторон.'],
    favorite: true,
    draft: false,
  ),
  Recipe(
    id: '2',
    title: 'Томатный суп',
    category: 'Супы',
    time: '35 мин',
    servings: '4 порции',
    ingredients: ['Томаты — 800 г', 'Лук — 1 шт.', 'Бульон — 500 мл'],
    steps: ['Нарежьте овощи.', 'Варите до готовности.'],
    draft: false,
  ),
  Recipe(
    id: '3',
    title: 'Паста с грибами',
    category: 'Основные блюда',
    time: '25 мин',
    ingredients: ['Паста — 200 г', 'Грибы — 150 г'],
    steps: ['Отварите пасту.', 'Обжарьте грибы и смешайте.'],
    favorite: true,
    draft: false,
  ),
  Recipe(
    id: '4',
    title: 'Лимонный пирог',
    category: 'Выпечка',
    sourceUrl: 'https://youtu.be/abcdefghijk',
  ),
];

class MemoryStorage extends LocalStorage {
  MemoryStorage() : super(Directory.systemTemp);
  @override
  Future<void> saveDatabase(RecipeDatabase database) async {}
  AppSettings? savedSettings;
  @override
  Future<void> saveSettings(AppSettings settings) async {
    savedSettings = settings;
  }

  @override
  Future<void> setSecret(String key, String value) async {}
  @override
  Future<String> secret(String key) async => '';
}

Future<AppController> controller() async {
  final database = RecipeDatabase();
  for (final r in samples) {
    database.put(r, 'test');
  }
  final c = AppController(
    storage: MemoryStorage(),
    database: database,
    settings: AppSettings(deviceId: 'test'),
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../docs/previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    // Optional locally installed font makes exported previews readable. It is never bundled.
    final font = File(
      Platform.environment['RECIPE_PREVIEW_FONT'] ??
          '/System/Library/Fonts/Supplemental/Arial.ttf',
    );
    if (await font.exists()) {
      for (final family in ['Roboto', 'Arial']) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          );
        await loader.load();
      }
    }
  });
  testWidgets('Android catalog, chat fallback and draft retain the source', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await controller(), key = GlobalKey();
    // This test covers ordinary URL fallback without YouTube subtitle requests.
    c.settings.localAi = false;
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: RecipeVaultApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сырники с ягодами'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, key, 'android-light');
    await tester.tap(find.text('Чат'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'https://youtu.be/abcdefghijk?t=10',
    );
    await tester.tap(find.byTooltip('Разобрать рецепт'));
    await tester.pumpAndSettle();
    expect(find.text('Заполнить вручную'), findsOneWidget);
    await screenshot(tester, key, 'android-chat');
    await tester.tap(find.text('Сохранить черновик'));
    await tester.pumpAndSettle();
    expect(find.text('Похожий рецепт уже есть'), findsOneWidget);
    await tester.tap(find.text('Сохранить отдельный рецепт'));
    await tester.pumpAndSettle();
    expect(
      c.recipes.any((r) => r.sourceUrl == 'https://youtu.be/abcdefghijk?t=10'),
      true,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'theme and accent apply immediately, persist and survive closing settings',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = await controller();
      await tester.pumpWidget(RecipeVaultApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Сохранить настройки'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('appearance-theme')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тёмная').last);
      await tester.pumpAndSettle();
      expect(c.settings.theme, 'dark');
      expect(
        Theme.of(tester.element(find.text('Настройки'))).brightness,
        Brightness.dark,
      );
      await tester.ensureVisible(find.text('Синий'));
      await tester.tap(find.text('Синий'));
      await tester.pumpAndSettle();
      expect(c.settings.accent, 'blue');
      expect((c.storage as MemoryStorage).savedSettings!.accent, 'blue');
      final darkBlue = Theme.of(
        tester.element(find.text('Настройки')),
      ).colorScheme.primary;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('appearance-theme')),
        -200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('settings-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('appearance-theme')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Светлая').last);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Настройки'))).brightness,
        Brightness.light,
      );
      expect(
        Theme.of(tester.element(find.text('Настройки'))).colorScheme.primary,
        isNot(darkBlue),
      );
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(c.settings.theme, 'light');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('dragging chat dismisses composer keyboard', (tester) async {
    final c = await controller();
    await tester.pumpWidget(RecipeVaultApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Чат'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, true);
    await tester.drag(find.byType(ListView).last, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, false);
  });
  testWidgets(
    'portions preserve original ingredients and cooking shows one step',
    (tester) async {
      final c = await controller();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(recipe: samples.first, controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Больше порций'));
      await tester.tap(find.byTooltip('Больше порций'));
      await tester.pumpAndSettle();
      expect(find.text('Творог — 600 г'), findsOneWidget);
      expect(
        c.recipes.firstWhere((r) => r.id == '1').ingredients.first,
        'Творог — 400 г',
      );
      await tester.tap(find.byTooltip('Исходные порции'));
      await tester.pumpAndSettle();
      expect(find.text('Творог — 400 г'), findsOneWidget);
      await tester.ensureVisible(find.text('Начать готовить'));
      await tester.tap(find.text('Начать готовить'));
      await tester.pumpAndSettle();
      expect(find.text('Шаг 1 из 2'), findsOneWidget);
      expect(find.text('Смешайте ингредиенты.'), findsOneWidget);
      expect(find.text('Обжарьте с двух сторон.'), findsNothing);
      await tester.tap(find.text('Следующий шаг'));
      await tester.pumpAndSettle();
      expect(find.text('Шаг 2 из 2'), findsOneWidget);
      expect(find.text('Обжарьте с двух сторон.'), findsOneWidget);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Windows layout displays catalog and chat together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await controller(), key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: RecipeVaultApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сырники с ягодами'), findsOneWidget);
    expect(find.text('Добавить рецепт'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, key, 'windows-light');
    c.settings.theme = 'dark';
    await c.save(samples.first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await screenshot(tester, key, 'windows-dark');
  });
  testWidgets('compact screen supports enlarged system text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await controller();
    await tester.pumpWidget(RecipeVaultApp(controller: c));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Чат'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'editor can save a manually filled YouTube recipe without losing its URL',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Recipe? saved;
      final recipe = Recipe.blank(url: 'https://youtu.be/abcdefghijk');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await Navigator.push<Recipe>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecipeEditor(recipe: recipe),
                    ),
                  );
                },
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Мой рецепт');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(saved?.title, 'Мой рецепт');
      expect(saved?.sourceUrl, 'https://youtu.be/abcdefghijk');
      expect(saved?.draft, true);
      expect(tester.takeException(), isNull);
    },
  );
}
