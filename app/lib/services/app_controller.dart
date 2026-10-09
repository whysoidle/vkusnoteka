import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';
import 'storage.dart';
import 'yandex_sync.dart';
import 'yandex_auth.dart';
import 'yandex_webdav.dart';

class AppController extends ChangeNotifier {
  final LocalStorage storage;
  final http.Client Function()? syncClientFactory;
  RecipeDatabase database;
  AppSettings settings;
  String yandexToken = '',
      webDavPassword = '',
      importToken = '',
      syncMessage = '';
  bool syncing = false;
  DateTime? lastSynced, _yandexExpires;
  String _yandexRefresh = '';
  bool syncFailed = false;
  bool _disposed = false;
  http.Client? _activeSyncClient;
  YandexAuth? _activeAuth;
  String _storedDiskToken = '', _storedImportToken = '';
  String _storedWebDavPassword = '';
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Timer? _debounce, _periodic;
  Future<void> _writes = Future.value();
  Future<void> _settingsWrites = Future.value();
  AppController({
    required this.storage,
    required this.database,
    required this.settings,
    this.syncClientFactory,
  });
  Future<void> initialize() async {
    yandexToken = await storage.secret('yandexToken');
    importToken = await storage.secret('importToken');
    webDavPassword = await storage.secret('yandexWebDavPassword');
    _storedWebDavPassword = webDavPassword;
    if (settings.syncMethod == 'oauth' &&
        yandexToken.isEmpty &&
        settings.yandexClientId.isEmpty) {
      settings.syncMethod = 'webdav';
    }
    _storedDiskToken = yandexToken;
    _storedImportToken = importToken;
    _yandexRefresh = await storage.secret('yandexRefresh');
    _yandexExpires = DateTime.tryParse(await storage.secret('yandexExpires'));
    await storage.saveSettings(settings);
    _periodic?.cancel();
    if (!_disposed) {
      _periodic = Timer.periodic(const Duration(minutes: 3), (_) => autoSync());
    }
  }

  List<Recipe> get recipes => database.recipes;
  Future<void> _serialize(Future<void> Function() operation) {
    final next = _writes.then((_) => operation());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> save(Recipe recipe) => _serialize(() async {
    final next = RecipeDatabase(database.records)
      ..put(recipe, settings.deviceId);
    await storage.saveDatabase(next);
    database = next;
    notifyListeners();
    autoSync();
  });
  Future<void> remove(Recipe recipe) => _serialize(() async {
    final next = RecipeDatabase(database.records)
      ..remove(recipe.id, settings.deviceId);
    await storage.saveDatabase(next);
    database = next;
    notifyListeners();
    autoSync();
  });
  Future<void> merge(RecipeDatabase imported) => _serialize(() async {
    final next = mergeDatabases(database, imported);
    await storage.saveDatabase(next);
    database = next;
    notifyListeners();
    autoSync();
  });
  Future<void> updateSettings(
    AppSettings next,
    String diskToken,
    String apiToken, {
    String? webDavSecret,
  }) {
    final nextPassword = (webDavSecret ?? webDavPassword).trim();
    final oldDiskToken = yandexToken;
    final connectionChanged =
        diskToken.trim() != yandexToken ||
        next.cloudFolder != settings.cloudFolder ||
        next.yandexClientId != settings.yandexClientId ||
        next.syncMethod != settings.syncMethod ||
        next.yandexLogin != settings.yandexLogin ||
        nextPassword != webDavPassword;
    settings = next;
    if (diskToken.trim() != oldDiskToken) {
      _yandexRefresh = '';
      _yandexExpires = null;
    }
    yandexToken = diskToken.trim();
    importToken = apiToken.trim();
    webDavPassword = nextPassword;
    if (connectionChanged) {
      syncMessage = '';
      syncFailed = false;
      lastSynced = null;
    }
    notifyListeners();
    final operation = _settingsWrites.then((_) async {
      if (diskToken.trim() != _storedDiskToken) {
        await storage.setSecret('yandexToken', diskToken);
        await storage.setSecret('yandexRefresh', '');
        await storage.setSecret('yandexExpires', '');
        _storedDiskToken = diskToken.trim();
      }
      if (apiToken.trim() != _storedImportToken) {
        await storage.setSecret('importToken', apiToken);
        _storedImportToken = apiToken.trim();
      }
      if (nextPassword != _storedWebDavPassword) {
        await storage.setSecret('yandexWebDavPassword', nextPassword);
        _storedWebDavPassword = nextPassword;
      }
      await storage.saveSettings(next);
    });
    _settingsWrites = operation.catchError((Object _) {});
    autoSync();
    return operation;
  }

  Future<void> connectYandex(YandexTokens tokens) async {
    await updateSettings(settings, tokens.accessToken, importToken);
    await storage.setSecret('yandexRefresh', tokens.refreshToken);
    await storage.setSecret(
      'yandexExpires',
      tokens.expiresAt.toIso8601String(),
    );
    _yandexRefresh = tokens.refreshToken;
    _yandexExpires = tokens.expiresAt;
  }

  Future<void> _refreshYandexIfNeeded() async {
    if (_yandexRefresh.isEmpty ||
        _yandexExpires == null ||
        _yandexExpires!.isAfter(
          DateTime.now().add(const Duration(minutes: 2)),
        )) {
      return;
    }
    final auth = YandexAuth();
    _activeAuth = auth;
    try {
      final tokens = await auth.refresh(
        settings.yandexClientId,
        _yandexRefresh,
      );
      if (!_disposed) await connectYandex(tokens);
    } finally {
      if (identical(_activeAuth, auth)) _activeAuth = null;
      auth.close();
    }
  }

  void autoSync() {
    _debounce?.cancel();
    if (_disposed || !settings.autoSync || !cloudConfigured) return;
    _debounce = Timer(const Duration(seconds: 3), sync);
  }

  bool get cloudConfigured => settings.syncMethod == 'webdav'
      ? settings.yandexLogin.trim().isNotEmpty && webDavPassword.isNotEmpty
      : yandexToken.isNotEmpty;

  RecipeCloudStore cloudStore() => settings.syncMethod == 'webdav'
      ? YandexWebDav(
          login: settings.yandexLogin,
          password: webDavPassword,
          folder: settings.cloudFolder,
          client: syncClientFactory?.call(),
        )
      : YandexDisk(
          token: yandexToken,
          folder: settings.cloudFolder,
          client: syncClientFactory?.call(),
        );

  Future<void> checkWebDavConnection() async {
    if (_disposed || syncing) return;
    _debounce?.cancel();
    syncing = true;
    syncFailed = false;
    syncMessage = 'Проверка подключения…';
    notifyListeners();
    YandexWebDav? disk;
    try {
      await _settingsWrites;
      if (_disposed) return;
      disk = YandexWebDav(
        login: settings.yandexLogin,
        password: webDavPassword,
        folder: settings.cloudFolder,
        client: syncClientFactory?.call(),
      );
      _activeSyncClient = disk.client;
      await disk.checkConnection();
      syncMessage = 'Доступ к Яндекс Диску подтверждён';
    } catch (e) {
      syncFailed = true;
      syncMessage = e is SyncException
          ? e.message
          : 'Не удалось проверить подключение. Проверьте интернет и повторите.';
    } finally {
      if (identical(_activeSyncClient, disk?.client)) _activeSyncClient = null;
      disk?.client.close();
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (_disposed || syncing) return;
    if (!cloudConfigured) {
      syncFailed = true;
      syncMessage = 'Подключите Яндекс Диск в настройках';
      notifyListeners();
      return;
    }
    syncing = true;
    syncFailed = false;
    syncMessage = '';
    notifyListeners();
    RecipeCloudStore? disk;
    try {
      await _settingsWrites;
      if (_disposed) return;
      if (settings.syncMethod == 'oauth') await _refreshYandexIfNeeded();
      if (_disposed) return;
      disk = cloudStore();
      _activeSyncClient = disk.client;
      await _writes;
      if (_disposed) return;
      final snapshot = RecipeDatabase(database.records);
      final remote = await disk.sync(snapshot, settings.deviceId);
      if (_disposed) return;
      await _serialize(() async {
        if (_disposed) return;
        final next = mergeDatabases(database, remote);
        await storage.saveDatabase(next);
        database = next;
      });
      lastSynced = DateTime.now();
      syncMessage = 'Синхронизировано';
      if (database.encode() != remote.encode()) autoSync();
    } catch (e) {
      syncFailed = true;
      syncMessage = e is YandexAuthException
          ? e.message
          : e is SyncException
          ? e.message
          : 'Синхронизация не завершена. Повторите позже. Локальные рецепты сохранены.';
    } finally {
      if (identical(_activeSyncClient, disk?.client)) _activeSyncClient = null;
      disk?.client.close();
      syncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _periodic?.cancel();
    _activeSyncClient?.close();
    _activeSyncClient = null;
    _activeAuth?.close();
    _activeAuth = null;
    super.dispose();
  }
}
