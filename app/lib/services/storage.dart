import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/recipe.dart';

class AppSettings {
  final String deviceId;
  String server,
      cloudFolder,
      theme,
      accent,
      yandexClientId,
      syncMethod,
      yandexLogin;
  bool autoSync, localAi;
  AppSettings({
    required this.deviceId,
    this.server = '',
    this.cloudFolder = '/RecipeVault',
    this.theme = 'system',
    this.accent = 'system',
    this.yandexClientId = const String.fromEnvironment('YANDEX_CLIENT_ID'),
    this.syncMethod = 'webdav',
    this.yandexLogin = '',
    this.autoSync = true,
    this.localAi = true,
  });
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    deviceId: j['deviceId'] as String? ?? const Uuid().v4(),
    server: j['server'] as String? ?? '',
    cloudFolder: j['cloudFolder'] as String? ?? '/RecipeVault',
    theme: j['theme'] as String? ?? 'system',
    accent: j['accent'] as String? ?? 'system',
    yandexClientId:
        j['yandexClientId'] as String? ??
        const String.fromEnvironment('YANDEX_CLIENT_ID'),
    syncMethod: j['syncMethod'] == 'webdav' ? 'webdav' : 'oauth',
    yandexLogin: j['yandexLogin'] as String? ?? '',
    autoSync: j['autoSync'] as bool? ?? true,
    localAi: j['localAi'] as bool? ?? true,
  );
  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'server': server,
    'cloudFolder': cloudFolder,
    'theme': theme,
    'accent': accent,
    'yandexClientId': yandexClientId,
    'syncMethod': syncMethod,
    'yandexLogin': yandexLogin,
    'autoSync': autoSync,
    'localAi': localAi,
  };
}

Future<void> atomicWrite(File file, String data) async {
  await file.parent.create(recursive: true);
  final pending = File('${file.path}.pending');
  final backup = File('${file.path}.bak');
  await pending.writeAsString(data, flush: true);
  if (await file.exists()) {
    if (await backup.exists()) await backup.delete();
    await file.rename(backup.path);
  }
  await pending.rename(file.path);
}

class LocalStorage {
  final Directory directory;
  final FlutterSecureStorage secrets;
  LocalStorage(this.directory, {FlutterSecureStorage? secrets})
    : secrets =
          secrets ??
          const FlutterSecureStorage(
            // The login Keychain supports personal Mac builds without a paid
            // signing identity. Passwords still stay encrypted outside the JSON.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  static Future<LocalStorage> open() async => LocalStorage(
    Directory(
      p.join((await getApplicationSupportDirectory()).path, 'RecipeVault'),
    ),
  );
  File get databaseFile => File(p.join(directory.path, 'recipes.json'));
  File get settingsFile => File(p.join(directory.path, 'settings.json'));

  Future<RecipeDatabase> loadDatabase() async {
    final mainExists = await databaseFile.exists();
    Object? error;
    for (final suffix in ['', '.pending', '.bak']) {
      final file = File('${databaseFile.path}$suffix');
      if (await file.exists()) {
        try {
          return RecipeDatabase.decode(await file.readAsString());
        } catch (e) {
          error = e;
        }
      }
    }
    if (mainExists || error != null) {
      throw FormatException(
        'Не удалось прочитать базу. Файлы сохранены для восстановления: $error',
      );
    }
    return RecipeDatabase();
  }

  Future<void> saveDatabase(RecipeDatabase database) =>
      atomicWrite(databaseFile, database.encode());
  Future<AppSettings> loadSettings() async {
    for (final suffix in ['', '.pending', '.bak']) {
      final file = File('${settingsFile.path}$suffix');
      if (await file.exists()) {
        try {
          return AppSettings.fromJson(
            jsonDecode(await file.readAsString()) as Map<String, dynamic>,
          );
        } catch (_) {
          /* Try a complete backup before assigning a new device identity. */
        }
      }
    }
    return AppSettings(deviceId: const Uuid().v4());
  }

  Future<void> saveSettings(AppSettings settings) =>
      atomicWrite(settingsFile, jsonEncode(settings.toJson()));
  Future<String> secret(String key) async => await secrets.read(key: key) ?? '';
  Future<void> setSecret(String key, String value) async {
    if (value.trim().isEmpty) {
      await secrets.delete(key: key);
    } else {
      await secrets.write(key: key, value: value.trim());
    }
  }
}
