import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/app_controller.dart';
import 'package:recipe_vault/services/storage.dart';

class SettingsStorage extends LocalStorage {
  SettingsStorage() : super(Directory.systemTemp);
  Completer<void>? gate;
  AppSettings? persisted;
  int active = 0, peak = 0;
  bool failSecretOnce = false;
  final secretsWritten = <String, String>{};
  @override
  Future<String> secret(String key) async => secretsWritten[key] ?? '';
  @override
  Future<void> saveSettings(AppSettings settings) async {
    active++;
    if (active > peak) peak = active;
    await gate?.future;
    persisted = AppSettings.fromJson(settings.toJson());
    active--;
  }

  @override
  Future<void> setSecret(String key, String value) async {
    if (failSecretOnce) {
      failSecretOnce = false;
      throw const FileSystemException('no space');
    }
    secretsWritten[key] = value;
  }
}

void main() {
  test(
    'WebDAV password persists only in secure storage and retries after failure',
    () async {
      final storage = SettingsStorage()..failSecretOnce = true;
      final c = AppController(
        storage: storage,
        database: RecipeDatabase(),
        settings: AppSettings(deviceId: 'test', autoSync: false),
      );
      addTearDown(c.dispose);
      final next = AppSettings(
        deviceId: 'test',
        yandexLogin: 'test',
        autoSync: false,
      );
      await expectLater(
        c.updateSettings(next, '', '', webDavSecret: 'private-password'),
        throwsA(isA<FileSystemException>()),
      );
      expect(c.cloudConfigured, true);
      await c.updateSettings(next, '', '');
      expect(
        storage.secretsWritten['yandexWebDavPassword'],
        'private-password',
      );
      expect(
        storage.persisted!.toJson().toString().contains('private-password'),
        false,
      );
      expect(c.database.encode().contains('private-password'), false);
      await c.updateSettings(next, '', '', webDavSecret: '');
      expect(c.cloudConfigured, false);
      expect(storage.secretsWritten['yandexWebDavPassword'], '');
    },
  );
  test(
    'upgrading an unconfigured installation selects WebDAV and loads its password',
    () async {
      final storage = SettingsStorage()
        ..secretsWritten['yandexWebDavPassword'] = 'saved-password';
      final c = AppController(
        storage: storage,
        database: RecipeDatabase(),
        settings: AppSettings.fromJson({
          'deviceId': 'old-device',
          'autoSync': false,
        }),
      );
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.settings.syncMethod, 'webdav');
      expect(c.settings.deviceId, 'old-device');
      expect(c.webDavPassword, 'saved-password');
    },
  );
  test(
    'upgrading an existing OAuth connection retains the token and method',
    () async {
      final storage = SettingsStorage()
        ..secretsWritten['yandexToken'] = 'existing-token';
      final c = AppController(
        storage: storage,
        database: RecipeDatabase(),
        settings: AppSettings.fromJson({
          'deviceId': 'old-device',
          'autoSync': false,
        }),
      );
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.settings.syncMethod, 'oauth');
      expect(c.yandexToken, 'existing-token');
      expect(c.cloudConfigured, true);
      expect(storage.persisted!.syncMethod, 'oauth');
    },
  );
  test('appearance changes preserve the last synchronization error', () async {
    final storage = SettingsStorage();
    final c = AppController(
      storage: storage,
      database: RecipeDatabase(),
      settings: AppSettings(deviceId: 'test', autoSync: false),
    );
    addTearDown(c.dispose);
    c.syncMessage = 'Ошибка сети';
    c.syncFailed = true;
    await c.updateSettings(
      AppSettings(deviceId: 'test', accent: 'blue', autoSync: false),
      '',
      '',
    );
    expect(c.syncMessage, 'Ошибка сети');
    expect(c.syncFailed, true);
  });
  test(
    'live preferences update before disk and concurrent writes preserve latest values',
    () async {
      final storage = SettingsStorage()..gate = Completer<void>();
      final c = AppController(
        storage: storage,
        database: RecipeDatabase(),
        settings: AppSettings(deviceId: 'test', autoSync: false),
      );
      addTearDown(c.dispose);
      final first = c.updateSettings(
        AppSettings(deviceId: 'test', theme: 'dark', autoSync: false),
        '',
        '',
      );
      expect(c.settings.theme, 'dark');
      final second = c.updateSettings(
        AppSettings(
          deviceId: 'test',
          theme: 'light',
          accent: 'blue',
          autoSync: false,
        ),
        '',
        '',
      );
      expect(c.settings.theme, 'light');
      expect(c.settings.accent, 'blue');
      storage.gate!.complete();
      await Future.wait([first, second]);
      expect(storage.peak, 1);
      expect(storage.persisted!.theme, 'light');
      expect(storage.persisted!.accent, 'blue');
    },
  );
  test(
    'failed secure write is retried by next change with the same token',
    () async {
      final storage = SettingsStorage()..failSecretOnce = true;
      final c = AppController(
        storage: storage,
        database: RecipeDatabase(),
        settings: AppSettings(deviceId: 'test', autoSync: false),
      );
      addTearDown(c.dispose);
      await expectLater(
        c.updateSettings(
          AppSettings(deviceId: 'test', autoSync: false),
          'private-token',
          '',
        ),
        throwsA(isA<FileSystemException>()),
      );
      await c.updateSettings(
        AppSettings(deviceId: 'test', accent: 'rose', autoSync: false),
        'private-token',
        '',
      );
      expect(storage.secretsWritten['yandexToken'], 'private-token');
      expect(storage.persisted!.accent, 'rose');
    },
  );
  test(
    'old preferences preserve device identity and default to device colors',
    () {
      final settings = AppSettings.fromJson({
        'deviceId': 'existing',
        'theme': 'dark',
      });
      expect(settings.deviceId, 'existing');
      expect(settings.accent, 'system');
      expect(settings.theme, 'dark');
    },
  );
}
