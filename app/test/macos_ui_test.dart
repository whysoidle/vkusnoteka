import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/main.dart';
import 'package:recipe_vault/screens/chat.dart';
import 'package:recipe_vault/screens/settings.dart';
import 'package:recipe_vault/theme/macos_glass.dart';
import 'package:recipe_vault/widgets/mac_motion.dart';
import 'package:recipe_vault/widgets/recipe_card.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'ui_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    if (await font.exists()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in [
        'Roboto',
        '.AppleSystemUIFont',
        '.AppleSystemUIFontDisplay',
      ]) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
  });
  void macTest(String name, WidgetTesterCallback test) => testWidgets(
    name,
    test,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  macTest('Mac sidebar filters, shortcuts and resize preserve chat state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1380, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await fixtures.controller();
    controller.settings.localAi = false;
    await tester.pumpWidget(RecipeVaultApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Моя книга'), findsOneWidget);
    expect(find.text('Добавить рецепт'), findsOneWidget);
    final chatState = tester.state(find.byType(ChatScreen));
    final favorite = find.widgetWithText(ListTile, 'Избранное');
    await tester.tap(favorite);
    await tester.pumpAndSettle();
    expect(find.text('Сырники с ягодами'), findsOneWidget);
    expect(find.text('Томатный суп'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, 'Блюдо или ингредиент');
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    await tester.tap(find.widgetWithText(ListTile, 'Импорт рецепта'));
    await tester.pumpAndSettle();
    final composer = find.byType(TextField).last;
    await tester.enterText(composer, 'Рецепт для проверки');
    tester.view.physicalSize = const Size(760, 680);
    await tester.pumpAndSettle();
    expect(identical(chatState, tester.state(find.byType(ChatScreen))), isTrue);
    expect(find.text('Рецепт для проверки'), findsOneWidget);
    expect(find.byTooltip('Каталог'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  macTest('Mac glass follows light/dark theme and reduced transparency', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1380, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var reduced = false;
    final nativeThemes = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('recipe_vault/appearance'),
          (call) async {
            if (call.method == 'setBrightness') {
              nativeThemes.add(call.arguments as String);
              return null;
            }
            return reduced;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('recipe_vault/appearance'),
            null,
          ),
    );
    final controller = await fixtures.controller(), key = GlobalKey();
    controller.settings.theme = 'light';
    controller.settings.accent = 'blue';
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: RecipeVaultApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(nativeThemes.last, 'light');
    await fixtures.screenshot(tester, key, 'macos-light');
    controller.settings.theme = 'dark';
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Моя книга'))).brightness,
      Brightness.dark,
    );
    await fixtures.screenshot(tester, key, 'macos-dark');
    expect(nativeThemes.last, 'dark');
    reduced = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(RecipeVaultApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      MacGlassPreferences.reduced(tester.element(find.text('Моя книга'))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  macTest('Mac glass removes sharp stripes on a transparent backdrop', (
    tester,
  ) async {
    final key = GlobalKey();
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 320,
                height: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Row(
                      children: List.generate(
                        80,
                        (i) => Expanded(
                          child: ColoredBox(
                            color: i.isEven ? Colors.black : Colors.transparent,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                    const GlassPanel(child: SizedBox.expand()),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final pixels = (await image.toByteData())!.buffer.asUint8List();
          // Four-pixel sharp stripes must become a smooth tint. Checking
          // alpha as well catches the original content leaking through a
          // blurred but translucent layer on the transparent macOS window.
          for (final channel in [0, 3]) {
            final values = [
              for (var x = 96; x < 224; x++)
                pixels[(48 * image.width + x) * 4 + channel],
            ]..sort();
            expect(values.last - values.first, lessThan(8));
          }
        } finally {
          image.dispose();
        }
      });
    }
  });

  macTest('Mac catalog scrolls underneath the pinned glass toolbar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await fixtures.controller();
    for (var i = 0; i < 20; i++) {
      controller.database.put(
        Recipe(id: 'under-header-$i', title: 'Рецепт для прокрутки $i'),
        'fixture',
      );
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: RecipeVaultApp(controller: controller),
      ),
    );
    for (final width in [1380.0, 1000.0, 760.0]) {
      tester.view.physicalSize = Size(width, 880);
      await tester.pumpAndSettle();
      final toolbar = find.ancestor(
        of: find.text('Моя книга'),
        matching: find.byType(GlassPanel),
      );
      final viewport = find.byType(CustomScrollView);
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
      );
      scroll.position.jumpTo(0);
      await tester.pump();
      final fixedRect = tester.getRect(toolbar);
      expect(tester.getRect(viewport).top, fixedRect.top);
      final heading = find.text('Ваша книга рецептов');
      expect(tester.getRect(heading).top, greaterThan(fixedRect.bottom));
      scroll.position.jumpTo(64);
      await tester.pump();
      expect(tester.getRect(toolbar), fixedRect);
      expect(tester.getRect(heading).overlaps(fixedRect), isTrue);
      expect(
        find.descendant(of: toolbar, matching: find.byType(BackdropFilter)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (width == 1380) {
        scroll.position.jumpTo(400);
        await tester.pump();
        await fixtures.screenshot(tester, key, 'macos-scrolled');
      }
    }
  });

  macTest(
    'Mac import opens a dedicated view and focuses the composer at every width',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixtures.controller();
      controller.settings.localAi = false;
      await tester.pumpWidget(RecipeVaultApp(controller: controller));
      for (final width in [1380.0, 1000.0]) {
        tester.view.physicalSize = Size(width, 880);
        await tester.pumpAndSettle();
        final chatState = tester.state(
          find.byType(ChatScreen, skipOffstage: false),
        );
        await tester.tap(find.widgetWithText(ListTile, 'Импорт рецепта'));
        await tester.pumpAndSettle();
        expect(find.text('Ваша книга рецептов'), findsNothing);
        expect(find.text('Добавить рецепт'), findsOneWidget);
        final composer = tester.widget<TextField>(find.byType(TextField).last);
        expect(composer.focusNode!.hasFocus, isTrue);
        await tester.enterText(
          find.byType(TextField).last,
          'Черновик для $width',
        );
        expect(
          tester.getSize(find.byType(ChatScreen)).width,
          greaterThan(width - 300),
        );
        await tester.tap(find.widgetWithText(ListTile, 'Все рецепты'));
        await tester.pumpAndSettle();
        expect(find.text('Ваша книга рецептов'), findsOneWidget);
        expect(
          identical(
            chatState,
            tester.state(find.byType(ChatScreen, skipOffstage: false)),
          ),
          isTrue,
        );
        await tester.tap(find.widgetWithText(ListTile, 'Импорт рецепта'));
        await tester.pumpAndSettle();
        expect(find.text('Черновик для $width'), findsOneWidget);
        await tester.tap(find.widgetWithText(ListTile, 'Все рецепты'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  macTest(
    'Mac settings replace the previous page on the first frame in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(1380, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixtures.controller();
      await tester.pumpWidget(RecipeVaultApp(controller: controller));
      for (final mode in ['light', 'dark']) {
        controller.settings.theme = mode;
        controller.notifyListeners();
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Настройки'));
        // Do not settle: that would hide the reported flash during transitions.
        await tester.pump();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('Ваша книга рецептов'), findsNothing);
        final page =
            ModalRoute.of(tester.element(find.byType(SettingsScreen)))!
                as PageRoute;
        expect(page.animation!.status, AnimationStatus.completed);
        final entrance = find.byType(MacPageEntrance);
        final cover = tester.widget<ColoredBox>(
          find
              .descendant(of: entrance, matching: find.byType(ColoredBox))
              .first,
        );
        expect(cover.color.a, 1);
        expect(tester.getSize(entrance), const Size(1380, 842));
        final opacity = find
            .descendant(of: entrance, matching: find.byType(Opacity))
            .first;
        expect(tester.widget<Opacity>(opacity).opacity, 0);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
        expect(find.text('Ваша книга рецептов'), findsNothing);
        await tester.pumpAndSettle();
        final settledCover = tester.widget<ColoredBox>(
          find
              .descendant(of: entrance, matching: find.byType(ColoredBox))
              .first,
        );
        // The first-frame flash guard must not permanently hide native glass.
        expect(settledCover.color.a, 0);
        expect(find.text('Ваша книга рецептов'), findsNothing);
        Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
        await tester.pump();
        expect(find.byType(SettingsScreen), findsNothing);
        expect(find.text('Ваша книга рецептов'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
  macTest(
    'Mac pane expansion animates without losing drafts during reversals and resize',
    (tester) async {
      tester.view.physicalSize = const Size(1380, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixtures.controller();
      controller.settings.localAi = false;
      await tester.pumpWidget(RecipeVaultApp(controller: controller));
      await tester.pumpAndSettle();
      final chat = find.byType(ChatScreen);
      final state = tester.state(chat);
      await tester.enterText(
        find.byType(TextField).last,
        'Сохраните этот черновик',
      );
      final initial = tester.getSize(chat).width;
      await tester.tap(find.widgetWithText(ListTile, 'Импорт рецепта'));
      await tester.pump();
      expect(tester.getSize(chat).width, initial);
      await tester.pump(const Duration(milliseconds: 60));
      final intermediate = tester.getSize(chat).width;
      expect(intermediate, greaterThan(initial));
      expect(intermediate, lessThan(1126));
      // Reverse before the animation completes and resize while reversing.
      await tester.tap(find.widgetWithText(ListTile, 'Все рецепты'));
      await tester.pump(const Duration(milliseconds: 40));
      tester.view.physicalSize = const Size(1000, 880);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.widgetWithText(ListTile, 'Импорт рецепта'));
      await tester.pumpAndSettle();
      expect(identical(state, tester.state(chat)), isTrue);
      expect(find.text('Сохраните этот черновик'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Блюдо или ингредиент'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  macTest('Mac hover and press preserve the photo frame and button actions', (
    tester,
  ) async {
    final photo = base64Encode(
      img.encodePng(
        img.Image(width: 8, height: 8)..clear(img.ColorRgb8(220, 120, 60)),
      ),
    );
    var opened = 0, favorited = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: macTheme(ThemeData(platform: TargetPlatform.macOS)),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: RecipeCard(
                recipe: Recipe(
                  id: 'hover',
                  title: 'Карточка с фото',
                  photo: photo,
                ),
                onOpen: () => opened++,
                onFavorite: () => favorited++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final imageState = tester.state(find.byType(Image));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(RecipeCard)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      greaterThan(1),
    );
    await mouse.down(tester.getCenter(find.byType(RecipeCard)));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
    );
    await mouse.up();
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.tap(find.byTooltip('В избранное'));
    await tester.pumpAndSettle();
    expect(favorited, 1);
    expect(opened, 1);
    expect(
      identical(provider, tester.widget<Image>(find.byType(Image)).image),
      isTrue,
    );
    expect(identical(imageState, tester.state(find.byType(Image))), isTrue);
    expect(tester.takeException(), isNull);
  });

  macTest('Mac Reduce Motion applies live to panes, page entrances and hover', (
    tester,
  ) async {
    const channel = 'recipe_vault/appearance';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(channel),
          (call) async => {'reduceTransparency': false, 'reduceMotion': false},
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channel), null),
    );
    tester.view.physicalSize = const Size(1380, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await fixtures.controller();
    await tester.pumpWidget(RecipeVaultApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Импорт рецепта'));
    await tester.pump(const Duration(milliseconds: 30));
    tester.binding.channelBuffers.push(
      channel,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('accessibilityChanged', {
          'reduceTransparency': true,
          'reduceMotion': true,
        }),
      ),
      (_) {},
    );
    await tester.pump();
    await tester.pump();
    expect(
      MacGlassPreferences.motionReduced(
        tester.element(find.byType(ChatScreen)),
      ),
      isTrue,
    );
    expect(tester.getSize(find.byType(ChatScreen)).width, 1126);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Все рецепты'));
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(find.byType(ChatScreen)).width, 390);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).duration,
      Duration.zero,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Настройки'));
    await tester.pump();
    final opacity = find
        .descendant(
          of: find.byType(MacPageEntrance),
          matching: find.byType(Opacity),
        )
        .first;
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    expect(find.text('Ваша книга рецептов'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Mac motion leaves Android and Windows interfaces unchanged',
    (tester) async {
      final controller = await fixtures.controller();
      await tester.pumpWidget(RecipeVaultApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.byType(MacHoverFeedback), findsNothing);
      expect(find.byType(MacPaneVisibility), findsNothing);
      expect(find.byType(MacPageEntrance), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );
}
