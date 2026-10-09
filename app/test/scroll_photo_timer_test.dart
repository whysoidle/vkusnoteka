import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/screens/cooking.dart';
import 'package:recipe_vault/screens/detail.dart';
import 'package:recipe_vault/screens/editor.dart';
import 'package:recipe_vault/services/app_controller.dart';
import 'package:recipe_vault/services/storage.dart';
import 'package:recipe_vault/services/timer_alarm.dart';
import 'package:recipe_vault/theme/appearance.dart';
import 'package:recipe_vault/widgets/recipe_photo.dart';
import 'package:recipe_vault/widgets/recipe_text.dart';

class ScreenStorage extends LocalStorage {
  ScreenStorage() : super(Directory.systemTemp);
  @override
  Future<void> saveDatabase(RecipeDatabase database) async {}
}

Widget app(Widget child) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.android),
  scrollBehavior: const RecipeScrollBehavior(),
  home: child,
);

void androidTest(String description, WidgetTesterCallback callback) =>
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  androidTest(
    'dragging read-only recipe text scrolls the page and long press still selects',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ListView(
              controller: controller,
              children: [
                RecipeText(
                  List.filled(20, 'Смешайте муку и молоко.').join('\n'),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      );
      final text = find.byType(RecipeText);
      await tester.dragFrom(
        tester.getTopLeft(text) + const Offset(40, 160),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(80));
      await tester.longPressAt(tester.getTopLeft(text) + const Offset(40, 160));
      await tester.pumpAndSettle();
      final selection = tester.state<SelectionAreaState>(
        find.byType(SelectionArea),
      );
      expect(selection.selectableRegion.contextMenuAnchors, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  androidTest(
    'recipe step, notes and source each allow dragging the detail page',
    (tester) async {
      final recipe = Recipe(
        id: 'test',
        title: 'Рецепт',
        steps: [List.filled(60, 'Смешайте продукты.').join('\n')],
        notes: List.filled(60, 'Заметка к рецепту.').join('\n'),
        sourceText: List.filled(20, 'Исходный текст.').join('\n'),
      );
      final c = AppController(
        storage: ScreenStorage(),
        database: RecipeDatabase(),
        settings: AppSettings(deviceId: 'test', autoSync: false),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(app(RecipeDetail(recipe: recipe, controller: c)));
      final list = find.byType(ListView);
      final scrollable = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      for (final value in [recipe.steps.single, recipe.notes]) {
        final text = find.text(value);
        await tester.scrollUntilVisible(text, 180, scrollable: scrollable);
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        final before = position.pixels;
        final point = tester
            .getRect(text)
            .intersect(tester.getRect(list))
            .center;
        await tester.dragFrom(point, const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(before + 50));
      }
      await tester.scrollUntilVisible(
        find.text('Исходный текст'),
        180,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Исходный текст'));
      await tester.pumpAndSettle();
      final text = find.text(recipe.sourceText);
      await tester.ensureVisible(text);
      await tester.pumpAndSettle();
      final before = position.pixels;
      await tester.dragFrom(
        tester.getRect(text).intersect(tester.getRect(list)).center,
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, lessThan(before - 50));
      expect(tester.takeException(), isNull);
    },
  );

  androidTest(
    'dragging the multiline recipe editor scrolls the page and dismisses keyboard',
    (tester) async {
      final recipe = Recipe(
        id: 'test',
        title: 'Рецепт',
        ingredients: List.generate(30, (i) => 'Мука — $i г'),
      );
      await tester.pumpWidget(app(RecipeEditor(recipe: recipe)));
      // Locate the ingredient field by its hint; it grows with the text rather than nesting a viewport.
      final ingredients = find.byWidgetPredicate(
        (w) =>
            w is EditableText &&
            w.controller.text == recipe.ingredients.join('\n'),
      );
      final list = find.byType(ListView),
          scrollable = find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first;
      await tester.scrollUntilVisible(ingredients, 180, scrollable: scrollable);
      final position = tester.state<ScrollableState>(scrollable).position;
      final point = tester
          .getRect(ingredients)
          .intersect(tester.getRect(list))
          .center;
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, true);
      final before = position.pixels;
      await tester.dragFrom(point, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(before + 50));
      expect(tester.testTextInput.isVisible, false);
    },
  );

  androidTest(
    'photo stays decoded on rebuild and returning to an offscreen list item',
    (tester) async {
      final photo = base64Encode(
        img.encodePng(
          img.Image(width: 16, height: 16)..setPixelRgba(0, 0, 255, 0, 0, 255),
        ),
      );
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      Widget page({int revision = 0}) => app(
        Scaffold(
          body: ListView.builder(
            controller: scroll,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            itemCount: 30,
            itemBuilder: (_, index) => index == 0
                ? RecipePhoto(photo: photo, height: 150)
                : SizedBox(height: 180, child: Text('$index · $revision')),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.runAsync(
        () => precacheImage(
          tester.widget<Image>(find.byType(Image)).image,
          tester.element(find.byType(Image)),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.widget<Image>(find.byType(Image));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await tester.pumpWidget(page(revision: 1));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      scroll.jumpTo(2400);
      await tester.pump();
      expect(find.byType(RecipePhoto), findsNothing);
      scroll.jumpTo(0);
      await tester.pump();
      expect(tester.widget<Image>(find.byType(Image)).image, first.image);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  androidTest('replacing a recipe photo displays the new image', (
    tester,
  ) async {
    String photo(int r, int g) => base64Encode(
      img.encodePng(
        img.Image(width: 2, height: 2)..setPixelRgba(0, 0, r, g, 0, 255),
      ),
    );
    await tester.pumpWidget(app(RecipePhoto(photo: photo(255, 0))));
    final first = tester.widget<Image>(find.byType(Image)).image;
    await tester.pumpWidget(app(RecipePhoto(photo: photo(0, 255))));
    expect(tester.widget<Image>(find.byType(Image)).image, isNot(first));
    await tester.runAsync(
      () => precacheImage(
        tester.widget<Image>(find.byType(Image)).image,
        tester.element(find.byType(Image)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });

  androidTest(
    'expired timer sounds once, can be silenced and stops on leaving cooking',
    (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        TimerAlarm.channel,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          TimerAlarm.channel,
          null,
        ),
      );
      var now = DateTime(2026, 10, 9);
      await tester.pumpWidget(
        app(
          CookingScreen(
            recipe: const Recipe(
              id: 'test',
              title: 'Таймер',
              steps: ['Подождите 1 сек.'],
            ),
            now: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Таймер 1 сек'));
      await tester.pump();
      expect(calls.where((m) => m == 'play'), isEmpty);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.where((m) => m == 'play').length, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(calls.where((m) => m == 'play').length, 1);
      await tester.tap(find.text('Остановить звук'));
      await tester.pump();
      expect(calls.last, 'stop');
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pump();
      expect(calls.where((m) => m == 'stop').length, 2);
    },
  );

  androidTest('sound preview reports silent alarm volume and can retry', (
    tester,
  ) async {
    var fail = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      TimerAlarm.channel,
      (call) async {
        if (call.method == 'play' && fail) {
          throw PlatformException(
            code: 'TIMER_SOUND_FAILED',
            message: 'Громкость будильника установлена на ноль.',
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        TimerAlarm.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      app(
        const CookingScreen(
          recipe: Recipe(id: 'test', title: 'Таймер', steps: ['Шаг']),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Проверить звук таймера'));
    await tester.tap(find.text('Проверить звук таймера'));
    await tester.pumpAndSettle();
    expect(
      find.text('Громкость будильника установлена на ноль.'),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(find.text('Проверить звук таймера'));
    await tester.pumpAndSettle();
    expect(
      find.text('Громкость будильника установлена на ноль.'),
      findsNothing,
    );
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pump();
  });

  test('Windows timer uses its supported system alert sound', () async {
    final methods = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          methods.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await const TimerAlarm(platform: TargetPlatform.windows).play();
    expect(methods.single.method, 'SystemSound.play');
    expect(methods.single.arguments, 'SystemSoundType.alert');
  });
}
