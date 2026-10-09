import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/app_controller.dart';
import 'package:recipe_vault/services/storage.dart';
import 'yandex_webdav_test.dart' show FakeWebDav;

class MemoryCloudStorage extends LocalStorage {
  MemoryCloudStorage() : super(Directory.systemTemp);
  final values = <String, String>{};
  RecipeDatabase? saved;
  @override
  Future<void> saveSettings(AppSettings settings) async {}
  @override
  Future<void> saveDatabase(RecipeDatabase database) async {
    saved = database;
  }

  @override
  Future<String> secret(String key) async => values[key] ?? '';
  @override
  Future<void> setSecret(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test(
    'controller uses WebDAV without OAuth token and persists merged recipes',
    () async {
      final server = FakeWebDav(), storage = MemoryCloudStorage();
      server.files['/RecipeVault/.devices/windows.json'] =
          (RecipeDatabase()
                ..put(const Recipe(id: 'w', title: 'Чай'), 'windows'))
              .encode();
      final c = AppController(
        storage: storage,
        database: RecipeDatabase()
          ..put(const Recipe(id: 'a', title: 'Суп'), 'android'),
        settings: AppSettings(
          deviceId: 'android',
          autoSync: false,
          yandexLogin: 'test',
        ),
        syncClientFactory: () => server.client,
      );
      addTearDown(c.dispose);
      await c.updateSettings(c.settings, '', '', webDavSecret: 'app-password');
      await c.sync();
      expect(c.yandexToken, isEmpty);
      expect(c.syncFailed, false);
      expect(c.lastSynced, isNotNull);
      expect(c.syncMessage, 'Синхронизировано');
      expect(storage.saved!.recipes.map((r) => r.title).toSet(), {
        'Суп',
        'Чай',
      });
    },
  );
  test('check marks a forbidden connection and keeps local recipes', () async {
    final c = AppController(
      storage: MemoryCloudStorage(),
      database: RecipeDatabase()
        ..put(const Recipe(id: 'a', title: 'Суп'), 'android'),
      settings: AppSettings(
        deviceId: 'android',
        autoSync: false,
        yandexLogin: 'test',
      ),
      syncClientFactory: () => MockClient((_) async => http.Response('', 403)),
    );
    addTearDown(c.dispose);
    await c.updateSettings(c.settings, '', '', webDavSecret: 'app-password');
    await c.checkWebDavConnection();
    expect(c.syncFailed, true);
    expect(c.syncMessage, contains('Яндекс 360'));
    expect(c.recipes.single.title, 'Суп');
    expect(c.lastSynced, isNull);
    expect(c.syncing, false);
  });
}
