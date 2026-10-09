import 'dart:io';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:recipe_vault/main.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/screens/cooking.dart';
import 'package:recipe_vault/screens/detail.dart';
import 'package:recipe_vault/screens/editor.dart';
import 'package:recipe_vault/screens/document_import.dart';
import 'package:recipe_vault/screens/settings.dart';
import 'package:recipe_vault/services/app_controller.dart';
import 'package:recipe_vault/services/storage.dart';
import 'ui_test.dart' show samples;

class MemoryStorage extends LocalStorage {
  MemoryStorage() : super(Directory.systemTemp);
  @override
  Future<void> saveSettings(AppSettings settings) async {}
  @override
  Future<void> setSecret(String key, String value) async {}
}

class VmHttpOverrides extends HttpOverrides {}

Future<void> exerciseApp(
  WidgetTester tester,
  List<WeakReference<Object>> references,
) async {
  final controller = AppController(
    storage: MemoryStorage(),
    settings: AppSettings(deviceId: 'fixture', autoSync: false, localAi: false),
    database: RecipeDatabase()..put(samples.first, 'fixture'),
  );
  references.add(WeakReference(controller));
  try {
    for (
      var cycle = 0;
      cycle < const int.fromEnvironment('MEMORY_TEST_CYCLES', defaultValue: 10);
      cycle++
    ) {
      await tester.pumpWidget(RecipeVaultApp(controller: controller));
      if (cycle == 0) {
        // Native asset decoding is asynchronous and pumpAndSettle does not
        // wait for it. Finish decoding with listeners attached before unmount.
        await tester.runAsync(() async {
          final context = tester.element(find.byType(RecipeVaultApp));
          await Future.wait(
            tester
                .widgetList<Image>(find.byType(Image))
                .map((image) => precacheImage(image.image, context)),
          );
        });
      }
      await tester.pumpAndSettle();
      final navigator = Navigator.of(
        tester.element(find.byType(Scaffold).first),
      );
      for (final page in <Widget>[
        SettingsScreen(controller: controller),
        RecipeEditor(recipe: samples.first),
        RecipeDetail(recipe: samples.first, controller: controller),
        const DocumentImportScreen(),
        CookingScreen(recipe: samples.first),
      ]) {
        navigator.push(MaterialPageRoute<void>(builder: (_) => page));
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
    // Static branding artwork deliberately lives in Flutter's global cache.
    // Release the test-owned cache after unmounting, before leak reporting.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.pump();
  }
}

Future<void> collectAndCheck(
  WidgetTester tester,
  List<WeakReference<Object>> references,
) async {
  final service = await tester.runAsync(() async {
    final uri = (await developer.Service.getInfo()).serverUri;
    if (uri == null) return null;
    return HttpOverrides.runWithHttpOverrides(
      () => vmServiceConnectUri(
        uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
      ),
      VmHttpOverrides(),
    );
  });
  if (service == null) return;
  try {
    final isolateId = developer.Service.getIsolateId(Isolate.current)!;
    for (var attempt = 0; attempt < 5; attempt++) {
      // Platform replies and finalizers can queue microtasks in FakeAsync while
      // the real VM service runs. Drain that zone between full GC requests.
      await tester.pump();
      await tester.runAsync(() async {
        await service.getAllocationProfile(isolateId, gc: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    }
    await tester.pump();
    final retained = <String, int>{};
    for (final reference in references) {
      final object = reference.target;
      if (object != null) {
        final type = object.runtimeType.toString();
        retained[type] = (retained[type] ?? 0) + 1;
      }
    }
    expect(
      retained,
      isEmpty,
      reason: 'Disposed application controllers remain reachable after full GC',
    );
    debugPrint(
      'GC verified: ${references.length} controller weak references released',
    );
  } finally {
    await tester.runAsync(service.dispose);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.hasStrings') return {'value': false};
        if (call.method == 'Clipboard.getData') return {'text': ''};
        return null;
      });
  LeakTesting.enable();
  LeakTesting.settings = LeakTesting.settings
      .withCreationStackTrace()
      .withDisposalStackTrace();

  testWidgets(
    'repeated screen and app lifecycles release Flutter objects',
    (tester) async {
      tester.view.physicalSize = const Size(1380, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final references = <WeakReference<Object>>[];
      void allocation(ObjectEvent event) {
        if (event is ObjectCreated &&
            (event.object is TextEditingController ||
                event.object is ScrollController ||
                event.object is AnimationController)) {
          references.add(WeakReference(event.object));
        }
      }

      FlutterMemoryAllocations.instance.addListener(allocation);
      try {
        await exerciseApp(tester, references);
      } finally {
        FlutterMemoryAllocations.instance.removeListener(allocation);
      }
      expect(references.length, greaterThan(100));
      await collectAndCheck(tester, references);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );
}
