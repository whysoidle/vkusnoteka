import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/main.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/app_controller.dart';
import 'package:recipe_vault/services/storage.dart';
import 'webdav_controller_test.dart' show MemoryCloudStorage;
import 'yandex_webdav_test.dart' show FakeWebDav;

void main() {
  testWidgets(
    'WebDAV credentials autosave, check connection and disconnect without OAuth',
    (tester) async {
      tester.view.physicalSize = const Size(430, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryCloudStorage(), server = FakeWebDav();
      final c = AppController(
        storage: storage,
        database: RecipeDatabase(),
        settings: AppSettings(deviceId: 'test', autoSync: false),
        syncClientFactory: () => server.client,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(RecipeVaultApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      final login = find.byKey(const ValueKey('webdav-login'));
      final password = find.byKey(const ValueKey('webdav-password'));
      await tester.scrollUntilVisible(login, 200, scrollable: scrollable);
      await tester.enterText(login, 'test');
      await tester.scrollUntilVisible(password, 150, scrollable: scrollable);
      await tester.enterText(password, 'app-password');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(c.settings.yandexLogin, 'test');
      expect(c.cloudConfigured, true);
      expect(storage.values['yandexWebDavPassword'], 'app-password');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: password,
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        true,
      );
      expect(find.text('Публичный Client ID Яндекс OAuth'), findsNothing);
      expect(find.text('Сохранить настройки'), findsNothing);
      final check = find.byKey(const ValueKey('webdav-check'));
      await tester.scrollUntilVisible(check, 100, scrollable: scrollable);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(c.syncMessage, 'Доступ к Яндекс Диску подтверждён');
      expect(c.syncFailed, false);
      expect(server.files, isEmpty);
      await tester.scrollUntilVisible(
        find.text('Отключить Диск'),
        120,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Отключить Диск'));
      await tester.pumpAndSettle();
      expect(c.cloudConfigured, false);
      expect(storage.values['yandexWebDavPassword'], '');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'leaving settings before debounce persists the entered password',
    (tester) async {
      final storage = MemoryCloudStorage();
      final c = AppController(
        storage: storage,
        database: RecipeDatabase(),
        settings: AppSettings(deviceId: 'test', autoSync: false),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(RecipeVaultApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('webdav-password')),
        200,
        scrollable: scrollable,
      );
      await tester.enterText(
        find.byKey(const ValueKey('webdav-password')),
        'new-password',
      );
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(storage.values['yandexWebDavPassword'], 'new-password');
      expect(tester.takeException(), isNull);
    },
  );
}
